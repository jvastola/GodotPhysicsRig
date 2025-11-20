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
	"player_scale": Vector3.ONE
}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


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
	server_disconnected.emit()
