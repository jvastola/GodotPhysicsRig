class_name PolyToolUI
extends PanelContainer

signal close_requested

@onready var path_edit: LineEdit = $MarginContainer/VBoxContainer/PathRow/PathEdit
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusLabel
@onready var info_label: Label = $MarginContainer/VBoxContainer/InfoLabel
@onready var files_label: Label = $MarginContainer/VBoxContainer/FilesLabel
@onready var save_button: Button = $MarginContainer/VBoxContainer/ButtonRow/SaveButton
@onready var refresh_button: Button = $MarginContainer/VBoxContainer/ButtonRow/RefreshButton
@onready var timestamp_button: Button = $MarginContainer/VBoxContainer/PathRow/TimestampButton
@onready var load_button: Button = $MarginContainer/VBoxContainer/ButtonRow/LoadButton
@onready var file_list: ItemList = $MarginContainer/VBoxContainer/FileList
@onready var location_dropdown: OptionButton = $MarginContainer/VBoxContainer/LocationRow/LocationDropdown
@onready var server_url_edit: LineEdit = $MarginContainer/VBoxContainer/UploadRow/ServerUrlEdit
@onready var upload_button: Button = $MarginContainer/VBoxContainer/UploadRow/UploadButton
@onready var close_button: Button = $MarginContainer/VBoxContainer/TitleRow/CloseButton

static var instance: PolyToolUI = null

# Storage location options
enum StorageLocation {
	DOCUMENTS,  # /sdcard/Documents/SceneTree/gltf or OS documents folder
	USER,       # user://poly_exports
	PROJECT     # res://src/levels/poly_exports
}

var _current_location: StorageLocation = StorageLocation.DOCUMENTS
var _http_request: HTTPRequest = null
var _upload_server_url: String = "https://localhost:3000/upload"

# Directory paths for each location
const DIR_USER := "user://poly_exports"
const DIR_PROJECT := "res://src/levels/poly_exports"


func _get_documents_dir() -> String:
	var docs_dir := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if docs_dir != "":
		return docs_dir.path_join("SceneTree/gltf")
	# Fallback for platforms without documents folder
	return DIR_USER


func _get_current_dir() -> String:
	match _current_location:
		StorageLocation.DOCUMENTS:
			return _get_documents_dir()
		StorageLocation.USER:
			return DIR_USER
		StorageLocation.PROJECT:
			return DIR_PROJECT
	return DIR_USER


func _ready() -> void:
	instance = self
	_setup_http_request()
	_connect_ui()
	_reset_path_to_default()
	_populate_file_list()
	_refresh_summary()
	_update_files_label()
	
	if close_button:
		close_button.pressed.connect(func(): close_requested.emit())


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _setup_http_request() -> void:
	_http_request = HTTPRequest.new()
	_http_request.name = "HTTPRequest"
	add_child(_http_request)
	_http_request.request_completed.connect(_on_upload_completed)


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
	if location_dropdown and not location_dropdown.item_selected.is_connected(_on_location_changed):
		location_dropdown.item_selected.connect(_on_location_changed)
	if upload_button and not upload_button.pressed.is_connected(_on_upload_pressed):
		upload_button.pressed.connect(_on_upload_pressed)


func _on_location_changed(index: int) -> void:
	_current_location = index as StorageLocation
	_update_files_label()
	_populate_file_list()
	_reset_path_to_default()


func _update_files_label() -> void:
	if not files_label:
		return
	var dir_path := _get_current_dir()
	var location_name := ""
	match _current_location:
		StorageLocation.DOCUMENTS:
			location_name = "Documents"
		StorageLocation.USER:
			location_name = "App Storage"
		StorageLocation.PROJECT:
			location_name = "Project"
	files_label.text = "Files in %s:" % location_name


func _reset_path_to_default() -> void:
	if not path_edit:
		return
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	path_edit.text = "poly_%s.gltf" % timestamp
	if status_label:
		status_label.text = ""


func _get_full_path(filename: String) -> String:
	var base_dir := _get_current_dir()
	if filename.begins_with("res://") or filename.begins_with("user://") or filename.begins_with("/"):
		return filename
	return base_dir.path_join(filename)


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
	
	var filename := path_edit.text.strip_edges()
	if filename.is_empty():
		var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
		filename = "poly_%s.gltf" % timestamp
		path_edit.text = filename
	
	# Ensure .gltf extension
	if not filename.to_lower().ends_with(".gltf") and not filename.to_lower().ends_with(".glb"):
		filename += ".gltf"
		path_edit.text = filename
	
	var target_path := _get_full_path(filename)
	
	# Ensure directory exists
	var base_dir := target_path.get_base_dir()
	_ensure_dir(base_dir)
	
	var err := tool.export_to_gltf(target_path)
	if err == OK:
		var display_path := target_path
		if not target_path.begins_with("res://"):
			display_path = ProjectSettings.globalize_path(target_path)
		_set_status("Saved: %s" % filename, false)
		_populate_file_list()
	elif err == ERR_CANT_CREATE:
		_set_status("Nothing to export (add triangles)", true)
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
	
	var filename := ""
	if path_edit:
		filename = path_edit.text.strip_edges()
	if filename.is_empty():
		filename = _selected_file_name()
	if filename.is_empty():
		_set_status("Select a file or enter a name", true)
		return
	
	var target_path := _get_full_path(filename)
	var err := tool.load_from_gltf(target_path)
	if err == OK:
		_set_status("Loaded: %s" % filename, false)
		if path_edit:
			path_edit.text = filename
		_refresh_summary()
	elif err == ERR_FILE_NOT_FOUND:
		_set_status("File not found", true)
	elif err == ERR_INVALID_DATA:
		_set_status("Invalid mesh data", true)
	else:
		_set_status("Load failed (code %s)" % err, true)
	_refresh_summary()


func _on_upload_pressed() -> void:
	if not server_url_edit:
		_set_status("Server URL input not found", true)
		return
	
	var server_url := server_url_edit.text.strip_edges()
	if server_url.is_empty() or server_url == "https://localhost:3000/upload":
		_set_status("Enter a valid server URL", true)
		return
	
	var filename := ""
	if path_edit:
		filename = path_edit.text.strip_edges()
	if filename.is_empty():
		filename = _selected_file_name()
	if filename.is_empty():
		_set_status("Select a file to upload", true)
		return
	
	var target_path := _get_full_path(filename)
	
	# Read the file
	var file := FileAccess.open(target_path, FileAccess.READ)
	if not file:
		_set_status("Could not read file", true)
		return
	
	var file_content := file.get_buffer(file.get_length())
	file.close()
	
	# Prepare multipart form data
	var boundary := "----GodotBoundary%d" % Time.get_ticks_msec()
	var headers := [
		"Content-Type: multipart/form-data; boundary=%s" % boundary
	]
	
	# Build multipart body
	var body := PackedByteArray()
	body.append_array(("--%s\r\n" % boundary).to_utf8_buffer())
	body.append_array(("Content-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\n" % filename).to_utf8_buffer())
	body.append_array("Content-Type: model/gltf+json\r\n\r\n".to_utf8_buffer())
	body.append_array(file_content)
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	
	_set_status("Uploading...", false)
	upload_button.disabled = true
	
	var err := _http_request.request_raw(server_url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_set_status("Upload request failed", true)
		upload_button.disabled = false


func _on_upload_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	upload_button.disabled = false
	
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_status("Upload failed (network error)", true)
		return
	
	if response_code >= 200 and response_code < 300:
		_set_status("Upload successful!", false)
	else:
		_set_status("Upload failed (HTTP %d)" % response_code, true)


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
	
	var dir_path := _get_current_dir()
	_ensure_dir(dir_path)
	
	var dir := DirAccess.open(dir_path)
	if not dir:
		file_list.add_item("(cannot access folder)")
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


func _ensure_dir(dir_path: String) -> bool:
	if dir_path.is_empty():
		return false
	
	# For absolute paths
	if dir_path.begins_with("/"):
		var err := DirAccess.make_dir_recursive_absolute(dir_path)
		return err == OK or DirAccess.dir_exists_absolute(dir_path)
	
	# For res:// and user:// paths
	var abs_dir := ProjectSettings.globalize_path(dir_path)
	var err := DirAccess.make_dir_recursive_absolute(abs_dir)
	return err == OK or DirAccess.dir_exists_absolute(abs_dir)


func _on_file_selected(index: int) -> void:
	if not file_list or not path_edit:
		return
	var name := file_list.get_item_text(index)
	if name.begins_with("("):
		return
	path_edit.text = name


func _selected_file_name() -> String:
	if not file_list:
		return ""
	var sel := file_list.get_selected_items()
	if sel.is_empty():
		return ""
	var name := file_list.get_item_text(sel[0])
	if name.begins_with("("):
		return ""
	return name
