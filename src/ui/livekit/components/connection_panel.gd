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
@onready var sandbox_http_request: HTTPRequest = $SandboxHTTPRequest

# State
var local_username: String = "User-" + str(randi() % 10000)
var is_connected: bool = false


func _ready():
	_setup_ui()
	_set_defaults()


func _setup_ui():
	connect_button.pressed.connect(_on_connect_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)
	auto_connect_button.pressed.connect(_on_auto_connect_pressed)
	generate_token_button.pressed.connect(_on_generate_token_pressed)
	update_name_button.pressed.connect(_on_update_name_pressed)
	sandbox_http_request.request_completed.connect(_on_sandbox_request_completed)
	
	username_entry.text = local_username
	disconnect_button.disabled = true


func _set_defaults():
	server_entry.text = "ws://localhost:7880"
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


func _on_sandbox_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	auto_connect_button.disabled = false
	
	if result != HTTPRequest.RESULT_SUCCESS:
		set_status("❌ Request Failed")
		connect_button.disabled = false
		return
	
	if response_code != 200:
		set_status("❌ API Error: " + str(response_code))
		connect_button.disabled = false
		return
	
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json:
		var server_url = json.get("serverUrl", "")
		var token = json.get("participantToken", "")
		
		if server_url and token:
			server_entry.text = server_url
			token_entry.text = token
			print("✅ Received Sandbox Token")
			_on_connect_pressed()
		else:
			set_status("❌ Invalid Response")
	else:
		set_status("❌ JSON Parse Error")
		connect_button.disabled = false


# Public API
func set_status(text: String):
	# Status is shown externally by the coordinator
	print("ConnectionPanel: ", text)


func set_connected(connected: bool, room_name: String = ""):
	is_connected = connected
	connect_button.disabled = connected
	disconnect_button.disabled = not connected
	
	if connected:
		room_info_label.text = "🎙️ Room: " + room_name if not room_name.is_empty() else "🎙️ Connected"
	else:
		room_info_label.text = "Room: Not connected"


func request_sandbox_token(nakama_id: String, room_name: String = "godot-demo2"):
	"""Request token from LiveKit Cloud sandbox"""
	set_status("⏳ Fetching Sandbox Token...")
	connect_button.disabled = true
	auto_connect_button.disabled = true
	
	var url = "https://cloud-api.livekit.io/api/sandbox/connection-details"
	var headers = [
		"X-Sandbox-ID: conference-pkdo9w",
		"Content-Type: application/json"
	]
	var body = JSON.stringify({
		"room_name": room_name,
		"participant_name": nakama_id
	})
	
	var error = sandbox_http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		set_status("❌ HTTP Request Failed")
		connect_button.disabled = false
		auto_connect_button.disabled = false


func get_username() -> String:
	return local_username
