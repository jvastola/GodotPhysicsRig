extends Node3D
class_name PaintedCube

## A 3D cube that displays textures from CanvasCubePainter
## Updates in real-time as you paint

@export var canvas_cube_painter_path: NodePath = NodePath("")
@export var cube_size: float = 1.0
@export var auto_rotate: bool = true
@export var rotation_speed: float = 0.5

@onready var cube_mesh: MeshInstance3D = $CubeMesh

var _canvas_cube_painter: CanvasCubePainter
var _cube_material: StandardMaterial3D

func _ready() -> void:
	_create_cube_mesh()
	call_deferred("_connect_to_painter")

func _process(delta: float) -> void:
	if auto_rotate:
		rotate_y(rotation_speed * delta)

func _connect_to_painter() -> void:
	if canvas_cube_painter_path == NodePath(""):
		print("PaintedCube: No canvas cube painter path set")
		return
	
	_canvas_cube_painter = get_node_or_null(canvas_cube_painter_path) as CanvasCubePainter
	if not _canvas_cube_painter:
		print("PaintedCube: Canvas cube painter not found at: ", canvas_cube_painter_path)
		return
	
	# Check if already connected to avoid duplicate connections
	if not _canvas_cube_painter.canvas_updated.is_connected(_on_canvas_updated):
		_canvas_cube_painter.canvas_updated.connect(_on_canvas_updated)
	if not _canvas_cube_painter.face_changed.is_connected(_on_face_changed):
		_canvas_cube_painter.face_changed.connect(_on_face_changed)
	
	# Initial update
	_update_cube_texture()
	print("PaintedCube: Connected to canvas cube painter")

func _on_canvas_updated(face_name: String) -> void:
	_update_cube_texture()

func _on_face_changed(face_name: String) -> void:
	# Optional: could highlight current face being edited
	pass

func _create_cube_mesh() -> void:
	var mesh := _generate_cube_mesh_with_uvs()
	cube_mesh.mesh = mesh
	cube_mesh.layers = 2  # Use layer 2 for preview cube
	
	# Create material
	_cube_material = StandardMaterial3D.new()
	_cube_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cube_material.cull_mode = BaseMaterial3D.CULL_BACK  # Proper back-face culling
	cube_mesh.material_override = _cube_material

func _update_cube_texture() -> void:
	if not _canvas_cube_painter:
		return
	
	# Create atlas texture from all 6 faces
	var atlas := _create_texture_atlas()
	if atlas:
		_cube_material.albedo_texture = atlas
		# Use pixel perfect filtering if enabled
		_cube_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if _canvas_cube_painter.pixel_perfect else BaseMaterial3D.TEXTURE_FILTER_LINEAR

func _create_texture_atlas() -> ImageTexture:
	if not _canvas_cube_painter:
		return null
	
	var res := _canvas_cube_painter.canvas_resolution
	
	# Create atlas layout matching GridPainter:
	# Row 1: [left] [top] [right]
	# Row 2: [back] [front] [bottom]
	var atlas_width := res * 3
	var atlas_height := res * 2
	
	var atlas_image := Image.create(atlas_width, atlas_height, false, Image.FORMAT_RGBA8)
	
	# Face order and positions in atlas
	var face_layout := [
		{"name": "left", "x": 0, "y": 0},
		{"name": "top", "x": res, "y": 0},
		{"name": "right", "x": res * 2, "y": 0},
		{"name": "back", "x": 0, "y": res},
		{"name": "front", "x": res, "y": res},
		{"name": "bottom", "x": res * 2, "y": res}
	]
	
	# Copy each face to atlas
	for face_info in face_layout:
		var face_image := _canvas_cube_painter.get_face_image(face_info["name"])
		if face_image:
			atlas_image.blit_rect(face_image, Rect2i(0, 0, res, res), Vector2i(face_info["x"], face_info["y"]))
	
	return ImageTexture.create_from_image(atlas_image)

func _generate_cube_mesh_with_uvs() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var half := cube_size * 0.5
	var res := _canvas_cube_painter.canvas_resolution if _canvas_cube_painter else 16
	
	# UV layout in atlas (matching face_layout above)
	# Each face is 1/3 width, 1/2 height
	var uv_w := 1.0 / 3.0
	var uv_h := 1.0 / 2.0
	
	# Face definitions with atlas UV coordinates
	var faces := [
		# Front face (+Z) - atlas position [1, 1]
		{
			"verts": [
				Vector3(-half, -half, half),
				Vector3(half, -half, half),
				Vector3(half, half, half),
				Vector3(-half, half, half)
			],
			"normal": Vector3(0, 0, 1),
			"uv_offset": Vector2(uv_w, uv_h)  # front
		},
		# Back face (-Z) - atlas position [0, 1]
		{
			"verts": [
				Vector3(half, -half, -half),
				Vector3(-half, -half, -half),
				Vector3(-half, half, -half),
				Vector3(half, half, -half)
			],
			"normal": Vector3(0, 0, -1),
			"uv_offset": Vector2(0, uv_h)  # back
		},
		# Right face (+X) - atlas position [2, 0]
		{
			"verts": [
				Vector3(half, -half, half),
				Vector3(half, -half, -half),
				Vector3(half, half, -half),
				Vector3(half, half, half)
			],
			"normal": Vector3(1, 0, 0),
			"uv_offset": Vector2(uv_w * 2, 0)  # right
		},
		# Left face (-X) - atlas position [0, 0]
		{
			"verts": [
				Vector3(-half, -half, -half),
				Vector3(-half, -half, half),
				Vector3(-half, half, half),
				Vector3(-half, half, -half)
			],
			"normal": Vector3(-1, 0, 0),
			"uv_offset": Vector2(0, 0)  # left
		},
		# Top face (+Y) - atlas position [1, 0]
		{
			"verts": [
				Vector3(-half, half, half),
				Vector3(half, half, half),
				Vector3(half, half, -half),
				Vector3(-half, half, -half)
			],
			"normal": Vector3(0, 1, 0),
			"uv_offset": Vector2(uv_w, 0)  # top
		},
		# Bottom face (-Y) - atlas position [2, 1]
		{
			"verts": [
				Vector3(-half, -half, -half),
				Vector3(half, -half, -half),
				Vector3(half, -half, half),
				Vector3(-half, -half, half)
			],
			"normal": Vector3(0, -1, 0),
			"uv_offset": Vector2(uv_w * 2, uv_h)  # bottom
		}
	]
	
	# Build each face
	for face in faces:
		var verts: Array = face["verts"]
		var normal: Vector3 = face["normal"]
		var uv_offset: Vector2 = face["uv_offset"]
		
		# Base UVs for a quad
		var base_uvs := [
			Vector2(0, 1),
			Vector2(1, 1),
			Vector2(1, 0),
			Vector2(0, 0)
		]
		
		# Scale and offset UVs to atlas position
		var uvs: Array = []
		for uv in base_uvs:
			uvs.append(Vector2(uv.x * uv_w, uv.y * uv_h) + uv_offset)
		
		# First triangle (counter-clockwise winding for outside face)
		st.set_normal(normal)
		st.set_uv(uvs[0])
		st.add_vertex(verts[0])
		st.set_normal(normal)
		st.set_uv(uvs[2])
		st.add_vertex(verts[2])
		st.set_normal(normal)
		st.set_uv(uvs[1])
		st.add_vertex(verts[1])
		
		# Second triangle (counter-clockwise winding for outside face)
		st.set_normal(normal)
		st.set_uv(uvs[0])
		st.add_vertex(verts[0])
		st.set_normal(normal)
		st.set_uv(uvs[3])
		st.add_vertex(verts[3])
		st.set_normal(normal)
		st.set_uv(uvs[2])
		st.add_vertex(verts[2])
	
	return st.commit()

## Set the canvas cube painter reference
func set_canvas_cube_painter(painter: CanvasCubePainter) -> void:
	_canvas_cube_painter = painter
	if _canvas_cube_painter:
		# Disconnect old signals if already connected
		if _canvas_cube_painter.canvas_updated.is_connected(_on_canvas_updated):
			_canvas_cube_painter.canvas_updated.disconnect(_on_canvas_updated)
		if _canvas_cube_painter.face_changed.is_connected(_on_face_changed):
			_canvas_cube_painter.face_changed.disconnect(_on_face_changed)
		
		# Connect signals
		_canvas_cube_painter.canvas_updated.connect(_on_canvas_updated)
		_canvas_cube_painter.face_changed.connect(_on_face_changed)
		_update_cube_texture()
