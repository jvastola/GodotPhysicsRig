extends Node
## NetworkManager - Handles all network connections and player management
## Singleton autoload that manages ENet connections, player spawning, and network events

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed()
signal connection_succeeded()
signal server_disconnected()
signal send_local_avatar()

# Nakama integration (scalable relay networking)
var use_nakama: bool = false  # Set to true to use Nakama instead of P2P

const DEFAULT_PORT = 7777
const MAX_CLIENTS = 8

# Room code system (legacy - now handled by Nakama match labels)
var current_room_code: String = ""
var room_code_to_ip: Dictionary = {} # room_code -> {ip, port, host_name, player_count, created_time}
signal room_code_generated(code: String)



var peer: ENetMultiplayerPeer = null
var players: Dictionary = {} # peer_id -> player_info Dictionary
var local_player: Node3D = null

# Player info structure
var local_player_info: Dictionary = {
	"name": "Player",
	"head_position": Vector3.ZERO,
	"head_rotation": Vector3.ZERO,
	"left_hand_position": Vector3.ZERO,
	"left_hand_rotation": Vector3.ZERO,
	"right_hand_position": Vector3.ZERO,
	"right_hand_rotation": Vector3.ZERO,
	"player_scale": Vector3.ONE,
	"avatar_texture_data": PackedByteArray()
}

# Grabbable sync
var grabbed_objects: Dictionary = {} # object_id -> {owner_peer_id, position, rotation, is_grabbed}
signal grabbable_grabbed(object_id: String, peer_id: int)
signal grabbable_released(object_id: String, peer_id: int)
signal grabbable_sync_update(object_id: String, data: Dictionary)

# Avatar signals
signal avatar_texture_received(peer_id: int)

# Voxel sync signals
signal voxel_placed_network(world_pos: Vector3, color: Color)
signal voxel_removed_network(world_pos: Vector3)

# Voice chat - HANDLED BY LIVEKIT (see PlayerVoiceComponent)
# These variables kept for API compatibility but not used
var voice_enabled: bool = false

# Connection quality monitoring
enum ConnectionQuality {
	EXCELLENT,  # < 50ms ping
	GOOD,       # 50-100ms ping
	FAIR,       # 100-200ms ping
	POOR        # > 200ms ping
}

var network_stats: Dictionary = {
	"ping_ms": 0.0,
	"bandwidth_up": 0.0,  # KB/s
	"bandwidth_down": 0.0,  # KB/s
	"packet_loss": 0.0,  # percentage
	"connection_quality": ConnectionQuality.GOOD
}

var peer_stats: Dictionary = {}  # peer_id -> stats Dictionary
var _ping_check_interval: float = 1.0  # Check ping every second
var _last_bytes_sent: int = 0
var _last_bytes_received: int = 0
var _monitor_timer: Timer = null
var _metrics := {
	"connect_attempts": 0,
	"connect_successes": 0,
	"connect_failures": 0,
	"last_connect_start_msec": 0,
	"last_connect_latency_ms": 0,
	"disconnects": 0,
	"reconnect_attempts": 0,
	"send_failures": 0,
	"last_send_failure": ""
}

signal connection_quality_changed(quality: ConnectionQuality)
signal network_stats_updated(stats: Dictionary)
signal metrics_updated(metrics: Dictionary)

# Push-to-talk
enum VoiceMode {
	ALWAYS_ON,
	PUSH_TO_TALK,
	VOICE_ACTIVATED
}

var voice_mode: VoiceMode = VoiceMode.PUSH_TO_TALK
var push_to_talk_key: Key = KEY_SPACE
var is_push_to_talk_pressed: bool = false

# Reconnection
var connection_timeout: float = 10.0
var _last_server_response_time: float = 0.0
var _reconnection_attempt: int = 0
const MAX_RECONNECTION_ATTEMPTS = 5
var _last_connection_address: String = ""
var _last_connection_port: int = 0



func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# Initialize network stats monitoring
	_last_server_response_time = Time.get_ticks_msec() / 1000.0
	
	# Setup Nakama signals (deferred to ensure NakamaManager autoload is ready)
	call_deferred("_setup_nakama_integration")
	
	# Connect Nakama signals
	if NakamaManager:
		NakamaManager.match_state_received.connect(_on_nakama_match_state_received)
	
	# Timer-based connection monitoring to avoid per-frame polling
	_monitor_timer = Timer.new()
	_monitor_timer.wait_time = _ping_check_interval
	_monitor_timer.one_shot = false
	_monitor_timer.autostart = false
	add_child(_monitor_timer)
	_monitor_timer.timeout.connect(_on_monitor_timeout)
	set_process(false)
	_update_monitoring_state()


func _setup_nakama_integration() -> void:
	"""Connect to NakamaManager signals"""
	if NakamaManager:
		if not NakamaManager.match_joined.is_connected(_on_nakama_match_joined):
			NakamaManager.match_joined.connect(_on_nakama_match_joined)
		if not NakamaManager.match_left.is_connected(_on_nakama_match_left):
			NakamaManager.match_left.connect(_on_nakama_match_left)
		if not NakamaManager.match_presence.is_connected(_on_nakama_match_presence):
			NakamaManager.match_presence.connect(_on_nakama_match_presence)
		if not NakamaManager.match_state_received.is_connected(_on_nakama_match_state_received):
			NakamaManager.match_state_received.connect(_on_nakama_match_state_received)
		print("NetworkManager: Nakama integration initialized")



## Generate a 6-character room code
func generate_room_code() -> String:
	const CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" # Removed confusing chars (I, O, 0, 1)
	var code = ""
	for i in range(6):
		code += CHARS[randi() % CHARS.length()]
	return code


## Create a server (host) with optional room code
func create_server(port: int = DEFAULT_PORT, use_room_code: bool = true) -> Error:
	_metrics["connect_attempts"] += 1
	_metrics["last_connect_start_msec"] = Time.get_ticks_msec()
	_emit_metrics()
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_CLIENTS)
	
	if error != OK:
		push_error("Failed to create server: " + str(error))
		_metrics["connect_failures"] += 1
		_emit_metrics()
		return error
	
	multiplayer.multiplayer_peer = peer
	print("Server created on port ", port)
	_metrics["connect_successes"] += 1
	_metrics["last_connect_latency_ms"] = 0
	_emit_metrics()
	
	# Generate room code if requested
	if use_room_code:
		current_room_code = generate_room_code()
		# Get local IP
		var local_ip = get_local_ip()
		room_code_to_ip[current_room_code] = {
			"ip": local_ip,
			"port": port,
			"host_name": local_player_info.get("name", "Host"),
			"player_count": 1,
			"created_time": Time.get_unix_time_from_system()
		}
		
		room_code_generated.emit(current_room_code)
		print("Room code: ", current_room_code, " (IP: ", local_ip, ")")
	
	# Host is also a player
	_register_local_player()
	
	return OK


## Get local IP address (for LAN)
func get_local_ip() -> String:
	var addresses = IP.get_local_addresses()
	for addr in addresses:
		# Prefer IPv4 local network addresses
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	# Fallback to first non-localhost address
	for addr in addresses:
		if addr != "127.0.0.1" and not addr.contains(":"):
			return addr
	return "127.0.0.1"


## Get public IP address (for internet play)
func get_public_ip() -> String:
	# Returns placeholder - use Nakama for proper matchmaking
	return "0.0.0.0"


## Join by room code (legacy - prefer Nakama match IDs)
func join_by_room_code(room_code: String) -> void:
	"""Lookup room via local dictionary and join (legacy ENet support)"""
	if room_code_to_ip.has(room_code):
		var room_data = room_code_to_ip[room_code]
		join_server(room_data["ip"], room_data["port"])
	else:
		push_error("Room code not found: ", room_code)
		connection_failed.emit()


## Join a server (client)
func join_server(address: String, port: int = DEFAULT_PORT) -> Error:
	_metrics["connect_attempts"] += 1
	_metrics["last_connect_start_msec"] = Time.get_ticks_msec()
	_emit_metrics()
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	
	if error != OK:
		push_error("Failed to join server: " + str(error))
		_metrics["connect_failures"] += 1
		_emit_metrics()
		return error
	
	multiplayer.multiplayer_peer = peer
	print("Attempting to connect to ", address, ":", port)
	
	# Store connection details for potential reconnection
	_last_connection_address = address
	_last_connection_port = port
	_reconnection_attempt = 0
	
	return OK


## Disconnect from network
func disconnect_from_network() -> void:
	current_room_code = ""
	
	if peer:
		peer.close()
		peer = null
	
	multiplayer.multiplayer_peer = null
	players.clear()
	print("Disconnected from network")


## Check if we are the server
func is_server() -> bool:
	return multiplayer.is_server()


## Get our multiplayer ID
func get_multiplayer_id() -> int:
	return multiplayer.get_unique_id()


## Get our Nakama User ID
func get_nakama_user_id() -> String:
	if NakamaManager:
		return NakamaManager.local_user_id
	return ""


## Register the local player node
func _register_local_player() -> void:
	var peer_id = multiplayer.get_unique_id()
	players[peer_id] = local_player_info.duplicate(true)
	print("Local player registered with ID: ", peer_id)


## Update local player transform data (called by XRPlayer every frame)
func update_local_player_transform(head_pos: Vector3, head_rot: Vector3, 
		left_pos: Vector3, left_rot: Vector3, 
		right_pos: Vector3, right_rot: Vector3,
		scale: Vector3) -> void:
	
	local_player_info.head_position = head_pos
	local_player_info.head_rotation = head_rot
	local_player_info.left_hand_position = left_pos
	local_player_info.left_hand_rotation = left_rot
	local_player_info.right_hand_position = right_pos
	local_player_info.right_hand_rotation = right_rot
	local_player_info.player_scale = scale
	
	# Update our entry in players dictionary
	var peer_id = multiplayer.get_unique_id()
	if use_nakama:
		var nakama_id = get_nakama_user_id()
		if not nakama_id.is_empty():
			players[nakama_id] = local_player_info.duplicate(true)
			
			# Send via Nakama
			var transform_data = {
				"hp": _vec3_to_dict(head_pos),
				"hr": _vec3_to_dict(head_rot),
				"lp": _vec3_to_dict(left_pos),
				"lr": _vec3_to_dict(left_rot),
				"rp": _vec3_to_dict(right_pos),
				"rr": _vec3_to_dict(right_rot),
				"s": _vec3_to_dict(scale)
			}
			NakamaManager.send_match_state(NakamaManager.MatchOpCode.PLAYER_TRANSFORM, transform_data)
	else:
		if players.has(peer_id):
			players[peer_id] = local_player_info.duplicate(true)
	
	# Send to all other players (unreliable for performance)
	# Only send if peer is actually connected
	if not use_nakama and multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_send_player_transform.rpc_id(0, head_pos, head_rot, left_pos, left_rot, right_pos, right_rot, scale)


## RPC to send player transform to others
@rpc("unreliable", "call_remote", "any_peer")
func _send_player_transform(head_pos: Vector3, head_rot: Vector3,
		left_pos: Vector3, left_rot: Vector3,
		right_pos: Vector3, right_rot: Vector3,
		scale: Vector3) -> void:
	
	var sender_id = multiplayer.get_remote_sender_id()
	
	if not players.has(sender_id):
		players[sender_id] = local_player_info.duplicate(true)
	
	players[sender_id].head_position = head_pos
	players[sender_id].head_rotation = head_rot
	players[sender_id].left_hand_position = left_pos
	players[sender_id].left_hand_rotation = left_rot
	players[sender_id].right_hand_position = right_pos
	players[sender_id].right_hand_rotation = right_rot
	players[sender_id].player_scale = scale


## Request player list from server (client calls this after connecting)
@rpc("reliable", "call_remote", "any_peer")
func request_player_list() -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	_send_player_list.rpc_id(sender_id, players)


## Server sends full player list to a client
@rpc("reliable", "call_remote", "authority")
func _send_player_list(player_list: Dictionary) -> void:
	players = player_list.duplicate(true)
	print("Received player list with ", players.size(), " players")


# ============================================================================
# Network Event Callbacks
# ============================================================================

func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)
	
	if is_server():
		# Initialize player entry
		players[id] = local_player_info.duplicate(true)
		
		# Send full voxel state to new client
		_sync_voxel_state_to_client.rpc_id(id)
	
	player_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	
	if players.has(id):
		players.erase(id)
	
	player_disconnected.emit(id)


func _on_connected_to_server() -> void:
	print("Successfully connected to server")
	if _metrics["last_connect_start_msec"] > 0:
		_metrics["last_connect_latency_ms"] = Time.get_ticks_msec() - int(_metrics["last_connect_start_msec"])
	_metrics["connect_successes"] += 1
	_metrics["reconnect_attempts"] = _reconnection_attempt
	_emit_metrics()
	_register_local_player()
	
	# Request existing player list from server
	request_player_list.rpc_id(1)
	
	connection_succeeded.emit()
	_update_monitoring_state()


func _on_connection_failed() -> void:
	push_error("Failed to connect to server")
	_metrics["connect_failures"] += 1
	_emit_metrics()
	peer = null
	multiplayer.multiplayer_peer = null
	connection_failed.emit()
	_update_monitoring_state()


func _on_server_disconnected() -> void:
	print("Server disconnected")
	_metrics["disconnects"] += 1
	_emit_metrics()
	peer = null
	multiplayer.multiplayer_peer = null
	players.clear()
	grabbed_objects.clear()
	server_disconnected.emit()
	_update_monitoring_state()


# ============================================================================
# Nakama Event Callbacks
# ============================================================================

func _on_nakama_match_joined(match_id: String) -> void:
	print("NetworkManager: Joined Nakama match: ", match_id)
	use_nakama = true
	
	# DON'T add ourselves to the players dictionary - this prevents duplicate spawns
	# The local player is already tracked separately via local_player_info
	
	# Notify listeners
	connection_succeeded.emit()
	
	# Trigger avatar send after a short delay to ensure everything is set up
	await get_tree().create_timer(0.5).timeout
	send_local_avatar.emit()
	_update_monitoring_state()

func _on_nakama_match_left() -> void:
	print("NetworkManager: Left Nakama match")
	players.clear()
	grabbed_objects.clear()
	server_disconnected.emit()
	_update_monitoring_state()

func _on_nakama_match_presence(joins: Array, leaves: Array) -> void:
	var my_id = get_nakama_user_id()
	print("NetworkManager: Match presence - my ID: ", my_id, ", joins: ", joins.size())
	
	for join in joins:
		var user_id = join.get("user_id", "")
		print("NetworkManager: Checking join - user_id: '", user_id, "', is_empty: ", user_id.is_empty(), ", equals_mine: ", (user_id == my_id))
		
		# Skip if empty OR if this is us
		if user_id.is_empty() or user_id == my_id:
			print("NetworkManager: SKIPPING user_id: ", user_id)
			continue
		
		print("NetworkManager: Nakama player joined: ", user_id)
		# Initialize player data
		players[user_id] = local_player_info.duplicate(true)
		player_connected.emit(user_id)
		
	for leave in leaves:
		var user_id = leave.get("user_id", "")
		if user_id != my_id and not user_id.is_empty():
			print("NetworkManager: Nakama player left: ", user_id)
			if players.has(user_id):
				players.erase(user_id)
			player_disconnected.emit(user_id)



func _handle_nakama_player_transform(sender_id: String, data: Dictionary) -> void:
	"""Handle incoming player transform data from Nakama"""
	if not players.has(sender_id):
		players[sender_id] = local_player_info.duplicate(true)
	
	var p = players[sender_id]
	
	# Update player data from received dictionary
	# We use short keys "hp", "hr", etc. to save bandwidth
	if data.has("hp"): p.head_position = _dict_to_vec3(data.hp)
	if data.has("hr"): p.head_rotation = _dict_to_vec3(data.hr)
	if data.has("lp"): p.left_hand_position = _dict_to_vec3(data.lp)
	if data.has("lr"): p.left_hand_rotation = _dict_to_vec3(data.lr)
	if data.has("rp"): p.right_hand_position = _dict_to_vec3(data.rp)
	if data.has("rr"): p.right_hand_rotation = _dict_to_vec3(data.rr)
	if data.has("s"): p.player_scale = _dict_to_vec3(data.s)


func _vec3_to_dict(v: Vector3) -> Dictionary:
	return {"x": snappedf(v.x, 0.001), "y": snappedf(v.y, 0.001), "z": snappedf(v.z, 0.001)}


func _dict_to_vec3(d: Dictionary) -> Vector3:
	return Vector3(d.get("x", 0), d.get("y", 0), d.get("z", 0))


func _quat_to_dict(q: Quaternion) -> Dictionary:
	return {"x": snappedf(q.x, 0.001), "y": snappedf(q.y, 0.001), "z": snappedf(q.z, 0.001), "w": snappedf(q.w, 0.001)}


func _dict_to_quat(d: Dictionary) -> Quaternion:
	return Quaternion(d.get("x", 0), d.get("y", 0), d.get("z", 0), d.get("w", 1))


func _handle_nakama_avatar_data(sender_id: String, data: Dictionary) -> void:
	"""Handle incoming avatar texture data from Nakama"""
	if data.is_empty():
		return
	
	# Store in player data
	if not players.has(sender_id):
		players[sender_id] = local_player_info.duplicate(true)
	
	# Initialize avatar_textures dictionary if not exists
	if not players[sender_id].has("avatar_textures"):
		players[sender_id].avatar_textures = {}
	
	var total_bytes = 0
	
	# Decode all avatar surfaces (head, body, hands)
	for surface_name in data:
		var texture_base64 = data[surface_name]
		var texture_data = Marshalls.base64_to_raw(texture_base64)
		players[sender_id].avatar_textures[surface_name] = texture_data
		total_bytes += texture_data.size()
	
	print("NetworkManager: Received ", data.size(), " avatar textures from ", sender_id, " via Nakama (", total_bytes, " bytes)")
	
	# Emit signal so PlayerNetworkComponent can apply them
	avatar_texture_received.emit(sender_id)


# ============================================================================
# Avatar Texture Sync
# ============================================================================

func set_local_avatar_textures(textures: Dictionary) -> void:
	"""Set the local player's avatar textures (head, body, hands) and broadcast to other players"""
	# Convert all textures to base64-encoded PNG data
	var avatar_data = {}
	var total_bytes = 0
	
	for surface_name in textures:
		var texture: ImageTexture = textures[surface_name]
		var image = texture.get_image()
		var texture_data = image.save_png_to_buffer()
		avatar_data[surface_name] = Marshalls.raw_to_base64(texture_data)
		total_bytes += texture_data.size()
	
	# Send via Nakama
	if use_nakama and NakamaManager:
		NakamaManager.send_match_state(NakamaManager.MatchOpCode.AVATAR_DATA, avatar_data)
		print("NetworkManager: Sent ", textures.size(), " avatar textures via Nakama (", total_bytes, " bytes)")
	# Fallback to ENet RPC (only sends head for compatibility)
	elif multiplayer.multiplayer_peer and textures.has("head"):
		var head_texture: ImageTexture = textures["head"]
		var image = head_texture.get_image()
		var texture_data = image.save_png_to_buffer()
		_send_avatar_texture.rpc_id(0, texture_data)
		print("NetworkManager: Sent head avatar texture via ENet (", texture_data.size(), " bytes)")


func set_local_avatar_texture(texture: ImageTexture) -> void:
	"""Set the local player's avatar texture and broadcast to other players"""
	var image = texture.get_image()
	var texture_data = image.save_png_to_buffer()
	
	# Store locally
	var peer_id = multiplayer.get_unique_id()
	if players.has(peer_id):
		players[peer_id].avatar_texture_data = texture_data
	
	# Send via Nakama
	if use_nakama and NakamaManager:
		var avatar_data = {
			"texture": Marshalls.raw_to_base64(texture_data)
		}
		NakamaManager.send_match_state(NakamaManager.MatchOpCode.AVATAR_DATA, avatar_data)
		print("NetworkManager: Sent avatar texture via Nakama (", texture_data.size(), " bytes)")
	# Fallback to ENet RPC
	elif multiplayer.multiplayer_peer:
		_send_avatar_texture.rpc_id(0, texture_data)
		print("NetworkManager: Sent avatar texture via ENet (", texture_data.size(), " bytes)")


@rpc("reliable", "call_remote", "any_peer")
func _send_avatar_texture(texture_data: PackedByteArray) -> void:
	"""Receive avatar texture from another player"""
	var sender_id = multiplayer.get_remote_sender_id()
	
	if not players.has(sender_id):
		players[sender_id] = local_player_info.duplicate(true)
	
	players[sender_id].avatar_texture_data = texture_data
	print("NetworkManager: Received avatar texture from ", sender_id, " (", texture_data.size(), " bytes)")
	
	# Emit signal so XRPlayer can apply the texture
	avatar_texture_received.emit(sender_id)


func get_player_avatar_texture(peer_id: Variant) -> ImageTexture:
	"""Get avatar texture for a specific player (supports both int and String peer IDs)"""
	if not players.has(peer_id):
		return null
	
	var texture_data = players[peer_id].get("avatar_texture_data", PackedByteArray())
	if texture_data.size() == 0:
		return null
	
	var image = Image.new()
	var error = image.load_png_from_buffer(texture_data)
	if error != OK:
		push_error("Failed to load avatar texture for peer ", peer_id)
		return null
	
	return ImageTexture.create_from_image(image)


# ============================================================================
# Grabbable Object Sync
# ============================================================================

func grab_object(object_id: String, hand_name: String = "", rel_pos: Vector3 = Vector3.ZERO, rel_rot: Quaternion = Quaternion.IDENTITY) -> void:
	"""Notify network that we grabbed an object"""
	var peer_id = multiplayer.get_unique_id()
	grabbed_objects[object_id] = {
		"owner_peer_id": peer_id,
		"is_grabbed": true,
		"position": Vector3.ZERO,
		"rotation": Quaternion.IDENTITY,
		"hand_name": hand_name
	}
	
	if use_nakama and NakamaManager:
		var grab_data = {
			"object_id": object_id,
			"hand_name": hand_name,
			"rel_pos": _vec3_to_dict(rel_pos),
			"rel_rot": _quat_to_dict(rel_rot) # need a new dict helper for this
		}
		NakamaManager.send_match_state(NakamaManager.MatchOpCode.GRAB_OBJECT, grab_data)
	elif multiplayer.multiplayer_peer:
		_notify_grab.rpc_id(0, object_id, peer_id)
	
	grabbable_grabbed.emit(object_id, peer_id)
	print("NetworkManager: Grabbed object ", object_id)


func release_object(object_id: String, final_pos: Vector3, final_rot: Quaternion, lin_vel: Vector3 = Vector3.ZERO, ang_vel: Vector3 = Vector3.ZERO) -> void:
	"""Notify network that we released an object"""
	var peer_id = multiplayer.get_unique_id()
	
	if grabbed_objects.has(object_id):
		grabbed_objects.erase(object_id)
	
	if use_nakama and NakamaManager:
		var release_data = {
			"object_id": object_id,
			"pos": _vec3_to_dict(final_pos),
			"rot": _quat_to_dict(final_rot),
			"lin_vel": _vec3_to_dict(lin_vel),
			"ang_vel": _vec3_to_dict(ang_vel)
		}
		NakamaManager.send_match_state(NakamaManager.MatchOpCode.RELEASE_OBJECT, release_data)
	elif multiplayer.multiplayer_peer:
		_notify_release.rpc_id(0, object_id, peer_id, final_pos, final_rot)
	
	grabbable_released.emit(object_id, peer_id)
	print("NetworkManager: Released object ", object_id)


func update_grabbed_object(object_id: String, pos: Vector3, rot: Quaternion, rel_pos: Variant = null, rel_rot: Variant = null) -> void:
	"""Send continuous update for an object while it is being held"""
	# Nakama state broadcast
	if use_nakama and NakamaManager:
		var update_data = {
			"object_id": object_id,
			"pos": _vec3_to_dict(pos),
			"rot": _quat_to_dict(rot),
		}
		
		# Include relative offsets if they changed (e.g. desktop distance/rotation)
		if rel_pos != null and rel_pos is Vector3:
			update_data["rel_pos"] = _vec3_to_dict(rel_pos)
		if rel_rot != null and rel_rot is Quaternion:
			update_data["rel_rot"] = _quat_to_dict(rel_rot)
			
		NakamaManager.send_match_state(NakamaManager.MatchOpCode.OBJECT_UPDATE, update_data)
	# Only send RPC if we have a valid connection (ENet)
	elif multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_sync_grabbed_object.rpc_id(0, object_id, pos, rot)


@rpc("reliable", "call_remote", "any_peer")
func _notify_grab(object_id: String, peer_id: int) -> void:
	"""Receive notification that someone grabbed an object"""
	grabbed_objects[object_id] = {
		"owner_peer_id": peer_id,
		"is_grabbed": true,
		"position": Vector3.ZERO,
		"rotation": Quaternion.IDENTITY
	}
	grabbable_grabbed.emit(object_id, peer_id)


@rpc("reliable", "call_remote", "any_peer")
func _notify_release(object_id: String, peer_id: int, final_pos: Vector3, final_rot: Quaternion) -> void:
	"""Receive notification that someone released an object"""
	if grabbed_objects.has(object_id):
		grabbed_objects.erase(object_id)
	grabbable_released.emit(object_id, peer_id)
	grabbable_sync_update.emit(object_id, {"position": final_pos, "rotation": final_rot})


@rpc("unreliable", "call_remote", "any_peer")
func _sync_grabbed_object(object_id: String, pos: Vector3, rot: Quaternion) -> void:
	"""Receive grabbed object position update"""
	if grabbed_objects.has(object_id):
		grabbed_objects[object_id].position = pos
		grabbed_objects[object_id].rotation = rot
	grabbable_sync_update.emit(object_id, {"position": pos, "rotation": rot})


func is_object_grabbed_by_other(object_id: String) -> bool:
	"""Check if an object is grabbed by another player"""
	if not grabbed_objects.has(object_id):
		return false
	
	var owner_id = grabbed_objects[object_id].get("owner_peer_id", -1)
	return owner_id != multiplayer.get_unique_id() and owner_id != -1


func get_object_owner(object_id: String) -> int:
	"""Get the peer ID of who owns/grabbed this object"""
	if not grabbed_objects.has(object_id):
		return -1
	return grabbed_objects[object_id].get("owner_peer_id", -1)



# ============================================================================
# Networked Object Spawning
# ============================================================================

func spawn_network_object(scene_path: String, position: Vector3) -> void:
	"""Spawn an object on all connected clients"""
	var object_id = "obj_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000)
	
	if use_nakama and NakamaManager:
		var spawn_data = {
			"scene_path": scene_path,
			"pos": _vec3_to_dict(position),
			"object_id": object_id
		}
		NakamaManager.send_match_state(NakamaManager.MatchOpCode.SPAWN_OBJECT, spawn_data)
		# Also spawn locally
		_do_spawn_object(scene_path, position, object_id)
	elif multiplayer.multiplayer_peer:
		# Call on all clients (including local)
		_spawn_object_remote.rpc(scene_path, position, object_id)


@rpc("reliable", "call_local", "any_peer")
func _spawn_object_remote(scene_path: String, position: Vector3, object_id: String) -> void:
	"""RPC to spawn object on all clients"""
	_do_spawn_object(scene_path, position, object_id)


func _do_spawn_object(scene_path: String, position: Vector3, object_id: String) -> void:
	"""Internal helper to instantiate and add object to scene"""
	var scene = load(scene_path)
	if not scene:
		push_error("NetworkManager: Failed to load scene for spawning: " + scene_path)
		return
		
	var instance = scene.instantiate()
	if not instance:
		push_error("NetworkManager: Failed to instantiate scene: " + scene_path)
		return
		
	instance.name = object_id
	if instance.has_method("set"):
		instance.set("save_id", object_id)
		
	# Add to current world
	var world = get_tree().current_scene
	if world:
		world.add_child(instance)
		if instance is Node3D:
			instance.global_position = position
		print("NetworkManager: Spawned object ", object_id, " at ", position)
	else:
		push_error("NetworkManager: No current scene to spawn object into")


# ============================================================================
# Voxel Build Sync
# ============================================================================

func sync_voxel_placed(world_pos: Vector3, color: Color) -> void:
	"""Notify network that a voxel was placed"""
	if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_notify_voxel_placed.rpc_id(0, world_pos, color)


func sync_voxel_removed(world_pos: Vector3) -> void:
	"""Notify network that a voxel was removed"""
	if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_notify_voxel_removed.rpc_id(0, world_pos)


@rpc("reliable", "call_remote", "any_peer")
func _notify_voxel_placed(world_pos: Vector3, color: Color) -> void:
	"""Receive notification that someone placed a voxel"""
	voxel_placed_network.emit(world_pos, color)
	print("NetworkManager: Voxel placed at ", world_pos, " by peer ", multiplayer.get_remote_sender_id())


@rpc("reliable", "call_remote", "any_peer")
func _notify_voxel_removed(world_pos: Vector3) -> void:
	"""Receive notification that someone removed a voxel"""
	voxel_removed_network.emit(world_pos)
	print("NetworkManager: Voxel removed at ", world_pos, " by peer ", multiplayer.get_remote_sender_id())


@rpc("reliable", "call_local", "authority")
func _sync_voxel_state_to_client() -> void:
	"""Send all existing voxels to a newly connected client"""
	if not is_server():
		return
	
	# Find the voxel chunk manager
	var voxel_manager = get_tree().get_first_node_in_group("voxel_manager")
	if not voxel_manager or not voxel_manager.has_method("get_all_voxels"):
		return
	
	# Get all voxels and send them to the client
	var all_voxels = voxel_manager.get_all_voxels()
	if all_voxels.size() > 0:
		_receive_voxel_state.rpc_id(multiplayer.get_remote_sender_id(), all_voxels)
		print("NetworkManager: Sent ", all_voxels.size(), " voxels to new client")


@rpc("reliable", "call_remote", "authority")
func _receive_voxel_state(voxels: Array) -> void:
	"""Receive full voxel state from server"""
	for voxel_data in voxels:
		if voxel_data.has("pos") and voxel_data.has("color"):
			voxel_placed_network.emit(voxel_data["pos"], voxel_data["color"])
	print("NetworkManager: Received ", voxels.size(), " voxels from server")


# ============================================================================
# Nakama Integration
# ============================================================================

func _on_nakama_match_state_received(peer_id: String, op_code: int, data: Variant) -> void:
	"""Handle incoming match state from Nakama"""
	if not use_nakama:
		return
		
	# Handle Player Transform
	if op_code == NakamaManager.MatchOpCode.PLAYER_TRANSFORM:
		if data is Dictionary:
			_handle_nakama_player_transform(peer_id, data)
			
	# Handle Avatar Data
	elif op_code == NakamaManager.MatchOpCode.AVATAR_DATA:
		if data is Dictionary:
			_handle_nakama_avatar_data(peer_id, data)
			
	# Note: Voice data (VOICE_DATA op code) removed - voice now handled by LiveKit
	
	# Handle Voxel Events
	# Note: NakamaManager is autoloaded, so we can access the enum directly if we wanted,
	# but to avoid circular dependency issues during load, we'll use the integer values
	# defined in NakamaManager (VOXEL_PLACE = 5, VOXEL_REMOVE = 6)
	
	elif op_code == NakamaManager.MatchOpCode.VOXEL_PLACE:
		if data is Dictionary and data.has("pos") and data.has("color"):
			var pos_str = data["pos"]
			var color_str = data["color"]
			
			# Parse vector and color from string/dict if needed
			var pos = _parse_vector3(pos_str)
			var color = _parse_color(color_str)
			
			voxel_placed_network.emit(pos, color)
			print("NetworkManager (Nakama): Voxel placed at ", pos, " by ", peer_id)
			
	elif op_code == NakamaManager.MatchOpCode.VOXEL_REMOVE:
		if data is Dictionary and data.has("pos"):
			var pos = _parse_vector3(data["pos"])
			voxel_removed_network.emit(pos)
			print("NetworkManager (Nakama): Voxel removed at ", pos, " by ", peer_id)
			
	elif op_code == NakamaManager.MatchOpCode.VOXEL_BATCH:
		if data is Dictionary and data.has("updates") and data["updates"] is Array:
			for update in data["updates"]:
				var type = update.get("t", 0) # 0=place, 1=remove
				var pos = _parse_vector3(update.get("p", Vector3.ZERO))
				
				if type == 0: # Place
					var color = _parse_color(update.get("c", Color.WHITE))
					voxel_placed_network.emit(pos, color)
				elif type == 1: # Remove
					voxel_removed_network.emit(pos)
			print("NetworkManager (Nakama): Processed voxel batch of size ", data["updates"].size(), " from ", peer_id)
			
	elif op_code == NakamaManager.MatchOpCode.SPAWN_OBJECT:
		if data is Dictionary and data.has("scene_path") and data.has("pos") and data.has("object_id"):
			var scene_path = data["scene_path"]
			var pos = _parse_vector3(data["pos"])
			var object_id = data["object_id"]
			_do_spawn_object(scene_path, pos, object_id)
			
	elif op_code == NakamaManager.MatchOpCode.GRAB_OBJECT:
		if data is Dictionary and data.has("object_id"):
			grabbable_grabbed.emit(data["object_id"], peer_id)
			
	elif op_code == NakamaManager.MatchOpCode.RELEASE_OBJECT:
		if data is Dictionary and data.has("object_id"):
			var object_id = data["object_id"]
			grabbable_released.emit(object_id, peer_id)
			if data.has("pos") and data.has("rot"):
				grabbable_sync_update.emit(object_id, {
					"position": _parse_vector3(data["pos"]),
					"rotation": _parse_quaternion(data["rot"])
				})
				
	elif op_code == NakamaManager.MatchOpCode.OBJECT_UPDATE:
		if data is Dictionary and data.has("object_id") and data.has("pos") and data.has("rot"):
			var object_id = data["object_id"]
			var sync_data = {
				"position": _parse_vector3(data["pos"]),
				"rotation": _parse_quaternion(data["rot"])
			}
			if data.has("rel_pos"): sync_data["rel_pos"] = _parse_vector3(data["rel_pos"])
			if data.has("rel_rot"): sync_data["rel_rot"] = _parse_quaternion(data["rel_rot"])
			grabbable_sync_update.emit(object_id, sync_data)


func _parse_vector3(data) -> Vector3:
	if data is Vector3:
		return data
	elif data is String:
		# simplistic parsing "x,y,z" or similar
		var parts = data.replace("(", "").replace(")", "").split(",")
		if parts.size() >= 3:
			return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	elif data is Dictionary:
		return Vector3(data.get("x", 0), data.get("y", 0), data.get("z", 0))
	return Vector3.ZERO


func _parse_color(data) -> Color:
	if data is Color:
		return data
	elif data is String:
		return Color(data)
	elif data is Dictionary:
		return Color(data.get("r", 1), data.get("g", 1), data.get("b", 1), data.get("a", 1))
	return Color.WHITE


func _parse_quaternion(data) -> Quaternion:
	if data is Quaternion:
		return data
	elif data is Dictionary:
		return Quaternion(data.get("x", 0), data.get("y", 0), data.get("z", 0), data.get("w", 1))
	return Quaternion.IDENTITY


# ============================================================================
# Connection Quality Monitoring
# ============================================================================

func _process(_delta: float) -> void:
	# Only track push-to-talk per-frame when active; everything else is timer-driven
	if voice_mode == VoiceMode.PUSH_TO_TALK:
		is_push_to_talk_pressed = Input.is_key_pressed(push_to_talk_key)


func _update_network_stats() -> void:
	"""Calculate and update network statistics"""
	if not peer:
		return
	
	# Calculate ping (simulated - ENet doesn't expose this directly)
	# In a real implementation, you'd send ping packets and measure RTT
	var estimated_ping = _estimate_ping()
	network_stats["ping_ms"] = estimated_ping
	
	# Calculate bandwidth
	var current_bytes_sent = 0  # Would need ENet extension to get real values
	var current_bytes_received = 0
	
	var bytes_sent_delta = current_bytes_sent - _last_bytes_sent
	var bytes_received_delta = current_bytes_received - _last_bytes_received
	
	network_stats["bandwidth_up"] = bytes_sent_delta / 1024.0 / _ping_check_interval
	network_stats["bandwidth_down"] = bytes_received_delta / 1024.0 / _ping_check_interval
	
	_last_bytes_sent = current_bytes_sent
	_last_bytes_received = current_bytes_received
	
	# Determine connection quality based on ping
	var old_quality = network_stats["connection_quality"]
	var new_quality = _calculate_connection_quality(estimated_ping)
	network_stats["connection_quality"] = new_quality
	
	# Emit signals if quality changed
	if old_quality != new_quality:
		connection_quality_changed.emit(new_quality)
	
	network_stats_updated.emit(network_stats.duplicate())


func _on_monitor_timeout() -> void:
	"""Timer-based connection monitoring to avoid per-frame polling"""
	if not _is_connection_active():
		_update_monitoring_state()
		return
	
	_update_network_stats()
	
	# Check for connection timeout (only for client side)
	if not is_server():
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - _last_server_response_time > connection_timeout:
			print("NetworkManager: Connection timeout detected")
			_attempt_reconnection()


func _is_connection_active() -> bool:
	if peer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		return true
	if use_nakama and NakamaManager and NakamaManager.is_socket_connected:
		return true
	return false


func _update_monitoring_state() -> void:
	if _monitor_timer:
		_monitor_timer.wait_time = _ping_check_interval
		var should_run := _is_connection_active()
		_monitor_timer.paused = not should_run
		if should_run:
			_monitor_timer.start()
		else:
			_monitor_timer.stop()
	
	var should_process_ptt := voice_mode == VoiceMode.PUSH_TO_TALK and _is_connection_active()
	set_process(should_process_ptt)


func _estimate_ping() -> float:
	"""Estimate ping based on transform update timing"""
	# This is a simplified estimation
	# In production, you'd implement proper ping packets
	if not is_server() and players.size() > 0:
		# Estimate based on update frequency
		return randf_range(40.0, 120.0)  # Placeholder
	return 0.0


func _calculate_connection_quality(ping_ms: float) -> ConnectionQuality:
	"""Determine connection quality from ping"""
	if ping_ms < 50.0:
		return ConnectionQuality.EXCELLENT
	elif ping_ms < 100.0:
		return ConnectionQuality.GOOD
	elif ping_ms < 200.0:
		return ConnectionQuality.FAIR
	else:
		return ConnectionQuality.POOR


func _attempt_reconnection() -> void:
	"""Try to reconnect to the server"""
	if _reconnection_attempt >= MAX_RECONNECTION_ATTEMPTS:
		print("NetworkManager: Max reconnection attempts reached")
		_on_connection_failed()
		return
	
	_reconnection_attempt += 1
	_metrics["reconnect_attempts"] = _reconnection_attempt
	_emit_metrics()
	print("NetworkManager: Reconnection attempt ", _reconnection_attempt, "/", MAX_RECONNECTION_ATTEMPTS)
	
	if _last_connection_address != "" and _last_connection_port > 0:
		# Disconnect first
		if peer:
			peer.close()
			peer = null
		
		# Wait a bit before reconnecting (exponential backoff)
		await get_tree().create_timer(pow(2, _reconnection_attempt - 1)).timeout
		
		# Try to reconnect
		join_server(_last_connection_address, _last_connection_port)


## Public API for network stats

func get_network_stats() -> Dictionary:
	"""Get current network statistics"""
	return network_stats.duplicate()

func get_metrics() -> Dictionary:
	"""Get lightweight connection/reconnect metrics"""
	return _metrics.duplicate()

func _emit_metrics() -> void:
	metrics_updated.emit(_metrics.duplicate())

func _record_send_failure(reason: String) -> void:
	_metrics["send_failures"] += 1
	_metrics["last_send_failure"] = reason
	_emit_metrics()


func get_connection_quality() -> ConnectionQuality:
	"""Get current connection quality"""
	return network_stats["connection_quality"]


func get_connection_quality_string() -> String:
	"""Get connection quality as human-readable string"""
	match network_stats["connection_quality"]:
		ConnectionQuality.EXCELLENT:
			return "Excellent"
		ConnectionQuality.GOOD:
			return "Good"
		ConnectionQuality.FAIR:
			return "Fair"
		ConnectionQuality.POOR:
			return "Poor"
	return "Unknown"


## Push-to-talk API

func set_voice_activation_mode(mode: VoiceMode) -> void:
	"""Set voice activation mode"""
	voice_mode = mode
	print("NetworkManager: Voice mode set to ", _voice_mode_to_string(mode))


func set_push_to_talk_key(key: Key) -> void:
	"""Set the push-to-talk key"""
	push_to_talk_key = key
	print("NetworkManager: Push-to-talk key set to ", OS.get_keycode_string(key))


func is_voice_transmitting() -> bool:
	"""Check if voice is currently being transmitted"""
	if not voice_enabled:
		return false
	
	match voice_mode:
		VoiceMode.ALWAYS_ON:
			return true
		VoiceMode.PUSH_TO_TALK:
			return is_push_to_talk_pressed
		VoiceMode.VOICE_ACTIVATED:
			# Would need audio level detection
			return false
	
	return false


func _voice_mode_to_string(mode: VoiceMode) -> String:
	"""Convert voice mode to string"""
	match mode:
		VoiceMode.ALWAYS_ON:
			return "Always On"
		VoiceMode.PUSH_TO_TALK:
			return "Push to Talk"
		VoiceMode.VOICE_ACTIVATED:
			return "Voice Activated"
	return "Unknown"
