# GameManager Autoload
# Manages global game state and scene transitions
extends Node

var current_world: Node = null
var player_instance: Node = null


func _ready() -> void:
	print("GameManager: Ready")


func change_scene_with_player(scene_path: String, player_state: Dictionary = {}) -> void:
	"""Change the world scene while keeping the player intact"""
	print("GameManager: Changing world to ", scene_path)
	
	# Load the new world scene
	var new_world_scene = load(scene_path)
	if not new_world_scene:
		print("GameManager: ERROR - Could not load scene ", scene_path)
		return
	
	# Get or create player reference
	if not player_instance:
		player_instance = get_tree().get_first_node_in_group("player")
	
	# If player exists in a world scene, reparent to GameManager temporarily
	if player_instance and player_instance.get_parent() != self:
		var old_global_pos = player_instance.global_position
		var old_global_rot = player_instance.global_rotation
		player_instance.get_parent().remove_child(player_instance)
		add_child(player_instance)
		player_instance.global_position = old_global_pos
		player_instance.global_rotation = old_global_rot
	
	# Remove old world
	if current_world:
		current_world.queue_free()
		current_world = null
	
	# Instance and add new world
	current_world = new_world_scene.instantiate()
	get_tree().root.add_child(current_world)
	
	# Wait for world to be ready
	await get_tree().process_frame
	
	# Find spawn point and move player
	var spawn_name = player_state.get("spawn_point", "SpawnPoint")
	var spawn_point = _find_spawn_point(current_world, spawn_name)
	
	if spawn_point and player_instance:
		# Move player from GameManager to new world
		var target_pos = spawn_point.global_position
		remove_child(player_instance)
		current_world.add_child(player_instance)
		player_instance.global_position = target_pos
		print("GameManager: Player moved to new world at ", target_pos)
	else:
		print("GameManager: ERROR - No spawn point found!")


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
	return player_instance if player_instance else get_tree().get_first_node_in_group("player")
