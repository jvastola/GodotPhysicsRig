extends PanelContainer
class_name ConnectionPanel
## Connection Panel - Server URL, token, connect/disconnect, username

signal connect_requested(server_url: String, token: String)
signal disconnect_requested()
signal username_changed(new_name: String)
signal auto_connect_requested()

# UI References
@onready var username_entry: LineEdit = $VBox/UsernameRow/UsernameEntry
@onready var update_name_button: Button = $VBox/UsernameRow/UpdateNameButton
@onready var server_entry: LineEdit = $VBox/ServerEntry
@onready var token_entry: LineEdit = $VBox/TokenEntry
@onready var connect_button: Button = $VBox/Buttons/ConnectButton
@onready var disconnect_button: Button = $VBox/Buttons/DisconnectButton
@onready var auto_connect_button: Button = $VBox/HelperButtons/AutoConnectButton
@onready var generate_token_button: Button = $VBox/HelperButtons/GenerateTokenButton
@onready var room_info_label: Label = $VBox/RoomInfo
# SandboxHTTPRequest removed

# State
var local_username: String = "User-" + str(randi() % 10000)
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
	# sandbox_http_request removed
	
	username_entry.text = local_username
	disconnect_button.disabled = true
	
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
	# Default to local LiveKit server
	server_entry.text = "ws://158.101.21.99:7880"
	token_entry.text = ""


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
	# Get Nakama ID from NetworkManager
	var network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager:
		set_status("❌ NetworkManager not found")
		return
	
	var nakama_id = network_manager.get_nakama_user_id()
	if nakama_id.is_empty():
		set_status("⚠️ Connect to Nakama first")
		return
	
	# Generate token using utility
	var token = LiveKitUtils.generate_token(nakama_id, "test-room")
	token_entry.text = token
	set_status("✅ Token generated for: " + nakama_id)


func _on_update_name_pressed():
	var new_name = username_entry.text.strip_edges()
	if not new_name.is_empty():
		local_username = new_name
		username_changed.emit(new_name)





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
	# Ensure URL is correct
	if server_entry.text.is_empty():
		server_entry.text = "ws://localhost:7880"
	
	_on_connect_pressed()


func get_username() -> String:
	return local_username
