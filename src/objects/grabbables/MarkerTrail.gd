# MarkerTrail - Handles drawing trail lines for the VRCMarker pen
# Based on VRCMarker implementation
extends Node3D

# Configuration
@export var trail_position: Node3D
@export var trail_storage: MeshInstance3D
@export var marker: Node

@export var trail_type: int = 0  # 0 = solid color, 1 = gradient
@export var color: Color = Color.WHITE
@export var gradient: Gradient

@export var emission: float = 1.0
@export var min_distance: float = 0.0025
@export var width: float = 0.003
@export var update_rate: float = 0.03
@export var smoothing_time: float = 0.06

# State
var _vertices: PackedVector3Array = PackedVector3Array()
var _uvs: PackedVector2Array = PackedVector2Array() # Added for shader vertex ID passing and width (uv.x = id, uv.y = width)
var _triangles: PackedInt32Array = PackedInt32Array()
var _custom0: PackedFloat32Array = PackedFloat32Array() # Replaces _normals for passing 'other position' safely (uses Floats to avoid clamping/twisting)

const _vertex_limit: int = 32000
var _vertices_used: int = 0
var _last_vertices_used: int = 0
var _triangles_used: int = 0
var _last_triangles_used: int = 0

var _mesh: ArrayMesh
var _time: float = 0.0
var _previous_position: Vector3 = Vector3.ZERO
var _previous_smoothing_position: Vector3 = Vector3.ZERO
var _smoothing_position: Vector3 = Vector3.ZERO

var is_local: bool = true
var _current_width_mult: float = 1.0 # Multiplier for line width based on pressure

var _sync_lines: PackedVector3Array = PackedVector3Array()
var _sync_lines_used: int = 0

const FloatHalfMax: float = 3.402823466e+38 / 2.0
var _inf_bounds: AABB = AABB(Vector3.ZERO, Vector3(FloatHalfMax, FloatHalfMax, FloatHalfMax))

# For smoothing
var _previous_unsmoothed_position: Vector3 = Vector3.ZERO
var _previous_direction_change: Vector3 = Vector3.ONE.normalized()
var _previous_direction: Vector3 = Vector3.ONE.normalized()

# Vertex indices for the last line
var v0: int = 0
var v1: int = 0
var v2: int = 0
var v3: int = 0
var v4: int = 0
var v5: int = 0
var v6: int = 0

const VertexIncrement: int = 7
const TriangleIncrement: int = 9

signal started_writing
signal stopped_writing


func _ready() -> void:
	if not trail_storage:
		trail_storage = get_node_or_null("TrailStorage")
	if not trail_position:
		trail_position = get_node_or_null("TipPosition")
	
	# Debug logging
	print("MarkerTrail: trail_storage = ", trail_storage)
	print("MarkerTrail: trail_position = ", trail_position)
	if trail_position:
		print("MarkerTrail: trail_position.global_position = ", trail_position.global_position)
	
	# Create mesh
	_mesh = ArrayMesh.new()
	
	if trail_storage:
		trail_storage.mesh = _mesh
		# Decouple from parent transform so global coordinates work correctly
		trail_storage.top_level = true
		trail_storage.global_transform = Transform3D.IDENTITY
	
	# Create materials
	var renderer = trail_storage.get_node_or_null("MeshInstance3D") if trail_storage else null
	if not renderer:
		renderer = trail_storage
	
	if trail_type == 0:
		# Solid color
		if renderer and renderer is MeshInstance3D:
			# Check if we already have a shader material (assigned in scene) and preserve it
			if renderer.material_override is ShaderMaterial:
				var smat = renderer.material_override as ShaderMaterial
				smat.set_shader_parameter("line_color", color)
				smat.set_shader_parameter("emission_strength", emission)
			else:
				var mat = StandardMaterial3D.new()
				mat.albedo_color = color * emission
				mat.emission_enabled = true
				mat.emission = color * emission
				mat.emission_energy_multiplier = emission
				renderer.material_override = mat
	elif trail_type == 1:
		# Gradient
		if renderer and renderer is MeshInstance3D:
			var mat = ShaderMaterial.new()
			# Use a simple shader for gradient
			var shader = Shader.new()
			shader.code = """
				shader_type spatial;
				render_mode unshaded;
				
				uniform vec4 color1 : source_color = vec4(1, 1, 1, 1);
				uniform vec4 color2 : source_color = vec4(0, 0, 1, 1);
				uniform float gradient_length : hint_range(1, 10) = 5.0;
				
				void fragment() {
					float t = mod(TIME, gradient_length) / gradient_length;
					ALBEDO = mix(color1.rgb, color2.rgb, t);
					ALPHA = 1.0;
				}
			"""
			mat.shader = shader
			renderer.material_override = mat
	
	# Initialize sync lines array
	_sync_lines.resize(100)
	
	# Reset transforms
	reset_transforms()
	
	set_process(false)


func reset_transforms() -> void:
	"""Reset transforms to fix culling issues"""
	if is_instance_valid(trail_storage):
		var parent = trail_storage.get_parent()
		trail_storage.get_parent().remove_child(trail_storage)
		trail_storage.scale = Vector3.ONE
		if parent:
			parent.add_child(trail_storage)
		trail_storage.position = Vector3.ZERO
		trail_storage.rotation = Vector3.ZERO


func start_writing() -> void:
	if is_processing():
		print("MarkerTrail: start_writing called but already processing")
		return
	
	_time = 0.0
	_last_vertices_used = _vertices_used
	_last_triangles_used = _triangles_used
	
	var pos = trail_position.global_position if trail_position else global_position
	print("MarkerTrail: start_writing at position ", pos)
	print("MarkerTrail: trail_position = ", trail_position)
	print("MarkerTrail: global_position = ", global_position)
	_smoothing_position = pos
	_previous_smoothing_position = pos
	_previous_position = pos
	create_trail_line(pos, pos)
	
	store_last_lines_transform(pos)
	update_mesh_data()
	
	create_trail_line(pos, pos)  # for point at tip
	
	set_process(true)
	print("MarkerTrail: Started processing, _vertices_used = ", _vertices_used)
	emit_signal("started_writing")


func stop_writing() -> void:
	if not is_processing():
		print("MarkerTrail: stop_writing called but not processing")
		return
	
	print("MarkerTrail: stop_writing, _vertices_used = ", _vertices_used)
	set_process(false)
	
	_time = 0.0
	
	if is_local and get_sync_lines().size() > 1:
		store_last_lines_transform(_smoothing_position)
		recalculate_mesh_bounds()
	
	print("MarkerTrail: Stopped writing")
	emit_signal("stopped_writing")


func _process(delta: float) -> void:
	if not is_processing():
		return
	
	_time += delta
	
	var tip_position = trail_position.global_position if trail_position else global_position
	# Debug logging (only log occasionally to avoid spam)
	if _time > 0.1 and _time < 0.2:
		print("MarkerTrail: tip_position = ", tip_position)
		print("MarkerTrail: _vertices_used = ", _vertices_used)
	_smoothing_position = _previous_smoothing_position.lerp(tip_position, delta / smoothing_time)
	_previous_smoothing_position = _smoothing_position
	
	var current_direction = tip_position - _previous_unsmoothed_position
	_previous_unsmoothed_position = tip_position
	
	update_last_position(_smoothing_position, _previous_position)
	update_mesh_data()
	
	if _time <= update_rate or _smoothing_position.distance_to(_previous_position) < min_distance:
		return
	
	if not (_time >= update_rate and _smoothing_position.distance_to(_previous_position) > min_distance and
		(_previous_direction.cross(tip_position - _previous_position).length() > 0.001 or
		 _previous_direction_change.angle_to(current_direction) > 25.0)):
		return
	
	if current_direction != Vector3.ZERO:
		_previous_direction_change = current_direction.normalized()
	
	_previous_direction = (tip_position - _previous_position).normalized()
	
	create_trail_line(_previous_position, _smoothing_position)
	store_last_lines_transform(_smoothing_position)
	
	if _sync_lines_used == 6:
		# prevent wrong first lines from object sync
		if marker and marker.has_method("start_writing_remote"):
			marker.start_writing_remote()
	
	_previous_position = _smoothing_position
	_time = 0.0


func set_pressure(pressure: float) -> void:
	# Map pressure 0.0-1.0 to width multiplier 0.2-1.5
	_current_width_mult = lerp(0.2, 1.5, pressure)


func create_trail_line(end: Vector3, start: Vector3) -> void:
	print("MarkerTrail: create_trail_line from ", start, " to ", end)
	update_array_size(VertexIncrement, TriangleIncrement)
	
	v0 = _vertices_used
	v1 = _vertices_used + 1
	v2 = _vertices_used + 2
	v3 = _vertices_used + 3
	v4 = _vertices_used + 4
	v5 = _vertices_used + 5
	v6 = _vertices_used + 6
	
	var t0 = _triangles_used
	var t1 = _triangles_used + 1
	var t2 = _triangles_used + 2
	var t3 = _triangles_used + 3
	var t4 = _triangles_used + 4
	var t5 = _triangles_used + 5
	var t6 = _triangles_used + 6
	var t7 = _triangles_used + 7
	var t8 = _triangles_used + 8
	
	# Line
	_vertices[v0] = start
	_vertices[v1] = start
	_vertices[v2] = end
	_vertices[v3] = end
	
	_triangles[t0] = v0
	_triangles[t1] = v1
	_triangles[t2] = v2
	_triangles[t3] = v0
	_triangles[t4] = v2
	_triangles[t5] = v3
	
	# Store end position in custom0 for shader access (replaces NORMAL)
	# PackedFloat32Array needs 3 components per vertex
	var i0 = v0 * 3
	_custom0[i0] = end.x; _custom0[i0+1] = end.y; _custom0[i0+2] = end.z
	
	var i1 = v1 * 3
	_custom0[i1] = end.x; _custom0[i1+1] = end.y; _custom0[i1+2] = end.z
	
	var i2 = v2 * 3
	_custom0[i2] = start.x; _custom0[i2+1] = start.y; _custom0[i2+2] = start.z
	
	var i3 = v3 * 3
	_custom0[i3] = start.x; _custom0[i3+1] = start.y; _custom0[i3+2] = start.z
	
	# Store vertex IDs in UVs for shader displacement (x = id, y = width multiplier)
	_uvs[v0] = Vector2(0, _current_width_mult)
	_uvs[v1] = Vector2(1, _current_width_mult)
	_uvs[v2] = Vector2(2, _current_width_mult)
	_uvs[v3] = Vector2(3, _current_width_mult)
	
	# Triangle (circle)
	_vertices[v4] = start
	_vertices[v5] = start
	_vertices[v6] = start
	
	_triangles[t6] = v6
	_triangles[t7] = v5
	_triangles[t8] = v4
	
	var i4 = v4 * 3
	_custom0[i4] = end.x; _custom0[i4+1] = end.y; _custom0[i4+2] = end.z
	
	var i5 = v5 * 3
	_custom0[i5] = end.x; _custom0[i5+1] = end.y; _custom0[i5+2] = end.z
	
	var i6 = v6 * 3
	_custom0[i6] = end.x; _custom0[i6+1] = end.y; _custom0[i6+2] = end.z
	
	_uvs[v4] = Vector2(4, _current_width_mult)
	_uvs[v5] = Vector2(5, _current_width_mult)
	_uvs[v6] = Vector2(6, _current_width_mult)
	
	_vertices_used += VertexIncrement
	_triangles_used += TriangleIncrement


func update_last_position(start: Vector3, end: Vector3) -> void:
	if v1 == 0:
		return
	
	_vertices[v0] = start
	_vertices[v1] = start
	_vertices[v2] = end
	_vertices[v3] = end
	
	_vertices[v4] = start
	_vertices[v5] = start
	_vertices[v6] = start
	
	var i0 = v0 * 3
	_custom0[i0] = end.x; _custom0[i0+1] = end.y; _custom0[i0+2] = end.z
	
	var i1 = v1 * 3
	_custom0[i1] = end.x; _custom0[i1+1] = end.y; _custom0[i1+2] = end.z
	
	var i2 = v2 * 3
	_custom0[i2] = start.x; _custom0[i2+1] = start.y; _custom0[i2+2] = start.z
	
	var i3 = v3 * 3
	_custom0[i3] = start.x; _custom0[i3+1] = start.y; _custom0[i3+2] = start.z


func update_mesh_data() -> void:
	if not _mesh:
		print("MarkerTrail: update_mesh_data called but _mesh is null")
		return
	
	print("MarkerTrail: update_mesh_data, _vertices_used = ", _vertices_used, ", _triangles_used = ", _triangles_used)
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_INDEX] = _triangles
	# arrays[Mesh.ARRAY_NORMAL] = _normals # No longer using normals
	arrays[Mesh.ARRAY_CUSTOM0] = _custom0 # Pass floats directly, do NOT convert to bytes when using RGB_FLOAT flag
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	
	_mesh.clear_surfaces()
	# Note: Using PRIMITIVE_TRIANGLES.
	# We must specify the format of the custom channel since we are passing raw bytes.
	# Using RGB Float (12 bytes per vertex) for the custom0 channel.
	var format_custom0 = (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format_custom0)
	_mesh.custom_aabb = _inf_bounds
	print("MarkerTrail: Mesh updated")


func store_last_lines_transform(pos: Vector3) -> void:
	if not is_local:
		return
	
	if _sync_lines_used > _sync_lines.size() - 1:
		return
	
	_sync_lines[_sync_lines_used] = pos
	_sync_lines_used += 1


func get_last_line_position() -> Vector3:
	if _vertices_used == 0:
		return Vector3.ZERO
	
	return _vertices[_vertices_used]


func remove_last_line_connection() -> int:
	if _vertices_used == 0:
		return 0
	
	var break_count = _vertices_used - 500
	var count = _vertices_used
	
	remove_last_line()
	if not is_last_position_end_of_line():
		for i in range(count - 1, break_count - 1, -7):
			if _vertices_used <= 0:
				break
			remove_last_line()
			if is_last_position_end_of_line():
				remove_last_line()
				break
	
	update_mesh_data()
	
	return count - _vertices_used


func remove_last_line() -> void:
	if _vertices_used == 0 or not marker_initialized():
		return
	
	var new_vertex_count = _vertices_used - VertexIncrement
	for i in range(new_vertex_count, _vertices_used):
		_vertices[i] = Vector3.ZERO
	
	_vertices_used = new_vertex_count


func remove_last_lines(lines: int) -> void:
	if _vertices_used == 0 or not marker_initialized():
		return
	
	var new_vertex_count = _vertices_used - lines
	if new_vertex_count < 0:
		return
	
	for i in range(new_vertex_count, _vertices_used):
		_vertices[i] = Vector3.ZERO
	
	_vertices_used = new_vertex_count
	
	update_mesh_data()


func is_last_position_end_of_line() -> bool:
	if _vertices_used <= VertexIncrement:
		return false
	
	var start_pos = _vertices[_vertices_used - 1]
	var end_pos = _vertices[_vertices_used - 4]
	return start_pos == end_pos


func marker_initialized() -> bool:
	return _vertices.size() != 0 and _vertices_used != 0


func get_sync_lines() -> PackedVector3Array:
	var arr = PackedVector3Array()
	arr.resize(_sync_lines_used)
	for i in range(_sync_lines_used):
		arr[i] = _sync_lines[i]
	return arr


func reset_sync_lines() -> void:
	_sync_lines_used = 0


func update_array_size(vertices_reserved: int, triangles_reserved: int) -> void:
	const multiplier: int = 100
	triangles_reserved *= multiplier
	vertices_reserved *= multiplier
	
	var v_count = _vertices_used + vertices_reserved
	if v_count > _vertices.size():
		if v_count > _vertex_limit:
			_vertices_used = 0
			_triangles_used = 0
			return
		_vertices = resize_array(_vertices, vertices_reserved)
		_custom0 = resize_array_float(_custom0, vertices_reserved * 3) # 3 floats per vertex
		_uvs = resize_array_vector2(_uvs, vertices_reserved)
	
	if _triangles_used + triangles_reserved > _triangles.size():
		_triangles = resize_array_int(_triangles, triangles_reserved)


func resize_array(source_array: PackedVector3Array, increment_size: int) -> PackedVector3Array:
	var new_array = PackedVector3Array()
	new_array.resize(increment_size + source_array.size())
	for i in range(source_array.size()):
		new_array[i] = source_array[i]
	return new_array


func resize_array_float(source_array: PackedFloat32Array, increment_size: int) -> PackedFloat32Array:
	var new_array = PackedFloat32Array()
	new_array.resize(increment_size + source_array.size())
	for i in range(source_array.size()):
		new_array[i] = source_array[i]
	return new_array


func resize_array_int(source_array: PackedInt32Array, increment_size: int) -> PackedInt32Array:
	var new_array = PackedInt32Array()
	new_array.resize(increment_size + source_array.size())
	for i in range(source_array.size()):
		new_array[i] = source_array[i]
	return new_array


func resize_array_vector2(source_array: PackedVector2Array, increment_size: int) -> PackedVector2Array:
	var new_array = PackedVector2Array()
	new_array.resize(increment_size + source_array.size())
	for i in range(source_array.size()):
		new_array[i] = source_array[i]
	return new_array


func recalculate_mesh_bounds() -> void:
	if _mesh:
		_mesh.custom_aabb = _inf_bounds


func clear() -> void:
	_time = 0.0
	_vertices = PackedVector3Array()
	_uvs = PackedVector2Array()
	_triangles = PackedInt32Array()
	_custom0 = PackedFloat32Array()
	
	if _mesh:
		_mesh.clear_surfaces()
	
	_vertices_used = 0
	_triangles_used = 0
	_last_vertices_used = 0
	_last_triangles_used = 0
	reset_sync_lines()
