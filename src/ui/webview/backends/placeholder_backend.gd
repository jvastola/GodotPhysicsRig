class_name PlaceholderBackend
extends WebViewBackend

## Placeholder backend shown when no real webview backend is available
## Displays installation instructions

var _message: String = ""
var _texture_rect: TextureRect = null

func initialize(settings: Dictionary) -> bool:
	var platform := OS.get_name()
	
	if platform == "Android":
		_message = """WebView not available.

To enable web browsing on Android/Quest:
1. Download TLabWebView from GitHub
2. Extract to addons/tlab_webview/
3. Enable the plugin in Project Settings
4. Rebuild the Android export template

GitHub: github.com/nicemicro/nicemolecules"""
	else:
		_message = """WebView not available.

To enable web browsing on Desktop:
1. Download gdCEF from GitHub
2. Extract to addons/gdcef/
3. Download CEF artifacts (~100MB)
4. Place artifacts in cef_artifacts/
5. Enable the plugin in Project Settings

The webview will work once configured."""
	
	return true


func shutdown() -> void:
	pass


func load_url(url: String) -> void:
	# Can't load URLs without a real backend
	pass


func get_url() -> String:
	return ""


func is_loaded() -> bool:
	return false


func get_backend_name() -> String:
	return "Placeholder"


func get_message() -> String:
	return _message


func set_texture_rect(rect: TextureRect) -> void:
	_texture_rect = rect


static func is_available() -> bool:
	# Placeholder is always available as fallback
	return true
