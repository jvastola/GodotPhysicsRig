class_name PlayerMovementComponent
extends Node

# Turning settings
enum TurnMode { SNAP, SMOOTH }
@export var turn_mode: TurnMode = TurnMode.SNAP
@export var snap_turn_angle: float = 45.0  # Degrees per snap turn
@export var smooth_turn_speed: float = 90.0  # Degrees per second
@export var turn_deadzone: float = 0.5  # Thumbstick deadzone for turning
@export var snap_turn_cooldown: float = 0.3  # Seconds between snap turns

# Turning state
var can_snap_turn := true
var snap_turn_timer := 0.0
var _pending_snap_angle := 0.0
var _smooth_input := 0.0

var player_body: RigidBody3D
var right_controller: XRController3D
var is_vr_mode: bool = false

func setup(p_player_body: RigidBody3D, p_right_controller: XRController3D) -> void:
	player_body = p_player_body
	right_controller = p_right_controller

func set_vr_mode(enabled: bool) -> void:
	is_vr_mode = enabled

func process_turning(delta: float) -> void:
	if not is_vr_mode:
		return
		
	_handle_turning(delta)

func physics_process_turning(delta: float) -> void:
	# Apply any pending rotation to the physics body during the physics step
	if player_body:
		# Apply snap rotation if pending
		if abs(_pending_snap_angle) > 0.001:
			var lv = player_body.linear_velocity
			var av = player_body.angular_velocity
			player_body.rotate_y(deg_to_rad(_pending_snap_angle))
			# restore linear velocity so rotation doesn't alter falling
			player_body.linear_velocity = lv
			# restore angular velocity as well (avoid changing spin during rotation)
			player_body.angular_velocity = av
			# clear pending
			_pending_snap_angle = 0.0

		# Apply smooth rotation based on input
		if abs(_smooth_input) > 0.001:
			var turn_amount = -_smooth_input * smooth_turn_speed * delta
			var lv2 = player_body.linear_velocity
			player_body.rotate_y(deg_to_rad(turn_amount))
			player_body.linear_velocity = lv2

func _handle_turning(delta: float) -> void:
	"""Handle VR turning input from right controller thumbstick"""
	if not right_controller:
		return
	
	# Update snap turn cooldown
	if snap_turn_timer > 0:
		snap_turn_timer -= delta
		if snap_turn_timer <= 0:
			can_snap_turn = true
	
	# Get thumbstick input for turning (horizontal axis)
	var turn_input = right_controller.get_vector2("primary")
	
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

func _handle_snap_turn(input: float) -> void:
	"""Handle snap turning"""
	if not can_snap_turn:
		return
	
	# Determine turn direction
	# Invert sign so pushing the thumbstick right (positive x) turns right
	var turn_angle = -snap_turn_angle if input > 0 else snap_turn_angle

	# Queue the snap rotation to be applied in physics step
	_pending_snap_angle = turn_angle

	# Start cooldown
	can_snap_turn = false
	snap_turn_timer = snap_turn_cooldown

	print("PlayerMovementComponent: Queued snap turn ", turn_angle, " degrees")

func _handle_smooth_turn(input: float, _delta: float) -> void:
	"""Handle smooth turning"""
	# Store smooth input for physics step to apply
	_smooth_input = input
