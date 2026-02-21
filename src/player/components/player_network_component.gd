class_name PlayerNetworkComponent
extends Node

signal player_connected(peer_id: Variant)
signal player_disconnected(peer_id: Variant)
signal avatar_texture_received(peer_id: Variant)

const NETWORK_PLAYER_SCENE = preload("res://multiplayer/NetworkPlayer.tscn")

var network_manager: Node = null
var remote_players: Dictionary = {} # peer_id (Variant) -> NetworkPlayer instance
var update_rate: float = 0.05 # 20 Hz (50ms between updates)
var time_since_last_update: float = 0.0

# References to player parts needed for sync
var player_body: RigidBody3D
var xr_camera: XRCamera3D
var desktop_camera: Camera3D
var left_controller: XRController3D
var right_controller: XRController3D
var is_vr_mode: bool = false

func setup(p_player_body: RigidBody3D, p_xr_camera: XRCamera3D, p_desktop_camera: Camera3D, p_left_controller: XRController3D, p_right_controller: XRController3D) -> void:
	player_body = p_player_body
	xr_camera = p_xr_camera
	desktop_camera = p_desktop_camera
	left_controller = p_left_controller
	right_controller = p_right_controller
	
	_setup_networking()

func set_vr_mode(enabled: bool) -> void:
	is_vr_mode = enabled

func _process(delta: float) -> void:
	_update_networking(delta)

func _setup_networking() -> void:
	"""Initialize network connections and signals"""
	network_manager = get_node("/root/NetworkManager")
	if not network_manager:
		push_error("PlayerNetworkComponent: NetworkManager not found")
		return
	
	# Connect signals
	network_manager.player_connected.connect(_on_player_connected)
	network_manager.player_disconnected.connect(_on_player_disconnected)
	network_manager.avatar_texture_received.connect(_on_avatar_texture_received)
	network_manager.send_local_avatar.connect(send_avatar_texture)
	
	# Connect to NakamaManager match_joined to send avatar when we join a room
	var nakama_manager = get_node_or_null("/root/NakamaManager")
	if nakama_manager and nakama_manager.has_signal("match_joined"):
		if not nakama_manager.match_joined.is_connected(_on_local_match_joined):
			nakama_manager.match_joined.connect(_on_local_match_joined)
	
	print("PlayerNetworkComponent: Networking initialized")


func _on_local_match_joined(_match_id: String) -> void:
	"""When local player joins a match, send our avatar to everyone"""
	print("PlayerNetworkComponent: Local player joined match, sending avatar...")
	# Delay slightly to ensure connection is fully established
	await get_tree().create_timer(0.5).timeout
	send_avatar_texture()

func _update_networking(delta: float) -> void:
	"""Send player transform updates to network and update remote players"""
	if not network_manager or not network_manager.multiplayer.multiplayer_peer:
		return
	
	# Throttle updates to update_rate
	time_since_last_update += delta
	if time_since_last_update < update_rate:
		return
	
	time_since_last_update = 0.0
	
	# Get local player transforms
	var head_pos = Vector3.ZERO
	var head_rot = Vector3.ZERO
	var left_pos = Vector3.ZERO
	var left_rot = Vector3.ZERO
	var right_pos = Vector3.ZERO
	var right_rot = Vector3.ZERO
	
	if is_vr_mode and xr_camera:
		head_pos = xr_camera.global_position
		head_rot = xr_camera.global_rotation_degrees
	elif desktop_camera:
		head_pos = desktop_camera.global_position
		head_rot = desktop_camera.global_rotation_degrees
	
	if is_vr_mode:
		if left_controller:
			left_pos = left_controller.global_position
			left_rot = left_controller.global_rotation_degrees
		if right_controller:
			right_pos = right_controller.global_position
			right_rot = right_controller.global_rotation_degrees
	else:
		# Desktop mode - use camera position for hands (or hide them)
		left_pos = head_pos + Vector3(-0.3, -0.3, 0.0)
		right_pos = head_pos + Vector3(0.3, -0.3, 0.0)
	
	# Get player scale
	var player_scale = player_body.scale if player_body else Vector3.ONE
	
	# Send to NetworkManager
	network_manager.update_local_player_transform(
		head_pos, head_rot,
		left_pos, left_rot,
		right_pos, right_rot,
		player_scale
	)
	
	# Update remote player visuals
	_update_remote_players()

func _update_remote_players() -> void:
	"""Update all remote player visual representations"""
	if not network_manager:
		return
	
	for peer_id in network_manager.players.keys():
		# Skip our own ID
		var local_id = network_manager.get_multiplayer_id()
		if network_manager.use_nakama:
			local_id = network_manager.get_nakama_user_id()
			
		if str(peer_id) == str(local_id):
			continue
		
		var player_data = network_manager.players[peer_id]
		
		# Create remote player if doesn't exist
		if not remote_players.has(peer_id):
			_spawn_remote_player(peer_id)
		
		# Update remote player transforms
		if remote_players.has(peer_id):
			remote_players[peer_id].update_from_network_data(player_data)

func _despawn_remote_player(peer_id: Variant) -> void:
	"""Remove a remote player's visual representation"""
	if remote_players.has(peer_id):
		remote_players[peer_id].queue_free()
		remote_players.erase(peer_id)
		print("PlayerNetworkComponent: Despawned remote player ", peer_id)

func _on_player_connected(peer_id: Variant) -> void:
	"""Handle new player connection"""
	# Skip if this is us
	var local_id = network_manager.get_multiplayer_id()
	if network_manager.use_nakama:
		local_id = network_manager.get_nakama_user_id()
	
	if str(peer_id) == str(local_id) or (peer_id is String and local_id is String and peer_id == local_id):
		print("PlayerNetworkComponent: Skipping spawn for local player")
		return
	
	print("PlayerNetworkComponent: Player connected: ", peer_id)
	_spawn_remote_player(peer_id)
	
	player_connected.emit(peer_id)
	
	# Send our avatar to the new player
	call_deferred("send_avatar_texture")

func _on_player_disconnected(peer_id: Variant) -> void:
	"""Handle player disconnection"""
	print("PlayerNetworkComponent: Player disconnected: ", peer_id)
	_despawn_remote_player(peer_id)
	player_disconnected.emit(peer_id)

## Send avatar texture to network
func send_avatar_texture() -> void:
	"""Send local player's avatar textures (head, body, hands) to all other players"""
	if not network_manager:
		return
	
	# GridPainter should be a sibling component or child of the player
	var grid_painter: GridPainter = null
	
	# Try getting it from parent's children (sibling)
	var parent = get_parent()
	if parent:
		for child in parent.get_children():
			if child is GridPainter:
				grid_painter = child
				break
	
	# Try getting it from scene tree by class
	if not grid_painter:
		var players = get_tree().get_nodes_in_group("player")
		for player in players:
			for child in player.get_children():
				if child is GridPainter:
					grid_painter = child
					break
			if grid_painter:
				break
	
	if not grid_painter:
		print("PlayerNetworkComponent: GridPainter not found, cannot send avatar")
		return
	
	if not grid_painter.has_method("_get_surface"):
		print("PlayerNetworkComponent: GridPainter doesn't have _get_surface method")
		return
	
	# Collect all avatar surfaces (head, body, hands)
	var avatar_textures = {}
	
	# Get head texture
	var head_surface = grid_painter._get_surface("head")
	if head_surface and head_surface.texture:
		avatar_textures["head"] = head_surface.texture
	
	# Get body texture
	var body_surface = grid_painter._get_surface("body")
	if body_surface and body_surface.texture:
		avatar_textures["body"] = body_surface.texture
	
	# Get hand texture (left_hand is shared with right_hand if link_hands is true)
	var hand_surface = grid_painter._get_surface("left_hand")
	if hand_surface and hand_surface.texture:
		avatar_textures["hands"] = hand_surface.texture
	
	if avatar_textures.is_empty():
		print("PlayerNetworkComponent: No avatar textures found, paint your character first!")
		return
	
	# Send all textures to network
	network_manager.set_local_avatar_textures(avatar_textures)
	print("PlayerNetworkComponent: Sent ", avatar_textures.size(), " avatar textures to network")

func _find_grid_painter_recursive(node: Node) -> Node:
	"""Recursively search for GridPainter in the scene tree"""
	if node.get_script():
		var script = node.get_script()
		if script and script.has_method("_get_surface"):
			return node
	
	for child in node.get_children():
		var found = _find_grid_painter_recursive(child)
		if found:
			return found
	
	return null

## Update remote player avatars when they connect
func _spawn_remote_player(peer_id: Variant) -> void:
	"""Spawn a visual representation of a remote player"""
	var remote_player = NETWORK_PLAYER_SCENE.instantiate()
	remote_player.peer_id = peer_id
	remote_player.name = "RemotePlayer_" + str(peer_id)
	
	# Add to scene
	get_tree().root.add_child(remote_player)
	remote_player.add_to_group("network_players")
	remote_players[peer_id] = remote_player
	
	print("PlayerNetworkComponent: Spawned remote player ", peer_id)
	
	# Try to apply their avatar texture
	call_deferred("_apply_remote_avatar", peer_id)

func _apply_remote_avatar(peer_id: Variant) -> void:
	"""Apply avatar texture to a remote player"""
	if not network_manager or not remote_players.has(peer_id):
		return
	
	# Check if we have player data
	if not network_manager.players.has(peer_id):
		return
	
	var player_data = network_manager.players[peer_id]
	
	# Try new multi-surface format first
	if player_data.has("avatar_textures") and not player_data.avatar_textures.is_empty():
		remote_players[peer_id].apply_avatar_textures(player_data.avatar_textures)
		print("PlayerNetworkComponent: Applied ", player_data.avatar_textures.size(), " avatar textures to remote player ", peer_id)
	# Fallback to legacy single texture
	elif player_data.has("avatar_texture_data"):
		var texture = network_manager.get_player_avatar_texture(peer_id)
		if texture:
			remote_players[peer_id].apply_avatar_texture(texture)
			print("PlayerNetworkComponent: Applied legacy avatar to remote player ", peer_id)

func _on_avatar_texture_received(peer_id: Variant) -> void:
	"""Handle avatar texture received for a remote player"""
	print("PlayerNetworkComponent: Avatar texture received for peer ", peer_id)
	
	# If player already spawned, apply the texture directly
	if remote_players.has(peer_id):
		# Access player data from NetworkManager's players dictionary
		if network_manager.players.has(peer_id):
			var player_data = network_manager.players[peer_id]
			
			# Try new multi-surface format first
			if player_data.has("avatar_textures"):
				remote_players[peer_id].apply_avatar_textures(player_data.avatar_textures)
				print("PlayerNetworkComponent: Applied avatar to remote player ", peer_id)
			# Fallback to legacy single texture if available
			elif player_data.has("avatar_texture_data"):
				var texture = network_manager.get_player_avatar_texture(peer_id)
				if texture:
					remote_players[peer_id].apply_avatar_texture(texture)
					print("PlayerNetworkComponent: Applied legacy avatar to remote player ", peer_id)
	else:
		# Player not spawned yet, will be applied when spawned
		print("PlayerNetworkComponent: Player ", peer_id, " not yet spawned, avatar will be applied on spawn")
	avatar_texture_received.emit(peer_id)
