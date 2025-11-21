# Mouse Interactor
# Provides mouse-based interactions for desktop players
# Raycasts from camera through mouse position
extends BaseInteractor
class_name MouseInteractor

@export var camera: Camera3D = null
@export var ray_length: float = 100.0
@export var left_click_action: String = "mouse_left_click"
@export var right_click_action: String = "mouse_right_click"

@export_group("Visual Feedback")
@export var show_hit_marker: bool = true
@export var hit_marker_scale: float = 0.1
@export var hover_cursor: Input.CursorShape = Input.CURSOR_POINTING_HAND
@export var default_cursor: Input.CursorShape = Input.CURSOR_ARROW

# Internal
var _raycast_query: PhysicsRayQueryParameters3D
var _current_hit_point: Vector3 = Vector3.ZERO
var _current_hit_normal: Vector3 = Vector3.ZERO
var _hit_marker: MeshInstance3D


func _ready() -> void:
	super._ready()
	_setup_hit_marker()
	
	# Try to find camera automatically if not set
	if not camera:
		camera = get_viewport().get_camera_3d()
	
	# Override interaction to use mouse buttons
	can_hover = true
	can_select = true


func _setup_hit_marker() -> void:
	if not show_hit_marker:
		return
	
	_hit_marker = MeshInstance3D.new()
	_hit_marker.name = "HitMarker"
	add_child(_hit_marker)
	
	var sphere = SphereMesh.new()
	sphere.radius = hit_marker_scale * 0.5
	sphere.height = hit_marker_scale
	_hit_marker.mesh = sphere
	
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 0.0, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hit_marker.material_override = mat
	_hit_marker.visible = false


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# Only process if mouse is captured or visible
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		return
	
	process_interaction()
	_update_cursor()
	_update_visuals()


func _detect_interactable() -> BaseInteractable:
	if not camera:
		return null
	
	# Get mouse position in viewport
	var mouse_pos = get_viewport().get_mouse_position()
	
	# Raycast from camera through mouse position
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * ray_length
	
	var space_state = get_world_3d().direct_space_state
	_raycast_query = PhysicsRayQueryParameters3D.create(from, to)
	_raycast_query.collision_mask = interaction_layer_mask
	_raycast_query.collide_with_areas = true
	_raycast_query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(_raycast_query)
	
	if result.is_empty():
		_current_hit_point = to
		_current_hit_normal = -camera.global_transform.basis.z
		return null
	
	# Store hit info
	_current_hit_point = result["position"]
	_current_hit_normal = result["normal"]
	
	# Find interactable component
	var collider = result["collider"]
	var node = collider as Node
	
	while node:
		# Check if node has a BaseInteractable child
		for child in node.get_children():
			if child is BaseInteractable:
				return child as BaseInteractable
		
		# Check parent
		node = node.get_parent()
	
	return null


func _is_select_pressed() -> bool:
	# Use left mouse button for selection
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _is_activate_pressed() -> bool:
	# Use right mouse button for activation
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)


func _update_cursor() -> void:
	# Change cursor based on hover state
	if hover_target:
		Input.set_default_cursor_shape(hover_cursor)
	else:
		Input.set_default_cursor_shape(default_cursor)


func _update_visuals() -> void:
	if not _hit_marker:
		return
	
	_hit_marker.visible = hover_target != null
	if _hit_marker.visible:
		_hit_marker.global_position = _current_hit_point


func get_interaction_point() -> Vector3:
	return _current_hit_point


func get_interaction_normal() -> Vector3:
	return _current_hit_normal


## Set the camera for this mouse interactor
func set_camera(cam: Camera3D) -> void:
	camera = cam
