extends Node3D

# Node Inspector Viewport 3D - 3D worldspace panel for displaying node properties
# Listens for node selection from SceneHierarchyUI

@export var pointer_group: StringName = &"pointer_interactable"
@export var ui_size: Vector2 = Vector2(500, 600)
@export var quad_size: Vector2 = Vector2(2.0, 2.4)  # Aspect ratio matches 500:600
@export var debug_coordinates: bool = false
@export var flip_v: bool = true

@onready var viewport: SubViewport = get_node_or_null("SubViewport") as SubViewport
@onready var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
@onready var _static_body: StaticBody3D = get_node_or_null("MeshInstance3D/StaticBody3D") as StaticBody3D
@onready var inspector_ui = get_node_or_null("SubViewport/NodeInspectorUI")

var _saved_static_body_layer: int = 0
var _last_mouse_pos: Vector2 = Vector2(-1, -1)
var _is_hovering: bool = false
var _is_pressed: bool = false


func _ready() -> void:
	if pointer_group != StringName(""):
		add_to_group(pointer_group)
	
	if viewport:
		viewport.size = Vector2i(int(ui_size.x), int(ui_size.y))
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.transparent_bg = true
		viewport.gui_embed_subwindows = true
	
	if _static_body:
		_saved_static_body_layer = _static_body.collision_layer
	
	if mesh_instance and _static_body:
		mesh_instance.visible = true
		_static_body.collision_layer = _saved_static_body_layer
	
	# Connect to scene hierarchy panels to receive selection events
	call_deferred("_connect_to_hierarchy_panels")


func _connect_to_hierarchy_panels() -> void:
	"""Find and connect to any SceneHierarchyUI panels in the scene."""
	# Find all hierarchy viewports in the scene
	var hierarchy_panels = get_tree().get_nodes_in_group("scene_hierarchy")
	for panel in hierarchy_panels:
		if panel.has_signal("node_selected"):
			if not panel.node_selected.is_connected(_on_node_selected):
				panel.node_selected.connect(_on_node_selected)
				print("NodeInspectorViewport: Connected to hierarchy panel: ", panel.name)


func _on_node_selected(node_path: NodePath) -> void:
	"""Handle node selection from a scene hierarchy panel."""
	if inspector_ui and inspector_ui.has_method("inspect_node_by_path"):
		inspector_ui.inspect_node_by_path(node_path)


func inspect_node(node: Node) -> void:
	"""Directly inspect a node."""
	if inspector_ui and inspector_ui.has_method("inspect_node"):
		inspector_ui.inspect_node(node)


func handle_pointer_event(event: Dictionary) -> void:
	if not viewport or not mesh_instance:
		return
	
	var event_type: String = String(event.get("type", ""))
	var hit_pos: Vector3 = event.get("global_position", Vector3.ZERO)
	
	var local_hit: Vector3 = mesh_instance.global_transform.affine_inverse() * hit_pos
	var uv: Vector2 = _world_to_uv(local_hit)
	
	if debug_coordinates:
		print("NodeInspectorViewport: Hit: global=", hit_pos, " local=", local_hit, " uv=", uv)
	
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		if _is_hovering:
			_send_mouse_exit()
		return
	
	var viewport_pos: Vector2 = Vector2(uv.x * ui_size.x, uv.y * ui_size.y)
	
	match event_type:
		"enter", "hover":
			_send_mouse_motion(viewport_pos)
			_is_hovering = true
		"press":
			_send_mouse_motion(viewport_pos)
			_send_mouse_button(viewport_pos, true, event.get("action_just_pressed", false))
			_is_pressed = true
		"hold":
			_send_mouse_motion(viewport_pos)
			if event.get("action_pressed", false) and not _is_pressed:
				_send_mouse_button(viewport_pos, true, true)
				_is_pressed = true
		"release":
			_send_mouse_motion(viewport_pos)
			_send_mouse_button(viewport_pos, false, event.get("action_just_released", false))
			_is_pressed = false
		"secondary_press":
			_send_mouse_motion(viewport_pos)
			_send_mouse_button(
				viewport_pos,
				true,
				event.get("secondary_just_pressed", event.get("action_just_pressed", true)),
				MOUSE_BUTTON_RIGHT
			)
		"secondary_release":
			_send_mouse_motion(viewport_pos)
			_send_mouse_button(
				viewport_pos,
				false,
				event.get("secondary_just_released", event.get("action_just_released", true)),
				MOUSE_BUTTON_RIGHT
			)
		"scroll":
			_send_mouse_motion(viewport_pos)
			_send_scroll(viewport_pos, event.get("scroll_value", 0.0) * event.get("scroll_wheel_factor", 1.0))
		"exit":
			_send_mouse_exit()
			_is_hovering = false
			_is_pressed = false


func _world_to_uv(local_pos: Vector3) -> Vector2:
	var half_size: Vector2 = quad_size * 0.5
	if half_size.x == 0 or half_size.y == 0:
		return Vector2(-1, -1)
	
	var u: float = (local_pos.x / half_size.x) * 0.5 + 0.5
	var v: float = (local_pos.y / half_size.y) * 0.5 + 0.5
	
	if flip_v:
		v = 1.0 - v
	
	return Vector2(u, v)


func _send_mouse_motion(pos: Vector2) -> void:
	if not viewport:
		return
	
	var motion_event := InputEventMouseMotion.new()
	motion_event.position = pos
	motion_event.global_position = pos
	
	if _last_mouse_pos.x >= 0:
		motion_event.relative = pos - _last_mouse_pos
	else:
		motion_event.relative = Vector2.ZERO
	
	_last_mouse_pos = pos
	viewport.push_input(motion_event)


func _send_mouse_button(pos: Vector2, pressed: bool, just_changed: bool, button_index: int = MOUSE_BUTTON_LEFT) -> void:
	if not viewport or not just_changed:
		return
	
	var button_event := InputEventMouseButton.new()
	button_event.position = pos
	button_event.global_position = pos
	button_event.button_index = button_index as MouseButton
	button_event.pressed = pressed
	
	viewport.push_input(button_event)

func _send_scroll(pos: Vector2, amount: float) -> void:
	if not viewport:
		return
	if abs(amount) <= 0.001:
		return
	var scroll_event := InputEventMouseButton.new()
	scroll_event.position = pos
	scroll_event.global_position = pos
	scroll_event.button_index = (MOUSE_BUTTON_WHEEL_UP if amount > 0.0 else MOUSE_BUTTON_WHEEL_DOWN) as MouseButton
	scroll_event.pressed = true
	scroll_event.factor = abs(amount)
	viewport.push_input(scroll_event)


func _send_mouse_exit() -> void:
	if _last_mouse_pos.x >= 0 and viewport:
		var exit_pos := Vector2(-100, -100)
		var motion_event := InputEventMouseMotion.new()
		motion_event.position = exit_pos
		motion_event.global_position = exit_pos
		motion_event.relative = exit_pos - _last_mouse_pos
		viewport.push_input(motion_event)
	
	_last_mouse_pos = Vector2(-1, -1)
	_is_hovering = false
	_is_pressed = false


func set_interactive(enabled: bool) -> void:
	if mesh_instance:
		mesh_instance.visible = enabled
	if _static_body:
		if enabled:
			_static_body.collision_layer = _saved_static_body_layer
		else:
			_static_body.collision_layer = 0


# ============================================================================
# POINTER GRAB INTERFACE
# ============================================================================

func pointer_grab_set_distance(new_distance: float, pointer: Node3D) -> void:
	if not pointer or not is_instance_valid(pointer):
		return
	var pointer_forward: Vector3 = -pointer.global_transform.basis.z.normalized()
	var pointer_origin: Vector3 = pointer.global_transform.origin
	var new_position: Vector3 = pointer_origin + pointer_forward * new_distance
	global_position = new_position
	var direction: Vector3 = (global_position - pointer_origin).normalized()
	if direction.length_squared() > 0.001:
		var look_away_point: Vector3 = global_position + direction
		look_at(look_away_point, Vector3.UP)


func pointer_grab_set_scale(new_scale: float) -> void:
	scale = Vector3.ONE * new_scale


func pointer_grab_set_rotation(pointer: Node3D, grab_point: Vector3 = Vector3.INF) -> void:
	if not pointer or not is_instance_valid(pointer):
		return
	
	var pointer_origin: Vector3 = pointer.global_transform.origin
	var direction: Vector3 = Vector3.ZERO
	
	if grab_point.is_finite():
		direction = (grab_point - pointer_origin).normalized()
	else:
		direction = (global_position - pointer_origin).normalized()
	
	if direction.length_squared() > 0.001:
		var look_away_point: Vector3 = global_position + direction
		look_at(look_away_point, Vector3.UP)
