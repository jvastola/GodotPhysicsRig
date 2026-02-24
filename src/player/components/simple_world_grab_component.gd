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
@export var scale_smoothing: float = 0.8

## Debug logging
@export var debug_logs: bool = false

# References (set via setup())
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var left_controller: XRController3D
var right_controller: XRController3D

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


func setup(p_origin: XROrigin3D, p_camera: XRCamera3D, p_left: XRController3D, p_right: XRController3D) -> void:
	xr_origin = p_origin
	xr_camera = p_camera
	left_controller = p_left
	right_controller = p_right
	var player_root := get_parent()
	if player_root and player_root.has_method("set_scale_rig_with_world_scale"):
		player_root.call("set_scale_rig_with_world_scale", true)
	if debug_logs:
		print("SimpleWorldGrabComponent: Setup complete")


func _physics_process(_delta: float) -> void:
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
		_process_world_grab()


func _start_grab_left() -> void:
	_left_grabbing = true
	_left_handle = Node3D.new()
	get_tree().root.add_child(_left_handle)
	_left_handle.global_transform = left_controller.global_transform
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
	_right_grabbing = true
	_right_handle = Node3D.new()
	get_tree().root.add_child(_right_handle)
	_right_handle.global_transform = right_controller.global_transform
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
	var left_pos = left_controller.global_position
	var right_pos = right_controller.global_position
	_initial_hand_distance = (right_pos - left_pos).slide(Vector3.UP).length()
	_initial_world_scale = XRServer.world_scale
	_target_scale = _initial_world_scale
	if debug_logs:
		print("SimpleWorldGrab: Two-hand grab started, initial distance: ", _initial_hand_distance)


func _end_two_hand_grab() -> void:
	_two_hand_active = false
	if debug_logs:
		print("SimpleWorldGrab: Two-hand grab ended")


func _release_all() -> void:
	if _left_grabbing:
		_end_grab_left()
	if _right_grabbing:
		_end_grab_right()


func _process_world_grab() -> void:
	var offset = Vector3.ZERO
	
	if _left_handle and not _right_handle:
		# Left hand only - simple movement
		offset = left_controller.global_position - _left_handle.global_position
		
	elif _right_handle and not _left_handle:
		# Right hand only - simple movement
		offset = right_controller.global_position - _right_handle.global_position
		
	elif _left_handle and _right_handle:
		# Both hands - rotation and scaling
		var left_pos = left_controller.global_position
		var right_pos = right_controller.global_position
		var up_vector = Vector3.UP
		
		# Current hand vector (flattened)
		var current_hand_vector = (right_pos - left_pos).slide(up_vector)
		var current_hand_distance = current_hand_vector.length()
		var current_mid = (left_pos + right_pos) * 0.5
		
		# Handle positions (for rotation reference)
		var left_grab_pos = _left_handle.global_position
		var right_grab_pos = _right_handle.global_position
		var grab_vector = (right_grab_pos - left_grab_pos).slide(up_vector)
		var grab_mid = (left_grab_pos + right_grab_pos) * 0.5
		
		# Apply rotation based on handle vs hand vectors
		if grab_vector.length() > 0.01 and current_hand_vector.length() > 0.01:
			var angle = grab_vector.signed_angle_to(current_hand_vector, up_vector)
			_rotate_origin(angle)
		
		# Apply scale based on INITIAL distance (not handle distance)
		# This prevents the feedback loop that causes jitter
		if _initial_hand_distance > 0.05 and current_hand_distance > 0.05:
			var scale_ratio = _initial_hand_distance / current_hand_distance
			_target_scale = clamp(_initial_world_scale * scale_ratio, world_scale_min, world_scale_max)
			
			# Smooth the scale change
			var current_scale = XRServer.world_scale
			var new_scale = lerp(current_scale, _target_scale, 1.0 - scale_smoothing)
			XRServer.world_scale = new_scale
		
		# Calculate offset from midpoints
		offset = current_mid - grab_mid
	
	# Apply movement
	if offset.length() > 0.001:
		xr_origin.global_transform.origin -= offset


func _rotate_origin(angle: float) -> void:
	if not xr_camera:
		return
	
	# Rotate around camera (matching XRTools style)
	var t1 = Transform3D()
	var t2 = Transform3D()
	var rot = Transform3D()
	
	t1.origin = -xr_camera.transform.origin
	t2.origin = xr_camera.transform.origin
	rot = rot.rotated(Vector3.DOWN, angle)
	
	xr_origin.transform = (xr_origin.transform * t2 * rot * t1).orthonormalized()
