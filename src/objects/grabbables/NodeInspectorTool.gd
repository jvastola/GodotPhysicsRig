# NodeInspectorTool - A grabbable tool that points at objects and opens their inspector
# Hold trigger while gripping to scan an object and open its inspector panel
extends Grabbable

# Configuration
@export var tip_offset: Vector3 = Vector3(0, 0, -0.25)  # Offset from center to tool tip
@export var ray_length: float = 20.0  # Maximum raycast distance
@export var laser_color: Color = Color(0.2, 0.8, 1.0, 0.8)
@export var hit_color: Color = Color(1.0, 0.5, 0.0, 1.0)
@export var spawn_at_hit_point: bool = true  # If true, spawn panels at hit point; if false, in front of player
@export var panel_spawn_distance: float = 1.0  # Distance from player head (when spawn_at_hit_point is false)
@export var panel_spawn_offset: Vector3 = Vector3(0.6, 0.0, 0.0)  # Offset for side-by-side panels
@export var panel_scale: float = 0.4  # Scale of spawned panels
@export var panel_height_offset: float = 0.3  # How high above hit point to spawn panels

# Scene references
@export var inspector_scene: PackedScene = preload("res://src/ui/NodeInspectorViewport3D.tscn")
@export var hierarchy_scene: PackedScene = preload("res://src/ui/SceneHierarchyViewport3D.tscn")

# State
var _is_active: bool = false
var _controller: Node = null
var _hand: RigidBody3D = null
var _prev_trigger_pressed: bool = false
var _current_hit_object: Node = null
var _current_hit_point: Vector3 = Vector3.ZERO

# Visual components
var _laser_beam: MeshInstance3D = null
var _laser_mesh: ImmediateMesh = null
var _laser_material: StandardMaterial3D = null
var _hit_indicator: MeshInstance3D = null
var _spawned_inspector: Node3D = null
var _spawned_hierarchy: Node3D = null


func _ready() -> void:
	super._ready()
	
	# Connect to our grab signals
	grabbed.connect(_on_tool_grabbed)
	released.connect(_on_tool_released)
	
	# Create visual components
	_create_laser_beam()
	_create_hit_indicator()
	
	set_physics_process(false)
	print("NodeInspectorTool: Ready")


func _create_laser_beam() -> void:
	"""Create the laser beam visual"""
	_laser_mesh = ImmediateMesh.new()
	
	_laser_material = StandardMaterial3D.new()
	_laser_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser_material.albedo_color = laser_color
	_laser_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_laser_material.no_depth_test = true
	_laser_material.render_priority = 1
	
	_laser_beam = MeshInstance3D.new()
	_laser_beam.name = "LaserBeam"
	_laser_beam.mesh = _laser_mesh
	_laser_beam.material_override = _laser_material
	_laser_beam.visible = false
	
	# Add to root so it persists during grab
	var root = get_tree().root
	if root:
		root.call_deferred("add_child", _laser_beam)


func _create_hit_indicator() -> void:
	"""Create the hit point indicator sphere"""
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.02
	sphere_mesh.height = 0.04
	sphere_mesh.radial_segments = 12
	sphere_mesh.rings = 6
	
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = hit_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = hit_color
	material.emission_energy_multiplier = 0.5
	material.no_depth_test = true
	material.render_priority = 2
	
	_hit_indicator = MeshInstance3D.new()
	_hit_indicator.name = "HitIndicator"
	_hit_indicator.mesh = sphere_mesh
	_hit_indicator.material_override = material
	_hit_indicator.visible = false
	
	# Add to root so it persists during grab
	var root = get_tree().root
	if root:
		root.call_deferred("add_child", _hit_indicator)


func _on_tool_grabbed(hand: RigidBody3D) -> void:
	"""Called when the tool is grabbed"""
	_hand = hand
	_controller = null
	
	if is_instance_valid(hand) and hand.has_method("get"):
		var maybe_target = hand.get("target")
		if maybe_target and maybe_target is Node3D:
			_controller = maybe_target
	
	_is_active = true
	set_physics_process(true)
	print("NodeInspectorTool: Grabbed by ", hand.name)


func _on_tool_released() -> void:
	"""Called when the tool is released"""
	_is_active = false
	_hide_visuals()
	_hand = null
	_controller = null
	_current_hit_object = null
	set_physics_process(false)
	print("NodeInspectorTool: Released")


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	if not is_grabbed or not _is_active:
		return
	if not is_instance_valid(_hand):
		return
	
	# Get trigger state
	var trigger_pressed: bool = false
	if is_instance_valid(_controller) and _controller.has_method("get_float"):
		var trigger_value = _controller.get_float("trigger")
		trigger_pressed = trigger_value > 0.5
	elif is_instance_valid(_controller) and _controller.has_method("is_button_pressed"):
		trigger_pressed = _controller.is_button_pressed("trigger_click")
	elif InputMap.has_action("trigger_click"):
		trigger_pressed = Input.is_action_pressed("trigger_click")
	
	# Perform raycast
	_perform_raycast()
	
	# Handle trigger press (rising edge)
	if trigger_pressed and not _prev_trigger_pressed:
		_on_trigger_pressed()
	
	_prev_trigger_pressed = trigger_pressed


func _get_tip_world_position() -> Vector3:
	"""Get the world position of the tool tip"""
	if grabbed_collision_shapes.size() > 0 and is_instance_valid(grabbed_collision_shapes[0]):
		var grabbed_transform = grabbed_collision_shapes[0].global_transform
		return grabbed_transform * tip_offset
	elif is_instance_valid(_hand):
		return _hand.global_transform * tip_offset
	return global_position + tip_offset


func _get_tip_direction() -> Vector3:
	"""Get the forward direction of the tool tip"""
	if grabbed_collision_shapes.size() > 0 and is_instance_valid(grabbed_collision_shapes[0]):
		return -grabbed_collision_shapes[0].global_transform.basis.z.normalized()
	elif is_instance_valid(_hand):
		return -_hand.global_transform.basis.z.normalized()
	return -global_transform.basis.z.normalized()


func _perform_raycast() -> void:
	"""Perform raycast from tool tip and update visuals"""
	var tip_pos = _get_tip_world_position()
	var tip_dir = _get_tip_direction()
	
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		_hide_visuals()
		return
	
	var query = PhysicsRayQueryParameters3D.create(
		tip_pos,
		tip_pos + tip_dir * ray_length
	)
	# Exclude self and physics hands
	var exclude_rids: Array[RID] = [get_rid()]
	if is_instance_valid(_hand):
		exclude_rids.append(_hand.get_rid())
	query.exclude = exclude_rids
	
	var result = space_state.intersect_ray(query)
	
	if result:
		_current_hit_object = _find_inspectable_node(result.collider)
		_current_hit_point = result.position
		_update_laser(tip_pos, result.position)
		_update_hit_indicator(result.position)
	else:
		_current_hit_object = null
		_current_hit_point = Vector3.ZERO
		# Still show laser pointing forward
		_update_laser(tip_pos, tip_pos + tip_dir * ray_length)
		_hide_hit_indicator()


func _find_inspectable_node(collider: Object) -> Node:
	"""Walk up the tree to find the best node to inspect"""
	if not collider or not is_instance_valid(collider):
		return null
	
	if not (collider is Node):
		return null
	
	var node = collider as Node
	
	# Prefer the root of a scene instance or a named node
	var candidates: Array[Node] = []
	var probe: Node = node
	while probe:
		candidates.append(probe)
		# Stop at scene root
		if probe.scene_file_path != "":
			break
		var parent = probe.get_parent()
		if not parent or parent == get_tree().root:
			break
		probe = parent
	
	# Prefer the highest node that isn't the absolute scene root
	if candidates.size() > 1:
		return candidates[candidates.size() - 1]
	return candidates[0] if candidates.size() > 0 else node


func _update_laser(start: Vector3, end: Vector3) -> void:
	"""Update the laser beam visual"""
	if not is_instance_valid(_laser_beam) or not _laser_mesh:
		return
	
	_laser_mesh.clear_surfaces()
	_laser_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_laser_mesh.surface_add_vertex(start)
	_laser_mesh.surface_add_vertex(end)
	_laser_mesh.surface_end()
	
	_laser_beam.visible = true


func _update_hit_indicator(pos: Vector3) -> void:
	"""Update the hit indicator position"""
	if not is_instance_valid(_hit_indicator):
		return
	
	_hit_indicator.global_position = pos
	_hit_indicator.visible = true


func _hide_hit_indicator() -> void:
	"""Hide the hit indicator"""
	if is_instance_valid(_hit_indicator):
		_hit_indicator.visible = false


func _hide_visuals() -> void:
	"""Hide all tool visuals"""
	if is_instance_valid(_laser_beam):
		_laser_beam.visible = false
	_hide_hit_indicator()


func _on_trigger_pressed() -> void:
	"""Handle trigger press - open inspector for hit object"""
	if not _current_hit_object:
		print("NodeInspectorTool: No object to inspect")
		return
	
	print("NodeInspectorTool: Inspecting ", _current_hit_object.name)
	_spawn_inspector_panels()


func _spawn_inspector_panels() -> void:
	"""Spawn or update the inspector panel(s) at hit point or in front of player"""
	if not _current_hit_object:
		return
	
	# Find player head position for panel orientation
	var player_head = _find_player_head()
	if not player_head:
		print("NodeInspectorTool: Could not find player head")
		return
	
	var head_pos = player_head.global_position
	var spawn_pos: Vector3
	
	if spawn_at_hit_point and _current_hit_point != Vector3.ZERO:
		# Spawn at hit point, offset upward
		spawn_pos = _current_hit_point + Vector3.UP * panel_height_offset
	else:
		# Spawn in front of player
		var head_forward = -player_head.global_transform.basis.z.normalized()
		spawn_pos = head_pos + head_forward * panel_spawn_distance
	
	# Calculate offset direction (perpendicular to view)
	var to_head = (head_pos - spawn_pos).normalized()
	var right_dir = to_head.cross(Vector3.UP).normalized()
	
	# Spawn or update inspector panel
	if not is_instance_valid(_spawned_inspector):
		_spawned_inspector = inspector_scene.instantiate()
		get_tree().current_scene.add_child(_spawned_inspector)
	
	# Position and scale inspector panel
	_spawned_inspector.global_position = spawn_pos + right_dir * panel_spawn_offset.x
	_spawned_inspector.look_at(head_pos, Vector3.UP)
	_spawned_inspector.rotate_y(PI)  # Face toward player
	_spawned_inspector.scale = Vector3.ONE * panel_scale
	
	# Tell inspector to inspect the hit object
	if _spawned_inspector.has_method("inspect_node"):
		_spawned_inspector.inspect_node(_current_hit_object)
	elif _spawned_inspector.get_node_or_null("SubViewport/NodeInspectorUI"):
		var ui = _spawned_inspector.get_node("SubViewport/NodeInspectorUI")
		if ui.has_method("inspect_node"):
			ui.inspect_node(_current_hit_object)
	
	# Optionally spawn hierarchy panel side-by-side
	if not is_instance_valid(_spawned_hierarchy):
		_spawned_hierarchy = hierarchy_scene.instantiate()
		get_tree().current_scene.add_child(_spawned_hierarchy)
	
	# Position hierarchy panel to the left of inspector
	_spawned_hierarchy.global_position = spawn_pos - right_dir * panel_spawn_offset.x
	_spawned_hierarchy.look_at(head_pos, Vector3.UP)
	_spawned_hierarchy.rotate_y(PI)
	_spawned_hierarchy.scale = Vector3.ONE * panel_scale


func _find_player_head() -> Node3D:
	"""Find the XR camera or player head"""
	# Try to find XR camera
	var xr_camera = get_tree().get_first_node_in_group("xr_camera")
	if xr_camera and xr_camera is Node3D:
		return xr_camera
	
	# Try to find XR origin + camera
	var xr_origin = get_tree().get_first_node_in_group("xr_origin")
	if xr_origin:
		var camera = xr_origin.find_child("XRCamera3D", true, false)
		if camera:
			return camera
	
	# Fallback to any Camera3D
	var viewport_camera = get_viewport().get_camera_3d()
	if viewport_camera:
		return viewport_camera
	
	# Last resort: use tool position
	return _hand if is_instance_valid(_hand) else null


func _exit_tree() -> void:
	# Clean up visual components
	if is_instance_valid(_laser_beam):
		_laser_beam.queue_free()
	if is_instance_valid(_hit_indicator):
		_hit_indicator.queue_free()
	
	# Note: Don't destroy spawned panels - user might want to keep them
	
	super._exit_tree()
