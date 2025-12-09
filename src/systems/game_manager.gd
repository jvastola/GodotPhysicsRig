# GameManager Autoload
# Manages global game state and scene transitions
extends Node

var current_world: Node = null
var player_instance: Node = null
var _is_changing_scene: bool = false
var _fallback_environment: Environment = null

const PLAYER_SCENE_PATH := "res://src/player/XRPlayer.tscn"


func _ready() -> void:
	print("GameManager: Ready")
	# Track the initial scene as current_world
	call_deferred("_setup_initial_world")


func _setup_initial_world() -> void:
	"""Set up tracking for the initial scene"""
	await get_tree().process_frame
	current_world = get_tree().current_scene
	_cache_fallback_environment_from(current_world)
	
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
	print("GameManager: _deferred_restore_saved_grabs running")
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
		# Diagnostic output for saved entry
		print("GameManager: Restore entry for ", save_id, ": ", entry)
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
		
		# If target exists and is already grabbed, skip restoration (already preserved)
		if target and target.has_method("get") and target.get("is_grabbed"):
			print("GameManager: Object ", save_id, " already grabbed, skipping restore")
			continue
		
		if not target:
			# Try to instantiate a saved prototype scene if provided in the save entry.
			var saved_scene_path := str(entry.get("scene", ""))
			var candidate_names: Array = []
			for x in candidates:
				if is_instance_valid(x):
					candidate_names.append(str(x.name))
			print("GameManager: Could not find saved grabbable node: ", save_id, ". Candidates: ", candidate_names)
			if saved_scene_path != "":
				print("GameManager: saved scene path present for ", save_id, ": ", saved_scene_path)
				# Attempt to load the saved resource. Only instantiate if it is a PackedScene
				var res = ResourceLoader.load(saved_scene_path)
				if res and res is PackedScene:
					var inst = res.instantiate()
					if inst:
						# Place instance in the current world and apply saved transform if available
						current_world.add_child(inst)
						# If the saved data includes a position/rotation array, apply it
						var has_pos := false
						var has_rot := false
						var pos: Vector3 = Vector3.ZERO
						var quat: Quaternion = Quaternion.IDENTITY
						if entry.has("position") and entry["position"] is Array and entry["position"].size() >= 3:
							var p = entry["position"]
							pos = Vector3(p[0], p[1], p[2])
							has_pos = true
						if entry.has("rotation") and entry["rotation"] is Array and entry["rotation"].size() >= 4:
							var r = entry["rotation"]
							quat = Quaternion(r[0], r[1], r[2], r[3])
							has_rot = true
						# Prefer setting the full global_transform when both are present
						if has_pos and has_rot:
							inst.global_transform = Transform3D(Basis(quat), pos)
						else:
							if has_pos:
								inst.global_position = pos
							if has_rot:
								inst.global_rotation = quat.get_euler()
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
			# If instantiation from saved_scene_path did not yield a target, try fallback
			if not target:
				var proto_path := _find_prototype_scene_for_save_id(save_id)
				if proto_path != "":
					print("GameManager: Found prototype fallback for ", save_id, ": ", proto_path)
					var proto_res = ResourceLoader.load(proto_path)
					if proto_res and proto_res is PackedScene:
						var proto_inst = proto_res.instantiate()
						if proto_inst:
							current_world.add_child(proto_inst)
							# Apply saved transform using full Transform3D when both position and rotation are available
							var has_pos2 := false
							var has_rot2 := false
							var pos2: Vector3 = Vector3.ZERO
							var quat2: Quaternion = Quaternion.IDENTITY
							if entry.has("position") and entry["position"] is Array and entry["position"].size() >= 3:
								var pp = entry["position"]
								pos2 = Vector3(pp[0], pp[1], pp[2])
								has_pos2 = true
							if entry.has("rotation") and entry["rotation"] is Array and entry["rotation"].size() >= 4:
								var rr = entry["rotation"]
								quat2 = Quaternion(rr[0], rr[1], rr[2], rr[3])
								has_rot2 = true
							if has_pos2 and has_rot2:
								proto_inst.global_transform = Transform3D(Basis(quat2), pos2)
							else:
								if has_pos2:
									proto_inst.global_position = pos2
								if has_rot2:
									proto_inst.global_rotation = quat2.get_euler()
							# set save_id if present
							var props: Array = proto_inst.get_property_list()
							var has_save := false
							for pr in props:
								if pr is Dictionary and pr.has("name") and pr["name"] == "save_id":
									has_save = true
									break
							if has_save:
								proto_inst.set("save_id", save_id)
							if proto_inst.has_method("try_grab"):
								target = proto_inst
								print("GameManager: Fallback instantiated and will use: ", proto_inst.name)
							else:
								proto_inst.queue_free()
					else:
						print("GameManager: Failed to load/instantiate prototype: ", proto_path)
				else:
					print("GameManager: No prototype fallback for ", save_id)
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

		# If the save contains a transform relative to the hand, apply it so
		# the object will align correctly when the hand computes offsets.
		if entry.has("relative_position") and entry.has("relative_rotation") and entry["relative_position"] is Array and entry["relative_rotation"] is Array and entry["relative_position"].size() == 3 and entry["relative_rotation"].size() == 4:
			var rp = entry["relative_position"]
			var rr = entry["relative_rotation"]
			var rel_pos = Vector3(rp[0], rp[1], rp[2])
			var rel_quat = Quaternion(rr[0], rr[1], rr[2], rr[3])
			# Debug: log hand and saved relative transforms
			if is_instance_valid(hand):
				print("GameManager: Restoring ", save_id, " to hand ", hand_name)
				print("  - hand global_transform: ", hand.global_transform)
				print("  - saved relative pos/quaternion: ", rel_pos, rel_quat)
			# Compute world transform so that: world_tf = hand.global_transform * rel_tf
			var rel_tf = Transform3D(Basis(rel_quat), rel_pos)
			if is_instance_valid(hand):
				var computed_world: Transform3D = hand.global_transform * rel_tf
				# Debug: computed world transform we're about to apply
				print("  - computed world transform: ", computed_world)
				target.global_transform = computed_world
				print("GameManager: Applied relative transform for ", save_id)
		# Attempt to grab the object with the hand (deferred so _ready finishes)
		target.call_deferred("try_grab", hand)
		print("GameManager: Restored grabbed object ", save_id, " to hand ", hand_name)


func _wrap_world_if_needed(world_root: Node) -> Node:
	"""Ensure the world root has a transform. If the instantiated root is not a Node3D,
	wrap it in a Node3D so systems that expect a transformable world root don't crash."""
	if world_root is Node3D:
		return world_root
	var wrapper := Node3D.new()
	wrapper.name = str(world_root.name)
	return wrapper


func _get_world_grabbables(world_root: Node) -> Array:
	"""Return all grabbable descendants of the world root."""
	var result: Array = []
	var queue: Array = [world_root]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		for child in node.get_children():
			queue.append(child)
			if child.is_in_group("grabbable"):
				result.append(child)
	return result


func change_scene_with_player(scene_path: String, player_state: Dictionary = {}) -> void:
	"""Change the world scene while keeping the player intact"""
	print("GameManager: change_scene_with_player called with path=", scene_path, " player_state=", player_state)
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
	if not (new_world_scene is PackedScene):
		print("GameManager: ERROR - Loaded resource is not a PackedScene: ", new_world_scene)
		return
	print("GameManager: Loaded PackedScene OK: ", new_world_scene.resource_path if new_world_scene is Resource else "<no path>")
	
	# Ensure we have a cached environment before removing the current world
	_cache_fallback_environment_from(current_world)
	print("GameManager: _cache_fallback_environment_from done; fallback env exists? ", _fallback_environment != null)
	
	# Get or find player reference
	if not player_instance:
		var player_body = get_tree().get_first_node_in_group("player")
		print("GameManager: player_instance missing; got player_body from group? ", player_body)
		if player_body:
			player_instance = player_body.get_parent()  # Get XRPlayer, not PlayerBody
	
	if not player_instance:
		# Attempt to instantiate a fallback XRPlayer so scene changes do not crash
		var player_res = ResourceLoader.load(PLAYER_SCENE_PATH)
		if player_res and player_res is PackedScene:
			player_instance = player_res.instantiate()
			if player_instance:
				add_child(player_instance)
				print("GameManager: Instantiated fallback XRPlayer from ", PLAYER_SCENE_PATH)
			else:
				print("GameManager: Fallback XRPlayer instantiation returned null")
		else:
			print("GameManager: Could not load fallback XRPlayer at ", PLAYER_SCENE_PATH)
		if not player_instance:
			print("GameManager: ERROR - No player found and fallback XRPlayer could not be instantiated!")
			return
	else:
		print("GameManager: player_instance present: ", player_instance.name)
	
	# Reparent player to GameManager temporarily to preserve it
	var old_global_pos = player_instance.global_position
	var old_global_rot = player_instance.global_rotation
	var player_parent = player_instance.get_parent()
	print("GameManager: player_parent before reparent: ", player_parent)
	
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
	print("GameManager: total grabbed_objects preserved: ", grabbed_objects.size())
	
	if player_parent and player_parent != self:
		player_parent.remove_child(player_instance)
		add_child(player_instance)
		player_instance.global_position = old_global_pos
		player_instance.global_rotation = old_global_rot
		print("GameManager: Player temporarily moved to GameManager")
	elif player_parent == self:
		print("GameManager: Player already parented to GameManager")
	else:
		print("GameManager: No player_parent found during reparent step")
	
	# Remove old world
	if current_world:
		print("GameManager: Removing old world: ", current_world.name)
		current_world.queue_free()
		current_world = null
	else:
		print("GameManager: No current_world to remove (first load?)")
	
	# Instance new world
	var raw_world: Node = new_world_scene.instantiate()
	if not raw_world:
		print("GameManager: ERROR - instantiate() returned null for ", scene_path)
		_is_changing_scene = false
		return
	print("GameManager: instantiate() returned: ", raw_world, " class: ", raw_world.get_class())
	current_world = _wrap_world_if_needed(raw_world)
	print("GameManager: _wrap_world_if_needed => ", current_world, " class: ", current_world.get_class())
	get_tree().root.add_child(current_world)
	if current_world != raw_world:
		current_world.add_child(raw_world)
		print("GameManager: Wrapped world ", raw_world.name, " in a Node3D container for transforms")
	
	# Ensure the new world has an environment; if missing, apply the cached main-scene one
	_ensure_world_environment(current_world)
	var env_node_debug = _find_world_environment(current_world)
	print("GameManager: Post-load environment node: ", env_node_debug, " (null means none)")
	# Keep SceneTree's current_scene in sync so helpers relying on it keep working
	if get_tree().current_scene != current_world:
		get_tree().set_current_scene(current_world)
	print("GameManager: New world loaded: ", current_world.name)
	if get_tree().current_scene:
		print("GameManager: SceneTree current_scene: ", get_tree().current_scene.name)
	else:
		print("GameManager: WARNING - SceneTree current_scene is null after load")
	
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
	
	# Remove any grabbable objects from the new scene that we already have preserved
	# (prevents duplicates when returning to a scene that has the same grabbable)
	print("GameManager: Checking duplicates in new scene; preserved count=", grabbed_objects.size())
	for preserved_obj in grabbed_objects:
		if not is_instance_valid(preserved_obj):
			continue
		var preserved_name = preserved_obj.name
		var preserved_save_id = ""
		if preserved_obj.has_method("get") and preserved_obj.get("save_id") != null:
			preserved_save_id = str(preserved_obj.get("save_id"))
		
		# Find and remove duplicates in the new scene
		for scene_grabbable in _get_world_grabbables(current_world):
			if not is_instance_valid(scene_grabbable):
				continue
			if scene_grabbable == preserved_obj:
				continue
			if not scene_grabbable.is_in_group("grabbable"):
				continue
			
			var scene_name = scene_grabbable.name
			var scene_save_id = ""
			if scene_grabbable.has_method("get") and scene_grabbable.get("save_id") != null:
				scene_save_id = str(scene_grabbable.get("save_id"))
			
			# Check if this is a duplicate (same name or same save_id)
			if scene_name == preserved_name or (preserved_save_id != "" and scene_save_id == preserved_save_id):
				print("GameManager: Removing duplicate grabbable from new scene: ", scene_name)
				scene_grabbable.queue_free()
	
	await get_tree().process_frame
	
	# Move grabbed objects back to the new world
	print("GameManager: Restoring grabbed_objects to new world; count=", grabbed_objects.size())
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
	# If we just entered the main scene, schedule restoration of saved grabs
	var joined_main := false
	if typeof(scene_path) == TYPE_STRING and scene_path.find("MainScene.tscn") != -1:
		joined_main = true
	elif current_world and current_world.name == "MainScene":
		joined_main = true
	if joined_main:
		print("GameManager: Entered MainScene — scheduling saved-grabbable restore")
		call_deferred("_deferred_restore_saved_grabs")
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


func _find_prototype_scene_for_save_id(save_id: String) -> String:
	"""Search `res://src/objects/grabbables` for a PackedScene whose root node matches the saved id.
	If found, instantiate it. Otherwise return null."""
	
	var dir := DirAccess.open("res://src/objects/grabbables")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tscn"):
				var path: String = "res://src/objects/grabbables/" + file_name
				var res = ResourceLoader.load(path)
				if res and res is PackedScene:
					var tmp = res.instantiate()
					if tmp:
						var matched := false
						# Check name match
						if str(tmp.name) == save_id:
							matched = true
						# Check save_id property if present
						if not matched and tmp.has_method("get") and tmp.get("save_id") != null:
							if str(tmp.get("save_id")) == save_id:
								matched = true
						if matched:
							tmp.queue_free()
							dir.list_dir_end()
							return path
						tmp.queue_free()
		file_name = dir.get_next()
	dir.list_dir_end()
	return ""


func get_player() -> Node:
	"""Get the current player node"""
	if player_instance:
		return player_instance
	
	# Try to find it
	var player_body = get_tree().get_first_node_in_group("player")
	if player_body:
		return player_body.get_parent()  # Return XRPlayer, not PlayerBody
	
	return null


func _cache_fallback_environment_from(world_root: Node) -> void:
	"""Cache the Environment resource from the current world (typically MainScene) for reuse."""
	if _fallback_environment or not world_root:
		return
	var env_node := _find_world_environment(world_root)
	if env_node and env_node.environment:
		_fallback_environment = env_node.environment.duplicate()
		print("GameManager: Cached fallback WorldEnvironment from ", world_root.name)


func _ensure_world_environment(world_root: Node) -> void:
	"""If the world has no Environment, apply the cached main-scene Environment."""
	if not world_root:
		print("GameManager: _ensure_world_environment called with null world_root")
		return
	var env_node := _find_world_environment(world_root)
	if env_node and env_node.environment:
		print("GameManager: _ensure_world_environment found existing environment on ", world_root.name)
		return
	
	if not _fallback_environment:
		print("GameManager: No fallback WorldEnvironment available; scene will use default environment")
		return
	
	var new_env := WorldEnvironment.new()
	new_env.name = "FallbackWorldEnvironment"
	new_env.environment = _fallback_environment.duplicate()
	world_root.add_child(new_env)
	print("GameManager: Applied fallback WorldEnvironment to ", world_root.name)


func _find_world_environment(world_root: Node) -> WorldEnvironment:
	"""Locate a WorldEnvironment node within the given world."""
	if not world_root:
		return null
	if world_root is WorldEnvironment:
		return world_root
	var found = world_root.find_child("WorldEnvironment", true, false)
	if found and found is WorldEnvironment:
		return found
	return null
