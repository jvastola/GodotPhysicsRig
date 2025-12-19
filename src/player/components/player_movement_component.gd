class_name PlayerMovementComponent
extends Node
## Handles VR turning and joystick locomotion

const InputBindingManager = preload("res://src/systems/input_binding_manager.gd")

# === Locomotion Settings ===
# Order is important to avoid breaking saved values; new modes are appended.
enum LocomotionMode { DISABLED, HEAD_DIRECTION, HAND_DIRECTION, HEAD_DIRECTION_3D, HAND_DIRECTION_3D }
@export var locomotion_mode: LocomotionMode = LocomotionMode.HEAD_DIRECTION_3D
@export var locomotion_speed: float = 5.0  # m/s
@export var locomotion_deadzone: float = 0.2
@export var invert_locomotion_x: bool = false
@export var invert_locomotion_y: bool = false

# === Turning Settings ===
enum TurnMode { SNAP, SMOOTH }
@export var turn_mode: TurnMode = TurnMode.SNAP
@export var snap_turn_angle: float = 45.0  # Degrees per snap turn
@export var smooth_turn_speed: float = 90.0  # Degrees per second
@export var turn_deadzone: float = 0.5  # Thumbstick deadzone for turning
@export var snap_turn_cooldown: float = 0.3  # Seconds between snap turns
@export var invert_turn_x: bool = false  # Optional invert for turn thumbstick

# === Hand Assignment ===
enum HandAssignment { DEFAULT, SWAPPED }
@export var hand_assignment: HandAssignment = HandAssignment.DEFAULT

# === UI Interaction ===
# Allows a pointing hand to temporarily repurpose its thumbstick for UI scrolling.
# While active, locomotion/turning driven by that stick are suppressed.
@export var ui_scroll_steals_stick: bool = false
@export_range(0.0, 1.0, 0.01) var ui_scroll_deadzone: float = 0.25
@export_range(10.0, 720.0, 10.0) var ui_scroll_wheel_factor: float = 240.0

# === World Grab / Utility Settings ===
@export var enable_two_hand_world_scale: bool = false
@export var enable_two_hand_world_rotation: bool = false
@export_range(0.01, 20.0, 0.05) var world_scale_min: float = 0.1
@export_range(0.1, 1000.0, 0.1) var world_scale_max: float = 15.0
@export_range(0.05, 1.5, 0.05) var world_scale_sensitivity: float = 0.35
@export_range(0.05, 2.0, 0.05) var world_rotation_sensitivity: float = 0.6
@export_range(1.0, 180.0, 1.0) var world_rotation_max_delta_deg: float = 180.0
@export_range(0.05, 3.0, 0.05) var world_grab_move_factor: float = 1.0
@export_range(0.05, 1.0, 0.05) var world_grab_smooth_factor: float = 0.15
@export var invert_two_hand_scale_direction: bool = true
@export var show_two_hand_rotation_visual: bool = true
enum TwoHandPivot { MIDPOINT, PLAYER_ORIGIN }
@export var two_hand_rotation_pivot: TwoHandPivot = TwoHandPivot.MIDPOINT
@export var two_hand_left_action: String = "trigger"
@export var two_hand_right_action: String = "trigger"
@export var debug_world_grab_logs: bool = true
@export var enable_one_hand_world_grab: bool = true
@export var enable_one_hand_world_rotate: bool = true
@export_range(0.0, 2.0, 0.05) var one_hand_world_move_sensitivity: float = 0.25
@export var apply_one_hand_release_velocity: bool = true
enum OneHandGrabMode { RELATIVE, ANCHORED }
@export var one_hand_grab_mode: OneHandGrabMode = OneHandGrabMode.RELATIVE
@export var enable_one_hand_rotation: bool = true
@export_range(0.01, 1.0, 0.01) var one_hand_rotation_smooth_factor: float = 0.2
@export var invert_one_hand_rotation: bool = false
@export var invert_one_hand_grab_direction: bool = true
@export var show_one_hand_grab_visual: bool = true
@export var auto_respawn_enabled: bool = false
@export_range(1.0, 1000.0, 1.0) var auto_respawn_distance: float = 120.0
@export var hard_respawn_resets_settings: bool = true

# === Jump Settings ===
@export var jump_enabled: bool = false
@export_range(1.0, 40.0, 0.5) var jump_impulse: float = 12.0
@export_range(0.0, 2.0, 0.05) var jump_cooldown: float = 0.4
@export var player_gravity_enabled: bool = false
@export_range(0.0, 5.0, 0.05) var player_drag_force: float = 0.85

# === Autojoin Settings ===
@export var autojoin_enabled: bool = false
@export_range(0.5, 10.0, 0.1) var autojoin_distance_threshold: float = 2.0
@export var autojoin_room_name: String = "default"
@export var autojoin_debug_logs: bool = true

# === Two-Hand Grab V2 Settings ===
# Completely separate from V1 - uses locked world point approach like Horizon Worlds
@export var enable_two_hand_grab_v2: bool = false
@export var v2_scale_enabled: bool = false
@export var v2_rotation_enabled: bool = false
@export_range(0.01, 20.0, 0.05) var v2_world_scale_min: float = 0.1
@export_range(0.1, 1000.0, 0.1) var v2_world_scale_max: float = 15.0
@export var v2_left_action: String = "trigger"
@export var v2_right_action: String = "trigger"
@export var v2_show_visual: bool = true
@export var v2_debug_logs: bool = false
@export var enable_physics_hands: bool = true

# === Two-Hand Grab V3 Settings ===
# XRToolsMovementWorldGrab style - exact algorithm from godot-xr-tools
@export var enable_two_hand_grab_v3: bool = true
@export_range(0.1, 20.0, 0.1) var v3_world_scale_min: float = 0.5
@export_range(0.5, 100.0, 0.5) var v3_world_scale_max: float = 2.0
@export var v3_left_action: String = "trigger"
@export var v3_right_action: String = "trigger"
@export var v3_show_visual: bool = true
@export var v3_debug_logs: bool = false
@export_range(0.0, 5.0, 0.1) var v3_scale_sensitivity: float = 0.0
@export_range(0.0, 5.0, 0.1) var v3_rotation_sensitivity: float = 1.0
@export_range(0.0, 5.0, 0.1) var v3_translation_sensitivity: float = 0.0
@export_range(0.0, 1.0, 0.05) var v3_smoothing: float = 0.5
@export var v3_invert_scale: bool = false

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
var _world_grab_prev_vector := Vector3.ZERO
var _world_grab_initial_midpoint := Vector3.ZERO
var _world_grab_prev_midpoint := Vector3.ZERO
var _world_grab_current_scale := 1.0
var _world_grab_smoothed_move := Vector3.ZERO
var _one_hand_grab_anchor := Vector3.ZERO
var _world_grab_initial_yaw := 0.0
var _one_hand_anchor_local := Vector3.ZERO
var _one_hand_initial_dir2d := Vector2.ZERO
var _one_hand_initial_yaw := 0.0
var _one_hand_rotation_pivot := Vector3.ZERO
var _one_hand_prev_body_pos := Vector3.ZERO
var _one_hand_last_move_velocity := Vector3.ZERO
var _manual_player_scale: float = 1.0

# Visual helpers
var _visual_root: Node3D
var _one_hand_anchor_mesh: MeshInstance3D
var _one_hand_line_mesh: MeshInstance3D
var _two_hand_line_mesh: MeshInstance3D
var _two_hand_midpoint_mesh: MeshInstance3D
var _two_hand_midpoint_line_mesh: MeshInstance3D
var _two_hand_anchor_xz_line_mesh: MeshInstance3D
var _world_grab_left_anchor: Vector3 = Vector3.ZERO
var _world_grab_right_anchor: Vector3 = Vector3.ZERO
var _world_grab_target_left_anchor: Vector3 = Vector3.ZERO
var _world_grab_target_right_anchor: Vector3 = Vector3.ZERO
var _one_hand_anchor_mat: StandardMaterial3D
var _one_hand_line_mat: StandardMaterial3D
var _two_hand_midpoint_line_mat: StandardMaterial3D
var _two_hand_anchor_xz_line_mat: StandardMaterial3D

# Respawn helpers
var _spawn_transform := Transform3D.IDENTITY
var _initial_settings: Dictionary = {}

# One-hand world grab state
var _one_hand_grab_active := false
var _one_hand_controller: XRController3D
var _one_hand_initial_controller_pos := Vector3.ZERO
var _one_hand_initial_body_pos := Vector3.ZERO

# Jump state
var _jump_cooldown_timer := 0.0

# Autojoin state
var _autojoin_triggered := false
var _initial_spawn_position := Vector3.ZERO

# Input mapping helper
var _input_binding_manager: InputBindingManager

# Two-Hand Grab V2 component
var _two_hand_grab_v2: TwoHandGrabV2

# Two-Hand Grab V3 component
var _two_hand_grab_v3: TwoHandGrabV3

# References
# References
var player_body: RigidBody3D
var left_controller: XRController3D
var right_controller: XRController3D
var xr_camera: XRCamera3D
var physics_hand_left: RigidBody3D
var physics_hand_right: RigidBody3D

# UI scroll capture state
var _ui_block_locomotion: bool = false
var _ui_block_turn: bool = false

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


func setup(p_player_body: RigidBody3D, p_left_controller: XRController3D, p_right_controller: XRController3D, p_xr_camera: XRCamera3D, p_hand_left: RigidBody3D = null, p_hand_right: RigidBody3D = null) -> void:
	player_body = p_player_body
	left_controller = p_left_controller
	right_controller = p_right_controller
	xr_camera = p_xr_camera
	physics_hand_left = p_hand_left
	physics_hand_right = p_hand_right
	
	if player_body:
		_spawn_transform = player_body.global_transform
		_initial_spawn_position = player_body.global_position
	
	# Log autojoin settings on setup
	print("[Autojoin] Setup - enabled: %s, threshold: %.1fm, room: '%s', spawn_pos: %s" % [
		autojoin_enabled, autojoin_distance_threshold, autojoin_room_name, _initial_spawn_position
	])
	_initial_settings = _snapshot_settings()
	_apply_manual_player_scale()
	_apply_player_gravity()
	_apply_player_drag()
	_update_physics_hands()
	_ensure_visuals()
	_setup_two_hand_grab_v2()
	_setup_two_hand_grab_v3()
	print("PlayerMovementComponent: Setup with hands")
	print("PlayerMovementComponent: Auto Respawn State: ", auto_respawn_enabled)


var _debug_frame_count: int = 0
var _last_pos_for_debug: Vector3 = Vector3.ZERO
func _physics_process(delta: float) -> void:
	_debug_frame_count += 1
	if _debug_frame_count % 60 == 0 and physics_hand_left and player_body:
		var hand_layer = physics_hand_left.collision_layer
		var body_mask = player_body.collision_mask
		if (hand_layer & body_mask) != 0:
			print("DEBUG: COLLISION RISK! Hand Layer: %d, Body Mask: %d (Overlap!)" % [hand_layer, body_mask])
			# Force fix attempt
			if not enable_physics_hands:
				physics_hand_left.collision_layer = 0
				physics_hand_left.collision_mask = 0
				print("DEBUG: Forced Hand Layer/Mask to 0")

	if player_body:
		var curr_pos := player_body.global_transform.origin
		var dist := curr_pos.distance_to(_last_pos_for_debug)
		
		# 1. Check for massive jumps (Telemetry)
		if dist > 3.0 and _last_pos_for_debug != Vector3.ZERO:
			print("PlayerMovementComponent: LARGE MOVEMENT! %.2fm" % dist)
			print("  Scale: %.2f | Vel: %s" % [XRServer.world_scale, player_body.linear_velocity])
			print("  From: %s -> To: %s" % [_last_pos_for_debug, curr_pos])
		
		_last_pos_for_debug = curr_pos
		

		
	if is_vr_mode:
		physics_process_turning(delta)
		physics_process_locomotion(delta)
	
	# Autojoin check runs regardless of VR mode
	_check_autojoin()
		
	# Head collision is now an Area3D parented to the XRCamera3D; it follows the headset automatically


func _ready() -> void:
	_input_binding_manager = InputBindingManager.get_singleton()
	if _input_binding_manager:
		var default_events := []
		if InputMap.has_action("jump"):
			default_events = InputMap.action_get_events("jump")
		_input_binding_manager.ensure_binding("jump", default_events, InputBindingManager.MODE_ANY)
	# Auto-load saved movement settings (Meta VRCS requirement: preserve user data)
	_load_saved_settings()


func set_vr_mode(enabled: bool) -> void:
	is_vr_mode = enabled
	_update_physics_hands()


func swap_hands() -> void:
	"""Toggle hand assignment between default and swapped"""
	if hand_assignment == HandAssignment.DEFAULT:
		hand_assignment = HandAssignment.SWAPPED
		print("PlayerMovementComponent: Hands swapped - Move:Right, Turn:Left")
	else:
		hand_assignment = HandAssignment.DEFAULT
		print("PlayerMovementComponent: Hands default - Move:Left, Turn:Right")
	_clear_ui_scroll_capture()


func set_ui_scroll_capture(active: bool, controller: XRController3D) -> void:
	if not ui_scroll_steals_stick:
		_clear_ui_scroll_capture()
		return
	if active:
		# While scrolling, pause both locomotion and turning to prevent drift.
		_ui_block_locomotion = true
		_ui_block_turn = true
	else:
		if controller and controller == locomotion_controller:
			_ui_block_locomotion = false
		if controller and controller == turn_controller:
			_ui_block_turn = false
		if not controller:
			_clear_ui_scroll_capture()


func _clear_ui_scroll_capture() -> void:
	_ui_block_locomotion = false
	_ui_block_turn = false


func _load_saved_settings() -> void:
	"""Load saved movement settings from SaveManager (Meta VRCS compliance)"""
	var save_manager = get_node_or_null("/root/SaveManager")
	if not save_manager or not save_manager.has_method("get_movement_settings"):
		return
	
	if not save_manager.has_movement_settings():
		print("PlayerMovementComponent: No saved settings found, using defaults")
		return
	
	var settings: Dictionary = save_manager.get_movement_settings()
	if settings.is_empty():
		return
	
	print("PlayerMovementComponent: Loading saved movement settings")
	
	# Apply all saved settings
	locomotion_mode = settings.get("locomotion_mode", locomotion_mode)
	locomotion_speed = settings.get("locomotion_speed", locomotion_speed)
	locomotion_deadzone = settings.get("locomotion_deadzone", locomotion_deadzone)
	invert_locomotion_x = settings.get("invert_locomotion_x", invert_locomotion_x)
	invert_locomotion_y = settings.get("invert_locomotion_y", invert_locomotion_y)
	turn_mode = settings.get("turn_mode", turn_mode)
	snap_turn_angle = settings.get("snap_turn_angle", snap_turn_angle)
	smooth_turn_speed = settings.get("smooth_turn_speed", smooth_turn_speed)
	turn_deadzone = settings.get("turn_deadzone", turn_deadzone)
	snap_turn_cooldown = settings.get("snap_turn_cooldown", snap_turn_cooldown)
	invert_turn_x = settings.get("invert_turn_x", invert_turn_x)
	ui_scroll_steals_stick = settings.get("ui_scroll_steals_stick", ui_scroll_steals_stick)
	hand_assignment = settings.get("hand_assignment", hand_assignment)
	enable_two_hand_world_scale = settings.get("enable_two_hand_world_scale", enable_two_hand_world_scale)
	enable_two_hand_world_rotation = settings.get("enable_two_hand_world_rotation", enable_two_hand_world_rotation)
	world_scale_min = settings.get("world_scale_min", world_scale_min)
	world_scale_max = settings.get("world_scale_max", world_scale_max)
	world_scale_sensitivity = settings.get("world_scale_sensitivity", world_scale_sensitivity)
	world_rotation_sensitivity = settings.get("world_rotation_sensitivity", world_rotation_sensitivity)
	world_grab_move_factor = settings.get("world_grab_move_factor", world_grab_move_factor)
	world_grab_smooth_factor = settings.get("world_grab_smooth_factor", world_grab_smooth_factor)
	invert_two_hand_scale_direction = settings.get("invert_two_hand_scale_direction", invert_two_hand_scale_direction)
	show_two_hand_rotation_visual = settings.get("show_two_hand_rotation_visual", show_two_hand_rotation_visual)
	two_hand_left_action = settings.get("two_hand_left_action", two_hand_left_action)
	two_hand_right_action = settings.get("two_hand_right_action", two_hand_right_action)
	two_hand_rotation_pivot = settings.get("two_hand_rotation_pivot", two_hand_rotation_pivot)
	enable_one_hand_world_grab = settings.get("enable_one_hand_world_grab", enable_one_hand_world_grab)
	one_hand_world_move_sensitivity = settings.get("one_hand_world_move_sensitivity", one_hand_world_move_sensitivity)
	invert_one_hand_grab_direction = settings.get("invert_one_hand_grab_direction", invert_one_hand_grab_direction)
	show_one_hand_grab_visual = settings.get("show_one_hand_grab_visual", show_one_hand_grab_visual)
	one_hand_grab_mode = settings.get("one_hand_grab_mode", one_hand_grab_mode)
	enable_one_hand_rotation = settings.get("enable_one_hand_rotation", enable_one_hand_rotation)
	enable_one_hand_world_rotate = settings.get("enable_one_hand_world_rotate", enable_one_hand_world_rotate)
	invert_one_hand_rotation = settings.get("invert_one_hand_rotation", invert_one_hand_rotation)
	apply_one_hand_release_velocity = settings.get("apply_one_hand_release_velocity", apply_one_hand_release_velocity)
	one_hand_rotation_smooth_factor = settings.get("one_hand_rotation_smooth_factor", one_hand_rotation_smooth_factor)
	auto_respawn_enabled = settings.get("auto_respawn_enabled", auto_respawn_enabled)
	auto_respawn_distance = settings.get("auto_respawn_distance", auto_respawn_distance)
	hard_respawn_resets_settings = settings.get("hard_respawn_resets_settings", hard_respawn_resets_settings)
	jump_enabled = settings.get("jump_enabled", jump_enabled)
	jump_impulse = settings.get("jump_impulse", jump_impulse)
	jump_cooldown = settings.get("jump_cooldown", jump_cooldown)
	player_gravity_enabled = settings.get("player_gravity_enabled", player_gravity_enabled)
	player_drag_force = settings.get("player_drag_force", player_drag_force)
	enable_physics_hands = settings.get("enable_physics_hands", enable_physics_hands)
	# V3 settings
	v3_scale_sensitivity = settings.get("v3_scale_sensitivity", v3_scale_sensitivity)
	v3_invert_scale = settings.get("v3_invert_scale", v3_invert_scale)
	v3_rotation_sensitivity = settings.get("v3_rotation_sensitivity", v3_rotation_sensitivity)
	v3_translation_sensitivity = settings.get("v3_translation_sensitivity", v3_translation_sensitivity)
	v3_smoothing = settings.get("v3_smoothing", v3_smoothing)
	
	print("PlayerMovementComponent: Settings restored successfully")


func process_turning(delta: float) -> void:
	if not is_vr_mode:
		return
	if ui_scroll_steals_stick and _ui_block_turn:
		_smooth_input = 0.0
		return
	_handle_turning(delta)


func process_locomotion(delta: float) -> void:
	if not is_vr_mode or locomotion_mode == LocomotionMode.DISABLED:
		return
	if ui_scroll_steals_stick and _ui_block_locomotion:
		return
	_handle_locomotion(delta)
	_handle_jump(delta)
	_check_auto_respawn()


func physics_process_turning(delta: float) -> void:
	# Apply any pending rotation to the physics body during the physics step
	if player_body:
		# Apply snap rotation if pending
		if abs(_pending_snap_angle) > 0.001:
			var lv = player_body.linear_velocity
			var av = player_body.angular_velocity
			_rotate_player_body_y(deg_to_rad(_pending_snap_angle))
			player_body.linear_velocity = lv
			player_body.angular_velocity = av
			_pending_snap_angle = 0.0

		# Apply smooth rotation based on input
		if abs(_smooth_input) > 0.001:
			var turn_amount = -_smooth_input * smooth_turn_speed * delta
			var lv2 = player_body.linear_velocity
			_rotate_player_body_y(deg_to_rad(turn_amount))
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
	if ui_scroll_steals_stick and _ui_block_locomotion:
		return
	
	# Get thumbstick input
	var input = locomotion_controller.get_vector2("primary")
	if invert_locomotion_x:
		input.x *= -1.0
	if invert_locomotion_y:
		input.y *= -1.0
	
	if input.length() < locomotion_deadzone:
		return
	
	# Get movement direction based on mode
	var move_direction = _get_movement_direction(input)
	var allow_vertical := locomotion_mode == LocomotionMode.HEAD_DIRECTION_3D or locomotion_mode == LocomotionMode.HAND_DIRECTION_3D
	
	if move_direction.length() < 0.01:
		return
	
	# Apply movement force (similar to desktop controller)
	var target_velocity = move_direction * locomotion_speed
	var current_velocity = player_body.linear_velocity if allow_vertical else Vector3(player_body.linear_velocity.x, 0, player_body.linear_velocity.z)
	var velocity_change = target_velocity - current_velocity
	
	# Apply force to reach target velocity
	player_body.apply_central_force(velocity_change * player_body.mass * 10.0)


func _get_movement_direction(input: Vector2) -> Vector3:
	"""Get world-space movement direction based on locomotion mode"""
	var forward: Vector3
	var right: Vector3
	var allow_vertical := locomotion_mode == LocomotionMode.HEAD_DIRECTION_3D or locomotion_mode == LocomotionMode.HAND_DIRECTION_3D
	
	if locomotion_mode == LocomotionMode.HEAD_DIRECTION or locomotion_mode == LocomotionMode.HEAD_DIRECTION_3D:
		# Movement relative to head/camera direction
		if xr_camera:
			forward = -xr_camera.global_transform.basis.z
			right = xr_camera.global_transform.basis.x
		elif player_body:
			forward = -player_body.global_transform.basis.z
			right = player_body.global_transform.basis.x
		else:
			return Vector3.ZERO
	else:  # HAND_DIRECTION or HAND_DIRECTION_3D
		# Movement relative to locomotion controller direction
		if locomotion_controller:
			forward = -locomotion_controller.global_transform.basis.z
			right = locomotion_controller.global_transform.basis.x
		else:
			return Vector3.ZERO
	
	# Keep movement on horizontal plane unless 3D mode is selected
	if not allow_vertical:
		forward.y = 0
		right.y = 0
	forward = forward.normalized()
	right = right.normalized()
	
	# Combine input with directions
	# Thumbstick: Y positive = forward, Y negative = back, X positive = right, X negative = left
	return (forward * input.y + right * input.x).normalized()


func _update_physics_hands() -> void:
	# Only enable if VR mode AND setting is enabled
	var should_enable := is_vr_mode and enable_physics_hands
	
	if physics_hand_left:
		_set_hand_state(physics_hand_left, should_enable)
		
	if physics_hand_right:
		_set_hand_state(physics_hand_right, should_enable)
		
	# Ensure exceptions are always present (just in case)
	if player_body:
		if physics_hand_left:
			player_body.add_collision_exception_with(physics_hand_left)
			physics_hand_left.add_collision_exception_with(player_body)
		if physics_hand_right:
			player_body.add_collision_exception_with(physics_hand_right)
			physics_hand_right.add_collision_exception_with(player_body)


func _set_hand_state(hand: RigidBody3D, enabled: bool) -> void:
	hand.visible = enabled
	hand.set_physics_process(enabled)
	
	if enabled:
		hand.process_mode = Node.PROCESS_MODE_INHERIT
		hand.freeze = false
		# Restore collision (Layer 2, Mask 1 - assuming standard setup)
		# TODO: Ideally we'd cache the original layers, but for this specific rig:
		# Hands are typically Layer 2 (Vehicle/PlayerProp) and Mask 1 (World).
		hand.collision_layer = 2
		hand.collision_mask = 1
		
		# FORCE exception again
		if player_body:
			player_body.add_collision_exception_with(hand)
			hand.add_collision_exception_with(player_body)
			print("PlayerMovementComponent: Enabled hand %s, restored collision & exceptions." % hand.name)
	else:
		hand.freeze = true
		hand.linear_velocity = Vector3.ZERO
		hand.angular_velocity = Vector3.ZERO
		# CRITICAL: Disable collision entirely so it doesn't explode if inside player
		hand.collision_layer = 0
		hand.collision_mask = 0
		print("PlayerMovementComponent: Disabled hand %s, CLEARED collision." % hand.name)


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
	if invert_turn_x:
		turn_input.x *= -1.0
	
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


func _rotate_player_body_y(angle_rad: float) -> void:
	"""Rotate the player body around the headset pivot instead of world origin."""
	if not player_body:
		return
	var pivot: Vector3 = xr_camera.global_transform.origin if xr_camera else player_body.global_transform.origin
	var xf := player_body.global_transform
	var rot_basis := Basis(Vector3.UP, angle_rad)
	xf.origin = pivot + rot_basis * (xf.origin - pivot)
	xf.basis = rot_basis * xf.basis
	player_body.global_transform = xf


func _rotate_body_around_point(angle_rad: float, pivot: Vector3) -> void:
	if not player_body:
		return
	var xf := player_body.global_transform
	var rot_basis := Basis(Vector3.UP, angle_rad)
	xf.origin = pivot + rot_basis * (xf.origin - pivot)
	xf.basis = rot_basis * xf.basis
	player_body.global_transform = xf


func _get_yaw(xf: Transform3D) -> float:
	return xf.basis.get_euler().y


func _get_player_up() -> Vector3:
	if player_body:
		var up := player_body.global_transform.basis.y
		if up.length_squared() > 0.0001:
			return up.normalized()
	return Vector3.UP


func _get_two_hand_pivot_point(midpoint: Vector3) -> Vector3:
	if two_hand_rotation_pivot == TwoHandPivot.PLAYER_ORIGIN and player_body:
		return player_body.global_transform.origin
	return midpoint


func _signed_angle_2d(a: Vector2, b: Vector2) -> float:
	var dot := a.normalized().dot(b.normalized())
	var cross := a.x * b.y - a.y * b.x
	return atan2(cross, dot)


# === World Grab Helpers ===

func physics_process_world_grab(delta: float) -> void:
	"""Allow two-hand grab gestures to scale/rotate the world."""
	
	# === V3 Mode: XRToolsMovementWorldGrab style ===
	if enable_two_hand_grab_v3 and _two_hand_grab_v3:
		_sync_v3_settings()
		var v3_handled := _two_hand_grab_v3.process_grab(delta)
		# If V3 is active, normally we skip V1. But if V1 scaling is enabled, we allow fall-through.
		if _two_hand_grab_v3.is_active():
			if not enable_two_hand_world_scale:
				_end_world_grab()
				_end_one_hand_grab()
				return
		# If V3 not grabbing, fall through to one-hand grab if enabled
	
	# === V2 Mode: Completely separate implementation ===
	if enable_two_hand_grab_v2 and _two_hand_grab_v2 and not enable_two_hand_grab_v3:
		_sync_v2_settings()
		_two_hand_grab_v2.process_grab(delta)
		# If V2 is active, skip V1 logic entirely
		if _two_hand_grab_v2.is_active():
			_end_world_grab()  # Ensure V1 state is cleaned up
			_end_one_hand_grab()
			return
		# If V2 not grabbing, fall through to one-hand grab if enabled
	
	# === V1 Mode: Original implementation (Hybrid-capable) ===
	var v3_active_and_scaling_wanted := enable_two_hand_grab_v3 and _two_hand_grab_v3 and _two_hand_grab_v3.is_active() and enable_two_hand_world_scale
	var two_hand_v1_enabled := ((enable_two_hand_world_scale or enable_two_hand_world_rotation) and not enable_two_hand_grab_v2 and not enable_two_hand_grab_v3) or v3_active_and_scaling_wanted
	var one_hand_enabled := enable_one_hand_world_grab or enable_one_hand_world_rotate

	if not (two_hand_v1_enabled or one_hand_enabled):
		_end_world_grab()
		_end_one_hand_grab()
		return
	if not player_body:
		_end_world_grab()
		_end_one_hand_grab()
		return

	var left_pressed: bool = left_controller and _is_action_pressed(left_controller, two_hand_left_action)
	var right_pressed: bool = right_controller and _is_action_pressed(right_controller, two_hand_right_action)

	if two_hand_v1_enabled and left_pressed and right_pressed and left_controller and right_controller:
		_end_one_hand_grab()
		if not _world_grab_active:
			_start_world_grab()
		_update_world_grab()
	elif one_hand_enabled and (left_pressed != right_pressed): # exactly one pressed
		_end_world_grab()
		var controller := left_controller if left_pressed else right_controller
		if controller:
			if not _one_hand_grab_active:
				_start_one_hand_grab(controller)
			_update_one_hand_grab(controller, delta)
	else:
		_end_world_grab()
		_end_one_hand_grab()


func _is_action_pressed(controller: XRController3D, action: String) -> bool:
	if not controller:
		return false
	if controller.has_method("get_float"):
		var val: float = controller.get_float(action)
		# Fallback for common naming variants
		if val == 0.0 and action == "grip":
			val = controller.get_float("grip_click")
		if val == 0.0 and action == "trigger":
			val = controller.get_float("trigger_click")
		return val > 0.75
	if controller.has_method("get_bool"):
		return controller.get_bool(action)
	return false


func _start_world_grab() -> void:
	_world_grab_active = true
	var up := _get_player_up()
	var initial_vec := (right_controller.global_position - left_controller.global_position).slide(up)
	_world_grab_initial_distance = max(0.01, initial_vec.length())
	_world_grab_initial_scale = XRServer.world_scale
	_world_grab_current_scale = XRServer.world_scale
	_world_grab_smoothed_move = Vector3.ZERO
	_world_grab_initial_vector = initial_vec
	_world_grab_prev_vector = _world_grab_initial_vector
	_world_grab_initial_midpoint = (left_controller.global_position + right_controller.global_position) * 0.5
	_world_grab_prev_midpoint = _world_grab_initial_midpoint
	_world_grab_initial_yaw = _get_yaw(player_body.global_transform)
	_world_grab_left_anchor = left_controller.global_position
	_world_grab_right_anchor = right_controller.global_position
	_world_grab_target_left_anchor = _world_grab_left_anchor
	_world_grab_target_right_anchor = _world_grab_right_anchor
	_update_two_hand_visual(left_controller.global_position, right_controller.global_position, _world_grab_initial_midpoint)


func _update_world_grab() -> void:
	if not _world_grab_active:
		return

	var up := _get_player_up()
	var raw_vector: Vector3 = (right_controller.global_position - left_controller.global_position).slide(up)
	var raw_midpoint: Vector3 = (left_controller.global_position + right_controller.global_position) * 0.5
	# Low-pass filter controller delta to reduce jitter before applying scale/rotation.
	_world_grab_prev_vector = _world_grab_prev_vector.lerp(raw_vector, world_grab_smooth_factor)
	var current_vector: Vector3 = _world_grab_prev_vector
	var current_distance: float = max(0.01, current_vector.length())
	var current_midpoint: Vector3 = _world_grab_prev_midpoint.lerp(raw_midpoint, world_grab_smooth_factor)

	if enable_two_hand_world_scale and _world_grab_initial_distance > 0.01:
		var ratio: float = current_distance / _world_grab_initial_distance
		var effective_ratio: float = ratio if not invert_two_hand_scale_direction else (1.0 / max(ratio, 0.0001))
		# Ignore micro-changes to avoid jitter from controller noise.
		if abs(effective_ratio - 1.0) > 0.01:
			var scale_factor: float = 1.0 + (effective_ratio - 1.0) * world_scale_sensitivity
			var target_scale: float = clampf(
				_world_grab_initial_scale * scale_factor,
				world_scale_min,
				world_scale_max
			)
			_world_grab_current_scale = lerpf(_world_grab_current_scale, target_scale, world_grab_smooth_factor)
			var anchor_point := xr_camera.global_transform.origin if xr_camera else player_body.global_transform.origin
			XRServer.world_scale = _world_grab_current_scale
			_reanchor_player(anchor_point)
	
	# Update target anchors to account for scale about the initial midpoint.
	var safe_scale: float = max(_world_grab_current_scale, 0.0001)
	var scale_ratio: float = _world_grab_initial_scale / safe_scale
	_world_grab_target_left_anchor = _world_grab_initial_midpoint + (_world_grab_left_anchor - _world_grab_initial_midpoint) * scale_ratio
	_world_grab_target_right_anchor = _world_grab_initial_midpoint + (_world_grab_right_anchor - _world_grab_initial_midpoint) * scale_ratio

	# Keep the original grab anchors fixed in world space (average correction).
	var anchor_err_left := left_controller.global_position - _world_grab_target_left_anchor if _world_grab_left_anchor != Vector3.ZERO else Vector3.ZERO
	var anchor_err_right := right_controller.global_position - _world_grab_target_right_anchor if _world_grab_right_anchor != Vector3.ZERO else Vector3.ZERO
	var avg_err := (anchor_err_left + anchor_err_right) * 0.5
	var vertical_correction := Vector3(0.0, -avg_err.y * world_grab_move_factor, 0.0)
	var horizontal_correction := -Vector3(avg_err.x, 0.0, avg_err.z) * world_grab_move_factor
	var anchor_max_step := 0.15
	horizontal_correction = horizontal_correction.limit_length(anchor_max_step)
	_world_grab_smoothed_move = _world_grab_smoothed_move.lerp(horizontal_correction + vertical_correction, world_grab_smooth_factor)
	if debug_world_grab_logs:
		print(
			"[WorldGrab] Lpos=", left_controller.global_position,
			" Rpos=", right_controller.global_position,
			" Lanchor=", _world_grab_target_left_anchor,
			" Ranchor=", _world_grab_target_right_anchor,
			" Lerr=", anchor_err_left,
			" Rerr=", anchor_err_right,
			" AvgErr=", avg_err,
			" AvgLen=", avg_err.length(),
			" Scale=", _world_grab_current_scale
		)
	if _world_grab_smoothed_move.length_squared() > 0.000001:
		var xf := player_body.global_transform
		var lv = player_body.linear_velocity
		var av = player_body.angular_velocity
		xf.origin += _world_grab_smoothed_move
		player_body.global_transform = xf
		player_body.linear_velocity = lv
		player_body.angular_velocity = av

	# Prevent V1 rotation if V3 is active (handled there)
	var v3_rotates := enable_two_hand_grab_v3 and _two_hand_grab_v3 and _two_hand_grab_v3.is_active()
	if enable_two_hand_world_rotation and not v3_rotates:
		var init_vec := _world_grab_initial_vector
		var curr_vec := current_vector
		if init_vec.length_squared() > 0.0001 and curr_vec.length_squared() > 0.0001:
			# Rotate world opposite to hand rotation (negative sign).
			var signed_angle := -init_vec.signed_angle_to(curr_vec, up) * world_rotation_sensitivity
			var target_yaw := _world_grab_initial_yaw + signed_angle
			var current_yaw := _get_yaw(player_body.global_transform)
			var delta_yaw := wrapf(target_yaw - current_yaw, -PI, PI)
			var rotation_deadzone := deg_to_rad(0.35)
			if abs(delta_yaw) > rotation_deadzone:
				var dot_sign := init_vec.normalized().dot(curr_vec.normalized())
				var hands_crossed := dot_sign < 0.0
				var max_step := deg_to_rad(world_rotation_max_delta_deg)
				if hands_crossed:
					max_step = abs(delta_yaw)  # allow full 180 catch-up when swapping
				var applied := clampf(delta_yaw, -max_step, max_step)
				if abs(applied) > 0.0001:
					var lv = player_body.linear_velocity
					var av = player_body.angular_velocity
					var pivot := _get_two_hand_pivot_point(current_midpoint)
					_rotate_body_around_point(applied, pivot)
					player_body.linear_velocity = lv
					player_body.angular_velocity = av
	_world_grab_prev_midpoint = current_midpoint
	_world_grab_prev_vector = current_vector
	_update_two_hand_visual(left_controller.global_position, right_controller.global_position, current_midpoint)


func _start_one_hand_grab(controller: XRController3D) -> void:
	_ensure_visuals()
	_one_hand_grab_active = true
	_one_hand_controller = controller
	_one_hand_initial_controller_pos = controller.global_position
	_one_hand_initial_body_pos = player_body.global_transform.origin
	_one_hand_prev_body_pos = player_body.global_transform.origin
	_one_hand_anchor_local = player_body.to_local(controller.global_position) if player_body else controller.global_position
	# Store initial grab anchor in world space (used for relative mode visuals)
	_one_hand_grab_anchor = controller.global_position
	_one_hand_rotation_pivot = _one_hand_grab_anchor
	_one_hand_initial_dir2d = Vector2(controller.global_position.x - _one_hand_rotation_pivot.x, controller.global_position.z - _one_hand_rotation_pivot.z)
	_one_hand_initial_yaw = _get_yaw(player_body.global_transform)
	_update_one_hand_visual()


func _update_one_hand_grab(controller: XRController3D, delta: float) -> void:
	if not _one_hand_grab_active or not controller or not player_body:
		return
	# Anchor always follows player space; relative mode uses the hand delta for movement, but visuals/pivot stay player-relative
	var anchor_move_world := player_body.to_global(_one_hand_anchor_local)
	_one_hand_grab_anchor = anchor_move_world
	_one_hand_rotation_pivot = anchor_move_world
	var offset: Vector3
	if enable_one_hand_world_grab:
		if one_hand_grab_mode == OneHandGrabMode.ANCHORED:
			offset = (anchor_move_world - controller.global_position) * one_hand_world_move_sensitivity
		else:
			offset = (controller.global_position - _one_hand_initial_controller_pos) * one_hand_world_move_sensitivity
		if invert_one_hand_grab_direction:
			offset *= -1.0
		var prev_pos: Vector3 = player_body.global_transform.origin
		var xf: Transform3D = player_body.global_transform
		xf.origin += offset
		player_body.global_transform = xf
		var dt: float = max(delta, 0.0001)
		var new_vel: Vector3 = (xf.origin - prev_pos) / dt
		player_body.linear_velocity = new_vel
		_one_hand_prev_body_pos = xf.origin
		_one_hand_last_move_velocity = new_vel
	else:
		_one_hand_last_move_velocity = Vector3.ZERO

	# One-hand rotation around anchor (player space)
	if enable_one_hand_rotation and enable_one_hand_world_rotate:
		var dir2d := Vector2(controller.global_position.x - _one_hand_rotation_pivot.x, controller.global_position.z - _one_hand_rotation_pivot.z)
		if dir2d.length_squared() > 0.0001 and _one_hand_initial_dir2d.length_squared() > 0.0001:
			var ang := _signed_angle_2d(_one_hand_initial_dir2d, dir2d)
			if invert_one_hand_rotation:
				ang *= -1.0
			var target_yaw := _one_hand_initial_yaw + ang
			var current_yaw := _get_yaw(player_body.global_transform)
			var delta_yaw := wrapf(target_yaw - current_yaw, -PI, PI)
			var applied := delta_yaw * one_hand_rotation_smooth_factor
			if abs(applied) > 0.0001:
				var lv2 = player_body.linear_velocity
				var av2 = player_body.angular_velocity
				_rotate_body_around_point(applied, _one_hand_rotation_pivot)
				player_body.linear_velocity = lv2
				player_body.angular_velocity = av2

	_update_one_hand_visual()


func _end_one_hand_grab() -> void:
	_one_hand_grab_active = false
	_one_hand_controller = null
	if not apply_one_hand_release_velocity and player_body:
		player_body.linear_velocity = Vector3.ZERO
	_one_hand_last_move_velocity = Vector3.ZERO
	_update_one_hand_visual()


func _end_world_grab() -> void:
	_world_grab_active = false
	_world_grab_left_anchor = Vector3.ZERO
	_world_grab_right_anchor = Vector3.ZERO
	_world_grab_target_left_anchor = Vector3.ZERO
	_world_grab_target_right_anchor = Vector3.ZERO
	_world_grab_target_left_anchor = Vector3.ZERO
	_world_grab_target_right_anchor = Vector3.ZERO
	_clear_two_hand_visual()


func set_player_gravity_enabled(enabled: bool) -> void:
	player_gravity_enabled = enabled
	_apply_player_gravity()


func _handle_jump(delta: float) -> void:
	if not jump_enabled or not player_body:
		return
	if _jump_cooldown_timer > 0.0:
		_jump_cooldown_timer = max(0.0, _jump_cooldown_timer - delta)
		return
	var triggered := Input.is_action_just_pressed("jump")
	if _input_binding_manager:
		triggered = triggered or _input_binding_manager.is_action_just_triggered("jump")
	if triggered:
		player_body.apply_central_impulse(Vector3.UP * jump_impulse * player_body.mass)
		_jump_cooldown_timer = jump_cooldown


func set_manual_player_scale(scale: float) -> void:
	_manual_player_scale = max(scale, 0.01)
	_apply_manual_player_scale()


func _apply_manual_player_scale() -> void:
	if not player_body:
		return
	player_body.scale = Vector3.ONE * _manual_player_scale


func _apply_player_gravity() -> void:
	if player_body:
		player_body.gravity_scale = 1.0 if player_gravity_enabled else 0.0


func _apply_player_drag() -> void:
	if not player_body:
		return
	player_body.linear_damp = player_drag_force
	player_body.angular_damp = player_drag_force * 0.5


# === Visual Helpers ===

func _ensure_visuals() -> void:
	if not player_body:
		return
	if not _visual_root:
		_visual_root = Node3D.new()
		_visual_root.name = "MovementVisuals"
		player_body.add_child(_visual_root)
		_visual_root.owner = player_body.get_owner()
	if show_one_hand_grab_visual and not _one_hand_anchor_mesh:
		var sphere := SphereMesh.new()
		sphere.radius = 0.05
		sphere.height = 0.1
		_one_hand_anchor_mat = StandardMaterial3D.new()
		_one_hand_anchor_mat.albedo_color = Color(0.3, 0.9, 1.0, 0.8)
		_one_hand_anchor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_one_hand_anchor_mesh = MeshInstance3D.new()
		_one_hand_anchor_mesh.mesh = sphere
		_one_hand_anchor_mesh.material_override = _one_hand_anchor_mat
		_one_hand_anchor_mesh.visible = false
		_visual_root.add_child(_one_hand_anchor_mesh)
	if not _one_hand_line_mesh:
		var im := ImmediateMesh.new()
		_one_hand_line_mat = StandardMaterial3D.new()
		_one_hand_line_mat.albedo_color = Color(0.3, 0.9, 1.0, 0.9)
		_one_hand_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_one_hand_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_one_hand_line_mesh = MeshInstance3D.new()
		_one_hand_line_mesh.mesh = im
		_one_hand_line_mesh.material_override = _one_hand_line_mat
		_one_hand_line_mesh.visible = false
		_visual_root.add_child(_one_hand_line_mesh)
	if show_two_hand_rotation_visual:
		if not _two_hand_line_mesh:
			var line_mesh := ImmediateMesh.new()
			var mat2 := StandardMaterial3D.new()
			mat2.albedo_color = Color(1.0, 0.6, 0.2, 0.85)
			mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_two_hand_line_mesh = MeshInstance3D.new()
			_two_hand_line_mesh.mesh = line_mesh
			_two_hand_line_mesh.material_override = mat2
			_two_hand_line_mesh.visible = false
			_visual_root.add_child(_two_hand_line_mesh)
		if not _two_hand_midpoint_line_mesh:
			var line_mesh_mid := ImmediateMesh.new()
			_two_hand_midpoint_line_mat = StandardMaterial3D.new()
			_two_hand_midpoint_line_mat.albedo_color = Color(0.4, 0.9, 0.4, 0.85)
			_two_hand_midpoint_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_two_hand_midpoint_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_two_hand_midpoint_line_mesh = MeshInstance3D.new()
			_two_hand_midpoint_line_mesh.mesh = line_mesh_mid
			_two_hand_midpoint_line_mesh.material_override = _two_hand_midpoint_line_mat
			_two_hand_midpoint_line_mesh.visible = false
			_visual_root.add_child(_two_hand_midpoint_line_mesh)
		if not _two_hand_anchor_xz_line_mesh:
			var line_mesh_xz := ImmediateMesh.new()
			_two_hand_anchor_xz_line_mat = StandardMaterial3D.new()
			_two_hand_anchor_xz_line_mat.albedo_color = Color(0.2, 0.8, 1.0, 0.8)
			_two_hand_anchor_xz_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_two_hand_anchor_xz_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_two_hand_anchor_xz_line_mesh = MeshInstance3D.new()
			_two_hand_anchor_xz_line_mesh.mesh = line_mesh_xz
			_two_hand_anchor_xz_line_mesh.material_override = _two_hand_anchor_xz_line_mat
			_two_hand_anchor_xz_line_mesh.visible = false
			_visual_root.add_child(_two_hand_anchor_xz_line_mesh)
		if not _two_hand_midpoint_mesh:
			var m := BoxMesh.new()
			m.size = Vector3(0.06, 0.06, 0.06)
			var mat3 := StandardMaterial3D.new()
			mat3.albedo_color = Color(1.0, 0.85, 0.2, 0.9)
			mat3.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat3.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_two_hand_midpoint_mesh = MeshInstance3D.new()
			_two_hand_midpoint_mesh.mesh = m
			_two_hand_midpoint_mesh.material_override = mat3
			_two_hand_midpoint_mesh.visible = false
			_visual_root.add_child(_two_hand_midpoint_mesh)


func _snapshot_settings() -> Dictionary:
	return {
		"locomotion_mode": locomotion_mode,
		"locomotion_speed": locomotion_speed,
		"locomotion_deadzone": locomotion_deadzone,
		"invert_locomotion_x": invert_locomotion_x,
		"invert_locomotion_y": invert_locomotion_y,
		"turn_mode": turn_mode,
		"snap_turn_angle": snap_turn_angle,
		"smooth_turn_speed": smooth_turn_speed,
		"turn_deadzone": turn_deadzone,
		"snap_turn_cooldown": snap_turn_cooldown,
		"invert_turn_x": invert_turn_x,
		"ui_scroll_steals_stick": ui_scroll_steals_stick,
		"ui_scroll_deadzone": ui_scroll_deadzone,
		"ui_scroll_wheel_factor": ui_scroll_wheel_factor,
		"hand_assignment": hand_assignment,
		"enable_two_hand_world_scale": enable_two_hand_world_scale,
		"enable_two_hand_world_rotation": enable_two_hand_world_rotation,
		"world_scale_min": world_scale_min,
		"world_scale_max": world_scale_max,
		"world_scale_sensitivity": world_scale_sensitivity,
		"world_rotation_sensitivity": world_rotation_sensitivity,
		"world_grab_move_factor": world_grab_move_factor,
		"world_grab_smooth_factor": world_grab_smooth_factor,
		"invert_two_hand_scale_direction": invert_two_hand_scale_direction,
		"show_two_hand_rotation_visual": show_two_hand_rotation_visual,
		"two_hand_left_action": two_hand_left_action,
		"two_hand_right_action": two_hand_right_action,
		"enable_one_hand_world_grab": enable_one_hand_world_grab,
		"enable_one_hand_world_rotate": enable_one_hand_world_rotate,
		"apply_one_hand_release_velocity": apply_one_hand_release_velocity,
		"one_hand_world_move_sensitivity": one_hand_world_move_sensitivity,
		"invert_one_hand_grab_direction": invert_one_hand_grab_direction,
		"show_one_hand_grab_visual": show_one_hand_grab_visual,
		"invert_one_hand_rotation": invert_one_hand_rotation,
		"jump_enabled": jump_enabled,
		"jump_impulse": jump_impulse,
		"jump_cooldown": jump_cooldown,
		"player_gravity_enabled": player_gravity_enabled,
		"player_drag_force": player_drag_force,
		"auto_respawn_enabled": auto_respawn_enabled,
		"auto_respawn_distance": auto_respawn_distance,
		"hard_respawn_resets_settings": hard_respawn_resets_settings,
		# V2 Settings
		"enable_two_hand_grab_v2": enable_two_hand_grab_v2,
		"v2_scale_enabled": v2_scale_enabled,
		"v2_rotation_enabled": v2_rotation_enabled,
		"v2_world_scale_min": v2_world_scale_min,
		"v2_world_scale_max": v2_world_scale_max,
		"v2_left_action": v2_left_action,
		"v2_right_action": v2_right_action,
		"v2_show_visual": v2_show_visual,
		"v2_debug_logs": v2_debug_logs,
	}


func _apply_settings_snapshot(data: Dictionary) -> void:
	locomotion_mode = data.get("locomotion_mode", locomotion_mode)
	locomotion_speed = data.get("locomotion_speed", locomotion_speed)
	locomotion_deadzone = data.get("locomotion_deadzone", locomotion_deadzone)
	invert_locomotion_x = data.get("invert_locomotion_x", invert_locomotion_x)
	invert_locomotion_y = data.get("invert_locomotion_y", invert_locomotion_y)
	turn_mode = data.get("turn_mode", turn_mode)
	snap_turn_angle = data.get("snap_turn_angle", snap_turn_angle)
	smooth_turn_speed = data.get("smooth_turn_speed", smooth_turn_speed)
	turn_deadzone = data.get("turn_deadzone", turn_deadzone)
	snap_turn_cooldown = data.get("snap_turn_cooldown", snap_turn_cooldown)
	invert_turn_x = data.get("invert_turn_x", invert_turn_x)
	ui_scroll_steals_stick = data.get("ui_scroll_steals_stick", ui_scroll_steals_stick)
	ui_scroll_deadzone = data.get("ui_scroll_deadzone", ui_scroll_deadzone)
	ui_scroll_wheel_factor = data.get("ui_scroll_wheel_factor", ui_scroll_wheel_factor)
	hand_assignment = data.get("hand_assignment", hand_assignment)
	enable_two_hand_world_scale = data.get("enable_two_hand_world_scale", enable_two_hand_world_scale)
	enable_two_hand_world_rotation = data.get("enable_two_hand_world_rotation", enable_two_hand_world_rotation)
	world_scale_min = data.get("world_scale_min", world_scale_min)
	world_scale_max = data.get("world_scale_max", world_scale_max)
	world_scale_sensitivity = data.get("world_scale_sensitivity", world_scale_sensitivity)
	world_rotation_sensitivity = data.get("world_rotation_sensitivity", world_rotation_sensitivity)
	world_grab_move_factor = data.get("world_grab_move_factor", world_grab_move_factor)
	world_grab_smooth_factor = data.get("world_grab_smooth_factor", world_grab_smooth_factor)
	invert_two_hand_scale_direction = data.get("invert_two_hand_scale_direction", invert_two_hand_scale_direction)
	show_two_hand_rotation_visual = data.get("show_two_hand_rotation_visual", show_two_hand_rotation_visual)
	two_hand_left_action = data.get("two_hand_left_action", two_hand_left_action)
	two_hand_right_action = data.get("two_hand_right_action", two_hand_right_action)
	enable_one_hand_world_grab = data.get("enable_one_hand_world_grab", enable_one_hand_world_grab)
	enable_one_hand_world_rotate = data.get("enable_one_hand_world_rotate", enable_one_hand_world_rotate)
	apply_one_hand_release_velocity = data.get("apply_one_hand_release_velocity", apply_one_hand_release_velocity)
	one_hand_world_move_sensitivity = data.get("one_hand_world_move_sensitivity", one_hand_world_move_sensitivity)
	invert_one_hand_grab_direction = data.get("invert_one_hand_grab_direction", invert_one_hand_grab_direction)
	show_one_hand_grab_visual = data.get("show_one_hand_grab_visual", show_one_hand_grab_visual)
	invert_one_hand_rotation = data.get("invert_one_hand_rotation", invert_one_hand_rotation)
	jump_enabled = data.get("jump_enabled", jump_enabled)
	jump_impulse = data.get("jump_impulse", jump_impulse)
	jump_cooldown = data.get("jump_cooldown", jump_cooldown)
	player_gravity_enabled = data.get("player_gravity_enabled", player_gravity_enabled)
	player_drag_force = data.get("player_drag_force", player_drag_force)
	auto_respawn_enabled = data.get("auto_respawn_enabled", auto_respawn_enabled)
	auto_respawn_distance = data.get("auto_respawn_distance", auto_respawn_distance)
	hard_respawn_resets_settings = data.get("hard_respawn_resets_settings", hard_respawn_resets_settings)
	# V2 Settings
	enable_two_hand_grab_v2 = data.get("enable_two_hand_grab_v2", enable_two_hand_grab_v2)
	v2_scale_enabled = data.get("v2_scale_enabled", v2_scale_enabled)
	v2_rotation_enabled = data.get("v2_rotation_enabled", v2_rotation_enabled)
	v2_world_scale_min = data.get("v2_world_scale_min", v2_world_scale_min)
	v2_world_scale_max = data.get("v2_world_scale_max", v2_world_scale_max)
	v2_left_action = data.get("v2_left_action", v2_left_action)
	v2_right_action = data.get("v2_right_action", v2_right_action)
	v2_show_visual = data.get("v2_show_visual", v2_show_visual)
	v2_debug_logs = data.get("v2_debug_logs", v2_debug_logs)
	_apply_player_gravity()
	_apply_player_drag()


func _update_one_hand_visual() -> void:
	if not _one_hand_anchor_mesh:
		return
	_set_one_hand_visual_style()
	_one_hand_anchor_mesh.visible = show_one_hand_grab_visual and _one_hand_grab_active
	var anchor_world := _one_hand_grab_anchor
	if _one_hand_anchor_mesh.visible:
		_one_hand_anchor_mesh.global_transform.origin = anchor_world
	if _one_hand_line_mesh and _one_hand_line_mesh.mesh is ImmediateMesh:
		var im := _one_hand_line_mesh.mesh as ImmediateMesh
		if show_one_hand_grab_visual and _one_hand_grab_active and _one_hand_controller:
			var hand_pos := _one_hand_controller.global_position
			var anchor_local := _visual_root.to_local(anchor_world) if _visual_root else anchor_world
			var hand_local := _visual_root.to_local(hand_pos) if _visual_root else hand_pos
			im.clear_surfaces()
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			im.surface_add_vertex(anchor_local)
			im.surface_add_vertex(hand_local)
			im.surface_end()
			_one_hand_line_mesh.visible = true
		else:
			im.clear_surfaces()
			_one_hand_line_mesh.visible = false


func _update_two_hand_visual(left_pos: Vector3, right_pos: Vector3, mid: Vector3) -> void:
	if not show_two_hand_rotation_visual:
		_clear_two_hand_visual()
		return
	_ensure_visuals()
	if _two_hand_line_mesh and _two_hand_line_mesh.mesh is ImmediateMesh:
		var im := _two_hand_line_mesh.mesh as ImmediateMesh
		im.clear_surfaces()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		var lp := player_body.to_local(left_pos)
		var rp := player_body.to_local(right_pos)
		im.surface_add_vertex(lp)
		im.surface_add_vertex(rp)
		im.surface_end()
		_two_hand_line_mesh.visible = true
	if _two_hand_midpoint_line_mesh and _two_hand_midpoint_line_mesh.mesh is ImmediateMesh:
		var im2 := _two_hand_midpoint_line_mesh.mesh as ImmediateMesh
		im2.clear_surfaces()
		im2.surface_begin(Mesh.PRIMITIVE_LINES)
		var la_world := _world_grab_target_left_anchor
		var ra_world := _world_grab_target_right_anchor
		if la_world != Vector3.ZERO and player_body:
			var la := player_body.to_local(la_world)
			var lc_world := Vector3(la_world.x, left_pos.y, la_world.z) # show vertical-only offset
			var lc := player_body.to_local(lc_world)
			im2.surface_add_vertex(la)
			im2.surface_add_vertex(lc)
		if ra_world != Vector3.ZERO and player_body:
			var ra := player_body.to_local(ra_world)
			var rc_world := Vector3(ra_world.x, right_pos.y, ra_world.z) # show vertical-only offset
			var rc := player_body.to_local(rc_world)
			im2.surface_add_vertex(ra)
			im2.surface_add_vertex(rc)
		im2.surface_end()
		_two_hand_midpoint_line_mesh.visible = true
	if _two_hand_anchor_xz_line_mesh and _two_hand_anchor_xz_line_mesh.mesh is ImmediateMesh:
		var im3 := _two_hand_anchor_xz_line_mesh.mesh as ImmediateMesh
		im3.clear_surfaces()
		im3.surface_begin(Mesh.PRIMITIVE_LINES)
		var la_world2 := _world_grab_target_left_anchor
		var ra_world2 := _world_grab_target_right_anchor
		if la_world2 != Vector3.ZERO and player_body:
			var la_ground := la_world2
			var lc_ground := Vector3(left_pos.x, la_world2.y, left_pos.z)
			im3.surface_add_vertex(player_body.to_local(la_ground))
			im3.surface_add_vertex(player_body.to_local(lc_ground))
		if ra_world2 != Vector3.ZERO and player_body:
			var ra_ground := ra_world2
			var rc_ground := Vector3(right_pos.x, ra_world2.y, right_pos.z)
			im3.surface_add_vertex(player_body.to_local(ra_ground))
			im3.surface_add_vertex(player_body.to_local(rc_ground))
		im3.surface_end()
		_two_hand_anchor_xz_line_mesh.visible = true
	if _two_hand_midpoint_mesh:
		_two_hand_midpoint_mesh.visible = true
		var xf := _two_hand_midpoint_mesh.global_transform
		xf.origin = mid
		var dir := right_pos - left_pos
		if dir.length_squared() > 0.000001:
			var up := _get_player_up()
			if abs(dir.normalized().dot(up)) > 0.98:
				up = Vector3.UP
			var basis := Basis.IDENTITY.looking_at(dir.normalized(), up)
			xf.basis = basis.scaled(Vector3.ONE * XRServer.world_scale)
		else:
			var basis_src := player_body.global_transform.basis if player_body else Basis.IDENTITY
			xf.basis = basis_src.scaled(Vector3.ONE * XRServer.world_scale)
		_two_hand_midpoint_mesh.global_transform = xf


func _clear_two_hand_visual() -> void:
	if _two_hand_line_mesh and _two_hand_line_mesh.mesh is ImmediateMesh:
		var im := _two_hand_line_mesh.mesh as ImmediateMesh
		im.clear_surfaces()
	if _two_hand_line_mesh:
		_two_hand_line_mesh.visible = false
	if _two_hand_midpoint_line_mesh and _two_hand_midpoint_line_mesh.mesh is ImmediateMesh:
		var im2 := _two_hand_midpoint_line_mesh.mesh as ImmediateMesh
		im2.clear_surfaces()
	if _two_hand_midpoint_line_mesh:
		_two_hand_midpoint_line_mesh.visible = false
	if _two_hand_anchor_xz_line_mesh and _two_hand_anchor_xz_line_mesh.mesh is ImmediateMesh:
		var im3 := _two_hand_anchor_xz_line_mesh.mesh as ImmediateMesh
		im3.clear_surfaces()
	if _two_hand_anchor_xz_line_mesh:
		_two_hand_anchor_xz_line_mesh.visible = false
	if _two_hand_midpoint_mesh:
		_two_hand_midpoint_mesh.visible = false
	_world_grab_left_anchor = Vector3.ZERO
	_world_grab_right_anchor = Vector3.ZERO


func _reanchor_player(anchor_point: Vector3) -> void:
	if not player_body:
		return
	var current_anchor := xr_camera.global_transform.origin if xr_camera else player_body.global_transform.origin
	var delta := current_anchor - anchor_point
	if delta.length_squared() < 0.00000001:
		return
	var xf := player_body.global_transform
	var lv := player_body.linear_velocity
	var av := player_body.angular_velocity
	xf.origin -= delta
	player_body.global_transform = xf
	player_body.linear_velocity = lv
	player_body.angular_velocity = av


func _set_one_hand_visual_style() -> void:
	# Anchored = cyan, Relative = orange
	var anchor_color := Color(0.3, 0.9, 1.0, 0.8)
	var line_color := Color(0.3, 0.9, 1.0, 0.9)
	if one_hand_grab_mode == OneHandGrabMode.RELATIVE:
		anchor_color = Color(1.0, 0.65, 0.2, 0.85)
		line_color = Color(1.0, 0.5, 0.1, 0.95)
	if _one_hand_anchor_mat:
		_one_hand_anchor_mat.albedo_color = anchor_color
	if _one_hand_line_mat:
		_one_hand_line_mat.albedo_color = line_color


func _check_auto_respawn() -> void:
	if not auto_respawn_enabled or not player_body:
		return
		
	# Scale distance check with world scale to prevent false positives when zoomed in
	var threshold := auto_respawn_distance * XRServer.world_scale
	var dist := player_body.global_transform.origin.distance_to(_spawn_transform.origin)
	
	if dist > threshold:
		print("PlayerMovementComponent: Auto-respawn TRIGGERED! Dist: %.2f, Threshold: %.2f, Enabled: %s" % [dist, threshold, auto_respawn_enabled])
		respawn(hard_respawn_resets_settings)


func _check_autojoin() -> void:
	# Early exit if disabled or already triggered
	if not autojoin_enabled:
		return
	if _autojoin_triggered:
		return
	if not player_body:
		_autojoin_log("ERROR: player_body is null")
		return
	if _initial_spawn_position == Vector3.ZERO:
		_autojoin_log("ERROR: _initial_spawn_position is Vector3.ZERO - was setup() called?")
		return
	
	# Check if already in a Nakama match
	var nakama_manager = get_node_or_null("/root/NakamaManager")
	if nakama_manager and not nakama_manager.current_match_id.is_empty():
		_autojoin_log("Already in Nakama match: %s - skipping" % nakama_manager.current_match_id)
		_autojoin_triggered = true
		return
	
	# Check if already connected to LiveKit
	var livekit_manager = _find_livekit_manager()
	if livekit_manager and livekit_manager.has_method("is_room_connected") and livekit_manager.is_room_connected():
		_autojoin_log("Already connected to LiveKit - skipping")
		_autojoin_triggered = true
		return
	
	# Check distance from spawn
	var dist := player_body.global_position.distance_to(_initial_spawn_position)
	if dist >= autojoin_distance_threshold:
		_autojoin_triggered = true
		_autojoin_log("========================================")
		_autojoin_log("TRIGGERED! Distance: %.2fm (threshold: %.2fm)" % [dist, autojoin_distance_threshold])
		_autojoin_log("Target room: '%s'" % autojoin_room_name)
		_autojoin_log("========================================")
		_trigger_autojoin()


func _autojoin_log(message: String) -> void:
	"""Log autojoin messages if debug logging is enabled"""
	if autojoin_debug_logs:
		print("[Autojoin] %s" % message)


func _trigger_autojoin() -> void:
	"""Trigger autojoin to Nakama match and LiveKit room"""
	var nakama_manager = get_node_or_null("/root/NakamaManager")
	var livekit_manager = _find_livekit_manager()
	
	# Validate managers
	if not nakama_manager:
		push_warning("[Autojoin] ERROR: NakamaManager not found")
		return
	if not livekit_manager:
		push_warning("[Autojoin] ERROR: LiveKitManager not found")
		return
	
	_autojoin_log("Found NakamaManager: %s" % nakama_manager)
	_autojoin_log("Found LiveKitManager: %s" % livekit_manager)
	
	# Check Nakama connection status
	if not nakama_manager.is_socket_connected:
		push_warning("[Autojoin] ERROR: Nakama socket not connected")
		return
	
	var user_id: String = ""
	if "local_user_id" in nakama_manager:
		user_id = nakama_manager.local_user_id
	
	if user_id.is_empty():
		push_warning("[Autojoin] ERROR: No Nakama user ID available")
		return
	
	_autojoin_log("User ID: %s" % user_id)
	
	# Connect signals for match list response (one-shot)
	if nakama_manager.has_signal("match_list_received"):
		if not nakama_manager.match_list_received.is_connected(_on_autojoin_match_list):
			nakama_manager.match_list_received.connect(_on_autojoin_match_list, CONNECT_ONE_SHOT)
	
	if nakama_manager.has_signal("match_joined"):
		if not nakama_manager.match_joined.is_connected(_on_autojoin_nakama_joined):
			nakama_manager.match_joined.connect(_on_autojoin_nakama_joined, CONNECT_ONE_SHOT)
	
	if nakama_manager.has_signal("match_created"):
		if not nakama_manager.match_created.is_connected(_on_autojoin_nakama_created):
			nakama_manager.match_created.connect(_on_autojoin_nakama_created, CONNECT_ONE_SHOT)
	
	# Request match list to find existing room or create new one
	_autojoin_log("Requesting match list from Nakama...")
	nakama_manager.list_matches()


func _on_autojoin_match_list(matches: Array) -> void:
	"""Handle match list response - join existing or create new"""
	_autojoin_log("Received %d matches from Nakama" % matches.size())
	
	var nakama_manager = get_node_or_null("/root/NakamaManager")
	if not nakama_manager:
		return
	
	# Look for a match with our target room name
	var target_match_id: String = ""
	for match_data in matches:
		var label: String = match_data.get("label", "")
		var match_id: String = match_data.get("match_id", "")
		var size: int = match_data.get("size", 0)
		_autojoin_log("  - Match: '%s' (ID: %s, players: %d)" % [label, match_id.substr(0, 8) if match_id.length() > 8 else match_id, size])
		
		if label == autojoin_room_name or label.begins_with(autojoin_room_name):
			target_match_id = match_id
			_autojoin_log("Found matching room: '%s'" % label)
			break
	
	if not target_match_id.is_empty():
		# Join existing match
		_autojoin_log("Joining existing Nakama match: %s" % target_match_id)
		nakama_manager.join_match(target_match_id)
	else:
		# Create new match
		_autojoin_log("No matching room found - creating new match")
		nakama_manager.create_match()


func _on_autojoin_nakama_created(match_id: String, label: String) -> void:
	"""Handle Nakama match created"""
	_autojoin_log("Nakama match CREATED: %s (label: %s)" % [match_id, label])
	_connect_to_livekit_after_nakama(label if not label.is_empty() else autojoin_room_name)


func _on_autojoin_nakama_joined(match_id: String) -> void:
	"""Handle Nakama match joined"""
	_autojoin_log("Nakama match JOINED: %s" % match_id)
	_connect_to_livekit_after_nakama(autojoin_room_name)


func _connect_to_livekit_after_nakama(room_name: String) -> void:
	"""Connect to LiveKit after Nakama match is ready"""
	var livekit_manager = _find_livekit_manager()
	var nakama_manager = get_node_or_null("/root/NakamaManager")
	
	if not livekit_manager:
		push_warning("[Autojoin] ERROR: Cannot connect to LiveKit - manager not found")
		return
	
	var user_id: String = ""
	if nakama_manager and "local_user_id" in nakama_manager:
		user_id = nakama_manager.local_user_id
	
	if user_id.is_empty():
		push_warning("[Autojoin] ERROR: Cannot connect to LiveKit - no user ID")
		return
	
	# Generate token and connect to LiveKit
	var token = _generate_livekit_token(user_id, room_name)
	var server_url = "wss://godotkit-mjbmdjse.livekit.cloud"
	
	_autojoin_log("Connecting to LiveKit...")
	_autojoin_log("  Server: %s" % server_url)
	_autojoin_log("  Room: %s" % room_name)
	_autojoin_log("  User: %s" % user_id)
	
	livekit_manager.connect_to_room(server_url, token)
	_autojoin_log("✅ Autojoin complete!")


func _find_livekit_manager() -> Node:
	"""Find the LiveKit manager in the scene"""
	var root = get_tree().root
	# Look for LiveKitWrapper autoload or in scene
	var livekit = get_node_or_null("/root/LiveKitWrapper")
	if livekit:
		return livekit
	# Fallback: search scene tree
	return _find_node_by_script(root, "livekit_wrapper.gd")


func _find_node_by_script(node: Node, script_name: String) -> Node:
	if node.get_script():
		var script_path = node.get_script().resource_path
		if script_name in script_path:
			return node
	for child in node.get_children():
		var result = _find_node_by_script(child, script_name)
		if result:
			return result
	return null


func _generate_livekit_token(participant_id: String, room_name: String) -> String:
	"""Generate a LiveKit JWT access token using HS256"""
	const API_KEY = "APIbSEA2MXzP8Mf"
	const API_SECRET = "Kqw1FLCX3rq2IWbuWjilBMlgbODqlzxTkgyzKrzuF6I"
	const TOKEN_VALIDITY_HOURS = 24
	
	var now = Time.get_unix_time_from_system()
	var expire_time = now + (TOKEN_VALIDITY_HOURS * 3600)
	
	var header = {"alg": "HS256", "typ": "JWT"}
	var claims = {
		"exp": expire_time,
		"iss": API_KEY,
		"nbf": now - 60,
		"sub": participant_id,
		"video": {
			"room": room_name,
			"roomJoin": true,
			"canPublish": true,
			"canSubscribe": true
		}
	}
	
	var header_b64 = _base64url_encode(JSON.stringify(header).to_utf8_buffer())
	var payload_b64 = _base64url_encode(JSON.stringify(claims).to_utf8_buffer())
	var signing_input = header_b64 + "." + payload_b64
	var signature = _hmac_sha256(signing_input.to_utf8_buffer(), API_SECRET.to_utf8_buffer())
	
	return signing_input + "." + _base64url_encode(signature)


func _base64url_encode(data: PackedByteArray) -> String:
	var b64 = Marshalls.raw_to_base64(data)
	b64 = b64.replace("+", "-").replace("/", "_").replace("=", "")
	return b64


func _hmac_sha256(message: PackedByteArray, key: PackedByteArray) -> PackedByteArray:
	var ctx = HMACContext.new()
	ctx.start(HashingContext.HASH_SHA256, key)
	ctx.update(message)
	return ctx.finish()


func respawn(hard: bool = false) -> void:
	if not player_body:
		return
	print("PlayerMovementComponent: RESPAWN CALLED! Stack trace:")
	print_stack()
	player_body.global_transform = _spawn_transform
	player_body.linear_velocity = Vector3.ZERO
	player_body.angular_velocity = Vector3.ZERO
	if hard:
		# Reset world scale and player scale (body + hands + head)
		XRServer.world_scale = 1.0
		_manual_player_scale = 1.0
		var player_root := player_body.get_parent()
		if player_root and player_root.has_method("set_player_scale"):
			player_root.set_player_scale(_manual_player_scale)
		else:
			_apply_manual_player_scale()
		_reset_physics_hands()
		_world_grab_initial_scale = 1.0
		_world_grab_current_scale = 1.0
		_apply_settings_snapshot(_initial_settings)
		_apply_player_gravity()
		_apply_player_drag()


func _reset_physics_hands() -> void:
	var player_root := player_body.get_parent()
	if not player_root:
		return
	var left_hand := player_root.get_node_or_null("PhysicsHandLeft") as RigidBody3D
	var right_hand := player_root.get_node_or_null("PhysicsHandRight") as RigidBody3D
	if left_hand and left_controller:
		left_hand.linear_velocity = Vector3.ZERO
		left_hand.angular_velocity = Vector3.ZERO
		left_hand.global_position = left_controller.global_position
		left_hand.global_rotation = left_controller.global_rotation
	if right_hand and right_controller:
		right_hand.linear_velocity = Vector3.ZERO
		right_hand.angular_velocity = Vector3.ZERO
		right_hand.global_position = right_controller.global_position
		right_hand.global_rotation = right_controller.global_rotation


# === Two-Hand Grab V2 Helpers ===

func _setup_two_hand_grab_v2() -> void:
	"""Create and configure the V2 two-hand grab component."""
	if _two_hand_grab_v2:
		return  # Already setup
	
	_two_hand_grab_v2 = TwoHandGrabV2.new()
	_two_hand_grab_v2.name = "TwoHandGrabV2"
	add_child(_two_hand_grab_v2)
	_two_hand_grab_v2.setup(player_body, left_controller, right_controller, xr_camera)
	_sync_v2_settings()
	print("PlayerMovementComponent: Two-Hand Grab V2 component initialized")


func _sync_v2_settings() -> void:
	"""Sync V2 component settings with exported values."""
	if not _two_hand_grab_v2:
		return
	
	_two_hand_grab_v2.scale_enabled = v2_scale_enabled
	_two_hand_grab_v2.rotation_enabled = v2_rotation_enabled
	_two_hand_grab_v2.world_scale_min = v2_world_scale_min
	_two_hand_grab_v2.world_scale_max = v2_world_scale_max
	_two_hand_grab_v2.left_action = v2_left_action
	_two_hand_grab_v2.right_action = v2_right_action
	_two_hand_grab_v2.show_visual = v2_show_visual
	_two_hand_grab_v2.debug_logs = v2_debug_logs


# === Two-Hand Grab V3 Helpers ===

func _setup_two_hand_grab_v3() -> void:
	"""Create and configure the V3 two-hand grab component."""
	if _two_hand_grab_v3:
		return  # Already setup
	
	_two_hand_grab_v3 = TwoHandGrabV3.new()
	_two_hand_grab_v3.name = "TwoHandGrabV3"
	add_child(_two_hand_grab_v3)
	_two_hand_grab_v3.setup(player_body, left_controller, right_controller, xr_camera)
	_sync_v3_settings()
	print("PlayerMovementComponent: Two-Hand Grab V3 component initialized")


func _sync_v3_settings() -> void:
	"""Sync V3 component settings with exported values."""
	if not _two_hand_grab_v3:
		return
	
	_two_hand_grab_v3.scale_sensitivity = v3_scale_sensitivity
	_two_hand_grab_v3.rotation_sensitivity = v3_rotation_sensitivity
	_two_hand_grab_v3.translation_sensitivity = v3_translation_sensitivity
	_two_hand_grab_v3.smoothing = v3_smoothing
	_two_hand_grab_v3.invert_scale = v3_invert_scale
	_two_hand_grab_v3.world_scale_min = v3_world_scale_min
	_two_hand_grab_v3.world_scale_max = v3_world_scale_max
	_two_hand_grab_v3.left_action = v3_left_action
	_two_hand_grab_v3.right_action = v3_right_action
	_two_hand_grab_v3.show_visual = v3_show_visual
	_two_hand_grab_v3.debug_logs = v3_debug_logs
