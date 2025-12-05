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

# === World Grab / Utility Settings ===
@export var enable_two_hand_world_scale: bool = false
@export var enable_two_hand_world_rotation: bool = false
@export_range(0.05, 5.0, 0.05) var world_scale_min: float = 0.25
@export_range(0.1, 10.0, 0.05) var world_scale_max: float = 3.0
@export var player_gravity_enabled: bool = true

# Turning state
var can_snap_turn := true
var snap_turn_timer := 0.0
var _pending_snap_angle := 0.0
var _smooth_input := 0.0

# Two-hand world grab state
var _world_grab_active := false
var _world_grab_initial_distance := 0.0
var _world_grab_initial_scale := 1.0
var _world_grab_initial_vector := Vector3.ZERO
var _world_grab_initial_body_basis := Basis.IDENTITY

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
	_apply_player_gravity()
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

	# Handle two-hand world manipulation (rotation/scale) in the physics step
	if is_vr_mode:
		physics_process_world_grab(delta)


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
	# Thumbstick: Y positive = forward, Y negative = back, X positive = right, X negative = left
	return (forward * input.y + right * input.x).normalized()


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


# === World Grab Helpers ===

func physics_process_world_grab(_delta: float) -> void:
	"""Allow two-hand grab gestures to scale/rotate the world."""
	if not (enable_two_hand_world_scale or enable_two_hand_world_rotation):
		_end_world_grab()
		return
	if not left_controller or not right_controller or not player_body:
		_end_world_grab()
		return

	var left_pressed := _is_grip_pressed(left_controller)
	var right_pressed := _is_grip_pressed(right_controller)

	if left_pressed and right_pressed:
		if not _world_grab_active:
			_start_world_grab()
		_update_world_grab()
	else:
		_end_world_grab()


func _is_grip_pressed(controller: XRController3D) -> bool:
	if not controller:
		return false
	if controller.has_method("get_float"):
		var grip_val := controller.get_float("grip")
		# Some action maps expose grip_click instead of grip
		grip_val = max(grip_val, controller.get_float("grip_click"))
		return grip_val > 0.75
	return false


func _start_world_grab() -> void:
	_world_grab_active = true
	_world_grab_initial_distance = max(0.01, left_controller.global_position.distance_to(right_controller.global_position))
	_world_grab_initial_scale = XRServer.world_scale
	_world_grab_initial_vector = right_controller.global_position - left_controller.global_position
	_world_grab_initial_body_basis = player_body.global_transform.basis


func _update_world_grab() -> void:
	if not _world_grab_active:
		return

	var current_vector: Vector3 = right_controller.global_position - left_controller.global_position
	var current_distance := max(0.01, left_controller.global_position.distance_to(right_controller.global_position))

	if enable_two_hand_world_scale and _world_grab_initial_distance > 0.01:
		var target_scale := clampf(
			_world_grab_initial_scale * (current_distance / _world_grab_initial_distance),
			world_scale_min,
			world_scale_max
		)
		if abs(target_scale - XRServer.world_scale) > 0.001:
			XRServer.world_scale = target_scale

	if enable_two_hand_world_rotation:
		var initial_2d := Vector2(_world_grab_initial_vector.x, _world_grab_initial_vector.z)
		var current_2d := Vector2(current_vector.x, current_vector.z)
		if initial_2d.length_squared() > 0.0001 and current_2d.length_squared() > 0.0001:
			var angle_delta := initial_2d.angle_to(current_2d)
			var lv = player_body.linear_velocity
			var av = player_body.angular_velocity
			player_body.global_transform = Transform3D(
				Basis(Vector3.UP, angle_delta) * _world_grab_initial_body_basis,
				player_body.global_transform.origin
			)
			player_body.linear_velocity = lv
			player_body.angular_velocity = av


func _end_world_grab() -> void:
	_world_grab_active = false


func set_player_gravity_enabled(enabled: bool) -> void:
	player_gravity_enabled = enabled
	_apply_player_gravity()


func _apply_player_gravity() -> void:
	if player_body:
		player_body.gravity_scale = 1.0 if player_gravity_enabled else 0.0
