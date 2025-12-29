class_name PolyTool
extends Grabbable
const ToolPoolManager = preload("res://src/systems/tool_pool_manager.gd")
const ColorPickerUI = preload("res://src/ui/color_picker_ui.gd")
const MaterialPickerUI = preload("res://src/ui/material_picker_ui.gd")

enum ToolMode {
	PLACE,
	EDIT,
	REMOVE,
	CONNECT,
	PAINT,
	APPLY_MATERIAL
}

enum PointVisibilityMode {
	ALWAYS,
	WHEN_HELD,
	WITHIN_RADIUS,
	HELD_AND_RADIUS
}

enum EditSelectionType {
	POINT,
	EDGE,
	FACE
}

# Configuration
@export var snap_radius: float = 0.04
@export var selection_radius: float = 0.05
@export var trigger_threshold: float = 0.5
@export var tip_forward_offset: float = 0.05
@export var max_points: int = 128
@export var point_visibility_mode: PointVisibilityMode = PointVisibilityMode.WITHIN_RADIUS
@export var point_visibility_radius: float = 1.0
@export var edge_selection_radius: float = 0.03
@export var face_selection_radius: float = 0.1
@export var merge_overlapping_points: bool = true
@export var merge_distance: float = 0.001

# Colors
@export var color_place: Color = Color(0.2, 1.0, 0.4) # Green
@export var color_edit: Color = Color(1.0, 0.9, 0.2) # Yellow
@export var color_remove: Color = Color(1.0, 0.2, 0.2) # Red
@export var color_connect: Color = Color(0.2, 0.6, 1.0) # Blue
@export var color_mesh: Color = Color(0.8, 0.8, 0.8, 0.5)
@export var color_paint_default: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var color_edge_highlight: Color = Color(1.0, 0.6, 0.0, 1.0) # Orange for edges
@export var color_face_highlight: Color = Color(1.0, 0.9, 0.2, 0.4) # Semi-transparent yellow for faces
@export var color_apply_material: Color = Color(0.8, 0.2, 0.8) # Purple for apply material mode

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

# Edit Mode State
var _edit_selection_type: EditSelectionType = EditSelectionType.POINT
var _hovered_edge: Array[int] = [] # [point_idx_a, point_idx_b]
var _hovered_face_idx: int = -1
var _drag_edge: Array[int] = []
var _drag_face_idx: int = -1
var _drag_start_positions: Array[Vector3] = [] # Positions relative to grab point
var _drag_grab_point: Vector3 = Vector3.ZERO # Where the user initially grabbed
var _drag_point_indices: Array[int] = [] # All point indices being dragged (including colocated)
var _drag_start_basis: Basis = Basis.IDENTITY # Tool rotation when drag started

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
var _edge_highlight: MeshInstance3D
var _edge_highlight_mesh: ImmediateMesh
var _face_highlight: MeshInstance3D
var _face_highlight_mesh: ImmediateMesh
var _mode_select_nodes: Array[MeshInstance3D] = []
var _mode_select_modes: Array[ToolMode] = []
var _is_selecting_mode: bool = false
var _mode_select_radius: float = 0.12
var _mode_select_height: float = 0.02
const _MODE_ORDER := [ToolMode.PLACE, ToolMode.EDIT, ToolMode.REMOVE, ToolMode.CONNECT, ToolMode.PAINT, ToolMode.APPLY_MATERIAL]
var _mode_labels: Array[MeshInstance3D] = []
const POOL_TYPE := "poly_tool"

# Material mode state
var _applied_material: Material = null
var _material_preview_dot: MeshInstance3D
var _material_preview_mat: StandardMaterial3D

func _ready() -> void:
	instance = self
	var pool := ToolPoolManager.find()
	if pool:
		pool.register_instance(POOL_TYPE, self)
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
	_create_edit_highlights()

func _exit_tree() -> void:
	super._exit_tree()
	if instance == self:
		instance = null
	if is_instance_valid(_point_container): _point_container.queue_free()
	if is_instance_valid(_mesh_instance): _mesh_instance.queue_free()
	if is_instance_valid(_preview_dot): _preview_dot.queue_free()
	if is_instance_valid(_connect_line): _connect_line.queue_free()
	if is_instance_valid(_edge_highlight): _edge_highlight.queue_free()
	if is_instance_valid(_face_highlight): _face_highlight.queue_free()
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
	_drag_edge.clear()
	_drag_face_idx = -1
	_drag_start_positions.clear()
	_drag_point_indices.clear()
	_drag_grab_point = Vector3.ZERO
	_drag_start_basis = Basis.IDENTITY
	_hovered_edge.clear()
	_hovered_face_idx = -1
	_connect_sequence.clear()
	_orb.visible = false
	if is_instance_valid(_preview_dot):
		_preview_dot.visible = false
	_clear_connect_lines()
	_clear_edit_highlights()
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
	
	# Edit Mode Highlights
	if _current_mode == ToolMode.EDIT:
		_update_edit_mode_highlights(target)
	else:
		_clear_edit_highlights()

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
			if just_pressed:
				_start_edit_drag(target, hover)
			
			if trigger:
				_continue_edit_drag(target)
			else:
				_end_edit_drag()
					
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
		
		ToolMode.APPLY_MATERIAL:
			if just_pressed:
				_apply_selected_material()

	_prev_trigger_pressed = trigger
	_prev_grip_pressed = grip

func _cycle_mode() -> void:
	var next = (_current_mode + 1) % 6
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
	_update_material_preview_dot()

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
	_move_point_with_colocated(index, pos)

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
		
		# Generate UVs using planar projection based on dominant axis
		var uv0 = _calculate_planar_uv(p0, normal)
		var uv1 = _calculate_planar_uv(p1, normal)
		var uv2 = _calculate_planar_uv(p2, normal)
		
		st.set_normal(normal)
		# Add vertices in order with UVs
		st.set_color(_get_point_color(_points[tri[0]]))
		st.set_uv(uv0)
		st.add_vertex(p0)  
		st.set_color(_get_point_color(_points[tri[1]]))
		st.set_uv(uv1)
		st.add_vertex(p1)
		st.set_color(_get_point_color(_points[tri[2]]))
		st.set_uv(uv2)
		st.add_vertex(p2)
		
	st.commit(_mesh_params)


## UV scale for texture mapping (units per UV repeat)
@export var uv_scale: float = 1.0


func _calculate_planar_uv(pos: Vector3, normal: Vector3) -> Vector2:
	# Use planar projection based on the dominant axis of the normal
	var abs_normal = normal.abs()
	var uv: Vector2
	
	if abs_normal.x >= abs_normal.y and abs_normal.x >= abs_normal.z:
		# Project onto YZ plane (X is dominant)
		uv = Vector2(pos.z, pos.y)
	elif abs_normal.y >= abs_normal.x and abs_normal.y >= abs_normal.z:
		# Project onto XZ plane (Y is dominant) - typical for floors/ceilings
		uv = Vector2(pos.x, pos.z)
	else:
		# Project onto XY plane (Z is dominant)
		uv = Vector2(pos.x, pos.y)
	
	return uv / uv_scale

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


# Edit Mode Helpers
func _create_edit_highlights() -> void:
	# Edge highlight line
	_edge_highlight = MeshInstance3D.new()
	_edge_highlight.name = "EdgeHighlight"
	_edge_highlight_mesh = ImmediateMesh.new()
	_edge_highlight.mesh = _edge_highlight_mesh
	var edge_mat = _make_unshaded_material(color_edge_highlight)
	edge_mat.no_depth_test = true
	_edge_highlight.material_override = edge_mat
	_edge_highlight.visible = false
	_add_to_root(_edge_highlight)
	
	# Face highlight
	_face_highlight = MeshInstance3D.new()
	_face_highlight.name = "FaceHighlight"
	_face_highlight_mesh = ImmediateMesh.new()
	_face_highlight.mesh = _face_highlight_mesh
	var face_mat = _make_unshaded_material(color_face_highlight)
	face_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	face_mat.no_depth_test = true
	_face_highlight.material_override = face_mat
	_face_highlight.visible = false
	_add_to_root(_face_highlight)


func _update_edit_mode_highlights(target: Vector3) -> void:
	# Skip if currently dragging
	if _drag_index != -1 or not _drag_edge.is_empty() or _drag_face_idx != -1:
		return
	
	var origin = _get_visibility_origin()
	
	# Find nearest point, edge, and face within visibility radius
	var nearest_point = _get_nearest_point(target)
	var nearest_edge = _get_nearest_edge_within_radius(target, origin)
	var nearest_face = _get_nearest_face_within_radius(target, origin)
	
	# Determine what to highlight based on proximity
	_hovered_edge.clear()
	_hovered_face_idx = -1
	_edit_selection_type = EditSelectionType.POINT
	
	var point_dist = nearest_point.distance if nearest_point.index != -1 else INF
	var edge_dist = nearest_edge.distance if not nearest_edge.edge.is_empty() else INF
	var face_dist = nearest_face.distance if nearest_face.index != -1 else INF
	
	# Priority: point < edge < face (closest wins, with type preference for ties)
	if point_dist < selection_radius and point_dist <= edge_dist and point_dist <= face_dist:
		_edit_selection_type = EditSelectionType.POINT
		_clear_edit_highlights()
	elif edge_dist < edge_selection_radius and edge_dist <= face_dist:
		_edit_selection_type = EditSelectionType.EDGE
		_hovered_edge = nearest_edge.edge
		_draw_edge_highlight(_hovered_edge)
		_clear_face_highlight()
	elif face_dist < face_selection_radius:
		_edit_selection_type = EditSelectionType.FACE
		_hovered_face_idx = nearest_face.index
		_draw_face_highlight(_hovered_face_idx)
		_clear_edge_highlight()
	else:
		_clear_edit_highlights()


func _get_nearest_edge_within_radius(target: Vector3, origin: Vector3) -> Dictionary:
	var best_edge: Array[int] = []
	var best_dist := INF
	var best_point := Vector3.ZERO
	
	# Build unique edges from triangles
	var edges := _get_unique_edges()
	
	for edge in edges:
		if edge.size() < 2:
			continue
		var p0 = _points[edge[0]].global_position
		var p1 = _points[edge[1]].global_position
		
		# Check if edge is within visibility radius
		var edge_center = (p0 + p1) * 0.5
		if edge_center.distance_to(origin) > point_visibility_radius:
			continue
		
		# Find closest point on edge to target
		var closest = _closest_point_on_segment(target, p0, p1)
		var dist = closest.distance_to(target)
		
		if dist < best_dist:
			best_dist = dist
			best_edge = edge
			best_point = closest
	
	return {"edge": best_edge, "distance": best_dist, "position": best_point}


func _get_nearest_face_within_radius(target: Vector3, origin: Vector3) -> Dictionary:
	var best_idx := -1
	var best_dist := INF
	
	for i in _triangles.size():
		var tri = _triangles[i]
		if tri.size() < 3:
			continue
		var p0 = _points[tri[0]].global_position
		var p1 = _points[tri[1]].global_position
		var p2 = _points[tri[2]].global_position
		
		# Check if face center is within visibility radius
		var center = (p0 + p1 + p2) / 3.0
		if center.distance_to(origin) > point_visibility_radius:
			continue
		
		# Project target onto plane and check if inside triangle
		var plane_normal = (p1 - p0).cross(p2 - p0)
		if plane_normal.length_squared() < 1e-6:
			continue
		var plane = Plane(p0, p1, p2)
		var projected = plane.project(target)
		
		if not _is_point_in_triangle(projected, p0, p1, p2):
			continue
		
		var dist = projected.distance_to(target)
		if dist < best_dist:
			best_dist = dist
			best_idx = i
	
	return {"index": best_idx, "distance": best_dist}


func _get_unique_edges() -> Array[Array]:
	var edge_set := {}
	var edges: Array[Array] = []
	
	for tri in _triangles:
		if tri.size() < 3:
			continue
		# Add 3 edges per triangle
		var tri_edges = [
			[tri[0], tri[1]],
			[tri[1], tri[2]],
			[tri[2], tri[0]]
		]
		for e in tri_edges:
			# Normalize edge order for deduplication
			var key = [mini(e[0], e[1]), maxi(e[0], e[1])]
			var key_str = "%d_%d" % [key[0], key[1]]
			if not edge_set.has(key_str):
				edge_set[key_str] = true
				var typed_edge: Array[int] = [key[0], key[1]]
				edges.append(typed_edge)
	
	return edges


func _closest_point_on_segment(point: Vector3, seg_start: Vector3, seg_end: Vector3) -> Vector3:
	var seg = seg_end - seg_start
	var seg_len_sq = seg.length_squared()
	if seg_len_sq < 1e-6:
		return seg_start
	var t = clampf((point - seg_start).dot(seg) / seg_len_sq, 0.0, 1.0)
	return seg_start + seg * t


func _draw_edge_highlight(edge: Array[int]) -> void:
	if edge.size() < 2:
		_clear_edge_highlight()
		return
	if edge[0] >= _points.size() or edge[1] >= _points.size():
		_clear_edge_highlight()
		return
	
	_edge_highlight_mesh.clear_surfaces()
	_edge_highlight_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_edge_highlight_mesh.surface_add_vertex(_points[edge[0]].global_position)
	_edge_highlight_mesh.surface_add_vertex(_points[edge[1]].global_position)
	_edge_highlight_mesh.surface_end()
	_edge_highlight.visible = true


func _draw_face_highlight(face_idx: int) -> void:
	if face_idx < 0 or face_idx >= _triangles.size():
		_clear_face_highlight()
		return
	
	var tri = _triangles[face_idx]
	if tri.size() < 3:
		_clear_face_highlight()
		return
	
	var p0 = _points[tri[0]].global_position
	var p1 = _points[tri[1]].global_position
	var p2 = _points[tri[2]].global_position
	
	_face_highlight_mesh.clear_surfaces()
	_face_highlight_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_face_highlight_mesh.surface_add_vertex(p0)
	_face_highlight_mesh.surface_add_vertex(p1)
	_face_highlight_mesh.surface_add_vertex(p2)
	_face_highlight_mesh.surface_end()
	_face_highlight.visible = true


func _clear_edge_highlight() -> void:
	if is_instance_valid(_edge_highlight_mesh):
		_edge_highlight_mesh.clear_surfaces()
	if is_instance_valid(_edge_highlight):
		_edge_highlight.visible = false


func _clear_face_highlight() -> void:
	if is_instance_valid(_face_highlight_mesh):
		_face_highlight_mesh.clear_surfaces()
	if is_instance_valid(_face_highlight):
		_face_highlight.visible = false


func _clear_edit_highlights() -> void:
	_clear_edge_highlight()
	_clear_face_highlight()


func _start_edit_drag(target: Vector3, hover: Dictionary) -> void:
	_drag_grab_point = target
	_drag_start_basis = _get_tool_basis()
	_drag_point_indices.clear()
	_drag_start_positions.clear()
	
	# Check what we're hovering based on current selection type
	match _edit_selection_type:
		EditSelectionType.POINT:
			if hover.index != -1 and hover.distance < selection_radius:
				_drag_index = hover.index
				# Collect this point and all colocated points
				if merge_overlapping_points:
					_drag_point_indices = _get_colocated_points(hover.index)
				else:
					_drag_point_indices = [hover.index]
				# Store positions relative to grab point
				for idx in _drag_point_indices:
					var relative_pos = _points[idx].global_position - _drag_grab_point
					_drag_start_positions.append(relative_pos)
		
		EditSelectionType.EDGE:
			if not _hovered_edge.is_empty():
				_drag_edge = _hovered_edge.duplicate()
				# Collect all points on the edge and their colocated points
				var indices_set := {}
				for idx in _drag_edge:
					if merge_overlapping_points:
						for colocated_idx in _get_colocated_points(idx):
							indices_set[colocated_idx] = true
					else:
						indices_set[idx] = true
				for idx in indices_set.keys():
					_drag_point_indices.append(idx)
					# Store positions relative to grab point
					var relative_pos = _points[idx].global_position - _drag_grab_point
					_drag_start_positions.append(relative_pos)
		
		EditSelectionType.FACE:
			if _hovered_face_idx != -1:
				_drag_face_idx = _hovered_face_idx
				var tri = _triangles[_drag_face_idx]
				# Collect all points on the face and their colocated points
				var indices_set := {}
				for idx in tri:
					if merge_overlapping_points:
						for colocated_idx in _get_colocated_points(idx):
							indices_set[colocated_idx] = true
					else:
						indices_set[idx] = true
				for idx in indices_set.keys():
					_drag_point_indices.append(idx)
					# Store positions relative to grab point
					var relative_pos = _points[idx].global_position - _drag_grab_point
					_drag_start_positions.append(relative_pos)


func _continue_edit_drag(target: Vector3) -> void:
	if _drag_point_indices.is_empty():
		return
	
	# Get current tool basis and calculate rotation delta
	var current_basis = _get_tool_basis()
	var rotation_delta = current_basis * _drag_start_basis.inverse()
	
	# For points, just translate (no rotation)
	# For edges and faces, apply rotation around the grab point
	var apply_rotation = (_drag_index == -1) and (not _drag_edge.is_empty() or _drag_face_idx != -1)
	
	# Move all tracked points
	for i in _drag_point_indices.size():
		var idx = _drag_point_indices[i]
		var relative_pos = _drag_start_positions[i]
		
		if apply_rotation:
			# Rotate the relative position, then translate to new grab point
			relative_pos = rotation_delta * relative_pos
		
		var new_pos = target + relative_pos
		_points[idx].global_position = new_pos
	
	_rebuild_mesh()
	_update_point_visibility()
	
	# Update highlights while dragging
	if not _drag_edge.is_empty():
		_draw_edge_highlight(_drag_edge)
	elif _drag_face_idx != -1:
		_draw_face_highlight(_drag_face_idx)


func _end_edit_drag() -> void:
	_drag_index = -1
	_drag_edge.clear()
	_drag_face_idx = -1
	_drag_start_positions.clear()
	_drag_point_indices.clear()
	_drag_grab_point = Vector3.ZERO
	_drag_start_basis = Basis.IDENTITY


func _get_tool_basis() -> Basis:
	if is_instance_valid(_tip) and _tip.is_inside_tree():
		return _tip.global_transform.basis
	if is_inside_tree():
		return global_transform.basis
	return Basis.IDENTITY


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


# Material picker functions
func _get_selected_material() -> Material:
	if MaterialPickerUI and MaterialPickerUI.instance and is_instance_valid(MaterialPickerUI.instance):
		return MaterialPickerUI.instance.get_current_material()
	var picker := _find_material_picker()
	if picker:
		return picker.get_current_material()
	return null


func _find_material_picker() -> MaterialPickerUI:
	if not get_tree():
		return null
	var node = get_tree().get_first_node_in_group("material_picker_ui")
	if node and node is MaterialPickerUI:
		return node
	return null


# Viewport for rendering shader materials to texture
var _shader_viewport: SubViewport = null
var _shader_color_rect: ColorRect = null
var _shader_viewport_texture: ViewportTexture = null


func _apply_selected_material() -> void:
	var mat := _get_selected_material()
	if mat == null:
		return
	
	# Check if it's a shader material (like plasma) - needs special handling
	if mat is ShaderMaterial:
		_apply_shader_material(mat as ShaderMaterial)
		return
	
	_applied_material = mat.duplicate()
	
	# Configure material for polygon mesh
	if _applied_material is StandardMaterial3D:
		var std_mat := _applied_material as StandardMaterial3D
		std_mat.vertex_color_use_as_albedo = false
		std_mat.cull_mode = BaseMaterial3D.CULL_BACK
		# Enable triplanar mapping for better texture projection on arbitrary geometry
		std_mat.uv1_triplanar = true
		std_mat.uv1_world_triplanar = true
		std_mat.uv1_triplanar_sharpness = 1.0
		# Scale the texture appropriately
		std_mat.uv1_scale = Vector3(1.0, 1.0, 1.0)
	
	if is_instance_valid(_mesh_instance):
		_mesh_instance.material_override = _applied_material
	
	_update_material_preview_dot()


func _apply_shader_material(shader_mat: ShaderMaterial) -> void:
	# Create a viewport to render the shader to a texture
	_ensure_shader_viewport()
	
	# Apply the shader material to the color rect in the viewport
	_shader_color_rect.material = shader_mat.duplicate()
	
	# Create a StandardMaterial3D that uses the viewport texture
	var std_mat := StandardMaterial3D.new()
	std_mat.albedo_texture = _shader_viewport_texture
	std_mat.vertex_color_use_as_albedo = false
	std_mat.cull_mode = BaseMaterial3D.CULL_BACK
	std_mat.uv1_triplanar = true
	std_mat.uv1_world_triplanar = true
	std_mat.uv1_triplanar_sharpness = 1.0
	std_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	_applied_material = std_mat
	
	if is_instance_valid(_mesh_instance):
		_mesh_instance.material_override = _applied_material
	
	_update_material_preview_dot()


func _ensure_shader_viewport() -> void:
	if is_instance_valid(_shader_viewport):
		return
	
	# Create viewport for rendering shader materials
	_shader_viewport = SubViewport.new()
	_shader_viewport.name = "ShaderMaterialViewport"
	_shader_viewport.size = Vector2i(512, 512)
	_shader_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_shader_viewport.transparent_bg = false
	
	# Create color rect to render the shader
	_shader_color_rect = ColorRect.new()
	_shader_color_rect.name = "ShaderRect"
	_shader_color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shader_color_rect.size = Vector2(512, 512)
	_shader_viewport.add_child(_shader_color_rect)
	
	# Add viewport to scene
	_add_to_root(_shader_viewport)
	
	# Get the viewport texture
	_shader_viewport_texture = _shader_viewport.get_texture()


func _update_material_preview_dot() -> void:
	_ensure_material_preview_dot()
	if not is_instance_valid(_material_preview_dot):
		return
	
	var mat := _get_selected_material()
	if mat:
		if mat is ShaderMaterial:
			# For shader materials, use the converted material if available
			if _applied_material:
				_material_preview_dot.material_override = _applied_material
			else:
				# Create a quick preview material
				_ensure_shader_viewport()
				_shader_color_rect.material = mat.duplicate()
				var preview_mat := StandardMaterial3D.new()
				preview_mat.albedo_texture = _shader_viewport_texture
				preview_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				_material_preview_dot.material_override = preview_mat
		else:
			# For standard materials, apply with triplanar for the sphere
			var preview_mat = mat.duplicate()
			if preview_mat is StandardMaterial3D:
				preview_mat.uv1_triplanar = true
				preview_mat.uv1_world_triplanar = true
			_material_preview_dot.material_override = preview_mat
		_material_preview_dot.visible = true
	else:
		_material_preview_dot.visible = false


func _ensure_material_preview_dot() -> void:
	if is_instance_valid(_material_preview_dot):
		return
	_material_preview_dot = MeshInstance3D.new()
	_material_preview_dot.name = "MaterialPreviewDot"
	_material_preview_dot.mesh = _make_sphere_mesh(0.018)
	_material_preview_dot.visible = false
	add_child(_material_preview_dot)
	_material_preview_dot.position = Vector3(0.05, -0.03, 0)


func get_applied_material() -> Material:
	return _applied_material


func clear_applied_material() -> void:
	_applied_material = null
	if is_instance_valid(_mesh_instance):
		# Restore default vertex color material
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1, 1, 1, 1)
		mat.cull_mode = BaseMaterial3D.CULL_BACK
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mesh_instance.material_override = mat

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
		ToolMode.APPLY_MATERIAL:
			return color_apply_material
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
		ToolMode.APPLY_MATERIAL: return "Material"
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


# Manually merge overlapping points
func merge_points() -> void:
	_merge_overlapping_points_impl()


func _get_android_export_dir() -> String:
	# Try to use Documents folder which is more accessible
	var docs_dir := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if docs_dir != "":
		return docs_dir.path_join("SceneTree/gltf")
	# Fallback to user:// which always works
	return "user://poly_exports"


func get_default_export_path() -> String:
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	if OS.get_name() == "Android":
		return _get_android_export_dir().path_join("poly_%s.gltf" % timestamp)
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
		# Try to create directory
		var abs_dir := base_dir if base_dir.begins_with("/") else ProjectSettings.globalize_path(base_dir)
		var err := DirAccess.make_dir_recursive_absolute(abs_dir)
		if err != OK and not DirAccess.dir_exists_absolute(abs_dir):
			# Fall back to user:// if external storage fails
			print("PolyTool: Could not create %s, falling back to user://" % abs_dir)
			var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
			target_path = "user://poly_exports/poly_%s.gltf" % timestamp
			base_dir = target_path.get_base_dir()
			abs_dir = ProjectSettings.globalize_path(base_dir)
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
	if not target_path.begins_with("res://") and not target_path.begins_with("user://") and not target_path.begins_with("/"):
		# Use appropriate directory based on platform
		if OS.get_name() == "Android":
			target_path = _get_android_export_dir().path_join(target_path)
		else:
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
	
	# Merge overlapping points if enabled
	if merge_overlapping_points:
		_merge_overlapping_points_impl()
	
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


func on_pooled() -> void:
	if instance == self:
		instance = null
	set_physics_process(false)
	_controller = null
	_drag_index = -1
	_drag_edge.clear()
	_drag_face_idx = -1
	_drag_start_positions.clear()
	_drag_point_indices.clear()
	_drag_grab_point = Vector3.ZERO
	_drag_start_basis = Basis.IDENTITY
	_hovered_edge.clear()
	_hovered_face_idx = -1
	_connect_sequence.clear()
	_clear_connect_lines()
	_clear_edit_highlights()
	_clear_geometry()
	_end_mode_select()
	_applied_material = null
	# Clean up shader viewport
	if is_instance_valid(_shader_viewport):
		_shader_viewport.queue_free()
		_shader_viewport = null
		_shader_color_rect = null
		_shader_viewport_texture = null
	if is_instance_valid(_preview_dot):
		_preview_dot.visible = false
	if is_instance_valid(_paint_dot):
		_paint_dot.visible = false
	if is_instance_valid(_material_preview_dot):
		_material_preview_dot.visible = false
	if is_instance_valid(_mesh_instance):
		_mesh_instance.visible = false
	if is_instance_valid(_point_container):
		_point_container.visible = false
	visible = false


func on_unpooled() -> void:
	visible = true
	if not is_instance_valid(_point_container) or not is_instance_valid(_mesh_instance):
		_create_visuals()
	if is_instance_valid(_mesh_instance):
		_mesh_instance.visible = true
	if is_instance_valid(_point_container):
		_point_container.visible = true
	if is_instance_valid(_preview_dot):
		_preview_dot.visible = false
	_update_point_visibility()
	_clear_connect_lines()
	set_physics_process(false)
	instance = self


func _clear_geometry() -> void:
	for p in _points:
		if is_instance_valid(p):
			p.queue_free()
	_points.clear()
	_triangles.clear()
	if _mesh_params:
		_mesh_params.clear_surfaces()


# Merges points that are within merge_distance of each other
# Returns a mapping of old indices to new indices
func _merge_overlapping_points_impl() -> void:
	if _points.size() < 2:
		return
	
	# Build groups of overlapping points
	var merge_map: Array[int] = [] # old_index -> new_index
	merge_map.resize(_points.size())
	for i in _points.size():
		merge_map[i] = i
	
	# Find overlapping points and mark them for merging
	for i in _points.size():
		if merge_map[i] != i:
			continue # Already merged into another point
		var pos_i = _points[i].global_position
		for j in range(i + 1, _points.size()):
			if merge_map[j] != j:
				continue # Already merged
			var pos_j = _points[j].global_position
			if pos_i.distance_to(pos_j) <= merge_distance:
				merge_map[j] = i # Merge j into i
	
	# Check if any merging is needed
	var needs_merge := false
	for i in _points.size():
		if merge_map[i] != i:
			needs_merge = true
			break
	
	if not needs_merge:
		return
	
	# Build new point list and index remapping
	var new_points: Array[Node3D] = []
	var old_to_new: Array[int] = []
	old_to_new.resize(_points.size())
	
	for i in _points.size():
		if merge_map[i] == i:
			# This point is kept
			old_to_new[i] = new_points.size()
			new_points.append(_points[i])
		else:
			# This point is merged into another - copy its color if needed
			var target_idx = merge_map[i]
			old_to_new[i] = old_to_new[target_idx]
			# Free the duplicate point
			_points[i].queue_free()
	
	# Update triangles with new indices
	var new_triangles: Array[Array] = []
	for tri in _triangles:
		var new_tri: Array[int] = []
		for idx in tri:
			new_tri.append(old_to_new[idx])
		# Check for degenerate triangles (same point used twice)
		if new_tri[0] != new_tri[1] and new_tri[1] != new_tri[2] and new_tri[0] != new_tri[2]:
			new_triangles.append(new_tri)
	
	_points = new_points
	_triangles = new_triangles
	_rebuild_mesh()
	_update_point_visibility()


# Get all point indices that share the same position as the given index
func _get_colocated_points(index: int) -> Array[int]:
	var result: Array[int] = [index]
	if not merge_overlapping_points:
		return result
	
	var pos = _points[index].global_position
	for i in _points.size():
		if i == index:
			continue
		if _points[i].global_position.distance_to(pos) <= merge_distance:
			result.append(i)
	return result


# Move a point and all colocated points together
func _move_point_with_colocated(index: int, pos: Vector3) -> void:
	if index < 0 or index >= _points.size():
		return
	
	if merge_overlapping_points:
		var colocated = _get_colocated_points(index)
		for idx in colocated:
			_points[idx].global_position = pos
	else:
		_points[index].global_position = pos
	
	_rebuild_mesh()
	_update_point_visibility()


# Move all points that were at start_pos to new_pos (used during drag for colocated points)
func _move_points_by_start_position(start_pos: Vector3, new_pos: Vector3) -> void:
	if not merge_overlapping_points:
		# Find the point at start_pos and move it
		for i in _points.size():
			if _points[i].global_position.distance_to(start_pos) <= merge_distance:
				_points[i].global_position = new_pos
				break
	else:
		# Move all points that were at start_pos
		for i in _points.size():
			if _points[i].global_position.distance_to(start_pos) <= merge_distance:
				_points[i].global_position = new_pos
