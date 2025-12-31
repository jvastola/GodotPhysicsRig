class_name WebViewBackend
extends RefCounted

## Abstract base class for webview backends
## Implement this for each platform (Android, Desktop, etc.)

signal page_loaded(url: String)
signal page_loading(url: String)
signal load_progress(progress: float)
signal page_title_changed(title: String)
signal error_occurred(error_code: int, description: String)
signal texture_updated()

## Initialize the backend. Returns true on success.
func initialize(settings: Dictionary) -> bool:
	push_error("WebViewBackend.initialize() not implemented")
	return false

## Shutdown and cleanup resources
func shutdown() -> void:
	pass

## Load a URL
func load_url(url: String) -> void:
	push_error("WebViewBackend.load_url() not implemented")

## Get the current URL
func get_url() -> String:
	push_error("WebViewBackend.get_url() not implemented")
	return ""

## Check if page is loaded
func is_loaded() -> bool:
	return false

## Reload the current page
func reload() -> void:
	pass

## Navigate back
func go_back() -> void:
	pass

## Navigate forward
func go_forward() -> void:
	pass

## Check if can go back
func can_go_back() -> bool:
	return false

## Check if can go forward
func can_go_forward() -> bool:
	return false

## Stop loading
func stop_loading() -> void:
	pass

## Resize the browser viewport
func resize(width: int, height: int) -> void:
	pass

## Send mouse move event
func send_mouse_move(x: int, y: int) -> void:
	pass

## Send mouse button down
func send_mouse_down(x: int, y: int, button: int = 0) -> void:
	pass

## Send mouse button up
func send_mouse_up(x: int, y: int, button: int = 0) -> void:
	pass

## Send scroll/wheel event
func send_scroll(x: int, y: int, delta: float) -> void:
	pass

## Send key event
func send_key(keycode: int, pressed: bool, shift: bool = false, alt: bool = false, ctrl: bool = false) -> void:
	pass

## Send text input (for virtual keyboard)
func send_text(text: String) -> void:
	pass

## Get the rendered texture (if applicable)
func get_texture() -> Texture2D:
	return null

## Get the TextureRect to render into (for backends that need it)
func set_texture_rect(rect: TextureRect) -> void:
	pass

## Check if this backend is available on the current platform
static func is_available() -> bool:
	return false

## Get backend name for debugging
func get_backend_name() -> String:
	return "Unknown"
