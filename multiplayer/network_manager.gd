extends Node
## NetworkManager - Handles all network connections and player management
## Singleton autoload that manages ENet connections, player spawning, and network events

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed()
signal connection_succeeded()
signal server_disconnected()

const DEFAULT_PORT = 7777
const MAX_CLIENTS = 8

# Room code system
var current_room_code: String = ""
var room_code_to_ip: Dictionary = {} # room_code -> {ip, port, host_name, player_count, created_time}
signal room_code_generated(code: String)

# Matchmaking
var matchmaking: Node = null
var use_matchmaking_server: bool = true
const MATCHMAKING_SERVER_URL = "http://localhost:8080"

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

# Voice chat
var voice_enabled: bool = false
var microphone_bus_index: int = -1
const VOICE_SAMPLE_RATE = 16000
const VOICE_BUFFER_SIZE = 2048


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# Setup matchmaking
	_setup_matchmaking()
	
	# Setup voice chat audio bus
	_setup_voice_chat()
	
	# Enable voice by default
	voice_enabled = true


func _setup_matchmaking() -> void:
	"""Initialize matchmaking server connection"""
	var matchmaking_script = load("res://multiplayer/matchmaking_server.gd")
	matchmaking = matchmaking_script.new()
	add_child(matchmaking)
	
	# Use local server for development, or set to false to use remote server
	matchmaking.matchmaking_url = MATCHMAKING_SERVER_URL
	
	# Connect signals
	matchmaking.room_registered.connect(_on_matchmaking_room_registered)
	matchmaking.room_found.connect(_on_matchmaking_room_found)
	
	print("NetworkManager: Matchmaking initialized")


func _on_matchmaking_room_found(success: bool, room_data: Dictionary) -> void:
	"""Handle room lookup response from matchmaking server"""
	if success and room_data.has("ip") and room_data.has("port"):
		print("Matchmaking: Found room at ", room_data["ip"], ":", room_data["port"])
		join_server(room_data["ip"], room_data["port"])
	else:
		push_error("Matchmaking: Failed to find room")
		connection_failed.emit()


func _on_matchmaking_room_registered(success: bool, room_code: String) -> void:
	"""Handle room registration response from matchmaking server"""
	if success:
		print("Matchmaking: Room registered with code ", room_code)
	else:
		push_error("Matchmaking: Failed to register room")


## Generate a 6-character room code
func generate_room_code() -> String:
	const CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" # Removed confusing chars (I, O, 0, 1)
	var code = ""
	for i in range(6):
		code += CHARS[randi() % CHARS.length()]
	return code


## Create a server (host) with optional room code
func create_server(port: int = DEFAULT_PORT, use_room_code: bool = true) -> Error:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_CLIENTS)
	
	if error != OK:
		push_error("Failed to create server: " + str(error))
		return error
	
	multiplayer.multiplayer_peer = peer
	print("Server created on port ", port)
	
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
		
		# Register with matchmaking server
		if use_matchmaking_server and matchmaking:
			matchmaking.register_room(current_room_code, local_ip, port, local_player_info.get("name", "Host"))
		
		room_code_generated.emit(current_room_code)
		print("Room code: ", current_room_code, " (IP: ", local_ip, ")")
	
	# Host is also a player
	_register_local_player()
	
	return OK


## Get local IP address
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


## Join by room code (uses matchmaking)
func join_by_room_code(room_code: String) -> void:
	"""Lookup room via matchmaking server and join"""
	if use_matchmaking_server and matchmaking:
		matchmaking.lookup_room(room_code)
	else:
		# Fallback to local dictionary
		if room_code_to_ip.has(room_code):
			var room_data = room_code_to_ip[room_code]
			join_server(room_data["ip"], room_data["port"])
		else:
			push_error("Room code not found: ", room_code)
			connection_failed.emit()


## Join a server (client)
func join_server(address: String, port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	
	if error != OK:
		push_error("Failed to join server: " + str(error))
		return error
	
	multiplayer.multiplayer_peer = peer
	print("Attempting to connect to ", address, ":", port)
	
	return OK


## Disconnect from network
func disconnect_from_network() -> void:
	# Unregister from matchmaking if we were the host
	if is_server() and use_matchmaking_server and current_room_code != "":
		matchmaking.unregister_room(current_room_code)
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
	if players.has(peer_id):
		players[peer_id] = local_player_info.duplicate(true)
	
	# Send to all other players (unreliable for performance)
	# Only send if peer is actually connected
	if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
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
	_register_local_player()
	
	# Request existing player list from server
	request_player_list.rpc_id(1)
	
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	push_error("Failed to connect to server")
	peer = null
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	print("Server disconnected")
	peer = null
	multiplayer.multiplayer_peer = null
	players.clear()
	grabbed_objects.clear()
	server_disconnected.emit()


# ============================================================================
# Avatar Texture Sync
# ============================================================================

func set_local_avatar_texture(texture: ImageTexture) -> void:
	"""Send avatar texture to all other players"""
	if not texture or not texture.get_image():
		return
	
	var image = texture.get_image()
	var texture_data = image.save_png_to_buffer()
	
	local_player_info.avatar_texture_data = texture_data
	
	# Update our entry
	var peer_id = multiplayer.get_unique_id()
	if players.has(peer_id):
		players[peer_id].avatar_texture_data = texture_data
	
	# Send to all other players
	if multiplayer.multiplayer_peer:
		_send_avatar_texture.rpc_id(0, texture_data)
	
	print("NetworkManager: Sent avatar texture (", texture_data.size(), " bytes)")


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


func get_player_avatar_texture(peer_id: int) -> ImageTexture:
	"""Get avatar texture for a specific player"""
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

func grab_object(object_id: String) -> void:
	"""Notify network that we grabbed an object"""
	var peer_id = multiplayer.get_unique_id()
	grabbed_objects[object_id] = {
		"owner_peer_id": peer_id,
		"is_grabbed": true,
		"position": Vector3.ZERO,
		"rotation": Quaternion.IDENTITY
	}
	
	if multiplayer.multiplayer_peer:
		_notify_grab.rpc_id(0, object_id, peer_id)
	
	grabbable_grabbed.emit(object_id, peer_id)
	print("NetworkManager: Grabbed object ", object_id)


func release_object(object_id: String, final_pos: Vector3, final_rot: Quaternion) -> void:
	"""Notify network that we released an object"""
	var peer_id = multiplayer.get_unique_id()
	
	if grabbed_objects.has(object_id):
		grabbed_objects.erase(object_id)
	
	if multiplayer.multiplayer_peer:
		_notify_release.rpc_id(0, object_id, peer_id, final_pos, final_rot)
	
	grabbable_released.emit(object_id, peer_id)
	print("NetworkManager: Released object ", object_id)


func update_grabbed_object(object_id: String, pos: Vector3, rot: Quaternion) -> void:
	"""Update grabbed object position (called frequently while holding)"""
	if not grabbed_objects.has(object_id):
		return
	
	grabbed_objects[object_id].position = pos
	grabbed_objects[object_id].rotation = rot
	
	# Only send RPC if we have a valid connection
	if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
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
# Voice Chat
# ============================================================================

func _setup_voice_chat() -> void:
	"""Initialize voice chat audio bus"""
	# Check if Voice bus exists, create if not
	var bus_count = AudioServer.get_bus_count()
	var voice_bus = AudioServer.get_bus_index("Voice")
	
	if voice_bus == -1:
		# Create Voice bus
		AudioServer.add_bus(bus_count)
		AudioServer.set_bus_name(bus_count, "Voice")
		voice_bus = bus_count
		print("NetworkManager: Created Voice audio bus")
	
	microphone_bus_index = voice_bus


func enable_voice_chat(enable: bool) -> void:
	"""Enable or disable voice chat"""
	voice_enabled = enable
	print("NetworkManager: Voice chat ", "enabled" if enable else "disabled")


func send_voice_data(audio_data: PackedVector2Array) -> void:
	"""Send voice audio data to all other players with compression"""
	if not voice_enabled or not multiplayer.multiplayer_peer:
		return
	
	# Compress to 16-bit PCM instead of 32-bit float (4x smaller)
	var byte_array = PackedByteArray()
	byte_array.resize(audio_data.size() * 4) # 2 int16 per Vector2, 2 bytes per int16
	
	for i in range(audio_data.size()):
		var sample = audio_data[i]
		# Convert float [-1.0, 1.0] to int16 [-32768, 32767]
		var left_int = int(clamp(sample.x, -1.0, 1.0) * 32767.0)
		var right_int = int(clamp(sample.y, -1.0, 1.0) * 32767.0)
		
		# Encode as 16-bit integers
		byte_array.encode_s16(i * 4, left_int)
		byte_array.encode_s16(i * 4 + 2, right_int)
	
	_receive_voice_data.rpc_id(0, byte_array)


@rpc("unreliable", "call_remote", "any_peer")
func _receive_voice_data(audio_data: PackedByteArray) -> void:
	"""Receive compressed voice data from another player"""
	var sender_id = multiplayer.get_remote_sender_id()
	
	# Don't play our own voice back to ourselves
	if sender_id == get_multiplayer_id():
		return
	
	# Decompress 16-bit PCM back to float samples
	var sample_count = int(float(audio_data.size()) / 4.0)
	var samples = PackedVector2Array()
	samples.resize(sample_count)
	
	for i in range(sample_count):
		# Decode 16-bit integers
		var left_int = audio_data.decode_s16(i * 4)
		var right_int = audio_data.decode_s16(i * 4 + 2)
		
		# Convert int16 back to float [-1.0, 1.0]
		var left = float(left_int) / 32767.0
		var right = float(right_int) / 32767.0
		samples[i] = Vector2(left, right)
	
	# Emit signal for audio playback
	# XRPlayer will handle playing this through the remote player's AudioStreamPlayer3D
	if players.has(sender_id):
		players[sender_id]["voice_samples"] = samples


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
