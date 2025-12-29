class_name MaterialPickerUI
extends PanelContainer

signal close_requested
signal material_selected(material: Material)

static var instance: MaterialPickerUI = null

@onready var material_list: ItemList = get_node_or_null("MarginContainer/VBoxContainer/MaterialList") as ItemList
@onready var preview_mesh: MeshInstance3D = get_node_or_null("MarginContainer/VBoxContainer/PreviewContainer/SubViewport/PreviewMesh") as MeshInstance3D
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

var _loaded_materials: Dictionary = {}
var _current_material: Material = null
var _material_names: Array[String] = []


func _ready() -> void:
	instance = self
	add_to_group("material_picker_ui")
	
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


func _load_materials() -> void:
	_loaded_materials.clear()
	_material_names.clear()
	
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
	if preview_mesh and _current_material:
		preview_mesh.material_override = _current_material
	
	# Update status
	if status_label:
		status_label.text = "Selected: %s" % mat_name
	
	material_selected.emit(_current_material)


func get_current_material() -> Material:
	return _current_material


func get_current_material_name() -> String:
	if material_list and material_list.is_anything_selected():
		var selected := material_list.get_selected_items()
		if selected.size() > 0 and selected[0] < _material_names.size():
			return _material_names[selected[0]]
	return ""
