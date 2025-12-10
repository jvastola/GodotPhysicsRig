class_name PolyTool
extends Grabbable
const ColorPickerUI = preload("res://src/ui/color_picker_ui.gd")

enum ToolMode {
	PLACE,
	EDIT,
	REMOVE,
	CONNECT,
	PAINT
}

enum PointVisibilityMode {
	ALWAYS,
	WHEN_HELD,
	WITHIN_RADIUS,
	HELD_AND_RADIUS
}

# Configuration
@export var snap_radius: float = 0.04
@export var selection_radius: float = 0.05
@export var trigger_threshold: float = 0.5
@export var tip_forward_offset: float = 0.05
@export var max_points: int = 128
@export var point_visibility_mode: PointVisibilityMode = PointVisibilityMode.WITHIN_RADIUS
@export var point_visibility_radius: float = 1.0

# Colors
@export var color_place: Color = Color(0.2, 1.0, 0.4) # Green
@export var color_edit: Color = Color(1.0, 0.9, 0.2) # Yellow
@export var color_remove: Color = Color(1.0, 0.2, 0.2) # Red
@export var color_connect: Color = Color(0.2, 0.6, 1.0) # Blue
@export var color_mesh: Color = Color(0.8, 0.8, 0.8, 0.5)
@export var color_paint_default: Color = Color(1.0, 1.0, 1.0, 1.0)

# State
static var instance: PolyTool
var _current_mode: ToolMode = ToolMode.PLACE
var _points: Array[Node3D] = []
var _triangles: Array[Array] = [] # Array of [i0, i1, i2]
var _controller: Node = null
var _prev_trigger_pressed: bool = false
var _prev_grip_pressed: bool = false
var _drag_index: int = -1

# Connect Mode State
var _connect_sequence: Array[int] = []

# Visuals
var _tip: Node3D
var _orb: MeshInstance3D
var _orb_material: StandardMaterial3D
var _preview_dot: MeshInstance3D
var _preview_mat: StandardMaterial3D
var _point_container: Node3D
var _mesh_instance: MeshInstance3D
var _mesh_params: ArrayMesh
var _connect_line: MeshInstance3D
var _connect_line_immediate: ImmediateMesh
var _paint_dot: MeshInstance3D
var _paint_mat: StandardMaterial3D
var _mode_select_nodes: Array[MeshInstance3D] = []
var _mode_select_modes: Array[ToolMode] = []
var _is_selecting_mode: bool = false
var _mode_select_radius: float = 0.12
var _mode_select_height: float = 0.02
const _MODE_ORDER := [ToolMode.PLACE, ToolMode.EDIT, ToolMode.REMOVE, ToolMode.CONNECT, ToolMode.PAINT]
var _mode_labels: Array[MeshInstance3D] = []

func _ready() -> void:
	instance = self
	super._ready()
	_create_visuals()
	grabbed.connect(_on_grabbed)
	released.connect(_on_released)
	set_physics_process(false)
	_update_point_visibility()

func _create_visuals() -> void:
	_tip = get_node_or_null("Tip")
	
	_point_container = Node3D.new()
	_point_container.name = "PolyToolPoints"
	_add_to_root(_point_container)
	
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "PolyToolMesh"
	_mesh_params = ArrayMesh.new()
	_mesh_instance.mesh = _mesh_params
	var mat = StandardMaterial3D.new()
	# Let vertex colors (including alpha) drive appearance
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED # Show both sides? User wanted winding to matter, so maybe enabled.
	# Actually, user said "clockwise... front face... counter clockwise... other side".
	# If cull is disabled, they see both always. If cull is BACK (default), they only see front.
	# Let's keep default culling so the winding matters visually.
	mat.cull_mode = BaseMaterial3D.CULL_BACK 
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh_instance.material_override = mat
	_add_to_root(_mesh_instance)

	_orb = MeshInstance3D.new()
	_orb.name = "ModeOrb"
	_orb.mesh = _make_sphere_mesh(0.02)
	_orb_material = _make_unshaded_material(color_place)
	_orb.material_override = _orb_material
	_orb.visible = false
	add_child(_orb)
	_orb.position = Vector3(0.05, 0, 0) # Offset relative to tool

	_ensure_preview_dot()
	
	_connect_line = MeshInstance3D.new()
	_connect_line.name = "ConnectLine"
	_connect_line_immediate = ImmediateMesh.new()
	_connect_line.mesh = _connect_line_immediate
	var line_mat = _make_unshaded_material(color_connect)
	_connect_line.material_override = line_mat
	_add_to_root(_connect_line)

	_ensure_paint_dot()

func _exit_tree() -> void:
	super._exit_tree()
	if instance == self:
		instance = null
	if is_instance_valid(_point_container): _point_container.queue_free()
	if is_instance_valid(_mesh_instance): _mesh_instance.queue_free()
	if is_instance_valid(_preview_dot): _preview_dot.queue_free()
	if is_instance_valid(_connect_line): _connect_line.queue_free()
	_clear_mode_select_nodes()

func _on_grabbed(hand: RigidBody3D) -> void:
	_controller = null
	if is_instance_valid(hand) and hand.get("target"):
		_controller = hand.get("target")
	
	set_physics_process(true)
	_orb.visible = true
	_update_mode_visuals()
	_update_point_visibility()
	
	# Initialize input state
	_prev_trigger_pressed = _is_trigger_pressed()
	_prev_grip_pressed = _is_grip_pressed()

func _on_released() -> void:
	set_physics_process(false)
	_controller = null
	_drag_index = -1
	_connect_sequence.clear()
	_orb.visible = false
	if is_instance_valid(_preview_dot):
		_preview_dot.visible = false
	_clear_connect_lines()
	_update_point_visibility()
	_end_mode_select()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_point_visibility()
	_update_paint_dot()
	
	if not is_inside_tree():
		return
	
	if not is_grabbed: 
		return

	_ensure_preview_dot()

	_handle_input()
	
	var target = _get_target_point()
	var hover = _get_nearest_point(target)
	var snapped_pos = target
	
	if hover.index != -1 and hover.distance < snap_radius:
		snapped_pos = hover.position
		
	# Update Visuals
	_preview_dot.global_position = snapped_pos
	_preview_dot.visible = true
	
	# Connect Mode Line Visualization
	if _current_mode == ToolMode.CONNECT and not _connect_sequence.is_empty():
		_update_connect_lines(target)
	else:
		_clear_connect_lines()

func _handle_input() -> void:
	var trigger = _is_trigger_pressed()
	var grip = _is_grip_pressed()
	
	if not is_inside_tree():
		_prev_trigger_pressed = trigger
		_prev_grip_pressed = grip
		return
	
	# Grip: enter/exit radial mode select
	if grip and not _prev_grip_pressed:
		_begin_mode_select()
	elif not grip and _prev_grip_pressed and _is_selecting_mode:
		_commit_mode_select()
	
	# If selecting mode, don't perform other actions
	if _is_selecting_mode:
		_update_mode_select_visuals()
		_prev_trigger_pressed = trigger
		_prev_grip_pressed = grip
		return
	
	# Trigger Actions
	var just_pressed = trigger and not _prev_trigger_pressed
	var _just_released = not trigger and _prev_trigger_pressed
	
	var target = _get_target_point()
	var hover = _get_nearest_point(target)
	
	match _current_mode:
		ToolMode.PLACE:
			if just_pressed and _points.size() < max_points:
				_add_point(target)
				
		ToolMode.EDIT:
			if just_pressed and hover.index != -1 and hover.distance < selection_radius:
				_drag_index = hover.index
			
			if _drag_index != -1:
				if trigger:
					_move_point(_drag_index, target)
				else:
					_drag_index = -1
					
		ToolMode.REMOVE:
			if just_pressed and hover.index != -1 and hover.distance < selection_radius:
				_remove_point(hover.index)
				
		ToolMode.CONNECT:
			if trigger:
				# Collecting points
				if hover.index != -1 and hover.distance < selection_radius:
					# Add to sequence if it's the first point or different from the last one
					if _connect_sequence.is_empty() or _connect_sequence.back() != hover.index:
						# Prevent using the same point twice in a SINGLE triangle
						if not hover.index in _connect_sequence:
							_connect_sequence.append(hover.index)
							# Check if we have 3 points
							if _connect_sequence.size() == 3:
								_add_triangle(_connect_sequence.duplicate())
								_connect_sequence.clear() # Reset for next
			else:
				# Clear sequence on release? 
				# User said "holding the trigger... if they go over 3 points".
				# Implies the sequence is valid only while holding.
				if not _connect_sequence.is_empty():
					_connect_sequence.clear()
		
		ToolMode.PAINT:
			if just_pressed:
				var painted := false
				if hover.index != -1 and hover.distance < selection_radius:
					_set_point_color(hover.index, _get_paint_color())
					painted = true
				else:
					var tri := _find_nearest_triangle(target)
					if tri.has("index") and tri["index"] != -1:
						var tri_indices: Array = _triangles[tri["index"]]
						for v in tri_indices:
							_set_point_color(v, _get_paint_color())
						painted = true
				if painted:
					_rebuild_mesh()

	_prev_trigger_pressed = trigger
	_prev_grip_pressed = grip

func _cycle_mode() -> void:
	var next = (_current_mode + 1) % 5
	_current_mode = next as ToolMode
	_update_mode_visuals()

func _update_mode_visuals() -> void:
	_ensure_preview_dot()
	var color = _mode_color(_current_mode)
	_orb_material.albedo_color = color
	_orb_material.emission = color
	if _preview_mat:
		_preview_mat.albedo_color = color.lightened(0.5)
	_update_paint_dot()

func _add_point(pos: Vector3) -> void:
	var node = Node3D.new()
	node.name = "P%d" % _points.size()
	
	var mesh = MeshInstance3D.new()
	mesh.mesh = _make_sphere_mesh(0.015)
	mesh.material_override = _make_unshaded_material(Color(0.8, 0.8, 0.8))
	node.add_child(mesh)
	
	_point_container.add_child(node)
	node.global_position = pos # Important: set after adding to tree
	_points.append(node)
	_update_point_visibility()

func _remove_point(index: int) -> void:
	if index < 0 or index >= _points.size(): return
	
	# Remove point node
	var node = _points[index]
	_points.remove_at(index)
	node.queue_free()
	
	# Remove triangles using this index
	var new_tris: Array[Array] = []
	for tri in _triangles:
		if index in tri:
			continue # Drop this triangle
		
		# Shift indices for points that shifted
		var new_tri: Array[int] = []
		for p_idx in tri:
			if p_idx > index:
				new_tri.append(p_idx - 1)
			else:
				new_tri.append(p_idx)
		new_tris.append(new_tri)
		
	_triangles = new_tris
	_rebuild_mesh()
	_update_point_visibility()

func _move_point(index: int, pos: Vector3) -> void:
	if index < 0 or index >= _points.size(): return
	_points[index].global_position = pos
	_rebuild_mesh()
	_update_point_visibility()

func _add_triangle(indices: Array) -> void:
	_triangles.append(indices)
	_rebuild_mesh()

func _rebuild_mesh() -> void:
	_mesh_params.clear_surfaces()
	if _triangles.is_empty(): return
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for tri in _triangles:
		var p0 = _points[tri[0]].global_position
		var p1 = _points[tri[1]].global_position
		var p2 = _points[tri[2]].global_position
		
		# Compute normal
		var normal = (p1 - p0).cross(p2 - p0).normalized()
		
		st.set_normal(normal)
		# Add vertices in order
		st.set_color(_get_point_color(_points[tri[0]]))
		st.add_vertex(p0)  
		st.set_color(_get_point_color(_points[tri[1]]))
		st.add_vertex(p1)
		st.set_color(_get_point_color(_points[tri[2]]))
		st.add_vertex(p2)
		
	st.commit(_mesh_params)

# Visualization Helpers
func _update_connect_lines(current_target: Vector3) -> void:
	_connect_line_immediate.clear_surfaces()
	_connect_line_immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	
	for idx in _connect_sequence:
		if idx < _points.size():
			_connect_line_immediate.surface_add_vertex(_points[idx].global_position)
	
	_connect_line_immediate.surface_add_vertex(current_target)
	_connect_line_immediate.surface_end()

func _clear_connect_lines() -> void:
	_connect_line_immediate.clear_surfaces()

# Utility Inputs
func _is_trigger_pressed() -> bool:
	if _controller:
		if _controller.has_method("get_float") and _controller.get_float("trigger") > trigger_threshold: return true
		if _controller.has_method("is_button_pressed") and _controller.is_button_pressed("trigger_click"): return true
	if InputMap.has_action("trigger_click"):
		return Input.is_action_pressed("trigger_click")
	return false

func _is_grip_pressed() -> bool:
	if _controller:
		if _controller.has_method("get_float") and _controller.get_float("grip") > 0.5: return true
		if _controller.has_method("is_button_pressed") and _controller.is_button_pressed("grip_click"): return true
	if InputMap.has_action("grip_click"):
		return Input.is_action_pressed("grip_click")
	return false

func _get_target_point() -> Vector3:
	var t = _tip.global_transform if _tip else global_transform
	return t.origin + (-t.basis.z * tip_forward_offset)

func _get_nearest_point(pos: Vector3) -> Dictionary:
	var best_idx = -1
	var best_dist = INF
	var best_pos = Vector3.ZERO
	for i in _points.size():
		var p = _points[i].global_position
		var d = p.distance_to(pos)
		if d < best_dist:
			best_dist = d
			best_idx = i
			best_pos = p
	return { "index": best_idx, "distance": best_dist, "position": best_pos }


func _find_nearest_triangle(pos: Vector3) -> Dictionary:
	var best_idx := -1
	var best_dist := INF
	for i in _triangles.size():
		var tri = _triangles[i]
		if tri.size() < 3:
			continue
		var p0 = _points[tri[0]].global_position
		var p1 = _points[tri[1]].global_position
		var p2 = _points[tri[2]].global_position
		var plane_normal = (p1 - p0).cross(p2 - p0)
		if plane_normal.length_squared() < 1e-6:
			continue
		var plane = Plane(p0, p1, p2)
		var projected = plane.project(pos)
		var inside = _is_point_in_triangle(projected, p0, p1, p2)
		if not inside:
			continue
		var dist = projected.distance_to(pos)
		if dist < best_dist:
			best_dist = dist
			best_idx = i
	return {"index": best_idx, "distance": best_dist}


func _is_point_in_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var v0 = c - a
	var v1 = b - a
	var v2 = p - a
	var dot00 = v0.dot(v0)
	var dot01 = v0.dot(v1)
	var dot02 = v0.dot(v2)
	var dot11 = v1.dot(v1)
	var dot12 = v1.dot(v2)
	var denom = (dot00 * dot11 - dot01 * dot01)
	if abs(denom) < 1e-6:
		return false
	var inv_denom = 1.0 / denom
	var u = (dot11 * dot02 - dot01 * dot12) * inv_denom
	var v = (dot00 * dot12 - dot01 * dot02) * inv_denom
	return u >= -0.0001 and v >= -0.0001 and (u + v) <= 1.0001

func _update_point_visibility() -> void:
	if not is_instance_valid(_point_container):
		return
	var origin = _get_visibility_origin()
	for point in _points:
		var mesh = _get_point_mesh(point)
		if mesh == null:
			continue
		mesh.visible = _is_point_visible(point.global_position, origin)

func _is_point_visible(point_pos: Vector3, origin: Vector3) -> bool:
	match point_visibility_mode:
		PointVisibilityMode.ALWAYS:
			return true
		PointVisibilityMode.WHEN_HELD:
			return is_grabbed
		PointVisibilityMode.WITHIN_RADIUS:
			return point_pos.distance_to(origin) <= point_visibility_radius
		PointVisibilityMode.HELD_AND_RADIUS:
			return is_grabbed and point_pos.distance_to(origin) <= point_visibility_radius
	return true

func _get_visibility_origin() -> Vector3:
	# Safe origin even if not in tree
	if not is_inside_tree():
		return Vector3.ZERO
	if is_instance_valid(_tip) and _tip.is_inside_tree():
		return _tip.global_transform.origin
	return global_transform.origin

func _get_point_mesh(point: Node3D) -> VisualInstance3D:
	if not is_instance_valid(point):
		return null
	for child in point.get_children():
		if child is VisualInstance3D:
			return child
	return null


func _get_point_color(point: Node3D) -> Color:
	var mesh = _get_point_mesh(point)
	if mesh and mesh.material_override and mesh.material_override is StandardMaterial3D:
		return (mesh.material_override as StandardMaterial3D).albedo_color
	return Color(0.8, 0.8, 0.8)


func _set_point_color(index: int, color: Color) -> void:
	if index < 0 or index >= _points.size():
		return
	var mesh = _get_point_mesh(_points[index])
	if mesh:
		var mat = mesh.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = color


func _get_paint_color() -> Color:
	if ColorPickerUI and ColorPickerUI.instance and is_instance_valid(ColorPickerUI.instance):
		return ColorPickerUI.instance.get_current_color()
	var picker := _find_color_picker()
	if picker:
		return picker.get_current_color()
	return color_paint_default


func _find_color_picker() -> ColorPickerUI:
	if not get_tree():
		return null
	# Prefer group lookup to avoid deep scans
	var node = get_tree().get_first_node_in_group("color_picker_ui")
	if node and node is ColorPickerUI:
		return node
	return null

func _make_sphere_mesh(r: float) -> SphereMesh:
	var m = SphereMesh.new()
	m.radius = r
	m.height = r * 2
	m.radial_segments = 8
	m.rings = 4
	return m

func _make_unshaded_material(c: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func _ensure_preview_dot() -> void:
	if is_instance_valid(_preview_dot):
		return
	_preview_dot = MeshInstance3D.new()
	_preview_dot.name = "PreviewDot"
	_preview_dot.mesh = _make_sphere_mesh(0.015)
	_preview_mat = _make_unshaded_material(Color.WHITE)
	_preview_dot.material_override = _preview_mat
	_preview_dot.visible = false
	_add_to_root(_preview_dot)


func _ensure_paint_dot() -> void:
	if is_instance_valid(_paint_dot):
		return
	_paint_dot = MeshInstance3D.new()
	_paint_dot.name = "PaintDot"
	_paint_dot.mesh = _make_sphere_mesh(0.018)
	_paint_mat = _make_unshaded_material(_get_paint_color())
	_paint_dot.material_override = _paint_mat
	_paint_dot.visible = true
	add_child(_paint_dot)
	_paint_dot.position = Vector3(0.05, 0.03, 0)


func _update_paint_dot() -> void:
	_ensure_paint_dot()
	if not is_instance_valid(_paint_mat):
		return
	var color = _get_paint_color()
	_paint_mat.albedo_color = color
	_paint_mat.emission = color
	# Keep paint dot visible as a legend for current paint color
	_paint_dot.visible = true


func _mode_color(mode: ToolMode) -> Color:
	match mode:
		ToolMode.PLACE:
			return color_place
		ToolMode.EDIT:
			return color_edit
		ToolMode.REMOVE:
			return color_remove
		ToolMode.CONNECT:
			return color_connect
		ToolMode.PAINT:
			return _get_paint_color()
	return Color.WHITE

func _add_to_root(node: Node) -> void:
	var root = get_tree().current_scene
	if not root: root = get_tree().root
	root.add_child(node)


func _begin_mode_select() -> void:
	if not is_inside_tree():
		return
	# Guard against missing root
	if get_tree() == null:
		return
	_clear_mode_select_nodes()
	_is_selecting_mode = true
	# Extra safety: require a valid transform
	if get_tree().root == null:
		return
	if not is_inside_tree():
		return
	var xf := global_transform
	var anchor := _get_visibility_origin()
	var basis := xf.basis
	# Arrange in a forward-facing arc to avoid side dots
	var count := _MODE_ORDER.size()
	for i in count:
		var mode: ToolMode = _MODE_ORDER[i]
		# Spread across -60..60 degrees
		var angle = deg_to_rad(-60.0 + (120.0 * float(i) / max(1.0, float(count - 1))))
		var offset_local = Vector3(sin(angle), 0, -cos(angle)) * _mode_select_radius + Vector3(0, _mode_select_height, 0)
		var pos = anchor + basis * offset_local
		var m := MeshInstance3D.new()
		m.mesh = _make_sphere_mesh(0.01)
		var mat := _make_unshaded_material(_mode_color(mode))
		mat.emission = _mode_color(mode)
		m.material_override = mat
		_mode_select_nodes.append(m)
		_mode_select_modes.append(mode)
		_add_to_root(m)
		m.global_position = pos
		_add_mode_label(mode, pos)
	_update_mode_select_visuals()


func _update_mode_select_visuals() -> void:
	if not _is_selecting_mode:
		return
	var nearest_idx := _nearest_mode_index()
	for i in _mode_select_nodes.size():
		var node = _mode_select_nodes[i]
		if not is_instance_valid(node):
			continue
		var scale := 1.0
		if i == nearest_idx:
			scale = 1.5
		node.scale = Vector3.ONE * scale
	if nearest_idx != -1 and nearest_idx < _mode_select_modes.size():
		var color := _mode_color(_mode_select_modes[nearest_idx])
		_orb_material.albedo_color = color
		_orb_material.emission = color
	for i in _mode_labels.size():
		var lbl = _mode_labels[i]
		if not is_instance_valid(lbl):
			continue
		var tint = Color(1, 1, 1, 1.0) if i == nearest_idx else Color(0.7, 0.7, 0.7, 0.85)
		if lbl.material_override and lbl.material_override is StandardMaterial3D:
			var mat := lbl.material_override as StandardMaterial3D
			mat.albedo_color = tint


func _commit_mode_select() -> void:
	var idx := _nearest_mode_index()
	if idx != -1 and idx < _mode_select_modes.size():
		_current_mode = _mode_select_modes[idx]
	_update_mode_visuals()
	_end_mode_select()


func _end_mode_select() -> void:
	_is_selecting_mode = false
	_clear_mode_select_nodes()


func _clear_mode_select_nodes() -> void:
	for n in _mode_select_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_mode_select_nodes.clear()
	_mode_select_modes.clear()
	_clear_mode_labels()


func _add_mode_label(mode: ToolMode, pos: Vector3) -> void:
	var text_mesh := TextMesh.new()
	text_mesh.text = _mode_name(mode)
	text_mesh.font_size = 48
	text_mesh.pixel_size = 0.0008
	text_mesh.depth = 0.001
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1, 0.95)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	var lbl := MeshInstance3D.new()
	lbl.mesh = text_mesh
	lbl.material_override = mat
	_add_to_root(lbl)
	lbl.global_position = pos + Vector3(0, 0.025, 0)
	lbl.scale = Vector3.ONE * 0.006
	_mode_labels.append(lbl)


func _clear_mode_labels() -> void:
	for l in _mode_labels:
		if is_instance_valid(l):
			l.queue_free()
	_mode_labels.clear()


func _mode_name(mode: ToolMode) -> String:
	match mode:
		ToolMode.PLACE: return "Place"
		ToolMode.EDIT: return "Edit"
		ToolMode.REMOVE: return "Remove"
		ToolMode.CONNECT: return "Connect"
		ToolMode.PAINT: return "Paint"
	return "Mode"


func _nearest_mode_index() -> int:
	if _mode_select_nodes.is_empty():
		return -1
	var tip_pos := _get_visibility_origin()
	var best_idx := -1
	var best_dist := INF
	for i in _mode_select_nodes.size():
		var node = _mode_select_nodes[i]
		if not is_instance_valid(node):
			continue
		var d = node.global_position.distance_to(tip_pos)
		if d < best_dist:
			best_dist = d
			best_idx = i
	return best_idx


func get_point_count() -> int:
	return _points.size()


func get_triangle_count() -> int:
	return _triangles.size()


func get_default_export_path() -> String:
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	return "user://poly_exports/poly_%s.gltf" % timestamp


func export_to_gltf(path: String) -> int:
	# Ensure we have geometry to export
	if not _mesh_params or _mesh_params.get_surface_count() == 0:
		return ERR_CANT_CREATE
	
	# Build a minimal scene with the mesh
	var root := Node3D.new()
	root.name = "PolyToolExport"
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "PolyMesh"
	mesh_instance.mesh = _mesh_params.duplicate()
	if is_instance_valid(_mesh_instance) and _mesh_instance.material_override:
		mesh_instance.material_override = _mesh_instance.material_override
	root.add_child(mesh_instance)
	
	# Prepare target path
	var target_path := path.strip_edges()
	if target_path.is_empty():
		target_path = get_default_export_path()
	var base_dir := target_path.get_base_dir()
	if base_dir != "":
		var abs_dir := ProjectSettings.globalize_path(base_dir)
		DirAccess.make_dir_recursive_absolute(abs_dir)
	
	# Export using GLTFDocument
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var append_err := gltf.append_from_scene(root, state)
	if append_err != OK:
		return append_err
	return gltf.write_to_filesystem(state, target_path)


func load_from_gltf(path: String) -> int:
	var target_path := path.strip_edges()
	if target_path.is_empty():
		return ERR_FILE_NOT_FOUND
	if not target_path.begins_with("res://") and not target_path.begins_with("user://"):
		target_path = "user://poly_exports".path_join(target_path)
	if not FileAccess.file_exists(target_path):
		return ERR_FILE_NOT_FOUND
	
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var append_err := gltf.append_from_file(target_path, state)
	if append_err != OK:
		return append_err
	var scene := gltf.generate_scene(state)
	if not scene:
		return ERR_PARSE_ERROR
	
	var mesh_instance := _find_first_mesh_instance(scene)
	if not mesh_instance or not mesh_instance.mesh:
		return ERR_DOES_NOT_EXIST
	
	var array_mesh := mesh_instance.mesh
	if not (array_mesh is ArrayMesh):
		return ERR_INVALID_DATA
	if array_mesh.get_surface_count() == 0:
		return ERR_INVALID_DATA
	
	var arrays := array_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[ArrayMesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[ArrayMesh.ARRAY_INDEX]
	var colors: PackedColorArray = arrays[ArrayMesh.ARRAY_COLOR]
	if vertices.is_empty():
		return ERR_INVALID_DATA
	if indices.is_empty():
		if vertices.size() % 3 != 0:
			return ERR_INVALID_DATA
		indices = PackedInt32Array()
		for i in range(vertices.size()):
			indices.append(i)
	
	_clear_geometry()
	
	# Recreate points
	for i in vertices.size():
		var node = Node3D.new()
		node.name = "P%d" % i
		var dot = MeshInstance3D.new()
		dot.mesh = _make_sphere_mesh(0.015)
		var color := Color(0.8, 0.8, 0.8)
		if colors.size() == vertices.size():
			color = colors[i]
		dot.material_override = _make_unshaded_material(color)
		node.add_child(dot)
		_point_container.add_child(node)
		node.global_position = vertices[i]
		_points.append(node)
	
	# Recreate triangles
	for t in range(0, indices.size(), 3):
		if t + 2 >= indices.size():
			break
		_triangles.append([indices[t], indices[t + 1], indices[t + 2]])
	
	# Apply material if present
	if mesh_instance.material_override:
		_mesh_instance.material_override = mesh_instance.material_override
	
	_rebuild_mesh()
	_update_point_visibility()
	return OK


func _find_first_mesh_instance(root: Node) -> MeshInstance3D:
	var queue: Array = [root]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh:
			return node as MeshInstance3D
		for child in node.get_children():
			queue.append(child)
	return null


func _clear_geometry() -> void:
	for p in _points:
		if is_instance_valid(p):
			p.queue_free()
	_points.clear()
	_triangles.clear()
	if _mesh_params:
		_mesh_params.clear_surfaces()
