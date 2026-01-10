class_name AssetLibraryUI
extends PanelContainer

## UI for browsing and loading assets (GLTF/GLB) from external sources

# Singleton instance for easy access
static var instance: AssetLibraryUI = null

# Config
# Placeholder mock URL. If the user enters this, we use local mock data.
const MOCK_URL = "mock://assets" 

# UI Elements
var url_input: LineEdit
var fetch_button: Button
var scroll_container: ScrollContainer
var asset_grid: GridContainer
var status_label: Label
var direct_url_input: LineEdit
var direct_load_button: Button

# Networking
var http_request_list: HTTPRequest
var http_request_download: HTTPRequest

# State
var current_assets: Array = []
var pending_download_path: String = ""
var pending_metadata: Dictionary = {}

func _ready() -> void:
	instance = self
	custom_minimum_size = Vector2(360, 480)
	
	_setup_network()
	_build_ui()
	
	# Initial fetch if mock
	url_input.text = MOCK_URL
	call_deferred("_fetch_library")

func _exit_tree() -> void:
	if instance == self:
		instance = null

func _setup_network() -> void:
	http_request_list = HTTPRequest.new()
	http_request_list.timeout = 10.0
	http_request_list.request_completed.connect(_on_list_request_completed)
	add_child(http_request_list)
	
	http_request_download = HTTPRequest.new()
	http_request_download.timeout = 30.0
	http_request_download.request_completed.connect(_on_download_request_completed)
	add_child(http_request_download)

func _build_ui() -> void:
	# Clear children
	for child in get_children():
		if child != http_request_list and child != http_request_download:
			child.queue_free()
			
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	
	# Header
	var title = Label.new()
	title.text = "📦 Asset Library"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)
	
	vbox.add_child(HSeparator.new())
	
	# Source Config
	var source_hbox = HBoxContainer.new()
	url_input = LineEdit.new()
	url_input.placeholder_text = "Library JSON URL"
	url_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	url_input.text = MOCK_URL
	source_hbox.add_child(url_input)
	
	fetch_button = Button.new()
	fetch_button.text = "Fetch"
	fetch_button.pressed.connect(_fetch_library)
	source_hbox.add_child(fetch_button)
	vbox.add_child(source_hbox)
	
	# Grid
	var scroll_bg = PanelContainer.new()
	scroll_bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll_bg)
	
	scroll_container = ScrollContainer.new()
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_bg.add_child(scroll_container)
	
	asset_grid = GridContainer.new()
	asset_grid.columns = 2
	asset_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	asset_grid.add_theme_constant_override("h_separation", 8)
	asset_grid.add_theme_constant_override("v_separation", 8)
	scroll_container.add_child(asset_grid)
	
	# Direct Load
	vbox.add_child(HSeparator.new())
	var direct_label = Label.new()
	direct_label.text = "Direct Load URL (.glb/.gltf)"
	vbox.add_child(direct_label)
	
	var direct_hbox = HBoxContainer.new()
	direct_url_input = LineEdit.new()
	direct_url_input.placeholder_text = "https://example.com/model.glb"
	direct_url_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	direct_hbox.add_child(direct_url_input)
	
	direct_load_button = Button.new()
	direct_load_button.text = "Load"
	direct_load_button.pressed.connect(func(): _download_asset(direct_url_input.text))
	direct_hbox.add_child(direct_load_button)
	vbox.add_child(direct_hbox)
	
	# Publish Section (Mock)
	vbox.add_child(HSeparator.new())
	var pub_label = Label.new()
	pub_label.text = "Publish"
	vbox.add_child(pub_label)
	
	var pub_hbox = HBoxContainer.new()
	var pub_name = LineEdit.new()
	pub_name.placeholder_text = "Item Name"
	pub_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pub_hbox.add_child(pub_name)
	
	var pub_btn = Button.new()
	pub_btn.text = "Upload"
	pub_btn.pressed.connect(func(): _mock_publish(pub_name.text))
	pub_hbox.add_child(pub_btn)
	vbox.add_child(pub_hbox)
	
	# Status
	status_label = Label.new()
	status_label.text = "Ready"
	status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(status_label)

func _set_status(text: String, is_error: bool = false) -> void:
	if not status_label: return
	status_label.text = text
	status_label.modulate = Color(1, 0.5, 0.5) if is_error else Color(1, 1, 1)

func _fetch_library() -> void:
	var url = url_input.text.strip_edges()
	_set_status("Fetching library...")
	
	# Clear grid
	for child in asset_grid.get_children():
		child.queue_free()
	
	if url == MOCK_URL or url.is_empty():
		_load_mock_data()
	else:
		var error = http_request_list.request(url)
		if error != OK:
			_set_status("Request failed: " + str(error), true)

func _load_mock_data() -> void:
	var mock_assets = [
		{
			"name": "Duck (GLB)",
			"url": "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/Duck/glTF-Binary/Duck.glb",
			"type": "gltf"
		},
		{
			"name": "Box (GLB)",
			"url": "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/Box/glTF-Binary/Box.glb",
			"type": "gltf"
		},
		{
			"name": "Example Package (PCK)",
			"url": "https://example.com/demo.pck",
			"type": "package",
			"scene_path": "res://demo/main.tscn",
			"description": "Entire scene with scripts (requires valid URL)"
		}
	]
	_populate_grid(mock_assets)
	_set_status("Mock library loaded")

func _on_list_request_completed(result, response_code, headers, body) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_status("Network error", true)
		return
		
	if response_code != 200:
		_set_status("HTTP Error: " + str(response_code), true)
		return
		
	var json = JSON.new()
	var parse_err = json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		_set_status("JSON Parse Error", true)
		return
		
	var data = json.get_data()
	if data is Array:
		_populate_grid(data)
		_set_status("Library loaded")
	else:
		_set_status("Invalid data format (expected Array)", true)

func _populate_grid(assets: Array) -> void:
	for item in assets:
		if not item is Dictionary: continue
		var name = item.get("name", "Unknown")
		var url = item.get("url", "")
		if url.is_empty(): continue
		
		var panel = PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var vbox = VBoxContainer.new()
		panel.add_child(vbox)
		
		# Thumbnail placeholder (could fetch image if url provided)
		var thumb_rect = ColorRect.new()
		thumb_rect.custom_minimum_size = Vector2(0, 80)
		thumb_rect.color = Color(0.2, 0.2, 0.2)
		vbox.add_child(thumb_rect)
		
		var name_lbl = Label.new()
		name_lbl.text = name
		name_lbl.clip_text = true
		vbox.add_child(name_lbl)
		
		var load_btn = Button.new()
		load_btn.text = "Load"
		load_btn.pressed.connect(func(): _download_asset(url, item))
		vbox.add_child(load_btn)
		
		asset_grid.add_child(panel)

func _download_asset(url: String, metadata: Dictionary = {}) -> void:
	if url.is_empty(): return
	
	_set_status("Downloading: " + url.get_file())
	
	pending_metadata = metadata
	
	# Determine file extension
	var ext = url.get_extension().to_lower()
	if ext.is_empty(): 
		ext = metadata.get("type", "gltf")
		if ext == "gltf": ext = "glb"
		else: ext = "pck"
	
	pending_download_path = "user://temp_download." + ext
	
	# Cancel pending
	http_request_download.cancel_request()
	
	var error = http_request_download.request(url)
	if error != OK:
		_set_status("Download request failed", true)

func _on_download_request_completed(result, response_code, headers, body) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_status("Download failed (Network)", true)
		return
		
	if response_code != 200:
		_set_status("Download failed (HTTP " + str(response_code) + ")", true)
		return
	
	# Save file
	var file = FileAccess.open(pending_download_path, FileAccess.WRITE)
	if not file:
		_set_status("Failed to write to file", true)
		return
		
	file.store_buffer(body)
	file.close() # Ensure flush
	
	var type = pending_metadata.get("type", "")
	if type == "":
		# Detect from extension
		var ext = pending_download_path.get_extension().to_lower()
		if ext == "pck" or ext == "zip":
			type = "package"
		else:
			type = "gltf"
	
	if type == "package":
		_set_status("Package downloaded. Mounting...")
		var scene_path = pending_metadata.get("scene_path", "")
		call_deferred("_load_package", pending_download_path, scene_path)
	else:
		_set_status("Downloaded. Importing...")
		call_deferred("_spawn_asset", pending_download_path)

func _load_package(path: String, scene_path: String) -> void:
	var global_path = ProjectSettings.globalize_path(path)
	var success = ProjectSettings.load_resource_pack(global_path)
	if not success:
		_set_status("Failed to mount package", true)
		return
	
	if scene_path.is_empty():
		_set_status("Package mounted. No scene_path specified.", true)
		return
	
	if not ResourceLoader.exists(scene_path):
		_set_status("Scene not found in pack: " + scene_path, true)
		return
		
	var packed_scene = load(scene_path)
	if not packed_scene or not packed_scene is PackedScene:
		_set_status("Invalid scene resource", true)
		return
		
	var instance = packed_scene.instantiate()
	var scene = get_tree().current_scene
	if not scene: scene = get_tree().root.get_child(0)
	
	scene.add_child(instance)
	_position_in_front_of_player(instance)
	_set_status("Spawned package item: " + instance.name)

func _spawn_asset(path: String) -> void:
	var doc = GLTFDocument.new()
	var state = GLTFState.new()
	
	var error = doc.append_from_file(path, state)
	if error != OK:
		_set_status("GLTF Load Error: " + str(error), true)
		return
	
	var root_node = doc.generate_scene(state)
	if not root_node:
		_set_status("Failed to generate scene", true)
		return
	
	# Add to scene
	var scene = get_tree().current_scene
	if not scene:
		# Fallback for VR cases where root might be different
		scene = get_tree().root.get_child(0)
	
	# Wrap in a rigid body if it's just a mesh, or just spawn it
	# For now, just spawn in front of player
	root_node.name = path.get_file().get_basename()
	scene.add_child(root_node)
	
	_position_in_front_of_player(root_node)
	_set_status("Spawned: " + root_node.name)
    
    # Try to make it grabbable if possible (advanced topic, but let's try)
    # If the user has a generic Grabbable script, we could attach it.
    # checking... Grabbable.gd exists in project? Likely.
    # But for now, just spawning is enough success.

func _mock_publish(name: String) -> void:
	if name.is_empty():
		_set_status("Please enter a name", true)
		return
	_set_status("Publishing '" + name + "'...", false)
	await get_tree().create_timer(1.0).timeout
	_set_status("Successfully published '" + name + "' (Mock)", false)

func _position_in_front_of_player(node: Node3D) -> void:
	var player = get_tree().get_first_node_in_group("xr_player")
	if player:
		var head = player.get_node_or_null("PlayerBody/XROrigin3D/XRCamera3D")
		if head:
			var forward = -head.global_transform.basis.z
			forward.y = 0
			forward = forward.normalized()
			node.global_position = head.global_position + forward * 1.5
			# node.look_at(head.global_position, Vector3.UP)
			# node.rotate_object_local(Vector3.UP, PI) # Match camera
