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
	
	# Setup voice chat audio bus
	_setup_voice_chat()


## Create a server (host)
func create_server(port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_CLIENTS)
	
	if error != OK:
		push_error("Failed to create server: " + str(error))
		return error
	
	multiplayer.multiplayer_peer = peer
	print("Server created on port ", port)
	
	# Host is also a player
	_register_local_player()
	
	return OK


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
	"""Send voice audio data to all other players"""
	if not voice_enabled or not multiplayer.multiplayer_peer:
		return
	
	# Convert to PackedByteArray for network transmission
	var byte_array = PackedByteArray()
	byte_array.resize(audio_data.size() * 8) # 2 floats per Vector2, 4 bytes per float
	
	for i in range(audio_data.size()):
		var sample = audio_data[i]
		byte_array.encode_float(i * 8, sample.x)
		byte_array.encode_float(i * 8 + 4, sample.y)
	
	_receive_voice_data.rpc_id(0, byte_array)


@rpc("unreliable", "call_remote", "any_peer")
func _receive_voice_data(audio_data: PackedByteArray) -> void:
	"""Receive voice data from another player"""
	var sender_id = multiplayer.get_remote_sender_id()
	
	# Convert back to audio samples
	var sample_count = audio_data.size() / 8
	var samples = PackedVector2Array()
	samples.resize(sample_count)
	
	for i in range(sample_count):
		var left = audio_data.decode_float(i * 8)
		var right = audio_data.decode_float(i * 8 + 4)
		samples[i] = Vector2(left, right)
	
	# Emit signal for audio playback
	# XRPlayer will handle playing this through the remote player's AudioStreamPlayer3D
	if players.has(sender_id):
		players[sender_id]["voice_samples"] = samples
