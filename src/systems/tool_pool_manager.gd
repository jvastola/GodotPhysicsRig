class_name ToolPoolManager
extends Node

# Centralized pooling for grabbable tools. Enforces spawn limits and recycles
# instances instead of letting duplicates pile up.

const TOOL_CONFIG := {
	"poly_tool": {
		"scene": "res://src/objects/grabbables/PolyTool.tscn",
		"default_limit": 1,
	},
	"convex_hull": {
		"scene": "res://src/objects/grabbables/ConvexHullPen.tscn",
		"default_limit": 1,
	},
	"volume_hull": {
		"scene": "res://src/objects/grabbables/VolumeHullPen.tscn",
		"default_limit": 1,
	},
	"voxel_tool": {
		"scene": "res://src/objects/VoxelTool.tscn",
		"default_limit": 1,
	},
}

signal spawn_limit_reached(scene_path: String, current_count: int, limit: int)
signal scene_spawned(scene_path: String, node: Node)
signal scene_removed(scene_path: String, node: Node)

static var instance: ToolPoolManager

var _pools: Dictionary = {} # tool_type -> { active: Array, pooled: Array, limit: int }
var _pool_root: Node

# Scene spawn tracking (for FileSystemUI spawned scenes)
var _spawned_scenes: Array[Node] = []
var _max_spawned_scenes: int = 0  # Conservative for VR performance (VRCS compliance)

# World object limits (configurable for VR performance)
var _max_hulls: int = 5  # Default max hulls in scene
var _max_voxels: int = 500  # Default max voxels in scene
var _max_polys: int = 10  # Default max poly triangles


func _ready() -> void:
	instance = self
	_pool_root = Node.new()
	_pool_root.name = "ToolPool"
	add_child(_pool_root)
	_init_defaults()


func _exit_tree() -> void:
	if instance == self:
		instance = null


static func find() -> ToolPoolManager:
	if instance and is_instance_valid(instance):
		return instance
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return null
	var root := tree.root
	if not root:
		return null
	var found := root.find_child("ToolPoolManager", true, false)
	if found and found is ToolPoolManager:
		instance = found
		return instance
	return null


func register_instance(tool_type: String, node: Node) -> void:
	if not node:
		return
	var data := _ensure_pool(tool_type)
	if node in data.active:
		return
	_remove_from_all_lists(node)
	data.active.append(node)
	# Keep newest at the end of the list; oldest will be pooled first.
	node.tree_exited.connect(func(): _remove_from_all_lists(node), CONNECT_ONE_SHOT)
	_enforce_limit(tool_type)


func unregister_instance(tool_type: String, node: Node) -> void:
	if not node:
		return
	if not _pools.has(tool_type):
		return
	_pools[tool_type].active.erase(node)
	_pools[tool_type].pooled.erase(node)


func set_limit(tool_type: String, limit: int) -> void:
	var data := _ensure_pool(tool_type)
	data.limit = max(0, limit)
	_enforce_limit(tool_type)


func get_limit(tool_type: String) -> int:
	return _ensure_pool(tool_type).limit


func get_counts(tool_type: String) -> Dictionary:
	var data := _ensure_pool(tool_type)
	return {
		"active": data.active.size(),
		"pooled": data.pooled.size(),
		"limit": data.limit,
	}


func request_scene_instance(scene_path: String, parent: Node, transform: Transform3D = Transform3D.IDENTITY) -> Node:
	var tool_type := _tool_type_for_scene(scene_path)
	if tool_type == "":
		return null
	var data := _ensure_pool(tool_type)
	var node: Node = null
	if not data.pooled.is_empty():
		node = data.pooled.pop_back()
		if node and is_instance_valid(node):
			_activate_node(node, parent)
			register_instance(tool_type, node)
	else:
		var packed := ResourceLoader.load(scene_path) as PackedScene
		if packed:
			node = packed.instantiate()
			if parent:
				parent.add_child(node)
		if node:
			# If the node implements its own registration in _ready, skip double-registration.
			register_instance(tool_type, node)
	if node:
		if node is Node3D:
			(node as Node3D).global_transform = transform
		_enforce_limit(tool_type)
	return node


func force_pool_all(tool_type: String) -> void:
	var data := _ensure_pool(tool_type)
	for node in data.active.duplicate():
		_move_to_pool(tool_type, node)


func tracked_tool_types() -> Array[String]:
	return TOOL_CONFIG.keys()


func _init_defaults() -> void:
	for tool_type in TOOL_CONFIG.keys():
		var defaults: Dictionary = TOOL_CONFIG[tool_type]
		_pools[tool_type] = {
			"active": [],
			"pooled": [],
			"limit": defaults.get("default_limit", 1),
		}


func _ensure_pool(tool_type: String) -> Dictionary:
	if not _pools.has(tool_type):
		_pools[tool_type] = { "active": [], "pooled": [], "limit": 1 }
	return _pools[tool_type]


func _enforce_limit(tool_type: String) -> void:
	var data := _ensure_pool(tool_type)
	while data.active.size() > data.limit:
		var oldest: Node = data.active.pop_front()
		_move_to_pool(tool_type, oldest)


func _move_to_pool(tool_type: String, node: Node) -> void:
	if not node or not is_instance_valid(node):
		return
	var data := _ensure_pool(tool_type)
	data.active.erase(node)
	if node.get_parent():
		node.get_parent().call_deferred("remove_child", node)
	_pool_root.call_deferred("add_child", node)
	_set_node_active(node, false)
	if node.has_method("on_pooled"):
		node.call_deferred("on_pooled")
	data.pooled.append(node)


func _activate_node(node: Node, parent: Node) -> void:
	if not node or not is_instance_valid(node):
		return
	if node.get_parent():
		node.get_parent().call_deferred("remove_child", node)
	if parent:
		parent.call_deferred("add_child", node)
	_set_node_active(node, true)
	if node.has_method("on_unpooled"):
		node.call_deferred("on_unpooled")


func _set_node_active(node: Node, active: bool) -> void:
	if node is Node3D:
		(node as Node3D).visible = active
	if node.has_method("set_physics_process"):
		node.set_physics_process(active)
	if node is RigidBody3D:
		var body := node as RigidBody3D
		body.sleeping = not active
		body.freeze = not active


func _remove_from_all_lists(node: Node) -> void:
	for tool_type in _pools.keys():
		_pools[tool_type].active.erase(node)
		_pools[tool_type].pooled.erase(node)


func _tool_type_for_scene(scene_path: String) -> String:
	for tool_type in TOOL_CONFIG.keys():
		var cfg: Dictionary = TOOL_CONFIG[tool_type]
		if cfg.get("scene", "") == scene_path:
			return tool_type
	return ""


# =============================================================================
# Scene Spawn Tracking (for FileSystemUI)
# =============================================================================

func can_spawn_scene() -> bool:
	"""Returns true if another scene can be spawned within limits."""
	_cleanup_invalid_spawned_scenes()
	return _spawned_scenes.size() < _max_spawned_scenes


func get_spawned_scene_count() -> int:
	"""Returns current number of spawned scenes."""
	_cleanup_invalid_spawned_scenes()
	return _spawned_scenes.size()


func get_max_spawned_scenes() -> int:
	"""Returns the maximum allowed spawned scenes."""
	return _max_spawned_scenes


func set_max_spawned_scenes(limit: int) -> void:
	"""Sets the maximum allowed spawned scenes."""
	_max_spawned_scenes = max(0, limit)


func register_spawned_scene(node: Node, scene_path: String = "") -> bool:
	"""Register a spawned scene. Returns false if limit is reached."""
	_cleanup_invalid_spawned_scenes()
	if _spawned_scenes.size() >= _max_spawned_scenes:
		spawn_limit_reached.emit(scene_path, _spawned_scenes.size(), _max_spawned_scenes)
		return false
	if node and is_instance_valid(node) and node not in _spawned_scenes:
		_spawned_scenes.append(node)
		node.tree_exited.connect(func(): _on_spawned_scene_exited(node, scene_path), CONNECT_ONE_SHOT)
		scene_spawned.emit(scene_path, node)
	return true


func unregister_spawned_scene(node: Node, scene_path: String = "") -> void:
	"""Unregister a spawned scene."""
	if node in _spawned_scenes:
		_spawned_scenes.erase(node)
		scene_removed.emit(scene_path, node)


func clear_all_spawned_scenes() -> void:
	"""Remove all spawned scenes from the world."""
	for node in _spawned_scenes.duplicate():
		if is_instance_valid(node):
			node.queue_free()
	_spawned_scenes.clear()


func _on_spawned_scene_exited(node: Node, scene_path: String) -> void:
	"""Called when a spawned scene exits the tree."""
	_spawned_scenes.erase(node)
	scene_removed.emit(scene_path, node)


func _cleanup_invalid_spawned_scenes() -> void:
	"""Remove invalid references from the spawned scenes list."""
	var valid_scenes: Array[Node] = []
	for node in _spawned_scenes:
		if is_instance_valid(node) and node.is_inside_tree():
			valid_scenes.append(node)
	_spawned_scenes = valid_scenes


# =============================================================================
# World Statistics (for PerformancePanel)
# =============================================================================

func get_world_stats() -> Dictionary:
	"""Get statistics about world objects for the performance panel."""
	var stats := {
		"voxels": 0,
		"chunks": 0,
		"hulls": 0,
		"polys": 0,
		"poly_points": 0,
		"spawned_scenes": _spawned_scenes.size(),
		"max_spawned_scenes": _max_spawned_scenes,
		"max_hulls": _max_hulls,
		"max_voxels": _max_voxels,
		"max_polys": _max_polys,
	}
	
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return stats
	
	# Get voxel stats from VoxelChunkManager
	var voxel_managers := tree.get_nodes_in_group("voxel_manager")
	for manager in voxel_managers:
		if manager.has_method("get_stats"):
			var voxel_stats: Dictionary = manager.get_stats()
			stats["voxels"] += voxel_stats.get("voxels", 0)
			stats["chunks"] += voxel_stats.get("chunks", 0)
	
	# Count generated hulls (nodes with hull names in scene)
	var root := tree.root
	if root:
		stats["hulls"] = _count_hulls_recursive(root)
	
	# Get poly stats from PolyTool instances
	var poly_point_count := 0
	var poly_tri_count := 0
	for tool_type in _pools.keys():
		if tool_type == "poly_tool":
			var data: Dictionary = _pools[tool_type]
			for node in data.get("active", []):
				if is_instance_valid(node) and node.has_method("get_point_count"):
					poly_point_count += node.get_point_count()
				if is_instance_valid(node) and node.has_method("get_triangle_count"):
					poly_tri_count += node.get_triangle_count()
	stats["poly_points"] = poly_point_count
	stats["polys"] = poly_tri_count
	
	return stats


func _count_hulls_recursive(node: Node) -> int:
	"""Count hull objects in the scene tree."""
	var count := 0
	if node.name.begins_with("GeneratedHull_") or node.name.begins_with("VolumeHull_"):
		count += 1
	for child in node.get_children():
		count += _count_hulls_recursive(child)
	return count


# =============================================================================
# Limit Getters/Setters
# =============================================================================

func get_max_hulls() -> int:
	return _max_hulls


func set_max_hulls(limit: int) -> void:
	_max_hulls = max(0, limit)


func get_max_voxels() -> int:
	return _max_voxels


func set_max_voxels(limit: int) -> void:
	_max_voxels = max(0, limit)


func get_max_polys() -> int:
	return _max_polys


func set_max_polys(limit: int) -> void:
	_max_polys = max(0, limit)


func can_create_hull() -> bool:
	"""Check if a new hull can be created within limits."""
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return true
	var current_hulls := _count_hulls_recursive(tree.root)
	return current_hulls < _max_hulls


func can_place_voxel() -> bool:
	"""Check if a new voxel can be placed within limits."""
	var stats := get_world_stats()
	return stats.get("voxels", 0) < _max_voxels


func can_add_poly() -> bool:
	"""Check if a new poly triangle can be added within limits."""
	var stats := get_world_stats()
	return stats.get("polys", 0) < _max_polys
