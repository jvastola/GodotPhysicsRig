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
signal match_list_received(matches)

# Nakama connection settings
var nakama_host: String = "158.101.21.99"  # Oracle Cloud server
var nakama_port: int = 7350
var nakama_server_key: String = "defaultkey"
var nakama_use_ssl: bool = false

# HTTP client for REST API
# HTTP client for REST API (for authentication)
var http_client: HTTPRequest

# WebSocket for real-time connection
var socket: WebSocketPeer
var is_socket_connected: bool = false

# HTTPRequest for REST API calls like match listing
var http_request: HTTPRequest = null

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
	GRAB_OBJECT = 2,
	RELEASE_OBJECT = 3,
	OBJECT_UPDATE = 4,
	VOXEL_PLACE = 5,
	VOXEL_REMOVE = 6,
	VOXEL_BATCH = 7,
	VOICE_DATA = 8,
	AVATAR_DATA = 9
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
	
	# Create HTTPRequest node for REST API calls
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_match_list_http_completed)


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
	
	# DON'T set current_match_id here - wait for server response
	# This prevents the race condition where join_match guard clause fails
	# The ID will be set in _handle_match_created when we get the actual match ID
	print("NakamaManager: Creating match with label: ", match_label)


## Join a match by ID
func join_match(match_id: String) -> void:
	print("NakamaManager: join_match called with: '", match_id, "' (length: ", match_id.length(), ")")
	
	# Guard: If we're already in this match, don't join again
	# This prevents redundant join calls on Android when creating a match
	if current_match_id == match_id:
		print("NakamaManager: Already in match ", match_id, " - skipping redundant join")
		return
	
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


## List available matches
func list_matches(min_players: int = 0, max_players: int = 10, limit: int = 20) -> void:
	"""Request list of available matches from Nakama using HTTP REST API"""
	if not is_authenticated or not session:
		push_error("NakamaManager: Cannot list matches - not authenticated")
		match_list_received.emit([])
		return
	
	# Safety: Cancel any pending HTTP request to prevent concurrent requests
	# This prevents crashes on Android when refresh is called multiple times quickly
	if http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		print("NakamaManager: Cancelling pending HTTP request")
		http_request.cancel_request()
	
	# Build URL - don't filter by min/max size to see all matches including empty ones
	var url = "http://" + nakama_host + ":" + str(nakama_port) + "/v2/match"
	var query = "?limit=" + str(limit)
	# NOTE: Removed authoritative filter and size filters to see ALL matches
	
	url += query
	
	var headers = [
		"Authorization: Bearer " + session.token
	]
	
	print("NakamaManager: Requesting match list from: ", url)
	var error = http_request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		push_error("NakamaManager: HTTP request failed: ", error)
		match_list_received.emit([])



## Send match state to other players
func send_match_state(op_code: int, data: Variant) -> void:
	if current_match_id.is_empty():
		return
	
	if not is_socket_connected:
		return
	
	var data_base64 = ""
	
	# Optimize: If data is already bytes, skip JSON serialization
	if data is PackedByteArray:
		data_base64 = Marshalls.raw_to_base64(data)
	else:
		# Encode data as JSON then base64 (Nakama protocol requirement)
		var json_data = JSON.stringify(data)
		var data_bytes = json_data.to_utf8_buffer()
		data_base64 = Marshalls.raw_to_base64(data_bytes)
	
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
	elif data.has("matches"):
		_handle_match_list(data)
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
	
	# IMPORTANT: Set local_user_id FIRST before processing any joins
	# This prevents us from adding ourselves to match_peers
	for join in joins:
		var user_id = join.get("user_id", "")
		if local_user_id.is_empty():
			# This is us joining - set our ID immediately
			local_user_id = user_id
			print("NakamaManager: Set local user ID: ", local_user_id)
			break  # Exit early since we found ourselves
	
	# Now update match_peers (exclude ourselves)
	for join in joins:
		var user_id = join.get("user_id", "")
		if user_id != local_user_id and not user_id.is_empty():
			match_peers[user_id] = join
			print("NakamaManager: Player joined: ", user_id)
	
	for leave in leaves:
		var user_id = leave.get("user_id", "")
		if user_id != local_user_id:
			match_peers.erase(user_id)
			print("NakamaManager: Player left: ", user_id)
	
	match_presence.emit(joins, leaves)


func _handle_match_list(list_data: Dictionary) -> void:
	"""Handle match list response from server"""
	var matches = list_data.get("matches", [])
	print("NakamaManager: Received ", matches.size(), " available matches")
	match_list_received.emit(matches)


func _handle_match_data(match_data_msg: Dictionary) -> void:
	var op_code = int(match_data_msg.get("op_code", 0))
	var data_base64 = match_data_msg.get("data", "")
	var sender_id = match_data_msg.get("presence", {}).get("user_id", "")
	
	# Decode base64 then parse JSON
	# Decode base64 to raw bytes
	var data_bytes = Marshalls.base64_to_raw(data_base64)
	
	var data = null
	
	# For voice data, we want the raw bytes (it's already compressed audio)
	if op_code == MatchOpCode.VOICE_DATA:
		data = data_bytes
	else:
		# For other op codes, parse as JSON
		var data_str = data_bytes.get_string_from_utf8()
		var json = JSON.new()
		var error = json.parse(data_str)
		
		if error == OK:
			data = json.get_data()
		else:
			push_warning("NakamaManager: Failed to parse match data as JSON for op_code " + str(op_code))
			# Fallback to raw bytes if JSON parse fails
			data = data_bytes
	
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
		
		# Try to get user ID from response, otherwise parse token
		local_user_id = data.get("user_id", "")
		if local_user_id.is_empty():
			local_user_id = _extract_user_id_from_token(session.token)
			
		print("NakamaManager: Authentication successful!")
		print("NakamaManager: User ID: ", local_user_id)
		print("NakamaManager: Token: ", session.token.substr(0, 20), "...")
		authenticated.emit(session)
		
		# Auto-connect WebSocket after authentication
		connect_socket()
	else:
		push_error("NakamaManager: Unexpected response format")
		authentication_failed.emit("Invalid response")


func _extract_user_id_from_token(token: String) -> String:
	var parts = token.split(".")
	if parts.size() < 2:
		return ""
	
	var payload_str = parts[1]
	# Add padding if needed
	match (payload_str.length() % 4):
		2: payload_str += "=="
		3: payload_str += "="
	
	# Replace URL-safe chars
	payload_str = payload_str.replace("-", "+").replace("_", "/")
	
	var payload_bytes = Marshalls.base64_to_raw(payload_str)
	var json = JSON.new()
	if json.parse(payload_bytes.get_string_from_utf8()) == OK:
		var payload = json.get_data()
		# Nakama uses 'uid' or 'sub' for user ID
		if payload.has("uid"):
			return payload.uid
		elif payload.has("sub"):
			return payload.sub
			
	return ""


func _on_match_list_http_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	"""Handle HTTP response from Nakama REST API (match list)"""
	print("NakamaManager: HTTP response - result: ", result, ", code: ", response_code)
	
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("NakamaManager: HTTP request failed with result: ", result)
		match_list_received.emit([])
		return
	
	if response_code != 200:
		push_error("NakamaManager: HTTP request returned code: ", response_code)
		var body_str = body.get_string_from_utf8()
		print("NakamaManager: Response body: ", body_str)
		match_list_received.emit([])
		return
	
	var json_str = body.get_string_from_utf8()
	print("NakamaManager: Raw response: ", json_str)
	
	var json = JSON.new()
	var parse_error = json.parse(json_str)
	
	if parse_error != OK:
		push_error("NakamaManager: Failed to parse HTTP response")
		match_list_received.emit([])
		return
	
	var data = json.get_data()
	var matches = data.get("matches", [])
	
	print("NakamaManager: Received ", matches.size(), " matches via HTTP")
	if matches.size() > 0:
		print("NakamaManager: First match: ", matches[0])
	match_list_received.emit(matches)
