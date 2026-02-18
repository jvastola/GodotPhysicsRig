extends Node3D

# UI Viewport 3D that handles pointer events and translates them to 2D UI interactions
# This script sits on the root Node3D and handles pointer interaction with the viewport

@export var pointer_group: StringName = &"pointer_interactable"
@export var ui_size: Vector2 = Vector2(512, 512)  # Match viewport size
@export var quad_size: Vector2 = Vector2(2, 2)     # Match QuadMesh size
@export var debug_coordinates: bool = false        # Print UV/viewport coordinates for debugging
@export var flip_v: bool = true                   # Flip V coordinate to match UI top-left origin

@export_group("Border Highlight")
@export var enable_resize_handles: bool = true
@export var border_color: Color = Color(0.4, 0.6, 1.0, 0.3)
@export var corner_highlight_color: Color = Color(1.0, 1.0, 1.0, 0.8)
@export var border_width: float = 0.015          # Normalized (0-1)
@export var border_gap: float = 0.04             # Gap between panel edge and border (meters)
@export var corner_arc_length: float = 0.05       # UV length of corner anchor
@export var corner_radius: float = 0.05           # UV radius
@export var resize_corner_size: float = 0.025       # UV region size for detection

@export var min_panel_size: Vector2 = Vector2(0.4, 0.3)  # Minimum quad dimensions
@export var max_panel_size: Vector2 = Vector2(5.0, 4.0)  # Maximum quad dimensions
@export var enable_panel_grab: bool = true  # If false, this panel ignores pointer grab requests (for wrapper use)
var grab_delegate: Node3D = null # If set, grab calls are forwarded here

@onready var viewport: SubViewport = get_node_or_null("SubViewport") as SubViewport
@onready var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
@onready var _static_body: StaticBody3D = get_node_or_null("MeshInstance3D/StaticBody3D") as StaticBody3D

var _saved_static_body_layer: int = 0

var _last_mouse_pos: Vector2 = Vector2(-1, -1)
var _is_hovering: bool = false
var _is_pressed: bool = false

# Border Highlight state
var _border_mesh: MeshInstance3D = null
var _border_material: ShaderMaterial = null
var _resize_active_corner: int = -1 # 0=TL, 1=TR, 2=BR, 3=BL, -1=None
var _resize_initial_quad_size: Vector2 = Vector2.ZERO
var _resize_initial_grab_pos: Vector3 = Vector3.ZERO
var _resize_anchor_corner: Vector3 = Vector3.ZERO  # Opposite corner in world space
var _resize_grab_offset: Vector3 = Vector3.ZERO    # Offset from grab point to actual corner
var _resize_pointer: Node3D = null
var _resize_controller: XRController3D = null
var _resize_action: String = ""
var _resize_initial_transform: Transform3D = Transform3D()

# Visibility state
var _hovering_panel: bool = false
var _hovering_corner: int = -1

signal panel_resized(new_quad_size: Vector2)

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
	
	# Setup border highlight
	if enable_resize_handles:
		_setup_border_highlight()
		# Initialize collision shape size with border expansion
		_set_collision_shape_size(quad_size)
	
	print("UIViewport3D: _ready() complete")

func _connect_button_signals() -> void:
	var button1: Button = viewport.get_node_or_null("WatchMenuUI/VBoxContainer/Button1") as Button
	var button2: Button = viewport.get_node_or_null("WatchMenuUI/VBoxContainer/Button2") as Button
	var button3: Button = viewport.get_node_or_null("WatchMenuUI/VBoxContainer/Button3") as Button
	
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
	
	# Check bounds
	var bounds_min = Vector2(0, 0)
	var bounds_max = Vector2(1, 1)
	
	if enable_resize_handles:
		# Map border size to UV space
		# Border is constant world size, so UV size depends on quad_size
		# Expand interaction area significantly (0.2m padding) to allow loose grabbing
		var border_uv_w = (border_gap + 0.2) / quad_size.x
		var border_uv_h = (border_gap + 0.2) / quad_size.y
		bounds_min = Vector2(-border_uv_w, -border_uv_h)
		bounds_max = Vector2(1.0 + border_uv_w, 1.0 + border_uv_h)
	
	if uv.x < bounds_min.x or uv.x > bounds_max.x or uv.y < bounds_min.y or uv.y > bounds_max.y:
		# Hit outside valid interaction bounds
		if _is_hovering:
			_send_mouse_exit()
		return
	
	var viewport_pos: Vector2 = Vector2(uv.x * ui_size.x, uv.y * ui_size.y)
	
	if debug_coordinates and event_type == "press":
		print("Viewport pos: ", viewport_pos)
	
	var corner: int = -1
	if enable_resize_handles:
		corner = _get_resize_corner(uv)
		if corner != _hovering_corner:
			_hovering_corner = corner
			_update_border_corner_highlight(corner)

	match event_type:
		"enter", "hover":
			_send_mouse_motion(viewport_pos)
			_is_hovering = true
			if not _hovering_panel:
				_hovering_panel = true
				_update_border_hover(1.0)
		"press":
			_send_mouse_motion(viewport_pos)
			_is_pressed = true
			
			if enable_resize_handles and corner != -1 and event.get("action_just_pressed", false):
				start_resize(corner, hit_pos, event.get("pointer"))
			else:
				_send_mouse_button(viewport_pos, true, event.get("action_just_pressed", false))
		"hold":
			if is_resizing():
				update_resize(hit_pos)
			else:
				_send_mouse_motion(viewport_pos)
				if event.get("action_pressed", false) and not _is_pressed:
					_send_mouse_button(viewport_pos, true, true)
					_is_pressed = true
		"release":
			if is_resizing():
				end_resize()
			else:
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
			if _hovering_panel:
				_hovering_panel = false
				_update_border_hover(0.0)
				_hovering_corner = -1
				_update_border_corner_highlight(-1)
			if is_resizing():
				end_resize()

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
	scroll_event.button_index = MOUSE_BUTTON_WHEEL_UP if amount > 0.0 else MOUSE_BUTTON_WHEEL_DOWN
	scroll_event.pressed = true
	scroll_event.factor = abs(amount)
	viewport.push_input(scroll_event)

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
	Called by hand_pointer during grip grab mode.
	Also rotates the panel to face toward the pointer."""
	if not enable_panel_grab:
		if grab_delegate and grab_delegate.has_method("pointer_grab_set_distance"):
			grab_delegate.pointer_grab_set_distance(new_distance, pointer)
		return

	if not pointer or not is_instance_valid(pointer):
		return
	
	# Get pointer direction
	var pointer_forward: Vector3 = -pointer.global_transform.basis.z.normalized()
	var pointer_origin: Vector3 = pointer.global_transform.origin
	
	# Position panel at the specified distance along pointer ray
	var new_position: Vector3 = pointer_origin + pointer_forward * new_distance
	global_position = new_position
	
	# Rotate panel to face toward the pointer origin (user)
	# look_at makes -Z face the target, so we look at a point BEHIND us 
	# (opposite direction from pointer) to make the front face toward the pointer
	var direction: Vector3 = (global_position - pointer_origin).normalized()
	
	# Only rotate if we have valid direction
	if direction.length_squared() > 0.001:
		# Look at a point behind us to face our +Z toward user
		var look_away_point: Vector3 = global_position + direction
		look_at(look_away_point, Vector3.UP)


func pointer_grab_set_scale(new_scale: float) -> void:
	"""Set the uniform scale of this UI panel.
	Called by hand_pointer during grip grab mode."""
	# Apply uniform scale
	scale = Vector3.ONE * new_scale
	
	# Optionally update quad_size to maintain proper collision/interaction bounds
	# This is handled by the mesh/collision being children that inherit scale


func pointer_grab_set_rotation(pointer: Node3D, grab_point: Vector3 = Vector3.INF) -> void:
	"""Rotate this panel to face the pointer origin.
	Called by hand_pointer during grip grab mode - position is handled separately."""
	if not enable_panel_grab:
		if grab_delegate and grab_delegate.has_method("pointer_grab_set_rotation"):
			grab_delegate.pointer_grab_set_rotation(pointer, grab_point)
		return

	if not pointer or not is_instance_valid(pointer):
		return
	
	var pointer_origin: Vector3 = pointer.global_transform.origin
	var direction: Vector3 = Vector3.ZERO
	
	# If we have a specific grab point (e.g. corner of panel), calculate direction
	# such that the surface normal at that point points to user
	# This means the vector from pointer to grab_point is our reference
	if grab_point.is_finite():
		direction = (grab_point - pointer_origin).normalized()
	else:
		# Fallback to center-based rotation
		direction = (global_position - pointer_origin).normalized()
	
	# Only rotate if we have valid direction
	if direction.length_squared() > 0.001:
		# Look at a point behind us to face our +Z toward user
		var look_away_point: Vector3 = global_position + direction
		look_at(look_away_point, Vector3.UP)


func pointer_grab_get_distance(pointer: Node3D) -> float:
	"""Get current distance from the pointer origin."""
	if not enable_panel_grab:
		if grab_delegate and grab_delegate.has_method("pointer_grab_get_distance"):
			return grab_delegate.pointer_grab_get_distance(pointer)
		return 0.0

	if not pointer or not is_instance_valid(pointer):
		return 0.0
	return global_position.distance_to(pointer.global_transform.origin)


func pointer_grab_get_scale() -> float:
	"""Get current uniform scale."""
	return scale.x


func get_grab_target() -> Node3D:
	"""Return the actual target that should be grabbed/moved.
	Used by hand_pointer to redirect grabs (e.g. to a parent wrapper)."""
	if not enable_panel_grab:
		return grab_delegate # Returns null if no delegate set!
	return self


# ============================================================================
# BORDER HIGHLIGHT & RESIZE (Horizon OS Style)
# ============================================================================

func _setup_border_highlight() -> void:
	"""Create the border highlight overlay mesh."""
	
	var border_mesh := MeshInstance3D.new()
	border_mesh.name = "BorderHighlight"
	border_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	var quad := QuadMesh.new()
	# Make border mesh larger than content to draw border outside
	quad.size = quad_size + Vector2(border_gap, border_gap) * 2.0
	border_mesh.mesh = quad
	
	# Load shader
	var shader = load("res://src/ui/shaders/panel_border_highlight.gdshader")
	if not shader:
		push_error("UIViewport3D: Could not load panel_border_highlight.gdshader")
		return
		
	var mat := ShaderMaterial.new()
	mat.shader = shader
	# Set initial uniforms
	mat.set_shader_parameter("border_color", border_color)
	mat.set_shader_parameter("corner_highlight_color", corner_highlight_color)
	mat.set_shader_parameter("border_width", border_width)
	mat.set_shader_parameter("corner_radius", corner_radius)
	mat.set_shader_parameter("corner_arc_length", corner_arc_length)
	mat.set_shader_parameter("aspect_ratio", quad.size.x / quad.size.y)
	mat.set_shader_parameter("active_corner", -1)
	mat.set_shader_parameter("hover_amount", 0.0)
	
	border_mesh.material_override = mat
	_border_material = mat
	_border_mesh = border_mesh
	
	add_child(border_mesh)
	# Position slightly in front of the content to avoid z-fighting
	border_mesh.position.z = 0.002

func _update_border_highlight_size() -> void:
	"""Update the border mesh size and shader aspect ratio."""
	if _border_mesh and _border_mesh.mesh is QuadMesh:
		var b_size = quad_size + Vector2(border_gap, border_gap) * 2.0
		_border_mesh.mesh.size = b_size
		
		if _border_material:
			var aspect = b_size.x / b_size.y if b_size.y > 0 else 1.0
			_border_material.set_shader_parameter("aspect_ratio", aspect)

func _update_border_corner_highlight(corner_index: int) -> void:
	# Don't update highlight if we are resizing (locks the active corner)
	if is_resizing() and corner_index == -1:
		return
		
	if _border_material:
		_border_material.set_shader_parameter("active_corner", corner_index)

func _update_border_hover(amount: float) -> void:
	if _border_material:
		# Tween this if we want smooth fade, but direct set is OK for now
		_border_material.set_shader_parameter("hover_amount", amount)


func _get_resize_corner(uv: Vector2) -> int:
	"""Get the corner index from UV coordinates.
	Returns 0=TL, 1=TR, 2=BR, 3=BL, -1=None"""
	
	# UV (0,0) is Top-Left in Godot QuadMesh
	
	# Check if within corner region
	var size = resize_corner_size
	
	# Top-Left (0,0) - Check extended region
	if uv.x < size and uv.y < size:
		return 0
	# Top-Right (1,0)
	if uv.x > (1.0 - size) and uv.y < size:
		return 1
	# Bottom-Right (1,1)
	if uv.x > (1.0 - size) and uv.y > (1.0 - size):
		return 2
	# Bottom-Left (0,1)
	if uv.x < size and uv.y > (1.0 - size):
		return 3
		
	return -1

func _get_opposite_corner_index(corner_index: int) -> int:
	# 0(TL) <-> 2(BR), 1(TR) <-> 3(BL)
	return (corner_index + 2) % 4

func _get_corner_world_position(corner_index: int) -> Vector3:
	var half_w: float = quad_size.x * 0.5
	var half_h: float = quad_size.y * 0.5
	
	# Local corners relative to center
	# Y is UP in 3D, but UV Y is DOWN.
	# Godot QuadMesh: +Y is Top? No, usually +Y is Top in 3D.
	# Let's double check standard QuadMesh UV mapping.
	# (0,0) UV -> (-0.5, 0.5) Local Pos (Top-Left)
	# (1,1) UV -> (0.5, -0.5) Local Pos (Bottom-Right)
	# So Top is +Y, Bottom is -Y. Left is -X, Right is +X.
	
	var local_corners := [
		Vector3(-half_w, half_h, 0.0),   # 0: Top-Left
		Vector3(half_w, half_h, 0.0),    # 1: Top-Right
		Vector3(half_w, -half_h, 0.0),   # 2: Bottom-Right
		Vector3(-half_w, -half_h, 0.0),  # 3: Bottom-Left
	]
	
	# Check flip_v. If UI is flip_v, then UV (0,0) maps to...
	# ui_viewport_3d flip_v=true by default.
	# _world_to_uv handles the flip.
	# Here we need physical world positions of the logical corners 0,1,2,3.
	
	return global_transform * local_corners[corner_index]


func start_resize(corner_index: int, grab_world_pos: Vector3, pointer: Node3D = null) -> void:
	if corner_index < 0 or corner_index > 3:
		return
	
	_resize_active_corner = corner_index
	_resize_initial_quad_size = quad_size
	_resize_initial_grab_pos = grab_world_pos
	
	var opposite_index: int = _get_opposite_corner_index(corner_index)
	_resize_anchor_corner = _get_corner_world_position(opposite_index)

	# Calculate offset from grab pos to the actual corner position
	var actual_corner_pos = _get_corner_world_position(corner_index)
	var local_grab = global_transform.affine_inverse() * grab_world_pos
	var local_corner = global_transform.affine_inverse() * actual_corner_pos
	_resize_grab_offset = local_corner - local_grab

	print("UIViewport3D: Started resize from corner ", corner_index)
	
	_resize_initial_transform = global_transform
	
	# robust resize: capture pointer
	if pointer:
		_resize_pointer = pointer
		_resize_action = pointer.get("interact_action") if "interact_action" in pointer else "trigger_click"
		_resize_controller = _find_controller_for_pointer(pointer)
		print("UIViewport3D: Robust resize setup - Pointer:", _resize_pointer, " Controller:", _resize_controller, " Action:", _resize_action)
		set_process(true) # Enable processing to track resize
	else:
		print("UIViewport3D: Robust resize setup FAILED - No pointer passed!")
	
	if _border_material:
		_border_material.set_shader_parameter("resize_progress", 1.0)
		_border_material.set_shader_parameter("active_corner", corner_index)

func update_resize(current_pointer_pos: Vector3) -> void:
	# Note: current_pointer_pos argument is legacy generic, we use _resize_pointer transform directly
	if _resize_active_corner == -1 or not _resize_pointer:
		return
		
	# Ray-Plane Intersection (Horizon OS style remote resize)
	# Plane is defined by initial transform (so it stays stable during resize)
	# Normal is +Z of the initial transform (assuming QuadMesh faces +Z)
	var plane_normal = _resize_initial_transform.basis.z.normalized()
	var plane_origin = _resize_initial_transform.origin
	var plane = Plane(plane_normal, plane_origin.dot(plane_normal))
	
	# Pointer Ray
	var ray_origin = _resize_pointer.global_position
	var ray_dir = -_resize_pointer.global_transform.basis.z.normalized() # Pointer faces -Z
	
	var intersection = plane.intersects_ray(ray_origin, ray_dir)
	
	if intersection == null:
		# Ray does not hit plane (pointing away), skip update to avoid jump
		return
		
	var current_grab_pos = intersection
	
	# Calculate new corner position in panel's LOCAL space (relative to INITIAL transform)
	var local_grab: Vector3 = _resize_initial_transform.affine_inverse() * current_grab_pos
	# Apply initial offset to get where the corner should be
	var local_new_corner: Vector3 = local_grab + _resize_grab_offset
	var local_anchor: Vector3 = _resize_initial_transform.affine_inverse() * _resize_anchor_corner
	
	# Calculate new size based on distance from anchor to new corner
	var delta: Vector3 = local_new_corner - local_anchor
	var new_width: float = abs(delta.x)
	var new_height: float = abs(delta.y)
	
	# Clamp to min/max
	new_width = clamp(new_width, min_panel_size.x, max_panel_size.x)
	new_height = clamp(new_height, min_panel_size.y, max_panel_size.y)
	
	if Engine.get_physics_frames() % 60 == 0:
		print("UIViewport3D: Resize - Delta:", delta, " NewSize:", Vector2(new_width, new_height))
		
	set_panel_size(Vector2(new_width, new_height), _resize_anchor_corner)

func end_resize() -> void:
	if _resize_active_corner != -1:
		print("UIViewport3D: Ended resize, new size: ", quad_size)
	
	_resize_active_corner = -1
	_resize_initial_quad_size = Vector2.ZERO
	_resize_initial_grab_pos = Vector3.ZERO
	_resize_anchor_corner = Vector3.ZERO
	_resize_pointer = null
	_resize_controller = null
	set_process(false)
	
	# Reset collision shape (just to be safe, though not modifying it anymore)
	_set_collision_shape_size(quad_size)
	
	if _border_material:
		_border_material.set_shader_parameter("resize_progress", 0.0)

func is_resizing() -> bool:
	return _resize_active_corner != -1

func set_panel_size(new_quad_size: Vector2, anchor_world_pos: Vector3 = Vector3.INF) -> void:
	"""Set the panel size, optionally keeping a world position fixed as anchor."""
	var old_quad_size: Vector2 = quad_size
	quad_size = new_quad_size
	
	# Calculate new ui_size maintaining aspect ratio with original resolution
	# Keep pixels per unit roughly consistent
	var pixels_per_unit: float = ui_size.x / old_quad_size.x if old_quad_size.x > 0 else 256.0
	ui_size = new_quad_size * pixels_per_unit
	# Clamp to reasonable viewport sizes
	ui_size.x = clamp(ui_size.x, 128, 2048)
	ui_size.y = clamp(ui_size.y, 128, 2048)
	
	# Update viewport
	if viewport:
		viewport.size = Vector2i(int(ui_size.x), int(ui_size.y))
	
	# Update mesh
	if mesh_instance and mesh_instance.mesh is QuadMesh:
		var quad_mesh: QuadMesh = mesh_instance.mesh as QuadMesh
		quad_mesh.size = new_quad_size
	
	# Update collision shape
	if _static_body:
		var collision_shape = _static_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if collision_shape and collision_shape.shape is BoxShape3D:
			var box: BoxShape3D = collision_shape.shape as BoxShape3D
			box.size = Vector3(new_quad_size.x, new_quad_size.y, 0.01)
	
	# If we have an anchor point, adjust position so anchor stays fixed
	if anchor_world_pos.is_finite():
		# Calculate where the anchor should be in the NEW local space
		var old_local_anchor: Vector3 = global_transform.affine_inverse() * anchor_world_pos
		
		# Determine corner signs relative to old center
		# Note: offset logic relies on correct sign
		var _half_w_old: float = old_quad_size.x * 0.5
		var _half_h_old: float = old_quad_size.y * 0.5
		var half_w_new: float = new_quad_size.x * 0.5
		var half_h_new: float = new_quad_size.y * 0.5
		
		var sign_x: float = sign(old_local_anchor.x) if abs(old_local_anchor.x) > 0.01 else -1.0
		var sign_y: float = sign(old_local_anchor.y) if abs(old_local_anchor.y) > 0.01 else 1.0
		
		# New local anchor position
		var new_local_anchor: Vector3 = Vector3(sign_x * half_w_new, sign_y * half_h_new, 0.0)
		
		# Offset needed to keep anchor in same world position
		var local_offset: Vector3 = old_local_anchor - new_local_anchor
		global_position += global_transform.basis * local_offset
	
	# Update border highlight size
	_update_border_highlight_size()
	
	# Emit signal
	panel_resized.emit(new_quad_size)

func _set_collision_shape_size(size: Vector2) -> void:
	if _static_body:
		var collision_shape = _static_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if collision_shape and collision_shape.shape is BoxShape3D:
			# Include border gap for interaction area
			var total_size = size
			if enable_resize_handles:
				total_size += Vector2(border_gap, border_gap) * 2.0
				# Add a bit extra padding for easier grabbing
				total_size += Vector2(0.02, 0.02)
				
			collision_shape.shape.size = Vector3(total_size.x, total_size.y, 0.01)

func _process(delta: float) -> void:
	if is_resizing() and _resize_pointer:
		# Check if button released
		var pressed = _is_action_pressed(_resize_controller, _resize_action)
		# print("UIViewport3D: Resize update - Pressed:", pressed) # Uncomment if needed widely
		if not pressed:
			print("UIViewport3D: Robust resize released")
			end_resize()
			return
			
		# Update resize based on pointer position
		update_resize(_resize_pointer.global_position)

func _find_controller_for_pointer(ptr: Node) -> XRController3D:
	var parent = ptr.get_parent()
	while parent:
		if parent is XRController3D:
			return parent
		parent = parent.get_parent()
	return null

func _is_action_pressed(controller: XRController3D, action_name: String) -> bool:
	if action_name == "": return false
	# Check global Input action first (e.g. valid actions mapped in Project Settings)
	if InputMap.has_action(action_name) and Input.is_action_pressed(action_name):
		return true
	# Check controller specific input
	if controller:
		# Direct check
		if controller.is_button_pressed(action_name):
			return true
			
		# Float check
		if controller.get_float(action_name) > 0.1:
			return true
			
		# Fallback for "trigger_click" vs "trigger" naming differences
		if action_name == "trigger_click":
			if controller.get_float("trigger") > 0.1:
				return true
			if controller.is_button_pressed("trigger"):
				return true
				
	return false
