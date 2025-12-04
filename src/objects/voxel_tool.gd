extends Grabbable
class_name VoxelTool
## Grabbable Voxel Tool - Place and remove voxels with adjustable ray and grid size

# === Ray Settings ===
@export_group("Ray Settings")
@export var ray_length: float = 5.0
@export var ray_length_min: float = 0.5
@export var ray_length_max: float = 15.0
@export var ray_length_adjust_speed: float = 5.0
@export var ray_deadzone: float = 0.2
@export var ray_axis_action: String = "primary"

# === Visibility ===
@export_group("Visibility")
@export var always_show_ray: bool = true
@export var always_show_indicator: bool = true
@export var ray_color: Color = Color(0.0, 1.0, 0.5, 0.6)
@export var ray_hit_color: Color = Color(0.0, 1.0, 0.0, 0.8)
@export var indicator_color: Color = Color(0.0, 1.0, 0.5, 0.4)
@export var remove_mode_color: Color = Color(1.0, 0.2, 0.2, 0.4)

# === Voxel Settings ===
@export_group("Voxel Settings")
@export var voxel_size: float = 0.1
@export var voxel_size_presets: Array[float] = [0.05, 0.1, 0.25, 0.5, 1.0]
@export var voxel_size_preset_index: int = 1
@export var voxel_size_adjust_speed: float = 0.5
@export var surface_offset: float = 0.01

# === Child Nodes (created dynamically) ===
var raycast: RayCast3D
var ray_visual: MeshInstance3D
var indicator_mesh: MeshInstance3D
var hit_marker: MeshInstance3D
var ray_immediate_mesh: ImmediateMesh

# === State ===
var _voxel_manager: VoxelChunkManager
var _was_trigger_pressed: bool = false
var _is_remove_mode: bool = false
var _has_hit: bool = false
var _hit_point: Vector3 = Vector3.ZERO
var _hit_normal: Vector3 = Vector3.UP


func _ready() -> void:
	super._ready()
	
	# Create child nodes
	_create_raycast()
	_create_ray_visual()
	_create_indicator()
	_create_hit_marker()
	
	# Find voxel manager
	_find_voxel_manager()
	
	# Apply initial voxel size
	_apply_voxel_size()
	
	print("VoxelTool: Ready with voxel size ", voxel_size)


func _exit_tree() -> void:
	# Don't clean up indicator/hit_marker here - they'll be recreated on demand
	# in _ensure_visuals_in_tree() after scene transitions
	pass


func _find_voxel_manager() -> void:
	# Search by group - more robust than find_child across scene transitions
	var managers = get_tree().get_nodes_in_group("voxel_manager")
	if managers.size() > 0:
		_voxel_manager = managers[0] as VoxelChunkManager
		if _voxel_manager:
			print("VoxelTool: Found VoxelChunkManager via group")
		else:
			push_warning("VoxelTool: Found node in voxel_manager group but wrong type!")
	else:
		# Fallback to find_child
		_voxel_manager = get_tree().root.find_child("VoxelChunkManager", true, false) as VoxelChunkManager
		if _voxel_manager:
			print("VoxelTool: Found VoxelChunkManager via find_child")
		else:
			push_warning("VoxelTool: VoxelChunkManager not found!")


func _create_raycast() -> void:
	raycast = RayCast3D.new()
	raycast.name = "VoxelRaycast"
	raycast.target_position = Vector3(0, 0, -ray_length)
	raycast.enabled = true
	raycast.collision_mask = 1  # World layer
	add_child(raycast)


func _create_ray_visual() -> void:
	ray_visual = MeshInstance3D.new()
	ray_visual.name = "RayVisual"
	ray_immediate_mesh = ImmediateMesh.new()
	ray_visual.mesh = ray_immediate_mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = ray_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	ray_visual.material_override = mat
	
	add_child(ray_visual)


func _create_indicator() -> void:
	indicator_mesh = MeshInstance3D.new()
	indicator_mesh.name = "VoxelToolIndicator"
	
	var box = BoxMesh.new()
	box.size = Vector3.ONE * voxel_size
	indicator_mesh.mesh = box
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = indicator_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	indicator_mesh.material_override = mat
	
	# Add to scene root (will be done when in tree)
	indicator_mesh.visible = false


func _create_hit_marker() -> void:
	hit_marker = MeshInstance3D.new()
	hit_marker.name = "VoxelToolHitMarker"
	
	var sphere = SphereMesh.new()
	sphere.radius = 0.02
	sphere.height = 0.04
	hit_marker.mesh = sphere
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = ray_hit_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hit_marker.material_override = mat
	
	# Add to scene root (will be done when in tree)
	hit_marker.visible = false


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# Ensure indicator and hit_marker are in the scene tree
	_ensure_visuals_in_tree()
	
	# Refind voxel manager if it became invalid (e.g., after scene transition)
	if not is_instance_valid(_voxel_manager):
		_find_voxel_manager()
	
	if not is_grabbed or not is_instance_valid(grabbing_hand):
		_set_visuals_visible(false)
		return
	
	_process_input(delta)
	_process_raycast()
	_update_visuals()


func _ensure_visuals_in_tree() -> void:
	"""Add indicator and hit_marker to scene root if not already there.
	Recreates them if they were freed during scene transitions."""
	if not is_inside_tree():
		return
	
	var scene_root = get_tree().current_scene
	if not scene_root:
		return
	
	# Recreate indicator if it was freed
	if not is_instance_valid(indicator_mesh):
		_create_indicator()
	
	# Recreate hit_marker if it was freed
	if not is_instance_valid(hit_marker):
		_create_hit_marker()
	
	# Add to scene tree if not already there
	if indicator_mesh and not indicator_mesh.is_inside_tree():
		scene_root.add_child(indicator_mesh)
	
	if hit_marker and not hit_marker.is_inside_tree():
		scene_root.add_child(hit_marker)


func _process_input(delta: float) -> void:
	var controller = _get_controller()
	if not controller:
		return
	
	# Get current input states
	var trigger_pressed = controller.is_button_pressed("trigger_click")
	var grip_pressed = controller.is_button_pressed("grip_click")
	_is_remove_mode = grip_pressed
	
	# Handle trigger press (place/remove voxel)
	if trigger_pressed and not _was_trigger_pressed:
		if _has_hit or always_show_indicator:
			if _is_remove_mode:
				_remove_voxel()
			else:
				_place_voxel()
	
	_was_trigger_pressed = trigger_pressed
	
	# Ray length adjustment (thumbstick Y)
	var axis_input = controller.get_vector2(ray_axis_action)
	if abs(axis_input.y) > ray_deadzone:
		ray_length = clamp(
			ray_length - axis_input.y * ray_length_adjust_speed * delta,
			ray_length_min,
			ray_length_max
		)
		raycast.target_position = Vector3(0, 0, -ray_length)
	
	# Voxel size adjustment (thumbstick X while holding grip)
	if grip_pressed and abs(axis_input.x) > ray_deadzone:
		_adjust_voxel_size(axis_input.x * delta)


func _get_controller() -> XRController3D:
	if not is_instance_valid(grabbing_hand):
		return null
	return grabbing_hand.target as XRController3D


func _process_raycast() -> void:
	if not raycast:
		return
	
	raycast.force_raycast_update()
	_has_hit = raycast.is_colliding()
	
	if _has_hit:
		_hit_point = raycast.get_collision_point()
		_hit_normal = raycast.get_collision_normal()
	else:
		# Project to max ray distance when no hit
		_hit_point = raycast.to_global(Vector3(0, 0, -ray_length))
		_hit_normal = Vector3.UP


func _update_visuals() -> void:
	var show_ray = always_show_ray or _has_hit
	var show_indicator = always_show_indicator or _has_hit
	
	# Update ray visual
	if ray_visual and ray_immediate_mesh:
		ray_visual.visible = show_ray
		if show_ray:
			_draw_ray()
	
	# Update indicator
	if indicator_mesh:
		indicator_mesh.visible = show_indicator
		if show_indicator:
			_update_indicator_position()
	
	# Update hit marker
	if hit_marker:
		hit_marker.visible = _has_hit
		if _has_hit:
			hit_marker.global_position = _hit_point


func _draw_ray() -> void:
	ray_immediate_mesh.clear_surfaces()
	ray_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	var end_point = Vector3(0, 0, -ray_length)
	if _has_hit:
		end_point = raycast.to_local(_hit_point)
	
	ray_immediate_mesh.surface_add_vertex(Vector3.ZERO)
	ray_immediate_mesh.surface_add_vertex(end_point)
	ray_immediate_mesh.surface_end()
	
	# Update color based on mode
	var mat = ray_visual.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = remove_mode_color if _is_remove_mode else ray_color


func _update_indicator_position() -> void:
	var adjusted_point = _hit_point
	
	# Offset based on mode
	if _hit_normal.length_squared() > 0.0:
		if _is_remove_mode:
			# Position inside the hit object for removal
			adjusted_point -= _hit_normal.normalized() * surface_offset
		else:
			# Position outside for placement
			adjusted_point += _hit_normal.normalized() * surface_offset
	
	# Snap to grid
	var snapped = _snap_to_grid(adjusted_point)
	indicator_mesh.global_position = snapped
	indicator_mesh.global_rotation = Vector3.ZERO
	
	# Update color
	var mat = indicator_mesh.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = remove_mode_color if _is_remove_mode else indicator_color


func _snap_to_grid(pos: Vector3) -> Vector3:
	var cell = max(voxel_size, 0.01)
	return Vector3(
		round(pos.x / cell) * cell,
		round(pos.y / cell) * cell,
		round(pos.z / cell) * cell
	)


func _place_voxel() -> void:
	print("VoxelTool: _place_voxel called, _voxel_manager valid: ", is_instance_valid(_voxel_manager))
	if not _voxel_manager:
		print("VoxelTool: _voxel_manager null, attempting to find...")
		_find_voxel_manager()
		if not _voxel_manager:
			print("VoxelTool: ERROR - Could not find VoxelChunkManager!")
			return
	
	print("VoxelTool: indicator_mesh valid: ", is_instance_valid(indicator_mesh), " visible: ", indicator_mesh.visible if is_instance_valid(indicator_mesh) else "N/A")
	if not indicator_mesh or not indicator_mesh.visible:
		print("VoxelTool: indicator_mesh not valid or not visible, skipping placement")
		return
	
	var pos = indicator_mesh.global_position
	_voxel_manager.set_voxel_size(voxel_size)
	_voxel_manager.add_voxel(pos)
	_voxel_manager.update_dirty_chunks()
	print("VoxelTool: Placed voxel at ", pos, " size: ", voxel_size)


func _remove_voxel() -> void:
	if not _voxel_manager:
		_find_voxel_manager()
		if not _voxel_manager:
			return
	
	if not indicator_mesh or not indicator_mesh.visible:
		return
	
	var pos = indicator_mesh.global_position
	if _voxel_manager.has_voxel(pos):
		_voxel_manager.remove_voxel(pos)
		_voxel_manager.update_dirty_chunks()
		print("VoxelTool: Removed voxel at ", pos)


func _adjust_voxel_size(delta_input: float) -> void:
	voxel_size = clamp(
		voxel_size + delta_input * voxel_size_adjust_speed,
		0.01,
		2.0
	)
	_apply_voxel_size()


func _apply_voxel_size() -> void:
	# Update indicator mesh size
	if indicator_mesh and indicator_mesh.mesh is BoxMesh:
		var box = indicator_mesh.mesh as BoxMesh
		box.size = Vector3.ONE * voxel_size
	
	# Update voxel manager
	if _voxel_manager:
		_voxel_manager.set_voxel_size(voxel_size)


func _set_visuals_visible(visible: bool) -> void:
	if ray_visual:
		ray_visual.visible = visible
	if indicator_mesh:
		indicator_mesh.visible = visible
	if hit_marker:
		hit_marker.visible = visible


# === Public API ===

func set_voxel_size_preset(index: int) -> void:
	"""Set voxel size from preset array"""
	if index >= 0 and index < voxel_size_presets.size():
		voxel_size_preset_index = index
		voxel_size = voxel_size_presets[index]
		_apply_voxel_size()
		print("VoxelTool: Voxel size preset ", index, " = ", voxel_size)


func cycle_voxel_size_preset(forward: bool = true) -> void:
	"""Cycle through voxel size presets"""
	var new_index = voxel_size_preset_index
	if forward:
		new_index = (new_index + 1) % voxel_size_presets.size()
	else:
		new_index = (new_index - 1 + voxel_size_presets.size()) % voxel_size_presets.size()
	set_voxel_size_preset(new_index)


func toggle_always_visible() -> void:
	"""Toggle always-visible mode for ray and indicator"""
	always_show_ray = not always_show_ray
	always_show_indicator = not always_show_indicator
	print("VoxelTool: Always visible = ", always_show_ray)


func get_current_voxel_size() -> float:
	return voxel_size
