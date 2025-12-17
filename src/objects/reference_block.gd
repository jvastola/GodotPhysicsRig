extends Node3D
class_name ReferenceBlock

## A paintable reference block for the voxel tool system
## Allows painting individual faces or all faces/sides at once

signal block_saved(block_name: String, texture: ImageTexture)
signal block_selected(block_name: String)
signal paint_mode_changed(mode: PaintMode)

enum PaintMode {
	SINGLE_CELL,    # Paint only the clicked cell
	ALL_FACES,      # Paint all 6 faces at once
	ALL_SIDES       # Paint 4 side faces (not top/bottom)
}

const TILE_PIXELS: int = 16

# Face indices: 0=+X, 1=-X, 2=+Y, 3=-Y, 4=+Z, 5=-Z
const FACE_NORMALS: Array[Vector3] = [
	Vector3(1, 0, 0),   # +X right
	Vector3(-1, 0, 0),  # -X left
	Vector3(0, 1, 0),   # +Y top
	Vector3(0, -1, 0),  # -Y bottom
	Vector3(0, 0, 1),   # +Z front
	Vector3(0, 0, -1)   # -Z back
]

@export var block_size: float = 0.3
@export var paint_mode: PaintMode = PaintMode.SINGLE_CELL
@export var grid_subdivisions: int = 4

var mesh_instance: MeshInstance3D
var collision_body: StaticBody3D
var face_colors: Array[Array] = []  # [face_index][y][x] = Color
var current_texture: ImageTexture
var _library: Dictionary = {}
var _selected_block: String = ""
var _save_path: String = "user://block_library.json"
var _next_block_id: int = 1

static var instance: ReferenceBlock = null


func _ready() -> void:
	instance = self
	add_to_group("reference_block")
	_init_face_colors()
	_create_mesh()
	_load_library()
	_update_texture()


func _exit_tree() -> void:
	if instance == self:
		instance = null
	_save_library()


func _init_face_colors() -> void:
	face_colors.clear()
	for _face_idx in range(6):
		var face_grid: Array = []
		for _y in range(grid_subdivisions):
			var row: Array = []
			for _x in range(grid_subdivisions):
				row.append(Color(0.7, 0.7, 0.7, 1.0))
			face_grid.append(row)
		face_colors.append(face_grid)


func _create_mesh() -> void:
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "BlockMesh"
	add_child(mesh_instance)
	
	# Attach handler script for painting interactions
	var handler_script := preload("res://src/systems/reference_block_handler.gd")
	if handler_script:
		mesh_instance.set_script(handler_script)
	
	# Add collision as child of mesh
	collision_body = StaticBody3D.new()
	collision_body.name = "CollisionBody"
	collision_body.collision_layer = 32
	collision_body.collision_mask = 0
	mesh_instance.add_child(collision_body)
	
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape"
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3.ONE * block_size
	shape.shape = box_shape
	collision_body.add_child(shape)


func _update_texture() -> void:
	current_texture = _build_texture()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = current_texture
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mesh_instance.material_override = mat
	mesh_instance.mesh = _generate_cube_mesh()


func _build_texture() -> ImageTexture:
	# Simple 3x2 atlas: each face gets one slot
	# Row 0: face 0, 1, 2 (+X, -X, +Y)
	# Row 1: face 3, 4, 5 (-Y, +Z, -Z)
	var face_size := grid_subdivisions * TILE_PIXELS
	var img := Image.create(face_size * 3, face_size * 2, false, Image.FORMAT_RGBA8)
	
	for face_idx in range(6):
		var atlas_x := (face_idx % 3) * face_size
		var atlas_y := (face_idx / 3) * face_size
		
		for gy in range(grid_subdivisions):
			for gx in range(grid_subdivisions):
				var color: Color = face_colors[face_idx][gy][gx]
				for py in range(TILE_PIXELS):
					for px in range(TILE_PIXELS):
						img.set_pixel(atlas_x + gx * TILE_PIXELS + px, atlas_y + gy * TILE_PIXELS + py, color)
	
	return ImageTexture.create_from_image(img)


func _generate_cube_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var h := block_size * 0.5
	
	# Define vertices for each face with correct winding (CCW when viewed from outside)
	# Face 0: +X (right)
	_add_face(st, 0,
		Vector3(h, -h, -h), Vector3(h, -h, h), Vector3(h, h, h), Vector3(h, h, -h),
		Vector3(1, 0, 0))
	
	# Face 1: -X (left)
	_add_face(st, 1,
		Vector3(-h, -h, h), Vector3(-h, -h, -h), Vector3(-h, h, -h), Vector3(-h, h, h),
		Vector3(-1, 0, 0))
	
	# Face 2: +Y (top)
	_add_face(st, 2,
		Vector3(-h, h, -h), Vector3(h, h, -h), Vector3(h, h, h), Vector3(-h, h, h),
		Vector3(0, 1, 0))
	
	# Face 3: -Y (bottom)
	_add_face(st, 3,
		Vector3(-h, -h, h), Vector3(h, -h, h), Vector3(h, -h, -h), Vector3(-h, -h, -h),
		Vector3(0, -1, 0))
	
	# Face 4: +Z (front)
	_add_face(st, 4,
		Vector3(h, -h, h), Vector3(-h, -h, h), Vector3(-h, h, h), Vector3(h, h, h),
		Vector3(0, 0, 1))
	
	# Face 5: -Z (back)
	_add_face(st, 5,
		Vector3(-h, -h, -h), Vector3(h, -h, -h), Vector3(h, h, -h), Vector3(-h, h, -h),
		Vector3(0, 0, -1))
	
	return st.commit()


func _add_face(st: SurfaceTool, face_idx: int, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3) -> void:
	# UV coordinates for this face in the atlas
	var u0 := float(face_idx % 3) / 3.0
	var v0_uv := float(face_idx / 3) / 2.0
	var u1 := float((face_idx % 3) + 1) / 3.0
	var v1_uv := float((face_idx / 3) + 1) / 2.0
	
	# Triangle 1: v0, v1, v2
	st.set_normal(normal)
	st.set_uv(Vector2(u0, v1_uv))
	st.add_vertex(v0)
	st.set_normal(normal)
	st.set_uv(Vector2(u1, v1_uv))
	st.add_vertex(v1)
	st.set_normal(normal)
	st.set_uv(Vector2(u1, v0_uv))
	st.add_vertex(v2)
	
	# Triangle 2: v0, v2, v3
	st.set_normal(normal)
	st.set_uv(Vector2(u0, v1_uv))
	st.add_vertex(v0)
	st.set_normal(normal)
	st.set_uv(Vector2(u1, v0_uv))
	st.add_vertex(v2)
	st.set_normal(normal)
	st.set_uv(Vector2(u0, v0_uv))
	st.add_vertex(v3)


## Paint at a local position with a normal
func paint_at(local_pos: Vector3, local_normal: Vector3, color: Color) -> void:
	var face_idx := _get_face_from_normal(local_normal)
	if face_idx < 0:
		print("ReferenceBlock: paint_at - invalid face from normal ", local_normal)
		return
	
	var cell := _get_cell_from_position(local_pos, face_idx)
	print("ReferenceBlock: paint_at face=", face_idx, " cell=", cell, " local_pos=", local_pos)
	
	match paint_mode:
		PaintMode.SINGLE_CELL:
			_set_cell_color(face_idx, cell.x, cell.y, color)
		PaintMode.ALL_FACES:
			for fi in range(6):
				_fill_face(fi, color)
		PaintMode.ALL_SIDES:
			for fi in [0, 1, 4, 5]:  # +X, -X, +Z, -Z
				_fill_face(fi, color)
	
	_update_texture()


func _get_face_from_normal(normal: Vector3) -> int:
	var best_idx := -1
	var best_dot := 0.5  # Threshold
	for i in range(6):
		var dot := normal.dot(FACE_NORMALS[i])
		if dot > best_dot:
			best_dot = dot
			best_idx = i
	return best_idx


func _get_cell_from_position(local_pos: Vector3, face_idx: int) -> Vector2i:
	var h := block_size * 0.5
	var u: float = 0.0
	var v: float = 0.0
	
	# Map local position to UV coordinates (0-1 range)
	# The UV layout matches _add_face: u0,v1 is bottom-left, u1,v0 is top-right
	# So u goes left-to-right, v goes bottom-to-top (but texture y is top-to-bottom)
	match face_idx:
		0:  # +X face: looking from +X toward origin
			# v0=(-h,-h,-h), v1=(-h,-h,h), v2=(-h,h,h), v3=(-h,h,-h) but we're on +X side
			# Actually vertices are: (h,-h,-h), (h,-h,h), (h,h,h), (h,h,-h)
			# UV: v0=(u0,v1), v1=(u1,v1), v2=(u1,v0), v3=(u0,v0)
			# So bottom-left is at z=-h, y=-h and top-right is at z=h, y=h
			u = (local_pos.z / h + 1.0) * 0.5  # z: -h to h -> 0 to 1
			v = 1.0 - (local_pos.y / h + 1.0) * 0.5  # y: -h to h -> 1 to 0 (flip for texture coords)
		1:  # -X face: looking from -X toward origin
			# Vertices: (-h,-h,h), (-h,-h,-h), (-h,h,-h), (-h,h,h)
			u = 1.0 - (local_pos.z / h + 1.0) * 0.5  # z flipped
			v = 1.0 - (local_pos.y / h + 1.0) * 0.5
		2:  # +Y face: looking from +Y down
			# Vertices: (-h,h,-h), (h,h,-h), (h,h,h), (-h,h,h)
			u = (local_pos.x / h + 1.0) * 0.5
			v = (local_pos.z / h + 1.0) * 0.5
		3:  # -Y face: looking from -Y up
			# Vertices: (-h,-h,h), (h,-h,h), (h,-h,-h), (-h,-h,-h)
			u = (local_pos.x / h + 1.0) * 0.5
			v = 1.0 - (local_pos.z / h + 1.0) * 0.5
		4:  # +Z face: looking from +Z toward origin
			# Vertices: (h,-h,h), (-h,-h,h), (-h,h,h), (h,h,h)
			u = 1.0 - (local_pos.x / h + 1.0) * 0.5  # x flipped
			v = 1.0 - (local_pos.y / h + 1.0) * 0.5
		5:  # -Z face: looking from -Z toward origin
			# Vertices: (-h,-h,-h), (h,-h,-h), (h,h,-h), (-h,h,-h)
			u = (local_pos.x / h + 1.0) * 0.5
			v = 1.0 - (local_pos.y / h + 1.0) * 0.5
	
	var cell_x := clampi(int(u * grid_subdivisions), 0, grid_subdivisions - 1)
	var cell_y := clampi(int(v * grid_subdivisions), 0, grid_subdivisions - 1)
	return Vector2i(cell_x, cell_y)


func _set_cell_color(face_idx: int, x: int, y: int, color: Color) -> void:
	if face_idx < 0 or face_idx >= 6:
		return
	if x < 0 or x >= grid_subdivisions or y < 0 or y >= grid_subdivisions:
		return
	face_colors[face_idx][y][x] = color


func _fill_face(face_idx: int, color: Color) -> void:
	if face_idx < 0 or face_idx >= 6:
		return
	for y in range(grid_subdivisions):
		for x in range(grid_subdivisions):
			face_colors[face_idx][y][x] = color


func fill_all_faces(color: Color) -> void:
	for fi in range(6):
		_fill_face(fi, color)
	_update_texture()


func set_paint_mode(mode: PaintMode) -> void:
	paint_mode = mode
	paint_mode_changed.emit(mode)


func get_paint_mode() -> PaintMode:
	return paint_mode


func set_grid_subdivisions(n: int) -> void:
	n = clampi(n, 1, 16)
	if n == grid_subdivisions:
		return
	grid_subdivisions = n
	_init_face_colors()
	_update_texture()
	# Update collision shape
	if collision_body:
		var shape := collision_body.get_node_or_null("CollisionShape") as CollisionShape3D
		if shape and shape.shape is BoxShape3D:
			(shape.shape as BoxShape3D).size = Vector3.ONE * block_size


func get_grid_subdivisions() -> int:
	return grid_subdivisions


# === Library Management ===

func _generate_block_name() -> String:
	var bname := "block%d" % _next_block_id
	while _library.has(bname):
		_next_block_id += 1
		bname = "block%d" % _next_block_id
	_next_block_id += 1
	return bname


func save_to_library(block_name: String = "") -> String:
	if block_name.is_empty():
		block_name = _generate_block_name()
	
	_library[block_name] = {
		"texture": _build_texture(),
		"face_colors": _serialize_face_colors(),
		"grid_subdivisions": grid_subdivisions
	}
	_save_library()
	block_saved.emit(block_name, _library[block_name]["texture"])
	return block_name


func load_from_library(block_name: String) -> bool:
	if not _library.has(block_name):
		return false
	
	var data: Dictionary = _library[block_name]
	if data.has("grid_subdivisions"):
		grid_subdivisions = data["grid_subdivisions"]
		_init_face_colors()
	if data.has("face_colors"):
		_deserialize_face_colors(data["face_colors"])
	
	_update_texture()
	_selected_block = block_name
	block_selected.emit(block_name)
	return true


func select_block(block_name: String) -> void:
	_selected_block = block_name
	block_selected.emit(block_name)


func get_selected_block() -> String:
	return _selected_block


func get_library_names() -> Array[String]:
	var names: Array[String] = []
	for key in _library.keys():
		names.append(key)
	names.sort()
	return names


func get_library_texture(block_name: String) -> ImageTexture:
	if _library.has(block_name) and _library[block_name].has("texture"):
		return _library[block_name]["texture"]
	return null


func delete_from_library(block_name: String) -> void:
	print("ReferenceBlock: Deleting block '%s' from library" % block_name)
	if _library.erase(block_name):
		print("ReferenceBlock: Block '%s' deleted successfully" % block_name)
		_save_library()
		if _selected_block == block_name:
			_selected_block = ""
	else:
		print("ReferenceBlock: Block '%s' not found in library" % block_name)


func get_current_texture() -> ImageTexture:
	return current_texture


func get_average_color() -> Color:
	"""Get average color of all faces for simple voxel coloring.
	Uses current face_colors which are updated when a block is loaded from library."""
	var total := Color(0, 0, 0, 0)
	var count := 0
	for face_idx in range(6):
		for y in range(grid_subdivisions):
			for x in range(grid_subdivisions):
				total += face_colors[face_idx][y][x]
				count += 1
	if count > 0:
		var avg := Color(total.r / count, total.g / count, total.b / count, 1.0)
		print("ReferenceBlock: get_average_color = ", avg, " (selected: ", _selected_block, ")")
		return avg
	return Color(0.7, 0.7, 0.7, 1.0)


func _serialize_face_colors() -> Array:
	var result: Array = []
	for face_idx in range(6):
		var face_data: Array = []
		for y in range(grid_subdivisions):
			var row_data: Array = []
			for x in range(grid_subdivisions):
				var c: Color = face_colors[face_idx][y][x]
				row_data.append({"r": c.r, "g": c.g, "b": c.b, "a": c.a})
			face_data.append(row_data)
		result.append(face_data)
	return result


func _deserialize_face_colors(data: Array) -> void:
	for face_idx in range(min(data.size(), 6)):
		var face_data: Array = data[face_idx]
		for y in range(min(face_data.size(), grid_subdivisions)):
			var row_data: Array = face_data[y]
			for x in range(min(row_data.size(), grid_subdivisions)):
				var cd: Dictionary = row_data[x]
				face_colors[face_idx][y][x] = Color(cd.get("r", 0.7), cd.get("g", 0.7), cd.get("b", 0.7), cd.get("a", 1.0))


func _save_library() -> void:
	var save_data: Dictionary = {}
	for block_name in _library.keys():
		var data: Dictionary = _library[block_name]
		save_data[block_name] = {
			"face_colors": data.get("face_colors", []),
			"grid_subdivisions": data.get("grid_subdivisions", 4)
		}
	var file := FileAccess.open(_save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data))
		file.close()


func _load_library() -> void:
	if not FileAccess.file_exists(_save_path):
		return
	var file := FileAccess.open(_save_path, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return
	file.close()
	
	var data: Variant = json.get_data()
	if not data is Dictionary:
		return
	
	_library.clear()
	for block_name in data.keys():
		var block_data: Dictionary = data[block_name]
		var saved_subdivs: int = block_data.get("grid_subdivisions", 4)
		var face_data: Array = block_data.get("face_colors", [])
		
		# Temporarily set subdivisions to rebuild texture
		var old_subdivs := grid_subdivisions
		grid_subdivisions = saved_subdivs
		_init_face_colors()
		_deserialize_face_colors(face_data)
		
		_library[block_name] = {
			"texture": _build_texture(),
			"face_colors": face_data,
			"grid_subdivisions": saved_subdivs
		}
		
		# Restore
		grid_subdivisions = old_subdivs
	
	_init_face_colors()
	_update_texture()
