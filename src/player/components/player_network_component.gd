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
	"""Initialize networking connections"""
	network_manager = get_node_or_null("/root/NetworkManager")
	
	if not network_manager:
		print("PlayerNetworkComponent: NetworkManager not found, multiplayer disabled")
		return
	
	# Connect to network events
	network_manager.player_connected.connect(_on_player_connected)
	network_manager.player_disconnected.connect(_on_player_disconnected)
	network_manager.avatar_texture_received.connect(_on_avatar_texture_received)
	
	print("PlayerNetworkComponent: Networking initialized")

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
	"""Send local player's avatar texture to all other players"""
	if not network_manager:
		return
	
	# Try multiple ways to find GridPainter
	var grid_painter = get_node_or_null("../GridPainter") # Assuming sibling or similar
	if not grid_painter:
		grid_painter = get_tree().root.get_node_or_null("MainScene/GridPainterTest")
	if not grid_painter:
		grid_painter = get_tree().root.get_node_or_null("MainScene/GridPainter")
	if not grid_painter:
		# Try finding by type or class name
		for node in get_tree().get_nodes_in_group("grid_painter"):
			grid_painter = node
			break
	if not grid_painter:
		# Last resort: search for GridPainter type
		var root = get_tree().root
		for child in root.get_children():
			if child is Node3D:
				var found = _find_grid_painter_recursive(child)
				if found:
					grid_painter = found
					break
	
	if not grid_painter:
		print("PlayerNetworkComponent: GridPainter not found, cannot send avatar")
		return
	
	# Get head surface texture
	if not grid_painter.has_method("_get_surface"):
		print("PlayerNetworkComponent: GridPainter doesn't have _get_surface method")
		return
	
	var head_surface = grid_painter._get_surface("head")
	if not head_surface or not head_surface.texture:
		print("PlayerNetworkComponent: No head texture found, paint your head first!")
		return
	
	network_manager.set_local_avatar_texture(head_surface.texture)
	print("PlayerNetworkComponent: Sent avatar texture to network")

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
	remote_players[peer_id] = remote_player
	
	print("PlayerNetworkComponent: Spawned remote player ", peer_id)
	
	# Try to apply their avatar texture
	call_deferred("_apply_remote_avatar", peer_id)

func _apply_remote_avatar(peer_id: Variant) -> void:
	"""Apply avatar texture to a remote player"""
	if not network_manager or not remote_players.has(peer_id):
		return
	
	var texture = network_manager.get_player_avatar_texture(peer_id)
	if texture:
		remote_players[peer_id].apply_avatar_texture(texture)
		print("PlayerNetworkComponent: Applied avatar to remote player ", peer_id)

func _on_avatar_texture_received(peer_id: Variant) -> void:
	"""Called when a remote player's avatar texture is received"""
	print("PlayerNetworkComponent: Avatar texture received for peer ", peer_id)
	_apply_remote_avatar(peer_id)
	avatar_texture_received.emit(peer_id)
