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

@export var grid_size: int = 8
@export var tile_pixels: int = 16
@export var random_seed: int = 0
@export var default_palette: Array = [Color(1, 0, 0), Color(0,1,0), Color(0,0,1), Color(1,1,0), Color(1,0,1), Color(0,1,1)]
@export var target_mesh: NodePath = NodePath(".")
@export var linked_mesh: NodePath = NodePath("")
@export var generate_on_ready: bool = false

# Internal grid: rows = grid_size, columns = grid_size; index [y][x]
var _grid_colors: Array = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Cached generated texture
var _texture: ImageTexture = null

func _ready():
	# Build initial grid
	_reset_grid()
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
	for y in range(grid_size):
		var row := []
		for x in range(grid_size):
			row.append(Color(0,0,0,0))
		_grid_colors.append(row)
	# rebuild cached texture
	_texture = null

func randomize_grid() -> void:
	"""Fill the grid with random colors drawn from `default_palette`.
	"""
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()
	for y in range(grid_size):
		for x in range(grid_size):
			_grid_colors[y][x] = default_palette[_rng.randi_range(0, default_palette.size() - 1)]
	# Generated new texture
	_texture = _build_texture_from_grid()

func _build_texture_from_grid() -> ImageTexture:
	"""Create an ImageTexture from _grid_colors using tile_pixels per cell."""
	var w := int(grid_size * tile_pixels)
	var h := int(grid_size * tile_pixels)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for gy in range(grid_size):
		for gx in range(grid_size):
			var c: Color = _grid_colors[gy][gx]
			# fill tile
			for py in range(tile_pixels):
				for px in range(tile_pixels):
					img.set_pixel(gx * tile_pixels + px, gy * tile_pixels + py, c)
	# No explicit lock/unlock needed in Godot 4; Image.set_pixel is safe to call directly.
	return ImageTexture.create_from_image(img)

func apply_texture(to_target: bool = true, to_linked: bool = true) -> void:
	"""Apply the built texture to `target_mesh` and `linked_mesh` materials.
	`target_mesh` path is required to be a MeshInstance3D node, as is `linked_mesh`.
	"""
	if not _texture:
		_texture = _build_texture_from_grid()
	if to_target and target_mesh != NodePath(""):
		var node := get_node_or_null(target_mesh)
		if node and node is MeshInstance3D:
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = _texture
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			node.material_override = mat
		else:
			push_warning("GridPainter: target_mesh is not a MeshInstance3D: %s" % [target_mesh])
	if to_linked and linked_mesh != NodePath(""):
		var ln := get_node_or_null(linked_mesh)
		if ln and ln is MeshInstance3D:
			var lmat := StandardMaterial3D.new()
			lmat.albedo_texture = _texture
			lmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ln.material_override = lmat
		else:
			push_warning("GridPainter: linked_mesh is not a MeshInstance3D: %s" % [linked_mesh])

func get_cell_color(x: int, y: int) -> Color:
	if x < 0 or x >= grid_size or y < 0 or y >= grid_size:
		return Color(0,0,0,0)
	return _grid_colors[y][x]

func set_cell_color(x: int, y: int, c: Color) -> void:
	if x < 0 or x >= grid_size or y < 0 or y >= grid_size:
		return
	_grid_colors[y][x] = c
	# rebuild only that tile
	_texture = _build_texture_from_grid()
	# If target mesh exists, update automatically
	apply_texture()

func fill_color(c: Color) -> void:
	for y in range(grid_size):
		for x in range(grid_size):
			_grid_colors[y][x] = c
	_texture = _build_texture_from_grid()
	apply_texture()

func paint_at_uv(uv: Vector2, color: Color) -> void:
	"""Paint a cell given UV coordinates in 0..1 range. 
	This assumes the target/linked mesh uses UVs matching the NxN grid layout (each cell covers 1/grid_size across U and V).
	"""
	if uv.x < 0 or uv.x > 1 or uv.y < 0 or uv.y > 1:
		return
	var gx := int(clamp(floor(uv.x * grid_size), 0, grid_size - 1))
	var gy := int(clamp(floor(uv.y * grid_size), 0, grid_size - 1))
	set_cell_color(gx, gy, color)

func save_grid_to_disk(path: String) -> void:
	# saves as PNG
	if not _texture:
		_texture = _build_texture_from_grid()
	var img := _texture.get_image()
	img.save_png(path)

func load_grid_image(path: String) -> void:
	# Load image and resample cells; useful for restoring from an atlas
	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		push_error("Failed to load image: %s" % [path])
		return
	# No lock required in Godot 4
	# Expect the loaded image to be grid_size * tile_pixels sized
	if img.get_width() < grid_size * tile_pixels or img.get_height() < grid_size * tile_pixels:
		push_warning("Loaded image smaller than expected grid. Attempting to sample by scale.")
	# sample cell centers
	for gy in range(grid_size):
		for gx in range(grid_size):
			var sample_x := int(round((gx + 0.5) * img.get_width() / float(grid_size)))
			var sample_y := int(round((gy + 0.5) * img.get_height() / float(grid_size)))
			_grid_colors[gy][gx] = img.get_pixel(sample_x, sample_y)
	# No unlock required in Godot 4
	_texture = _build_texture_from_grid()

# Editor helpers
func _get_configuration_warning() -> String:
	if not Engine.is_editor_hint():
		return ""
	if target_mesh == NodePath(""):
		return "GridPainter: Assign a target_mesh to apply textures."
	return ""

# Simple sanity methods making script usable from in-editor with buttons
func _editor_randomize_grid() -> void: randomize_grid(); apply_texture()
func _editor_apply_texture() -> void: apply_texture()
func _editor_save_grid_png(path: String = "res://grid_painter_output.png") -> void: save_grid_to_disk(path)

# Optional: expose as callable tool methods for EditorPlugin or remote calls
@export var developer_mode: bool = false

func debug_print_grid() -> void:
	if not developer_mode:
		return
	for y in range(grid_size):
		var line := ""
		for x in range(grid_size):
			line += "%s " % [_grid_colors[y][x]]
		print(line)
