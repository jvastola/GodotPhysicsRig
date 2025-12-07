# Ray Interactor
# Provides ray-based interactions for VR controllers
# Extends the base interactor with raycast detection
extends BaseInteractor
class_name RayInteractor

@export var ray_length: float = 3.0
@export var ray_length_min: float = 0.25
@export var ray_length_max: float = 10.0
@export var pointer_axis_local: Vector3 = Vector3(0, 0, -1)

@export_group("Visual Feedback")
@export var show_ray: bool = true
@export var show_hit_marker: bool = true
@export var ray_color: Color = Color(0.3, 0.7, 1.0, 0.8)
@export var hit_color: Color = Color(1.0, 1.0, 1.0, 0.35)
@export var hit_scale: float = 0.05
@export_enum("sphere", "cylinder") var hit_shape: String = "sphere"

@export_group("Input")
@export var select_action: String = "trigger_click"
@export var activate_action: String = ""
@export var controller: XRController3D = null

# Internal components
var _raycast: RayCast3D
var _ray_visual: MeshInstance3D
var _hit_visual: MeshInstance3D
var _line_mesh: ImmediateMesh

# State
var _current_hit_point: Vector3 = Vector3.ZERO
var _current_hit_normal: Vector3 = Vector3.ZERO
var _current_distance: float = 0.0


func _ready() -> void:
	super._ready()
	_setup_raycast()
	_setup_visuals()
	

func _setup_raycast() -> void:
	_raycast = RayCast3D.new()
	_raycast.name = "RayCast3D"
	add_child(_raycast)
	_raycast.enabled = true
	_raycast.collide_with_areas = true
	_raycast.collide_with_bodies = true
	_raycast.collision_mask = interaction_layer_mask
	_update_raycast_target()


func _setup_visuals() -> void:
	# Ray visual
	if show_ray:
		_ray_visual = MeshInstance3D.new()
		_ray_visual.name = "RayVisual"
		add_child(_ray_visual)
		
		_line_mesh = ImmediateMesh.new()
		_ray_visual.mesh = _line_mesh
		
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = ray_color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ray_visual.material_override = mat
	
	# Hit marker visual
	if show_hit_marker:
		_hit_visual = MeshInstance3D.new()
		_hit_visual.name = "HitMarker"
		add_child(_hit_visual)
		
		_hit_visual.mesh = _create_hit_mesh()
		_hit_visual.material_override = _build_hit_material()
		_hit_visual.visible = false


func _create_hit_mesh() -> PrimitiveMesh:
	match hit_shape:
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = hit_scale
			cylinder.bottom_radius = hit_scale
			cylinder.height = max(hit_scale * 0.02, 0.0005)
			cylinder.radial_segments = 16
			return cylinder
		_:
			var sphere := SphereMesh.new()
			sphere.radius = hit_scale
			sphere.height = hit_scale * 2.0
			sphere.radial_segments = 16
			return sphere


func _build_hit_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = hit_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# Update raycast
	_update_raycast_target()
	_raycast.force_raycast_update()
	
	# Process interaction
	process_interaction()
	
	# Update visuals
	_update_visuals()


func _detect_interactable() -> BaseInteractable:
	if not _raycast.is_colliding():
		_current_hit_point = global_position + global_transform.basis * (pointer_axis_local.normalized() * ray_length)
		_current_hit_normal = -global_transform.basis.z
		_current_distance = ray_length
		return null
	
	# Get collision info
	var collider = _raycast.get_collider()
	_current_hit_point = _raycast.get_collision_point()
	_current_hit_normal = _raycast.get_collision_normal()
	_current_distance = global_position.distance_to(_current_hit_point)
	
	# Find interactable component
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
	if select_action.is_empty():
		return false
	
	# Check XR controller input
	if controller and controller.has_method("get_float"):
		var value = controller.get_float("trigger")
		return value > 0.5
	
	# Fallback to input action
	if InputMap.has_action(select_action):
		return Input.is_action_pressed(select_action)
	
	return false


func _is_activate_pressed() -> bool:
	if activate_action.is_empty():
		return false
	
	if InputMap.has_action(activate_action):
		return Input.is_action_just_pressed(activate_action)
	
	return false


func _update_raycast_target() -> void:
	var axis = pointer_axis_local.normalized()
	_raycast.target_position = axis * ray_length


func _update_visuals() -> void:
	# Update ray visual
	if _ray_visual and _line_mesh:
		var local_end = pointer_axis_local.normalized() * _current_distance
		_line_mesh.clear_surfaces()
		_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		_line_mesh.surface_add_vertex(Vector3.ZERO)
		_line_mesh.surface_add_vertex(local_end)
		_line_mesh.surface_end()
	
	# Update hit marker visual
	if _hit_visual:
		_hit_visual.visible = _raycast.is_colliding()
		if _hit_visual.visible:
			_hit_visual.global_position = _current_hit_point


func get_interaction_point() -> Vector3:
	return _current_hit_point


func get_interaction_normal() -> Vector3:
	return _current_hit_normal


## Set the controller for this ray interactor
func set_controller(ctrl: XRController3D) -> void:
	controller = ctrl


## Adjust ray length dynamically
func set_ray_length(length: float) -> void:
	ray_length = clamp(length, ray_length_min, ray_length_max)
