# GameManager Autoload
# Manages global game state and scene transitions
extends Node

var current_world: Node = null
var player_instance: Node = null
var _is_changing_scene: bool = false


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
	# Prevent re-entrant scene changes
	if _is_changing_scene:
		print("GameManager: change_scene_with_player ignored - already changing scene")
		return
	_is_changing_scene = true
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
	
	# Find and preserve all grabbed objects by moving them to GameManager temporarily
	var grabbed_objects = []
	for obj in get_tree().get_nodes_in_group("grabbable"):
		if obj.has_method("get") and obj.get("is_grabbed"):
			grabbed_objects.append(obj)
			var obj_parent = obj.get_parent()
			if obj_parent:
				var obj_transform = obj.global_transform
				obj_parent.remove_child(obj)
				add_child(obj)
				obj.global_transform = obj_transform
				print("GameManager: Preserved grabbed object: ", obj.name)
	
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
	
	# Move grabbed objects back to the new world
	for obj in grabbed_objects:
		if is_instance_valid(obj):
			var obj_transform = obj.global_transform
			remove_child(obj)
			current_world.add_child(obj)
			obj.global_transform = obj_transform
			print("GameManager: Restored grabbed object to new world: ", obj.name)
	
	# Find spawn point and move player to new world
	# Determine whether to use a spawn point or maintain player's previous global position
	var use_spawn: bool = player_state.get("use_spawn_point", false)
	var spawn_name = player_state.get("spawn_point", "SpawnPoint")
	print("GameManager: spawn request - use_spawn=", use_spawn, ", spawn_name=", spawn_name)
	var spawn_point: Node3D = null
	if use_spawn:
		spawn_point = _find_spawn_point(current_world, spawn_name)
		print("GameManager: _find_spawn_point returned: ", spawn_point)
		if spawn_point:
			var target_pos = spawn_point.global_position
			print("GameManager: spawn_point global_position=", target_pos)
			# Reparent player into new world
			if player_instance.get_parent() == self:
				remove_child(player_instance)
			if player_instance.get_parent() != current_world:
				current_world.add_child(player_instance)
			await get_tree().process_frame
			var player_body = player_instance.get_node_or_null("PlayerBody")
			if player_body and player_body is RigidBody3D:
				player_body.freeze = true
				# Prefer a teleport method on the player (handles XR offsets) if available
				if player_instance.has_method("teleport_to"):
					player_instance.call_deferred("teleport_to", target_pos)
					print("GameManager: used XRPlayer.teleport_to for teleport")
				else:
					player_instance.global_position = target_pos
					print("GameManager: set player_instance.global_position = ", target_pos)
				await get_tree().physics_frame
				await get_tree().physics_frame
				player_body.linear_velocity = Vector3.ZERO
				player_body.angular_velocity = Vector3.ZERO
				player_body.freeze = false
			else:
				if player_instance.has_method("teleport_to"):
					player_instance.call_deferred("teleport_to", target_pos)
				else:
					player_instance.global_position = target_pos
			print("GameManager: Player moved to spawn point in new world at ", target_pos)
			# Debug: confirm player's actual global position after move
			print("GameManager: player global position after move = ", player_instance.global_position)
		else:
			print("GameManager: WARNING - use_spawn_point requested but spawn not found: ", spawn_name)
			# Fallback: reparent and keep old global position
			if player_instance.get_parent() == self:
				remove_child(player_instance)
			if player_instance.get_parent() != current_world:
				current_world.add_child(player_instance)
			await get_tree().process_frame
			var player_body2 = player_instance.get_node_or_null("PlayerBody")
			if player_body2 and player_body2 is RigidBody3D:
				player_body2.freeze = true
				if player_instance.has_method("teleport_to"):
					player_instance.call_deferred("teleport_to", old_global_pos)
				else:
					player_instance.global_position = old_global_pos
				await get_tree().physics_frame
				player_body2.linear_velocity = Vector3.ZERO
				player_body2.freeze = false
			else:
				if player_instance.has_method("teleport_to"):
					player_instance.call_deferred("teleport_to", old_global_pos)
				else:
					player_instance.global_position = old_global_pos
			print("GameManager: Player restored to previous global position at ", old_global_pos)
			print("GameManager: player global position after restore = ", player_instance.global_position)
	else:
		# Maintain player's previous global position across the world swap
		if player_instance.get_parent() == self:
			remove_child(player_instance)
		if player_instance.get_parent() != current_world:
			current_world.add_child(player_instance)
		await get_tree().process_frame
		var player_body3 = player_instance.get_node_or_null("PlayerBody")
		if player_body3 and player_body3 is RigidBody3D:
			player_body3.freeze = true
			if player_instance.has_method("teleport_to"):
				player_instance.call_deferred("teleport_to", old_global_pos)
			else:
				player_instance.global_position = old_global_pos
			await get_tree().physics_frame
			player_body3.linear_velocity = Vector3.ZERO
			player_body3.angular_velocity = Vector3.ZERO
			player_body3.freeze = false
		else:
			if player_instance.has_method("teleport_to"):
				player_instance.call_deferred("teleport_to", old_global_pos)
			else:
				player_instance.global_position = old_global_pos
		print("GameManager: Player maintained previous global position at ", old_global_pos)

	# Finished changing scene
	_is_changing_scene = false


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
