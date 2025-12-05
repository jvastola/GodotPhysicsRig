extends Node3D

# UI Viewport 3D that handles pointer events and translates them to 2D UI interactions
# This script sits on the root Node3D and handles pointer interaction with the viewport

@export var pointer_group: StringName = &"pointer_interactable"
@export var ui_size: Vector2 = Vector2(512, 512)  # Match viewport size
@export var quad_size: Vector2 = Vector2(2, 2)     # Match QuadMesh size
@export var debug_coordinates: bool = false        # Print UV/viewport coordinates for debugging
@export var flip_v: bool = true                   # Flip V coordinate to match UI top-left origin

@onready var viewport: SubViewport = get_node_or_null("SubViewport") as SubViewport
@onready var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
@onready var _static_body: StaticBody3D = get_node_or_null("MeshInstance3D/StaticBody3D") as StaticBody3D

var _saved_static_body_layer: int = 0

var _last_mouse_pos: Vector2 = Vector2(-1, -1)
var _is_hovering: bool = false
var _is_pressed: bool = false

func _ready() -> void:
	print("UIViewport3D: _ready() called")
	print("UIViewport3D: viewport = ", viewport)
	print("UIViewport3D: mesh_instance = ", mesh_instance)
	
	if pointer_group != StringName(""):
		add_to_group(pointer_group)
	
	if viewport:
		print("UIViewport3D: Setting viewport size to ", ui_size)
		viewport.size = Vector2i(int(ui_size.x), int(ui_size.y))
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.transparent_bg = true
		# Embed subwindow popups (OptionButton, ContextMenu, etc) into the SubViewport so
		# popup controls (PopupMenu, OptionButton menu) render and receive input correctly
		# when the UI is rendered to a SubViewport/mesh in 3D space.
		viewport.gui_embed_subwindows = true
		
		print("UIViewport3D: Viewport configured. Children count: ", viewport.get_child_count())
		for i in viewport.get_child_count():
			var child = viewport.get_child(i)
			print("UIViewport3D: Child ", i, ": ", child.name, " (", child.get_class(), ")")
			if child.get_script():
				print("  - Has script: ", child.get_script().resource_path)
		
		# Connect button signals for debug output
		_connect_button_signals()
	else:
		print("UIViewport3D: ERROR - viewport is null!")

	# Cache static body collision layer so we can toggle interaction cleanly
	if _static_body:
		_saved_static_body_layer = _static_body.collision_layer
		print("UIViewport3D: StaticBody collision layer: ", _saved_static_body_layer)

	# Ensure the mesh_instance visibility and collision are consistent
	# (mesh visibility is visual only; collisions are controlled by the StaticBody)
	if mesh_instance and _static_body:
		mesh_instance.visible = true
		_static_body.collision_layer = _saved_static_body_layer
		print("UIViewport3D: MeshInstance visible, StaticBody enabled")
	
	print("UIViewport3D: _ready() complete")

func _connect_button_signals() -> void:
	var button1: Button = viewport.get_node_or_null("UIPanel/VBoxContainer/Button1") as Button
	var button2: Button = viewport.get_node_or_null("UIPanel/VBoxContainer/Button2") as Button
	var button3: Button = viewport.get_node_or_null("UIPanel/VBoxContainer/Button3") as Button
	
	if button1:
		button1.pressed.connect(self._on_button1_pressed)
	if button2:
		button2.pressed.connect(self._on_button2_pressed)
	if button3:
		button3.pressed.connect(self._on_button3_pressed)

func _on_button1_pressed() -> void:
	# Simple debug handler
	print("Button 1 pressed!")

func _on_button2_pressed() -> void:
	print("Button 2 pressed!")

func _on_button3_pressed() -> void:
	print("Button 3 pressed!")

func handle_pointer_event(event: Dictionary) -> void:
	if not viewport or not mesh_instance:
		return
	
	var event_type: String = String(event.get("type", ""))
	var hit_pos: Vector3 = event.get("global_position", Vector3.ZERO)
	
	# Convert 3D hit position to 2D viewport coordinates
	var local_hit: Vector3 = mesh_instance.global_transform.affine_inverse() * hit_pos
	var uv: Vector2 = _world_to_uv(local_hit)
	
	if debug_coordinates:
		print("Hit: global=", hit_pos, " local=", local_hit, " uv=", uv)
	
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		# Hit outside viewport bounds
		if _is_hovering:
			_send_mouse_exit()
		return
	
	var viewport_pos: Vector2 = Vector2(uv.x * ui_size.x, uv.y * ui_size.y)
	
	if debug_coordinates and event_type == "press":
		print("Viewport pos: ", viewport_pos)
	
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
		"exit":
			_send_mouse_exit()
			_is_hovering = false
			_is_pressed = false

func _world_to_uv(local_pos: Vector3) -> Vector2:
	# Convert mesh-local position to UV coordinates on the quad.
	# Use local X (left-right) and local Y (up-down) because after
	# transforming into the mesh's local space the quad lies on its
	# local XY plane. Map from [-half, half] to [0,1].
	var half_size: Vector2 = quad_size * 0.5
	if half_size.x == 0 or half_size.y == 0:
		return Vector2(-1, -1)

	var u: float = (local_pos.x / half_size.x) * 0.5 + 0.5
	var v: float = (local_pos.y / half_size.y) * 0.5 + 0.5

	# UI viewport coordinates have origin at top-left (y grows downward),
	# while mesh local Y grows upward. Flip V by default so (top) maps to 0.
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

func _send_mouse_button(pos: Vector2, pressed: bool, just_changed: bool) -> void:
	if not viewport or not just_changed:
		return
	
	var button_event := InputEventMouseButton.new()
	button_event.position = pos
	button_event.global_position = pos
	button_event.button_index = MOUSE_BUTTON_LEFT
	button_event.pressed = pressed
	
	viewport.push_input(button_event)

func _send_mouse_exit() -> void:
	if _last_mouse_pos.x >= 0 and viewport:
		# Send a mouse motion event off-screen to trigger hover exit
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
	# Toggle visual and collision interactivity of the 3D UI. When disabled,
	# the StaticBody's collision_layer is set to 0 so raycasts ignore it.
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
	"""Set the distance of this UI panel from the pointer origin.
	Called by hand_pointer during grip grab mode."""
	if not pointer or not is_instance_valid(pointer):
		return
	
	# Get pointer direction
	var pointer_forward: Vector3 = -pointer.global_transform.basis.z.normalized()
	var pointer_origin: Vector3 = pointer.global_transform.origin
	
	# Position panel at the specified distance along pointer ray
	global_position = pointer_origin + pointer_forward * new_distance


func pointer_grab_set_scale(new_scale: float) -> void:
	"""Set the uniform scale of this UI panel.
	Called by hand_pointer during grip grab mode."""
	# Apply uniform scale
	scale = Vector3.ONE * new_scale
	
	# Optionally update quad_size to maintain proper collision/interaction bounds
	# This is handled by the mesh/collision being children that inherit scale


func pointer_grab_get_distance(pointer: Node3D) -> float:
	"""Get current distance from the pointer origin."""
	if not pointer or not is_instance_valid(pointer):
		return 0.0
	return global_position.distance_to(pointer.global_transform.origin)


func pointer_grab_get_scale() -> float:
	"""Get current uniform scale."""
	return scale.x
