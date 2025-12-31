class_name DesktopCEFBackend
extends WebViewBackend

## Desktop CEF (Chromium Embedded Framework) backend
## Works on Windows, macOS, and Linux

var _cef_node: Node = null
var _browser: Object = null
var _texture_rect: TextureRect = null
var _current_url: String = ""
var _is_initialized: bool = false
var _parent_node: Node = null

# CEF settings
var _cef_settings := {
	"artifacts": "res://cef_artifacts/",
	"locale": "en-US",
	"remote_debugging_port": 0,
	"enable_media_stream": false,
	"cache_path": "user://cef_cache/"
}

var _browser_settings := {
	"javascript": true,
	"javascript_close_windows": false,
	"javascript_access_clipboard": false,
	"javascript_dom_paste": false,
	"image_loading": true,
	"databases": false,
	"webgl": true
}


func initialize(settings: Dictionary) -> bool:
	var platform := OS.get_name()
	if platform == "Android" or platform == "iOS":
		push_error("DesktopCEFBackend: Not supported on mobile platforms")
		return false
	
	# Check if gdCEF is available
	if not ClassDB.class_exists("GDCef"):
		push_warning("DesktopCEFBackend: GDCef class not found. Install gdCEF addon.")
		return false
	
	# Get parent node from settings (needed to add CEF node to tree)
	_parent_node = settings.get("parent_node", null)
	if not _parent_node:
		push_error("DesktopCEFBackend: parent_node required in settings")
		return false
	
	# Merge user settings
	if settings.has("cef_settings"):
		_cef_settings.merge(settings.cef_settings, true)
	if settings.has("browser_settings"):
		_browser_settings.merge(settings.browser_settings, true)
	
	# Create CEF node
	_cef_node = ClassDB.instantiate("GDCef")
	if not _cef_node:
		push_error("DesktopCEFBackend: Failed to instantiate GDCef")
		return false
	
	_parent_node.add_child(_cef_node)
	
	# Initialize CEF
	if _cef_node.has_method("initialize"):
		if not _cef_node.initialize(_cef_settings):
			push_error("DesktopCEFBackend: CEF initialization failed")
			_cef_node.queue_free()
			_cef_node = null
			return false
	
	# Store texture rect reference
	_texture_rect = settings.get("texture_rect", null)
	
	# Create browser with default URL
	var default_url: String = settings.get("url", "about:blank")
	if not _create_browser(default_url):
		return false
	
	_is_initialized = true
	return true


func _create_browser(url: String) -> bool:
	if not _cef_node or not _texture_rect:
		return false
	
	if _cef_node.has_method("create_browser"):
		_browser = _cef_node.create_browser(url, _texture_rect, _browser_settings)
		if not _browser:
			push_error("DesktopCEFBackend: Failed to create browser")
			return false
		
		# Connect browser signals
		if _browser.has_signal("on_page_loaded"):
			_browser.on_page_loaded.connect(_on_page_loaded)
		if _browser.has_signal("on_load_start"):
			_browser.on_load_start.connect(_on_load_start)
		if _browser.has_signal("on_load_progress"):
			_browser.on_load_progress.connect(_on_load_progress)
		if _browser.has_signal("on_title_change"):
			_browser.on_title_change.connect(_on_title_change)
		
		_current_url = url
		return true
	
	return false


func shutdown() -> void:
	if _browser and _browser.has_method("close"):
		_browser.close()
	_browser = null
	
	if _cef_node:
		if _cef_node.has_method("shutdown"):
			_cef_node.shutdown()
		_cef_node.queue_free()
		_cef_node = null
	
	_is_initialized = false


func load_url(url: String) -> void:
	if not _is_initialized or not _browser:
		return
	
	_current_url = url
	if _browser.has_method("load_url"):
		_browser.load_url(url)


func get_url() -> String:
	if _browser and _browser.has_method("get_url"):
		return _browser.get_url()
	return _current_url


func is_loaded() -> bool:
	if _browser and _browser.has_method("is_loaded"):
		return _browser.is_loaded()
	return false


func reload() -> void:
	if _browser and _browser.has_method("reload"):
		_browser.reload()


func go_back() -> void:
	if _browser and _browser.has_method("go_back"):
		_browser.go_back()


func go_forward() -> void:
	if _browser and _browser.has_method("go_forward"):
		_browser.go_forward()


func can_go_back() -> bool:
	if _browser and _browser.has_method("can_go_back"):
		return _browser.can_go_back()
	return false


func can_go_forward() -> bool:
	if _browser and _browser.has_method("can_go_forward"):
		return _browser.can_go_forward()
	return false


func stop_loading() -> void:
	if _browser and _browser.has_method("stop_load"):
		_browser.stop_load()


func resize(width: int, height: int) -> void:
	if _browser and _browser.has_method("resize"):
		_browser.resize(width, height)


func send_mouse_move(x: int, y: int) -> void:
	if _browser and _browser.has_method("on_mouse_moved"):
		_browser.on_mouse_moved(x, y)


func send_mouse_down(x: int, y: int, button: int = 0) -> void:
	if not _browser:
		return
	
	# Move mouse first
	send_mouse_move(x, y)
	
	# Then send button down
	match button:
		0:  # Left
			if _browser.has_method("on_mouse_left_down"):
				_browser.on_mouse_left_down()
		1:  # Right
			if _browser.has_method("on_mouse_right_down"):
				_browser.on_mouse_right_down()
		2:  # Middle
			if _browser.has_method("on_mouse_middle_down"):
				_browser.on_mouse_middle_down()


func send_mouse_up(x: int, y: int, button: int = 0) -> void:
	if not _browser:
		return
	
	match button:
		0:  # Left
			if _browser.has_method("on_mouse_left_up"):
				_browser.on_mouse_left_up()
		1:  # Right
			if _browser.has_method("on_mouse_right_up"):
				_browser.on_mouse_right_up()
		2:  # Middle
			if _browser.has_method("on_mouse_middle_up"):
				_browser.on_mouse_middle_up()


func send_scroll(x: int, y: int, delta: float) -> void:
	if _browser and _browser.has_method("on_mouse_wheel"):
		_browser.on_mouse_wheel(int(delta * 100))


func send_key(keycode: int, pressed: bool, shift: bool = false, alt: bool = false, ctrl: bool = false) -> void:
	if _browser and _browser.has_method("on_key_pressed"):
		_browser.on_key_pressed(keycode, pressed, shift, alt, ctrl)


func send_text(text: String) -> void:
	# CEF handles text through key events
	for c in text:
		var code := c.unicode_at(0)
		send_key(code, true)
		send_key(code, false)


func get_texture() -> Texture2D:
	if _browser and _browser.has_method("get_texture"):
		return _browser.get_texture()
	return null


func set_texture_rect(rect: TextureRect) -> void:
	_texture_rect = rect


func get_backend_name() -> String:
	return "gdCEF (Desktop)"


static func is_available() -> bool:
	var platform := OS.get_name()
	if platform == "Android" or platform == "iOS":
		return false
	return ClassDB.class_exists("GDCef")


# Signal handlers
func _on_page_loaded(url: String) -> void:
	_current_url = url
	page_loaded.emit(url)


func _on_load_start(url: String) -> void:
	page_loading.emit(url)


func _on_load_progress(progress: float) -> void:
	load_progress.emit(progress)


func _on_title_change(title: String) -> void:
	page_title_changed.emit(title)
