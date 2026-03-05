extends PanelContainer
class_name ConnectionPanel
## Connection Panel - Server URL, token, connect/disconnect, username

signal connect_requested(server_url: String, token: String)
signal disconnect_requested()
signal username_changed(new_name: String)
signal auto_connect_requested()
signal meta_username_fallback_toggled(enabled: bool)

# UI References
@onready var username_entry: LineEdit = $VBox/UsernameRow/UsernameEntry
@onready var update_name_button: Button = $VBox/UsernameRow/UpdateNameButton
@onready var server_entry: LineEdit = $VBox/ServerEntry
@onready var token_entry: LineEdit = $VBox/TokenEntry
@onready var meta_username_toggle: CheckButton = $VBox/MetaUsernameToggle
@onready var connect_button: Button = $VBox/Buttons/ConnectButton
@onready var disconnect_button: Button = $VBox/Buttons/DisconnectButton
@onready var auto_connect_button: Button = $VBox/HelperButtons/AutoConnectButton
@onready var generate_token_button: Button = $VBox/HelperButtons/GenerateTokenButton
@onready var room_info_label: Label = $VBox/RoomInfo
# SandboxHTTPRequest removed

# State
var local_username: String = ""
var connected_state: bool = false


func _ready():
	_setup_ui()
	_set_defaults()


func _setup_ui():
	connect_button.pressed.connect(_on_connect_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)
	auto_connect_button.pressed.connect(_on_auto_connect_pressed)
	generate_token_button.pressed.connect(_on_generate_token_pressed)
	update_name_button.pressed.connect(_on_update_name_pressed)
	meta_username_toggle.toggled.connect(_on_meta_username_toggle_toggled)
	# sandbox_http_request removed
	
	username_entry.text = local_username
	disconnect_button.disabled = true

	if NakamaManager and NakamaManager.has_signal("display_name_changed"):
		if not NakamaManager.display_name_changed.is_connected(_on_nakama_display_name_changed):
			NakamaManager.display_name_changed.connect(_on_nakama_display_name_changed)
	
	# Register input fields with KeyboardManager for virtual keyboard
	_register_keyboard_fields()


func _register_keyboard_fields() -> void:
	# Find parent viewport for context
	var viewport: SubViewport = null
	var parent = get_parent()
	while parent:
		if parent is SubViewport:
			viewport = parent
			break
		parent = parent.get_parent()
	
	# Register all text entry fields
	if KeyboardManager and KeyboardManager.instance:
		KeyboardManager.instance.register_control(username_entry, viewport)
		KeyboardManager.instance.register_control(server_entry, viewport)
		KeyboardManager.instance.register_control(token_entry, viewport)
		print("ConnectionPanel: Registered input fields with KeyboardManager")


func _set_defaults():
	server_entry.text = _default_livekit_ws_url()
	token_entry.text = ""
	
	# Try to auto-populate username from Nakama display name
	if NakamaManager and not NakamaManager.display_name.is_empty():
		local_username = NakamaManager.display_name
		username_entry.text = local_username
		print("ConnectionPanel: Auto-populated username from Nakama: ", local_username)
	if NakamaManager and NakamaManager.has_method("is_meta_username_fallback_enabled"):
		meta_username_toggle.button_pressed = bool(NakamaManager.is_meta_username_fallback_enabled())


func _on_connect_pressed():
	var server_url = server_entry.text.strip_edges()
	var token = token_entry.text.strip_edges()
	
	if server_url.is_empty() or token.is_empty():
		set_status("❌ Enter server URL and token")
		return
	
	set_status("⏳ Connecting...")
	connect_button.disabled = true
	connect_requested.emit(server_url, token)


func _on_disconnect_pressed():
	disconnect_requested.emit()


func _on_auto_connect_pressed():
	auto_connect_requested.emit()


func _on_generate_token_pressed():
	var nakama_manager = get_node_or_null("/root/NakamaManager")
	if not nakama_manager:
		set_status("❌ NakamaManager not found")
		return
	
	var nakama_id = nakama_manager.local_user_id
	if nakama_id.is_empty() or not nakama_manager.is_authenticated:
		set_status("⚠️ Connect to Nakama first")
		return
	
	if not nakama_manager.has_method("request_livekit_token"):
		set_status("❌ Nakama RPC client missing")
		return
	
	var token_result: Dictionary = await nakama_manager.request_livekit_token("test-room", nakama_id)
	if not token_result.get("ok", false):
		set_status("❌ Token RPC failed: " + token_result.get("error", "unknown"))
		return
	
	var token: String = token_result.get("token", "")
	var server_url: String = token_result.get("ws_url", "")
	token_entry.text = token
	if not server_url.is_empty():
		server_entry.text = server_url
	set_status("✅ Token generated for: " + nakama_id)


func _on_update_name_pressed():
	var new_name = username_entry.text.strip_edges()
	if not new_name.is_empty():
		local_username = new_name
		username_changed.emit(new_name)


func _on_meta_username_toggle_toggled(enabled: bool) -> void:
	meta_username_fallback_toggled.emit(enabled)


func _on_nakama_display_name_changed(new_name: String) -> void:
	var normalized_name := new_name.strip_edges()
	if normalized_name.is_empty():
		return
	local_username = normalized_name
	username_entry.text = normalized_name





# Public API
func set_status(text: String):
	# Status is shown externally by the coordinator
	print("ConnectionPanel: ", text)


func set_connected(connected: bool, room_name: String = ""):
	connected_state = connected
	connect_button.disabled = connected
	disconnect_button.disabled = not connected
	
	if connected:
		room_info_label.text = "🎙️ Room: " + room_name if not room_name.is_empty() else "🎙️ Connected"
	else:
		room_info_label.text = "Room: Not connected"


func set_token_and_connect(token: String):
	token_entry.text = token
	# Ensure URL is set
	if server_entry.text.is_empty():
		server_entry.text = _default_livekit_ws_url()
	
	_on_connect_pressed()


func set_server_url(server_url: String) -> void:
	if server_url.is_empty():
		return
	server_entry.text = server_url


func _default_livekit_ws_url() -> String:
	var nakama_manager = get_node_or_null("/root/NakamaManager")
	if nakama_manager and nakama_manager.has_method("get_livekit_ws_url"):
		return nakama_manager.get_livekit_ws_url()
	var env_url := OS.get_environment("LIVEKIT_WS_URL")
	if not env_url.is_empty():
		return env_url
	return "ws://127.0.0.1:7880"


func get_username() -> String:
	return local_username
