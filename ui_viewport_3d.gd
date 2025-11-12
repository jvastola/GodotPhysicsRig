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
		viewport.gui_embed_subwindows = false
		
		# Connect button signals for debug output
		_connect_button_signals()

func _connect_button_signals() -> void:
	var button1: Button = viewport.get_node_or_null("UIPanel/VBoxContainer/Button1") as Button
	var button2: Button = viewport.get_node_or_null("UIPanel/VBoxContainer/Button2") as Button
	var button3: Button = viewport.get_node_or_null("UIPanel/VBoxContainer/Button3") as Button
	
	if button1:
		button1.pressed.connect(func(): print("Button 1 pressed!"))
	if button2:
		button2.pressed.connect(func(): print("Button 2 pressed!"))
	if button3:
		button3.pressed.connect(func(): print("Button 3 pressed!"))

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
