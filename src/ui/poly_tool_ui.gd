extends PanelContainer
class_name PolyToolUI

@onready var path_edit: LineEdit = $MarginContainer/VBoxContainer/PathRow/PathEdit
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusLabel
@onready var info_label: Label = $MarginContainer/VBoxContainer/InfoLabel
@onready var save_button: Button = $MarginContainer/VBoxContainer/ButtonRow/SaveButton
@onready var refresh_button: Button = $MarginContainer/VBoxContainer/ButtonRow/RefreshButton
@onready var timestamp_button: Button = $MarginContainer/VBoxContainer/PathRow/TimestampButton
@onready var load_button: Button = $MarginContainer/VBoxContainer/ButtonRow/LoadButton
@onready var file_list: ItemList = $MarginContainer/VBoxContainer/FileList

static var instance: PolyToolUI = null

const DEFAULT_DIR := "user://poly_exports"


func _ready() -> void:
	instance = self
	_connect_ui()
	_reset_path_to_default()
	_populate_file_list()
	_refresh_summary()


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _connect_ui() -> void:
	if save_button and not save_button.pressed.is_connected(_on_save_pressed):
		save_button.pressed.connect(_on_save_pressed)
	if refresh_button and not refresh_button.pressed.is_connected(_refresh_summary):
		refresh_button.pressed.connect(func():
			_refresh_summary()
			_populate_file_list()
		)
	if timestamp_button and not timestamp_button.pressed.is_connected(_reset_path_to_default):
		timestamp_button.pressed.connect(_reset_path_to_default)
	if path_edit and not path_edit.text_submitted.is_connected(_on_path_submitted):
		path_edit.text_submitted.connect(_on_path_submitted)
	if load_button and not load_button.pressed.is_connected(_on_load_pressed):
		load_button.pressed.connect(_on_load_pressed)
	if file_list and not file_list.item_selected.is_connected(_on_file_selected):
		file_list.item_selected.connect(_on_file_selected)


func _reset_path_to_default() -> void:
	if not path_edit:
		return
	var tool := _find_poly_tool()
	if tool:
		path_edit.text = tool.get_default_export_path()
	else:
		var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
		path_edit.text = "user://poly_exports/poly_%s.gltf" % timestamp
	if status_label:
		status_label.text = ""


func _refresh_summary() -> void:
	var tool := _find_poly_tool()
	if tool:
		info_label.text = "Points: %d   Triangles: %d" % [tool.get_point_count(), tool.get_triangle_count()]
	else:
		info_label.text = "Poly Tool not found in scene"


func _on_save_pressed() -> void:
	var tool := _find_poly_tool()
	if not tool:
		_set_status("Poly Tool not found", true)
		return
	if not path_edit:
		_set_status("Path input not found", true)
		return
	var target_path := path_edit.text.strip_edges()
	if target_path.is_empty():
		target_path = tool.get_default_export_path()
		path_edit.text = target_path
	var err := tool.export_to_gltf(target_path)
	if err == OK:
		var global_path := ProjectSettings.globalize_path(target_path)
		_set_status("Saved to %s" % global_path, false)
	elif err == ERR_CANT_CREATE:
		_set_status("Nothing to export yet (add triangles)", true)
	else:
		_set_status("Save failed (code %s)" % err, true)
	_refresh_summary()


func _on_path_submitted(_text: String) -> void:
	_on_save_pressed()


func _on_load_pressed() -> void:
	var tool := _find_poly_tool()
	if not tool:
		_set_status("Poly Tool not found", true)
		return
	var target_path := ""
	if path_edit:
		target_path = path_edit.text.strip_edges()
	if target_path.is_empty():
		target_path = _selected_file_path()
	if target_path.is_empty():
		_set_status("Select a GLTF file or enter a path", true)
		return
	if not target_path.begins_with("res://") and not target_path.begins_with("user://"):
		target_path = DEFAULT_DIR.path_join(target_path)
	var err := tool.load_from_gltf(target_path)
	if err == OK:
		var global_path := ProjectSettings.globalize_path(target_path)
		_set_status("Loaded %s" % global_path, false)
		if path_edit:
			path_edit.text = target_path
		_refresh_summary()
	elif err == ERR_FILE_NOT_FOUND:
		_set_status("File not found", true)
	elif err == ERR_INVALID_DATA:
		_set_status("Invalid mesh data in file", true)
	else:
		_set_status("Load failed (code %s)" % err, true)
	_refresh_summary()


func _set_status(text: String, is_error: bool) -> void:
	if not status_label:
		return
	status_label.text = text
	var color := Color(0.8, 1.0, 0.8) if not is_error else Color(1.0, 0.6, 0.6)
	status_label.add_theme_color_override("font_color", color)


func _find_poly_tool() -> PolyTool:
	if PolyTool and PolyTool.instance and is_instance_valid(PolyTool.instance):
		return PolyTool.instance
	for node in get_tree().get_nodes_in_group("grabbable"):
		if node is PolyTool:
			return node
	return null


func _populate_file_list() -> void:
	if not file_list:
		return
	file_list.clear()
	_ensure_export_dir()
	var dir := DirAccess.open(DEFAULT_DIR)
	if not dir:
		return
	var files: Array[String] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			if name.to_lower().ends_with(".gltf") or name.to_lower().ends_with(".glb"):
				files.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	files.sort()
	for f in files:
		file_list.add_item(f)
	if files.is_empty():
		file_list.add_item("(no gltf files yet)")


func _ensure_export_dir() -> void:
	var abs_dir := ProjectSettings.globalize_path(DEFAULT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)


func _on_file_selected(index: int) -> void:
	if not file_list or not path_edit:
		return
	var name := file_list.get_item_text(index)
	if name.begins_with("("):
		return
	path_edit.text = DEFAULT_DIR.path_join(name)


func _selected_file_path() -> String:
	if not file_list:
		return ""
	var sel := file_list.get_selected_items()
	if sel.is_empty():
		return ""
	var name := file_list.get_item_text(sel[0])
	if name.begins_with("("):
		return ""
	return DEFAULT_DIR.path_join(name)

