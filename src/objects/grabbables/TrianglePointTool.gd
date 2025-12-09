extends Grabbable
class_name TrianglePointTool

# Placement and snapping
@export var ray_length: float = 5.0
@export var snap_radius: float = 0.05
@export var selection_radius: float = 0.05
@export var edge_dot_spacing: float = 0.08
@export var clear_action: String = "secondary_click"
@export var trigger_threshold: float = 0.5

# Visuals
@export var preview_color: Color = Color(0.3, 1.0, 0.4, 0.6)
@export var snap_preview_color: Color = Color(1.0, 0.5, 0.2, 0.8)
@export var vertex_color: Color = Color(1.0, 0.9, 0.4, 1.0)
@export var edge_dot_color: Color = Color(0.9, 0.9, 1.0, 0.8)
@export var triangle_color: Color = Color(0.2, 0.8, 1.0, 0.25)
@export var triangle_outline_color: Color = Color(0.2, 0.8, 1.0, 0.8)
@export var stroke_color: Color = Color(1.0, 0.6, 0.2, 0.9)
@export var stroke_emission: float = 0.4

var _raycast: RayCast3D
var _preview: MeshInstance3D
var _preview_material: StandardMaterial3D
var _triangle_mesh_instance: MeshInstance3D
var _triangle_mesh: ArrayMesh
var _outline_mesh_instance: MeshInstance3D
var _outline_immediate: ImmediateMesh
var _edge_dots_instance: MultiMeshInstance3D
var _edge_multimesh: MultiMesh
var _edge_dot_mesh: SphereMesh
var _vertex_meshes: Array[MeshInstance3D] = []
var _points: Array[Node3D] = []
var _point_container: Node3D
var _stroke_particles: GPUParticles3D

var _controller: Node = null
var _prev_trigger_pressed: bool = false
var _drag_index: int = -1

const MAX_POINTS := 3


func _ready() -> void:
	super._ready()
	_create_support_nodes()
	
	grabbed.connect(_on_tool_grabbed)
	released.connect(_on_tool_released)
	
	set_physics_process(false)


func _create_support_nodes() -> void:
	_raycast = RayCast3D.new()
	_raycast.name = "TriangleRaycast"
	_raycast.target_position = Vector3(0, 0, -ray_length)
	_raycast.collision_mask = 1
	add_child(_raycast)
	
	_preview = MeshInstance3D.new()
	_preview.name = "PreviewDot"
	_preview.mesh = _make_sphere_mesh(0.015)
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
	
	_edge_dots_instance = MultiMeshInstance3D.new()
	_edge_dots_instance.name = "EdgeDots"
	_edge_dot_mesh = _make_sphere_mesh(0.01)
	_edge_multimesh = MultiMesh.new()
	_edge_multimesh.mesh = _edge_dot_mesh
	_edge_multimesh.use_colors = true
	_edge_dots_instance.multimesh = _edge_multimesh
	_edge_dots_instance.material_override = _make_unshaded_material(edge_dot_color)
	
	_ensure_point_container()
	_add_to_root(_preview)
	_add_to_root(_triangle_mesh_instance)
	_add_to_root(_outline_mesh_instance)
	_add_to_root(_edge_dots_instance)
	_create_stroke_particles()


func _ensure_point_container() -> void:
	if is_instance_valid(_point_container):
		return
	_point_container = Node3D.new()
	_point_container.name = "TrianglePointToolPoints"
	_add_to_root(_point_container)


func _add_to_root(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var root = get_tree().root
	if root and not node.is_inside_tree():
		root.call_deferred("add_child", node)


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


func _on_tool_grabbed(hand: RigidBody3D) -> void:
	_controller = null
	if is_instance_valid(hand) and hand.has_method("get"):
		var maybe_target = hand.get("target")
		if maybe_target and maybe_target is Node:
			_controller = maybe_target
	
	_prev_trigger_pressed = false
	_drag_index = -1
	set_physics_process(true)
	_preview.visible = true


func _on_tool_released() -> void:
	set_physics_process(false)
	_controller = null
	_prev_trigger_pressed = false
	_drag_index = -1
	_preview.visible = false


func _physics_process(_delta: float) -> void:
	if not is_grabbed or not is_instance_valid(grabbing_hand):
		_preview.visible = false
		return
	
	_preview.visible = true
	_raycast.target_position = Vector3(0, 0, -ray_length)
	_raycast.force_raycast_update()
	
	var target_point = _get_target_point()
	var hover = _get_nearest_point(target_point)
	var snapped_point = target_point
	var snapped_to_existing = false
	
	if hover["index"] != -1 and hover["distance"] <= snap_radius:
		snapped_point = hover["position"]
		snapped_to_existing = true
	
	_update_preview(snapped_point, snapped_to_existing)
	_handle_trigger(snapped_point, hover)
	_handle_clear()


func _handle_trigger(snapped_point: Vector3, hover: Dictionary) -> void:
	var trigger_pressed = _is_trigger_pressed()
	var trigger_just_pressed = trigger_pressed and not _prev_trigger_pressed
	var trigger_just_released = not trigger_pressed and _prev_trigger_pressed
	
	if trigger_just_pressed:
		if hover["index"] != -1 and hover["distance"] <= selection_radius:
			_drag_index = hover["index"]
		elif _points.size() < MAX_POINTS:
			_add_point(snapped_point)
			_update_triangle_visuals()
	
	if _drag_index != -1 and trigger_pressed:
		_move_point(_drag_index, snapped_point)
		_update_triangle_visuals()
	elif _drag_index != -1 and trigger_just_released:
		_drag_index = -1
	
	_prev_trigger_pressed = trigger_pressed


func _handle_clear() -> void:
	if clear_action.is_empty():
		return
	if InputMap.has_action(clear_action) and Input.is_action_just_pressed(clear_action):
		_clear_points()


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


func _get_target_point() -> Vector3:
	if _raycast.is_colliding():
		return _raycast.get_collision_point()
	return _raycast.to_global(Vector3(0, 0, -ray_length))


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
	holder.global_position = pos
	
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = _make_sphere_mesh(0.018)
	mesh_instance.material_override = _make_unshaded_material(vertex_color)
	holder.add_child(mesh_instance)
	
	_point_container.add_child(holder)
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
	if is_instance_valid(_edge_multimesh):
		_edge_multimesh.instance_count = 0


func _update_preview(pos: Vector3, snapped: bool) -> void:
	if not is_instance_valid(_preview):
		return
	_preview.global_position = pos
	if is_instance_valid(_preview_material):
		_preview_material.albedo_color = snap_preview_color if snapped else preview_color


func _update_triangle_visuals() -> void:
	if _points.size() < 3:
		_triangle_mesh.clear_surfaces()
		if is_instance_valid(_edge_multimesh):
			_edge_multimesh.instance_count = 0
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
		_edge_multimesh.instance_count = 0
		return
	
	_build_triangle_mesh(ordered, normal)
	_build_outline(ordered)
	_build_edge_dots(ordered, normal)


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
	
	var sign = 1.0
	match drop_axis:
		0:
			sign = normal.x
		1:
			sign = normal.y
		_:
			sign = normal.z
	
	projected.sort_custom(func(a, b):
		return a["angle"] > b["angle"] if sign >= 0.0 else a["angle"] < b["angle"]
	)
	
	var ordered: Array[Vector3] = []
	for item in projected:
		ordered.append(points[item["index"]])
	return ordered


func _compute_normal(points: Array[Vector3]) -> Vector3:
	if points.size() < 3:
		return Vector3.ZERO
	var a = points[0]
	var b = points[1]
	var c = points[2]
	return (b - a).cross(c - a)


func _build_triangle_mesh(points: Array[Vector3], normal: Vector3) -> void:
	_triangle_mesh.clear_surfaces()
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	st.set_color(triangle_color)
	st.set_normal(normal.normalized())
	
	for p in points:
		st.add_vertex(p)
	st.index()
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


func _build_edge_dots(points: Array[Vector3], normal: Vector3) -> void:
	if not is_instance_valid(_edge_multimesh):
		return
	var transforms: Array[Transform3D] = []
	
	for i in points.size():
		var a = points[i]
		var b = points[(i + 1) % points.size()]
		var edge_vec = b - a
		var length = edge_vec.length()
		if length < 0.001:
			continue
		var dir = edge_vec / length
		var steps = max(1, int(floor(length / edge_dot_spacing)))
		for s in range(1, steps):
			var t = float(s) / float(steps)
			var pos = a + dir * (length * t)
			var basis = Basis()
			basis = basis.looking_at(dir, normal)
			transforms.append(Transform3D(basis, pos))
	
	_edge_multimesh.mesh = _edge_dot_mesh
	_edge_multimesh.instance_count = transforms.size()
	
	for i in transforms.size():
		_edge_multimesh.set_instance_transform(i, transforms[i])
		_edge_multimesh.set_instance_color(i, edge_dot_color)


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
