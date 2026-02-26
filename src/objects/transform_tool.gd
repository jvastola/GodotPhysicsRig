extends Grabbable
class_name TransformTool
## Grabbable Transform Tool - Ray/indicator plus selection bounds and transform handles (no voxel placement)

# === Ray Settings ===
@export_group("Ray Settings")
@export var ray_length: float = 5.0
@export var ray_length_min: float = 0.5
@export var ray_length_max: float = 15.0
@export var ray_length_adjust_speed: float = 5.0
@export var ray_deadzone: float = 0.2
@export var ray_axis_action: String = "primary"

# === Visibility ===
@export_group("Visibility")
@export var always_show_ray: bool = true
@export var always_show_indicator: bool = true
@export var ray_color: Color = Color(0.7, 0.3, 0.9, 0.6)
@export var ray_hit_color: Color = Color(0.5, 0.9, 0.2, 0.8)
@export var indicator_color: Color = Color(0.7, 0.3, 0.9, 0.4)
@export var remove_mode_color: Color = Color(1.0, 0.2, 0.2, 0.4)

# === Indicator Settings ===
@export_group("Indicator Settings")
@export var indicator_size: float = 0.1
@export var indicator_size_presets: Array[float] = [0.05, 0.1, 0.25, 0.5, 1.0]
@export var indicator_size_preset_index: int = 1
@export var indicator_size_adjust_speed: float = 0.5
@export var surface_offset: float = 0.01

# === Selection Settings ===
@export_group("Selection")
@export var handle_length: float = 0.15
@export var handle_thickness: float = 0.015
@export var handle_offset: float = 0.05
@export var handle_color_x: Color = Color(1.0, 0.3, 0.3, 0.85)
@export var handle_color_y: Color = Color(0.3, 1.0, 0.3, 0.85)
@export var handle_color_z: Color = Color(0.3, 0.5, 1.0, 0.85)

# === Scaling ===
@export_group("Scaling")
@export var scale_controls_with_tool: bool = true
@export var scale_controls_with_player: bool = false # Legacy toggle kept for old scenes.
@export_range(0.05, 100.0, 0.05) var controls_scale_min: float = 0.1
@export_range(0.1, 1000.0, 0.1) var controls_scale_max: float = 100.0

# === Networking ===
@export_group("Networking")
@export var network_debug_logs: bool = false

# === Child Nodes (created dynamically) ===
var raycast: RayCast3D
var ray_visual: MeshInstance3D
var indicator_mesh: MeshInstance3D
var hit_marker: MeshInstance3D
var ray_immediate_mesh: ImmediateMesh
var _selection_bounds: MeshInstance3D
var _selection_bounds_mesh: ImmediateMesh
var _selection_handles: Array[Area3D] = []

# === State ===
var _was_trigger_pressed: bool = false
var _is_remove_mode: bool = false
var _has_hit: bool = false
var _hit_point: Vector3 = Vector3.ZERO
var _hit_normal: Vector3 = Vector3.UP
var _hit_collider: Node = null
var _selected_objects: Array[Node3D] = []
var _active_axis: Vector3 = Vector3.ZERO
var _active_handle: Node3D = null
var _active_proj: float = 0.0
var _active_mode: String = "translate"
var _rotate_ref: Vector3 = Vector3.ZERO
var _rotate_center: Vector3 = Vector3.ZERO
var _rotate_last_angle: float = 0.0
var _scale_reference: float = 0.1
var _last_center: Vector3 = Vector3.ZERO
var _last_half_size: Vector3 = Vector3.ZERO
var _controls_scale_multiplier: float = 1.0
var _last_applied_controls_scale: float = -1.0
var _network_manager: Node = null
var _owned_selected_object_ids: Dictionary = {} # object_id -> true while this tool owns selection authority
var _ownership_request_msec: Dictionary = {} # object_id -> last ownership request tick
var _last_scale_sync_msec: Dictionary = {} # object_id -> msec
var _last_synced_scale: Dictionary = {} # object_id -> Vector3
var _was_grabbed_last_frame: bool = false
var _last_network_sync_log_msec: int = 0

const OWNERSHIP_REQUEST_RETRY_MS: int = 250
const SCALE_SYNC_INTERVAL_MS: int = 50
const SCALE_SYNC_EPSILON: float = 0.0005
const NETWORK_LOG_INTERVAL_MS: int = 250


func _ready() -> void:
	super._ready()
	
	_create_raycast()
	_create_ray_visual()
	_create_indicator()
	_create_hit_marker()
	_setup_selection_bounds()
	_setup_selection_handles()
	_update_controls_scale(true)
	_apply_indicator_size()
	
	print("TransformTool: Ready with indicator size ", indicator_size)


func _exit_tree() -> void:
	_release_all_owned_selection_objects()


func _create_raycast() -> void:
	raycast = RayCast3D.new()
	raycast.name = "TransformRaycast"
	raycast.target_position = Vector3(0, 0, -ray_length)
	raycast.enabled = true
	raycast.exclude_parent = true
	raycast.collision_mask = 1  # World/handles layer
	raycast.collide_with_areas = true
	raycast.collide_with_bodies = true
	add_child(raycast)


func _create_ray_visual() -> void:
	ray_visual = MeshInstance3D.new()
	ray_visual.name = "RayVisual"
	ray_immediate_mesh = ImmediateMesh.new()
	ray_visual.mesh = ray_immediate_mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = ray_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	ray_visual.material_override = mat
	
	add_child(ray_visual)


func _create_indicator() -> void:
	indicator_mesh = MeshInstance3D.new()
	indicator_mesh.name = "TransformToolIndicator"
	
	var sphere = SphereMesh.new()
	sphere.radius = indicator_size * 0.5
	sphere.height = indicator_size
	sphere.radial_segments = 12
	indicator_mesh.mesh = sphere
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = indicator_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	indicator_mesh.material_override = mat
	
	indicator_mesh.visible = false


func _create_hit_marker() -> void:
	hit_marker = MeshInstance3D.new()
	hit_marker.name = "TransformToolHitMarker"
	
	var sphere = SphereMesh.new()
	hit_marker.mesh = sphere
	_apply_hit_marker_size()
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = ray_hit_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hit_marker.material_override = mat
	
	hit_marker.visible = false


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	_update_controls_scale()
	_ensure_visuals_in_tree()
	_refresh_raycast_exceptions()
	
	if not is_grabbed:
		if _was_grabbed_last_frame:
			_broadcast_selected_transform_updates(true, false)
			_release_all_owned_selection_objects()
			_was_grabbed_last_frame = false
		_set_visuals_visible(false)
		return
	if not is_desktop_grabbed and not is_instance_valid(grabbing_hand):
		if _was_grabbed_last_frame:
			_broadcast_selected_transform_updates(true, false)
			_release_all_owned_selection_objects()
			_was_grabbed_last_frame = false
		_set_visuals_visible(false)
		return
	_was_grabbed_last_frame = true
	
	_process_input(delta)
	_process_raycast()
	_update_visuals()


func _ensure_visuals_in_tree() -> void:
	if not is_inside_tree():
		return
	
	var scene_root = get_tree().current_scene
	if not scene_root:
		return
	
	if not is_instance_valid(indicator_mesh):
		_create_indicator()
	
	if not is_instance_valid(hit_marker):
		_create_hit_marker()
	
	if not is_instance_valid(_selection_bounds):
		_setup_selection_bounds()
	if _selection_handles.is_empty():
		_setup_selection_handles()
	
	if indicator_mesh and not indicator_mesh.is_inside_tree():
		scene_root.add_child(indicator_mesh)
	
	if hit_marker and not hit_marker.is_inside_tree():
		scene_root.add_child(hit_marker)
	
	if _selection_bounds and _selection_bounds.get_parent() != scene_root:
		scene_root.add_child(_selection_bounds)
	
	for handle in _selection_handles:
		if handle and handle.get_parent() != scene_root:
			scene_root.add_child(handle)


func _process_input(delta: float) -> void:
	if is_desktop_grabbed:
		_process_desktop_input(delta)
		return

	var controller = _get_controller()
	if not controller:
		return
	
	# Get current input states - check both trigger value and trigger_click
	var trigger_pressed = false
	var grip_pressed = false
	
	if controller.has_method("get_float"):
		var trigger_value = controller.get_float("trigger")
		trigger_pressed = controller.is_button_pressed("trigger_click") or trigger_value > 0.5
		var grip_value = controller.get_float("grip")
		grip_pressed = controller.is_button_pressed("grip_click") or grip_value > 0.5
	else:
		trigger_pressed = controller.is_button_pressed("trigger_click")
		grip_pressed = controller.is_button_pressed("grip_click")
	
	_is_remove_mode = grip_pressed
	
	# Handle selection / handle dragging
	if trigger_pressed and not _was_trigger_pressed:
		if _hit_collider and _hit_collider.has_meta("selection_axis"):
			_begin_handle_drag(_hit_collider)
		elif _hit_collider and _hit_collider is Node3D:
			_add_selected_object(_hit_collider as Node3D)
		else:
			_clear_selection()
	elif not trigger_pressed and _was_trigger_pressed and _active_axis != Vector3.ZERO:
		_end_handle_drag()
	
	if trigger_pressed and _active_axis != Vector3.ZERO:
		_update_handle_drag()
	
	_was_trigger_pressed = trigger_pressed
	
	var axis_input = controller.get_vector2(ray_axis_action)
	if abs(axis_input.y) > ray_deadzone:
		ray_length = clamp(
			ray_length - axis_input.y * ray_length_adjust_speed * delta,
			ray_length_min,
			ray_length_max
		)
		raycast.target_position = Vector3(0, 0, -ray_length)
	
	if grip_pressed and abs(axis_input.x) > ray_deadzone:
		_adjust_indicator_size(axis_input.x * delta)


func _process_desktop_input(delta: float) -> void:
	_is_remove_mode = Input.is_action_pressed("grip_click")
	var trigger_pressed = Input.is_action_pressed("trigger_click")

	# Handle selection / handle dragging
	if trigger_pressed and not _was_trigger_pressed:
		if _hit_collider and _hit_collider.has_meta("selection_axis"):
			_begin_handle_drag(_hit_collider)
		elif _hit_collider and _hit_collider is Node3D:
			_add_selected_object(_hit_collider as Node3D)
		else:
			_clear_selection()
	elif not trigger_pressed and _was_trigger_pressed and _active_axis != Vector3.ZERO:
		_end_handle_drag()

	if trigger_pressed and _active_axis != Vector3.ZERO:
		_update_handle_drag()

	_was_trigger_pressed = trigger_pressed

	# Desktop ray-length adjustment
	if Input.is_action_just_pressed("ui_text_scroll_up"):
		_adjust_ray_length(1.0, delta)
	elif Input.is_action_just_pressed("ui_text_scroll_down"):
		_adjust_ray_length(-1.0, delta)


func _adjust_ray_length(direction: float, delta: float) -> void:
	ray_length = clamp(
		ray_length + direction * ray_length_adjust_speed * delta * 5.0,
		ray_length_min,
		ray_length_max
	)
	if raycast:
		raycast.target_position = Vector3(0, 0, -ray_length)


func _get_controller() -> XRController3D:
	if not is_instance_valid(grabbing_hand):
		return null
	return grabbing_hand.target as XRController3D


func _process_raycast() -> void:
	if not raycast:
		return
	
	raycast.force_raycast_update()
	_has_hit = raycast.is_colliding()
	
	if _has_hit:
		_hit_point = raycast.get_collision_point()
		_hit_normal = raycast.get_collision_normal()
		_hit_collider = raycast.get_collider()
	else:
		_hit_point = raycast.to_global(Vector3(0, 0, -ray_length))
		_hit_normal = Vector3.UP
		_hit_collider = null


func _refresh_raycast_exceptions() -> void:
	if raycast == null:
		return
	raycast.clear_exceptions()
	raycast.add_exception(self)
	if is_instance_valid(grabbing_hand):
		raycast.add_exception(grabbing_hand)


func _update_visuals() -> void:
	var show_ray = always_show_ray or _has_hit
	var show_indicator = always_show_indicator or _has_hit
	
	if ray_visual and ray_immediate_mesh:
		ray_visual.visible = show_ray
		if show_ray:
			_draw_ray()
	
	if indicator_mesh:
		indicator_mesh.visible = show_indicator
		if show_indicator:
			_update_indicator_position()
	
	if hit_marker:
		hit_marker.visible = _has_hit
		if _has_hit:
			hit_marker.global_position = _hit_point
	
	_update_selection_visuals()


func _draw_ray() -> void:
	ray_immediate_mesh.clear_surfaces()
	ray_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	var end_point = Vector3(0, 0, -ray_length)
	if _has_hit:
		end_point = raycast.to_local(_hit_point)
	
	ray_immediate_mesh.surface_add_vertex(Vector3.ZERO)
	ray_immediate_mesh.surface_add_vertex(end_point)
	ray_immediate_mesh.surface_end()
	
	var mat = ray_visual.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = remove_mode_color if _is_remove_mode else ray_color


func _update_indicator_position() -> void:
	var adjusted_point = _hit_point
	
	if _hit_normal.length_squared() > 0.0:
		if _is_remove_mode:
			adjusted_point -= _hit_normal.normalized() * surface_offset
		else:
			adjusted_point += _hit_normal.normalized() * surface_offset
	
	indicator_mesh.global_position = adjusted_point
	indicator_mesh.global_rotation = Vector3.ZERO
	
	var mat = indicator_mesh.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = remove_mode_color if _is_remove_mode else indicator_color


func _adjust_indicator_size(delta_input: float) -> void:
	indicator_size = clamp(
		indicator_size + delta_input * indicator_size_adjust_speed,
		0.01,
		2.0
	)
	_apply_indicator_size()


func _apply_indicator_size() -> void:
	if indicator_mesh and indicator_mesh.mesh is SphereMesh:
		var sphere = indicator_mesh.mesh as SphereMesh
		var scaled_size := maxf(indicator_size * _controls_scale_multiplier, 0.001)
		sphere.radius = scaled_size * 0.5
		sphere.height = scaled_size


func _apply_hit_marker_size() -> void:
	if hit_marker and hit_marker.mesh is SphereMesh:
		var sphere := hit_marker.mesh as SphereMesh
		var marker_size := maxf(0.04 * _controls_scale_multiplier, 0.002)
		sphere.radius = marker_size * 0.5
		sphere.height = marker_size


func _set_visuals_visible(visible_state: bool) -> void:
	if ray_visual:
		ray_visual.visible = visible_state
	if indicator_mesh:
		indicator_mesh.visible = visible_state
	if hit_marker:
		hit_marker.visible = visible_state
	if _selection_bounds:
		_selection_bounds.visible = visible_state and not _selected_objects.is_empty()
	for handle in _selection_handles:
		if is_instance_valid(handle):
			handle.visible = visible_state and not _selected_objects.is_empty()
			handle.monitoring = handle.visible


# === Selection / Handles ===

func _setup_selection_bounds() -> void:
	_selection_bounds_mesh = ImmediateMesh.new()
	_selection_bounds = MeshInstance3D.new()
	_selection_bounds.name = "SelectionBounds"
	_selection_bounds.mesh = _selection_bounds_mesh
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.3, 0.85, 1.0, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_selection_bounds.material_override = mat
	_selection_bounds.visible = false


func _setup_selection_handles() -> void:
	_selection_handles.clear()
	var defs = [
		# Translate
		{"axis": Vector3.RIGHT, "color": handle_color_x, "name": "HandleXPos", "mode": "translate"},
		{"axis": Vector3.LEFT, "color": handle_color_x, "name": "HandleXNeg", "mode": "translate"},
		{"axis": Vector3.UP, "color": handle_color_y, "name": "HandleYPos", "mode": "translate"},
		{"axis": Vector3.DOWN, "color": handle_color_y, "name": "HandleYNeg", "mode": "translate"},
		{"axis": Vector3.BACK, "color": handle_color_z, "name": "HandleZPos", "mode": "translate"}, # Godot forward is -Z
		{"axis": Vector3.FORWARD, "color": handle_color_z, "name": "HandleZNeg", "mode": "translate"},
		# Scale
		{"axis": Vector3.RIGHT, "color": handle_color_x, "name": "ScaleXPos", "mode": "scale"},
		{"axis": Vector3.LEFT, "color": handle_color_x, "name": "ScaleXNeg", "mode": "scale"},
		{"axis": Vector3.UP, "color": handle_color_y, "name": "ScaleYPos", "mode": "scale"},
		{"axis": Vector3.DOWN, "color": handle_color_y, "name": "ScaleYNeg", "mode": "scale"},
		{"axis": Vector3.BACK, "color": handle_color_z, "name": "ScaleZPos", "mode": "scale"},
		{"axis": Vector3.FORWARD, "color": handle_color_z, "name": "ScaleZNeg", "mode": "scale"},
		# Rotate
		{"axis": Vector3.RIGHT, "color": handle_color_x, "name": "RotateXPos", "mode": "rotate"},
		{"axis": Vector3.LEFT, "color": handle_color_x, "name": "RotateXNeg", "mode": "rotate"},
		{"axis": Vector3.UP, "color": handle_color_y, "name": "RotateYPos", "mode": "rotate"},
		{"axis": Vector3.DOWN, "color": handle_color_y, "name": "RotateYNeg", "mode": "rotate"},
		{"axis": Vector3.BACK, "color": handle_color_z, "name": "RotateZPos", "mode": "rotate"},
		{"axis": Vector3.FORWARD, "color": handle_color_z, "name": "RotateZNeg", "mode": "rotate"}
	]
	for def in defs:
		var axis_vec: Vector3 = (def["axis"] as Vector3).normalized()
		var handle := Area3D.new()
		handle.name = def["name"]
		handle.collision_layer = 1 # world default so raycast can hit
		handle.collision_mask = 0
		handle.set_meta("selection_axis", axis_vec)
		handle.set_meta("selection_mode", def.get("mode", "translate"))
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Visual"
		var mode: String = def.get("mode", "translate")
		if mode == "translate":
			mesh_instance.mesh = _build_handle_mesh()
		elif mode == "scale":
			mesh_instance.mesh = _build_handle_scale_mesh()
		else:
			mesh_instance.mesh = _build_handle_ring_mesh()
		mesh_instance.material_override = _build_handle_material(def["color"])
		handle.add_child(mesh_instance)
		var collider := CollisionShape3D.new()
		collider.name = "Collision"
		if mode == "translate":
			collider.shape = _build_handle_collision_shape()
			collider.position = Vector3(0, 0, handle_length * 0.5)
		elif mode == "scale":
			collider.shape = _build_handle_scale_collision_shape()
		else:
			collider.shape = _build_handle_ring_collision_shape()
		handle.add_child(collider)
		handle.visible = false
		_selection_handles.append(handle)


func _build_handle_mesh() -> Mesh:
	var st: SurfaceTool = SurfaceTool.new()
	var mesh: ArrayMesh = ArrayMesh.new()
	var sides: int = 12
	var radius: float = max(handle_thickness, 0.005)
	var shaft_len: float = max(handle_length * 0.6, 0.02)
	var head_len: float = max(handle_length * 0.4, 0.015)
	var tip_z: float = shaft_len + head_len
	var head_radius: float = radius * 1.6
	
	# Shaft
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(sides):
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float((i + 1) % sides) / float(sides)
		var p0 := Vector3(cos(a0) * radius, sin(a0) * radius, 0.0)
		var p1 := Vector3(cos(a1) * radius, sin(a1) * radius, 0.0)
		var p0_top := Vector3(p0.x, p0.y, shaft_len)
		var p1_top := Vector3(p1.x, p1.y, shaft_len)
		st.add_vertex(p0); st.add_vertex(p1_top); st.add_vertex(p0_top)
		st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(p1_top)
	st.generate_normals()
	st.commit(mesh)
	
	# Head
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := Vector3(0, 0, tip_z)
	for i in range(sides):
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float((i + 1) % sides) / float(sides)
		var b0 := Vector3(cos(a0) * head_radius, sin(a0) * head_radius, shaft_len)
		var b1 := Vector3(cos(a1) * head_radius, sin(a1) * head_radius, shaft_len)
		st.add_vertex(tip); st.add_vertex(b1); st.add_vertex(b0)
	st.generate_normals()
	st.commit(mesh)
	
	return mesh


func _build_handle_collision_shape() -> BoxShape3D:
	var box := BoxShape3D.new()
	var half: float = max(handle_thickness * 1.5, 0.01)
	box.extents = Vector3(half, half, max(handle_length * 0.5, 0.02))
	return box


func _build_handle_scale_mesh() -> Mesh:
	var box := BoxMesh.new()
	var size: float = max(handle_thickness * 3.0, 0.05)
	box.size = Vector3(size, size, size)
	return box


func _build_handle_scale_collision_shape() -> BoxShape3D:
	var box := BoxShape3D.new()
	var half: float = max(0.025, handle_thickness * 1.5)
	box.extents = Vector3(half, half, half)
	return box


func _build_handle_ring_mesh() -> Mesh:
	var ring := TorusMesh.new()
	ring.inner_radius = max(0.05, handle_thickness * 3.0)
	ring.outer_radius = ring.inner_radius + max(handle_thickness * 2.0, 0.02)
	ring.ring_segments = 32
	return ring


func _build_handle_ring_collision_shape() -> CylinderShape3D:
	var cyl := CylinderShape3D.new()
	cyl.radius = max(0.05, handle_thickness * 3.0)
	cyl.height = max(handle_thickness * 4.0, 0.02)
	return cyl


func _build_handle_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.render_priority = 2
	return mat


func _add_selected_object(node: Node3D) -> void:
	var target := _selection_move_target(node)
	if not target or _selected_objects.has(target):
		return
	_selected_objects.append(target)
	if network_debug_logs:
		var selected_object_id := _resolve_network_object_id(target)
		_network_log("selected %s id=%s path=%s" % [target.name, selected_object_id if not selected_object_id.is_empty() else "<none>", str(target.get_path())])
	_claim_network_ownership_for_object(target)
	_update_selection_visuals()


func _clear_selection() -> void:
	_broadcast_selected_transform_updates(true, false)
	for node in _selected_objects:
		_release_network_ownership_for_object(node)
	_selected_objects.clear()
	_active_axis = Vector3.ZERO
	_active_handle = null
	_active_proj = 0.0
	_update_selection_visuals()


func _selection_move_target(node: Node3D) -> Node3D:
	var candidates: Array[Node3D] = []
	var probe: Node = node
	while probe and probe is Node3D and probe != self:
		candidates.append(probe as Node3D)
		probe = probe.get_parent()
	# Prefer network-addressable grabbables (save_id) so transform sync can replicate.
	for candidate in candidates:
		if candidate.has_method("get"):
			var raw_save_id: Variant = candidate.get("save_id")
			var save_id: String = String(raw_save_id) if raw_save_id != null else ""
			if not save_id.is_empty():
				return candidate
	for candidate in candidates:
		if candidate is RigidBody3D and candidate.is_in_group("grabbable"):
			return candidate
	for candidate in candidates:
		if _has_visual_descendant(candidate) and _has_collision_descendant(candidate):
			return candidate
	for candidate in candidates:
		if candidate is CollisionObject3D:
			return candidate
	return candidates[0] if not candidates.is_empty() else node


func _has_visual_descendant(root: Node) -> bool:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is VisualInstance3D:
			return true
		for child in cur.get_children():
			if child is Node:
				stack.append(child)
	return false


func _has_collision_descendant(root: Node) -> bool:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is CollisionObject3D or cur is CollisionShape3D:
			return true
		for child in cur.get_children():
			if child is Node:
				stack.append(child)
	return false


func _compute_selection_aabb() -> AABB:
	_prune_selected_objects()
	var has_box := false
	var combined := AABB()
	for node in _selected_objects:
		var aabb := _get_object_aabb(node)
		if aabb.size == Vector3.ZERO:
			continue
		if not has_box:
			combined = aabb
			has_box = true
		else:
			combined = combined.merge(aabb)
	return combined if has_box else AABB()


func _prune_selected_objects() -> void:
	for i in range(_selected_objects.size() - 1, -1, -1):
		if not is_instance_valid(_selected_objects[i]):
			_selected_objects.remove_at(i)


func _get_object_aabb(node: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	_collect_visual_aabbs(node, boxes)
	_collect_collisionshape_aabbs(node, boxes)
	if boxes.is_empty():
		return AABB(node.global_transform.origin - Vector3.ONE * 0.05, Vector3.ONE * 0.1)
	var combined := boxes[0]
	for i in range(1, boxes.size()):
		combined = combined.merge(boxes[i])
	return combined


func _collect_visual_aabbs(node: Node, boxes: Array[AABB]) -> void:
	if node is VisualInstance3D:
		var vi := node as VisualInstance3D
		var local_aabb := vi.get_aabb()
		if local_aabb.size != Vector3.ZERO:
			var global_box := _transform_aabb(local_aabb, vi.global_transform)
			boxes.append(global_box)
	for child in node.get_children():
		if child is Node:
			_collect_visual_aabbs(child, boxes)


func _collect_collisionshape_aabbs(node: Node, boxes: Array[AABB]) -> void:
	if node is CollisionShape3D:
		var cs := node as CollisionShape3D
		if cs.shape:
			var box := _shape_aabb(cs.shape, cs.global_transform)
			if box.size != Vector3.ZERO:
				boxes.append(box)
	for child in node.get_children():
		if child is Node:
			_collect_collisionshape_aabbs(child, boxes)


func _shape_aabb(shape: Shape3D, xform: Transform3D) -> AABB:
	var local := AABB()
	match shape:
		BoxShape3D:
			var s := shape as BoxShape3D
			local = AABB(-s.extents, s.extents * 2.0)
		SphereShape3D:
			var sp := shape as SphereShape3D
			var r := sp.radius
			local = AABB(Vector3(-r, -r, -r), Vector3(r * 2.0, r * 2.0, r * 2.0))
		CapsuleShape3D:
			var cap := shape as CapsuleShape3D
			var r2 := cap.radius
			var h := cap.height
			local = AABB(Vector3(-r2, -r2, -h * 0.5 - r2), Vector3(r2 * 2.0, r2 * 2.0, h + r2 * 2.0))
		CylinderShape3D:
			var cyl := shape as CylinderShape3D
			var rc := cyl.radius
			var hc := cyl.height * 0.5
			local = AABB(Vector3(-rc, -hc, -rc), Vector3(rc * 2.0, hc * 2.0, rc * 2.0))
		_:
			var dbg := shape.get_debug_mesh()
			if dbg:
				local = dbg.get_aabb()
	if local.size == Vector3.ZERO:
		return AABB()
	return _transform_aabb(local, xform)


func _transform_aabb(box: AABB, xform: Transform3D) -> AABB:
	var points := [
		box.position,
		box.position + Vector3(box.size.x, 0, 0),
		box.position + Vector3(0, box.size.y, 0),
		box.position + Vector3(0, 0, box.size.z),
		box.position + Vector3(box.size.x, box.size.y, 0),
		box.position + Vector3(box.size.x, 0, box.size.z),
		box.position + Vector3(0, box.size.y, box.size.z),
		box.position + box.size
	]
	var min_v: Vector3 = xform * points[0]
	var max_v: Vector3 = min_v
	for i in range(1, points.size()):
		var p: Vector3 = xform * points[i]
		min_v = min_v.min(p)
		max_v = max_v.max(p)
	return AABB(min_v, max_v - min_v)


func _update_selection_visuals() -> void:
	if not _selection_bounds_mesh:
		return
	var aabb := _compute_selection_aabb()
	_selection_bounds_mesh.clear_surfaces()
	if aabb.size == Vector3.ZERO:
		_selection_bounds.visible = false
		_position_handles(Vector3.ZERO, Vector3.ZERO)
		return
	_last_center = aabb.position + aabb.size * 0.5
	_last_half_size = aabb.size * 0.5
	_draw_selection_bounds(aabb)
	_position_handles(_last_center, _last_half_size)


func _draw_selection_bounds(aabb: AABB) -> void:
	_selection_bounds_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var min_v := aabb.position
	var max_v := aabb.position + aabb.size
	var p0 := Vector3(min_v.x, min_v.y, min_v.z)
	var p1 := Vector3(max_v.x, min_v.y, min_v.z)
	var p2 := Vector3(max_v.x, max_v.y, min_v.z)
	var p3 := Vector3(min_v.x, max_v.y, min_v.z)
	var p4 := Vector3(min_v.x, min_v.y, max_v.z)
	var p5 := Vector3(max_v.x, min_v.y, max_v.z)
	var p6 := Vector3(max_v.x, max_v.y, max_v.z)
	var p7 := Vector3(min_v.x, max_v.y, max_v.z)
	# Bottom
	_selection_bounds_mesh.surface_add_vertex(p0); _selection_bounds_mesh.surface_add_vertex(p1)
	_selection_bounds_mesh.surface_add_vertex(p1); _selection_bounds_mesh.surface_add_vertex(p2)
	_selection_bounds_mesh.surface_add_vertex(p2); _selection_bounds_mesh.surface_add_vertex(p3)
	_selection_bounds_mesh.surface_add_vertex(p3); _selection_bounds_mesh.surface_add_vertex(p0)
	# Top
	_selection_bounds_mesh.surface_add_vertex(p4); _selection_bounds_mesh.surface_add_vertex(p5)
	_selection_bounds_mesh.surface_add_vertex(p5); _selection_bounds_mesh.surface_add_vertex(p6)
	_selection_bounds_mesh.surface_add_vertex(p6); _selection_bounds_mesh.surface_add_vertex(p7)
	_selection_bounds_mesh.surface_add_vertex(p7); _selection_bounds_mesh.surface_add_vertex(p4)
	# Sides
	_selection_bounds_mesh.surface_add_vertex(p0); _selection_bounds_mesh.surface_add_vertex(p4)
	_selection_bounds_mesh.surface_add_vertex(p1); _selection_bounds_mesh.surface_add_vertex(p5)
	_selection_bounds_mesh.surface_add_vertex(p2); _selection_bounds_mesh.surface_add_vertex(p6)
	_selection_bounds_mesh.surface_add_vertex(p3); _selection_bounds_mesh.surface_add_vertex(p7)
	_selection_bounds_mesh.surface_end()
	_selection_bounds.global_transform = Transform3D.IDENTITY
	_selection_bounds.visible = true


func _position_handles(center: Vector3, half_size: Vector3) -> void:
	if _selection_handles.is_empty():
		return
	var has_selection := half_size != Vector3.ZERO
	var abs_half := Vector3(abs(half_size.x), abs(half_size.y), abs(half_size.z))
	var control_scale := _controls_scale_multiplier
	for handle in _selection_handles:
		if not is_instance_valid(handle):
			continue
		handle.visible = has_selection
		handle.monitoring = has_selection
		if not has_selection:
			continue
		var axis: Vector3 = handle.get_meta("selection_axis", Vector3.ZERO)
		var mode: String = handle.get_meta("selection_mode", "translate")
		var axis_len: float = abs(axis.x) * abs_half.x + abs(axis.y) * abs_half.y + abs(axis.z) * abs_half.z
		var extra: float = handle_offset * control_scale
		if mode == "translate":
			extra += handle_length * 0.6 * control_scale
		elif mode == "scale":
			extra += 0.05 * control_scale
		else:
			extra += 0.1 * control_scale
		var pos := center + axis.normalized() * (axis_len + extra)
		if mode == "rotate":
			var y := axis.normalized()
			var x := _any_perpendicular(y)
			var z := x.cross(y).normalized()
			var h_basis := Basis(x, y, z)
			handle.global_transform = Transform3D(h_basis, pos)
		else:
			var up := Vector3.UP if abs(axis.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
			# Basis.looking_at aims -Z to target; flip to make +Z point outward
			var h_basis := Basis.looking_at(-axis.normalized(), up)
			handle.global_transform = Transform3D(h_basis, pos)
		handle.scale = Vector3.ONE * control_scale


func _begin_handle_drag(handle: Node) -> void:
	if not handle or not handle.has_meta("selection_axis"):
		return
	_claim_network_ownership_for_selection()
	_active_axis = (handle.get_meta("selection_axis") as Vector3).normalized()
	_active_handle = handle as Node3D
	_active_mode = handle.get_meta("selection_mode", "translate")
	_active_proj = _hit_point.dot(_active_axis)
	if _active_mode == "scale":
		var ref_extent: float = abs(_last_half_size.x * _active_axis.x) + abs(_last_half_size.y * _active_axis.y) + abs(_last_half_size.z * _active_axis.z)
		_scale_reference = max(ref_extent, 0.05)
	elif _active_mode == "rotate":
		_rotate_center = _last_center
		var ref_vec := _project_on_plane(_hit_point - _rotate_center, _active_axis)
		if ref_vec.length() < 0.0001:
			ref_vec = _any_perpendicular(_active_axis)
		_rotate_ref = ref_vec
		_rotate_last_angle = 0.0


func _update_handle_drag() -> void:
	if _active_axis == Vector3.ZERO:
		return
	var proj := _hit_point.dot(_active_axis)
	var delta := proj - _active_proj
	var did_transform := false
	if _active_mode == "translate":
		if abs(delta) <= 0.0005:
			return
		_move_selected_objects_along_axis(_active_axis, delta)
		_active_proj = proj
		did_transform = true
	elif _active_mode == "scale":
		if abs(delta) <= 0.0005 or _scale_reference <= 0.0:
			return
		var scale_factor: float = 1.0 + (delta / _scale_reference)
		scale_factor = clamp(scale_factor, 0.05, 10.0)
		_scale_selected_objects_along_axis(_active_axis, scale_factor)
		_active_proj = proj
		did_transform = true
	elif _active_mode == "rotate":
		var cur_vec := _project_on_plane(_hit_point - _rotate_center, _active_axis)
		if cur_vec.length() < 0.0001 or _rotate_ref.length() < 0.0001:
			return
		var angle := _signed_angle_on_plane(_rotate_ref, cur_vec, _active_axis)
		var delta_angle := angle - _rotate_last_angle
		if abs(delta_angle) > 0.0001:
			_rotate_selected_objects(_active_axis, _rotate_center, delta_angle)
			_rotate_last_angle = angle
			did_transform = true
	_active_proj = proj
	if did_transform:
		_broadcast_selected_transform_updates()
	_update_selection_visuals()


func _end_handle_drag() -> void:
	_active_axis = Vector3.ZERO
	_active_handle = null
	_active_proj = 0.0
	_active_mode = "translate"
	_rotate_ref = Vector3.ZERO
	_rotate_center = Vector3.ZERO
	_rotate_last_angle = 0.0


func _move_selected_objects_along_axis(axis: Vector3, distance: float) -> void:
	var dir := axis.normalized()
	for node in _selected_objects:
		if is_instance_valid(node):
			if node is RigidBody3D:
				var rb := node as RigidBody3D
				var xform := rb.global_transform
				xform.origin += dir * distance
				rb.global_transform = xform
				rb.linear_velocity = Vector3.ZERO
				rb.angular_velocity = Vector3.ZERO
				rb.sleeping = false
			else:
				node.global_position += dir * distance


func _scale_selected_objects_along_axis(axis: Vector3, scale_factor: float) -> void:
	if axis == Vector3.ZERO or scale_factor == 1.0:
		return
	var dir := axis.normalized()
	for node in _selected_objects:
		if is_instance_valid(node):
			_scale_node_along_axis(node, dir, scale_factor)


func _rotate_selected_objects(axis: Vector3, pivot: Vector3, angle: float) -> void:
	if axis == Vector3.ZERO or angle == 0.0:
		return
	var dir := axis.normalized()
	for node in _selected_objects:
		if is_instance_valid(node):
			_rotate_node_around_axis(node, pivot, dir, angle)


func _scale_node_along_axis(node: Node3D, dir: Vector3, scale_factor: float) -> void:
	if scale_factor == 1.0:
		return
	# For physics bodies, stick to uniform scaling to avoid Jolt non-uniform errors.
	if node is CollisionObject3D:
		node.scale = node.scale * Vector3.ONE * scale_factor
		return
	var local_axis: Vector3 = node.global_transform.basis.inverse() * dir
	var weights := Vector3(abs(local_axis.x), abs(local_axis.y), abs(local_axis.z))
	var safe_weights := Vector3(
		max(weights.x, 0.001),
		max(weights.y, 0.001),
		max(weights.z, 0.001)
	)
	var scale_vec := Vector3(
		lerp(1.0, scale_factor, clamp(safe_weights.x, 0.0, 1.0)),
		lerp(1.0, scale_factor, clamp(safe_weights.y, 0.0, 1.0)),
		lerp(1.0, scale_factor, clamp(safe_weights.z, 0.0, 1.0))
	)
	node.scale = node.scale * scale_vec


func _rotate_node_around_axis(node: Node3D, pivot: Vector3, axis: Vector3, angle: float) -> void:
	var basis_rot := Basis(axis, angle)
	var xform := node.global_transform
	var offset := xform.origin - pivot
	offset = basis_rot * offset
	xform.origin = pivot + offset
	xform.basis = basis_rot * xform.basis
	if node is RigidBody3D:
		var rb := node as RigidBody3D
		rb.global_transform = xform
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.sleeping = false
	else:
		node.global_transform = xform


func _project_on_plane(vec: Vector3, axis: Vector3) -> Vector3:
	var n := axis.normalized()
	return vec - n * vec.dot(n)


func _signed_angle_on_plane(ref: Vector3, cur: Vector3, axis: Vector3) -> float:
	var a := ref.normalized()
	var b := cur.normalized()
	var dot_ab: float = clamp(a.dot(b), -1.0, 1.0)
	var cross_ab: Vector3 = a.cross(b)
	var angle := acos(dot_ab)
	var angle_sign := 1.0 if cross_ab.dot(axis) >= 0.0 else -1.0
	return angle * angle_sign


func _any_perpendicular(axis: Vector3) -> Vector3:
	var n := axis.normalized()
	if abs(n.dot(Vector3.UP)) < 0.99:
		return n.cross(Vector3.UP).normalized()
	return n.cross(Vector3.FORWARD).normalized()


func _get_network_manager() -> Node:
	if _network_manager and is_instance_valid(_network_manager):
		return _network_manager
	_network_manager = get_node_or_null("/root/NetworkManager")
	return _network_manager


func _resolve_network_object_id(node: Node3D) -> String:
	if not is_instance_valid(node):
		return ""
	var probe: Node = node
	while probe and probe is Node3D and probe != self:
		if probe.has_method("get"):
			var raw_save_id: Variant = probe.get("save_id")
			var save_id: String = String(raw_save_id) if raw_save_id != null else ""
			if not save_id.is_empty():
				return save_id
		if probe.name.begins_with("obj_"):
			return probe.name
		probe = probe.get_parent()
	return ""


func _claim_network_ownership_for_selection() -> void:
	for node in _selected_objects:
		if is_instance_valid(node):
			_claim_network_ownership_for_object(node)


func _claim_network_ownership_for_object(node: Node3D) -> void:
	var network_manager := _get_network_manager()
	if network_manager == null:
		return
	var object_id := _resolve_network_object_id(node)
	if object_id.is_empty():
		if network_debug_logs:
			_network_log("ownership request skipped; no object id for %s path=%s" % [node.name, str(node.get_path())])
		return
	if _is_locally_authoritative_for_object(network_manager, object_id):
		_owned_selected_object_ids[object_id] = true
		_set_local_network_component_ownership(node, true)
		_network_log("ownership already local for %s" % object_id)
		return
	var now_msec := Time.get_ticks_msec()
	var last_request_msec := int(_ownership_request_msec.get(object_id, 0))
	if _owned_selected_object_ids.has(object_id) and (now_msec - last_request_msec) < OWNERSHIP_REQUEST_RETRY_MS:
		return
	if network_manager.has_method("grab_object"):
		network_manager.grab_object(object_id, "transform_tool")
	elif network_manager.has_method("request_object_ownership"):
		network_manager.request_object_ownership(object_id, "transform_tool")
	else:
		return
	_owned_selected_object_ids[object_id] = true
	_ownership_request_msec[object_id] = now_msec
	_network_log("requested ownership for %s" % object_id)


func _release_network_ownership_for_object(node: Node3D) -> void:
	var object_id := _resolve_network_object_id(node)
	if object_id.is_empty():
		return
	_owned_selected_object_ids.erase(object_id)
	_ownership_request_msec.erase(object_id)
	_last_scale_sync_msec.erase(object_id)
	_last_synced_scale.erase(object_id)

	var network_manager := _get_network_manager()
	if network_manager == null:
		_set_local_network_component_ownership(node, false)
		return
	if not network_manager.has_method("release_object"):
		_set_local_network_component_ownership(node, false)
		return
	if not is_instance_valid(node):
		return
	if not _is_locally_authoritative_for_object(network_manager, object_id):
		_set_local_network_component_ownership(node, false)
		return

	var persist_mode := _resolve_object_persist_mode(network_manager, object_id)
	var rot: Quaternion = node.global_transform.basis.orthonormalized().get_rotation_quaternion().normalized()
	network_manager.release_object(
		object_id,
		node.global_position,
		rot,
		Vector3.ZERO,
		Vector3.ZERO,
		persist_mode,
		"RELEASED_STATIC"
	)
	_set_local_network_component_ownership(node, false)
	_network_log("released ownership for %s" % object_id)


func _release_all_owned_selection_objects() -> void:
	if _owned_selected_object_ids.is_empty():
		return
	var owned_ids: Array = _owned_selected_object_ids.keys()
	for object_id_variant in owned_ids:
		var object_id := String(object_id_variant)
		if object_id.is_empty():
			continue
		var node := _find_selected_object_by_id(object_id)
		if not is_instance_valid(node):
			continue
		_release_network_ownership_for_object(node)
	_owned_selected_object_ids.clear()
	_ownership_request_msec.clear()
	_last_scale_sync_msec.clear()
	_last_synced_scale.clear()


func _find_selected_object_by_id(object_id: String) -> Node3D:
	for node in _selected_objects:
		if not is_instance_valid(node):
			continue
		if _resolve_network_object_id(node) == object_id:
			return node
	return null


func _broadcast_selected_transform_updates(force_scale_sync: bool = false, claim_ownership: bool = true) -> void:
	var network_manager := _get_network_manager()
	if network_manager == null:
		return
	if not network_manager.has_method("update_grabbed_object"):
		return
	if claim_ownership:
		_claim_network_ownership_for_selection()
	var sent_count := 0
	var skipped_not_authoritative := 0
	var skipped_invalid := 0
	var skipped_no_object_id := 0
	var no_object_id_samples: PackedStringArray = PackedStringArray()
	for node in _selected_objects:
		if not is_instance_valid(node):
			skipped_invalid += 1
			continue
		var object_id := _resolve_network_object_id(node)
		if object_id.is_empty():
			skipped_no_object_id += 1
			if no_object_id_samples.size() < 3:
				no_object_id_samples.append("%s(%s)" % [node.name, str(node.get_path())])
			continue
		if not _is_locally_authoritative_for_object(network_manager, object_id):
			skipped_not_authoritative += 1
			continue
		_set_local_network_component_ownership(node, true)
		var rot: Quaternion = node.global_transform.basis.orthonormalized().get_rotation_quaternion().normalized()
		network_manager.update_grabbed_object(object_id, node.global_position, rot)
		_maybe_broadcast_object_scale(network_manager, object_id, node.scale, force_scale_sync)
		sent_count += 1
	if network_debug_logs:
		var now_msec := Time.get_ticks_msec()
		if now_msec - _last_network_sync_log_msec >= NETWORK_LOG_INTERVAL_MS:
			_last_network_sync_log_msec = now_msec
			var sample_text := ", no_id_samples=%s" % str(no_object_id_samples) if not no_object_id_samples.is_empty() else ""
			_network_log("sync sent=%d skipped_not_authoritative=%d skipped_no_object_id=%d skipped_invalid=%d selected=%d%s" % [sent_count, skipped_not_authoritative, skipped_no_object_id, skipped_invalid, _selected_objects.size(), sample_text])


func _resolve_object_persist_mode(network_manager: Node, object_id: String) -> String:
	var persist_mode := "placed_room"
	if network_manager == null:
		return persist_mode
	var registry_variant: Variant = network_manager.get("room_object_registry")
	if registry_variant is Dictionary:
		var registry := registry_variant as Dictionary
		var object_state_variant: Variant = registry.get(object_id, null)
		if object_state_variant is Dictionary:
			var object_state := object_state_variant as Dictionary
			var state_mode := String(object_state.get("persist_mode", ""))
			if not state_mode.is_empty():
				persist_mode = state_mode
	return persist_mode


func _is_locally_authoritative_for_object(network_manager: Node, object_id: String) -> bool:
	if network_manager == null or object_id.is_empty():
		return false
	if not network_manager.has_method("get_nakama_user_id"):
		return false
	var my_id := String(network_manager.get_nakama_user_id())
	if my_id.is_empty():
		return false
	if network_manager.has_method("get_object_owner"):
		var owner_id := String(network_manager.get_object_owner(object_id))
		if not owner_id.is_empty() and owner_id == my_id:
			return true
	var registry_variant: Variant = network_manager.get("room_object_registry")
	if registry_variant is Dictionary:
		var registry := registry_variant as Dictionary
		var state_variant: Variant = registry.get(object_id, null)
		if state_variant is Dictionary:
			var state := state_variant as Dictionary
			var held_by := String(state.get("held_by", ""))
			if held_by == my_id:
				return true
	return false


func _maybe_broadcast_object_scale(network_manager: Node, object_id: String, object_scale: Vector3, force_sync: bool = false) -> void:
	if network_manager == null:
		return
	if not network_manager.has_method("replicate_object_property"):
		return
	var should_send: bool = force_sync or not _last_synced_scale.has(object_id)
	if not should_send:
		var previous_scale: Vector3 = _last_synced_scale[object_id]
		should_send = previous_scale.distance_to(object_scale) > SCALE_SYNC_EPSILON
	if not should_send:
		return
	var now_msec := Time.get_ticks_msec()
	var last_sent_msec := int(_last_scale_sync_msec.get(object_id, 0))
	if not force_sync and now_msec - last_sent_msec < SCALE_SYNC_INTERVAL_MS:
		return
	network_manager.replicate_object_property(object_id, "scale", object_scale, false)
	_last_scale_sync_msec[object_id] = now_msec
	_last_synced_scale[object_id] = object_scale


func _set_local_network_component_ownership(node: Node3D, is_owner: bool) -> void:
	if not is_instance_valid(node):
		return
	if not node.has_method("get"):
		return
	var network_component_variant: Variant = node.get("network_component")
	if not (network_component_variant is Node):
		return
	var network_component := network_component_variant as Node
	if network_component.has_method("set_network_owner"):
		network_component.call("set_network_owner", is_owner)
	if network_component.has_method("set_grabbed"):
		network_component.call("set_grabbed", is_owner)


func _network_log(message: String) -> void:
	if not network_debug_logs:
		return
	print("TransformTool Net: ", message)


func _update_controls_scale(force: bool = false) -> void:
	var next_scale := _resolve_controls_scale_multiplier()
	if not force and is_equal_approx(next_scale, _last_applied_controls_scale):
		return
	_controls_scale_multiplier = next_scale
	_last_applied_controls_scale = next_scale
	_apply_indicator_size()
	_apply_hit_marker_size()


func _resolve_controls_scale_multiplier() -> float:
	if not scale_controls_with_tool and not scale_controls_with_player:
		return 1.0
	return clampf(_get_tool_scale_multiplier(), controls_scale_min, controls_scale_max)


func _get_tool_scale_multiplier() -> float:
	var global_scale := global_transform.basis.get_scale()
	var approx_uniform := (absf(global_scale.x) + absf(global_scale.y) + absf(global_scale.z)) / 3.0
	if is_finite(approx_uniform):
		return maxf(approx_uniform, 0.0001)
	var local_scale := scale
	var local_uniform := (absf(local_scale.x) + absf(local_scale.y) + absf(local_scale.z)) / 3.0
	if is_finite(local_uniform):
		return maxf(local_uniform, 0.0001)
	return 1.0


# === Public API ===

func set_indicator_size_preset(index: int) -> void:
	if index >= 0 and index < indicator_size_presets.size():
		indicator_size_preset_index = index
		indicator_size = indicator_size_presets[index]
		_apply_indicator_size()
		print("TransformTool: Indicator size preset ", index, " = ", indicator_size)


func cycle_indicator_size_preset(forward: bool = true) -> void:
	var new_index = indicator_size_preset_index
	if forward:
		new_index = (new_index + 1) % indicator_size_presets.size()
	else:
		new_index = (new_index - 1 + indicator_size_presets.size()) % indicator_size_presets.size()
	set_indicator_size_preset(new_index)


func toggle_always_visible() -> void:
	always_show_ray = not always_show_ray
	always_show_indicator = not always_show_indicator
	print("TransformTool: Always visible = ", always_show_ray)


func get_current_indicator_size() -> float:
	return indicator_size
