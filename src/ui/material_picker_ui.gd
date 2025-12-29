class_name MaterialPickerUI
extends PanelContainer

signal close_requested
signal material_selected(material: Material)

static var instance: MaterialPickerUI = null

@onready var material_list: ItemList = get_node_or_null("MarginContainer/VBoxContainer/MaterialList") as ItemList
@onready var preview_rect: ColorRect = get_node_or_null("MarginContainer/VBoxContainer/PreviewRect") as ColorRect
@onready var status_label: Label = get_node_or_null("MarginContainer/VBoxContainer/StatusLabel") as Label
@onready var close_button: Button = get_node_or_null("MarginContainer/VBoxContainer/TitleRow/CloseButton") as Button

# Available materials from the procedural materials demo
const MATERIAL_PATHS := {
	"Lava": "res://src/demos/tools/materials/lava.tres",
	"Marble": "res://src/demos/tools/materials/marble.tres",
	"Grass": "res://src/demos/tools/materials/grass.tres",
	"Sand": "res://src/demos/tools/materials/sand.tres",
	"Ice": "res://src/demos/tools/materials/ice.tres",
	"Wet Concrete": "res://src/demos/tools/materials/wet_concrete.tres",
	"Pixel Art": "res://src/demos/tools/materials/pixel_art.tres",
	"Glass": "res://src/demos/tools/materials/glass.tres",
}

# Special shader-based materials that need runtime creation
const SHADER_MATERIALS := {
	"Plasma": "plasma",
}

var _loaded_materials: Dictionary = {}
var _current_material: Material = null
var _material_names: Array[String] = []

# For animated shader materials
var _plasma_shader_material: ShaderMaterial = null
var _plasma_viewport: SubViewport = null


func _ready() -> void:
	instance = self
	add_to_group("material_picker_ui")
	
	_create_shader_materials()
	_load_materials()
	_populate_list()
	
	if material_list:
		material_list.item_selected.connect(_on_material_selected)
		# Select first material by default
		if material_list.item_count > 0:
			material_list.select(0)
			_on_material_selected(0)
	
	if close_button:
		close_button.pressed.connect(func(): close_requested.emit())
	
	if status_label:
		status_label.text = "Select a material to apply"


func _exit_tree() -> void:
	if instance == self:
		instance = null
	# Clean up viewport
	if is_instance_valid(_plasma_viewport):
		_plasma_viewport.queue_free()


func _create_shader_materials() -> void:
	# Create the plasma shader material with its own viewport
	var plasma_shader = load("res://src/demos/tools/shaders/plasma.gdshader") as Shader
	if plasma_shader:
		_plasma_shader_material = ShaderMaterial.new()
		_plasma_shader_material.shader = plasma_shader
		
		# Create noise textures for the plasma effect
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0, 0.385, 0.656, 0.887, 1])
		gradient.colors = PackedColorArray([
			Color(0, 0.021, 0.097, 1),
			Color(0.295, 0.332, 0.730, 1),
			Color(0.223, 0.724, 0.777, 1),
			Color(0.877, 0.649, 0.963, 1),
			Color(0.932, 0.719, 0.921, 1)
		])
		
		var noise1 := FastNoiseLite.new()
		noise1.frequency = 0.002
		noise1.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise1.fractal_octaves = 4
		noise1.fractal_lacunarity = 2.901
		noise1.fractal_gain = 0.353
		
		var noise_tex1 := NoiseTexture2D.new()
		noise_tex1.noise = noise1
		noise_tex1.color_ramp = gradient
		noise_tex1.seamless = true
		
		var noise2 := FastNoiseLite.new()
		noise2.seed = 60607
		noise2.fractal_gain = 0.695
		noise2.domain_warp_enabled = true
		
		var noise_tex2 := NoiseTexture2D.new()
		noise_tex2.noise = noise2
		noise_tex2.seamless = true
		
		_plasma_shader_material.set_shader_parameter("noise1", noise_tex1)
		_plasma_shader_material.set_shader_parameter("noise2", noise_tex2)


func _load_materials() -> void:
	_loaded_materials.clear()
	_material_names.clear()
	
	# Load standard materials
	for mat_name in MATERIAL_PATHS.keys():
		var path: String = MATERIAL_PATHS[mat_name]
		if ResourceLoader.exists(path):
			var mat = load(path) as Material
			if mat:
				_loaded_materials[mat_name] = mat
				_material_names.append(mat_name)
			else:
				push_warning("MaterialPickerUI: Failed to load material: %s" % path)
		else:
			push_warning("MaterialPickerUI: Material not found: %s" % path)
	
	# Add shader materials
	for mat_name in SHADER_MATERIALS.keys():
		match SHADER_MATERIALS[mat_name]:
			"plasma":
				if _plasma_shader_material:
					_loaded_materials[mat_name] = _plasma_shader_material
					_material_names.append(mat_name)


func _populate_list() -> void:
	if not material_list:
		return
	
	material_list.clear()
	
	for mat_name in _material_names:
		material_list.add_item(mat_name)


func _on_material_selected(index: int) -> void:
	if index < 0 or index >= _material_names.size():
		return
	
	var mat_name := _material_names[index]
	_current_material = _loaded_materials.get(mat_name)
	
	# Update preview
	_update_preview(mat_name)
	
	# Update status
	if status_label:
		status_label.text = "Selected: %s" % mat_name
	
	material_selected.emit(_current_material)


func _update_preview(mat_name: String) -> void:
	if not preview_rect:
		return
	
	var mat = _loaded_materials.get(mat_name)
	if not mat:
		return
	
	if mat is ShaderMaterial:
		# For shader materials, apply directly to the ColorRect
		preview_rect.material = mat
	elif mat is StandardMaterial3D:
		# For StandardMaterial3D, create a simple shader to display the albedo texture
		var std_mat := mat as StandardMaterial3D
		if std_mat.albedo_texture:
			var preview_mat := ShaderMaterial.new()
			var preview_shader := Shader.new()
			preview_shader.code = """
shader_type canvas_item;
uniform sampler2D albedo_tex : repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
void fragment() {
	COLOR = texture(albedo_tex, UV) * albedo_color;
}
"""
			preview_mat.shader = preview_shader
			preview_mat.set_shader_parameter("albedo_tex", std_mat.albedo_texture)
			preview_mat.set_shader_parameter("albedo_color", std_mat.albedo_color)
			preview_rect.material = preview_mat
		else:
			# Just show the albedo color
			preview_rect.material = null
			preview_rect.color = std_mat.albedo_color
	else:
		preview_rect.material = null
		preview_rect.color = Color(0.5, 0.5, 0.5)


func get_current_material() -> Material:
	return _current_material


func get_current_material_name() -> String:
	if material_list and material_list.is_anything_selected():
		var selected := material_list.get_selected_items()
		if selected.size() > 0 and selected[0] < _material_names.size():
			return _material_names[selected[0]]
	return ""


## Returns true if the current material is a shader material (like plasma)
func is_shader_material() -> bool:
	return _current_material is ShaderMaterial
