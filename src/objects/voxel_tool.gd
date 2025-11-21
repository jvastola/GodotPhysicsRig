extends Grabbable

# Voxel Tool
# A grabbable object that can place and remove voxels when held.
# Mimics the behavior of GridSnapIndicator but for a held object.

@export_group("Voxel Settings")
@export var grid_size: float = 0.1
@export var build_scale_multiplier: float = 1.0
@export var ray_length: float = 5.0
@export var ray_color: Color = Color(0.0, 1.0, 0.0, 0.5)
@export var indicator_color: Color = Color(0.0, 1.0, 0.0, 0.5)

@export_group("References")
@export var raycast_node: RayCast3D
@export var indicator_mesh: MeshInstance3D
@export var ray_visual: MeshInstance3D

var _voxel_manager: VoxelChunkManager
var _is_trigger_pressed: bool = false
var _was_trigger_pressed: bool = false
var _is_grip_pressed: bool = false

func _ready() -> void:
	super._ready()
	
	# Find voxel manager
	_voxel_manager = get_tree().root.find_child("VoxelChunkManager", true, false) as VoxelChunkManager
	if _voxel_manager:
		print("VoxelTool: Found VoxelChunkManager")
	else:
		print("VoxelTool: VoxelChunkManager not found!")
		
	# Setup raycast
	if raycast_node:
		raycast_node.target_position = Vector3(0, 0, -ray_length)
		raycast_node.enabled = true
		
	# Setup indicator
	if indicator_mesh:
		indicator_mesh.visible = false
		var mat = StandardMaterial3D.new()
		mat.albedo_color = indicator_color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		indicator_mesh.material_override = mat
		
	# Setup ray visual
	if ray_visual:
		var mesh = ImmediateMesh.new()
		ray_visual.mesh = mesh
		var mat = StandardMaterial3D.new()
		mat.albedo_color = ray_color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ray_visual.material_override = mat

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	if not is_grabbed or not is_instance_valid(grabbing_hand):
		_set_indicator_visible(false)
		_update_ray_visual(false)
		return
		
	_process_input()
	_process_raycast()

func _process_input() -> void:
	if not is_instance_valid(grabbing_hand):
		return
		
	# Get controller input from the hand's target (XRController3D)
	var controller = grabbing_hand.target as XRController3D
	if not controller:
		return
		
	_is_trigger_pressed = controller.is_button_pressed("trigger_click")
	_is_grip_pressed = controller.is_button_pressed("grip_click")
	
	# Handle trigger press (place voxel)
	if _is_trigger_pressed and not _was_trigger_pressed:
		if _is_grip_pressed:
			_remove_voxel()
		else:
			_place_voxel()
			
	_was_trigger_pressed = _is_trigger_pressed

func _process_raycast() -> void:
	if not raycast_node:
		return
		
	var has_hit = raycast_node.is_colliding()
	_update_ray_visual(true, has_hit)
	
	if has_hit:
		var hit_point = raycast_node.get_collision_point()
		var normal = raycast_node.get_collision_normal()
		_update_indicator(hit_point, normal)
	else:
		_set_indicator_visible(false)

func _update_indicator(hit_point: Vector3, normal: Vector3) -> void:
	if not indicator_mesh:
		return
		
	var adjusted_point = hit_point
	var offset = 0.01
	
	if _is_grip_pressed:
		# Remove mode: inside
		adjusted_point -= normal.normalized() * offset
		indicator_mesh.material_override.albedo_color = Color(1.0, 0.0, 0.0, 0.5)
	else:
		# Place mode: outside
		adjusted_point += normal.normalized() * offset
		indicator_mesh.material_override.albedo_color = indicator_color
		
	var snapped_pos = _snap_to_grid(adjusted_point)
	
	indicator_mesh.global_position = snapped_pos
	indicator_mesh.global_rotation = Vector3.ZERO # Reset rotation to align with grid
	_set_indicator_visible(true)

func _snap_to_grid(pos: Vector3) -> Vector3:
	var cell_size = max(grid_size, 0.01)
	return Vector3(
		round(pos.x / cell_size) * cell_size,
		round(pos.y / cell_size) * cell_size,
		round(pos.z / cell_size) * cell_size
	)

func _place_voxel() -> void:
	if not _voxel_manager:
		return
		
	if not indicator_mesh or not indicator_mesh.visible:
		return
		
	var pos = indicator_mesh.global_position
	_voxel_manager.add_voxel(pos)
	_voxel_manager.update_dirty_chunks()
	print("VoxelTool: Placed voxel at ", pos)

func _remove_voxel() -> void:
	if not _voxel_manager:
		return
		
	if not indicator_mesh or not indicator_mesh.visible:
		return
		
	var pos = indicator_mesh.global_position
	if _voxel_manager.has_voxel(pos):
		_voxel_manager.remove_voxel(pos)
		_voxel_manager.update_dirty_chunks()
		print("VoxelTool: Removed voxel at ", pos)

func _set_indicator_visible(visible: bool) -> void:
	if indicator_mesh:
		indicator_mesh.visible = visible

func _update_ray_visual(visible: bool, has_hit: bool = false) -> void:
	if not ray_visual:
		return
		
	ray_visual.visible = visible
	if not visible:
		return
		
	var mesh = ray_visual.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	var start = Vector3.ZERO
	var end = Vector3(0, 0, -ray_length)
	
	if has_hit and raycast_node:
		end = raycast_node.to_local(raycast_node.get_collision_point())
		
	mesh.surface_add_vertex(start)
	mesh.surface_add_vertex(end)
	mesh.surface_end()
