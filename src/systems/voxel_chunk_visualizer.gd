@tool
extends Node3D

## Visualizes voxel chunk boundaries in 3D space
## Useful for debugging and understanding chunk layout

@export var draw_enabled: bool = true:
	set(value):
		draw_enabled = value
		queue_redraw()

@export var chunk_size: int = 32:
	set(value):
		chunk_size = value
		queue_redraw()

@export var voxel_size: float = 1.0:
	set(value):
		voxel_size = value
		queue_redraw()

@export var draw_range: int = 3:
	set(value):
		draw_range = max(1, value)
		queue_redraw()

@export var line_color: Color = Color(0.0, 1.0, 1.0, 0.3):
	set(value):
		line_color = value
		queue_redraw()

var _immediate_mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D

func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	
	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate_mesh
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = line_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.disable_fog = true
	_mesh_instance.material_override = mat
	
	queue_redraw()

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	
	# Auto-redraw when properties change
	if _mesh_instance and _mesh_instance.material_override:
		if _mesh_instance.material_override.albedo_color != line_color:
			_mesh_instance.material_override.albedo_color = line_color

func queue_redraw() -> void:
	if not is_inside_tree() or not Engine.is_editor_hint():
		return
	call_deferred("_draw_chunk_grid")

func _draw_chunk_grid() -> void:
	if not _immediate_mesh or not draw_enabled:
		return
	
	_immediate_mesh.clear_surfaces()
	
	var world_chunk_size := chunk_size * voxel_size
	
	# Draw grid centered around origin
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	for x in range(-draw_range, draw_range + 1):
		for y in range(-draw_range, draw_range + 1):
			for z in range(-draw_range, draw_range + 1):
				var chunk_origin := Vector3(x, y, z) * world_chunk_size
				_draw_chunk_box(chunk_origin, world_chunk_size)
	
	_immediate_mesh.surface_end()

func _draw_chunk_box(origin: Vector3, size: float) -> void:
	var corners := [
		origin + Vector3(0, 0, 0),
		origin + Vector3(size, 0, 0),
		origin + Vector3(size, 0, size),
		origin + Vector3(0, 0, size),
		origin + Vector3(0, size, 0),
		origin + Vector3(size, size, 0),
		origin + Vector3(size, size, size),
		origin + Vector3(0, size, size)
	]
	
	# Bottom face
	_draw_line(corners[0], corners[1])
	_draw_line(corners[1], corners[2])
	_draw_line(corners[2], corners[3])
	_draw_line(corners[3], corners[0])
	
	# Top face
	_draw_line(corners[4], corners[5])
	_draw_line(corners[5], corners[6])
	_draw_line(corners[6], corners[7])
	_draw_line(corners[7], corners[4])
	
	# Vertical edges
	_draw_line(corners[0], corners[4])
	_draw_line(corners[1], corners[5])
	_draw_line(corners[2], corners[6])
	_draw_line(corners[3], corners[7])

func _draw_line(from: Vector3, to: Vector3) -> void:
	_immediate_mesh.surface_add_vertex(from)
	_immediate_mesh.surface_add_vertex(to)
