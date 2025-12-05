extends Node3D

# Keyboard Full Viewport 3D - 3D worldspace wrapper for full keyboard
# Supports single-hand grab (move) and two-hand grab (scale)

@export var pointer_group: StringName = &"pointer_interactable"
@export var ui_size: Vector2 = Vector2(800, 280)
@export var quad_size: Vector2 = Vector2(3.2, 1.12)  # Aspect ratio matches 800:280
@export var debug_coordinates: bool = false
@export var flip_v: bool = true

# Grab settings
@export_group("Grabbing")
@export var grabbable: bool = true
@export var min_scale: float = 0.3
@export var max_scale: float = 3.0
@export var grab_smooth_factor: float = 15.0  # Higher = snappier follow

@onready var viewport: SubViewport = get_node_or_null("SubViewport") as SubViewport
@onready var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
@onready var _static_body: StaticBody3D = get_node_or_null("MeshInstance3D/StaticBody3D") as StaticBody3D

var _saved_static_body_layer: int = 0
var _last_mouse_pos: Vector2 = Vector2(-1, -1)
var _is_hovering: bool = false
var _is_pressed: bool = false

# Grab state
var _primary_hand: RigidBody3D = null  # First hand that grabbed
var _secondary_hand: RigidBody3D = null  # Second hand for two-hand scaling
var _grab_offset: Transform3D = Transform3D.IDENTITY  # Offset from primary hand at grab time
var _initial_hand_distance: float = 0.0  # Distance between hands when two-hand grab started
var _initial_scale: Vector3 = Vector3.ONE  # Scale when two-hand grab started
var _is_grabbed: bool = false
var _is_two_hand_grab: bool = false


func _ready() -> void:
	if pointer_group != StringName(""):
		add_to_group(pointer_group)
	
	# Add to grabbable group for detection by physics hands
	add_to_group("grabbable")
	add_to_group("keyboard_grabbable")
	
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
	
	# Connect to KeyboardManager for focus feedback
	_connect_keyboard_manager()


func _connect_keyboard_manager() -> void:
	# Use call_deferred to ensure KeyboardManager is ready
	call_deferred("_deferred_connect_keyboard_manager")


func _deferred_connect_keyboard_manager() -> void:
	if KeyboardManager and KeyboardManager.instance:
		KeyboardManager.instance.focus_changed.connect(_on_focus_changed)
		KeyboardManager.instance.focus_cleared.connect(_on_focus_cleared)
		print("KeyboardFullViewport3D: Connected to KeyboardManager")


func _on_focus_changed(_control: Control, _viewport: SubViewport) -> void:
	# Show visual feedback that keyboard is active
	if mesh_instance:
		var mat = mesh_instance.get_active_material(0) as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)  # Full brightness when active


func _on_focus_cleared() -> void:
	# Dim the keyboard when no input is focused
	if mesh_instance:
		var mat = mesh_instance.get_active_material(0) as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.7, 0.7, 0.7, 0.85)  # Dimmed when inactive


func handle_pointer_event(event: Dictionary) -> void:
	if not viewport or not mesh_instance:
		return
	
	var event_type: String = String(event.get("type", ""))
	var hit_pos: Vector3 = event.get("global_position", Vector3.ZERO)
	
	var local_hit: Vector3 = mesh_instance.global_transform.affine_inverse() * hit_pos
	var uv: Vector2 = _world_to_uv(local_hit)
	
	if debug_coordinates:
		print("KeyboardViewport: Hit uv=", uv)
	
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
# GRABBABLE INTERFACE
# ============================================================================

func try_grab(hand: RigidBody3D) -> bool:
	"""Attempt to grab this keyboard with a hand. Returns true if successful."""
	if not grabbable:
		return false
	
	if not _is_grabbed:
		# First hand grab - start single-hand mode
		_primary_hand = hand
		_is_grabbed = true
		_is_two_hand_grab = false
		
		# Calculate offset from hand to keyboard in hand's local space
		_grab_offset = hand.global_transform.affine_inverse() * global_transform
		
		print("KeyboardFullViewport3D: Grabbed by ", hand.name)
		return true
	
	elif _is_grabbed and _primary_hand != hand and _secondary_hand == null:
		# Second hand grab - start two-hand scaling mode
		_secondary_hand = hand
		_is_two_hand_grab = true
		
		# Record initial distance and scale for proportional scaling
		_initial_hand_distance = _primary_hand.global_position.distance_to(_secondary_hand.global_position)
		_initial_scale = scale
		
		print("KeyboardFullViewport3D: Two-hand grab started, initial distance: ", _initial_hand_distance)
		return true
	
	return false


func release(hand: RigidBody3D = null) -> void:
	"""Release the keyboard from a specific hand, or all hands if null."""
	if hand == null:
		# Release from all hands
		_primary_hand = null
		_secondary_hand = null
		_is_grabbed = false
		_is_two_hand_grab = false
		print("KeyboardFullViewport3D: Released from all hands")
		return
	
	if hand == _secondary_hand:
		# Secondary hand released - exit two-hand mode but stay grabbed by primary
		_secondary_hand = null
		_is_two_hand_grab = false
		print("KeyboardFullViewport3D: Secondary hand released, back to single-hand mode")
	
	elif hand == _primary_hand:
		if _secondary_hand:
			# Primary released but secondary still holding - swap roles
			_primary_hand = _secondary_hand
			_secondary_hand = null
			_is_two_hand_grab = false
			# Recalculate offset for new primary hand
			_grab_offset = _primary_hand.global_transform.affine_inverse() * global_transform
			print("KeyboardFullViewport3D: Primary released, secondary becomes primary")
		else:
			# Only hand released - fully release
			_primary_hand = null
			_is_grabbed = false
			_is_two_hand_grab = false
			print("KeyboardFullViewport3D: Released completely")


func is_grabbed() -> bool:
	"""Returns true if currently grabbed by at least one hand."""
	return _is_grabbed


func get_grabbing_hand() -> RigidBody3D:
	"""Returns the primary grabbing hand, or null if not grabbed."""
	return _primary_hand


func _physics_process(delta: float) -> void:
	if not _is_grabbed or not is_instance_valid(_primary_hand):
		# If hand became invalid, release
		if _is_grabbed:
			print("KeyboardFullViewport3D: Hand became invalid, releasing")
			release()
		return
	
	if _is_two_hand_grab:
		_process_two_hand_grab(delta)
	else:
		_process_single_hand_grab(delta)


func _process_single_hand_grab(delta: float) -> void:
	"""Smoothly follow the primary hand."""
	# Target transform is hand's transform * our stored offset
	var target_transform: Transform3D = _primary_hand.global_transform * _grab_offset
	
	# Smoothly interpolate position and rotation
	var t: float = clamp(grab_smooth_factor * delta, 0.0, 1.0)
	global_position = global_position.lerp(target_transform.origin, t)
	
	var current_quat: Quaternion = global_transform.basis.get_rotation_quaternion()
	var target_quat: Quaternion = target_transform.basis.get_rotation_quaternion()
	global_transform.basis = Basis(current_quat.slerp(target_quat, t))


func _process_two_hand_grab(delta: float) -> void:
	"""Handle two-hand grab: position at midpoint and scale based on hand distance."""
	if not is_instance_valid(_secondary_hand):
		# Secondary hand became invalid, fall back to single hand
		_secondary_hand = null
		_is_two_hand_grab = false
		return
	
	var primary_pos: Vector3 = _primary_hand.global_position
	var secondary_pos: Vector3 = _secondary_hand.global_position
	
	# Position at midpoint between hands
	var midpoint: Vector3 = (primary_pos + secondary_pos) * 0.5
	
	# Calculate current hand distance
	var current_distance: float = primary_pos.distance_to(secondary_pos)
	
	# Avoid division by zero
	if _initial_hand_distance < 0.01:
		_initial_hand_distance = 0.01
	
	# Calculate scale factor based on ratio of current to initial distance
	var scale_ratio: float = current_distance / _initial_hand_distance
	var new_scale: Vector3 = _initial_scale * scale_ratio
	
	# Clamp scale within bounds
	new_scale = new_scale.clamp(Vector3.ONE * min_scale, Vector3.ONE * max_scale)
	
	# Smooth interpolation
	var t: float = clamp(grab_smooth_factor * delta, 0.0, 1.0)
	global_position = global_position.lerp(midpoint, t)
	scale = scale.lerp(new_scale, t)
	
	# Orient to face the average of both hands' forward directions
	# with the keyboard horizontal (Y up)
	var forward_dir: Vector3 = (secondary_pos - primary_pos).normalized()
	var up_dir: Vector3 = Vector3.UP
	# Make the keyboard face perpendicular to the line between hands
	var look_dir: Vector3 = forward_dir.cross(up_dir).normalized()
	if look_dir.length_squared() > 0.001:
		var target_basis: Basis = Basis.looking_at(look_dir, up_dir)
		var current_quat: Quaternion = global_transform.basis.get_rotation_quaternion()
		var target_quat: Quaternion = target_basis.get_rotation_quaternion()
		global_transform.basis = Basis(current_quat.slerp(target_quat, t * 0.5))  # Slower rotation


# ============================================================================
# POINTER GRAB INTERFACE (for hand_pointer grip grab mode)
# ============================================================================

func pointer_grab_set_distance(new_distance: float, pointer: Node3D) -> void:
	"""Set the distance of this keyboard from the pointer origin.
	Called by hand_pointer during grip grab mode.
	Also rotates the keyboard to face toward the pointer."""
	if not pointer or not is_instance_valid(pointer):
		return
	
	# Get pointer direction
	var pointer_forward: Vector3 = -pointer.global_transform.basis.z.normalized()
	var pointer_origin: Vector3 = pointer.global_transform.origin
	
	# Position keyboard at the specified distance along pointer ray
	var new_position: Vector3 = pointer_origin + pointer_forward * new_distance
	global_position = new_position
	
	# Rotate keyboard to face toward the pointer origin (user)
	# look_at makes -Z face the target, so we look at a point BEHIND us 
	# to make the front face toward the pointer
	var direction: Vector3 = (global_position - pointer_origin).normalized()
	
	# Only rotate if we have valid direction
	if direction.length_squared() > 0.001:
		var look_away_point: Vector3 = global_position + direction
		look_at(look_away_point, Vector3.UP)


func pointer_grab_set_scale(new_scale: float) -> void:
	"""Set the uniform scale of this keyboard.
	Called by hand_pointer during grip grab mode."""
	# Clamp to our configured min/max
	new_scale = clamp(new_scale, min_scale, max_scale)
	scale = Vector3.ONE * new_scale


func pointer_grab_get_distance(pointer: Node3D) -> float:
	"""Get current distance from the pointer origin."""
	if not pointer or not is_instance_valid(pointer):
		return 0.0
	return global_position.distance_to(pointer.global_transform.origin)


func pointer_grab_get_scale() -> float:
	"""Get current uniform scale."""
	return scale.x
