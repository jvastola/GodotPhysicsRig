extends Node
class_name PerformanceMonitor

# Lightweight runtime performance helper for Quest targets.
# - Tracks FPS and nudges viewport scaling when frame times sag.
# - Registers spawned nodes to cap total count and trim oldest ones.
# - Optionally disables shadows on spawned visuals to reduce GPU cost.

@export var target_refresh_rate: float = 80.0
@export var fps_warn_threshold: float = 60.0
@export var base_scale: float = 0.9
@export var min_scale: float = 0.75
@export var perf_mode_scale: float = 0.85  # Kept for reference; scaling now forced to 1.0 to avoid depth warping
@export var max_spawned_nodes: int = 80
@export var trim_batch: int = 5
@export var disable_shadows_for_spawns: bool = true
@export var max_contacts_per_rigidbody: int = 4
@export var perf_mode_enabled: bool = false
@export var perf_mode_shadow_distance: float = 25.0

static var instance: PerformanceMonitor = null

var _viewport: Viewport = null
var _current_scale: float = 1.0
var _fps_samples: Array[float] = []
var _fps_time: Array[float] = []
var _time_accum: float = 0.0
var _low_fps_timer: float = 0.0
var _high_fps_timer: float = 0.0
var _last_warn_time: float = 0.0
var _spawned_nodes: Array[Node] = []
var _saved_viewport_state: Dictionary = {}
var _saved_mirror_visibility: Dictionary = {}
var _saved_shadow_distance: float = -1.0
var viewports_suspended: bool = false
var mirrors_hidden: bool = false
var shadow_distance_reduced: bool = false


func _ready() -> void:
	instance = self
	_viewport = get_viewport()
	if _viewport:
		_current_scale = _viewport.scaling_3d_scale
		_apply_graphics_defaults()
	# Respect the exported toggle (default off to avoid any warp risk)
	if perf_mode_enabled:
		set_perf_mode(true)
	set_process(true)
	_log("PerformanceMonitor: initialized; base_scale=%.2f min_scale=%.2f" % [base_scale, min_scale])


func _process(delta: float) -> void:
	_track_fps(delta)
	_maybe_adjust_scaling(delta)


func register_spawn(node: Node) -> void:
	if not node:
		return
	_spawned_nodes.append(node)
	node.add_to_group("perf_spawned", true)
	var cb := Callable(self, "_on_spawn_removed").bind(node)
	if not node.tree_exiting.is_connected(cb):
		node.tree_exiting.connect(cb)
	_optimize_spawned_node(node)
	_trim_spawned_if_needed()


func _on_spawn_removed(exiting: Node) -> void:
	for i in range(_spawned_nodes.size() - 1, -1, -1):
		if _spawned_nodes[i] == exiting:
			_spawned_nodes.remove_at(i)
			break


func get_spawn_count() -> int:
	return _spawned_nodes.size()


func register_tools_in_world(world_root: Node) -> void:
	"""Scan a world root for tool-like nodes (Tool/Pen/Poly in name) and add them to the spawn pool."""
	if not world_root:
		return
	var queue: Array = [world_root]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		var name_l := node.name.to_lower()
		if name_l.find("tool") != -1 or name_l.find("pen") != -1 or name_l.find("poly") != -1:
			register_spawn(node)
		for child in node.get_children():
			if child is Node:
				queue.append(child)


func _track_fps(delta: float) -> void:
	_time_accum += delta
	var fps := Engine.get_frames_per_second()
	_fps_samples.append(fps)
	_fps_time.append(_time_accum)
	# Keep roughly 2 seconds of samples
	while _fps_time.size() > 0 and _time_accum - _fps_time[0] > 2.0:
		_fps_time.pop_front()
		_fps_samples.pop_front()


func _maybe_adjust_scaling(delta: float) -> void:
	if not _viewport:
		return
	if _fps_samples.is_empty():
		return
	var sum_fps := 0.0
	for f in _fps_samples:
		sum_fps += f
	var avg_fps := sum_fps / float(_fps_samples.size())

	if avg_fps < target_refresh_rate - 5.0:
		_low_fps_timer += delta
		_high_fps_timer = 0.0
	else:
		_high_fps_timer += delta
		_low_fps_timer = 0.0

	if _low_fps_timer > 1.25:
		var target_scale: float = clamp(_current_scale - 0.05, min_scale, base_scale)
		if target_scale < _current_scale - 0.001:
			_apply_scale(target_scale, "fps %.1f" % avg_fps)
		_low_fps_timer = 0.0
	elif _high_fps_timer > 3.0 and _current_scale < base_scale:
		var target_scale_up: float = min(base_scale, _current_scale + 0.05)
		if target_scale_up > _current_scale + 0.001:
			_apply_scale(target_scale_up, "recovery fps %.1f" % avg_fps)
		_high_fps_timer = 0.0

	# Periodic warning if we're under the Quest requirement
	if avg_fps < fps_warn_threshold and (_time_accum - _last_warn_time) > 3.0:
		_log("PerformanceMonitor: low FPS avg=%.1f (spawned=%d scale=%.2f)" % [avg_fps, _spawned_nodes.size(), _current_scale])
		_last_warn_time = _time_accum


func _apply_graphics_defaults() -> void:
	if not _viewport:
		return
	# Enable dynamic resolution; prefer FSR2 only when Forward+ is active
	# Force no scaling to eliminate perceived depth warping
	_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_viewport.scaling_3d_scale = 1.0
	_viewport.fsr_sharpness = 0.0
	_current_scale = _viewport.scaling_3d_scale
	# Explicitly disable VRS to avoid possible depth warping artifacts
	_viewport.vrs_mode = Viewport.VRS_DISABLED


func _apply_scale(scale: float, reason: String) -> void:
	if not _viewport:
		return
	var clamped: float = clamp(scale, min_scale, 1.0)
	if abs(clamped - _current_scale) < 0.001:
		return
	_viewport.scaling_3d_scale = clamped
	_current_scale = clamped
	_log("PerformanceMonitor: scaling_3d_scale -> %.2f due to %s" % [clamped, reason])


func _trim_spawned_if_needed() -> void:
	if max_spawned_nodes <= 0:
		return
	if _spawned_nodes.size() <= max_spawned_nodes:
		return
	var over := _spawned_nodes.size() - max_spawned_nodes
	var to_trim: int = min(trim_batch, over)
	for i in range(to_trim):
		if _spawned_nodes.is_empty():
			break
		var victim: Node = _spawned_nodes.pop_front()
		if is_instance_valid(victim):
			_log("PerformanceMonitor: trimming spawned node %s to protect perf" % victim.name)
			victim.queue_free()


func _optimize_spawned_node(node: Node) -> void:
	if node is RigidBody3D and max_contacts_per_rigidbody > 0:
		var rb := node as RigidBody3D
		rb.max_contacts_reported = min(rb.max_contacts_reported, max_contacts_per_rigidbody)
	if disable_shadows_for_spawns:
		_disable_shadows(node)


func _disable_shadows(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is GeometryInstance3D:
			var gi := cur as GeometryInstance3D
			if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for child in cur.get_children():
			if child is Node:
				stack.append(child)


func _log(msg: String) -> void:
	if Engine.is_editor_hint():
		print(msg)
	else:
		print(msg)


func set_perf_mode(enabled: bool) -> void:
	perf_mode_enabled = enabled
	disable_shadows_for_spawns = enabled
	# Re-apply graphics defaults to ensure scaling stays neutral (1.0)
	_apply_graphics_defaults()
	# Keep scale fixed at 1.0 to avoid depth warping
	_apply_scale(1.0, "perf mode on" if enabled else "perf mode off")
	set_suspend_viewports(enabled)
	set_hide_mirrors(enabled)
	set_reduce_shadow_distance(enabled)
	set_disable_spawn_shadows(enabled)


func _apply_perf_visual_toggles(enabled: bool) -> void:
	set_suspend_viewports(enabled)
	set_hide_mirrors(enabled)
	set_reduce_shadow_distance(enabled)


func set_suspend_viewports(enabled: bool) -> void:
	viewports_suspended = enabled
	_toggle_viewports(enabled)


func set_hide_mirrors(enabled: bool) -> void:
	mirrors_hidden = enabled
	_toggle_mirrors(enabled)


func set_reduce_shadow_distance(enabled: bool) -> void:
	shadow_distance_reduced = enabled
	_adjust_shadow_distance(enabled)


func set_disable_spawn_shadows(enabled: bool) -> void:
	disable_shadows_for_spawns = enabled
	# Retroactively disable shadows on already-registered spawned nodes if requested
	if enabled:
		for n in _spawned_nodes:
			if is_instance_valid(n):
				_disable_shadows(n)


func _toggle_viewports(enabled: bool) -> void:
	var subs: Array = _collect_nodes_of_type("SubViewport")
	for sv in subs:
		if not (sv is SubViewport):
			continue
		var key: NodePath = sv.get_path()
		if enabled:
			# Restore prior state if saved
			if _saved_viewport_state.has(key):
				var st: Dictionary = _saved_viewport_state[key]
				sv.render_target_update_mode = st.get("mode", SubViewport.UPDATE_ALWAYS)
				if st.has("parent_visible") and sv.get_parent() and sv.get_parent() is Node3D:
					(sv.get_parent() as Node3D).visible = st["parent_visible"]
			else:
				sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				if sv.get_parent() and sv.get_parent() is Node3D:
					(sv.get_parent() as Node3D).visible = true
		else:
			if not _saved_viewport_state.has(key):
				var parent_vis := true
				if sv.get_parent() and sv.get_parent() is Node3D:
					parent_vis = (sv.get_parent() as Node3D).visible
				_saved_viewport_state[key] = {
					"mode": sv.render_target_update_mode,
					"parent_visible": parent_vis,
				}
			sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
			if sv.get_parent() and sv.get_parent() is Node3D:
				(sv.get_parent() as Node3D).visible = false


func _toggle_mirrors(enabled: bool) -> void:
	var mirrors: Array = []
	var nodes := _collect_nodes_of_type("MeshInstance3D")
	for node in nodes:
		if node is MeshInstance3D:
			var name_l: String = node.name.to_lower()
			if name_l.find("mirror") != -1:
				mirrors.append(node)
	for m in mirrors:
		var key: NodePath = m.get_path()
		if enabled:
			if _saved_mirror_visibility.has(key):
				m.visible = _saved_mirror_visibility[key]
			else:
				m.visible = true
		else:
			if not _saved_mirror_visibility.has(key):
				_saved_mirror_visibility[key] = m.visible
			m.visible = false


func _adjust_shadow_distance(enabled: bool) -> void:
	var env_node := _find_world_environment()
	if not env_node:
		return
	var env := env_node.environment
	if not env:
		return
	# Guard against missing property on some renderers
	if not env.has_method("get") or not env.has_method("set"):
		return
	var has_prop := env.has("directional_shadow_max_distance")
	if not has_prop:
		return
	if enabled:
		if _saved_shadow_distance < 0.0:
			_saved_shadow_distance = float(env.get("directional_shadow_max_distance"))
		env.set("directional_shadow_max_distance", perf_mode_shadow_distance)
	else:
		if _saved_shadow_distance >= 0.0:
			env.set("directional_shadow_max_distance", _saved_shadow_distance)


func _find_world_environment() -> WorldEnvironment:
	var root := get_tree().root
	if not root:
		return null
	return root.find_child("WorldEnvironment", true, false) as WorldEnvironment


func _collect_nodes_of_type(type_name: String) -> Array:
	var result: Array = []
	var root := get_tree().root
	if not root:
		return result
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node and type_name != "" and node.is_class(type_name):
			result.append(node)
		for child in node.get_children():
			if child is Node:
				stack.append(child)
	return result
