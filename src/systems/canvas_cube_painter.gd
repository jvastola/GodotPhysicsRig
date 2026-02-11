extends Node3D
class_name CanvasCubePainter

## Canvas painter for cube faces - creates 6 separate canvases for each face
## Links to GridPainter for applying textures to voxel blocks or other cubes

@export_group("Canvas Settings")
@export var canvas_resolution: int = 16:
	set(value):
		canvas_resolution = max(1, value)
		if is_node_ready():
			_resize_all_canvases()
@export var background_color: Color = Color.WHITE
@export var default_brush_color: Color = Color.BLACK
@export var brush_size: int = 2:
	set(value):
		brush_size = max(1, min(value, 50))
@export var pixel_perfect: bool = true:
	set(value):
		pixel_perfect = value
		if is_node_ready():
			_update_all_materials()

@export_group("Grid Painter Integration")
@export var grid_painter_path: NodePath = NodePath("")
@export var auto_sync_to_grid: bool = true
@export var target_surface_id: String = ""

@export_group("Persistence")
@export var auto_save: bool = true
@export var save_path: String = "user://canvas_cube_painter.json"

# Face names matching GridPainter FACE_DEFS order
const FACE_NAMES: Array[String] = ["front", "back", "right", "left", "top", "bottom"]
const FACE_NORMALS: Array[Vector3] = [
	Vector3(0, 0, 1),   # Front
	Vector3(0, 0, -1),  # Back
	Vector3(1, 0, 0),   # Right
	Vector3(-1, 0, 0),  # Left
	Vector3(0, 1, 0),   # Top
	Vector3(0, -1, 0)   # Bottom
]

var _face_images: Dictionary = {}  # face_name -> Image
var _face_textures: Dictionary = {}  # face_name -> ImageTexture
var _current_face: String = "front"
var _is_painting: bool = false
var _last_paint_pos: Vector2 = Vector2(-1, -1)
var _save_pending: bool = false
var _save_timer: float = 0.0
const SAVE_DEBOUNCE_TIME: float = 1.0

signal face_changed(face_name: String)
signal canvas_updated(face_name: String)

func _ready() -> void:
	print("CanvasCubePainter: Initializing with resolution ", canvas_resolution, "x", canvas_resolution)
	_initialize_all_canvases()
	if auto_save and FileAccess.file_exists(save_path):
		load_all_canvases()

func _process(delta: float) -> void:
	if _save_pending:
		_save_timer -= delta
		if _save_timer <= 0.0:
			_save_pending = false
			save_all_canvases()

func _initialize_all_canvases() -> void:
	for face_name in FACE_NAMES:
		var img := Image.create(canvas_resolution, canvas_resolution, false, Image.FORMAT_RGBA8)
		img.fill(background_color)
		_face_images[face_name] = img
		_face_textures[face_name] = ImageTexture.create_from_image(img)
	print("CanvasCubePainter: All 6 face canvases initialized")

func _resize_all_canvases() -> void:
	for face_name in FACE_NAMES:
		if not _face_images.has(face_name):
			continue
		var old_image: Image = _face_images[face_name]
		var new_image := Image.create(canvas_resolution, canvas_resolution, false, Image.FORMAT_RGBA8)
		new_image.fill(background_color)
		
		# Copy old content (scaled)
		if old_image:
			new_image.blit_rect_mask(old_image, old_image, Rect2i(0, 0, old_image.get_width(), old_image.get_height()), Vector2i(0, 0))
		
		_face_images[face_name] = new_image
		_face_textures[face_name] = ImageTexture.create_from_image(new_image)
	
	_update_all_materials()
	print("CanvasCubePainter: All canvases resized to ", canvas_resolution, "x", canvas_resolution)

func _update_all_materials() -> void:
	# This will be called when pixel_perfect changes
	# Materials are applied when textures are retrieved
	pass

## Get the current active face name
func get_current_face() -> String:
	return _current_face

## Set the current active face for painting
func set_current_face(face_name: String) -> void:
	if face_name in FACE_NAMES:
		_current_face = face_name
		face_changed.emit(face_name)
		print("CanvasCubePainter: Switched to face: ", face_name)

## Paint at UV coordinates on the current face
func paint_at_uv(uv: Vector2, color: Color, face_name: String = "") -> void:
	var target_face := face_name if face_name != "" else _current_face
	if not target_face in FACE_NAMES:
		return
	
	if uv.x < 0 or uv.x > 1 or uv.y < 0 or uv.y > 1:
		return
	
	var x := int(clamp(uv.x * canvas_resolution, 0, canvas_resolution - 1))
	var y := int(clamp(uv.y * canvas_resolution, 0, canvas_resolution - 1))
	
	_paint_brush(x, y, color, target_face)

## Paint with brush at pixel coordinates
func _paint_brush(x: int, y: int, color: Color, face_name: String) -> void:
	if not _face_images.has(face_name):
		return
	
	var img: Image = _face_images[face_name]
	var radius := brush_size / 2
	
	# Draw circle brush
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				var px := x + dx
				var py := y + dy
				if px >= 0 and px < canvas_resolution and py >= 0 and py < canvas_resolution:
					img.set_pixel(px, py, color)
	
	_update_face_texture(face_name)
	
	# Interpolate for smooth lines
	if _is_painting and _last_paint_pos.x >= 0:
		_paint_line(_last_paint_pos, Vector2(x, y), color, face_name)
	
	_last_paint_pos = Vector2(x, y)
	_schedule_save()
	
	# Sync to grid painter if enabled
	if auto_sync_to_grid:
		_sync_face_to_grid_painter(face_name)
	
	canvas_updated.emit(face_name)

## Paint a line between two points
func _paint_line(from: Vector2, to: Vector2, color: Color, face_name: String) -> void:
	if not _face_images.has(face_name):
		return
	
	var img: Image = _face_images[face_name]
	var dist := from.distance_to(to)
	var steps := int(dist) + 1
	var radius := brush_size / 2
	
	for i in range(steps):
		var t := float(i) / float(steps)
		var pos := from.lerp(to, t)
		var x := int(pos.x)
		var y := int(pos.y)
		
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if dx * dx + dy * dy <= radius * radius:
					var px := x + dx
					var py := y + dy
					if px >= 0 and px < canvas_resolution and py >= 0 and py < canvas_resolution:
						img.set_pixel(px, py, color)

func _update_face_texture(face_name: String) -> void:
	if _face_textures.has(face_name) and _face_images.has(face_name):
		_face_textures[face_name].update(_face_images[face_name])

func start_painting() -> void:
	_is_painting = true
	_last_paint_pos = Vector2(-1, -1)

func stop_painting() -> void:
	_is_painting = false
	_last_paint_pos = Vector2(-1, -1)

## Clear a specific face or all faces
func clear_canvas(color: Color = Color.WHITE, face_name: String = "") -> void:
	if face_name != "" and face_name in FACE_NAMES:
		_face_images[face_name].fill(color)
		_update_face_texture(face_name)
		if auto_sync_to_grid:
			_sync_face_to_grid_painter(face_name)
		canvas_updated.emit(face_name)
	else:
		# Clear all faces
		for fname in FACE_NAMES:
			_face_images[fname].fill(color)
			_update_face_texture(fname)
			if auto_sync_to_grid:
				_sync_face_to_grid_painter(fname)
			canvas_updated.emit(fname)
	_schedule_save()
	print("CanvasCubePainter: Canvas cleared")

## Get texture for a specific face
func get_face_texture(face_name: String) -> ImageTexture:
	return _face_textures.get(face_name, null)

## Get image for a specific face
func get_face_image(face_name: String) -> Image:
	return _face_images.get(face_name, null)

## Get all face textures as array (in FACE_DEFS order)
func get_all_face_textures() -> Array[ImageTexture]:
	var textures: Array[ImageTexture] = []
	for face_name in FACE_NAMES:
		textures.append(_face_textures[face_name])
	return textures

## Sync a specific face to GridPainter
func _sync_face_to_grid_painter(face_name: String) -> void:
	if grid_painter_path == NodePath(""):
		return
	
	var grid_painter := get_node_or_null(grid_painter_path)
	if not grid_painter or not grid_painter.has_method("set_cell_color"):
		return
	
	var face_index := FACE_NAMES.find(face_name)
	if face_index < 0:
		return
	
	var img: Image = _face_images[face_name]
	
	# Copy pixels to grid painter
	# GridPainter uses a grid layout, we need to map face to correct offset
	for y in range(canvas_resolution):
		for x in range(canvas_resolution):
			var color := img.get_pixel(x, y)
			# Map to grid painter coordinates based on face
			# This assumes GridPainter has matching subdivisions
			grid_painter.call("set_cell_color", x, y, color, NodePath(""), target_surface_id)

## Sync all faces to GridPainter
func sync_all_to_grid_painter() -> void:
	for face_name in FACE_NAMES:
		_sync_face_to_grid_painter(face_name)
	print("CanvasCubePainter: Synced all faces to GridPainter")

## Load face from GridPainter
func load_from_grid_painter(face_name: String) -> void:
	if grid_painter_path == NodePath(""):
		return
	
	var grid_painter := get_node_or_null(grid_painter_path)
	if not grid_painter or not grid_painter.has_method("get_cell_color"):
		return
	
	var img: Image = _face_images[face_name]
	
	for y in range(canvas_resolution):
		for x in range(canvas_resolution):
			var color: Color = grid_painter.call("get_cell_color", x, y, target_surface_id)
			img.set_pixel(x, y, color)
	
	_update_face_texture(face_name)
	canvas_updated.emit(face_name)

## Save all canvases to JSON
func save_all_canvases(path: String = "") -> void:
	var save_to := path if path != "" else save_path
	var data := {
		"resolution": canvas_resolution,
		"faces": {}
	}
	
	for face_name in FACE_NAMES:
		var img: Image = _face_images[face_name]
		var pixels: Array = []
		for y in range(canvas_resolution):
			for x in range(canvas_resolution):
				var c := img.get_pixel(x, y)
				pixels.append([c.r, c.g, c.b, c.a])
		data["faces"][face_name] = pixels
	
	var file := FileAccess.open(save_to, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()
		print("CanvasCubePainter: Saved to: ", save_to)
	else:
		push_error("CanvasCubePainter: Failed to save to: ", save_to)

## Load all canvases from JSON
func load_all_canvases(path: String = "") -> void:
	var load_from := path if path != "" else save_path
	if not FileAccess.file_exists(load_from):
		print("CanvasCubePainter: No save file found at: ", load_from)
		return
	
	var file := FileAccess.open(load_from, FileAccess.READ)
	if not file:
		push_error("CanvasCubePainter: Failed to open: ", load_from)
		return
	
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	
	if err != OK:
		push_error("CanvasCubePainter: Failed to parse JSON")
		return
	
	var data: Dictionary = json.get_data()
	if data.has("resolution"):
		canvas_resolution = int(data["resolution"])
	
	if data.has("faces"):
		for face_name in FACE_NAMES:
			if data["faces"].has(face_name):
				var pixels: Array = data["faces"][face_name]
				var img: Image = _face_images[face_name]
				var idx := 0
				for y in range(canvas_resolution):
					for x in range(canvas_resolution):
						if idx < pixels.size():
							var p: Array = pixels[idx]
							img.set_pixel(x, y, Color(p[0], p[1], p[2], p[3]))
							idx += 1
				_update_face_texture(face_name)
				canvas_updated.emit(face_name)
	
	print("CanvasCubePainter: Loaded from: ", load_from)

func _schedule_save() -> void:
	if not auto_save:
		return
	if not _save_pending:
		_save_pending = true
		_save_timer = SAVE_DEBOUNCE_TIME

func _exit_tree() -> void:
	if auto_save:
		save_all_canvases()
