extends "res://src/ui/ui_viewport_3d.gd"
class_name UIViewport3DTwoHand

## UI Viewport with Two-Hand Grab and Scale
## Extends the base UI viewport to support two-hand grabbing and scaling
## similar to TwoHandGrabCube but for UI panels

@export_group("Two Hand Settings")
@export var enable_two_hand_grab: bool = true
@export var scale_sensitivity: float = 1.0
@export var rotation_sensitivity: float = 1.0
@export var smoothing: float = 10.0
@export var min_scale: float = 0.3
@export var max_scale: float = 3.0
@export var lock_y_axis: bool = false
@export var debug_two_hand: bool = false

var _left_pointer: Node3D
var _right_pointer: Node3D
var _left_controller: XRController3D
var _right_controller: XRController3D

# Two-hand grab state
var _is_two_hand_grabbing: bool = false
var _left_pressing_me: bool = false
var _right_pressing_me: bool = false

# Grab reference data
var _initial_panel_transform: Transform3D
var _initial_left_pos: Vector3
var _initial_right_pos: Vector3
var _initial_distance: float = 1.0
var _initial_hand_vector: Vector3

# Virtual cursor distances
var _left_grab_dist: float = 0.0
var _right_grab_dist: float = 0.0

# Visual indicators
var _left_indicator: MeshInstance3D
var _right_indicator: MeshInstance3D

func _ready() -> void:
	super._ready()
	if enable_two_hand_grab:
		_find_pointers()
		_create_indicators()

func _find_pointers() -> void:
	var player = get_tree().get_first_node_in_group("xr_player")
	if player:
		if "left_hand_pointer" in player:
			_left_pointer = player.left_hand_pointer
		if "right_hand_pointer" in player:
			_right_pointer = player.right_hand_pointer
		if "left_controller" in player:
			_left_controller = player.left_controller
		if "right_controller" in player:
			_right_controller = player.right_controller

func _create_indicators() -> void:
	var sphere = SphereMesh.new()
	sphere.radius = 0.03
	sphere.height = 0.06
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 1.0, 1.0, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	
	_left_indicator = MeshInstance3D.new()
	_left_indicator.mesh = sphere
	_left_indicator.material_override = mat
	_left_indicator.visible = false
	add_child(_left_indicator)
	
	_right_indicator = MeshInstance3D.new()
	_right_indicator.mesh = sphere
	_right_indicator.material_override = mat
	_right_indicator.visible = false
	add_child(_right_indicator)
	
	# Indicators need to be top-level to stay at world coordinates
	_left_indicator.top_level = true
	_right_indicator.top_level = true

func _exit_tree() -> void:
	if _left_indicator: _left_indicator.queue_free()
	if _right_indicator: _right_indicator.queue_free()

func _physics_process(delta: float) -> void:
	if not enable_two_hand_grab:
		return
	
	# Fallback if pointers missing
	if not _left_pointer or not _right_pointer:
		_find_pointers()
		return
	
	# Update press state
	var left_trigger = _is_trigger_pressed(_left_controller)
	var right_trigger = _is_trigger_pressed(_right_controller)
	
	# If we are not grabbing, look for start condition
	if not _is_two_hand_grabbing:
		# Check if pointers are hitting me
		var left_hit = _check_pointer_hit(_left_pointer)
		var right_hit = _check_pointer_hit(_right_pointer)
		
		if left_trigger and left_hit: 
			_left_pressing_me = true
		if not left_trigger: 
			_left_pressing_me = false
		
		if right_trigger and right_hit: 
			_right_pressing_me = true
		if not right_trigger: 
			_right_pressing_me = false
		
		# Start grab if both triggers pressed while hitting panel
		if _left_pressing_me and _right_pressing_me:
			_start_two_hand_grab()
	else:
		# We ARE grabbing
		# End grab if either trigger released
		if not left_trigger or not right_trigger:
			_end_two_hand_grab()
			return
		
		_process_two_hand_grab(delta)

func _start_two_hand_grab() -> void:
	_is_two_hand_grabbing = true
	
	# Store initial transform (without scale baked into basis)
	_initial_panel_transform = Transform3D(global_transform.basis.orthonormalized(), global_transform.origin)
	
	var left_hit = _left_pointer.get_hit_point()
	var right_hit = _right_pointer.get_hit_point()
	
	_left_grab_dist = _left_pointer.global_position.distance_to(left_hit)
	_right_grab_dist = _right_pointer.global_position.distance_to(right_hit)
	
	_initial_left_pos = left_hit
	_initial_right_pos = right_hit
	
	_initial_distance = _initial_left_pos.distance_to(_initial_right_pos)
	_initial_hand_vector = (_initial_right_pos - _initial_left_pos)
	
	_left_indicator.visible = true
	_right_indicator.visible = true
	
	if debug_two_hand:
		print("TwoHandGrab Panel: Started. Dist: ", _initial_distance, " Scale: ", scale)

func _end_two_hand_grab() -> void:
	_is_two_hand_grabbing = false
	_left_pressing_me = false
	_right_pressing_me = false
	
	_left_indicator.visible = false
	_right_indicator.visible = false
	
	if debug_two_hand:
		print("TwoHandGrab Panel: Ended")

func _process_two_hand_grab(delta: float) -> void:
	# Get current virtual cursor positions
	var curr_left_pos = _get_cursor_pos(_left_pointer, _left_grab_dist)
	var curr_right_pos = _get_cursor_pos(_right_pointer, _right_grab_dist)
	
	# Update indicators
	_left_indicator.global_position = curr_left_pos
	_right_indicator.global_position = curr_right_pos
	
	# 1. Scale
	var curr_dist = curr_left_pos.distance_to(curr_right_pos)
	
	var scale_ratio = 1.0
	if _initial_distance > 0.001:
		scale_ratio = curr_dist / _initial_distance
	
	# Apply sensitivity
	scale_ratio = 1.0 + (scale_ratio - 1.0) * scale_sensitivity
	
	var new_scale_value = scale.x * scale_ratio
	# Clamp scale
	new_scale_value = clamp(new_scale_value, min_scale, max_scale)
	
	# 2. Rotation
	var curr_hand_vector = (curr_right_pos - curr_left_pos)
	var init_vec = _initial_hand_vector
	
	if lock_y_axis:
		# Project to XZ plane
		curr_hand_vector.y = 0
		init_vec.y = 0
		if curr_hand_vector.length_squared() < 0.001: curr_hand_vector = Vector3.RIGHT
		if init_vec.length_squared() < 0.001: init_vec = Vector3.RIGHT
	
	# Calculate rotation difference
	var rot_axis = init_vec.cross(curr_hand_vector).normalized()
	var rot_angle = init_vec.angle_to(curr_hand_vector) * rotation_sensitivity
	
	var rot_diff = Basis.IDENTITY
	if rot_axis.length_squared() > 0.001 and not is_nan(rot_angle):
		rot_diff = Basis(rot_axis, rot_angle)
	
	# 3. Position (Midpoint)
	var initial_mid = (_initial_left_pos + _initial_right_pos) * 0.5
	var current_mid = (curr_left_pos + curr_right_pos) * 0.5
	
	# Construct new transform
	# Apply rotation to initial basis (without scale from initial transform)
	var initial_basis_no_scale = _initial_panel_transform.basis.orthonormalized()
	var target_basis = rot_diff * initial_basis_no_scale
	
	# Rotation pivot logic
	var offset_from_mid = _initial_panel_transform.origin - initial_mid
	var rotated_offset = rot_diff * offset_from_mid
	var target_origin = current_mid + rotated_offset
	
	if lock_y_axis:
		target_origin.y = _initial_panel_transform.origin.y
	
	# Apply smoothing to rotation and position
	var target_transform = Transform3D(target_basis, target_origin)
	var smoothed_transform = global_transform.interpolate_with(target_transform, smoothing * delta)
	
	# Apply scale separately (uniform scale on the node itself)
	var target_scale = Vector3.ONE * new_scale_value
	var smoothed_scale = scale.lerp(target_scale, smoothing * delta)
	
	global_transform = smoothed_transform
	scale = smoothed_scale

func _get_cursor_pos(pointer: Node3D, dist: float) -> Vector3:
	return pointer.global_position + (-pointer.global_transform.basis.z * dist)

func _is_trigger_pressed(controller: XRController3D) -> bool:
	if not controller: return false
	return controller.get_float("trigger") > 0.5

func _check_pointer_hit(pointer: Node3D) -> bool:
	if pointer.has_method("get_hit_collider"):
		var col = pointer.get_hit_collider()
		return col == _static_body or (col is Node and _static_body and _static_body.is_ancestor_of(col))
	return false

func is_two_hand_grabbing() -> bool:
	return _is_two_hand_grabbing
