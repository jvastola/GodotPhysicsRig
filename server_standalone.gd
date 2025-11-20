extends SceneTree

# Headless matchmaking server entrypoint for Godot 4.x
# - This script extends SceneTree and creates a ServerNode
# - All logic runs inside ServerNode (a Node) so we can use Node APIs

const ROOM_EXPIRY_TIME = 3600

func _init():
    print("SceneTree init: creating ServerNode...")
    var server = ServerNode.new()
    root.add_child(server)

class ServerNode extends Node:

    var tcp_server: TCPServer = null
    var registered_rooms: Dictionary = {}
    var _last_heartbeat_s: int = 0
    var _is_bound: bool = false
    var _last_bind_try_s: int = 0

    func _ready() -> void:
        print("ServerNode ready: attempting to bind 0.0.0.0:8080")
        tcp_server = TCPServer.new()
        var err = tcp_server.listen(8080, "0.0.0.0")
        if err != OK:
            print("ERROR: TCPServer.listen returned: ", err)
            print("Matchmaking server: will retry binding periodically; check system ports or permission issues")
            _is_bound = false
        else:
            _is_bound = true
            print("Matchmaking server started and listening on 0.0.0.0:8080")
        set_process(true)

    func _process(_delta: float) -> void:
        var now = OS.get_unix_time_from_system()
        if now - _last_heartbeat_s > 10:
            _last_heartbeat_s = now
            print("Matchmaking heartbeat — process is alive. Registered rooms: ", registered_rooms.size())

        # Try rebind if not bound
        if not _is_bound and now - _last_bind_try_s > 10:
            _last_bind_try_s = now
            print("Attempting to bind to 0.0.0.0:8080...")
            tcp_server = TCPServer.new()
            var err = tcp_server.listen(8080, "0.0.0.0")
            if err == OK:
                _is_bound = true
                print("Successfully bound to 0.0.0.0:8080")
            else:
                print("Retry bind failed: ", err)

        if _is_bound and tcp_server and tcp_server.is_connection_available():
            var connection = tcp_server.take_connection()
            if connection:
                _handle_client(connection)

        _cleanup_expired_rooms()

    func _handle_client(connection: StreamPeerTCP) -> void:
        var request = ""
        var max_header_size = 8192 # 8 KB max header size
        var timeout = 2.0 # seconds
        var start_time = OS.get_ticks_msec()
        while true:
            var available = connection.get_available_bytes()
            if available > 0:
                request += connection.get_utf8_string(available)
                # Check for end of HTTP headers
                if request.find("\r\n\r\n") != -1 or request.find("\n\n") != -1:
                    break
                # Protect against runaway header sizes
                if request.length() > max_header_size:
                    _send_response(connection, 400, JSON.stringify({"error": "Bad request"}))
                    connection.disconnect_from_host()
                    return
            # Timeout if headers not received in time
            if (OS.get_ticks_msec() - start_time) > int(timeout * 1000):
                print("Timeout waiting for complete HTTP headers.")
                _send_response(connection, 408, JSON.stringify({"error": "Request timeout"}))
                connection.disconnect_from_host()
                return
            # Yield to allow more data to arrive
            await get_tree().process_frame
        print("Got connection — request preview:", request.substr(0, min(request.length(), 80)))
        if request.begins_with("POST"):
            _handle_register(connection, request)
        elif request.begins_with("GET"):
            _handle_lookup(connection, request)
        elif request.begins_with("DELETE"):
            _handle_unregister(connection, request)
        else:
            if request.length() > 0:
                _send_response(connection, 400, JSON.stringify({"error": "Bad request"}))
        connection.disconnect_from_host()

    func _handle_register(connection: StreamPeerTCP, request: String) -> void:
        var json_start = request.find("{")
        if json_start == -1:
            _send_response(connection, 400, "Invalid request")
            return
        var json_str = request.substr(json_start)
        var json = JSON.new()
        var error = json.parse(json_str)
        if error != OK:
            _send_response(connection, 400, "Invalid JSON")
            return
        var data = json.get_data()
        var room_code = data.get("room_code", "")
        if room_code == "":
            _send_response(connection, 400, "Missing room_code")
            return
        registered_rooms[room_code] = {
            "ip": data.get("ip", ""),
            "port": data.get("port", 0),
            "host_name": data.get("host_name", "Host"),
            "player_count": data.get("player_count", 1),
            "timestamp": OS.get_unix_time_from_system()
        }
        _send_response(connection, 200, JSON.stringify({"success": true, "room_code": room_code}))
        print("Room registered: ", room_code)

    func _handle_lookup(connection: StreamPeerTCP, request: String) -> void:
        var parts = request.split(" ")
        if parts.size() < 2:
            _send_response(connection, 400, "Invalid request")
            return
        var url = parts[1]
        if url == "/rooms":
            var rooms = []
            for code in registered_rooms.keys():
                var room = registered_rooms[code].duplicate()
                room["room_code"] = code
                rooms.append(room)
            _send_response(connection, 200, JSON.stringify(rooms))
            return
        var room_code = url.get_file()
        if registered_rooms.has(room_code):
            _send_response(connection, 200, JSON.stringify(registered_rooms[room_code]))
        else:
            _send_response(connection, 404, JSON.stringify({"error": "Room not found"}))

    func _handle_unregister(connection: StreamPeerTCP, request: String) -> void:
        var parts = request.split(" ")
        if parts.size() < 2:
            _send_response(connection, 400, "Invalid request")
            return
        var url = parts[1]
        var room_code = url.get_file()
        if registered_rooms.has(room_code):
            registered_rooms.erase(room_code)
            _send_response(connection, 200, JSON.stringify({"success": true}))
            print("Room unregistered: ", room_code)
        else:
            _send_response(connection, 404, JSON.stringify({"error": "Room not found"}))

    func _send_response(connection: StreamPeerTCP, status: int, body: String) -> void:
        var status_text = "OK" if status == 200 else ("Not Found" if status == 404 else "Bad Request")
        var response = "HTTP/1.1 " + str(status) + " " + status_text + "\r\n"
        response += "Content-Type: application/json\r\n"
        response += "Content-Length: " + str(body.length()) + "\r\n"
        response += "Access-Control-Allow-Origin: *\r\n"
        response += "\r\n"
        response += body
        connection.put_data(response.to_utf8_buffer())

    func _cleanup_expired_rooms() -> void:
        var current_time = OS.get_unix_time_from_system()
        var expired = []
        for room_code in registered_rooms.keys():
            var room = registered_rooms[room_code]
            if current_time - room["timestamp"] > ROOM_EXPIRY_TIME:
                expired.append(room_code)
        for room_code in expired:
            registered_rooms.erase(room_code)
            print("Room expired: ", room_code)

