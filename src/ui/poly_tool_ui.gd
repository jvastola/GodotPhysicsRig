class_name PolyToolUI
extends PanelContainer

signal close_requested

# UI References
@onready var tab_container: TabContainer = get_node_or_null("MarginContainer/TabContainer")
@onready var close_button: Button = get_node_or_null("MarginContainer/VBoxContainer/TitleRow/CloseButton")

# Sidebar & Content Area (New)
var sidebar: VBoxContainer
var content_area: PanelContainer
var content_vbox: VBoxContainer
var _sections: Dictionary = {}
var _sidebar_buttons: Dictionary = {}

# File Tab References (kept from original)
var path_edit: LineEdit
var file_list: ItemList
var save_button: Button
var load_button: Button
var refresh_button: Button
var location_dropdown: OptionButton
var status_label: Label
var info_label: Label

# Mode Section References
var mode_grid: GridContainer

# Props Section References
var props_container: VBoxContainer

# Layers Section References
var layer_list: ItemList
var add_layer_button: Button
var remove_layer_button: Button
var layer_name_edit: LineEdit

# Material Section References (New)
var material_list_ui: ItemList
var material_preview: ColorRect
var _loaded_materials: Dictionary = {}
var _current_material: Material = null
var _material_names: Array[String] = []
var _plasma_shader_material: ShaderMaterial = null

var _last_layer_count: int = -1
var _last_active_layer_idx: int = -1

static var instance: PolyToolUI = null

enum StorageLocation { DOCUMENTS, USER, PROJECT }
var _current_location: StorageLocation = StorageLocation.DOCUMENTS
var _http_request: HTTPRequest = null

const DIR_USER := "user://poly_exports"
const DIR_PROJECT := "res://src/levels/poly_exports"

# Available materials (Migrated from MaterialPickerUI)
const MATERIAL_PATHS := {
	"Lava": "res://src/demos/tools/materials/lava.tres",
	"Marble": "res://src/demos/tools/materials/marble.tres",
	"Grass": "res://src/demos/tools/materials/grass.tres",
	"Sand": "res://src/demos/tools/materials/sand.tres",
	"Ice": "res://src/demos/tools/materials/ice.tres",
	"Wet Concrete": "res://src/demos/tools/materials/wet_concrete.tres",
	"Pixel Art": "res://src/demos/tools/materials/pixel_art.tres",
	"Wood Pixel": "res://src/demos/tools/materials/wood_pixel.tres",
	"Grass Pixel": "res://src/demos/tools/materials/grass_pixel.tres",
	"Stone Pixel": "res://src/demos/tools/materials/stone_pixel.tres",
	"Dirt Pixel": "res://src/demos/tools/materials/dirt_pixel.tres",
	"Sand Pixel": "res://src/demos/tools/materials/sand_pixel.tres",
	"Snow Pixel": "res://src/demos/tools/materials/snow_pixel.tres",
	"Brick Pixel": "res://src/demos/tools/materials/brick_pixel.tres",
	"Metal Pixel": "res://src/demos/tools/materials/metal_pixel.tres",
	"Glass": "res://src/demos/tools/materials/glass.tres",
}

const SHADER_MATERIALS := {
	"Plasma": "plasma",
}

func _ready() -> void:
	instance = self
	add_to_group("material_picker_ui")
	_setup_ui_structure()
	_setup_http_request()
	
	_create_shader_materials()
	_load_materials()
	
	_populate_mode_sections()
	_populate_material_section()
	_populate_layer_section()
	_populate_file_section()
	_populate_props_section()
	
	_refresh_summary()
	
	# Default section
	_switch_to_section("Place")
	
	if close_button:
		close_button.pressed.connect(func(): close_requested.emit())
	
	# Periodically refresh info
	var timer = Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	timer.timeout.connect(_refresh_summary)
	add_child(timer)

func _setup_ui_structure() -> void:
	# Clear existing children if any
	for child in get_children():
		child.queue_free()
	
	var margin = MarginContainer.new()
	margin.name = "MarginContainer"
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(main_vbox)
	
	# Title Row
	var title_row = HBoxContainer.new()
	main_vbox.add_child(title_row)
	var title_label = Label.new()
	title_label.text = "Poly Tool"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_label)
	
	info_label = Label.new()
	info_label.text = "Points: 0   Triangles: 0"
	title_row.add_child(info_label)
	
	close_button = Button.new()
	close_button.text = " X "
	close_button.pressed.connect(func(): close_requested.emit())
	title_row.add_child(close_button)
	
	# Two-column layout
	var hbox = HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 12)
	main_vbox.add_child(hbox)
	
	# Sidebar
	var sidebar_scroll = ScrollContainer.new()
	sidebar_scroll.custom_minimum_size.x = 140
	sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hbox.add_child(sidebar_scroll)
	
	sidebar = VBoxContainer.new()
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar_scroll.add_child(sidebar)
	
	# Content Area
	content_area = PanelContainer.new()
	content_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(content_area)
	
	content_vbox = VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_area.add_child(content_vbox)

func _add_sidebar_button(label: String, section_name: String) -> Button:
	var btn = Button.new()
	btn.text = label
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(func(): _switch_to_section(section_name))
	sidebar.add_child(btn)
	_sidebar_buttons[section_name] = btn
	return btn

func _switch_to_section(section_name: String) -> void:
	for s_name in _sections:
		_sections[s_name].visible = (s_name == section_name)
		
		# Update button styling
		if _sidebar_buttons.has(s_name):
			var btn = _sidebar_buttons[s_name] as Button
			if s_name == section_name:
				btn.add_theme_color_override("font_color", Color(1, 0.9, 0.2))
			else:
				btn.remove_theme_color_override("font_color")
	
	# If it's a ToolMode, also update the Tool's mode
	var tool = _find_poly_tool()
	if tool:
		match section_name:
			"Place": tool.current_mode = PolyTool.ToolMode.PLACE
			"Edit": tool.current_mode = PolyTool.ToolMode.EDIT
			"Extrude": tool.current_mode = PolyTool.ToolMode.EXTRUDE
			"Remove": tool.current_mode = PolyTool.ToolMode.REMOVE
			"Connect": tool.current_mode = PolyTool.ToolMode.CONNECT
			"Paint": tool.current_mode = PolyTool.ToolMode.PAINT
			"Material": tool.current_mode = PolyTool.ToolMode.APPLY_MATERIAL
			"Select": tool.current_mode = PolyTool.ToolMode.SELECT
			"Convert Volume": tool.current_mode = PolyTool.ToolMode.CONVERT_VOLUME

func _create_section(section_name: String) -> VBoxContainer:
	var section = VBoxContainer.new()
	section.name = section_name
	section.visible = false
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_vbox.add_child(section)
	_sections[section_name] = section
	return section

func _populate_mode_sections() -> void:
	var modes = [
		["Place", "Place Mode Settings"],
		["Edit", "Edit Mode Settings"],
		["Extrude", "Extrude Mode Settings"],
		["Remove", "Remove Mode Settings"],
		["Connect", "Connect Mode Settings"],
		["Paint", "Paint Mode Settings"],
		["Select", "Select Mode Settings"],
		["Convert Volume", "Volume Conversion Settings"]
	]
	
	for m in modes:
		var section = _create_section(m[0])
		_add_sidebar_button(m[0], m[0])
		
		var lbl = Label.new()
		lbl.text = m[1]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		section.add_child(lbl)
		
		# Mode specific settings could go here
		if m[0] == "Paint":
			var hb = HBoxContainer.new()
			section.add_child(hb)
			var paint_lbl = Label.new()
			paint_lbl.text = "Paint Color:"
			hb.add_child(paint_lbl)
			var info = Label.new()
			info.text = "(Use Color Picker Tool)"
			section.add_child(info)

func _create_shader_materials() -> void:
	var plasma_shader = load("res://src/demos/tools/shaders/plasma.gdshader") as Shader
	if plasma_shader:
		_plasma_shader_material = ShaderMaterial.new()
		_plasma_shader_material.shader = plasma_shader
		
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0, 0.385, 0.656, 0.887, 1])
		gradient.colors = PackedColorArray([
			Color(0, 0.021, 0.097, 1), Color(0.295, 0.332, 0.730, 1),
			Color(0.223, 0.724, 0.777, 1), Color(0.877, 0.649, 0.963, 1),
			Color(0.932, 0.719, 0.921, 1)
		])
		
		var noise1 := FastNoiseLite.new()
		noise1.frequency = 0.002
		noise1.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise1.fractal_octaves = 4
		
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
	
	for mat_name in MATERIAL_PATHS.keys():
		var path = MATERIAL_PATHS[mat_name]
		if ResourceLoader.exists(path):
			var mat = load(path) as Material
			if mat:
				_loaded_materials[mat_name] = mat
				_material_names.append(mat_name)
	
	for mat_name in SHADER_MATERIALS.keys():
		match SHADER_MATERIALS[mat_name]:
			"plasma":
				if _plasma_shader_material:
					_loaded_materials[mat_name] = _plasma_shader_material
					_material_names.append(mat_name)

func _populate_material_section() -> void:
	var section = _create_section("Material")
	_add_sidebar_button("Materials", "Material")
	
	var lbl = Label.new()
	lbl.text = "Material Selection"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	section.add_child(lbl)
	
	var hbox = HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section.add_child(hbox)
	
	material_list_ui = ItemList.new()
	material_list_ui.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	material_list_ui.size_flags_vertical = Control.SIZE_EXPAND_FILL
	material_list_ui.custom_minimum_size = Vector2(100, 150)
	material_list_ui.item_selected.connect(_on_material_selected_ui)
	hbox.add_child(material_list_ui)
	
	var right_vbox = VBoxContainer.new()
	right_vbox.custom_minimum_size.x = 160
	hbox.add_child(right_vbox)
	
	material_preview = ColorRect.new()
	material_preview.custom_minimum_size = Vector2(100, 100)
	right_vbox.add_child(material_preview)
	
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_vbox.add_child(status_label)
	
	for m_name in _material_names:
		material_list_ui.add_item(m_name)
	
	if material_list_ui.item_count > 0:
		material_list_ui.select(0)
		_on_material_selected_ui(0)

func _on_material_selected_ui(index: int) -> void:
	if index < 0 or index >= _material_names.size(): return
	var mat_name = _material_names[index]
	_current_material = _loaded_materials.get(mat_name)
	
	_update_preview(mat_name)
	status_label.text = "Selected: " + mat_name
	
	var tool = _find_poly_tool()
	if tool:
		if tool.has_method("refresh_material_visuals"):
			tool.refresh_material_visuals()

func _update_preview(mat_name: String) -> void:
	if not material_preview: return
	var mat = _loaded_materials.get(mat_name)
	if not mat: return
	
	if mat is ShaderMaterial:
		material_preview.material = mat
	elif mat is StandardMaterial3D:
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
			material_preview.material = preview_mat
		else:
			material_preview.material = null
			material_preview.color = std_mat.albedo_color
	else:
		material_preview.material = null
		material_preview.color = Color(0.5, 0.5, 0.5)

func get_current_material() -> Material:
	return _current_material

func _populate_file_section() -> void:
	var section = _create_section("File")
	_add_sidebar_button("Export/File", "File")
	
	# Name input row
	var name_row = HBoxContainer.new()
	section.add_child(name_row)
	var name_lbl = Label.new()
	name_lbl.text = "Name:"
	name_lbl.custom_minimum_size.x = 60
	name_row.add_child(name_lbl)
	path_edit = LineEdit.new()
	path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_edit.placeholder_text = "Enter drawing name"
	name_row.add_child(path_edit)
	
	var loc_lbl = Label.new()
	loc_lbl.text = "Save Location:"
	section.add_child(loc_lbl)
	
	location_dropdown = OptionButton.new()
	location_dropdown.add_item("Documents")
	location_dropdown.add_item("App Storage")
	location_dropdown.add_item("Project")
	location_dropdown.item_selected.connect(_on_location_changed)
	section.add_child(location_dropdown)
	
	file_list = ItemList.new()
	file_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	file_list.custom_minimum_size.y = 150
	file_list.item_selected.connect(_on_file_selected)
	section.add_child(file_list)
	
	# Save/Load/Refresh row
	var save_row = HBoxContainer.new()
	section.add_child(save_row)
	save_button = Button.new()
	save_button.text = "Save"
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(_on_save_pressed)
	save_row.add_child(save_button)
	
	load_button = Button.new()
	load_button.text = "Load"
	load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_button.pressed.connect(_on_load_pressed)
	save_row.add_child(load_button)
	
	refresh_button = Button.new()
	refresh_button.pressed.connect(func(): _populate_file_list())
	save_row.add_child(refresh_button)
	
	
	# Publish row (separate from save/load)
	var pub_row = HBoxContainer.new()
	section.add_child(pub_row)
	var pub_btn = Button.new()
	pub_btn.text = "Publish to Library"
	pub_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pub_btn.pressed.connect(_on_publish_pressed)
	pub_row.add_child(pub_btn)
	
	_reset_path_to_default()
	_populate_file_list()

func _on_publish_pressed() -> void:
	var tool = _find_poly_tool()
	if not tool or not path_edit: return
	
	var asset_name = path_edit.text.get_basename()
	if asset_name.is_empty():
		if status_label: status_label.text = "Error: Name required"
		return
	
	if status_label: status_label.text = "Exporting..."
	
	# 1. Export to temp file
	var temp_path = "user://temp_publish.glb"
	var err = tool.export_to_gltf(temp_path)
	if err != OK:
		if status_label: status_label.text = "Export Error %d" % err
		return
		
	# 2. Get auth token
	var nakama = get_node_or_null("/root/NakamaManager")
	if not nakama or not nakama.get("is_authenticated"):
		if status_label: status_label.text = "Error: Not authenticated"
		return
	
	var token = ""
	if nakama.get("session") is Dictionary:
		token = nakama.get("session").get("token", "")
		
	if token.is_empty():
		if status_label: status_label.text = "Error: No session token"
		return
		
	# 3. Upload to server
	_upload_asset(temp_path, asset_name, token)

func _upload_asset(file_path: String, asset_name: String, token: String) -> void:
	if status_label: status_label.text = "Publishing..."
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		if status_label: status_label.text = "Error reading temp file"
		return
	
	var body_data = file.get_buffer(file.get_length())
	file.close()
	
	var boundary = "GodotPolyToolBoundary"
	var body = PackedByteArray()
	
	# Add 'name' field
	body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
	body.append_array(("Content-Disposition: form-data; name=\"name\"\r\n\r\n").to_utf8_buffer())
	body.append_array((asset_name + "\r\n").to_utf8_buffer())
	
	# Add 'category' field
	body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
	body.append_array(("Content-Disposition: form-data; name=\"category\"\r\n\r\n").to_utf8_buffer())
	body.append_array(("model\r\n").to_utf8_buffer())
	
	# Add 'description' field
	body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
	body.append_array(("Content-Disposition: form-data; name=\"description\"\r\n\r\n").to_utf8_buffer())
	body.append_array(("Created with Poly Tool\r\n").to_utf8_buffer())
	
	# Add 'file' field
	body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
	body.append_array(("Content-Disposition: form-data; name=\"file\"; filename=\"" + asset_name + ".glb\"\r\n").to_utf8_buffer())
	body.append_array(("Content-Type: application/octet-stream\r\n\r\n").to_utf8_buffer())
	body.append_array(body_data)
	body.append_array(("\r\n").to_utf8_buffer())
	
	# End boundary
	body.append_array(("--" + boundary + "--\r\n").to_utf8_buffer())
	
	var headers = [
		"Content-Type: multipart/form-data; boundary=" + boundary,
		"Authorization: Bearer " + token
	]
	
	var server_url = "http://158.101.21.99:3001/assets"
	if AssetLibraryUI.instance:
		server_url = AssetLibraryUI.ASSET_SERVER_URL + "/assets"
		
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(res, code, hdrs, bdy): 
		if code == 201:
			if status_label: status_label.text = "Successfully Published!"
			# Refresh library if it's open
			if AssetLibraryUI.instance:
				AssetLibraryUI.instance._fetch_library()
		else:
			var err_msg = "Error %d" % code
			if bdy.size() > 0:
				var json = JSON.parse_string(bdy.get_string_from_utf8())
				if json and json.has("error"):
					err_msg = json.error
			if status_label: status_label.text = err_msg
		http.queue_free()
	)
	
	var err = http.request_raw(server_url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		if status_label: status_label.text = "Request Start Error %d" % err
		http.queue_free()

func _populate_layer_section() -> void:
	var section = _create_section("Layers")
	_add_sidebar_button("Layers", "Layers")
	
	layer_list = ItemList.new()
	layer_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layer_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layer_list.custom_minimum_size.y = 200
	layer_list.item_selected.connect(_on_layer_selected)
	section.add_child(layer_list)
	
	var debug_info = Label.new()
	debug_info.name = "DebugLayerInfo"
	section.add_child(debug_info)
	
	var action_row = HBoxContainer.new()
	section.add_child(action_row)
	layer_name_edit = LineEdit.new()
	layer_name_edit.placeholder_text = "New Name"
	layer_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(layer_name_edit)
	
	add_layer_button = Button.new()
	add_layer_button.text = " + "
	add_layer_button.pressed.connect(_on_add_layer_pressed)
	action_row.add_child(add_layer_button)
	
	remove_layer_button = Button.new()
	remove_layer_button.text = " - "
	remove_layer_button.pressed.connect(_on_remove_layer_pressed)
	action_row.add_child(remove_layer_button)

func _populate_props_section() -> void:
	props_container = _create_section("Settings")
	_add_sidebar_button("Settings", "Settings")
	
	_add_slider_prop("Snap Radius", 0.001, 0.1, 0.001, "snap_radius")
	_add_slider_prop("Selection Radius", 0.01, 0.5, 0.01, "selection_radius")
	_add_slider_prop("Face Select Radius", 0.01, 0.5, 0.01, "face_selection_radius")
	_add_slider_prop("Select Vol Radius", 0.1, 2.0, 0.1, "selection_volume_radius")
	_add_check_prop("Merge Points", "merge_overlapping_points")
	_add_slider_prop("Merge Dist", 0.0001, 0.05, 0.001, "merge_distance")

func _add_slider_prop(label_text: String, min_val: float, max_val: float, step_val: float, prop_name: String) -> void:
	var hb = HBoxContainer.new()
	props_container.add_child(hb)
	var lbl = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 100
	hb.add_child(lbl)
	var slider = HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step_val
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tool = _find_poly_tool()
	if tool: slider.value = tool.get(prop_name)
	slider.value_changed.connect(func(val): _on_prop_changed(prop_name, val))
	hb.add_child(slider)

func _add_check_prop(label_text: String, prop_name: String) -> void:
	var cb = CheckBox.new()
	cb.text = label_text
	var tool = _find_poly_tool()
	if tool: cb.button_pressed = tool.get(prop_name)
	cb.toggled.connect(func(val): _on_prop_changed(prop_name, val))
	props_container.add_child(cb)

func _on_prop_changed(prop_name: String, value: Variant) -> void:
	var tool = _find_poly_tool()
	if tool:
		tool.set(prop_name, value)

func _on_layer_selected(index: int) -> void:
	var tool = _find_poly_tool()
	if tool:
		tool.active_layer_idx = index

func _on_add_layer_pressed() -> void:
	var tool = _find_poly_tool()
	if tool:
		var lname = layer_name_edit.text.strip_edges()
		tool.add_new_layer(lname)
		layer_name_edit.text = ""
		_update_layer_list()

func _on_remove_layer_pressed() -> void:
	var tool = _find_poly_tool()
	if tool:
		tool.remove_active_layer()
		_update_layer_list()

func _update_layer_list() -> void:
	if not layer_list: return
	var tool = _find_poly_tool()
	if not tool: return
	
	var layers = tool.get_layers()
	var current_count = layers.size()
	var current_idx = tool.active_layer_idx
	
	# Update debug info
	var debug_info = layer_list.get_parent().get_node_or_null("DebugLayerInfo")
	if debug_info:
		debug_info.text = "Tool Layers: %d, Active: %d" % [current_count, current_idx]
	
	# Only rebuild if count changed or it's the first time
	if current_count != _last_layer_count:
		layer_list.clear()
		for i in current_count:
			var lname = layers[i].name
			if lname == "": lname = "Layer " + str(i + 1)
			layer_list.add_item(lname)
		_last_layer_count = current_count
		_last_active_layer_idx = -1 
	
	# Update selection if index changed
	if current_idx != _last_active_layer_idx:
		if current_idx >= 0 and current_idx < layer_list.item_count:
			layer_list.select(current_idx)
		_last_active_layer_idx = current_idx

func _refresh_summary() -> void:
	var tool = _find_poly_tool()
	if tool:
		if info_label:
			info_label.text = "Points: %d   Triangles: %d" % [tool.get_point_count(), tool.get_triangle_count()]
		_update_layer_list()
	elif info_label:
		info_label.text = "Poly Tool not found"

# Original File logic (adapted)
func _get_documents_dir() -> String:
	var docs_dir := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if docs_dir != "": return docs_dir.path_join("SceneTree/gltf")
	return DIR_USER

func _get_current_dir() -> String:
	match _current_location:
		StorageLocation.DOCUMENTS: return _get_documents_dir()
		StorageLocation.USER: return DIR_USER
		StorageLocation.PROJECT: return DIR_PROJECT
	return DIR_USER

func _setup_http_request() -> void:
	_http_request = HTTPRequest.new()
	add_child(_http_request)

func _on_location_changed(index: int) -> void:
	_current_location = index as StorageLocation
	_populate_file_list()
	_reset_path_to_default()

func _reset_path_to_default() -> void:
	if not path_edit: return
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	path_edit.text = "poly_%s.gltf" % timestamp

func _populate_file_list() -> void:
	if not file_list: return
	file_list.clear()
	var dir_path := _get_current_dir()
	# Ensure directory exists
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var dir := DirAccess.open(dir_path)
	if not dir: return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and (name.to_lower().ends_with(".gltf") or name.to_lower().ends_with(".glb")):
			file_list.add_item(name)
		name = dir.get_next()
	dir.list_dir_end()

func _on_file_selected(index: int) -> void:
	if path_edit: path_edit.text = file_list.get_item_text(index)

func _on_save_pressed() -> void:
	var tool = _find_poly_tool()
	if not tool or not path_edit: return
	var target_path = _get_current_dir().path_join(path_edit.text)
	var err = tool.export_to_gltf(target_path)
	if status_label:
		status_label.text = "Saved" if err == OK else "Error %d" % err

func _on_load_pressed() -> void:
	var tool = _find_poly_tool()
	if not tool or not path_edit: return
	var target_path = _get_current_dir().path_join(path_edit.text)
	var err = tool.load_from_gltf(target_path)
	if status_label:
		status_label.text = "Loaded" if err == OK else "Error %d" % err



func _find_poly_tool() -> PolyTool:
	return PolyTool.instance if PolyTool.instance and is_instance_valid(PolyTool.instance) else null
