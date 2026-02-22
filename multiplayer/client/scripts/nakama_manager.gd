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
# Default to non-SSL; common development Nakama instances run on 7350 without TLS.
# Set this to true (and port 7443) for production servers with proper certificates.
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
var display_name: String = ""  # Our display name from Nakama account

# Match data
var current_match_id: String = ""
var match_peers: Dictionary = {}  # peer_id -> presence (EXCLUDING self)

# Authentication retry settings
var _auth_retry_count: int = 0
var _auth_max_retries: int = 3
var _auth_retry_delay: float = 1.0

# Op codes for match state (must match across all clients)
enum MatchOpCode {
	PLAYER_TRANSFORM = 1,
	GRAB_OBJECT = 2,
	RELEASE_OBJECT = 3,
	OBJECT_UPDATE = 4,
	VOXEL_PLACE = 5,
	VOXEL_REMOVE = 6,
	VOXEL_BATCH = 8,
	VOICE_DATA = 7,
	AVATAR_DATA = 9,
	SPAWN_OBJECT = 10
}


func _ready() -> void:
	# Load settings from ConfigManager
	if has_node("/root/ConfigManager"):
		var cm = get_node("/root/ConfigManager")
		nakama_host = cm.get_value("nakama_host", nakama_host)
		nakama_port = cm.get_value("nakama_port", nakama_port)
		nakama_server_key = cm.get_value("nakama_server_key", nakama_server_key)
		nakama_use_ssl = cm.get_value("nakama_use_ssl", nakama_use_ssl)
		print("NakamaManager: Settings loaded from ConfigManager")
	# Ensure port/protocol consistency – the default TLS port is 7443
	if nakama_use_ssl and nakama_port == 7350:
		push_warning("NakamaManager: SSL enabled but port is 7350 – switching to 7443 automatically")
		nakama_port = 7443

	# Create HTTP client with timeout
	http_client = HTTPRequest.new()
	http_client.timeout = 10.0  # 10 second timeout
	add_child(http_client)
	http_client.request_completed.connect(_on_http_request_completed)
	
	# Create WebSocket
	socket = WebSocketPeer.new()
	
	# Generate device ID if not exists
	device_id = _get_or_create_device_id()
	print("NakamaManager: Initialized with device ID: ", device_id)
	
	# Create HTTPRequest node for REST API calls
	http_request = HTTPRequest.new()
	http_request.timeout = 10.0  # 10 second timeout
	add_child(http_request)
	http_request.request_completed.connect(_on_match_list_http_completed)
	
	# Wait a moment for network to be ready before any requests
	# This helps avoid connection errors on startup
	await get_tree().create_timer(0.5).timeout
	print("NakamaManager: Network initialization delay complete")


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
	# Guard against duplicate auth attempts
	if is_authenticated:
		print("NakamaManager: Already authenticated, skipping")
		authenticated.emit(session)
		return
	
	# Reset retry count for new authentication attempt
	_auth_retry_count = 0
	
	# Check if HTTP request is busy (HTTPRequest uses get_http_client_status())
	var client_status = http_client.get_http_client_status()
	if client_status != HTTPClient.STATUS_DISCONNECTED and client_status != HTTPClient.STATUS_RESOLVING and client_status != HTTPClient.STATUS_CANT_CONNECT:
		print("NakamaManager: HTTP client busy (status: %d), cancelling previous request" % client_status)
		http_client.cancel_request()
		# Wait a frame before retrying
		await get_tree().process_frame
	
	print("NakamaManager: Authenticating with device ID...")
	print("NakamaManager: Target URL: %s" % _get_nakama_url())
	
	_do_authenticate_request()


## Internal function to perform the actual authentication request
func _do_authenticate_request() -> void:
	var url = _get_nakama_url() + "/v2/account/authenticate/device?create=true"
	var body = JSON.stringify({
		"id": device_id
	})
	
	var headers = [
		"Content-Type: application/json",
		"Authorization: Basic " + Marshalls.utf8_to_base64(nakama_server_key + ":")
	]
	
	print("NakamaManager: Sending auth request to: ", url)
	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		push_error("NakamaManager: Failed to start auth request: ", err)
		authentication_failed.emit("Request failed: " + str(err))


## Connect WebSocket after authentication
func connect_socket() -> void:
	if not is_authenticated:
		push_error("NakamaManager: Must authenticate before connecting socket")
		return
	
	if is_socket_connected:
		print("NakamaManager: Socket already connected")
		return
	
	var ws_url = _get_websocket_url()
	print("NakamaManager: Connecting WebSocket to ", ws_url)
	var err = socket.connect_to_url(ws_url)
	if err != OK:
		push_error("NakamaManager: Failed to initiate WebSocket connection: ", err)
		return
	# Note: mbedtls handshake errors for websockets are logged internally; if they occur
	# the WebSocket will close and _process will eventually emit connection_lost.
	# We could add a timer or callback for failure, but for now the retry logic in auth
	# will diagnose via HTTP error messages.


## Create a new match (Relay by default)
func create_match(is_authoritative: bool = true) -> void:
	if not is_socket_connected:
		push_error("NakamaManager: Socket not connected")
		return
	
	if is_authoritative:
		create_authoritative_match("world_match")
		return

	# Fallback to relay match
	var envelope = {
		"match_create": {}
	}
	_send_socket_message(envelope)
	print("NakamaManager: Creating relay match")


## Create an authoritative match using a server-side module
func create_authoritative_match(module_name: String) -> void:
	if not is_socket_connected:
		push_error("NakamaManager: Socket not connected")
		return
		
	var envelope = {
		"match_create": {
			"name": module_name
		}
	}
	_send_socket_message(envelope)
	print("NakamaManager: Creating authoritative match using module: ", module_name)


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
func list_matches(_min_players: int = 0, _max_players: int = 10, limit: int = 20) -> void:
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
const MAX_PAYLOAD_SIZE_BYTES = 1024 * 1024 # 1MB limit for match data

func send_match_state(op_code: int, data: Variant) -> void:
	if current_match_id.is_empty():
		return
	
	if not is_socket_connected:
		return
	
	var data_base64 = ""
	
	# Optimize: If data is already bytes, skip JSON serialization
	if data is PackedByteArray:
		# SECURE COMPONENT: Check raw payload size
		if data.size() > MAX_PAYLOAD_SIZE_BYTES:
			push_error("NakamaManager: Binary payload too large (", data.size(), " bytes)")
			return
		data_base64 = Marshalls.raw_to_base64(data)
	else:
		# Encode data as JSON then base64 (Nakama protocol requirement)
		var json_data = JSON.stringify(data)
		var data_bytes = json_data.to_utf8_buffer()
		
		# SECURE COMPONENT: Check serialized payload size
		if data_bytes.size() > MAX_PAYLOAD_SIZE_BYTES:
			push_error("NakamaManager: JSON payload too large (", data_bytes.size(), " bytes)")
			return
			
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
	
	# Decode base64 to raw bytes
	var data_bytes = Marshalls.base64_to_raw(data_base64)
	
	var data = null
	
	# Performance optimization: Skip JSON parsing for high-frequency binary opcodes
	# These will be decoded using bytes_to_var() in NetworkManager
	var is_binary_op = (
		op_code == MatchOpCode.PLAYER_TRANSFORM or 
		op_code == MatchOpCode.OBJECT_UPDATE or
		op_code == MatchOpCode.VOICE_DATA
	)
	
	if is_binary_op:
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
	# mirror same protocol/port consistency logic as HTTP
	if nakama_use_ssl and nakama_port == 7350:
		push_warning("NakamaManager: SSL websocket requested on port 7350 – switching to 7443")
		nakama_port = 7443
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
	# Map result codes to human-readable strings
	var result_names = {
		0: "RESULT_SUCCESS",
		1: "RESULT_CHUNKED_BODY_SIZE_MISMATCH",
		2: "RESULT_CANT_CONNECT",
		3: "RESULT_CANT_RESOLVE",
		4: "RESULT_CONNECTION_ERROR",
		5: "RESULT_TLS_HANDSHAKE_ERROR",
		6: "RESULT_NO_RESPONSE",
		7: "RESULT_BODY_SIZE_LIMIT_EXCEEDED",
		8: "RESULT_BODY_DECOMPRESS_FAILED",
		9: "RESULT_REQUEST_FAILED",
		10: "RESULT_DOWNLOAD_FILE_CANT_OPEN",
		11: "RESULT_DOWNLOAD_FILE_WRITE_ERROR",
		12: "RESULT_REDIRECT_LIMIT_REACHED",
		13: "RESULT_TIMEOUT"
	}
	var result_name = result_names.get(result, "UNKNOWN")
	
	if result != HTTPRequest.RESULT_SUCCESS:
		print("NakamaManager: HTTP request failed: %d (%s) to %s" % [result, result_name, _get_nakama_url()])
		
		# special-case TLS handshake failure when user accidentally tried SSL on a non‑TLS port
		if result == HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			if nakama_use_ssl:
				push_warning("NakamaManager: TLS handshake failed, disabling SSL and retrying using http")
				nakama_use_ssl = false
				# adjust default port if still the common 7350
				if nakama_port == 7443:
					nakama_port = 7350
				_auth_retry_count = 0
				_do_authenticate_request()
				return
		
		# Retry logic for other connection errors
		if _auth_retry_count < _auth_max_retries:
			_auth_retry_count += 1
			print("NakamaManager: Retrying authentication (%d/%d) in %.1fs..." % [_auth_retry_count, _auth_max_retries, _auth_retry_delay])
			await get_tree().create_timer(_auth_retry_delay).timeout
			_do_authenticate_request()
			return
		
		push_error("NakamaManager: Authentication failed after %d retries" % _auth_max_retries)
		_auth_retry_count = 0
		authentication_failed.emit("Connection failed: " + result_name)
		return
	
	# Reset retry count on success
	_auth_retry_count = 0
	
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
		
		# SECURE COMPONENT: Redact token in logs
		var redacted_token = session.token.substr(0, 4) + "..." + session.token.substr(session.token.length() - 4)
		print("NakamaManager: Token: ", redacted_token)
		
		# Fetch account info to get display_name
		_fetch_account()
		
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


func _on_match_list_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
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


# ============================================================================
# Account / Display Name
# ============================================================================

## Fetch account info from Nakama to get display_name
func _fetch_account() -> void:
	if not is_authenticated or not session:
		return
	
	var account_http = HTTPRequest.new()
	account_http.timeout = 10.0
	add_child(account_http)
	account_http.request_completed.connect(_on_account_fetched.bind(account_http))
	
	var url = _get_nakama_url() + "/v2/account"
	var headers = [
		"Authorization: Bearer " + session.token
	]
	
	var err = account_http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		push_error("NakamaManager: Failed to fetch account: ", err)
		account_http.queue_free()


func _on_account_fetched(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http_node: HTTPRequest) -> void:
	http_node.queue_free()
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("NakamaManager: Could not fetch account (result: %d, code: %d)" % [result, response_code])
		return
	
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return
	
	var data = json.get_data()
	var user = data.get("user", {})
	var fetched_name = user.get("display_name", "")
	if not fetched_name.is_empty():
		display_name = fetched_name
		print("NakamaManager: Display name from account: ", display_name)
	else:
		print("NakamaManager: No display name set in account")


## Update display name on Nakama (persists across sessions)
func update_display_name(new_name: String) -> void:
	if not is_authenticated or not session:
		push_warning("NakamaManager: Cannot update display name - not authenticated")
		return
	
	display_name = new_name
	
	var update_http = HTTPRequest.new()
	update_http.timeout = 10.0
	add_child(update_http)
	update_http.request_completed.connect(_on_display_name_updated.bind(update_http))
	
	var url = _get_nakama_url() + "/v2/account"
	var body_json = JSON.stringify({
		"display_name": new_name
	})
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + session.token
	]
	
	var err = update_http.request(url, headers, HTTPClient.METHOD_PUT, body_json)
	if err != OK:
		push_error("NakamaManager: Failed to update display name: ", err)
		update_http.queue_free()


func _on_display_name_updated(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray, http_node: HTTPRequest) -> void:
	http_node.queue_free()
	
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		print("NakamaManager: Display name updated to: ", display_name)
	else:
		push_warning("NakamaManager: Failed to update display name (result: %d, code: %d)" % [result, response_code])
