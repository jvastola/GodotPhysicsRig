extends Node
## NakamaManager - Complete Nakama integration with WebSocket support
## Singleton autoload for scalable multiplayer (10k+ concurrent users)

signal authenticated(session)
signal authentication_failed(error)
signal match_created(match_id, match_label)
signal match_joined(match_id)
signal match_left()
signal match_error(error)
signal match_presence(joins, leaves)
signal match_state_received(peer_id, op_code, data)
signal connection_lost()
signal connection_restored()

# Nakama connection settings
var nakama_host: String = "localhost"
var nakama_port: int = 7350
var nakama_server_key: String = "defaultkey"
var nakama_use_ssl: bool = false

# HTTP client for REST API
var http_client: HTTPRequest

# WebSocket for real-time connection
var socket: WebSocketPeer
var is_socket_connected: bool = false

# Session data
var session: Dictionary = {}
var is_authenticated: bool = false
var device_id: String = ""
var local_user_id: String = ""  # Our own user ID from Nakama

# Match data
var current_match_id: String = ""
var match_peers: Dictionary = {}  # peer_id -> presence (EXCLUDING self)

# Op codes for match state (must match across all clients)
enum MatchOpCode {
	PLAYER_TRANSFORM = 1,
	GRABBABLE_GRAB = 2,
	GRABBABLE_RELEASE = 3,
	GRABBABLE_UPDATE = 4,
	VOXEL_PLACE = 5,
	VOXEL_REMOVE = 6,
	VOICE_DATA = 7
}


func _ready() -> void:
	# Create HTTP client
	http_client = HTTPRequest.new()
	add_child(http_client)
	http_client.request_completed.connect(_on_http_request_completed)
	
	# Create WebSocket
	socket = WebSocketPeer.new()
	
	# Generate device ID if not exists
	device_id = _get_or_create_device_id()
	print("NakamaManager: Initialized with device ID: ", device_id)


func _process(_delta: float) -> void:
	# Poll WebSocket
	if socket and socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		socket.poll()
		
		var state = socket.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			if not is_socket_connected:
				is_socket_connected = true
				print("NakamaManager: WebSocket connected!")
				connection_restored.emit()
			
			# Process incoming packets
			while socket.get_available_packet_count() > 0:
				var packet = socket.get_packet()
				_process_socket_message(packet)
		
		elif state == WebSocketPeer.STATE_CLOSING:
			pass
			
		elif state == WebSocketPeer.STATE_CLOSED:
			if is_socket_connected:
				is_socket_connected = false
				print("NakamaManager: WebSocket disconnected! Code: ", socket.get_close_code())
				connection_lost.emit()


func _get_or_create_device_id() -> String:
	# For local multi-instance testing: use process ID + timestamp to ensure uniqueness
	# Each game instance gets its own ID, even on the same machine
	var base_id = OS.get_unique_id()
	if base_id.is_empty():
		base_id = "DEVICE"
	
	# Use process ID to make each instance truly unique
	var process_id = OS.get_process_id()
	var timestamp = Time.get_ticks_msec()
	var unique_id = base_id + "_" + str(process_id) + "_" + str(timestamp % 10000)
	
	return unique_id


## Authenticate with Nakama using device ID
func authenticate_device() -> void:
	print("NakamaManager: Authenticating with device ID...")
	
	var url = _get_nakama_url() + "/v2/account/authenticate/device?create=true"
	var body = JSON.stringify({
		"id": device_id
	})
	
	var headers = [
		"Content-Type: application/json",
		"Authorization: Basic " + Marshalls.utf8_to_base64(nakama_server_key + ":")
	]
	
	http_client.request(url, headers, HTTPClient.METHOD_POST, body)


## Connect WebSocket after authentication
func connect_socket() -> void:
	if not is_authenticated:
		push_error("NakamaManager: Must authenticate before connecting socket")
		return
	
	if is_socket_connected:
		print("NakamaManager: Socket already connected")
		return
	
	var ws_url = _get_websocket_url()
	var err = socket.connect_to_url(ws_url)
	
	if err != OK:
		push_error("NakamaManager: Failed to connect WebSocket: ", err)
		return
	
	print("NakamaManager: Connecting WebSocket to ", ws_url)


## Create a new match
func create_match() -> void:
	if not is_socket_connected:
		push_error("NakamaManager: Socket not connected")
		return
	
	var match_label = _generate_room_code()
	
	# Send match create request via WebSocket
	var envelope = {
		"match_create": {}
	}
	_send_socket_message(envelope)
	
	# Store for when we receive the response
	current_match_id = match_label
	print("NakamaManager: Creating match with label: ", match_label)


## Join a match by ID
func join_match(match_id: String) -> void:
	if not is_socket_connected:
		push_error("NakamaManager: Socket not connected")
		return
	
	var envelope = {
		"match_join": {
			"match_id": match_id
		}
	}
	_send_socket_message(envelope)
	print("NakamaManager: Joining match: ", match_id)


## Leave current match
func leave_match() -> void:
	if current_match_id.is_empty():
		return
	
	if is_socket_connected:
		var envelope = {
			"match_leave": {
				"match_id": current_match_id
			}
		}
		_send_socket_message(envelope)
	
	current_match_id = ""
	match_peers.clear()
	match_left.emit()
	print("NakamaManager: Left match")


## Send match state to other players
func send_match_state(op_code: int, data: Dictionary) -> void:
	if current_match_id.is_empty():
		return
	
	if not is_socket_connected:
		return
	
	# Encode data as JSON then base64 (Nakama protocol requirement)
	var json_data = JSON.stringify(data)
	var data_bytes = json_data.to_utf8_buffer()
	var data_base64 = Marshalls.raw_to_base64(data_bytes)
	
	var envelope = {
		"match_data_send": {
			"match_id": current_match_id,
			"op_code": op_code,
			"data": data_base64
		}
	}
	_send_socket_message(envelope)


func _send_socket_message(envelope: Dictionary) -> void:
	var json = JSON.stringify(envelope)
	socket.send_text(json)


func _process_socket_message(packet: PackedByteArray) -> void:
	var json_str = packet.get_string_from_utf8()
	var json = JSON.new()
	var error = json.parse(json_str)
	
	if error != OK:
		push_error("NakamaManager: Failed to parse socket message")
		return
	
	var data = json.get_data()
	
	# Handle different message types
	if data.has("match"):
		_handle_match_created(data.match)
	elif data.has("match_presence_event"):
		_handle_match_presence(data.match_presence_event)
	elif data.has("match_data"):
		_handle_match_data(data.match_data)
	elif data.has("error"):
		push_error("NakamaManager: Server error: ", data.error)
		match_error.emit(data.error)


func _handle_match_created(match_data: Dictionary) -> void:
	current_match_id = match_data.get("match_id", "")
	var label = match_data.get("label", current_match_id)
	
	# Get all existing players in the match (for when we join an existing match)
	var presences = match_data.get("presences", [])
	
	# Add all existing players to match_peers (excluding ourselves)
	for presence in presences:
		var user_id = presence.get("user_id", "")
		if user_id != local_user_id and not user_id.is_empty():
			match_peers[user_id] = presence
	
	print("NakamaManager: Match created/joined: ", current_match_id, " (", presences.size(), " players)")
	match_created.emit(current_match_id, label)
	match_joined.emit(current_match_id)


func _handle_match_presence(presence_data: Dictionary) -> void:
	var joins = presence_data.get("joins", [])
	var leaves = presence_data.get("leaves", [])
	
	# Update match_peers (exclude ourselves)
	for join in joins:
		var user_id = join.get("user_id", "")
		
		# Set local_user_id if we don't have it yet (this is us joining)
		if local_user_id.is_empty():
			local_user_id = user_id
			# Remove ourselves from match_peers if we were added during match join
			if match_peers.has(user_id):
				match_peers.erase(user_id)
		elif user_id != local_user_id:
			match_peers[user_id] = join
			print("NakamaManager: Player joined: ", user_id)
	
	for leave in leaves:
		var user_id = leave.get("user_id", "")
		if user_id != local_user_id:
			match_peers.erase(user_id)
			print("NakamaManager: Player left: ", user_id)
	
	match_presence.emit(joins, leaves)


func _handle_match_data(match_data_msg: Dictionary) -> void:
	var op_code = match_data_msg.get("op_code", 0)
	var data_base64 = match_data_msg.get("data", "")
	var sender_id = match_data_msg.get("presence", {}).get("user_id", "")
	
	# Decode base64 then parse JSON
	var data_bytes = Marshalls.base64_to_raw(data_base64)
	var data_str = data_bytes.get_string_from_utf8()
	
	var json = JSON.new()
	var error = json.parse(data_str)
	
	if error != OK:
		push_error("NakamaManager: Failed to parse match data")
		return
	
	var data = json.get_data()
	match_state_received.emit(sender_id, op_code, data)


func _get_nakama_url() -> String:
	var protocol = "https" if nakama_use_ssl else "http"
	return "%s://%s:%d" % [protocol, nakama_host, nakama_port]


func _get_websocket_url() -> String:
	var protocol = "wss" if nakama_use_ssl else "ws"
	var token = session.get("token", "")
	return "%s://%s:%d/ws?token=%s" % [protocol, nakama_host, nakama_port, token]


func _generate_room_code() -> String:
	const CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code = ""
	for i in range(6):
		code += CHARS[randi() % CHARS.length()]
	return code


func _on_http_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("NakamaManager: HTTP request failed: ", result)
		authentication_failed.emit("Connection failed")
		return
	
	if response_code != 200:
		push_error("NakamaManager: HTTP error: ", response_code)
		authentication_failed.emit("HTTP error: " + str(response_code))
		return
	
	var json = JSON.new()
	var error = json.parse(body.get_string_from_utf8())
	
	if error != OK:
		push_error("NakamaManager: Failed to parse response")
		authentication_failed.emit("Parse error")
		return
	
	var data = json.get_data()
	
	# Handle authentication response
	if data.has("token"):
		session = data
		is_authenticated = true
		local_user_id = data.get("user_id", "")  # May be empty, will get from presence
		print("NakamaManager: Authentication successful!")
		print("NakamaManager: Token: ", session.token.substr(0, 20), "...")
		authenticated.emit(session)
		
		# Auto-connect WebSocket after authentication
		connect_socket()
	else:
		push_error("NakamaManager: Unexpected response format")
		authentication_failed.emit("Invalid response")
