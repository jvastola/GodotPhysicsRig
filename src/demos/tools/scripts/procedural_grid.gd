@tool
extends Node3D

const TEXTURE_SIZE = Vector2i(512, 512)
const GRID_SIZE = 32
const GRID_THICKNESS = 4

@export var apply_to_children: bool = true:
	set(value):
		apply_to_children = value
		if is_inside_tree():
			_update_materials()

@export var grid_color: Color = Color(0.0, 1.0, 0.0):
	set(value):
		grid_color = value
		_update_materials()

var _generated_texture: Texture2D

func _ready() -> void:
	_update_materials()

func _update_materials() -> void:
	if not _generated_texture:
		_generated_texture = _generate_grid_texture()
	
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = _generated_texture
	mat.uv1_triplanar = true
	
	if apply_to_children:
		for child in get_children():
			if child.get("material") != null:
				child.set("material", mat)
			elif child is MeshInstance3D:
				child.material_override = mat

func _generate_grid_texture() -> Texture2D:
	var image := Image.create(TEXTURE_SIZE.x, TEXTURE_SIZE.y, false, Image.FORMAT_RGBA8)
	var offset := int(float(GRID_THICKNESS) / 2.0)
	
	for y in TEXTURE_SIZE.y:
		for x in TEXTURE_SIZE.x:
			var line_x := (x + offset) % GRID_SIZE < GRID_THICKNESS
			var line_y := (y + offset) % GRID_SIZE < GRID_THICKNESS
			
			var color := Color(0.1, 0.1, 0.1, 1.0)

			if line_x and line_y:
				color = grid_color
			elif line_x or line_y:
				color = grid_color * 0.5
				color.a = 1.0

			image.set_pixel(x, y, color)

	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
