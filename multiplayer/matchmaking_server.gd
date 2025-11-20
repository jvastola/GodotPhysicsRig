extends Node
## MatchmakingServer - Simple HTTP-based matchmaking for room codes
## This can run as a standalone Godot headless server or use external HTTP API

const DEFAULT_MATCHMAKING_URL = "http://localhost:8080"
const ROOM_EXPIRY_TIME = 3600 # 1 hour

var matchmaking_url: String = DEFAULT_MATCHMAKING_URL
var http_request: HTTPRequest = null

signal room_registered(success: bool, room_code: String)
signal room_found(success: bool, room_data: Dictionary)
signal rooms_listed(rooms: Array)

# For hosting a local matchmaking server
var tcp_server: TCPServer = null
var is_server_mode: bool = false
var registered_rooms: Dictionary = {} # room_code -> {ip, port, host_name, player_count, timestamp}


func _ready() -> void:
	# Create HTTP request node
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_http_request_completed)


## Register a room with the matchmaking server
func register_room(room_code: String, ip: String, port: int, host_name: String) -> void:
	if is_server_mode:
		# Local server mode
		_register_room_local(room_code, ip, port, host_name)
		return
	
	# Remote server mode - send HTTP request
	var json = JSON.stringify({
		"action": "register",
		"room_code": room_code,
		"ip": ip,
		"port": port,
		"host_name": host_name,
		"timestamp": Time.get_unix_time_from_system()
	})
	
	var headers = ["Content-Type: application/json"]
	http_request.request(matchmaking_url + "/room", headers, HTTPClient.METHOD_POST, json)
	print("MatchmakingServer: Registering room ", room_code)


## Lookup a room by code
func lookup_room(room_code: String) -> void:
	if is_server_mode:
		# Local server mode
		_lookup_room_local(room_code)
		return
	
	# Remote server mode - send HTTP request
	var url = matchmaking_url + "/room/" + room_code
	http_request.request(url, [], HTTPClient.METHOD_GET)
	print("MatchmakingServer: Looking up room ", room_code)


## List all active rooms
func list_rooms() -> void:
	if is_server_mode:
		# Local server mode
		_list_rooms_local()
		return
	
	# Remote server mode - send HTTP request
	var url = matchmaking_url + "/rooms"
	http_request.request(url, [], HTTPClient.METHOD_GET)
	print("MatchmakingServer: Listing all rooms")


## Unregister a room (when host disconnects)
func unregister_room(room_code: String) -> void:
	if is_server_mode:
		# Local server mode
		if registered_rooms.has(room_code):
			registered_rooms.erase(room_code)
		return
	
	# Remote server mode - send HTTP request
	var url = matchmaking_url + "/room/" + room_code
	http_request.request(url, [], HTTPClient.METHOD_DELETE)
	print("MatchmakingServer: Unregistering room ", room_code)


## Start local matchmaking server (for development/LAN)
## 
## Parameters:
##   port (int): The port to listen on. Default is 8080.
##   bind_address (String): The address to bind the server to. Default is "0.0.0.0".
## 
## Returns:
##   Error: OK on success, or error code on failure.
func start_local_server(port: int = 8080, bind_address: String = "0.0.0.0") -> Error:
	tcp_server = TCPServer.new()
	var error = tcp_server.listen(port, bind_address)
	if error != OK:
		push_error("MatchmakingServer: Failed to start server on port ", port, " and address ", bind_address)
		return error
	is_server_mode = true
	print("MatchmakingServer: Local server started on port ", port, " and address ", bind_address)
	return OK


func _process(_delta: float) -> void:
	if is_server_mode and tcp_server:
		_process_server()
	
	# Clean up expired rooms
	if is_server_mode:
		_cleanup_expired_rooms()


func _process_server() -> void:
	if not tcp_server:
		return
	
	# Accept new connections
	if tcp_server.is_connection_available():
		var connection = tcp_server.take_connection()
		if connection:
			_handle_client_connection(connection)


func _handle_client_connection(connection: StreamPeerTCP) -> void:
	# Simple HTTP request handling
	var request = connection.get_utf8_string(connection.get_available_bytes())
	
	if request.begins_with("POST"):
		_handle_register_request(connection, request)
	elif request.begins_with("GET"):
		_handle_lookup_request(connection, request)
	elif request.begins_with("DELETE"):
		_handle_unregister_request(connection, request)
	
	connection.disconnect_from_host()


func _handle_register_request(connection: StreamPeerTCP, request: String) -> void:
	# Parse JSON from request body
	var json_start = request.find("{")
	if json_start == -1:
		_send_http_response(connection, 400, "Invalid request")
		return
	
	var json_str = request.substr(json_start)
	var json = JSON.new()
	var error = json.parse(json_str)
	
	if error != OK:
		_send_http_response(connection, 400, "Invalid JSON")
		return
	
	var data = json.get_data()
	var room_code = data.get("room_code", "")
	
	_register_room_local(room_code, data.get("ip", ""), data.get("port", 0), data.get("host_name", "Host"))
	_send_http_response(connection, 200, JSON.stringify({"success": true, "room_code": room_code}))


func _handle_lookup_request(connection: StreamPeerTCP, request: String) -> void:
	# Extract room code from URL
	var parts = request.split(" ")
	if parts.size() < 2:
		_send_http_response(connection, 400, "Invalid request")
		return
	
	var url = parts[1]
	var room_code = url.get_file()
	
	if registered_rooms.has(room_code):
		var room_data = registered_rooms[room_code]
		_send_http_response(connection, 200, JSON.stringify(room_data))
	else:
		_send_http_response(connection, 404, JSON.stringify({"error": "Room not found"}))


func _handle_unregister_request(connection: StreamPeerTCP, request: String) -> void:
	# Extract room code from URL
	var parts = request.split(" ")
	if parts.size() < 2:
		_send_http_response(connection, 400, "Invalid request")
		return
	
	var url = parts[1]
	var room_code = url.get_file()
	
	if registered_rooms.has(room_code):
		registered_rooms.erase(room_code)
		_send_http_response(connection, 200, JSON.stringify({"success": true}))
	else:
		_send_http_response(connection, 404, JSON.stringify({"error": "Room not found"}))


func _send_http_response(connection: StreamPeerTCP, status: int, body: String) -> void:
	var status_text = "OK" if status == 200 else ("Not Found" if status == 404 else "Bad Request")
	var response = "HTTP/1.1 " + str(status) + " " + status_text + "\r\n"
	response += "Content-Type: application/json\r\n"
	response += "Content-Length: " + str(body.length()) + "\r\n"
	response += "Access-Control-Allow-Origin: *\r\n"
	response += "\r\n"
	response += body
	
	connection.put_data(response.to_utf8_buffer())


func _register_room_local(room_code: String, ip: String, port: int, host_name: String) -> void:
	registered_rooms[room_code] = {
		"ip": ip,
		"port": port,
		"host_name": host_name,
		"player_count": 1,
		"timestamp": Time.get_unix_time_from_system()
	}
	room_registered.emit(true, room_code)
	print("MatchmakingServer: Room ", room_code, " registered locally")


func _lookup_room_local(room_code: String) -> void:
	if registered_rooms.has(room_code):
		room_found.emit(true, registered_rooms[room_code])
	else:
		room_found.emit(false, {})


func _list_rooms_local() -> void:
	var rooms = []
	for code in registered_rooms.keys():
		var room = registered_rooms[code].duplicate()
		room["room_code"] = code
		rooms.append(room)
	rooms_listed.emit(rooms)


func _cleanup_expired_rooms() -> void:
	var current_time = Time.get_unix_time_from_system()
	var expired_rooms = []
	
	for room_code in registered_rooms.keys():
		var room = registered_rooms[room_code]
		if current_time - room["timestamp"] > ROOM_EXPIRY_TIME:
			expired_rooms.append(room_code)
	
	for room_code in expired_rooms:
		registered_rooms.erase(room_code)
		if expired_rooms.size() > 0:
			print("MatchmakingServer: Cleaned up ", expired_rooms.size(), " expired rooms")


func _on_http_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("MatchmakingServer: HTTP request failed: ", result)
		return
	
	var json = JSON.new()
	var error = json.parse(body.get_string_from_utf8())
	
	if error != OK:
		push_error("MatchmakingServer: Failed to parse response JSON")
		return
	
	var data = json.get_data()
	
	# Determine which signal to emit based on response
	if data.has("room_code") and data.has("ip"):
		room_found.emit(true, data)
	elif data.is_array():
		rooms_listed.emit(data)
	elif data.has("success"):
		room_registered.emit(data["success"], data.get("room_code", ""))
