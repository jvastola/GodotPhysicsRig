class_name AndroidWebViewBackend
extends WebViewBackend

## Android WebView backend using native Android WebView via Godot plugin
## Works on Quest 3 and other Android devices
##
## NOTE: has_method() doesn't work reliably with Android plugins,
## so we call methods directly and catch errors if they fail.

var _plugin: Object = null
var _texture: ImageTexture = null
var _texture_rect: TextureRect = null
var _current_url: String = ""
var _is_initialized: bool = false
var _width: int = 1280
var _height: int = 720

# Update timer
var _update_timer: float = 0.0
var _update_interval: float = 0.033  # ~30 FPS


func initialize(settings: Dictionary) -> bool:
	if OS.get_name() != "Android":
		push_error("AndroidWebViewBackend: Not running on Android")
		return false
	
	# Check if our plugin is available
	if not Engine.has_singleton("GodotAndroidWebView"):
		push_warning("AndroidWebViewBackend: GodotAndroidWebView plugin not found")
		return false
	
	_plugin = Engine.get_singleton("GodotAndroidWebView")
	if not _plugin:
		push_error("AndroidWebViewBackend: Failed to get GodotAndroidWebView singleton")
		return false
	
	_width = settings.get("width", 1280)
	_height = settings.get("height", 720)
	var initial_url: String = settings.get("url", "about:blank")
	
	# Store the texture rect reference
	_texture_rect = settings.get("texture_rect", null)
	
	# Initialize the plugin - call directly without has_method check
	# (has_method doesn't work reliably with Android plugins)
	var result = _plugin.initialize(_width, _height, initial_url)
	if not result:
		push_error("AndroidWebViewBackend: Plugin initialization failed")
		return false
	
	# Create texture for rendering
	_texture = ImageTexture.new()
	var img := Image.create(_width, _height, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_texture.set_image(img)
	
	# Apply texture to TextureRect immediately
	if _texture_rect:
		_texture_rect.texture = _texture
		print("AndroidWebViewBackend: Texture applied to TextureRect")
	
	# Connect signals (has_signal works fine)
	if _plugin.has_signal("page_loaded"):
		_plugin.page_loaded.connect(_on_page_loaded)
	if _plugin.has_signal("page_started"):
		_plugin.page_started.connect(_on_page_started)
	if _plugin.has_signal("progress_changed"):
		_plugin.progress_changed.connect(_on_progress_changed)
	if _plugin.has_signal("title_changed"):
		_plugin.title_changed.connect(_on_title_changed)
	if _plugin.has_signal("texture_updated"):
		_plugin.texture_updated.connect(_on_texture_updated)
	if _plugin.has_signal("scroll_info_received"):
		_plugin.scroll_info_received.connect(_on_scroll_info_received)
	
	_current_url = initial_url
	_is_initialized = true
	print("AndroidWebViewBackend: Initialized successfully, URL: ", initial_url)
	
	return true


func shutdown() -> void:
	if _plugin:
		_plugin.destroy()
	_plugin = null
	_texture = null
	_is_initialized = false


func load_url(url: String) -> void:
	if not _is_initialized or not _plugin:
		return
	_current_url = url
	_plugin.loadUrl(url)


func get_url() -> String:
	if _plugin:
		return _plugin.getUrl()
	return _current_url


func is_loaded() -> bool:
	if _plugin:
		return _plugin.getProgress() >= 100
	return false


func reload() -> void:
	if _plugin:
		_plugin.reload()


func go_back() -> void:
	if _plugin:
		_plugin.goBack()


func go_forward() -> void:
	if _plugin:
		_plugin.goForward()


func can_go_back() -> bool:
	if _plugin:
		return _plugin.canGoBack()
	return false


func can_go_forward() -> bool:
	if _plugin:
		return _plugin.canGoForward()
	return false


func stop_loading() -> void:
	if _plugin:
		_plugin.stopLoading()


func resize(width: int, height: int) -> void:
	if not _is_initialized or not _plugin:
		return
	
	_width = width
	_height = height
	_plugin.resize(width, height)
	
	# Recreate texture
	_texture = ImageTexture.new()
	var img := Image.create(_width, _height, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_texture.set_image(img)


func send_mouse_move(x: int, y: int) -> void:
	if _plugin:
		_plugin.touchMove(x, y)


func send_mouse_down(x: int, y: int, button: int = 0) -> void:
	if _plugin:
		_plugin.touchDown(x, y)


func send_mouse_up(x: int, y: int, button: int = 0) -> void:
	if _plugin:
		_plugin.touchUp(x, y)


## Perform a tap (click) at the specified position
func tap(x: int, y: int) -> void:
	if _plugin:
		_plugin.tap(x, y)


## Cancel current touch gesture
func touch_cancel() -> void:
	if _plugin:
		_plugin.touchCancel()


func send_scroll(x: int, y: int, delta: float) -> void:
	# Native scrolling disabled - use scroll_by_amount instead
	pass


## Scroll by a delta amount using JavaScript (more reliable than native scrolling)
func scroll_by_amount(delta_y: int) -> void:
	if _plugin:
		_plugin.scrollByAmount(delta_y)


## Scroll to a specific position using JavaScript
func scroll_to_position(scroll_y: int) -> void:
	if _plugin:
		_plugin.scrollToPosition(scroll_y)


## Request scroll info from the page (emits scroll_info_received signal)
func request_scroll_info() -> void:
	if _plugin:
		_plugin.getScrollInfo()


func send_key(keycode: int, pressed: bool, shift: bool = false, alt: bool = false, ctrl: bool = false) -> void:
	# Android WebView handles keys through touch/text input
	pass


func send_text(text: String) -> void:
	if _plugin:
		_plugin.inputText(text)


func get_texture() -> Texture2D:
	return _texture


func set_texture_rect(rect: TextureRect) -> void:
	_texture_rect = rect
	if _texture_rect and _texture:
		_texture_rect.texture = _texture


func get_backend_name() -> String:
	return "Android WebView"


## Call this from _process to update the texture
func update(delta: float) -> void:
	if not _is_initialized or not _plugin:
		return
	
	_update_timer += delta
	if _update_timer < _update_interval:
		return
	_update_timer = 0.0
	
	# Get pixel data from plugin
	var pixel_data: PackedByteArray = _plugin.getPixelData()
	if pixel_data.size() > 0:
		_update_texture_from_data(pixel_data)


func _update_texture_from_data(data: PackedByteArray) -> void:
	var expected_size := _width * _height * 4
	if data.size() != expected_size:
		print("AndroidWebViewBackend: Unexpected data size: ", data.size(), " expected: ", expected_size)
		return
	
	var img := Image.create_from_data(_width, _height, false, Image.FORMAT_RGBA8, data)
	if img:
		_texture.update(img)
		if _texture_rect:
			_texture_rect.texture = _texture
		texture_updated.emit()


static func is_available() -> bool:
	if OS.get_name() != "Android":
		return false
	return Engine.has_singleton("GodotAndroidWebView")


# Signal handlers
func _on_page_loaded(url: String) -> void:
	_current_url = url
	# Inject CSS to hide webpage scrollbar (we handle scrolling via drag gestures)
	_hide_webpage_scrollbar()
	page_loaded.emit(url)


func _hide_webpage_scrollbar() -> void:
	if not _plugin:
		return
	# Inject CSS to hide scrollbars on the webpage
	var css_script := """
		(function() {
			var style = document.createElement('style');
			style.textContent = `
				::-webkit-scrollbar { display: none !important; width: 0 !important; height: 0 !important; }
				html, body { scrollbar-width: none !important; -ms-overflow-style: none !important; }
			`;
			document.head.appendChild(style);
		})();
	"""
	_plugin.executeJavaScript(css_script)


func _on_page_started(url: String) -> void:
	page_loading.emit(url)


func _on_progress_changed(progress: int) -> void:
	load_progress.emit(float(progress) / 100.0)


func _on_title_changed(title: String) -> void:
	page_title_changed.emit(title)


func _on_texture_updated() -> void:
	# Texture was updated on the Java side
	pass


func _on_scroll_info_received(json_str: String) -> void:
	# Check for null/empty string before parsing (Requirements 3.1, 3.2)
	if json_str.is_empty() or json_str == "null":
		push_warning("AndroidWebViewBackend: Received empty or null scroll info")
		return
	
	var json := JSON.new()
	var error := json.parse(json_str)
	if error != OK:
		push_warning("AndroidWebViewBackend: Failed to parse scroll info: ", json_str)
		return
	
	# Check if parsed data is Dictionary before using (Requirements 3.1, 3.2, 3.3)
	var data = json.data  # Don't type as Dictionary yet
	if data == null or not data is Dictionary:
		push_warning("AndroidWebViewBackend: Invalid scroll info data type, expected Dictionary")
		return
	
	# Now safe to use as Dictionary
	var scroll_y: int = int(data.get("scrollY", 0))
	var scroll_height: int = int(data.get("scrollHeight", 0))
	var client_height: int = int(data.get("clientHeight", 0))
	scroll_info_received.emit(scroll_y, scroll_height, client_height)
