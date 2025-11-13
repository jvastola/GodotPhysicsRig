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

	# Allow the world and player to finish initializing, then restore any saved grabbed objects
	call_deferred("_deferred_restore_saved_grabs")


func _deferred_restore_saved_grabs() -> void:
	# Run a couple frames to ensure nodes are ready
	await get_tree().process_frame
	await get_tree().process_frame
	# Guard: need SaveManager and current_world and player_instance
	if not SaveManager or not current_world or not player_instance:
		return

	var saved: Dictionary = SaveManager.get_all_grabbed_objects()
	if saved.is_empty():
		return

	for save_id in saved.keys():
		var entry = saved[save_id]
		if not entry.get("grabbed", false):
			continue
		# Previously we skipped restores when the saved scene didn't match the
		# currently loaded world. That caused misses when scenes are reparented
		# or scene file paths are not available at runtime. Instead, just try
		# to find the node by id in the current world and skip if it's not
		# present — that's more robust across different load flows.

		# Find node by save_id. Search all nodes in the 'grabbable' group and
		# match either the node.name or its `save_id` property. This is more
		# robust than relying on scene search paths which may vary at runtime.
		var target: Node = null
		var candidates := get_tree().get_nodes_in_group("grabbable")
		for c in candidates:
			if not is_instance_valid(c):
				continue
			var c_name := str(c.name)
			var c_save_id := ""
			if c.has_method("get") and c.get("save_id") != null:
				c_save_id = str(c.get("save_id"))
			if c_name == save_id or (c_save_id != "" and c_save_id == save_id):
				target = c
				break
		if not target:
			# Try to instantiate a saved prototype scene if provided in the save entry.
			var saved_scene_path := str(entry.get("scene", ""))
			var candidate_names: Array = []
			for x in candidates:
				if is_instance_valid(x):
					candidate_names.append(str(x.name))
			print("GameManager: Could not find saved grabbable node: ", save_id, ". Candidates: ", candidate_names)
			if saved_scene_path != "":
				# Attempt to load the saved resource. Only instantiate if it is a PackedScene
				var res = ResourceLoader.load(saved_scene_path)
				if res and res is PackedScene:
					var inst = res.instantiate()
					if inst:
						# Place instance in the current world and apply saved transform if available
						current_world.add_child(inst)
						# If the saved data includes a position/rotation array, apply it
						var pos = null
						var rot = null
						if entry.has("position") and entry["position"] is Array and entry["position"].size() >= 3:
							var p = entry["position"]
							pos = Vector3(p[0], p[1], p[2])
						if entry.has("rotation") and entry["rotation"] is Array and entry["rotation"].size() >= 4:
							var r = entry["rotation"]
							rot = Quaternion(r[0], r[1], r[2], r[3])
						if pos:
							inst.global_position = pos
						if rot:
							# Convert quaternion to basis
							inst.global_rotation = rot.get_euler()
						# If inst exposes a save_id property, set it to match the saved id
						var prop_list: Array = inst.get_property_list()
						var has_save_prop := false
						for p in prop_list:
							if p is Dictionary and p.has("name") and p["name"] == "save_id":
								has_save_prop = true
								break
						if has_save_prop:
							inst.set("save_id", save_id)
						# If the instance is grabbable, use it as target
						if inst.has_method("try_grab"):
							target = inst
							print("GameManager: Instantiated missing grabbable from ", saved_scene_path, " as ", inst.name)
						else:
							# Not a grabbable, remove to avoid clutter
							inst.queue_free()
					else:
						print("GameManager: Failed to instantiate resource: ", saved_scene_path)
				else:
					# If resource is not a PackedScene, skip instancing
					print("GameManager: Saved scene path is not a PackedScene or missing: ", saved_scene_path)
				# If we still have no target after this, continue to next saved id
			if not target:
				continue
		if not target.has_method("try_grab"):
			print("GameManager: Found node but it's not grabbable: ", save_id)
			continue

		# Determine which hand to restore to
		var hand_name: String = str(entry.get("hand", ""))
		var hand: Node = null
		if hand_name == "left":
			hand = player_instance.get_node_or_null("PhysicsHandLeft")
		elif hand_name == "right":
			hand = player_instance.get_node_or_null("PhysicsHandRight")
		else:
			# Fallback: prefer left hand
			hand = player_instance.get_node_or_null("PhysicsHandLeft")

		if not hand or not is_instance_valid(hand):
			print("GameManager: Could not find hand '" + str(hand_name) + "' to restore ", save_id)
			continue

		# Attempt to grab the object with the hand (deferred so _ready finishes)
		target.call_deferred("try_grab", hand)
		print("GameManager: Restored grabbed object ", save_id, " to hand ", hand_name)


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
