extends Node3D

signal pointer_event(event: Dictionary)

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
@export_range(0.1, 10.0, 0.1) var ray_length: float = 3.0

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
@export var collide_with_areas: bool = true
@export var collide_with_bodies: bool = true

@onready var _pointer_face: MeshInstance3D = get_node_or_null(pointer_face_path) as MeshInstance3D
@onready var _raycast: RayCast3D = get_node_or_null(raycast_node_path) as RayCast3D
@onready var _ray_visual: MeshInstance3D = get_node_or_null(ray_visual_node_path) as MeshInstance3D
@onready var _ray_hit: MeshInstance3D = get_node_or_null(ray_hit_node_path) as MeshInstance3D

@export var hit_scale_per_meter: float = 0.02
@export var hit_min_scale: float = 0.01
@export var hit_max_scale: float = 0.2

var _line_mesh: ImmediateMesh
var _hover_target: Node = null
var _hover_collider: Object = null
var _last_event: Dictionary = {}
var _controller_cache: XRController3D = null
var _prev_action_pressed: bool = false

func _ready() -> void:
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
		_ray_hit.visible = false

func _physics_process(_delta: float) -> void:
	if not _raycast:
		return

	if _hover_target and not is_instance_valid(_hover_target):
		_hover_target = null
		_hover_collider = null
		_last_event = {}

	var axis_local: Vector3 = pointer_axis_local.normalized()
	if axis_local.length_squared() <= 0.0:
		return

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

	var controller: XRController3D = _get_pointer_controller()
	var action_state: Dictionary = _gather_action_state(controller)

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
	else:
		_clear_hover_state()

	if _ray_hit:
		_ray_hit.visible = has_hit
		if has_hit:
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
			# Create a basis scaled by the desired scale factor so we don't overwrite
			# node scale by setting global_transform after changing scale.
			# Scale linearly from hit_min_scale at 0m to hit_max_scale at 1.5m, clamped outside that range.
			var scale_factor: float = lerp(hit_min_scale, hit_max_scale, clamp(distance / 1.5, 0.0, 1.0))
			var scaled_x: Vector3 = x * scale_factor
			var scaled_y: Vector3 = y * scale_factor
			var scaled_z: Vector3 = z * scale_factor
			hit_xform.basis = Basis(scaled_x, scaled_y, scaled_z)
			_ray_hit.global_transform = hit_xform

	if _line_mesh:
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
		_emit_event(_hover_target, "exit", _last_event)
	_hover_target = null
	_hover_collider = null
	_last_event = {}
