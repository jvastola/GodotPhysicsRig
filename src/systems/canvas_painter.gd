extends Node3D
class_name CanvasPainter

## A 2D canvas painter that allows finger painting on a flat surface
## Can define canvas size/resolution and save to image texture

@export_group("Canvas Settings")
@export var canvas_width: int = 512:
	set(value):
		canvas_width = max(1, value)
		if is_node_ready():
			_resize_canvas()
@export var canvas_height: int = 512:
	set(value):
		canvas_height = max(1, value)
		if is_node_ready():
			_resize_canvas()
@export var background_color: Color = Color.WHITE
@export var default_brush_color: Color = Color.BLACK
@export var brush_size: int = 5:
	set(value):
		brush_size = max(1, min(value, 50))
@export var pixel_perfect: bool = false:
	set(value):
		pixel_perfect = value
		if is_node_ready():
			_apply_canvas_texture()

@export_group("Canvas Mesh")
@export_node_path("MeshInstance3D") var canvas_mesh_path: NodePath = NodePath("")
@export var canvas_physical_size: Vector2 = Vector2(1.0, 1.0)

@export_group("Persistence")
@export var auto_save: bool = true
@export var save_path: String = "user://canvas_painter.png"

var _canvas_image: Image
var _canvas_texture: ImageTexture
var _canvas_mesh: MeshInstance3D
var _handler_script: Script
var _last_paint_pos: Vector2 = Vector2(-1, -1)
var _is_painting: bool = false
var _save_pending: bool = false
var _save_timer: float = 0.0
const SAVE_DEBOUNCE_TIME: float = 1.0

func _ready() -> void:
	print("CanvasPainter: Initializing canvas ", canvas_width, "x", canvas_height)
	_load_handler_script()
	_initialize_canvas()
	call_deferred("_deferred_init")

func _process(delta: float) -> void:
	if _save_pending:
		_save_timer -= delta
		if _save_timer <= 0.0:
			_save_pending = false
			save_canvas()

func _deferred_init() -> void:
	_resolve_canvas_mesh()
	_attach_handler_script()
	_apply_canvas_texture()
	if auto_save and FileAccess.file_exists(save_path):
		load_canvas()

func _load_handler_script() -> void:
	if FileAccess.file_exists("res://src/systems/canvas_painter_handler.gd"):
		_handler_script = preload("res://src/systems/canvas_painter_handler.gd")

func _initialize_canvas() -> void:
	_canvas_image = Image.create(canvas_width, canvas_height, false, Image.FORMAT_RGBA8)
	_canvas_image.fill(background_color)
	_canvas_texture = ImageTexture.create_from_image(_canvas_image)
	print("CanvasPainter: Canvas initialized")

func _resize_canvas() -> void:
	if not _canvas_image:
		_initialize_canvas()
		return
	
	var old_image := _canvas_image
	_canvas_image = Image.create(canvas_width, canvas_height, false, Image.FORMAT_RGBA8)
	_canvas_image.fill(background_color)
	
	# Copy old content (scaled to fit)
	_canvas_image.blit_rect(old_image, Rect2i(0, 0, old_image.get_width(), old_image.get_height()), Vector2i(0, 0))
	
	_canvas_texture = ImageTexture.create_from_image(_canvas_image)
	_apply_canvas_texture()
	print("CanvasPainter: Canvas resized to ", canvas_width, "x", canvas_height)

func _resolve_canvas_mesh() -> void:
	if canvas_mesh_path == NodePath(""):
		return
	_canvas_mesh = get_node_or_null(canvas_mesh_path) as MeshInstance3D
	if _canvas_mesh:
		print("CanvasPainter: Canvas mesh resolved: ", _canvas_mesh.name)
	else:
		print("CanvasPainter: Canvas mesh not found at: ", canvas_mesh_path)

func _attach_handler_script() -> void:
	if not _handler_script or not _canvas_mesh:
		return
	_canvas_mesh.set_script(_handler_script)
	if _canvas_mesh.has_method("set"):
		_canvas_mesh.set("painter", self.get_path())
		_canvas_mesh.set("brush_size", brush_size)
	_canvas_mesh.add_to_group("pointer_interactable")
	print("CanvasPainter: Handler script attached to canvas mesh")

func _apply_canvas_texture() -> void:
	if not _canvas_mesh or not _canvas_texture:
		return
	
	# Create or update the plane mesh with proper UVs
	var plane_mesh := _create_plane_mesh()
	_canvas_mesh.mesh = plane_mesh
	
	# Create material with the canvas texture
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _canvas_texture
	# Use NEAREST for pixel-perfect (no blur), LINEAR for smooth
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if pixel_perfect else BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_canvas_mesh.material_override = mat
	
	print("CanvasPainter: Canvas texture applied to mesh")

func _create_plane_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var half_w := canvas_physical_size.x * 0.5
	var half_h := canvas_physical_size.y * 0.5
	
	# Define vertices for a plane facing +Z
	var verts := [
		Vector3(-half_w, -half_h, 0),  # Bottom-left
		Vector3(half_w, -half_h, 0),   # Bottom-right
		Vector3(half_w, half_h, 0),    # Top-right
		Vector3(-half_w, half_h, 0)    # Top-left
	]
	
	var uvs := [
		Vector2(0, 1),  # Bottom-left
		Vector2(1, 1),  # Bottom-right
		Vector2(1, 0),  # Top-right
		Vector2(0, 0)   # Top-left
	]
	
	var normal := Vector3(0, 0, 1)
	
	# First triangle
	st.set_normal(normal)
	st.set_uv(uvs[0])
	st.add_vertex(verts[0])
	st.set_normal(normal)
	st.set_uv(uvs[1])
	st.add_vertex(verts[1])
	st.set_normal(normal)
	st.set_uv(uvs[2])
	st.add_vertex(verts[2])
	
	# Second triangle
	st.set_normal(normal)
	st.set_uv(uvs[0])
	st.add_vertex(verts[0])
	st.set_normal(normal)
	st.set_uv(uvs[2])
	st.add_vertex(verts[2])
	st.set_normal(normal)
	st.set_uv(uvs[3])
	st.add_vertex(verts[3])
	
	return st.commit()

## Paint at UV coordinates (0-1 range)
func paint_at_uv(uv: Vector2, color: Color) -> void:
	if uv.x < 0 or uv.x > 1 or uv.y < 0 or uv.y > 1:
		return
	
	var x := int(clamp(uv.x * canvas_width, 0, canvas_width - 1))
	var y := int(clamp(uv.y * canvas_height, 0, canvas_height - 1))
	
	_paint_brush(x, y, color)

## Paint with brush at pixel coordinates
func _paint_brush(x: int, y: int, color: Color) -> void:
	# Draw a circle brush
	var radius := brush_size / 2
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				var px := x + dx
				var py := y + dy
				if px >= 0 and px < canvas_width and py >= 0 and py < canvas_height:
					_canvas_image.set_pixel(px, py, color)
	
	_update_texture()
	
	# Interpolate between last position and current for smooth lines
	if _is_painting and _last_paint_pos.x >= 0:
		_paint_line(_last_paint_pos, Vector2(x, y), color)
	
	_last_paint_pos = Vector2(x, y)
	_schedule_save()

## Paint a line between two points
func _paint_line(from: Vector2, to: Vector2, color: Color) -> void:
	var dist := from.distance_to(to)
	var steps := int(dist) + 1
	
	for i in range(steps):
		var t := float(i) / float(steps)
		var pos := from.lerp(to, t)
		var x := int(pos.x)
		var y := int(pos.y)
		
		var radius := brush_size / 2
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if dx * dx + dy * dy <= radius * radius:
					var px := x + dx
					var py := y + dy
					if px >= 0 and px < canvas_width and py >= 0 and py < canvas_height:
						_canvas_image.set_pixel(px, py, color)

func _update_texture() -> void:
	if _canvas_texture:
		_canvas_texture.update(_canvas_image)

func start_painting() -> void:
	_is_painting = true
	_last_paint_pos = Vector2(-1, -1)

func stop_painting() -> void:
	_is_painting = false
	_last_paint_pos = Vector2(-1, -1)

## Clear the canvas
func clear_canvas(color: Color = Color.WHITE) -> void:
	_canvas_image.fill(color)
	_update_texture()
	_schedule_save()
	print("CanvasPainter: Canvas cleared")

## Save canvas to file
func save_canvas(path: String = "") -> void:
	var save_to := path if path != "" else save_path
	var err := _canvas_image.save_png(save_to)
	if err == OK:
		print("CanvasPainter: Canvas saved to: ", save_to)
	else:
		push_error("CanvasPainter: Failed to save canvas to: ", save_to)

## Load canvas from file
func load_canvas(path: String = "") -> void:
	var load_from := path if path != "" else save_path
	if not FileAccess.file_exists(load_from):
		print("CanvasPainter: No saved canvas found at: ", load_from)
		return
	
	var loaded_image := Image.load_from_file(load_from)
	if loaded_image:
		# Resize if dimensions don't match
		if loaded_image.get_width() != canvas_width or loaded_image.get_height() != canvas_height:
			loaded_image.resize(canvas_width, canvas_height)
		_canvas_image = loaded_image
		_canvas_texture = ImageTexture.create_from_image(_canvas_image)
		_apply_canvas_texture()
		print("CanvasPainter: Canvas loaded from: ", load_from)
	else:
		push_error("CanvasPainter: Failed to load canvas from: ", load_from)

func _schedule_save() -> void:
	if not auto_save:
		return
	if not _save_pending:
		_save_pending = true
		_save_timer = SAVE_DEBOUNCE_TIME

## Get the canvas texture
func get_canvas_texture() -> ImageTexture:
	return _canvas_texture

## Get the canvas image
func get_canvas_image() -> Image:
	return _canvas_image

func _exit_tree() -> void:
	if auto_save:
		save_canvas()
