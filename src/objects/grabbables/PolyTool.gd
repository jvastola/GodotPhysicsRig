extends Grabbable
class_name PolyTool

enum ToolMode {
	PLACE,
	EDIT,
	REMOVE,
	CONNECT
}

# Configuration
@export var snap_radius: float = 0.04
@export var selection_radius: float = 0.05
@export var trigger_threshold: float = 0.5
@export var tip_forward_offset: float = 0.05
@export var max_points: int = 128

# Colors
@export var color_place: Color = Color(0.2, 1.0, 0.4) # Green
@export var color_edit: Color = Color(1.0, 0.9, 0.2) # Yellow
@export var color_remove: Color = Color(1.0, 0.2, 0.2) # Red
@export var color_connect: Color = Color(0.2, 0.6, 1.0) # Blue
@export var color_mesh: Color = Color(0.8, 0.8, 0.8, 0.5)

# State
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

func _ready() -> void:
	super._ready()
	_create_visuals()
	grabbed.connect(_on_grabbed)
	released.connect(_on_released)
	set_physics_process(false)

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
	mat.albedo_color = color_mesh
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED # Show both sides? User wanted winding to matter, so maybe enabled.
	# Actually, user said "clockwise... front face... counter clockwise... other side".
	# If cull is disabled, they see both always. If cull is BACK (default), they only see front.
	# Let's keep default culling so the winding matters visually.
	mat.cull_mode = BaseMaterial3D.CULL_BACK 
	mat.vertex_color_use_as_albedo = false
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

	_preview_dot = MeshInstance3D.new()
	_preview_dot.name = "PreviewDot"
	_preview_dot.mesh = _make_sphere_mesh(0.015)
	_preview_mat = _make_unshaded_material(Color.WHITE)
	_preview_dot.material_override = _preview_mat
	_preview_dot.visible = false
	_add_to_root(_preview_dot)
	
	_connect_line = MeshInstance3D.new()
	_connect_line.name = "ConnectLine"
	_connect_line_immediate = ImmediateMesh.new()
	_connect_line.mesh = _connect_line_immediate
	var line_mat = _make_unshaded_material(color_connect)
	_connect_line.material_override = line_mat
	_add_to_root(_connect_line)

func _exit_tree() -> void:
	super._exit_tree()
	if is_instance_valid(_point_container): _point_container.queue_free()
	if is_instance_valid(_mesh_instance): _mesh_instance.queue_free()
	if is_instance_valid(_preview_dot): _preview_dot.queue_free()
	if is_instance_valid(_connect_line): _connect_line.queue_free()

func _on_grabbed(hand: RigidBody3D) -> void:
	_controller = null
	if is_instance_valid(hand) and hand.get("target"):
		_controller = hand.get("target")
	
	set_physics_process(true)
	_orb.visible = true
	_update_mode_visuals()
	
	# Initialize input state
	_prev_trigger_pressed = _is_trigger_pressed()
	_prev_grip_pressed = _is_grip_pressed()

func _on_released() -> void:
	set_physics_process(false)
	_controller = null
	_drag_index = -1
	_connect_sequence.clear()
	_orb.visible = false
	_preview_dot.visible = false
	_clear_connect_lines()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	if not is_grabbed: 
		return

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
	
	# Grip Cycle Mode
	if grip and not _prev_grip_pressed:
		_cycle_mode()
	
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

	_prev_trigger_pressed = trigger
	_prev_grip_pressed = grip

func _cycle_mode() -> void:
	var next = (_current_mode + 1) % 4
	_current_mode = next as ToolMode
	_update_mode_visuals()

func _update_mode_visuals() -> void:
	var color = Color.WHITE
	match _current_mode:
		ToolMode.PLACE: color = color_place
		ToolMode.EDIT: color = color_edit
		ToolMode.REMOVE: color = color_remove
		ToolMode.CONNECT: color = color_connect
	
	_orb_material.albedo_color = color
	_orb_material.emission = color
	_preview_mat.albedo_color = color.lightened(0.5)

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

func _move_point(index: int, pos: Vector3) -> void:
	if index < 0 or index >= _points.size(): return
	_points[index].global_position = pos
	_rebuild_mesh()

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
		st.add_vertex(p0)  
		st.add_vertex(p1)
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

func _add_to_root(node: Node) -> void:
	var root = get_tree().current_scene
	if not root: root = get_tree().root
	root.add_child(node)
