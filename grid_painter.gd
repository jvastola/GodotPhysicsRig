
extends Node3D
class_name GridPainter

# GridPainter.gd
# Creates an NxN paintable color grid, builds an atlas texture, applies to the
# host mesh, and can also apply the same texture to a linked mesh whose UVs
# are expected to be mapped to the same NxN grid.
#
# Usage:
# - Attach to any Node in the scene (for example the MeshInstance you want to
#   paint), then set `target_mesh` to the MeshInstance3D to which the generated
#   texture will be applied. Optionally set `linked_mesh` if you want another
#   mesh to share the same texture.
# - Click `randomize_grid()` (or call from script) to create random colors.
# - Use `set_cell_color(x,y,color)` to paint single cells and `apply_texture()`
#   to update the mesh material.

# Grid sizing is computed from `subdivisions_axis` to match cube atlas layout.
# The painter exposes `subdivisions_axis` and `generate_on_ready` for random coloring.

# Internal grid size (in cells) computed from subdivisions_axis into an atlas layout
var _grid_size_x: int = 8
var _grid_size_y: int = 8

# Tile pixel resolution per cell (internal constant)
const TILE_PIXELS: int = 16
@export var target_mesh: NodePath = NodePath(".")
@export var linked_mesh: NodePath = NodePath("")
@export var generate_on_ready: bool = false

# Internal grid: rows = grid_size, columns = grid_size; index [y][x]
var _grid_colors: Array = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _face_cell_dims: Array = []
var _face_offsets: Array = []

# Face definitions used to compute per-face subdivision dims (matches `subdivided_cube.gd`)
const FACE_DEFS: Array = [
	{"n": Vector3(0, 0, 1), "u": Vector3(1, 0, 0), "v": Vector3(0, 1, 0)},
	{"n": Vector3(0, 0, -1), "u": Vector3(-1, 0, 0), "v": Vector3(0, 1, 0)},
	{"n": Vector3(1, 0, 0), "u": Vector3(0, 0, -1), "v": Vector3(0, 1, 0)},
	{"n": Vector3(-1, 0, 0), "u": Vector3(0, 0, 1), "v": Vector3(0, 1, 0)},
	{"n": Vector3(0, 1, 0), "u": Vector3(1, 0, 0), "v": Vector3(0, 0, -1)},
	{"n": Vector3(0, -1, 0), "u": Vector3(1, 0, 0), "v": Vector3(0, 0, 1)}
]

func _count_for_axis(axis: Vector3, axis_counts: Vector3i) -> int:
	var abs_axis := axis.abs()
	if abs_axis.x > 0.5:
		return axis_counts.x
	elif abs_axis.y > 0.5:
		return axis_counts.y
	else:
		return axis_counts.z

# Cached generated texture
var _texture: ImageTexture = null

func _ready():
	# Apply exported subdivisions (maps Vector3i -> grid_size_x/grid_size_y) and build initial grid
	set_subdivisions_from_axis(subdivisions_axis)
	# Load saved grid data if exists
	load_grid_data()
	# Apply the loaded texture to meshes
	apply_texture()
	# Ensure material applied early if added in editor with linked meshes
	_texture = _build_texture_from_grid()
	if generate_on_ready:
		randomize_grid()
		apply_texture()

	# Attach handler script to target and linked meshes at runtime so the scene doesn't
	# require a separate ext_resource for it which may cause parse-time errors.
	# This keeps the scene clean and avoids id conflicts in text resources.
	var handler_script: Script = null
	# prefer to preload the handler if present
	if FileAccess.file_exists("res://grid_painter_handler.gd"):
		handler_script = preload("res://grid_painter_handler.gd")
	if handler_script:
		var tnode := get_node_or_null(target_mesh)
		if tnode and tnode is MeshInstance3D:
			tnode.set_script(handler_script)
			# set painter property for handler to point back to this GridPainter
			if tnode.has_method("set"):
				tnode.set("painter", self.get_path())
		var lnode := get_node_or_null(linked_mesh)
		if lnode and lnode is MeshInstance3D:
			lnode.set_script(handler_script)
			if lnode.has_method("set"):
				lnode.set("painter", self.get_path())

func _reset_grid() -> void:
	_grid_colors = []
	for y in range(_grid_h()):
		var row := []
		for x in range(_grid_w()):
			row.append(Color(0,0,0,0))
		_grid_colors.append(row)
	# rebuild cached texture
	_texture = null

func randomize_grid() -> void:
	"""Fill the grid with random colors (per-cell random RGB, alpha=1).
	Matches the behavior of `subdivided_cube` random paint generation.
	"""
	_rng.randomize()
	for y in range(_grid_h()):
		for x in range(_grid_w()):
			_grid_colors[y][x] = Color(_rng.randf(), _rng.randf(), _rng.randf(), 1.0)
	# Generated new texture
	_texture = _build_texture_from_grid()

func _build_texture_from_grid() -> ImageTexture:
	"""Create an ImageTexture from _grid_colors using tile_pixels per cell.

	Supports rectangular grids via `grid_size_x` and `grid_size_y`.
	"""
	var w := int(_grid_w() * TILE_PIXELS)
	var h := int(_grid_h() * TILE_PIXELS)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for gy in range(_grid_h()):
		for gx in range(_grid_w()):
			var c: Color = _grid_colors[gy][gx]
			# fill tile
			for py in range(TILE_PIXELS):
				for px in range(TILE_PIXELS):
					img.set_pixel(gx * TILE_PIXELS + px, gy * TILE_PIXELS + py, c)
	# No explicit lock/unlock needed in Godot 4; Image.set_pixel is safe to call directly.
	return ImageTexture.create_from_image(img)

func apply_texture(to_target: bool = true, to_linked: bool = true) -> void:
	"""Apply the built texture to `target_mesh` and `linked_mesh` materials.
	`target_mesh` path is required to be a MeshInstance3D node, as is `linked_mesh`.
	Also generates and applies a cube mesh with proper UVs for the atlas layout.
	"""
	if not _texture:
		_texture = _build_texture_from_grid()
	
	# Generate cube mesh with correct UVs if face dims are initialized
	var cube_mesh: ArrayMesh = null
	if _face_cell_dims.size() == 6 and _face_offsets.size() == 6:
		cube_mesh = _generate_cube_mesh_with_uvs(Vector3(1, 1, 1))
	
	if to_target and target_mesh != NodePath(""):
		var node := get_node_or_null(target_mesh)
		if node and node is MeshInstance3D:
			print("GridPainter: Applying texture to target_mesh %s" % [target_mesh])
			# Apply the cube mesh with correct UVs
			if cube_mesh:
				node.mesh = cube_mesh
				print("GridPainter: Assigned cube mesh to target_mesh")
			
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = _texture
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			if "cull_mode" in mat:
				mat.cull_mode = BaseMaterial3D.CULL_BACK
			node.material_override = mat
			print("GridPainter: Applied material to target_mesh")
		else:
			push_warning("GridPainter: target_mesh is not a MeshInstance3D: %s" % [target_mesh])
	if to_linked and linked_mesh != NodePath(""):
		var ln := get_node_or_null(linked_mesh)
		if ln and ln is MeshInstance3D:
			print("GridPainter: Applying texture to linked_mesh %s" % [linked_mesh])
			# Apply the cube mesh with correct UVs
			if cube_mesh:
				ln.mesh = cube_mesh
				print("GridPainter: Assigned cube mesh to linked_mesh")
			
			var lmat := StandardMaterial3D.new()
			lmat.albedo_texture = _texture
			lmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			if "cull_mode" in lmat:
				lmat.cull_mode = BaseMaterial3D.CULL_BACK
			ln.material_override = lmat
			print("GridPainter: Applied material to linked_mesh")
		else:
			push_warning("GridPainter: linked_mesh is not a MeshInstance3D: %s" % [linked_mesh])

func get_cell_color(x: int, y: int) -> Color:
	if x < 0 or x >= _grid_w() or y < 0 or y >= _grid_h():
		return Color(0,0,0,0)
	return _grid_colors[y][x]

func set_cell_color(x: int, y: int, c: Color) -> void:
	if x < 0 or x >= _grid_w() or y < 0 or y >= _grid_h():
		return
	_grid_colors[y][x] = c
	# rebuild only that tile
	_texture = _build_texture_from_grid()
	# If target mesh exists, update automatically
	apply_texture()
	# Save the grid data after change
	print("GridPainter: Saving grid data due to cell change at (%d, %d)" % [x, y])
	save_grid_data()

func fill_color(c: Color) -> void:
	for y in range(_grid_h()):
		for x in range(_grid_w()):
			_grid_colors[y][x] = c
	_texture = _build_texture_from_grid()
	apply_texture()

func paint_at_uv(uv: Vector2, color: Color) -> void:
	"""Paint a cell given UV coordinates in 0..1 range. 
	This assumes the target/linked mesh uses UVs matching the NxN grid layout (each cell covers 1/grid_size across U and V).
	"""
	if uv.x < 0 or uv.x > 1 or uv.y < 0 or uv.y > 1:
		return
	var gx := int(clamp(floor(uv.x * _grid_w()), 0, _grid_w() - 1))
	var gy := int(clamp(floor(uv.y * _grid_h()), 0, _grid_h() - 1))
	set_cell_color(gx, gy, color)

func save_grid_to_disk(path: String) -> void:
	# saves as PNG
	if not _texture:
		_texture = _build_texture_from_grid()
	var img := _texture.get_image()
	img.save_png(path)

func save_grid_data(path: String = "user://grid_painter_save.json") -> void:
	"""Save the grid colors and subdivisions to a JSON file for persistence."""
	print("GridPainter: Saving grid data to %s" % [path])
	var non_transparent = 0
	for row in _grid_colors:
		for c in row:
			if c.a > 0:
				non_transparent += 1
	print("GridPainter: Saving grid with %d total cells, %d non-transparent" % [_grid_colors.size() * _grid_colors[0].size(), non_transparent])
	var grid_data = []
	for row in _grid_colors:
		var row_data = []
		for c in row:
			row_data.append({"r": c.r, "g": c.g, "b": c.b, "a": c.a})
		grid_data.append(row_data)
	var data = {
		"grid": grid_data,
		"subdivisions": {
			"x": subdivisions_axis.x,
			"y": subdivisions_axis.y,
			"z": subdivisions_axis.z
		}
	}
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()
		print("GridPainter: Grid data saved successfully.")
	else:
		push_error("Failed to open file for saving: " + path)

func load_grid_data(path: String = "user://grid_painter_save.json") -> void:
	"""Load the grid colors and subdivisions from a JSON file."""
	print("GridPainter: Loading grid data from %s" % [path])
	if not FileAccess.file_exists(path):
		print("GridPainter: Save file does not exist, starting with default grid.")
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to open file for loading: " + path)
		return
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()
	if error != OK:
		push_error("Failed to parse save file: " + str(error))
		return
	var data = json.get_data()
	if "subdivisions" in data:
		subdivisions_axis = Vector3i(data["subdivisions"]["x"], data["subdivisions"]["y"], data["subdivisions"]["z"])
		set_subdivisions_from_axis(subdivisions_axis)
	if "grid" in data:
		var saved_grid = data["grid"]
		# Check if sizes match
		if saved_grid.size() == _grid_h() and saved_grid.size() > 0 and saved_grid[0].size() == _grid_w():
			# Load colors from dicts or strings
			for y in range(saved_grid.size()):
				for x in range(saved_grid[y].size()):
					var cd = saved_grid[y][x]
					if cd is Dictionary:
						_grid_colors[y][x] = Color(cd["r"], cd["g"], cd["b"], cd["a"])
					elif cd is String:
						# Parse the string like "(r, g, b, a)"
						var parts = cd.trim_prefix("(").trim_suffix(")").split(", ")
						if parts.size() == 4:
							_grid_colors[y][x] = Color(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]))
						else:
							_grid_colors[y][x] = Color(0, 0, 0, 0)  # default
					else:
						_grid_colors[y][x] = Color(0, 0, 0, 0)  # default
			var non_transparent = 0
			for row in _grid_colors:
				for c in row:
					if c.a > 0:
						non_transparent += 1
			print("GridPainter: Loaded grid with %d total cells, %d non-transparent" % [_grid_colors.size() * _grid_colors[0].size(), non_transparent])
			print("GridPainter: Grid data loaded successfully.")
		else:
			push_warning("Saved grid size doesn't match current subdivisions, keeping current grid")
	_texture = _build_texture_from_grid()


# --- New: support subdivisions per-axis helper (for cube-like workflows)
@export var subdivisions_axis: Vector3i = Vector3i(8, 8, 1)

func set_subdivisions_from_axis(axis_counts: Vector3i) -> void:
	"""Helper: set grid X/Y from a Vector3i subdivisions axis (x -> grid_size_x, y -> grid_size_y).
	This keeps the 2D grid painter compatible with simple cube workflows where Z is unused for the atlas.
	"""
	# If axis_counts is provided, compute per-face dims and then compute
	# atlas width/height (in cells) so the generated texture matches
	# how `subdivided_cube` arranges faces into the atlas.
	if axis_counts == null:
		# default to the exported subdivisions_axis if caller didn't provide one
		axis_counts = subdivisions_axis

	# Compute per-face dims similar to subdivided_cube
	var axis_counts_clamped := Vector3i(max(1, int(axis_counts.x)), max(1, int(axis_counts.y)), max(1, int(axis_counts.z)))
	var face_dims: Array = []
	for face in FACE_DEFS:
		var u_div := _count_for_axis(face["u"], axis_counts_clamped)
		var v_div := _count_for_axis(face["v"], axis_counts_clamped)
		face_dims.append(Vector2i(u_div, v_div))

	# Debug: optionally print mapping to help verify Z-axis mapping
	if developer_mode:
		print("GridPainter: set_subdivisions_from_axis -> axis_counts_clamped=", axis_counts_clamped)
		for i in range(face_dims.size()):
			print("  face", i, "dims=", face_dims[i])

	# Arrange faces into the same 3x2 layout used by subdivided_cube._generate_texture_from_cells
	# Arrange faces into rows (tight packing per-face across each row)
	var row_faces := [[3, 4, 2], [1, 0, 5]]

	# For each row, compute each face's width (face_dims[fi].x) and the row height (max of face y dims)
	var row_widths: Array = []
	var row_face_x_offsets: Array = [] # array of arrays for per-face x offsets in each row
	var row_heights: Array = []
	for row_idx in range(row_faces.size()):
		var faces: Array = row_faces[row_idx]
		var offsets: Array = []
		var acc_x: int = 0
		for j in range(faces.size()):
			var fi: int = int(faces[j])
			offsets.append(acc_x)
			acc_x += int(face_dims[fi].x)
		row_face_x_offsets.append(offsets)
		row_widths.append(acc_x)
		# row height is max y among faces in the row
		var rh: int = 0
		for j in range(faces.size()):
			var fi2: int = int(faces[j])
			rh = max(rh, int(face_dims[fi2].y))
		row_heights.append(rh)

	# total atlas size in cells: width is the widest row, height is sum of row heights
	var tex_w := 0
	for w in row_widths:
		tex_w = max(tex_w, w)
	var tex_h := 0
	for h in row_heights:
		tex_h += h

	_grid_size_x = max(1, tex_w)
	_grid_size_y = max(1, tex_h)

	# rebuild internal grid to match new dims
	# compute per-face offsets (x,y in cells) for this packing
	_face_cell_dims = face_dims
	_face_offsets.clear()
	var y_acc := 0
	for row_i in range(row_faces.size()):
		var faces: Array = row_faces[row_i]
		for fi_i in range(faces.size()):
			var fi: int = int(faces[fi_i])
			var ox: int = int(row_face_x_offsets[row_i][fi_i])
			_face_offsets.append(Vector2i(ox, y_acc))
		y_acc += int(row_heights[row_i])

	_reset_grid()
	_texture = _build_texture_from_grid()

	if developer_mode:
		print("GridPainter face offsets:")
		for i in range(_face_offsets.size()):
			print(" face", i, "offset=", _face_offsets[i], "dims=", _face_cell_dims[i])
		# Log top face cell count (face index 4 is the top face in FACE_DEFS)
		var top_index: int = 4
		if top_index >= 0 and top_index < _face_cell_dims.size():
			var top_dims: Vector2i = _face_cell_dims[top_index]
			var top_cells: int = int(top_dims.x) * int(top_dims.y)
			print("GridPainter: Top face (index", top_index, ") dims=", top_dims, "cells=", top_cells)


func _grid_w() -> int:
	# Primary width: internal computed grid size
	if _grid_size_x > 0:
		return _grid_size_x
	return 1

func _grid_h() -> int:
	# Primary height: internal computed grid size
	if _grid_size_y > 0:
		return _grid_size_y
	return 1

# Editor helpers
func _exit_tree():
	# Save grid data when the node exits
	save_grid_data()

# Simple sanity methods making script usable from in-editor with buttons
func _editor_randomize_grid() -> void: randomize_grid(); apply_texture()
func _editor_apply_texture() -> void: apply_texture()
func _editor_save_grid_png(path: String = "res://grid_painter_output.png") -> void: save_grid_to_disk(path)

func _editor_apply_subdivisions() -> void:
	"""Editor helper: apply the exported `subdivisions_axis`, randomize colors, and apply texture.
	Call this from the Editor to force the GridPainter to update when you change `subdivisions_axis`.
	"""
	set_subdivisions_from_axis(subdivisions_axis)
	randomize_grid()
	apply_texture()

func _generate_cube_mesh_with_uvs(cube_size: Vector3 = Vector3(1, 1, 1)) -> ArrayMesh:
	"""Generate a cube mesh with UVs mapped to the tight-packed atlas layout.
	Each face uses its correct subdivision dims from _face_cell_dims and _face_offsets.
	"""
	if _face_cell_dims.size() != 6 or _face_offsets.size() != 6:
		push_error("GridPainter: face dims/offsets not initialized. Call set_subdivisions_from_axis first.")
		return null
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var atlas_w: float = float(_grid_w())
	var atlas_h: float = float(_grid_h())
	
	# Generate each face with proper UVs
	for fi in range(FACE_DEFS.size()):
		var face: Dictionary = FACE_DEFS[fi]
		var n: Vector3 = face["n"]
		var u: Vector3 = face["u"]
		var v: Vector3 = face["v"]
		
		# Face dims and offset in atlas (in cells)
		var dims: Vector2i = _face_cell_dims[fi]
		var offset: Vector2i = _face_offsets[fi]
		
		# UV coords in atlas (0..1 range)
		var uv_x0: float = float(offset.x) / atlas_w
		var uv_y0: float = float(offset.y) / atlas_h
		var uv_x1: float = float(offset.x + dims.x) / atlas_w
		var uv_y1: float = float(offset.y + dims.y) / atlas_h
		
		# Quad corners in 3D space
		var p00: Vector3 = ((u * -0.5) + (v * -0.5) + n * 0.5) * cube_size
		var p10: Vector3 = ((u * 0.5) + (v * -0.5) + n * 0.5) * cube_size
		var p11: Vector3 = ((u * 0.5) + (v * 0.5) + n * 0.5) * cube_size
		var p01: Vector3 = ((u * -0.5) + (v * 0.5) + n * 0.5) * cube_size
		
		var normal: Vector3 = n.normalized()
		
		# Triangles in counter-clockwise order for outward normal
		# triangle 1: p00, p01, p11
		st.set_normal(normal)
		st.set_uv(Vector2(uv_x0, uv_y0))
		st.add_vertex(p00)
		st.set_normal(normal)
		st.set_uv(Vector2(uv_x0, uv_y1))
		st.add_vertex(p01)
		st.set_normal(normal)
		st.set_uv(Vector2(uv_x1, uv_y1))
		st.add_vertex(p11)
		# triangle 2: p00, p11, p10
		st.set_normal(normal)
		st.set_uv(Vector2(uv_x0, uv_y0))
		st.add_vertex(p00)
		st.set_normal(normal)
		st.set_uv(Vector2(uv_x1, uv_y1))
		st.add_vertex(p11)
		st.set_normal(normal)
		st.set_uv(Vector2(uv_x1, uv_y0))
		st.add_vertex(p10)
	
	return st.commit()

# Optional: expose as callable tool methods for EditorPlugin or remote calls
@export var developer_mode: bool = false

func debug_print_grid() -> void:
	if not developer_mode:
		return
	for y in range(_grid_h()):
		var line := ""
		for x in range(_grid_w()):
			line += "%s " % [_grid_colors[y][x]]
		print(line)
