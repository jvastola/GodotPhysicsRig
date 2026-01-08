extends Node3D

signal pointer_event(event: Dictionary)
signal hit_scale_changed(scale: float)
signal selection_handle_event(event: Dictionary)

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
@export var enable_pointer_processing: bool = true
@export var enable_debug_logs: bool = false
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

@export_group("Selection Handles")
@export var enable_selection_bounds: bool = false
@export var show_selection_handles: bool = true
@export_range(0.025, 1.0, 0.01) var selection_handle_length: float = 0.125
@export_range(0.0, 0.5, 0.005) var selection_handle_offset: float = 0.05
@export_range(0.0, 0.3, 0.005) var selection_handle_spacing: float = 0.03
@export_range(0.0025, 0.5, 0.0025) var selection_handle_thickness: float = 0.01
@export_range(0.005, 0.25, 0.005) var selection_handle_base_size: float = 0.02
@export_range(0.0, 0.5, 0.005) var selection_handle_base_gap: float = 0.03
@export_range(0.0, 1.0, 0.01) var selection_handle_base_gap_ratio: float = 0.35
@export_range(0.005, 0.25, 0.005) var selection_handle_cap_size: float = 0.015
@export_range(0.0025, 0.25, 0.0025) var selection_handle_cap_depth: float = 0.01
@export_range(0.01, 0.5, 0.01) var selection_handle_ring_radius: float = 0.06
@export_range(0.0025, 0.25, 0.0025) var selection_handle_ring_thickness: float = 0.0075
@export_range(0.0, 0.5, 0.005) var selection_handle_ring_gap: float = 0.015
@export_range(0.1, 20.0, 0.1) var selection_handle_move_speed: float = 8.0
@export_range(0.0, 0.2, 0.001) var selection_handle_move_deadzone: float = 0.0

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
var _selection_handles: Array[Area3D] = []
var _selection_handle_active_axis: Vector3 = Vector3.ZERO
var _selection_handle_active_mode: String = "translate" # "translate" or "scale"
var _selection_handle_last_proj: float = 0.0
var _pointer_hit_point: Vector3 = Vector3.ZERO
var _selection_handle_grab_point: Vector3 = Vector3.ZERO
var _selection_handle_grab_offset: float = 0.0
var _selection_handle_active_handle: Node3D = null
var _selection_handle_line: MeshInstance3D
var _selection_handle_line_mesh: ImmediateMesh
var _selection_handle_grab_marker: MeshInstance3D
var _selection_handle_scale_reference: float = 0.1
var _selection_last_half_size: Vector3 = Vector3.ZERO
var _selection_last_center: Vector3 = Vector3.ZERO
var _selection_handle_rotate_ref: Vector3 = Vector3.ZERO
var _selection_handle_rotate_last_angle: float = 0.0
var _selection_handle_rotate_center: Vector3 = Vector3.ZERO

# Grip grab mode state
var _grab_target: Node = null  # Currently grabbed object
var _grab_distance: float = 0.0  # Current distance from pointer origin
var _grab_initial_scale: Vector3 = Vector3.ONE  # Scale when grab started
var _grab_offset: Vector3 = Vector3.ZERO  # Offset from grab point to object center
var _prev_grip_pressed: bool = false  # For edge detection
var _grab_should_rotate: bool = false # Whether current grab target allows rotation

# Resize handle state
var _resize_target_viewport: Node = null  # UI viewport being resized
var _resize_corner_index: int = -1        # Which corner is being dragged
var _resize_hover_corner: int = -1        # Which corner is being hovered


func get_hit_point() -> Vector3:
	"""Get the current world-space hit point of the pointer raycast"""
	return _pointer_hit_point


func get_hit_collider() -> Object:
	"""Get the current collider hit by the pointer raycast"""
	if not _raycast:
		return null
	return _raycast.get_collider()


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
	if enable_selection_bounds:
		_setup_selection_bounds()
		_setup_selection_handles()
		_setup_selection_handle_visuals()
	
	set_physics_process(enable_pointer_processing)


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


func _update_selector_shape(new_scale: float) -> void:
	if not _hit_selector_shape or not _hit_selector_shape.shape:
		return
	var radius: float = max(new_scale, 0.0005)
	if _hit_selector_shape.shape is SphereShape3D:
		var sphere := _hit_selector_shape.shape as SphereShape3D
		sphere.radius = radius
	elif _hit_selector_shape.shape is CylinderShape3D:
		var cylinder := _hit_selector_shape.shape as CylinderShape3D
		cylinder.radius = radius
		cylinder.height = max(radius * 0.2, 0.0005)


func _setup_selection_bounds() -> void:
	if not enable_selection_bounds:
		return
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


func _setup_selection_handles() -> void:
	if not enable_selection_bounds:
		return
	if not show_selection_handles:
		return
	_selection_handles.clear()
	var defs := [
		{"axis": Vector3.RIGHT, "name": "HandleXPos", "color": Color(1.0, 0.25, 0.25)},
		{"axis": Vector3.LEFT, "name": "HandleXNeg", "color": Color(0.9, 0.4, 0.4)},
		{"axis": Vector3.UP, "name": "HandleYPos", "color": Color(0.35, 1.0, 0.35)},
		{"axis": Vector3.DOWN, "name": "HandleYNeg", "color": Color(0.4, 0.9, 0.4)},
		{"axis": Vector3.BACK, "name": "HandleZPos", "color": Color(0.3, 0.5, 1.0)}, # Godot forward is -Z
		{"axis": Vector3.FORWARD, "name": "HandleZNeg", "color": Color(0.35, 0.6, 0.95)}
	]
	for def in defs:
		var axis_vec: Vector3 = (def["axis"] as Vector3).normalized()
		# Translate handle (arrow)
		var handle := Area3D.new()
		handle.name = def["name"]
		handle.monitorable = false # avoid being picked up by selector area
		handle.collision_layer = pointer_collision_mask
		handle.collision_mask = 0
		handle.set_meta("selection_handle_axis", axis_vec)
		handle.set_meta("selection_handle_name", def["name"])
		handle.set_meta("selection_handle_mode", "translate")
		if pointer_handler_group != StringName():
			handle.add_to_group(pointer_handler_group)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Visual"
		mesh_instance.mesh = _build_handle_mesh(selection_handle_length)
		mesh_instance.material_override = _build_handle_material(def["color"])
		handle.add_child(mesh_instance)
		var collider := CollisionShape3D.new()
		collider.name = "Collision"
		collider.shape = _build_handle_collision_shape(selection_handle_length)
		collider.position = Vector3(0, 0, selection_handle_length * 0.5)
		handle.add_child(collider)
		handle.visible = false
		add_child(handle)
		_selection_handles.append(handle)

		# Scale handle (cube)
		var base_handle := Area3D.new()
		base_handle.name = def["name"] + "Base"
		base_handle.monitorable = false
		base_handle.collision_layer = pointer_collision_mask
		base_handle.collision_mask = 0
		base_handle.set_meta("selection_handle_axis", axis_vec)
		base_handle.set_meta("selection_handle_name", def["name"] + "Base")
		base_handle.set_meta("selection_handle_mode", "scale")
		if pointer_handler_group != StringName():
			base_handle.add_to_group(pointer_handler_group)
		var base_instance := MeshInstance3D.new()
		base_instance.name = "Base"
		base_instance.mesh = _build_handle_base_mesh()
		base_instance.material_override = _build_handle_material(def["color"])
		base_handle.add_child(base_instance)
		var cap_instance := MeshInstance3D.new()
		cap_instance.name = "Cap"
		cap_instance.mesh = _build_handle_cap_mesh()
		cap_instance.material_override = base_instance.material_override
		cap_instance.position = Vector3(0, 0, -(selection_handle_base_size * 0.5 + selection_handle_cap_depth * 0.5))
		base_handle.add_child(cap_instance)
		var base_collider := CollisionShape3D.new()
		base_collider.name = "Collision"
		base_collider.shape = _build_handle_base_collision_shape()
		base_handle.add_child(base_collider)
		base_handle.visible = false
		add_child(base_handle)
		_selection_handles.append(base_handle)

		# Rotate handle (ring)
		var ring_handle := Area3D.new()
		ring_handle.name = def["name"] + "Rotate"
		ring_handle.monitorable = false
		ring_handle.collision_layer = pointer_collision_mask
		ring_handle.collision_mask = 0
		ring_handle.set_meta("selection_handle_axis", axis_vec)
		ring_handle.set_meta("selection_handle_name", def["name"] + "Rotate")
		ring_handle.set_meta("selection_handle_mode", "rotate")
		if pointer_handler_group != StringName():
			ring_handle.add_to_group(pointer_handler_group)
		var ring_instance := MeshInstance3D.new()
		ring_instance.name = "Ring"
		ring_instance.mesh = _build_handle_ring_mesh()
		ring_instance.material_override = _build_handle_material(def["color"])
		ring_handle.add_child(ring_instance)
		var ring_collider := CollisionShape3D.new()
		ring_collider.name = "Collision"
		ring_collider.shape = _build_handle_ring_collision_shape()
		ring_handle.add_child(ring_collider)
		ring_handle.visible = false
		add_child(ring_handle)
		_selection_handles.append(ring_handle)


func _setup_selection_handle_visuals() -> void:
	_selection_handle_line_mesh = ImmediateMesh.new()
	_selection_handle_line = MeshInstance3D.new()
	_selection_handle_line.name = "SelectionHandleLine"
	_selection_handle_line.mesh = _selection_handle_line_mesh
	_selection_handle_line.material_override = _build_handle_material(Color(0.9, 0.9, 0.9, 0.8))
	_selection_handle_line.visible = false
	add_child(_selection_handle_line)

	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = max(selection_handle_thickness * 0.6, 0.01)
	marker_mesh.height = marker_mesh.radius * 2.0
	marker_mesh.radial_segments = 8
	_selection_handle_grab_marker = MeshInstance3D.new()
	_selection_handle_grab_marker.name = "SelectionHandleGrabMarker"
	_selection_handle_grab_marker.mesh = marker_mesh
	_selection_handle_grab_marker.material_override = _build_handle_material(Color(1.0, 1.0, 0.2, 0.9))
	_selection_handle_grab_marker.visible = false
	add_child(_selection_handle_grab_marker)


func _build_handle_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Draw on top of scene geometry (like the red grapple ball).
	mat.no_depth_test = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.render_priority = 2
	return mat


func _build_handle_mesh(length: float) -> Mesh:
	# Build a low-poly solid arrow: cylinder shaft + cone head.
	var st: SurfaceTool = SurfaceTool.new()
	var mesh: ArrayMesh = ArrayMesh.new()

	var sides: int = 10
	var radius: float = max(selection_handle_thickness * 1.2, 0.01)
	var shaft_len: float = max(length * 0.55, 0.015)
	var head_len: float = max(length * 0.45, 0.01)
	var tip_z: float = shaft_len + head_len
	var head_radius: float = radius * 1.35

	# Shaft (cylinder)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(sides):
		var a0: float = TAU * float(i) / float(sides)
		var a1: float = TAU * float((i + 1) % sides) / float(sides)
		var p0: Vector3 = Vector3(cos(a0) * radius, sin(a0) * radius, 0.0)
		var p1: Vector3 = Vector3(cos(a1) * radius, sin(a1) * radius, 0.0)
		var p0_top: Vector3 = Vector3(p0.x, p0.y, shaft_len)
		var p1_top: Vector3 = Vector3(p1.x, p1.y, shaft_len)

		# quad split into two triangles
		st.add_vertex(p0)
		st.add_vertex(p1_top)
		st.add_vertex(p0_top)

		st.add_vertex(p0)
		st.add_vertex(p1)
		st.add_vertex(p1_top)
	st.generate_normals()
	st.commit(mesh)

	# Head (cone)
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip: Vector3 = Vector3(0, 0, tip_z)
	for i in range(sides):
		var a0: float = TAU * float(i) / float(sides)
		var a1: float = TAU * float((i + 1) % sides) / float(sides)
		var b0: Vector3 = Vector3(cos(a0) * head_radius, sin(a0) * head_radius, shaft_len)
		var b1: Vector3 = Vector3(cos(a1) * head_radius, sin(a1) * head_radius, shaft_len)

		st.add_vertex(tip)
		st.add_vertex(b1)
		st.add_vertex(b0)
	st.generate_normals()
	st.commit(mesh)

	# Cap the cone base so the underside is solid.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base_center: Vector3 = Vector3(0, 0, shaft_len)
	for i in range(sides):
		var a0: float = TAU * float(i) / float(sides)
		var a1: float = TAU * float((i + 1) % sides) / float(sides)
		var b0: Vector3 = Vector3(cos(a0) * head_radius, sin(a0) * head_radius, shaft_len)
		var b1: Vector3 = Vector3(cos(a1) * head_radius, sin(a1) * head_radius, shaft_len)
		# Wind so normals face outward/downward.
		st.add_vertex(base_center)
		st.add_vertex(b0)
		st.add_vertex(b1)
	st.generate_normals()
	st.commit(mesh)

	return mesh


func _build_handle_base_mesh() -> Mesh:
	var box := BoxMesh.new()
	var base_size: float = max(selection_handle_thickness * 3.0, selection_handle_base_size)
	box.size = Vector3(base_size, base_size, base_size) # make it a cube
	return box


func _build_handle_cap_mesh() -> Mesh:
	var box := BoxMesh.new()
	var size_xy: float = max(selection_handle_cap_size, selection_handle_thickness * 2.0)
	var depth: float = max(selection_handle_cap_depth, selection_handle_thickness)
	box.size = Vector3(size_xy, size_xy, depth)
	return box


func _build_handle_ring_mesh() -> Mesh:
	var torus := TorusMesh.new()
	torus.inner_radius = max(selection_handle_ring_radius * 0.5, selection_handle_ring_thickness * 2.0)
	torus.outer_radius = max(selection_handle_ring_radius, torus.inner_radius + selection_handle_ring_thickness)
	torus.ring_segments = 32
	return torus


func _build_handle_base_collision_shape() -> BoxShape3D:
	var box := BoxShape3D.new()
	var half: float = max(selection_handle_base_size * 0.5, selection_handle_thickness * 1.5)
	box.extents = Vector3(half, half, half)
	return box


func _build_handle_ring_collision_shape() -> CylinderShape3D:
	var cyl := CylinderShape3D.new()
	cyl.radius = max(selection_handle_ring_radius, selection_handle_ring_thickness * 2.0)
	cyl.height = max(selection_handle_ring_thickness * 3.0, selection_handle_cap_depth)
	return cyl


func _build_handle_collision_shape(length: float) -> BoxShape3D:
	var box := BoxShape3D.new()
	var radius: float = max(selection_handle_thickness * 1.2, 0.01)
	var half_thickness: float = max(radius * 1.1, 0.01)
	box.extents = Vector3(half_thickness, half_thickness, max(length * 0.35, 0.01))
	return box


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
	var target := _selection_move_target(node3d)
	if target == self or _selected_objects.has(target):
		return
	_selected_objects.append(target)
	_update_selection_bounds()


func _selection_move_target(node: Node3D) -> Node3D:
	var candidates: Array[Node3D] = []
	var probe: Node = node
	while probe and probe is Node3D and probe != self:
		candidates.append(probe as Node3D)
		probe = probe.get_parent()
	# Prefer the nearest ancestor that has both visuals and collision, so meshes move with the collider.
	for candidate in candidates:
		if _has_visual_descendant(candidate) and _has_collision_descendant(candidate):
			return candidate
	# Otherwise prefer the nearest collision object (bodies/areas).
	for candidate in candidates:
		if candidate is CollisionObject3D:
			return candidate
	# Fallback to the original node.
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


func _update_selection_handles(aabb: AABB) -> void:
	if _selection_handles.is_empty() or not show_selection_handles:
		return
	var has_box: bool = aabb.size != Vector3.ZERO
	if not has_box:
		_hide_selection_handles()
		return
	var center: Vector3 = aabb.position + aabb.size * 0.5
	var half_size: Vector3 = aabb.size * 0.5
	_selection_last_half_size = half_size
	_selection_last_center = center
	for handle in _selection_handles:
		if not is_instance_valid(handle):
			continue
		var axis_dir: Vector3 = handle.get_meta("selection_handle_axis", Vector3.ZERO)
		if axis_dir == Vector3.ZERO:
			handle.visible = false
			handle.monitoring = false
			continue
		var mode: String = handle.get_meta("selection_handle_mode", "translate")
		var axis_unit: Vector3 = axis_dir.normalized()
		var face_offset := Vector3(
			half_size.x * axis_dir.x,
			half_size.y * axis_dir.y,
			half_size.z * axis_dir.z
		)
		# Keep consistent spacing relative to each element (box -> ring -> arrow) regardless of selection size.
		var cube_center_offset: float = selection_handle_base_gap + selection_handle_base_size * 0.5
		var ring_center_offset: float = cube_center_offset + selection_handle_base_size * 0.5 + selection_handle_ring_gap + selection_handle_ring_radius
		var extra: float = cube_center_offset
		if mode == "translate":
			# Place arrow further out so the cube and ring sit between box and arrow.
			extra = ring_center_offset + selection_handle_ring_radius + selection_handle_ring_thickness + selection_handle_spacing
		elif mode == "rotate":
			extra = ring_center_offset
		var pos: Vector3 = center + face_offset + axis_unit * extra
		if mode == "rotate":
			var y := axis_unit
			var x := _any_perpendicular(y)
			var z := x.cross(y).normalized()
			var ring_basis := Basis(x, y, z)
			handle.global_transform = Transform3D(ring_basis, pos)
		else:
			var up: Vector3 = Vector3.FORWARD if abs(axis_unit.dot(Vector3.UP)) > 0.95 else Vector3.UP
			var new_basis := Basis.looking_at(-axis_unit, up)
			handle.global_transform = Transform3D(new_basis, pos)
		# Inherit player scaling via scene graph; avoid double-scaling.
		handle.scale = Vector3.ONE
		handle.visible = true
		handle.monitoring = true


func _hide_selection_handles() -> void:
	if _selection_handles.is_empty():
		return
	for handle in _selection_handles:
		if is_instance_valid(handle):
			handle.visible = false
			handle.monitoring = false


func _update_selection_handle_movement(_delta: float, action_state: Dictionary) -> void:
	if not enable_selection_bounds or not show_selection_handles:
		return
	if _selection_handle_active_axis == Vector3.ZERO:
		return
	if not action_state.get("pressed", false):
		_update_handle_visuals(false)
		return
	_selection_handle_grab_point = _compute_active_grab_point()
	var axis: Vector3 = _selection_handle_active_axis
	var current_proj: float = _pointer_hit_point.dot(axis)
	var delta_proj: float = current_proj - _selection_handle_last_proj
	if _selection_handle_active_mode == "scale":
		if abs(delta_proj) <= selection_handle_move_deadzone:
			return
		if _selection_handle_scale_reference <= 0.0:
			return
		var scale_factor: float = 1.0 + (delta_proj / _selection_handle_scale_reference)
		scale_factor = clamp(scale_factor, 0.05, 10.0)
		_scale_selected_objects_along_axis(axis, scale_factor)
	elif _selection_handle_active_mode == "rotate":
		var cur_vec := _project_on_plane(_pointer_hit_point - _selection_handle_rotate_center, axis)
		if cur_vec.length() < 0.0001 or _selection_handle_rotate_ref.length() < 0.0001:
			return
		var angle := _signed_angle_on_plane(_selection_handle_rotate_ref, cur_vec, axis)
		var delta_angle := angle - _selection_handle_rotate_last_angle
		if abs(delta_angle) > 0.0001:
			_rotate_selected_objects(axis, _selection_handle_rotate_center, delta_angle)
			_selection_handle_rotate_last_angle = angle
	else:
		# Move exactly by the pointer's delta along the locked axis so the hit point stays anchored.
		if abs(delta_proj) <= selection_handle_move_deadzone:
			return
		var move_amount: float = delta_proj
		_move_selected_objects_along_axis(axis, move_amount)
	_selection_handle_last_proj = current_proj
	_update_selection_bounds()
	_update_handle_visuals(true)


func _update_handle_visuals(active: bool) -> void:
	if not _selection_handle_line or not _selection_handle_line_mesh or not _selection_handle_grab_marker:
		return
	_selection_handle_line.visible = active
	_selection_handle_grab_marker.visible = active
	_selection_handle_line_mesh.clear_surfaces()
	if not active:
		return
	_selection_handle_line.global_transform = Transform3D.IDENTITY
	_selection_handle_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_selection_handle_line_mesh.surface_add_vertex(_selection_handle_grab_point)
	_selection_handle_line_mesh.surface_add_vertex(_pointer_hit_point)
	_selection_handle_line_mesh.surface_end()
	_selection_handle_grab_marker.global_transform = Transform3D(Basis.IDENTITY, _selection_handle_grab_point)


func _compute_active_grab_point() -> Vector3:
	if _selection_handle_active_handle and is_instance_valid(_selection_handle_active_handle) and _selection_handle_active_axis != Vector3.ZERO:
		var origin: Vector3 = _selection_handle_active_handle.global_transform.origin
		return origin + _selection_handle_active_axis * _selection_handle_grab_offset
	return _selection_handle_grab_point


func _move_selected_objects_along_axis(axis: Vector3, distance: float) -> void:
	if axis == Vector3.ZERO:
		return
	var dir: Vector3 = axis.normalized()
	for node in _selected_objects:
		if is_instance_valid(node):
			_move_node_along_axis(node, dir, distance)


func _scale_selected_objects_along_axis(axis: Vector3, scale_factor: float) -> void:
	if axis == Vector3.ZERO:
		return
	var dir: Vector3 = axis.normalized()
	for node in _selected_objects:
		if is_instance_valid(node):
			_scale_node_along_axis(node, dir, scale_factor)


func _rotate_selected_objects(axis: Vector3, pivot: Vector3, angle: float) -> void:
	if axis == Vector3.ZERO or angle == 0.0:
		return
	var dir: Vector3 = axis.normalized()
	for node in _selected_objects:
		if is_instance_valid(node):
			_rotate_node_around_axis(node, pivot, dir, angle)


func _update_selection_handle_activation(action_state: Dictionary, handler: Node) -> void:
	if not enable_selection_bounds or not show_selection_handles:
		return
	if not handler or not is_instance_valid(handler):
		if action_state.get("just_released", false):
			_selection_handle_active_axis = Vector3.ZERO
			_selection_handle_active_handle = null
			_selection_handle_active_mode = "translate"
			_selection_handle_rotate_ref = Vector3.ZERO
			_selection_handle_rotate_last_angle = 0.0
			_update_handle_visuals(false)
		return
	if handler.has_meta("selection_handle_axis") and action_state.get("just_pressed", false):
		var axis_meta = handler.get_meta("selection_handle_axis")
		if axis_meta is Vector3:
			_selection_handle_active_axis = (axis_meta as Vector3).normalized()
			_selection_handle_active_handle = handler as Node3D
			_selection_handle_active_mode = handler.get_meta("selection_handle_mode", "translate")
			_selection_handle_last_proj = _pointer_hit_point.dot(_selection_handle_active_axis)
			_selection_handle_grab_point = _compute_active_grab_point()
			_selection_handle_grab_offset = (_selection_handle_grab_point - _selection_handle_active_handle.global_transform.origin).dot(_selection_handle_active_axis) if _selection_handle_active_handle else 0.0
			var ref_extent: float = abs(_selection_last_half_size.x * _selection_handle_active_axis.x) + abs(_selection_last_half_size.y * _selection_handle_active_axis.y) + abs(_selection_last_half_size.z * _selection_handle_active_axis.z)
			_selection_handle_scale_reference = max(ref_extent, 0.05)
			if _selection_handle_active_mode == "rotate":
				_selection_handle_rotate_center = _selection_last_center
				var ref_vec := _project_on_plane(_pointer_hit_point - _selection_handle_rotate_center, _selection_handle_active_axis)
				if ref_vec.length() < 0.0001:
					ref_vec = _any_perpendicular(_selection_handle_active_axis)
				_selection_handle_rotate_ref = ref_vec
				_selection_handle_rotate_last_angle = 0.0
			_update_handle_visuals(true)
	if action_state.get("just_released", false):
		_selection_handle_active_axis = Vector3.ZERO
		_selection_handle_active_handle = null
		_selection_handle_active_mode = "translate"
		_selection_handle_rotate_ref = Vector3.ZERO
		_selection_handle_rotate_last_angle = 0.0
		_update_handle_visuals(false)


func _move_node_along_axis(node: Node3D, dir: Vector3, distance: float) -> void:
	var delta_vec: Vector3 = dir * distance
	if node is RigidBody3D:
		var rb := node as RigidBody3D
		var xform := rb.global_transform
		xform.origin += delta_vec
		rb.global_transform = xform
		# Keep body awake and prevent inherited momentum from old velocity
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.sleeping = false
	else:
		node.global_position += delta_vec


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


func _scale_node_along_axis(node: Node3D, dir: Vector3, scale_factor: float) -> void:
	if scale_factor == 1.0:
		return
	# Map world axis into the node's local space to scale the most aligned components.
	var local_axis: Vector3 = node.global_transform.basis.inverse() * dir
	var weights := Vector3(abs(local_axis.x), abs(local_axis.y), abs(local_axis.z))
	# Avoid zero weights so we at least apply some scaling.
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


func _update_selection_bounds() -> void:
	if not enable_selection_bounds:
		return
	if not _selection_bounds_mesh:
		return
	var combined := _compute_selection_aabb()
	if combined.size == Vector3.ZERO:
		_selection_bounds.visible = false
		_selection_bounds_mesh.clear_surfaces()
		_update_selection_handles(combined)
		return
	_draw_selection_bounds(combined)
	_update_selection_handles(combined)


func _clear_selection() -> void:
	if not enable_selection_bounds:
		return
	_selected_objects.clear()
	if _selection_bounds_mesh:
		_selection_bounds_mesh.clear_surfaces()
	if _selection_bounds:
		_selection_bounds.visible = false
	_hide_selection_handles()
	_selection_handle_active_axis = Vector3.ZERO
	_selection_handle_active_handle = null
	_update_handle_visuals(false)

func _physics_process(delta: float) -> void:
	if not enable_pointer_processing:
		return
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
	_update_selection_handle_movement(delta, action_state)

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
		if enable_debug_logs and is_android and action_state["just_pressed"]:
			print("HandPointer: Hit on Android - collider=", collider_obj, " handler=", handler)
			print("  - collision_mask=", _raycast.collision_mask, " point=", end)

	_pointer_hit_point = end

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
		_update_selection_handle_activation(action_state, handler)
		_update_resize_handle_activation(handler)
	else:
		_clear_hover_state()
		_clear_ui_scroll_capture(controller)
		_update_resize_handle_activation(null)
		if action_state.get("just_released", false):
			_selection_handle_active_axis = Vector3.ZERO
			_selection_handle_active_handle = null
			_update_handle_visuals(false)

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

	# First try Godot InputMap if the action exists there
	if interact_action != "" and InputMap.has_action(interact_action):
		state["pressed"] = Input.is_action_pressed(interact_action)
		state["just_pressed"] = Input.is_action_just_pressed(interact_action)
		state["just_released"] = Input.is_action_just_released(interact_action)
		state["strength"] = Input.get_action_strength(interact_action)
	
	# Always also check XR controller directly for VR - this handles OpenXR actions
	# that aren't mapped to Godot InputMap
	if controller:
		var xr_value: float = 0.0
		
		# Try analog trigger value first (most reliable on Quest/OpenXR)
		if controller.has_method("get_float"):
			xr_value = controller.get_float("trigger")
			# Debug: Log trigger value on Android
			if enable_debug_logs and OS.get_name() == "Android" and xr_value > 0.1:
				print("HandPointer: XR trigger value = ", xr_value)
		
		# Fallback to trigger_click boolean if analog returns 0
		if xr_value < 0.01 and controller.has_method("get_float"):
			var click_value: float = controller.get_float("trigger_click")
			if click_value > 0.5:
				xr_value = 1.0
		
		# Additional fallback: check is_button_pressed
		if xr_value < 0.01 and controller.has_method("is_button_pressed"):
			if controller.is_button_pressed("trigger_click"):
				xr_value = 1.0
			elif controller.is_button_pressed("trigger"):
				xr_value = 1.0
		
		# Use XR value if it's higher than what we got from InputMap
		if xr_value > state["strength"]:
			state["strength"] = xr_value
			var xr_pressed: bool = xr_value >= fallback_trigger_threshold
			# Only update pressed state if XR shows pressed OR if InputMap didn't detect anything
			if xr_pressed or not state["pressed"]:
				state["pressed"] = xr_pressed
				state["just_pressed"] = xr_pressed and not _prev_action_pressed
				state["just_released"] = (not xr_pressed) and _prev_action_pressed

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
	if target and target.has_meta("selection_handle_axis"):
		payload["selection_handle_axis"] = target.get_meta("selection_handle_axis")
		payload["selection_handle_name"] = target.get_meta("selection_handle_name")
	pointer_event.emit(payload.duplicate(true))
	if payload.has("selection_handle_axis"):
		selection_handle_event.emit(payload.duplicate(true))
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
	if not enable_grip_grab:
		return
	
	# Get grip state
	var grip_value: float = 0.0
	if controller and controller.has_method("get_float"):
		grip_value = controller.get_float(grip_action)
	var grip_pressed: bool = grip_value >= grip_threshold
	
	# Fallback to mouse left click if not pressed via controller
	if not grip_pressed:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			grip_pressed = true
			
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
	if is_grabbing() and grip_pressed:
		_update_grabbed_object(delta, controller)
	
	# Cleanup invalid targets
	if _grab_target and not is_instance_valid(_grab_target):
		_grab_target = null
	if _resize_target_viewport and not is_instance_valid(_resize_target_viewport):
		_resize_target_viewport = null


func _try_start_grab() -> void:
	"""Attempt to start grabbing the currently hovered target."""
	if not _hover_target or not is_instance_valid(_hover_target):
		return
	
	# Check if this is a resize handle
	if _hover_target.has_meta("is_resize_handle"):
		_try_start_resize()
		return
	
	# Check if target supports pointer grab
	if not _hover_target.has_method("pointer_grab_set_distance"):
		# Fall back to checking if it's a Node3D we can manipulate
		if not _hover_target is Node3D:
			return
	
	# Resolve actual grab target (allows redirection, e.g. from UI panel to WindowWrapper)
	# If get_grab_target() exists, we MUST use its result. If it returns null, it means "ungrabbable".
	var final_target: Node = _hover_target
	if _hover_target.has_method("get_grab_target"):
		final_target = _hover_target.get_grab_target()
		if not final_target:
			# Target explicitly requested no grab
			return
	
	_grab_target = final_target
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
	
	# Calculate grab parameters based on the ACTUAL target we are moving
	if _grab_target is Node3D:
		var target_3d: Node3D = _grab_target as Node3D
		
		# Get the actual hit point from raycast
		var hit_point: Vector3 = target_3d.global_position # Default to center if ray fails
		if _raycast and _raycast.is_colliding():
			hit_point = _raycast.get_collision_point()
		
		# Calculate offset from hit point to object center (in object's local space)
		# IMPORTANT: Use target_3d (Wrapper) position, even if we hit a child (Chrome)
		_grab_offset = target_3d.global_position - hit_point
		
		# Calculate distance along ray to HIT POINT (not object center)
		# This ensures we grab it "where it is" relative to the pointer
		var to_hit: Vector3 = hit_point - start
		_grab_distance = to_hit.dot(axis_world)
		_grab_distance = clamp(_grab_distance, grab_min_distance, grab_max_distance)
		_grab_initial_scale = target_3d.scale
	else:
		_grab_distance = ray_length
		_grab_initial_scale = Vector3.ONE
		_grab_offset = Vector3.ZERO


	
	print("HandPointer: Started grab on ", _grab_target.name, " at distance ", _grab_distance, " offset ", _grab_offset)


func _try_start_resize() -> void:
	"""Start a resize operation on a UI viewport."""
	if not _hover_target or not _hover_target.has_meta("is_resize_handle"):
		return
	
	# Get parent viewport and corner index
	var parent_viewport = _hover_target.get_meta("parent_viewport", null)
	var corner_index: int = _hover_target.get_meta("corner_index", -1)
	
	if not parent_viewport or corner_index < 0:
		return
	
	if not parent_viewport.has_method("start_resize"):
		print("HandPointer: Parent viewport doesn't support resize")
		return
	
	# Get grab position
	var grab_pos: Vector3 = _pointer_hit_point
	if _raycast and _raycast.is_colliding():
		grab_pos = _raycast.get_collision_point()
	
	# Store resize state
	_resize_target_viewport = parent_viewport
	_resize_corner_index = corner_index
	
	# Start the resize
	parent_viewport.start_resize(corner_index, grab_pos)
	print("HandPointer: Started resize on corner ", corner_index)


func _end_grab() -> void:
	"""End the current grab."""
	# End resize if active
	if _resize_target_viewport and is_instance_valid(_resize_target_viewport):
		if _resize_target_viewport.has_method("end_resize"):
			_resize_target_viewport.end_resize()
		print("HandPointer: Ended resize")
	_resize_target_viewport = null
	_resize_corner_index = -1
	
	# End normal grab
	if _grab_target:
		print("HandPointer: Ended grab on ", String(_grab_target.name) if is_instance_valid(_grab_target) else "invalid")
	_grab_target = null
	_grab_distance = 0.0
	_grab_initial_scale = Vector3.ONE
	_grab_offset = Vector3.ZERO
	_grab_should_rotate = false


func _update_grabbed_object(delta: float, controller: XRController3D) -> void:
	"""Update the grabbed object's position and scale based on joystick input."""
	# Check if we're in resize mode
	if _resize_target_viewport and is_instance_valid(_resize_target_viewport):
		_update_resize_operation()
		return
	
	if not _grab_target or not is_instance_valid(_grab_target):
		return
	
	# Get joystick input
	var joystick: Vector2 = _get_pointer_axis_vector(controller)

	# Only allow joystick manipulation if trigger is also held
	var trigger_val: float = 0.0
	if controller and controller.has_method("get_float"):
		trigger_val = controller.get_float("trigger")
		if trigger_val == 0.0:
			trigger_val = controller.get_float("trigger_click")
	
	if trigger_val < 0.5:
		joystick = Vector2.ZERO
	
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


func _update_resize_operation() -> void:
	"""Update the current resize operation based on pointer position."""
	if not _resize_target_viewport or not is_instance_valid(_resize_target_viewport):
		_end_grab() # Clean up state
		return
	
	# Calculate current grab position
	var grab_pos: Vector3 = _pointer_hit_point
	if _raycast and _raycast.is_colliding():
		grab_pos = _raycast.get_collision_point()
	
	# Update the resize
	if _resize_target_viewport.has_method("update_resize"):
		_resize_target_viewport.update_resize(grab_pos)


func _update_resize_handle_activation(handler: Node) -> void:
	"""Update visual highlighting of resize handles."""
	var new_hover_corner: int = -1
	var viewport: Node = null
	
	if handler and handler.has_meta("is_resize_handle"):
		new_hover_corner = handler.get_meta("corner_index", -1)
		viewport = handler.get_meta("parent_viewport", null)
	
	# If changed, update highlights
	if new_hover_corner != _resize_hover_corner:
		# Unhighlight old
		if _resize_hover_corner != -1 and _resize_target_viewport and is_instance_valid(_resize_target_viewport):
			if _resize_target_viewport.has_method("set_resize_handle_highlight"):
				_resize_target_viewport.set_resize_handle_highlight(_resize_hover_corner, false)
		elif _resize_hover_corner != -1 and viewport and is_instance_valid(viewport):
			# Try to unhighlight on the new viewport if we switched handles within same viewport
			if viewport.has_method("set_resize_handle_highlight"):
				viewport.set_resize_handle_highlight(_resize_hover_corner, false)
				
		# Highlight new
		if new_hover_corner != -1 and viewport and is_instance_valid(viewport):
			if viewport.has_method("set_resize_handle_highlight"):
				viewport.set_resize_handle_highlight(new_hover_corner, true)
		
		_resize_hover_corner = new_hover_corner
		# If we're not resizing, track the potential target viewport
		if not _resize_target_viewport:
			_resize_target_viewport = viewport # Only temporarily for highlight
	
	# If we stopped hovering a handle and aren't resizing, clear the viewport ref
	if new_hover_corner == -1 and not is_grabbing():
		_resize_target_viewport = null


func is_grabbing() -> bool:
	"""Returns true if currently grabbing an object."""
	return (_grab_target != null and is_instance_valid(_grab_target)) or is_resizing()


func is_resizing() -> bool:
	"""Returns true if currently resizing a UI panel."""
	return _resize_target_viewport != null and _resize_corner_index != -1


func get_grabbed_object() -> Node:
	"""Returns the currently grabbed object, or null."""
	if _grab_target and is_instance_valid(_grab_target):
		return _grab_target
	if _resize_target_viewport and is_instance_valid(_resize_target_viewport):
		return _resize_target_viewport
	return null
