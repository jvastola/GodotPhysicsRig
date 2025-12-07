extends Node3D

signal pointer_event(event: Dictionary)
signal hit_scale_changed(scale: float)

# hand_pointer.gd
# Provides a versatile pointer that can interact with UI controls, specialised
# interactables (such as the SubdividedColorCube), or generic grabbable-like
# actors. Interaction details are packaged into a dictionary and dispatched to
# the first ancestor that implements `handle_pointer_event(event)` or belongs to
# the exported handler group.

@export var pointer_face_path: NodePath = "PointerFace"
@export var raycast_node_path: NodePath = "PointerRayCast"
@export var ray_visual_node_path: NodePath = "PointerRayVisual"
@export var ray_hit_node_path: NodePath = "PointerRayHit"
@export var pointer_axis_local: Vector3 = Vector3(0, 0, -1)
@export_range(0.1, 20.0, 0.1) var ray_length: float = 3.0
@export_range(0.1, 20.0, 0.1) var ray_length_min: float = 0.25
@export_range(0.1, 20.0, 0.1) var ray_length_max: float = 10.0
@export_range(0.1, 10.0, 0.1) var ray_length_adjust_speed: float = 3.0
@export var ray_length_axis_action: String = "primary"
@export var require_trigger_for_length_adjust: bool = true
@export_range(0.0, 1.0, 0.01) var ray_length_adjust_deadzone: float = 0.2

@export var hide_face_on_player_hit: bool = true
@export var player_group: StringName = &"player"

@export_flags_3d_physics var pointer_collision_mask: int = 1 << 5
@export var pointer_handler_group: StringName = &"pointer_interactable"
@export var interact_action: String = "trigger_click"
@export_range(0.0, 1.0, 0.01) var fallback_trigger_threshold: float = 0.5
@export var send_hover_events: bool = true
@export var send_hold_events: bool = true
@export var include_pointer_color: bool = false
@export var pointer_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var secondary_action: String = "by_button" # Quest/Oculus B or Y button
@export var enable_secondary_long_press: bool = true
@export_range(0.1, 2.0, 0.05) var secondary_long_press_time: float = 0.65
@export var collide_with_areas: bool = true
@export var collide_with_bodies: bool = true
@export_enum("always", "on_hit", "on_trigger", "on_hit_or_trigger", "on_hit_and_trigger") var ray_visibility_mode: String = "always"
@export var require_trigger_for_hit_scaling: bool = true
@export var enable_hit_scaling: bool = true
@export_enum("on_hit", "always", "on_trigger", "on_hit_or_trigger", "on_hit_and_trigger") var hit_visibility_mode: String = "on_hit"
@export_enum("cylinder", "sphere") var hit_shape: String = "cylinder"
@export var hit_color: Color = Color(0.9, 0.9, 1.0, 0.35)
@export var hit_material_unshaded: bool = true
@export var enable_hit_selector: bool = true
@export_flags_3d_physics var hit_selector_collision_mask: int = 1 << 5
@export var hit_selector_monitor_bodies: bool = true
@export var hit_selector_monitor_areas: bool = true

# Grip-based grab mode: hold grip while pointing at an object to grab and manipulate it
@export_group("Grip Grab Mode")
@export var enable_grip_grab: bool = true
@export var grip_action: String = "grip"  # Grip button to activate grab mode
@export_range(0.0, 1.0, 0.01) var grip_threshold: float = 0.5
@export_range(0.1, 10.0, 0.1) var grab_distance_adjust_speed: float = 2.0
@export_range(0.1, 5.0, 0.1) var grab_scale_adjust_speed: float = 1.0
@export_range(0.1, 5.0, 0.1) var grab_min_scale: float = 0.2
@export_range(0.5, 10.0, 0.1) var grab_max_scale: float = 5.0
@export_range(0.1, 20.0, 0.1) var grab_min_distance: float = 0.3
@export_range(0.5, 50.0, 0.1) var grab_max_distance: float = 20.0
# Layer mask for objects that should rotate to face user when grabbed (default: Layer 6 for UI)
@export_flags_3d_physics var grab_rotation_mask: int = 1 << 5

@onready var _pointer_face: MeshInstance3D = get_node_or_null(pointer_face_path) as MeshInstance3D
@onready var _raycast: RayCast3D = get_node_or_null(raycast_node_path) as RayCast3D
@onready var _ray_visual: MeshInstance3D = get_node_or_null(ray_visual_node_path) as MeshInstance3D
@onready var _ray_hit: MeshInstance3D = get_node_or_null(ray_hit_node_path) as MeshInstance3D

@export var hit_scale_per_meter: float = 0.02
@export var hit_min_scale: float = 0.01
@export var hit_max_scale: float = 0.2
@export_range(1.0, 20.0, 0.1) var hit_far_distance: float = 8.0
@export_range(0.05, 1.0, 0.01) var hit_far_scale: float = 0.35
@export var use_hit_scale_limits: bool = false
@export_range(0.05, 1.5, 0.01) var hit_scale_user_multiplier_min: float = 0.25
@export_range(0.05, 2.0, 0.01) var hit_scale_user_multiplier_max: float = 1.5
@export_range(0.05, 2.0, 0.01) var hit_scale_adjust_speed: float = 0.75

var _line_mesh: ImmediateMesh
var _hover_target: Node = null
var _hover_collider: Object = null
var _last_event: Dictionary = {}
var _controller_cache: XRController3D = null
var _prev_action_pressed: bool = false
var _prev_secondary_pressed: bool = false
var _secondary_active: bool = false
var _secondary_source: String = "" # "button" or "long_press"
var _secondary_hold_time: float = 0.0
var _hit_scale_user_multiplier: float = 1.0
var _last_emitted_hit_scale: float = -1.0
var _movement_component: PlayerMovementComponent = null
var _ui_scroll_active: bool = false
var _hit_selector_area: Area3D
var _hit_selector_shape: CollisionShape3D
var _selection_bounds: MeshInstance3D
var _selection_bounds_mesh: ImmediateMesh
var _selected_objects: Array[Node3D] = []

# Grip grab mode state
var _grab_target: Node = null  # Currently grabbed object
var _grab_distance: float = 0.0  # Current distance from pointer origin
var _grab_initial_scale: Vector3 = Vector3.ONE  # Scale when grab started
var _grab_offset: Vector3 = Vector3.ZERO  # Offset from grab point to object center
var _prev_grip_pressed: bool = false  # For edge detection
var _grab_should_rotate: bool = false # Whether current grab target allows rotation

func _ready() -> void:
	_clamp_ray_length()
	if _pointer_face:
		_pointer_face.visible = true

	if _raycast:
		var axis: Vector3 = pointer_axis_local.normalized()
		if axis.length_squared() > 0.0:
			_raycast.target_position = axis * ray_length
		_raycast.enabled = true
		_raycast.collide_with_areas = collide_with_areas
		_raycast.collide_with_bodies = collide_with_bodies
		if pointer_collision_mask > 0:
			_raycast.collision_mask = pointer_collision_mask

	if _ray_visual:
		var mesh := _ray_visual.mesh
		if mesh is ImmediateMesh:
			_line_mesh = mesh
		else:
			_line_mesh = ImmediateMesh.new()
			_ray_visual.mesh = _line_mesh
		_ray_visual.visible = true

	if _ray_hit:
		_configure_hit_visual()
		_ray_hit.visible = false
		_setup_hit_selector()
	_setup_selection_bounds()


func _configure_hit_visual() -> void:
	if not _ray_hit:
		return
	_ray_hit.mesh = _create_hit_mesh()
	_ray_hit.material_override = _build_hit_material()


func _create_hit_mesh() -> PrimitiveMesh:
	var base_radius: float = max(hit_min_scale, 0.001)
	match hit_shape:
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = base_radius
			sphere.height = base_radius * 2.0
			sphere.radial_segments = 16
			return sphere
		_:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = base_radius
			cylinder.bottom_radius = base_radius
			cylinder.height = max(base_radius * 0.1, 0.0005)
			cylinder.radial_segments = 16
			return cylinder


func _build_hit_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	if hit_material_unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = hit_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func _setup_hit_selector() -> void:
	if not enable_hit_selector:
		return
	_hit_selector_area = Area3D.new()
	_hit_selector_area.name = "HitSelectorArea"
	_hit_selector_area.monitoring = false
	_hit_selector_area.monitorable = true
	_hit_selector_area.collision_mask = hit_selector_collision_mask
	_hit_selector_area.collision_layer = 0
	_hit_selector_area.body_entered.connect(_on_hit_selector_body_entered)
	_hit_selector_area.area_entered.connect(_on_hit_selector_area_entered)
	add_child(_hit_selector_area)
	
	_hit_selector_shape = CollisionShape3D.new()
	_hit_selector_shape.name = "HitSelectorShape"
	_hit_selector_shape.shape = _build_selector_shape(hit_min_scale)
	_hit_selector_area.add_child(_hit_selector_shape)


func _build_selector_shape(radius: float) -> Shape3D:
	if hit_shape == "sphere":
		var sphere := SphereShape3D.new()
		sphere.radius = radius
		return sphere
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = max(radius * 0.2, 0.0005)
	return cylinder


func _update_selector_shape(scale: float) -> void:
	if not _hit_selector_shape or not _hit_selector_shape.shape:
		return
	var radius: float = max(scale, 0.0005)
	if _hit_selector_shape.shape is SphereShape3D:
		var sphere := _hit_selector_shape.shape as SphereShape3D
		sphere.radius = radius
	elif _hit_selector_shape.shape is CylinderShape3D:
		var cylinder := _hit_selector_shape.shape as CylinderShape3D
		cylinder.radius = radius
		cylinder.height = max(radius * 0.2, 0.0005)


func _setup_selection_bounds() -> void:
	_selection_bounds_mesh = ImmediateMesh.new()
	_selection_bounds = MeshInstance3D.new()
	_selection_bounds.name = "SelectionBounds"
	_selection_bounds.mesh = _selection_bounds_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.2, 0.8, 1.0, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_selection_bounds.material_override = mat
	_selection_bounds.visible = false
	add_child(_selection_bounds)


func _update_hit_selector(action_state: Dictionary, has_hit: bool, hit_scale: float, hit_transform: Transform3D) -> void:
	if not enable_hit_selector or not _hit_selector_area:
		return
	var active: bool = action_state.get("pressed", false) and has_hit
	_hit_selector_area.monitoring = active
	_hit_selector_area.monitorable = active
	_hit_selector_area.global_transform = hit_transform
	if active:
		_update_selector_shape(hit_scale)


func _on_hit_selector_body_entered(body: Node) -> void:
	if not hit_selector_monitor_bodies:
		return
	_add_selected_object(body)


func _on_hit_selector_area_entered(area: Area3D) -> void:
	if not hit_selector_monitor_areas:
		return
	_add_selected_object(area)


func _add_selected_object(node: Node) -> void:
	if not (node is Node3D):
		return
	var node3d := node as Node3D
	if node3d == self or _selected_objects.has(node3d):
		return
	_selected_objects.append(node3d)
	_update_selection_bounds()


func _prune_selected_objects() -> void:
	for i in range(_selected_objects.size() - 1, -1, -1):
		if not is_instance_valid(_selected_objects[i]):
			_selected_objects.remove_at(i)


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
	if has_box:
		return combined
	return AABB()


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
		ConvexPolygonShape3D, ConcavePolygonShape3D, HeightMapShape3D:
			var mesh := shape.get_debug_mesh()
			if mesh:
				local = mesh.get_aabb()
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


func _draw_selection_bounds(aabb: AABB) -> void:
	if not _selection_bounds_mesh:
		return
	_selection_bounds_mesh.clear_surfaces()
	if aabb.size == Vector3.ZERO:
		_selection_bounds.visible = false
		return
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
	_selection_bounds_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
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


func _update_selection_bounds() -> void:
	if not _selection_bounds_mesh:
		return
	var combined := _compute_selection_aabb()
	if combined.size == Vector3.ZERO:
		_selection_bounds.visible = false
		_selection_bounds_mesh.clear_surfaces()
		return
	_draw_selection_bounds(combined)


func _clear_selection() -> void:
	_selected_objects.clear()
	if _selection_bounds_mesh:
		_selection_bounds_mesh.clear_surfaces()
	if _selection_bounds:
		_selection_bounds.visible = false

func _physics_process(delta: float) -> void:
	if not _raycast:
		return
	_get_movement_component()

	if _hover_target and not is_instance_valid(_hover_target):
		_hover_target = null
		_hover_collider = null
		_last_event = {}

	var axis_local: Vector3 = pointer_axis_local.normalized()
	if axis_local.length_squared() <= 0.0:
		return

	var controller: XRController3D = _get_pointer_controller()
	var action_state: Dictionary = _gather_action_state(controller)
	_apply_ray_length_adjustment(delta, controller, action_state)
	_apply_hit_scale_adjustment(delta, controller, action_state)
	_clamp_ray_length()
	
	# Process grip grab mode (must be done before normal pointer events)
	_process_grip_grab_mode(delta, controller)

	_raycast.target_position = axis_local * ray_length
	_raycast.force_raycast_update()

	var axis_world: Vector3 = (global_transform.basis * axis_local).normalized()
	var start: Vector3 = global_transform.origin
	var end: Vector3 = start + axis_world * ray_length
	var normal: Vector3 = -axis_world
	var distance: float = ray_length
	var collider_obj: Object = null
	var handler: Node = null
	var hit_player: bool = false
	var has_hit: bool = _raycast.is_colliding()
	var hit_transform := Transform3D.IDENTITY
	if action_state["just_pressed"] and not has_hit:
		_clear_selection()
	
	# Debug logging for Android troubleshooting
	var is_android = OS.get_name() == "Android"

	if has_hit:
		end = _raycast.get_collision_point()
		distance = start.distance_to(end)
		var raw_normal: Vector3 = _raycast.get_collision_normal()
		if raw_normal.length_squared() > 0.0:
			normal = raw_normal.normalized()
		collider_obj = _raycast.get_collider()
		var collider_node: Node = collider_obj as Node
		if collider_node and hide_face_on_player_hit and collider_node.is_in_group(player_group):
			hit_player = true
			handler = null
		else:
			handler = _resolve_handler(collider_obj)
			if handler and not is_instance_valid(handler):
				handler = null
		
		# Debug: Log hit info on Android
		if is_android and action_state["just_pressed"]:
			print("HandPointer: Hit on Android - collider=", collider_obj, " handler=", handler)
			print("  - collision_mask=", _raycast.collision_mask, " point=", end)

	if handler:
		var base_event: Dictionary = _build_event(handler, collider_obj, end, normal, axis_world, start, distance, action_state, controller)
		if handler != _hover_target:
			_clear_hover_state()
			_hover_target = handler
			_hover_collider = collider_obj
			_last_event = base_event.duplicate(true)
			_emit_event(handler, "enter", base_event)
		else:
			_last_event = base_event.duplicate(true)

		if send_hover_events:
			_emit_event(handler, "hover", base_event)
		if action_state["just_pressed"]:
			_emit_event(handler, "press", base_event)
		if send_hold_events and action_state["pressed"]:
			_emit_event(handler, "hold", base_event)
		if action_state["just_released"]:
			_emit_event(handler, "release", base_event)
		_process_secondary_actions(handler, base_event, action_state, controller, delta)
		_process_ui_scroll(handler, base_event, controller, delta)
	else:
		_clear_hover_state()
		_clear_ui_scroll_capture(controller)

	var hit_scale: float = _compute_hit_scale(distance)
	_maybe_emit_hit_scale(hit_scale)

	if _ray_hit:
		var show_hit: bool = _should_show_hit_visual(action_state, has_hit)
		_ray_hit.visible = show_hit
		if show_hit:
			var hit_xform: Transform3D = _ray_hit.global_transform
			hit_xform.origin = end
			var orient_normal: Vector3 = normal
			if orient_normal.length_squared() <= 0.0:
				orient_normal = -axis_world
			var y: Vector3 = orient_normal.normalized()
			var up: Vector3 = Vector3.UP
			if abs(y.dot(up)) > 0.999:
				up = Vector3.FORWARD
			var x: Vector3 = up.cross(y).normalized()
			var z: Vector3 = y.cross(x).normalized()
			hit_transform = Transform3D(Basis(x, y, z), end)
			# Create a basis scaled by the desired scale factor so we don't overwrite
			# node scale by setting global_transform after changing scale.
			var scale_factor: float = hit_scale
			var scaled_x: Vector3 = x * scale_factor
			var scaled_y: Vector3 = y * scale_factor
			var scaled_z: Vector3 = z * scale_factor
			hit_xform.basis = Basis(scaled_x, scaled_y, scaled_z)
			_ray_hit.global_transform = hit_xform
		else:
			hit_transform.origin = end
	else:
		hit_transform.origin = end

	_update_hit_selector(action_state, has_hit, hit_scale, hit_transform)
	_update_selection_bounds()

	if _ray_visual and _line_mesh:
		var show_ray: bool = _should_show_ray_visual(action_state, has_hit)
		_ray_visual.visible = show_ray
		if show_ray:
			var local_end: Vector3 = axis_local * distance
			_line_mesh.clear_surfaces()
			_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			_line_mesh.surface_add_vertex(Vector3.ZERO)
			_line_mesh.surface_add_vertex(local_end)
			_line_mesh.surface_end()

	if _pointer_face and hide_face_on_player_hit:
		_pointer_face.visible = not hit_player

func _get_pointer_controller() -> XRController3D:
	if _controller_cache and is_instance_valid(_controller_cache):
		return _controller_cache
	var node: Node = get_parent()
	while node:
		if node is XRController3D:
			_controller_cache = node
			return _controller_cache
		node = node.get_parent()
	return null

func _gather_action_state(controller: XRController3D) -> Dictionary:
	var state: Dictionary = {
		"pressed": false,
		"just_pressed": false,
		"just_released": false,
		"strength": 0.0
	}

	if interact_action != "" and InputMap.has_action(interact_action):
		state["pressed"] = Input.is_action_pressed(interact_action)
		state["just_pressed"] = Input.is_action_just_pressed(interact_action)
		state["just_released"] = Input.is_action_just_released(interact_action)
		state["strength"] = Input.get_action_strength(interact_action)
	else:
		var value: float = 0.0
		if controller and controller.has_method("get_float"):
			value = controller.get_float("trigger")
		state["strength"] = value
		state["pressed"] = value >= fallback_trigger_threshold
		state["just_pressed"] = state["pressed"] and not _prev_action_pressed
		state["just_released"] = (not state["pressed"]) and _prev_action_pressed

	_prev_action_pressed = state["pressed"]
	return state


func _is_action_pressed(controller: XRController3D, action_name: String) -> bool:
	if action_name == "":
		return false
	if InputMap.has_action(action_name) and Input.is_action_pressed(action_name):
		return true
	if controller:
		if controller.has_method("get_pressed") and controller.get_pressed(action_name):
			return true
		if controller.has_method("get_bool") and controller.get_bool(action_name):
			return true
		if controller.has_method("get_button") and controller.get_button(action_name):
			return true
		if controller.has_method("is_button_pressed") and controller.is_button_pressed(action_name):
			return true
		if controller.has_method("get_float") and abs(controller.get_float(action_name)) > 0.5:
			return true
		if controller.has_method("get_axis") and abs(controller.get_axis(action_name)) > 0.5:
			return true
		if controller.has_method("get_vector2"):
			var v2 := controller.get_vector2(action_name)
			if v2.length() > 0.5:
				return true
	return false

func _apply_ray_length_adjustment(delta: float, controller: XRController3D, action_state: Dictionary) -> void:
	if ray_length_axis_action == "":
		return
	if require_trigger_for_length_adjust and not action_state.get("pressed", false):
		return
	var input_value: float = _get_ray_length_input_value(controller)
	if abs(input_value) <= ray_length_adjust_deadzone:
		return
	ray_length = clamp(ray_length + input_value * ray_length_adjust_speed * delta, ray_length_min, ray_length_max)

func _apply_hit_scale_adjustment(delta: float, controller: XRController3D, action_state: Dictionary) -> void:
	if not enable_hit_scaling:
		return
	if ray_length_axis_action == "" or not controller:
		return
	if require_trigger_for_hit_scaling and not action_state.get("pressed", false):
		return
	var vec: Vector2 = _get_pointer_axis_vector(controller)
	var lateral_input: float = vec.x
	if abs(lateral_input) <= ray_length_adjust_deadzone:
		return
	_hit_scale_user_multiplier = clamp(_hit_scale_user_multiplier + lateral_input * hit_scale_adjust_speed * delta, hit_scale_user_multiplier_min, hit_scale_user_multiplier_max)

func _get_ray_length_input_value(controller: XRController3D) -> float:
	return _get_pointer_axis_vector(controller).y

func _get_pointer_axis_vector(controller: XRController3D) -> Vector2:
	if not controller:
		return Vector2.ZERO
	if controller.has_method("get_vector2"):
		return controller.get_vector2(ray_length_axis_action)
	elif controller.has_method("get_axis"):
		var v: float = controller.get_axis(ray_length_axis_action)
		return Vector2(v, v)
	elif controller.has_method("get_float"):
		var f := controller.get_float(ray_length_axis_action)
		return Vector2(f, f)
	return Vector2.ZERO

func _clamp_ray_length() -> void:
	if ray_length_min > ray_length_max:
		var temp := ray_length_min
		ray_length_min = ray_length_max
		ray_length_max = temp
	ray_length = clamp(ray_length, ray_length_min, ray_length_max)

func _should_show_ray_visual(action_state: Dictionary, has_hit: bool) -> bool:
	match ray_visibility_mode:
		"always":
			return true
		"on_hit":
			return has_hit
		"on_trigger":
			return action_state.get("pressed", false)
		"on_hit_or_trigger":
			return has_hit or action_state.get("pressed", false)
		"on_hit_and_trigger":
			return has_hit and action_state.get("pressed", false)
		_:
			return true

func _should_show_hit_visual(action_state: Dictionary, has_hit: bool) -> bool:
	match hit_visibility_mode:
		"always":
			return true
		"on_hit":
			return has_hit
		"on_trigger":
			return action_state.get("pressed", false)
		"on_hit_or_trigger":
			return has_hit or action_state.get("pressed", false)
		"on_hit_and_trigger":
			return has_hit and action_state.get("pressed", false)
		_:
			return true

func _compute_hit_scale(distance: float) -> float:
	if not use_hit_scale_limits:
		var unclamped_scale: float = max(distance * hit_scale_per_meter, hit_min_scale)
		return unclamped_scale * _hit_scale_user_multiplier
	var near_reference: float = 1.5
	var near_t: float = clamp(distance / near_reference, 0.0, 1.0)
	var scale_factor: float = lerp(hit_min_scale, hit_max_scale, near_t)
	if distance <= near_reference:
		return scale_factor * _hit_scale_user_multiplier
	var far_range: float = max(hit_far_distance - near_reference, 0.001)
	var far_t: float = clamp((distance - near_reference) / far_range, 0.0, 1.0)
	var far_scale: float = lerp(scale_factor, hit_far_scale, far_t)
	return far_scale * _hit_scale_user_multiplier

func _maybe_emit_hit_scale(hit_scale: float) -> void:
	if not is_finite(hit_scale):
		return
	if _last_emitted_hit_scale < 0.0 or abs(hit_scale - _last_emitted_hit_scale) > 0.0005:
		_last_emitted_hit_scale = hit_scale
		hit_scale_changed.emit(hit_scale)

func _build_event(handler: Node, collider: Object, hit_point: Vector3, normal: Vector3, axis_world: Vector3, start: Vector3, distance: float, action_state: Dictionary, controller: XRController3D) -> Dictionary:
	var event: Dictionary = {
		"pointer": self,
		"controller": controller,
		"collider": collider,
		"handler": handler,
		"global_position": hit_point,
		"global_normal": normal,
		"pointer_origin": start,
		"pointer_direction": axis_world,
		"distance": distance,
		"action": interact_action,
		"action_pressed": action_state.get("pressed", false),
		"action_just_pressed": action_state.get("just_pressed", false),
		"action_just_released": action_state.get("just_released", false),
		"action_strength": action_state.get("strength", 0.0)
	}
	if controller and controller.has_method("get_tracker_hand"):
		event["controller_hand"] = controller.get_tracker_hand()
	if handler and handler is Node3D:
		var handler3d := handler as Node3D
		event["local_position"] = handler3d.to_local(hit_point)
		event["local_normal"] = (handler3d.global_transform.basis.transposed() * normal).normalized()
	if include_pointer_color:
		event["pointer_color"] = pointer_color
	return event

func _emit_event(target: Node, event_type: StringName, base_event: Dictionary) -> void:
	var payload: Dictionary = base_event.duplicate(true)
	payload["type"] = event_type
	pointer_event.emit(payload.duplicate(true))
	if not target or not is_instance_valid(target):
		return
	var handler_payload: Dictionary = payload.duplicate(true)
	if target.has_method("handle_pointer_event"):
		target.call_deferred("handle_pointer_event", handler_payload)
	elif pointer_handler_group != StringName() and target.is_in_group(pointer_handler_group):
		var method_name: String = "pointer_" + String(event_type)
		if target.has_method(method_name):
			target.call_deferred(method_name, handler_payload)


func _process_secondary_actions(handler: Node, base_event: Dictionary, action_state: Dictionary, controller: XRController3D, delta: float) -> void:
	if not handler or not is_instance_valid(handler):
		_reset_secondary_state()
		return

	var button_pressed: bool = _is_action_pressed(controller, secondary_action)
	var should_press: bool = false
	var should_release: bool = false
	var reason: String = ""

	if button_pressed and not _prev_secondary_pressed and not _secondary_active:
		should_press = true
		reason = "button"
	elif _prev_secondary_pressed and not button_pressed and _secondary_active and _secondary_source == "button":
		should_release = true
		reason = "button"

	_prev_secondary_pressed = button_pressed

	if enable_secondary_long_press:
		if action_state.get("pressed", false):
			_secondary_hold_time += delta
			if not _secondary_active and _secondary_hold_time >= secondary_long_press_time:
				should_press = true
				reason = "long_press"
		else:
			if _secondary_active and _secondary_source == "long_press":
				should_release = true
				reason = "long_press"
			_secondary_hold_time = 0.0

	if should_press:
		_secondary_active = true
		_secondary_source = reason if reason != "" else "button"
		var secondary_event := base_event.duplicate(true)
		secondary_event["secondary_action"] = secondary_action
		secondary_event["secondary_reason"] = _secondary_source
		secondary_event["secondary_just_pressed"] = true
		secondary_event["secondary_pressed"] = true
		_emit_event(handler, "secondary_press", secondary_event)

	if should_release:
		var secondary_event := base_event.duplicate(true)
		secondary_event["secondary_action"] = secondary_action
		secondary_event["secondary_reason"] = _secondary_source
		secondary_event["secondary_just_released"] = true
		secondary_event["secondary_pressed"] = false
		_emit_event(handler, "secondary_release", secondary_event)
		_secondary_active = false
		_secondary_source = ""
		_secondary_hold_time = 0.0

func _process_ui_scroll(handler: Node, base_event: Dictionary, controller: XRController3D, _delta: float) -> void:
	var movement := _get_movement_component()
	if not movement or not movement.ui_scroll_steals_stick:
		_clear_ui_scroll_capture(controller, movement)
		return
	if not handler or not is_instance_valid(handler):
		_clear_ui_scroll_capture(controller, movement)
		return
	if not controller:
		_clear_ui_scroll_capture(controller, movement)
		return

	var axis: Vector2 = _get_pointer_axis_vector(controller)
	var scroll_value: float = axis.y
	if abs(scroll_value) <= movement.ui_scroll_deadzone:
		_clear_ui_scroll_capture(controller, movement)
		return

	var scroll_event := base_event.duplicate(true)
	scroll_event["type"] = "scroll"
	scroll_event["scroll_value"] = scroll_value
	scroll_event["scroll_vector"] = axis
	scroll_event["scroll_wheel_factor"] = movement.ui_scroll_wheel_factor * _delta
	_emit_event(handler, "scroll", scroll_event)

	movement.set_ui_scroll_capture(true, controller)
	_ui_scroll_active = true

func _clear_ui_scroll_capture(controller: XRController3D, movement: PlayerMovementComponent = null) -> void:
	var move_ref := movement if movement else _movement_component
	if _ui_scroll_active and move_ref:
		move_ref.set_ui_scroll_capture(false, controller)
	_ui_scroll_active = false

func _get_movement_component() -> PlayerMovementComponent:
	if _movement_component and is_instance_valid(_movement_component):
		return _movement_component
	var player := get_tree().get_first_node_in_group("xr_player")
	if player:
		_movement_component = player.get_node_or_null("PlayerMovementComponent")
	return _movement_component

func _resolve_handler(target: Object) -> Node:
	var node: Node = target as Node
	while node:
		if node == self:
			break
		if pointer_handler_group != StringName() and node.is_in_group(pointer_handler_group):
			return node
		if node.has_method("handle_pointer_event"):
			return node
		node = node.get_parent()
	return null

func _clear_hover_state() -> void:
	if _hover_target and is_instance_valid(_hover_target) and not _last_event.is_empty():
		if _secondary_active:
			var secondary_event := _last_event.duplicate(true)
			secondary_event["secondary_action"] = secondary_action
			secondary_event["secondary_reason"] = _secondary_source
			secondary_event["secondary_just_released"] = true
			secondary_event["secondary_pressed"] = false
			_emit_event(_hover_target, "secondary_release", secondary_event)
		_emit_event(_hover_target, "exit", _last_event)
	_clear_ui_scroll_capture(_get_pointer_controller())
	_hover_target = null
	_hover_collider = null
	_last_event = {}
	_reset_secondary_state()


func _reset_secondary_state() -> void:
	_prev_secondary_pressed = false
	_secondary_active = false
	_secondary_source = ""
	_secondary_hold_time = 0.0


# ============================================================================
# GRIP GRAB MODE
# ============================================================================

func _process_grip_grab_mode(delta: float, controller: XRController3D) -> void:
	"""Process grip-based grab mode for manipulating objects at a distance."""
	if not enable_grip_grab or not controller:
		return
	
	# Get grip state
	var grip_value: float = 0.0
	if controller.has_method("get_float"):
		grip_value = controller.get_float(grip_action)
	var grip_pressed: bool = grip_value >= grip_threshold
	var grip_just_pressed: bool = grip_pressed and not _prev_grip_pressed
	var grip_just_released: bool = not grip_pressed and _prev_grip_pressed
	_prev_grip_pressed = grip_pressed
	
	# Handle grab initiation
	if grip_just_pressed:
		_try_start_grab()
	
	# Handle grab release
	if grip_just_released:
		_end_grab()
	
	# Process grab manipulation if actively grabbing
	if _grab_target and is_instance_valid(_grab_target) and grip_pressed:
		_update_grabbed_object(delta, controller)
	elif _grab_target and not is_instance_valid(_grab_target):
		# Target became invalid, clean up
		_grab_target = null


func _try_start_grab() -> void:
	"""Attempt to start grabbing the currently hovered target."""
	if not _hover_target or not is_instance_valid(_hover_target):
		return
	
	# Check if target supports pointer grab
	if not _hover_target.has_method("pointer_grab_set_distance"):
		# Fall back to checking if it's a Node3D we can manipulate
		if not _hover_target is Node3D:
			return
	
	_grab_target = _hover_target
	_grab_should_rotate = false
	
	# Check if we should allow rotation based on collision layer
	if _hover_target is CollisionObject3D:
		var col_obj = _hover_target as CollisionObject3D
		if (col_obj.collision_layer & grab_rotation_mask) != 0:
			_grab_should_rotate = true
	# Also allow rotation if target is NOT a collision object (fallback) or if we hit a UI static body
	elif _hover_collider is CollisionObject3D:
		var col_obj = _hover_collider as CollisionObject3D
		if (col_obj.collision_layer & grab_rotation_mask) != 0:
			_grab_should_rotate = true
	
	# Get initial distance from pointer
	var axis_local: Vector3 = pointer_axis_local.normalized()
	var axis_world: Vector3 = (global_transform.basis * axis_local).normalized()
	var start: Vector3 = global_transform.origin
	
	if _hover_target is Node3D:
		var target_3d: Node3D = _hover_target as Node3D
		
		# Get the actual hit point from raycast for offset calculation
		var hit_point: Vector3 = target_3d.global_position  # default to center
		if _raycast and _raycast.is_colliding():
			hit_point = _raycast.get_collision_point()
		
		# Calculate offset from hit point to object center (in object's local space)
		_grab_offset = target_3d.global_position - hit_point
		
		# Calculate distance along ray to HIT POINT (not object center)
		var to_hit: Vector3 = hit_point - start
		_grab_distance = to_hit.dot(axis_world)
		_grab_distance = clamp(_grab_distance, grab_min_distance, grab_max_distance)
		_grab_initial_scale = target_3d.scale
	else:
		_grab_distance = ray_length
		_grab_initial_scale = Vector3.ONE
		_grab_offset = Vector3.ZERO
	
	print("HandPointer: Started grab on ", _grab_target.name, " at distance ", _grab_distance, " offset ", _grab_offset)


func _end_grab() -> void:
	"""End the current grab."""
	if _grab_target:
		print("HandPointer: Ended grab on ", _grab_target.name if is_instance_valid(_grab_target) else "invalid")
	_grab_target = null
	_grab_distance = 0.0
	_grab_distance = 0.0
	_grab_initial_scale = Vector3.ONE
	_grab_offset = Vector3.ZERO
	_grab_should_rotate = false


func _update_grabbed_object(delta: float, controller: XRController3D) -> void:
	"""Update the grabbed object's position and scale based on joystick input."""
	if not _grab_target or not is_instance_valid(_grab_target):
		return
	
	# Get joystick input
	var joystick: Vector2 = _get_pointer_axis_vector(controller)
	
	# Apply deadzone
	if abs(joystick.y) < ray_length_adjust_deadzone:
		joystick.y = 0.0
	if abs(joystick.x) < ray_length_adjust_deadzone:
		joystick.x = 0.0
	
	# Adjust distance (joystick Y = forward/back)
	if joystick.y != 0.0:
		_grab_distance += joystick.y * grab_distance_adjust_speed * delta
		_grab_distance = clamp(_grab_distance, grab_min_distance, grab_max_distance)
	
	# Adjust scale (joystick X = left/right)
	var scale_delta: float = 0.0
	if joystick.x != 0.0:
		scale_delta = joystick.x * grab_scale_adjust_speed * delta
	
	# Calculate grab point on ray, then add offset to get object center
	var axis_local: Vector3 = pointer_axis_local.normalized()
	var axis_world: Vector3 = (global_transform.basis * axis_local).normalized()
	var start: Vector3 = global_transform.origin
	var grab_point: Vector3 = start + axis_world * _grab_distance
	
	# Apply changes to grabbed object
	if _grab_target is Node3D:
		var target_3d: Node3D = _grab_target as Node3D
		
		# Position the object so the grab point is on the ray
		# grab_point is where we grabbed, _grab_offset is vector from grab point to center
		target_3d.global_position = grab_point + _grab_offset
		
		# Apply rotation to face the pointer (if method exists and allowed by layer mask)
		if _grab_should_rotate:
			if _grab_target.has_method("pointer_grab_set_rotation"):
				_grab_target.pointer_grab_set_rotation(self, grab_point)
			elif _grab_target.has_method("pointer_grab_set_distance"):
				# Just call for rotation side side effect - but DON'T let it reposition
				# Actually skip this since it repositions
				pass
		
		if scale_delta != 0.0:
			if _grab_target.has_method("pointer_grab_set_scale"):
				var current_uniform_scale: float = target_3d.scale.x
				var new_uniform_scale: float = clamp(current_uniform_scale + scale_delta, grab_min_scale, grab_max_scale)
				_grab_target.pointer_grab_set_scale(new_uniform_scale)
			else:
				# Direct scale update for objects without interface
				var new_scale: float = clamp(target_3d.scale.x + scale_delta, grab_min_scale, grab_max_scale)
				target_3d.scale = Vector3.ONE * new_scale


func is_grabbing() -> bool:
	"""Returns true if currently grabbing an object."""
	return _grab_target != null and is_instance_valid(_grab_target)


func get_grabbed_object() -> Node:
	"""Returns the currently grabbed object, or null."""
	if _grab_target and is_instance_valid(_grab_target):
		return _grab_target
	return null
