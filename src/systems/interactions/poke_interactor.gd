# Poke Interactor
# Provides touch-based interactions for VR (finger poke)
# Simulates pressing buttons/switches with fingertip
extends BaseInteractor
class_name PokeInteractor

@export var poke_depth: float = 0.02  # How deep to penetrate to trigger select
@export var poke_radius: float = 0.015  # Size of poke detection sphere
@export var hover_radius: float = 0.03  # Larger radius for hover detection
@export var attach_transform_path: NodePath = NodePath()  # Path to fingertip marker

@export_group("Visual Feedback")
@export var show_debug_sphere: bool = false
@export var poke_color: Color = Color(1.0, 0.5, 0.2, 0.5)

# Internal
var _attach_transform: Node3D = null
var _hover_area: Area3D
var _poke_area: Area3D
var _debug_hover_mesh: MeshInstance3D
var _debug_poke_mesh: MeshInstance3D

# State
var _overlapping_interactables: Array[BaseInteractable] = []
var _penetration_depths: Dictionary = {}  # interactable -> depth


func _ready() -> void:
	super._ready()
	_setup_attach_transform()
	_setup_detection_areas()
	_setup_debug_visuals()


func _setup_attach_transform() -> void:
	if attach_transform_path.is_empty():
		_attach_transform = self
	else:
		_attach_transform = get_node_or_null(attach_transform_path)
		if not _attach_transform:
			push_warning("PokeInteractor: attach_transform not found, using self")
			_attach_transform = self


func _setup_detection_areas() -> void:
	# Hover area (larger)
	_hover_area = Area3D.new()
	_hover_area.name = "HoverArea"
	_attach_transform.add_child(_hover_area)
	_hover_area.collision_layer = 0
	_hover_area.collision_mask = interaction_layer_mask
	_hover_area.monitoring = true
	
	var hover_shape = CollisionShape3D.new()
	var hover_sphere = SphereShape3D.new()
	hover_sphere.radius = hover_radius
	hover_shape.shape = hover_sphere
	_hover_area.add_child(hover_shape)
	
	_hover_area.area_entered.connect(_on_hover_area_entered)
	_hover_area.area_exited.connect(_on_hover_area_exited)
	_hover_area.body_entered.connect(_on_hover_body_entered)
	_hover_area.body_exited.connect(_on_hover_body_exited)
	
	# Poke area (smaller)
	_poke_area = Area3D.new()
	_poke_area.name = "PokeArea"
	_attach_transform.add_child(_poke_area)
	_poke_area.collision_layer = 0
	_poke_area.collision_mask = interaction_layer_mask
	_poke_area.monitoring = true
	
	var poke_shape = CollisionShape3D.new()
	var poke_sphere = SphereShape3D.new()
	poke_sphere.radius = poke_radius
	poke_shape.shape = poke_sphere
	_poke_area.add_child(poke_shape)


func _setup_debug_visuals() -> void:
	if not show_debug_sphere:
		return
	
	# Hover sphere visual
	_debug_hover_mesh = MeshInstance3D.new()
	_debug_hover_mesh.name = "DebugHoverSphere"
	_attach_transform.add_child(_debug_hover_mesh)
	
	var hover_sphere = SphereMesh.new()
	hover_sphere.radius = hover_radius
	hover_sphere.height = hover_radius * 2.0
	_debug_hover_mesh.mesh = hover_sphere
	
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(poke_color.r, poke_color.g, poke_color.b, 0.2)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_debug_hover_mesh.material_override = mat
	
	# Poke sphere visual
	_debug_poke_mesh = MeshInstance3D.new()
	_debug_poke_mesh.name = "DebugPokeSphere"
	_attach_transform.add_child(_debug_poke_mesh)
	
	var poke_sphere = SphereMesh.new()
	poke_sphere.radius = poke_radius
	poke_sphere.height = poke_radius * 2.0
	_debug_poke_mesh.mesh = poke_sphere
	
	var poke_mat = StandardMaterial3D.new()
	poke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	poke_mat.albedo_color = poke_color
	poke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_debug_poke_mesh.material_override = poke_mat


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_penetration_depths()
	process_interaction()


func _detect_interactable() -> BaseInteractable:
	# Return the interactable with deepest penetration  
	if _overlapping_interactables.is_empty():
		return null
	
	var deepest_interactable: BaseInteractable = null
	var max_depth: float = 0.0
	
	for interactable in _overlapping_interactables:
		var depth = _penetration_depths.get(interactable, 0.0)
		if depth > max_depth:
			max_depth = depth
			deepest_interactable = interactable
	
	return deepest_interactable


func _is_select_pressed() -> bool:
	# Select is triggered when penetration depth exceeds threshold
	var detected = _detect_interactable()
	if not detected:
		return false
	
	var depth = _penetration_depths.get(detected, 0.0)
	return depth >= poke_depth


func _update_penetration_depths() -> void:
	_penetration_depths.clear()
	
	for interactable in _overlapping_interactables:
		if not is_instance_valid(interactable):
			continue
		
		var collider = interactable.get_collider()
		if not collider:
			continue
		
		# Calculate penetration depth (simplified - distance into collider bounds)
		var poke_point = _attach_transform.global_position
		var closest_point = _get_closest_point_on_collider(collider, poke_point)
		var depth = (closest_point - poke_point).length()
		
		_penetration_depths[interactable] = depth


func _get_closest_point_on_collider(collider: CollisionObject3D, point: Vector3) -> Vector3:
	# Simplified: use collider position for now
	# In a full implementation, this should calculate the actual closest surface point
	if collider is StaticBody3D or collider is RigidBody3D or collider is Area3D:
		return collider.global_position
	return point


func _on_hover_area_entered(area: Area3D) -> void:
	_check_and_add_interactable(area)


func _on_hover_area_exited(area: Area3D) -> void:
	_check_and_remove_interactable(area)


func _on_hover_body_entered(body: Node3D) -> void:
	_check_and_add_interactable(body)


func _on_hover_body_exited(body: Node3D) -> void:
	_check_and_remove_interactable(body)


func _check_and_add_interactable(node: Node) -> void:
	var interactable = _find_interactable_component(node)
	if interactable and not _overlapping_interactables.has(interactable):
		_overlapping_interactables.append(interactable)


func _check_and_remove_interactable(node: Node) -> void:
	var interactable = _find_interactable_component(node)
	if interactable:
		_overlapping_interactables.erase(interactable)


func _find_interactable_component(node: Node) -> BaseInteractable:
	# Check node and its children for BaseInteractable component
	while node:
		for child in node.get_children():
			if child is BaseInteractable:
				return child as BaseInteractable
		node = node.get_parent()
	return null


func get_interaction_point() -> Vector3:
	return _attach_transform.global_position


func get_interaction_normal() -> Vector3:
	# For poke, normal is typically the direction from fingertip
	return -_attach_transform.global_transform.basis.z
