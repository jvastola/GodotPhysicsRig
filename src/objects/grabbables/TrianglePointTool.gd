extends Grabbable
class_name TrianglePointTool

# Placement and snapping
@export var snap_radius: float = 0.03
@export var selection_radius: float = 0.05
@export var edge_dot_spacing: float = 0.08
@export var clear_action: String = "secondary_click"

@export var trigger_threshold: float = 0.5
@export var long_press_duration: float = 0.5

# Visuals
@export var preview_color: Color = Color(0.3, 1.0, 0.4, 0.6)
@export var snap_preview_color: Color = Color(1.0, 0.5, 0.2, 0.8)
@export var vertex_color: Color = Color(1.0, 0.9, 0.4, 1.0)
@export var edge_dot_color: Color = Color(0.9, 0.9, 1.0, 0.8)
@export var triangle_color: Color = Color(0.2, 0.8, 1.0, 0.25)
@export var triangle_outline_color: Color = Color(0.2, 0.8, 1.0, 0.8)
@export var stroke_color: Color = Color(1.0, 0.6, 0.2, 0.9)
@export var stroke_emission: float = 0.4
@export var preview_size: float = 0.025
@export var beam_color: Color = Color(0.2, 0.9, 1.0, 0.6)
@export var add_mode_color: Color = Color(0.2, 1.0, 0.4, 0.8)
@export var edit_mode_color: Color = Color(1.0, 0.25, 0.25, 0.8)
@export var mode_toggle_action: String = "secondary_click" 
@export var orb_offset: Vector3 = Vector3(0.06, 0, 0)
@export var tip_forward_offset: float = 0.05

var _preview: MeshInstance3D
var _preview_material: StandardMaterial3D
var _triangle_mesh_instance: MeshInstance3D
var _triangle_mesh: ArrayMesh
var _outline_mesh_instance: MeshInstance3D
var _outline_immediate: ImmediateMesh
var _guide_mesh_instance: MeshInstance3D
var _guide_immediate: ImmediateMesh
var _beam_mesh_instance: MeshInstance3D
var _beam_immediate: ImmediateMesh
# Removed edge dots variables
var _vertex_meshes: Array[MeshInstance3D] = []
var _points: Array[Node3D] = []
var _point_container: Node3D
var _stroke_particles: GPUParticles3D
var _tip: Node3D
var _last_target_normal: Vector3 = Vector3.UP
var _orb: MeshInstance3D
var _orb_material: StandardMaterial3D

var _controller: Node = null
var _prev_trigger_pressed: bool = false
var _trigger_start_time: int = 0
var _long_press_triggered: bool = false
var _prev_toggle_pressed: bool = false
var _drag_index: int = -1
var _is_edit_mode: bool = false

const MAX_POINTS := 32


func _ready() -> void:
	super._ready()
	_create_support_nodes()
	
	grabbed.connect(_on_tool_grabbed)
	released.connect(_on_tool_released)
	
	set_physics_process(false)


func _create_support_nodes() -> void:
	_tip = get_node_or_null("Tip")
	
	_preview = MeshInstance3D.new()
	_preview.name = "PreviewDot"
	_preview.mesh = _make_sphere_mesh(preview_size)
	_preview_material = _make_unshaded_material(preview_color)
	_preview.material_override = _preview_material
	_preview.visible = false
	
	_triangle_mesh_instance = MeshInstance3D.new()
	_triangle_mesh_instance.name = "TriangleMesh"
	_triangle_mesh_instance.material_override = _make_unshaded_material(triangle_color)
	_triangle_mesh = ArrayMesh.new()
	_triangle_mesh_instance.mesh = _triangle_mesh
	
	_outline_mesh_instance = MeshInstance3D.new()
	_outline_mesh_instance.name = "TriangleOutline"
	_outline_immediate = ImmediateMesh.new()
	_outline_mesh_instance.mesh = _outline_immediate
	var outline_mat = _make_unshaded_material(triangle_outline_color)
	outline_mat.emission_enabled = true
	outline_mat.emission = triangle_outline_color
	outline_mat.emission_energy_multiplier = 0.6
	_outline_mesh_instance.material_override = outline_mat

	_guide_mesh_instance = MeshInstance3D.new()
	_guide_mesh_instance.name = "PlacementGuide"
	_guide_immediate = ImmediateMesh.new()
	_guide_mesh_instance.mesh = _guide_immediate
	var guide_mat = _make_unshaded_material(triangle_outline_color)
	guide_mat.emission_enabled = true
	guide_mat.emission = triangle_outline_color
	guide_mat.emission_energy_multiplier = 0.8
	_guide_mesh_instance.material_override = guide_mat

	_beam_mesh_instance = MeshInstance3D.new()
	_beam_mesh_instance.name = "PlacementBeam"
	_beam_immediate = ImmediateMesh.new()
	_beam_mesh_instance.mesh = _beam_immediate
	var beam_mat = _make_unshaded_material(beam_color)
	beam_mat.emission_enabled = true
	beam_mat.emission = beam_color
	beam_mat.emission_energy_multiplier = 0.7
	_beam_mesh_instance.material_override = beam_mat
	
	_ensure_point_container()
	_add_to_root(_preview)
	_add_to_root(_triangle_mesh_instance)
	_add_to_root(_outline_mesh_instance)
	_add_to_root(_guide_mesh_instance)
	_add_to_root(_beam_mesh_instance)
	_create_stroke_particles()
	_create_orb()
	_apply_mode_visuals()


func _ensure_point_container() -> void:
	if is_instance_valid(_point_container):
		return
	_point_container = Node3D.new()
	_point_container.name = "TrianglePointToolPoints"
	_add_to_root(_point_container)


# ... existing code ...

func _add_to_root(node: Node) -> void:
	if not is_instance_valid(node):
		return
	# Use current_scene to ensure visibility and proper lifecycle in the active scene
	var root = get_tree().current_scene
	if not root:
		root = get_tree().root
		
	if root and not node.is_inside_tree():
		# Check if parent is already set to something else to avoid errors
		if node.get_parent():
			node.reparent(root)
		else:
			root.call_deferred("add_child", node)


func _exit_tree() -> void:
	super._exit_tree()
	# Cleanup helper nodes
	for node in [_preview, _triangle_mesh_instance, _outline_mesh_instance, _guide_mesh_instance, _beam_mesh_instance, _stroke_particles, _orb]:
		if is_instance_valid(node):
			node.queue_free()


func _create_stroke_particles() -> void:
	_stroke_particles = GPUParticles3D.new()
	_stroke_particles.name = "TriangleStrokeParticles"
	_stroke_particles.amount = 32
	_stroke_particles.lifetime = 0.4
	_stroke_particles.one_shot = true
	_stroke_particles.speed_scale = 1.5
	_stroke_particles.explosiveness = 0.7
	_stroke_particles.emitting = false
	
	var material = ParticleProcessMaterial.new()
	material.color = stroke_color
	material.emission_curve = Curve.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	material.direction = Vector3(0, 1, 0)
	material.spread = 180.0
	material.initial_velocity_min = 0.3
	material.initial_velocity_max = 0.8
	material.gravity = Vector3.ZERO
	material.scale_min = 0.5
	material.scale_max = 1.0
	material.angular_velocity_min = -4.0
	material.angular_velocity_max = 4.0
	_stroke_particles.process_material = material
	
	_add_to_root(_stroke_particles)


func _create_orb() -> void:
	_orb = MeshInstance3D.new()
	_orb.name = "ModeOrb"
	_orb.mesh = _make_sphere_mesh(0.025)
	_orb_material = _make_unshaded_material(add_mode_color)
	_orb_material.emission_enabled = true
	_orb_material.emission = add_mode_color
	_orb_material.emission_energy_multiplier = 0.8
	_orb.material_override = _orb_material
	_orb.visible = false
	# Orb should be child of the tool (or following it), assuming offset is local
	# Actually, original code did add_child(_orb), so it moves with tool. 
	# BUT since tool logic position was broken, it stayed behind.
	# Now that tool logic is fixed, simple add_child is fine.
	add_child(_orb)
	_orb.position = orb_offset


func _get_mode_color() -> Color:
	return edit_mode_color if _is_edit_mode else add_mode_color


func _apply_mode_visuals() -> void:
	var mode_color = _get_mode_color()
	preview_color = mode_color
	snap_preview_color = mode_color.lightened(0.25)
	if _preview_material:
		_preview_material.albedo_color = preview_color
	if _beam_mesh_instance and _beam_mesh_instance.material_override:
		var bmat = _beam_mesh_instance.material_override as StandardMaterial3D
		if bmat:
			bmat.albedo_color = mode_color
			bmat.emission_enabled = true
			bmat.emission = mode_color
	if _guide_mesh_instance and _guide_mesh_instance.material_override:
		var gmat = _guide_mesh_instance.material_override as StandardMaterial3D
		if gmat:
			gmat.albedo_color = mode_color
			gmat.emission_enabled = true
			gmat.emission = mode_color
	if _outline_mesh_instance and _outline_mesh_instance.material_override:
		var omat = _outline_mesh_instance.material_override as StandardMaterial3D
		if omat:
			omat.albedo_color = triangle_outline_color
			omat.emission_enabled = true
			omat.emission = triangle_outline_color
	if _orb_material:
		_orb_material.albedo_color = mode_color
		_orb_material.emission = mode_color
		_orb_material.emission_enabled = true


func _on_tool_grabbed(hand: RigidBody3D) -> void:
	_controller = null
	if is_instance_valid(hand) and hand.has_method("get"):
		var maybe_target = hand.get("target")
		if maybe_target and maybe_target is Node:
			_controller = maybe_target
	
	# Initialize input states to CURRENT values to prevent immediate triggering
	_prev_trigger_pressed = _is_trigger_pressed()
	
	var toggle_pressed := false
	if is_instance_valid(_controller) and _controller.has_method("is_button_pressed"):
		toggle_pressed = _controller.is_button_pressed(mode_toggle_action)
	elif InputMap.has_action(mode_toggle_action):
		toggle_pressed = Input.is_action_pressed(mode_toggle_action)
	_prev_toggle_pressed = toggle_pressed
	
	_drag_index = -1
	set_physics_process(true)
	_preview.visible = true
	if _orb:
		_orb.visible = true
	_apply_mode_visuals()


func _on_tool_released() -> void:
	set_physics_process(false)
	_controller = null
	_prev_trigger_pressed = false
	_prev_toggle_pressed = false
	_drag_index = -1
	_preview.visible = false
	if _orb:
		_orb.visible = false
	_clear_guide()
	_clear_beam()


func _physics_process(_delta: float) -> void:
	# CRITICAL: Call super to update Grabbable state (sync position with hand)
	super._physics_process(_delta)
	
	if not is_grabbed or not is_instance_valid(grabbing_hand):
		_preview.visible = false
		_clear_guide()
		_clear_beam()
		return
	
	_handle_mode_toggle()
	_preview.visible = true
	var target_point = _get_target_point()
	var target_normal = _last_target_normal
# ... existing code ...

	var hover = _get_nearest_point(target_point)
	var snapped_point = target_point
	var snapped_to_existing = false
	
	# Snap if grip is NOT held
	if not _is_grip_pressed():
		if hover["index"] != -1 and hover["distance"] <= snap_radius:
			snapped_point = hover["position"]
			snapped_to_existing = true
	
	_update_preview(snapped_point, snapped_to_existing, target_normal)
	_update_beam(snapped_point)
	_update_guide(snapped_point)
	_handle_trigger(snapped_point, hover)
	_handle_clear()


func _handle_trigger(snapped_point: Vector3, hover: Dictionary) -> void:
	var trigger_pressed = _is_trigger_pressed()
	var trigger_just_pressed = trigger_pressed and not _prev_trigger_pressed
	var trigger_just_released = not trigger_pressed and _prev_trigger_pressed
	
	var current_time = Time.get_ticks_msec()
	
	if trigger_just_pressed:
		_trigger_start_time = current_time
		_long_press_triggered = false
		
		# Check for drag start immediately (Edit Mode)
		if _is_edit_mode:
			if hover["index"] != -1 and hover["distance"] <= selection_radius:
				_drag_index = hover["index"]
	
	if trigger_pressed:
		# Check for Long Press
		if not _long_press_triggered and _drag_index == -1:
			var elapsed = (current_time - _trigger_start_time) / 1000.0
			if elapsed > long_press_duration:
				# Switch Mode
				_is_edit_mode = not _is_edit_mode
				_apply_mode_visuals()
				_long_press_triggered = true
		
		# Handle Dragging
		if _drag_index != -1:
			_move_point(_drag_index, snapped_point)
			_update_triangle_visuals()
	
	if trigger_just_released:
		if not _long_press_triggered:
			# Short Press Action
			# Only if NOT dragging (if we were dragging, releasing just ends drag)
			if _drag_index == -1:
				if not _is_edit_mode:
					if _points.size() < MAX_POINTS:
						_add_point(snapped_point)
						_update_triangle_visuals()
		
		# Always end drag on release
		_drag_index = -1
	
	_prev_trigger_pressed = trigger_pressed


func _handle_clear() -> void:
	if clear_action.is_empty():
		return
	if InputMap.has_action(clear_action) and Input.is_action_just_pressed(clear_action):
		_clear_points()


func _handle_mode_toggle() -> void:
	var toggle_pressed := false
	# Try specific controller first
	if is_instance_valid(_controller) and _controller.has_method("is_button_pressed"):
		if _controller.is_button_pressed(mode_toggle_action):
			toggle_pressed = true
	
	# Fallback to InputMap (OR logic) so either works
	if not toggle_pressed and InputMap.has_action(mode_toggle_action):
		if Input.is_action_pressed(mode_toggle_action):
			toggle_pressed = true
	
	if toggle_pressed and not _prev_toggle_pressed:
		_is_edit_mode = not _is_edit_mode
		_apply_mode_visuals()
	
	_prev_toggle_pressed = toggle_pressed


func _is_trigger_pressed() -> bool:
	if is_instance_valid(_controller):
		if _controller.has_method("get_float"):
			var trigger_value = _controller.get_float("trigger")
			if trigger_value >= trigger_threshold:
				return true
		if _controller.has_method("is_button_pressed"):
			if _controller.is_button_pressed("trigger_click"):
				return true
	if InputMap.has_action("trigger_click"):
		return Input.is_action_pressed("trigger_click")
	return false


func _is_grip_pressed() -> bool:
	if is_instance_valid(_controller):
		if _controller.has_method("get_float"):
			if _controller.get_float("grip") > 0.5:
				return true
		if _controller.has_method("is_button_pressed"):
			# Fallback if float not available
			pass
	# Try generic action
	if InputMap.has_action("grip_click"):
		if Input.is_action_pressed("grip_click"):
			return true
	return false


func _get_target_point() -> Vector3:
	var tip_xform = _tip.global_transform if is_instance_valid(_tip) else global_transform
	var forward = -tip_xform.basis.z
	if forward.length() < 0.001:
		forward = Vector3.FORWARD
	_last_target_normal = forward.normalized()
	return tip_xform.origin + forward.normalized() * tip_forward_offset


func _get_nearest_point(target: Vector3) -> Dictionary:
	var best_index := -1
	var best_dist := INF
	var best_pos := Vector3.ZERO
	for i in _points.size():
		var p = _points[i].global_position
		var dist = p.distance_to(target)
		if dist < best_dist:
			best_dist = dist
			best_index = i
			best_pos = p
	return {
		"index": best_index,
		"distance": best_dist,
		"position": best_pos
	}


func _add_point(pos: Vector3) -> void:
	_ensure_point_container()
	
	var holder = Node3D.new()
	holder.name = "TrianglePoint%d" % _points.size()
	
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = _make_sphere_mesh(0.018)
	mesh_instance.material_override = _make_unshaded_material(vertex_color)
	holder.add_child(mesh_instance)
	
	_point_container.add_child(holder)
	holder.global_position = pos
	_points.append(holder)
	_vertex_meshes.append(mesh_instance)
	_emit_stroke(pos)


func _move_point(index: int, pos: Vector3) -> void:
	if index < 0 or index >= _points.size():
		return
	_points[index].global_position = pos
	_emit_stroke(pos)


func _clear_points() -> void:
	for p in _points:
		if is_instance_valid(p):
			p.queue_free()
	_points.clear()
	_vertex_meshes.clear()
	_triangle_mesh.clear_surfaces()
	if is_instance_valid(_outline_immediate):
		_outline_immediate.clear_surfaces()


func _update_preview(pos: Vector3, is_snapped: bool, _normal: Vector3) -> void:
	if not is_instance_valid(_preview):
		return
	_preview.global_position = pos
	if is_instance_valid(_preview_material):
		_preview_material.albedo_color = snap_preview_color if is_snapped else preview_color


func _update_beam(target: Vector3) -> void:
	if not is_instance_valid(_beam_immediate):
		return
	_beam_immediate.clear_surfaces()
	if not is_grabbed or not is_instance_valid(grabbing_hand):
		return
	var origin = _tip.global_transform.origin if is_instance_valid(_tip) else global_transform.origin
	_beam_immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	_beam_immediate.surface_add_vertex(origin)
	_beam_immediate.surface_add_vertex(target)
	_beam_immediate.surface_end()


func _update_guide(target: Vector3) -> void:
	if not is_instance_valid(_guide_immediate):
		return
	_guide_immediate.clear_surfaces()
	if not is_grabbed or not is_instance_valid(grabbing_hand):
		return
	_guide_immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	_guide_immediate.surface_add_vertex(global_transform.origin)
	_guide_immediate.surface_add_vertex(target)
	_guide_immediate.surface_end()


func _clear_guide() -> void:
	if _guide_immediate:
		_guide_immediate.clear_surfaces()


func _clear_beam() -> void:
	if _beam_immediate:
		_beam_immediate.clear_surfaces()


func _update_triangle_visuals() -> void:
	if _points.size() < 3:
		_triangle_mesh.clear_surfaces()
		return
	
	var positions: Array[Vector3] = []
	for p in _points:
		positions.append(p.global_position)
	
	var ordered = _order_clockwise(positions)
	var normal = _compute_normal(ordered)
	if normal.length() < 0.0001:
		_triangle_mesh.clear_surfaces()
		if is_instance_valid(_outline_immediate):
			_outline_immediate.clear_surfaces()
		return
	
	_build_triangle_mesh(ordered, normal)
	_build_outline(ordered)


func _order_clockwise(points: Array[Vector3]) -> Array[Vector3]:
	if points.size() != 3:
		return points
	var centroid = (points[0] + points[1] + points[2]) / 3.0
	var normal = _compute_normal(points)
	if normal.length() < 0.0001:
		return points
	normal = normal.normalized()
	
	var abs_normal = normal.abs()
	var drop_axis = 0
	if abs_normal.y >= abs_normal.x and abs_normal.y >= abs_normal.z:
		drop_axis = 1
	elif abs_normal.z >= abs_normal.x and abs_normal.z >= abs_normal.y:
		drop_axis = 2
	
	var projected: Array = []
	for i in points.size():
		var v = points[i] - centroid
		var u := 0.0
		var w := 0.0
		match drop_axis:
			0:
				u = v.y
				w = v.z
			1:
				u = v.x
				w = v.z
			_:
				u = v.x
				w = v.y
		var angle = atan2(w, u)
		projected.append({"index": i, "angle": angle})
	
	var sort_sign = 1.0
	match drop_axis:
		0:
			sort_sign = normal.x
		1:
			sort_sign = normal.y
		_:
			sort_sign = normal.z
	
	projected.sort_custom(func(a, b):
		return a["angle"] > b["angle"] if sort_sign >= 0.0 else a["angle"] < b["angle"]
	)
	
	var ordered: Array[Vector3] = []
	for item in projected:
		ordered.append(points[item["index"]])
	return ordered


func _compute_normal(points: Array[Vector3]) -> Vector3:
	if points.size() < 3:
		return Vector3.ZERO
	
	# Try to find a valid normal using the first valid non-collinear triplet
	var a = points[0]
	var best_normal = Vector3.ZERO
	var max_len_sq = 0.0
	
	# Check multiple triplets to find the best normal (avoids issues if first 3 are collinear)
	for i in range(1, points.size() - 1):
		var b = points[i]
		var c = points[i+1]
		var normal = (b - a).cross(c - a)
		var len_sq = normal.length_squared()
		if len_sq > max_len_sq:
			max_len_sq = len_sq
			best_normal = normal
			
	return best_normal


func _build_triangle_mesh(points: Array[Vector3], normal: Vector3) -> void:
	_triangle_mesh.clear_surfaces()
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	st.set_color(triangle_color)
	st.set_normal(normal.normalized())
	
	# Triangulate using a fan from the first point
	# Since points are ordered clockwise/counter-clockwise, this fills a convex polygon
	for i in range(1, points.size() - 1):
		st.add_vertex(points[0])
		st.add_vertex(points[i])
		st.add_vertex(points[i+1])
		
	# st.index() isn't necessary for immediate rendering unless we want optimization, 
	# and with fan generation we are submitting explicit triangles.
	st.generate_normals() # Optional: regenerate normals if needed, but we set custom normal above
	st.commit(_triangle_mesh)


func _build_outline(points: Array[Vector3]) -> void:
	if not is_instance_valid(_outline_immediate):
		return
	_outline_immediate.clear_surfaces()
	_outline_immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in points.size():
		var a = points[i]
		var b = points[(i + 1) % points.size()]
		_outline_immediate.surface_add_vertex(a)
		_outline_immediate.surface_add_vertex(b)
	_outline_immediate.surface_end()


func _emit_stroke(pos: Vector3) -> void:
	if not is_instance_valid(_stroke_particles):
		return
	_stroke_particles.global_position = pos
	_stroke_particles.restart()


func _make_sphere_mesh(radius: float) -> SphereMesh:
	var mesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	return mesh


func _make_unshaded_material(color: Color) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = false
	return mat
