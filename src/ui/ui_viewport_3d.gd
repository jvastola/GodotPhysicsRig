extends Node3D

# UI Viewport 3D that handles pointer events and translates them to 2D UI interactions
# This script sits on the root Node3D and handles pointer interaction with the viewport

@export var pointer_group: StringName = &"pointer_interactable"
@export var ui_size: Vector2 = Vector2(512, 512)  # Match viewport size
@export var quad_size: Vector2 = Vector2(2, 2)     # Match QuadMesh size
@export var debug_coordinates: bool = false        # Print UV/viewport coordinates for debugging
@export var flip_v: bool = true                   # Flip V coordinate to match UI top-left origin

@export_group("Resize Handles")
@export var enable_resize_handles: bool = true
@export var resize_handle_size: float = 0.06       # Handle sphere radius
@export var resize_handle_offset: float = 0.08     # Distance outside panel corners
@export var min_panel_size: Vector2 = Vector2(0.4, 0.3)  # Minimum quad dimensions
@export var max_panel_size: Vector2 = Vector2(5.0, 4.0)  # Maximum quad dimensions
@export var resize_handle_color: Color = Color(0.9, 0.95, 1.0, 0.7)
@export var resize_handle_hover_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export_flags_3d_physics var resize_handle_collision_layer: int = 1 << 5
@export var enable_panel_grab: bool = true  # If false, this panel ignores pointer grab requests (for wrapper use)
var grab_delegate: Node3D = null # If set, grab calls are forwarded here

@onready var viewport: SubViewport = get_node_or_null("SubViewport") as SubViewport
@onready var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
@onready var _static_body: StaticBody3D = get_node_or_null("MeshInstance3D/StaticBody3D") as StaticBody3D

var _saved_static_body_layer: int = 0

var _last_mouse_pos: Vector2 = Vector2(-1, -1)
var _is_hovering: bool = false
var _is_pressed: bool = false

# Resize handle state
var _resize_handles: Array[Area3D] = []
var _resize_handle_materials: Array[StandardMaterial3D] = []
var _resize_handle_meshes: Array[MeshInstance3D] = []  # To toggle visibility
var _resize_active_handle: Area3D = null
var _resize_initial_quad_size: Vector2 = Vector2.ZERO
var _resize_initial_grab_pos: Vector3 = Vector3.ZERO
var _resize_anchor_corner: Vector3 = Vector3.ZERO  # Opposite corner in world space

# Visibility state
var _hovering_panel: bool = false
var _hovered_handle_index: int = -1

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
	
	# Setup resize handles
	if enable_resize_handles:
		_setup_resize_handles()
	
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
			if not _hovering_panel:
				_hovering_panel = true
				_update_handle_visibility()
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
			if _hovering_panel:
				_hovering_panel = false
				_update_handle_visibility()

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
# RESIZE HANDLES (VisionOS/HorizonOS Style)
# ============================================================================

func _setup_resize_handles() -> void:
	"""Create corner resize handles outside the panel bounds."""
	# Corner indices: 0=TopLeft, 1=TopRight, 2=BottomRight, 3=BottomLeft
	var corner_names := ["ResizeHandleTL", "ResizeHandleTR", "ResizeHandleBR", "ResizeHandleBL"]
	
	for i in range(4):
		var handle := Area3D.new()
		handle.name = corner_names[i]
		handle.collision_layer = resize_handle_collision_layer
		handle.collision_mask = 0
		handle.monitorable = false
		
		# Add to pointer interactable group
		if pointer_group != StringName(""):
			handle.add_to_group(pointer_group)
		
		# Store metadata for identification
		handle.set_meta("is_resize_handle", true)
		handle.set_meta("corner_index", i)
		handle.set_meta("parent_viewport", self)
		
		# Create visual sphere
		var handle_mesh := MeshInstance3D.new()
		handle_mesh.name = "Visual"
		var sphere := SphereMesh.new()
		sphere.radius = resize_handle_size
		sphere.height = resize_handle_size * 2.0
		sphere.radial_segments = 12
		sphere.rings = 6
		handle_mesh.mesh = sphere
		
		# Create material
		var mat := StandardMaterial3D.new()
		mat.albedo_color = resize_handle_color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.render_priority = 5
		handle_mesh.material_override = mat
		handle.add_child(handle_mesh)
		_resize_handle_materials.append(mat)
		_resize_handle_meshes.append(handle_mesh)
		
		# Create collision shape
		var collision := CollisionShape3D.new()
		collision.name = "Collision"
		var sphere_shape := SphereShape3D.new()
		sphere_shape.radius = resize_handle_size * 1.5  # Slightly larger for easier grabbing
		collision.shape = sphere_shape
		handle.add_child(collision)
		
		add_child(handle)
		_resize_handles.append(handle)
	
	# Position handles at corners
	_update_resize_handle_positions()
	
	# Initial visibility update
	_update_handle_visibility()


func _update_handle_visibility() -> void:
	"""Update visibility of resize handles based on hover/interaction state."""
	# Only show if hovering the specific handle OR if resizing using that handle
	# We ignore _hovering_panel for visibility now (handles hidden by default unless directly interacted with)
	
	var active_handle_index: int = -1
	if is_resizing():
		active_handle_index = get_resize_handle_corner_index(_resize_active_handle)
	
	for i in range(_resize_handle_meshes.size()):
		var mesh = _resize_handle_meshes[i]
		if mesh:
			# Show if this specific handle is hovered OR if it is the active handle being dragged
			var should_show: bool = (i == _hovered_handle_index) or (i == active_handle_index)
			mesh.visible = should_show


func _update_resize_handle_positions() -> void:
	"""Position resize handles at the corners of the panel."""
	if _resize_handles.size() != 4:
		return
	
	var half_w: float = quad_size.x * 0.5
	var half_h: float = quad_size.y * 0.5
	
	# Corner positions in local space (panel lies on XY plane, facing +Z)
	# Add offset to push handles outside the panel
	var offset: float = resize_handle_offset
	var corners := [
		Vector3(-half_w - offset, half_h + offset, 0.0),   # Top-Left
		Vector3(half_w + offset, half_h + offset, 0.0),    # Top-Right
		Vector3(half_w + offset, -half_h - offset, 0.0),   # Bottom-Right
		Vector3(-half_w - offset, -half_h - offset, 0.0),  # Bottom-Left
	]
	
	for i in range(4):
		_resize_handles[i].position = corners[i]


func _get_opposite_corner_index(corner_index: int) -> int:
	"""Get the index of the diagonally opposite corner."""
	# 0(TL) <-> 2(BR), 1(TR) <-> 3(BL)
	return (corner_index + 2) % 4


func _get_corner_world_position(corner_index: int) -> Vector3:
	"""Get the world position of a panel corner (not the handle, the actual corner)."""
	var half_w: float = quad_size.x * 0.5
	var half_h: float = quad_size.y * 0.5
	
	var local_corners := [
		Vector3(-half_w, half_h, 0.0),   # Top-Left
		Vector3(half_w, half_h, 0.0),    # Top-Right
		Vector3(half_w, -half_h, 0.0),   # Bottom-Right
		Vector3(-half_w, -half_h, 0.0),  # Bottom-Left
	]
	
	return global_transform * local_corners[corner_index]


func start_resize(corner_index: int, grab_world_pos: Vector3) -> void:
	"""Start a resize operation from the specified corner."""
	if corner_index < 0 or corner_index >= 4:
		return
	
	_resize_active_handle = _resize_handles[corner_index] if corner_index < _resize_handles.size() else null
	_resize_initial_quad_size = quad_size
	_resize_initial_grab_pos = grab_world_pos
	
	# Get the opposite corner as anchor point
	var opposite_index: int = _get_opposite_corner_index(corner_index)
	_resize_anchor_corner = _get_corner_world_position(opposite_index)
	
	print("UIViewport3D: Started resize from corner ", corner_index, " anchor at corner ", opposite_index)
	_update_handle_visibility()


func update_resize(current_grab_pos: Vector3) -> void:
	"""Update panel size based on current grab position."""
	if not _resize_active_handle:
		return
	
	# Calculate new corner position in panel's local space
	var local_new_corner: Vector3 = global_transform.affine_inverse() * current_grab_pos
	var local_anchor: Vector3 = global_transform.affine_inverse() * _resize_anchor_corner
	
	# Calculate new size based on distance from anchor to new corner
	# The anchor stays fixed, new corner determines size
	var delta: Vector3 = local_new_corner - local_anchor
	var new_width: float = abs(delta.x)
	var new_height: float = abs(delta.y)
	
	# Clamp to min/max
	new_width = clamp(new_width, min_panel_size.x, max_panel_size.x)
	new_height = clamp(new_height, min_panel_size.y, max_panel_size.y)
	
	# Apply new size
	set_panel_size(Vector2(new_width, new_height), _resize_anchor_corner)


func end_resize() -> void:
	"""End the current resize operation."""
	if _resize_active_handle:
		print("UIViewport3D: Ended resize, new size: ", quad_size)
	_resize_active_handle = null
	_resize_initial_quad_size = Vector2.ZERO
	_resize_initial_grab_pos = Vector3.ZERO
	_resize_anchor_corner = Vector3.ZERO
	_update_handle_visibility()


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
	var collision_shape: CollisionShape3D = null
	if _static_body:
		collision_shape = _static_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape and collision_shape.shape is BoxShape3D:
		var box: BoxShape3D = collision_shape.shape as BoxShape3D
		box.size = Vector3(new_quad_size.x, new_quad_size.y, 0.01)
	
	# If we have an anchor point, adjust position so anchor stays fixed
	if anchor_world_pos.is_finite():
		# Calculate where the anchor should be in the NEW local space
		var old_local_anchor: Vector3 = global_transform.affine_inverse() * anchor_world_pos
		# The anchor was at a corner, figure out which quadrant
		var _half_w_old: float = old_quad_size.x * 0.5
		var _half_h_old: float = old_quad_size.y * 0.5
		var half_w_new: float = new_quad_size.x * 0.5
		var half_h_new: float = new_quad_size.y * 0.5
		
		# Determine corner signs
		var sign_x: float = sign(old_local_anchor.x) if abs(old_local_anchor.x) > 0.01 else -1.0
		var sign_y: float = sign(old_local_anchor.y) if abs(old_local_anchor.y) > 0.01 else 1.0
		
		# New local anchor position
		var new_local_anchor: Vector3 = Vector3(sign_x * half_w_new, sign_y * half_h_new, 0.0)
		
		# Offset needed to keep anchor in same world position
		var local_offset: Vector3 = old_local_anchor - new_local_anchor
		global_position += global_transform.basis * local_offset
	
	# Update resize handle positions
	_update_resize_handle_positions()
	
	# Emit signal
	panel_resized.emit(new_quad_size)


func set_resize_handle_highlight(corner_index: int, highlighted: bool) -> void:
	"""Set the visual highlight state of a resize handle."""
	if corner_index < 0 or corner_index >= _resize_handle_materials.size():
		return
	
	var mat: StandardMaterial3D = _resize_handle_materials[corner_index]
	if mat:
		mat.albedo_color = resize_handle_hover_color if highlighted else resize_handle_color
	
	# Track if any handle is being hovered
	if highlighted:
		_hovered_handle_index = corner_index
	elif _hovered_handle_index == corner_index:
		# Only clear if we are unhighlighting the currently hovered one
		_hovered_handle_index = -1
	
	_update_handle_visibility()


func is_resizing() -> bool:
	"""Returns true if currently in a resize operation."""
	return _resize_active_handle != null


func get_resize_handle_corner_index(handle: Node) -> int:
	"""Get the corner index for a resize handle node, or -1 if not a valid handle."""
	if not handle:
		return -1
	if not handle.has_meta("is_resize_handle"):
		return -1
	if not handle.has_meta("parent_viewport"):
		return -1
	if handle.get_meta("parent_viewport") != self:
		return -1
	return handle.get_meta("corner_index", -1)
