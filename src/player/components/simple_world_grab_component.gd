class_name SimpleWorldGrabComponent
extends Node

## Simple World Grab Component
## A minimal world grab implementation that works anywhere without Area3D.
## Add this to your XRPlayer and call setup() with the required references.

signal grab_started()
signal grab_ended()

## Enable/disable the world grab functionality
@export var enabled: bool = true

## Minimum world scale
@export var world_scale_min: float = 0.1

## Maximum world scale  
@export var world_scale_max: float = 1000.0

## Grip threshold for detecting grab
@export var grip_threshold: float = 0.7

## Smoothing factor for scale changes (0 = instant, 1 = no change)
@export var scale_smoothing: float = 0.0

## Smoothing factor for noisy hand-distance input (0 = instant, 1 = no change)
@export var hand_distance_smoothing: float = 0.65

## Ignore tiny distance noise around neutral pinch scale to reduce 1x drift
@export_range(0.0, 0.1, 0.001) var scale_ratio_deadzone: float = 0.01

## Show a floating label between hands displaying current scale multiplier
@export var show_scale_label: bool = true

## Debug logging
@export var debug_logs: bool = false

# References (set via setup())
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var left_controller: XRController3D
var right_controller: XRController3D
var _player_root: Node = null

# Grab state
var _left_grabbing: bool = false
var _right_grabbing: bool = false
var _left_handle: Node3D
var _right_handle: Node3D

# Two-hand grab state (for stable scaling)
var _two_hand_active: bool = false
var _initial_hand_distance: float = 0.0
var _initial_world_scale: float = 1.0
var _target_scale: float = 1.0
var _smoothed_hand_distance: float = 0.0
var _base_world_scale: float = 1.0
var _scale_label: Label3D = null


func setup(p_origin: XROrigin3D, p_camera: XRCamera3D, p_left: XRController3D, p_right: XRController3D) -> void:
	xr_origin = p_origin
	xr_camera = p_camera
	left_controller = p_left
	right_controller = p_right
	_player_root = get_parent()
	_base_world_scale = maxf(XRServer.world_scale, 0.0001)
	if _player_root and _player_root.has_method("set_scale_rig_with_world_scale"):
		_player_root.call("set_scale_rig_with_world_scale", true)
	if debug_logs:
		print("SimpleWorldGrabComponent: Setup complete")


func _physics_process(delta: float) -> void:
	if not enabled:
		_release_all()
		return
	
	if not xr_origin or not left_controller or not right_controller:
		return
	
	# Check grip inputs
	var left_grip = left_controller.get_float("grip") if left_controller.get_is_active() else 0.0
	var right_grip = right_controller.get_float("grip") if right_controller.get_is_active() else 0.0
	
	var left_pressed = left_grip > grip_threshold
	var right_pressed = right_grip > grip_threshold
	
	# Handle left grab
	if left_pressed and not _left_grabbing:
		_start_grab_left()
	elif not left_pressed and _left_grabbing:
		_end_grab_left()
	
	# Handle right grab
	if right_pressed and not _right_grabbing:
		_start_grab_right()
	elif not right_pressed and _right_grabbing:
		_end_grab_right()
	
	# Validate handles
	if _left_handle and not is_instance_valid(_left_handle):
		_left_handle = null
		_left_grabbing = false
	if _right_handle and not is_instance_valid(_right_handle):
		_right_handle = null
		_right_grabbing = false
	
	# Check for two-hand grab state changes
	var both_grabbing = _left_handle != null and _right_handle != null
	if both_grabbing and not _two_hand_active:
		_start_two_hand_grab()
	elif not both_grabbing and _two_hand_active:
		_end_two_hand_grab()
	
	# Process movement
	if _left_handle or _right_handle:
		_process_world_grab(delta)


func _start_grab_left() -> void:
	var left_xform := left_controller.global_transform
	if not _is_finite_transform3d(left_xform):
		if debug_logs:
			push_warning("SimpleWorldGrab: Skipping left grab start due to non-finite controller transform")
		return
	_left_grabbing = true
	_left_handle = Node3D.new()
	get_tree().root.add_child(_left_handle)
	_left_handle.global_transform = left_xform
	if debug_logs:
		print("SimpleWorldGrab: Left grab started")
	if not _right_grabbing:
		grab_started.emit()


func _end_grab_left() -> void:
	_left_grabbing = false
	if _left_handle and is_instance_valid(_left_handle):
		_left_handle.queue_free()
	_left_handle = null
	if debug_logs:
		print("SimpleWorldGrab: Left grab ended")
	if not _right_grabbing:
		grab_ended.emit()


func _start_grab_right() -> void:
	var right_xform := right_controller.global_transform
	if not _is_finite_transform3d(right_xform):
		if debug_logs:
			push_warning("SimpleWorldGrab: Skipping right grab start due to non-finite controller transform")
		return
	_right_grabbing = true
	_right_handle = Node3D.new()
	get_tree().root.add_child(_right_handle)
	_right_handle.global_transform = right_xform
	if debug_logs:
		print("SimpleWorldGrab: Right grab started")
	if not _left_grabbing:
		grab_started.emit()


func _end_grab_right() -> void:
	_right_grabbing = false
	if _right_handle and is_instance_valid(_right_handle):
		_right_handle.queue_free()
	_right_handle = null
	if debug_logs:
		print("SimpleWorldGrab: Right grab ended")
	if not _left_grabbing:
		grab_ended.emit()


func _start_two_hand_grab() -> void:
	_two_hand_active = true
	# Capture initial state for stable scaling
	# World-space controller positions are scale-independent in Godot XR
	# (XRNode3D divides by world_scale, origin basis multiplies by it → they cancel)
	var left_pos = left_controller.global_position
	var right_pos = right_controller.global_position
	if not _is_finite_vector3(left_pos) or not _is_finite_vector3(right_pos):
		_two_hand_active = false
		if debug_logs:
			push_warning("SimpleWorldGrab: Skipping two-hand start due to non-finite hand positions")
		return
	_initial_hand_distance = (right_pos - left_pos).slide(Vector3.UP).length()
	if not is_finite(_initial_hand_distance):
		_two_hand_active = false
		if debug_logs:
			push_warning("SimpleWorldGrab: Skipping two-hand start due to non-finite hand distance")
		return
	_initial_world_scale = XRServer.world_scale
	if not is_finite(_initial_world_scale):
		_initial_world_scale = 1.0
	_target_scale = _initial_world_scale
	_smoothed_hand_distance = _initial_hand_distance
	if show_scale_label:
		_create_scale_label()
	if debug_logs:
		print("SimpleWorldGrab: Two-hand grab started, initial distance: ", _initial_hand_distance)


func _end_two_hand_grab() -> void:
	_two_hand_active = false
	_destroy_scale_label()
	if debug_logs:
		print("SimpleWorldGrab: Two-hand grab ended")


func _release_all() -> void:
	if _left_grabbing:
		_end_grab_left()
	if _right_grabbing:
		_end_grab_right()


func _process_world_grab(delta: float) -> void:
	var offset = Vector3.ZERO
	
	if _left_handle and not _right_handle:
		# Left hand only - simple movement
		var left_pos := left_controller.global_position
		var left_anchor := _left_handle.global_position
		if _is_finite_vector3(left_pos) and _is_finite_vector3(left_anchor):
			offset = left_pos - left_anchor
		
	elif _right_handle and not _left_handle:
		# Right hand only - simple movement
		var right_pos := right_controller.global_position
		var right_anchor := _right_handle.global_position
		if _is_finite_vector3(right_pos) and _is_finite_vector3(right_anchor):
			offset = right_pos - right_anchor
		
	elif _left_handle and _right_handle:
		# Both hands - rotation and scaling
		var left_pos = left_controller.global_position
		var right_pos = right_controller.global_position
		if not _is_finite_vector3(left_pos) or not _is_finite_vector3(right_pos):
			return
		var up_vector = Vector3.UP
		
		# Current hand vector (flattened)
		var current_hand_vector = (right_pos - left_pos).slide(up_vector)
		var current_hand_distance = current_hand_vector.length()
		var current_mid = (left_pos + right_pos) * 0.5
		
		# Handle positions (for rotation reference)
		var left_grab_pos = _left_handle.global_position
		var right_grab_pos = _right_handle.global_position
		if not _is_finite_vector3(left_grab_pos) or not _is_finite_vector3(right_grab_pos):
			return
		var grab_vector = (right_grab_pos - left_grab_pos).slide(up_vector)
		var grab_mid = (left_grab_pos + right_grab_pos) * 0.5
		
		# Apply rotation based on handle vs hand vectors
		if grab_vector.length() > 0.01 and current_hand_vector.length() > 0.01:
			var angle = grab_vector.signed_angle_to(current_hand_vector, up_vector)
			if is_finite(angle):
				_rotate_origin(angle)
		
		# Scale based on world-space distance ratio (scale-independent in XR)
		if _initial_hand_distance > 0.05 and current_hand_distance > 0.05:
			var dist_smooth_t := 1.0 - pow(hand_distance_smoothing, delta * 60.0)
			_smoothed_hand_distance = lerp(_smoothed_hand_distance, current_hand_distance, dist_smooth_t)
			var safe_distance := maxf(_smoothed_hand_distance, 0.0001)
			var scale_ratio = _initial_hand_distance / safe_distance
			if not is_finite(scale_ratio):
				scale_ratio = 1.0
			if absf(scale_ratio - 1.0) < scale_ratio_deadzone:
				scale_ratio = 1.0
			_target_scale = clamp(_initial_world_scale * scale_ratio, world_scale_min, world_scale_max)
			if not is_finite(_target_scale):
				_target_scale = XRServer.world_scale
			
			# Frame-rate-independent exponential smoothing
			var new_scale = _target_scale
			if scale_smoothing > 0.001:
				var smooth_t := 1.0 - pow(scale_smoothing, delta * 60.0)
				var current_scale = XRServer.world_scale
				new_scale = lerp(current_scale, _target_scale, smooth_t)
			_set_world_scale_immediate(new_scale)
		
		# Calculate offset from midpoints
		offset = current_mid - grab_mid
		
		# Update scale label position and text
		if _scale_label and is_instance_valid(_scale_label):
			# Scale multiplier: how big the player is relative to the baseline scale.
			var scale_multiplier = _get_player_scale_multiplier_from_base()
			if not is_finite(scale_multiplier):
				scale_multiplier = 1.0
			_scale_label.text = "x%.2f" % scale_multiplier
			# Position above the midpoint, offset scales with player size
			var label_offset = 0.06 * scale_multiplier
			var label_pos: Vector3 = current_mid + Vector3.UP * label_offset
			if _is_finite_vector3(label_pos):
				_scale_label.global_position = label_pos
			# Scale the label so it remains readable at any player size
			var label_scale_val = maxf(scale_multiplier, 0.01)
			if is_finite(label_scale_val):
				_scale_label.scale = Vector3.ONE * label_scale_val
	
	# Apply movement
	if _is_finite_vector3(offset) and offset.length() > 0.001:
		xr_origin.global_transform.origin -= offset
	
	# Keep grab handles fixed in world space while grabbing.
	# This preserves the initial anchor points (e.g. cube vertices) under each hand.


func _rotate_origin(angle: float) -> void:
	if not xr_camera:
		return
	if not is_finite(angle):
		return
	if not _is_finite_vector3(xr_camera.transform.origin):
		return
	
	# Rotate around camera (matching XRTools style)
	var t1 = Transform3D()
	var t2 = Transform3D()
	var rot = Transform3D()
	
	t1.origin = -xr_camera.transform.origin
	t2.origin = xr_camera.transform.origin
	rot = rot.rotated(Vector3.DOWN, angle)
	
	var new_transform := (xr_origin.transform * t2 * rot * t1).orthonormalized()
	if _is_finite_transform3d(new_transform):
		xr_origin.transform = new_transform


func _create_scale_label() -> void:
	if _scale_label and is_instance_valid(_scale_label):
		return
	_scale_label = Label3D.new()
	_scale_label.name = "ScaleLabel"
	_scale_label.text = "x1.00"
	_scale_label.font_size = 48
	_scale_label.pixel_size = 0.001
	_scale_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_scale_label.no_depth_test = true
	_scale_label.shaded = false
	_scale_label.modulate = Color(1.0, 1.0, 1.0, 0.9)
	_scale_label.outline_size = 12
	_scale_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	get_tree().root.add_child(_scale_label)


func _get_player_scale_multiplier_from_base() -> float:
	var safe_base := maxf(_base_world_scale, 0.0001)
	var safe_current := maxf(XRServer.world_scale, 0.0001)
	if not is_finite(safe_base) or not is_finite(safe_current):
		return 1.0
	return safe_current / safe_base


func _set_world_scale_immediate(new_scale: float) -> void:
	if not is_finite(new_scale):
		return
	new_scale = clamp(new_scale, world_scale_min, world_scale_max)
	if new_scale <= 0.0001:
		return
	if is_equal_approx(new_scale, XRServer.world_scale):
		return
	XRServer.world_scale = new_scale
	if _player_root and _player_root.has_method("force_world_scale_sync"):
		_player_root.call("force_world_scale_sync")


func _is_finite_vector3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _is_finite_transform3d(t: Transform3D) -> bool:
	return _is_finite_vector3(t.origin) and _is_finite_vector3(t.basis.x) and _is_finite_vector3(t.basis.y) and _is_finite_vector3(t.basis.z)


func _destroy_scale_label() -> void:
	if _scale_label and is_instance_valid(_scale_label):
		_scale_label.queue_free()
	_scale_label = null
