# GameManager Autoload
# Manages global game state and scene transitions
extends Node

var current_world: Node = null
var player_instance: Node = null


func _ready() -> void:
	print("GameManager: Ready")
	# Track the initial scene as current_world
	call_deferred("_setup_initial_world")


func _setup_initial_world() -> void:
	"""Set up tracking for the initial scene"""
	await get_tree().process_frame
	current_world = get_tree().current_scene
	
	# Find the XRPlayer root node (PlayerBody is in "player" group, but we need its parent)
	var player_body = get_tree().get_first_node_in_group("player")
	if player_body:
		player_instance = player_body.get_parent()  # Get XRPlayer, not PlayerBody
	
	if current_world:
		print("GameManager: Initial world tracked: ", current_world.name)
	if player_instance:
		print("GameManager: Initial player tracked: ", player_instance.name)


func change_scene_with_player(scene_path: String, player_state: Dictionary = {}) -> void:
	"""Change the world scene while keeping the player intact"""
	print("GameManager: Changing world to ", scene_path)
	
	# Load the new world scene
	var new_world_scene = load(scene_path)
	if not new_world_scene:
		print("GameManager: ERROR - Could not load scene ", scene_path)
		return
	
	# Get or find player reference
	if not player_instance:
		var player_body = get_tree().get_first_node_in_group("player")
		if player_body:
			player_instance = player_body.get_parent()  # Get XRPlayer, not PlayerBody
	
	if not player_instance:
		print("GameManager: ERROR - No player found!")
		return
	
	# Reparent player to GameManager temporarily to preserve it
	var old_global_pos = player_instance.global_position
	var old_global_rot = player_instance.global_rotation
	var player_parent = player_instance.get_parent()
	
	if player_parent and player_parent != self:
		player_parent.remove_child(player_instance)
		add_child(player_instance)
		player_instance.global_position = old_global_pos
		player_instance.global_rotation = old_global_rot
		print("GameManager: Player temporarily moved to GameManager")
	
	# Remove old world
	if current_world:
		print("GameManager: Removing old world: ", current_world.name)
		current_world.queue_free()
		current_world = null
	
	# Instance new world
	current_world = new_world_scene.instantiate()
	get_tree().root.add_child(current_world)
	print("GameManager: New world loaded: ", current_world.name)
	
	# Wait for world to be fully ready with physics
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	
	# Remove any player instance that came with the new world scene
	var scene_player = current_world.get_node_or_null("XRPlayer")
	if scene_player and scene_player != player_instance:
		print("GameManager: Removing duplicate player from new scene")
		scene_player.queue_free()
		await get_tree().process_frame
	
	# Find spawn point and move player to new world
	var spawn_name = player_state.get("spawn_point", "SpawnPoint")
	var spawn_point = _find_spawn_point(current_world, spawn_name)
	
	if spawn_point:
		# Move player from GameManager to new world
		var target_pos = spawn_point.global_position
		remove_child(player_instance)
		current_world.add_child(player_instance)
		
		# Wait for player to be in tree
		await get_tree().process_frame
		
		# Set position and freeze PlayerBody briefly to prevent falling
		var player_body = player_instance.get_node_or_null("PlayerBody")
		if player_body and player_body is RigidBody3D:
			player_body.freeze = true
			player_instance.global_position = target_pos
			await get_tree().physics_frame
			await get_tree().physics_frame
			player_body.linear_velocity = Vector3.ZERO
			player_body.angular_velocity = Vector3.ZERO
			player_body.freeze = false
		else:
			player_instance.global_position = target_pos
		
		print("GameManager: Player moved to new world at ", target_pos)
	else:
		# No spawn point, just move player to new world at origin
		remove_child(player_instance)
		current_world.add_child(player_instance)
		await get_tree().process_frame
		
		var player_body = player_instance.get_node_or_null("PlayerBody")
		if player_body and player_body is RigidBody3D:
			player_body.freeze = true
			player_instance.global_position = Vector3.ZERO
			await get_tree().physics_frame
			player_body.linear_velocity = Vector3.ZERO
			player_body.freeze = false
		else:
			player_instance.global_position = Vector3.ZERO
		
		print("GameManager: WARNING - No spawn point found, player at origin")


func _find_spawn_point(scene_root: Node, spawn_name: String = "SpawnPoint") -> Node3D:
	"""Find a spawn point in the scene"""
	# First try to find by exact name
	var spawn = scene_root.find_child(spawn_name, true, false)
	if spawn and spawn is Node3D:
		return spawn
	
	# Fallback to any Marker3D named SpawnPoint
	spawn = scene_root.find_child("SpawnPoint", true, false)
	if spawn and spawn is Node3D:
		return spawn
	
	return null


func get_player() -> Node:
	"""Get the current player node"""
	if player_instance:
		return player_instance
	
	# Try to find it
	var player_body = get_tree().get_first_node_in_group("player")
	if player_body:
		return player_body.get_parent()  # Return XRPlayer, not PlayerBody
	
	return null
