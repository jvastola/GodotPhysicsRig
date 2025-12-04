class_name PlayerMovementComponent
extends Node
## Handles VR turning and joystick locomotion

# === Locomotion Settings ===
enum LocomotionMode { DISABLED, HEAD_DIRECTION, HAND_DIRECTION }
@export var locomotion_mode: LocomotionMode = LocomotionMode.DISABLED
@export var locomotion_speed: float = 3.0  # m/s
@export var locomotion_deadzone: float = 0.2

# === Turning Settings ===
enum TurnMode { SNAP, SMOOTH }
@export var turn_mode: TurnMode = TurnMode.SNAP
@export var snap_turn_angle: float = 45.0  # Degrees per snap turn
@export var smooth_turn_speed: float = 90.0  # Degrees per second
@export var turn_deadzone: float = 0.5  # Thumbstick deadzone for turning
@export var snap_turn_cooldown: float = 0.3  # Seconds between snap turns

# === Hand Assignment ===
enum HandAssignment { DEFAULT, SWAPPED }
@export var hand_assignment: HandAssignment = HandAssignment.DEFAULT

# Turning state
var can_snap_turn := true
var snap_turn_timer := 0.0
var _pending_snap_angle := 0.0
var _smooth_input := 0.0

# References
var player_body: RigidBody3D
var left_controller: XRController3D
var right_controller: XRController3D
var xr_camera: XRCamera3D
var is_vr_mode: bool = false

# Computed controller references (based on hand assignment)
var locomotion_controller: XRController3D:
	get:
		if hand_assignment == HandAssignment.SWAPPED:
			return right_controller
		return left_controller

var turn_controller: XRController3D:
	get:
		if hand_assignment == HandAssignment.SWAPPED:
			return left_controller
		return right_controller


func setup(p_player_body: RigidBody3D, p_left_controller: XRController3D, p_right_controller: XRController3D, p_xr_camera: XRCamera3D = null) -> void:
	player_body = p_player_body
	left_controller = p_left_controller
	right_controller = p_right_controller
	xr_camera = p_xr_camera
	print("PlayerMovementComponent: Setup with both controllers")


func set_vr_mode(enabled: bool) -> void:
	is_vr_mode = enabled


func swap_hands() -> void:
	"""Toggle hand assignment between default and swapped"""
	if hand_assignment == HandAssignment.DEFAULT:
		hand_assignment = HandAssignment.SWAPPED
		print("PlayerMovementComponent: Hands swapped - Move:Right, Turn:Left")
	else:
		hand_assignment = HandAssignment.DEFAULT
		print("PlayerMovementComponent: Hands default - Move:Left, Turn:Right")


func process_turning(delta: float) -> void:
	if not is_vr_mode:
		return
	_handle_turning(delta)


func process_locomotion(delta: float) -> void:
	if not is_vr_mode or locomotion_mode == LocomotionMode.DISABLED:
		return
	_handle_locomotion(delta)


func physics_process_turning(delta: float) -> void:
	# Apply any pending rotation to the physics body during the physics step
	if player_body:
		# Apply snap rotation if pending
		if abs(_pending_snap_angle) > 0.001:
			var lv = player_body.linear_velocity
			var av = player_body.angular_velocity
			player_body.rotate_y(deg_to_rad(_pending_snap_angle))
			player_body.linear_velocity = lv
			player_body.angular_velocity = av
			_pending_snap_angle = 0.0

		# Apply smooth rotation based on input
		if abs(_smooth_input) > 0.001:
			var turn_amount = -_smooth_input * smooth_turn_speed * delta
			var lv2 = player_body.linear_velocity
			player_body.rotate_y(deg_to_rad(turn_amount))
			player_body.linear_velocity = lv2


func physics_process_locomotion(_delta: float) -> void:
	"""Apply locomotion forces in physics step"""
	if not is_vr_mode or locomotion_mode == LocomotionMode.DISABLED:
		return
	if not player_body or not locomotion_controller:
		return
	
	# Get thumbstick input
	var input = locomotion_controller.get_vector2("primary")
	
	if input.length() < locomotion_deadzone:
		return
	
	# Get movement direction based on mode
	var move_direction = _get_movement_direction(input)
	
	if move_direction.length() < 0.01:
		return
	
	# Apply movement force (similar to desktop controller)
	var target_velocity = move_direction * locomotion_speed
	var current_horizontal = Vector3(player_body.linear_velocity.x, 0, player_body.linear_velocity.z)
	var velocity_change = target_velocity - current_horizontal
	
	# Apply force to reach target velocity
	player_body.apply_central_force(velocity_change * player_body.mass * 10.0)


func _get_movement_direction(input: Vector2) -> Vector3:
	"""Get world-space movement direction based on locomotion mode"""
	var forward: Vector3
	var right: Vector3
	
	if locomotion_mode == LocomotionMode.HEAD_DIRECTION:
		# Movement relative to head/camera direction
		if xr_camera:
			forward = -xr_camera.global_transform.basis.z
			right = xr_camera.global_transform.basis.x
		elif player_body:
			forward = -player_body.global_transform.basis.z
			right = player_body.global_transform.basis.x
		else:
			return Vector3.ZERO
	else:  # HAND_DIRECTION
		# Movement relative to locomotion controller direction
		if locomotion_controller:
			forward = -locomotion_controller.global_transform.basis.z
			right = locomotion_controller.global_transform.basis.x
		else:
			return Vector3.ZERO
	
	# Keep movement on horizontal plane
	forward.y = 0
	right.y = 0
	forward = forward.normalized()
	right = right.normalized()
	
	# Combine input with directions
	# Thumbstick: Y is forward/back, X is left/right
	return (forward * -input.y + right * input.x).normalized()


func _handle_turning(delta: float) -> void:
	"""Handle VR turning input from turn controller thumbstick"""
	if not turn_controller:
		return
	
	# Update snap turn cooldown
	if snap_turn_timer > 0:
		snap_turn_timer -= delta
		if snap_turn_timer <= 0:
			can_snap_turn = true
	
	# Get thumbstick input for turning (horizontal axis)
	var turn_input = turn_controller.get_vector2("primary")
	
	if abs(turn_input.x) > turn_deadzone:
		if turn_mode == TurnMode.SNAP:
			_handle_snap_turn(turn_input.x)
		else:  # SMOOTH
			_handle_smooth_turn(turn_input.x, delta)
	else:
		# Reset snap turn when thumbstick returns to center
		if turn_mode == TurnMode.SNAP and snap_turn_timer <= 0:
			can_snap_turn = true
		# Clear smooth input when centered
		_smooth_input = 0.0


func _handle_locomotion(_delta: float) -> void:
	"""Process locomotion input (actual movement applied in physics_process)"""
	# Movement is handled in physics_process_locomotion
	pass


func _handle_snap_turn(input: float) -> void:
	"""Handle snap turning"""
	if not can_snap_turn:
		return
	
	# Determine turn direction
	var turn_angle = -snap_turn_angle if input > 0 else snap_turn_angle
	
	# Queue the snap rotation to be applied in physics step
	_pending_snap_angle = turn_angle
	
	# Start cooldown
	can_snap_turn = false
	snap_turn_timer = snap_turn_cooldown


func _handle_smooth_turn(input: float, _delta: float) -> void:
	"""Handle smooth turning"""
	_smooth_input = input
