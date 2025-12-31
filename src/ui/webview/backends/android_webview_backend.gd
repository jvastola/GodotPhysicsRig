class_name AndroidWebViewBackend
extends WebViewBackend

## Android WebView backend using native Android WebView via Godot plugin
## Works on Quest 3 and other Android devices

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
	
	# Initialize the plugin
	if _plugin.has_method("initialize"):
		var result = _plugin.initialize(_width, _height, initial_url)
		if not result:
			push_error("AndroidWebViewBackend: Plugin initialization failed")
			return false
	else:
		push_error("AndroidWebViewBackend: Plugin missing initialize method")
		return false
	
	# Create texture for rendering
	_texture = ImageTexture.new()
	var img := Image.create(_width, _height, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_texture.set_image(img)
	
	# Connect signals
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
	
	_current_url = initial_url
	_is_initialized = true
	
	return true


func shutdown() -> void:
	if _plugin and _plugin.has_method("destroy"):
		_plugin.destroy()
	_plugin = null
	_texture = null
	_is_initialized = false


func load_url(url: String) -> void:
	if not _is_initialized or not _plugin:
		return
	
	_current_url = url
	if _plugin.has_method("loadUrl"):
		_plugin.loadUrl(url)


func get_url() -> String:
	if _plugin and _plugin.has_method("getUrl"):
		return _plugin.getUrl()
	return _current_url


func is_loaded() -> bool:
	if _plugin and _plugin.has_method("getProgress"):
		return _plugin.getProgress() >= 100
	return false


func reload() -> void:
	if _plugin and _plugin.has_method("reload"):
		_plugin.reload()


func go_back() -> void:
	if _plugin and _plugin.has_method("goBack"):
		_plugin.goBack()


func go_forward() -> void:
	if _plugin and _plugin.has_method("goForward"):
		_plugin.goForward()


func can_go_back() -> bool:
	if _plugin and _plugin.has_method("canGoBack"):
		return _plugin.canGoBack()
	return false


func can_go_forward() -> bool:
	if _plugin and _plugin.has_method("canGoForward"):
		return _plugin.canGoForward()
	return false


func stop_loading() -> void:
	if _plugin and _plugin.has_method("stopLoading"):
		_plugin.stopLoading()


func resize(width: int, height: int) -> void:
	if not _is_initialized or not _plugin:
		return
	
	_width = width
	_height = height
	
	if _plugin.has_method("resize"):
		_plugin.resize(width, height)
	
	# Recreate texture
	_texture = ImageTexture.new()
	var img := Image.create(_width, _height, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_texture.set_image(img)


func send_mouse_move(x: int, y: int) -> void:
	if _plugin and _plugin.has_method("touchMove"):
		_plugin.touchMove(x, y)


func send_mouse_down(x: int, y: int, button: int = 0) -> void:
	if _plugin and _plugin.has_method("touchDown"):
		_plugin.touchDown(x, y)


func send_mouse_up(x: int, y: int, button: int = 0) -> void:
	if _plugin and _plugin.has_method("touchUp"):
		_plugin.touchUp(x, y)


func send_scroll(x: int, y: int, delta: float) -> void:
	if _plugin and _plugin.has_method("scroll"):
		_plugin.scroll(x, y, int(delta * 50))


func send_key(keycode: int, pressed: bool, shift: bool = false, alt: bool = false, ctrl: bool = false) -> void:
	# Android WebView handles keys through touch/text input
	pass


func send_text(text: String) -> void:
	if _plugin and _plugin.has_method("inputText"):
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
	if _plugin.has_method("getPixelData"):
		var pixel_data: PackedByteArray = _plugin.getPixelData()
		if pixel_data.size() > 0:
			_update_texture_from_data(pixel_data)


func _update_texture_from_data(data: PackedByteArray) -> void:
	if data.size() != _width * _height * 4:
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
	page_loaded.emit(url)


func _on_page_started(url: String) -> void:
	page_loading.emit(url)


func _on_progress_changed(progress: int) -> void:
	load_progress.emit(float(progress) / 100.0)


func _on_title_changed(title: String) -> void:
	page_title_changed.emit(title)


func _on_texture_updated() -> void:
	# Texture was updated on the Java side
	pass
