# GameManager Autoload
# Manages global game state and scene transitions
extends Node

# Player state for scene transitions
var player_data: Dictionary = {}
var player_scene: PackedScene = preload("res://XRPlayer.tscn")


func _ready() -> void:
	# Ensure player is spawned in first scene
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	# When a new scene loads, check if it needs player spawning
	if node is Node3D and node.name.ends_with("Scene") or node.name.ends_with("Room"):
		call_deferred("_spawn_player_if_needed", node)


func _spawn_player_if_needed(scene_root: Node) -> void:
	# Wait a frame to ensure scene is fully loaded
	await get_tree().process_frame
	
	print("GameManager: Scene loaded - ", scene_root.name)
	
	# Check if player already exists in the NEW scene
	var existing_player = scene_root.get_tree().get_first_node_in_group("player")
	print("GameManager: Existing player in scene: ", existing_player != null)
	
	# If we have stored player data, we're transitioning scenes
	if player_data.has("spawn_point"):
		print("GameManager: Have spawn point data: ", player_data.get("spawn_point"))
		if existing_player:
			# Position the existing player at the spawn point
			print("GameManager: Repositioning existing player")
			_position_player_at_spawn(existing_player, scene_root)
		else:
			# No player in scene, spawn one
			print("GameManager: Spawning new player")
			var spawn_point = _find_spawn_point(scene_root)
			if spawn_point:
				_spawn_player(scene_root, spawn_point)
			else:
				print("GameManager: ERROR - No spawn point found!")
		# Clear player data after using it
		player_data.clear()
	else:
		print("GameManager: No spawn point data (first load or no transition)")
		# First scene load, player should already be in scene
		if not existing_player:
			# No player found, spawn one as fallback
			print("GameManager: No player found, spawning as fallback")
			var spawn_point = _find_spawn_point(scene_root)
			if spawn_point:
				_spawn_player(scene_root, spawn_point)


func change_scene_with_player(scene_path: String, player_state: Dictionary = {}) -> void:
	"""Change scene while preserving player state"""
	print("GameManager: Changing scene to ", scene_path)
	player_data = player_state.duplicate()
	
	# Get current player reference
	var current_player = get_tree().get_first_node_in_group("player")
	if current_player:
		# Store additional player data
		if current_player is RigidBody3D:
			player_data["velocity"] = current_player.linear_velocity
			player_data["angular_velocity"] = current_player.angular_velocity
		print("GameManager: Stored player state - spawn_point: ", player_data.get("spawn_point", "none"))
	
	# Change scene (this will destroy the old player)
	get_tree().change_scene_to_file(scene_path)


func _spawn_player(scene_root: Node, spawn_point: Node3D) -> void:
	"""Spawn a new player instance"""
	print("GameManager: _spawn_player called at ", spawn_point.global_position)
	
	# Ensure spawn point is in the tree and has valid transform
	if not spawn_point.is_inside_tree():
		push_warning("Spawn point not in scene tree yet, retrying...")
		await get_tree().process_frame
		if not spawn_point.is_inside_tree():
			push_error("Spawn point never entered tree!")
			return
	
	var player_instance = player_scene.instantiate()
	player_instance.name = "XRPlayer"
	player_instance.add_to_group("player")
	
	# Add to scene first
	scene_root.add_child(player_instance)
	print("GameManager: Player added to scene")
	
	# Then position at spawn point (after it's in the tree)
	await get_tree().process_frame
	player_instance.global_position = spawn_point.global_position
	print("GameManager: Player positioned at ", player_instance.global_position)
	
	# Apply stored velocity if available
	if player_data.has("velocity") and player_instance is RigidBody3D:
		player_instance.linear_velocity = player_data.get("velocity", Vector3.ZERO)
		print("GameManager: Applied velocity: ", player_instance.linear_velocity)


func _position_player_at_spawn(player: Node3D, scene_root: Node) -> void:
	"""Position existing player at the appropriate spawn point"""
	var spawn_name = player_data.get("spawn_point", "SpawnPoint")
	print("GameManager: _position_player_at_spawn - looking for spawn: ", spawn_name)
	var spawn_point = _find_spawn_point(scene_root, spawn_name)
	
	if not spawn_point:
		print("GameManager: ERROR - Spawn point not found!")
		return
	
	print("GameManager: Found spawn point at ", spawn_point.global_position)
	
	# Ensure spawn point has valid transform
	if not spawn_point.is_inside_tree():
		await get_tree().process_frame
	
	if spawn_point and player.has_method("teleport_to"):
		print("GameManager: Using teleport_to method")
		player.call_deferred("teleport_to", spawn_point.global_position)
	elif spawn_point:
		# Use call_deferred for physics objects
		if player is RigidBody3D:
			print("GameManager: Setting position via call_deferred")
			player.call_deferred("set_global_position", spawn_point.global_position)
		else:
			print("GameManager: Setting position directly")
			player.global_position = spawn_point.global_position


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
	return get_tree().get_first_node_in_group("player")
