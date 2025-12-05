# VolumeHullPen - A grabbable pen that creates filled convex hull meshes in real-time
# Hold trigger while gripping to draw points, mesh updates live as you draw
extends Grabbable

# Configuration
@export var tip_offset: Vector3 = Vector3(0, 0, -0.15)  # Offset from center to pen tip
@export var min_distance: float = 0.02  # Minimum distance between recorded points
@export var min_points: int = 4  # Minimum points needed for a hull
@export var hull_color: Color = Color(0.2, 0.8, 0.4, 0.85)
@export var preview_point_radius: float = 0.008
@export var preview_point_color: Color = Color(1.0, 0.8, 0.0, 1.0)

# State
var _hull_points: PackedVector3Array = PackedVector3Array()  # Current hull vertices (minimal set)
var _is_recording: bool = false
var _preview_mesh: MeshInstance3D = null
var _hull_mesh_instance: MeshInstance3D = null
var _preview_material: StandardMaterial3D = null
var _hull_material: StandardMaterial3D = null
var _controller: Node = null
var _hand: RigidBody3D = null
var _prev_trigger_pressed: bool = false

# Preview sphere resources
var _preview_sphere_mesh: SphereMesh = null
var _preview_spheres: Array[MeshInstance3D] = []
var _preview_container: Node3D = null


func _ready() -> void:
	super._ready()
	
	grabbed.connect(_on_pen_grabbed)
	released.connect(_on_pen_released)
	
	# Create preview materials
	_create_materials()
	_create_preview_container()
	
	print("VolumeHullPen: Ready")


func _create_materials() -> void:
	# Preview point material
	_preview_material = StandardMaterial3D.new()
	_preview_material.albedo_color = preview_point_color
	_preview_material.emission_enabled = true
	_preview_material.emission = preview_point_color
	_preview_material.emission_energy_multiplier = 0.5
	
	# Preview sphere mesh
	_preview_sphere_mesh = SphereMesh.new()
	_preview_sphere_mesh.radius = preview_point_radius
	_preview_sphere_mesh.height = preview_point_radius * 2
	_preview_sphere_mesh.radial_segments = 8
	_preview_sphere_mesh.rings = 4
	
	# Hull material
	_hull_material = StandardMaterial3D.new()
	_hull_material.albedo_color = hull_color
	_hull_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if hull_color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	_hull_material.metallic = 0.3
	_hull_material.roughness = 0.4
	_hull_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Double-sided


func _create_preview_container() -> void:
	_preview_container = Node3D.new()
	_preview_container.name = "VolumeHullPenPreview"
	var root = get_tree().root
	if root:
		root.call_deferred("add_child", _preview_container)
	
	# Create hull mesh instance for live preview
	_hull_mesh_instance = MeshInstance3D.new()
	_hull_mesh_instance.name = "LiveHullMesh"
	_hull_mesh_instance.material_override = _hull_material
	if is_instance_valid(_preview_container):
		_preview_container.call_deferred("add_child", _hull_mesh_instance)


func _on_pen_grabbed(hand: RigidBody3D) -> void:
	_hand = hand
	_controller = null
	
	if is_instance_valid(hand) and hand.has_method("get"):
		var maybe_target = hand.get("target")
		if maybe_target and maybe_target is Node3D:
			_controller = maybe_target
	
	set_physics_process(true)
	print("VolumeHullPen: Grabbed")


func _on_pen_released() -> void:
	if _is_recording:
		_stop_recording()
	
	_cleanup_previews()
	_hand = null
	_controller = null
	set_physics_process(false)
	print("VolumeHullPen: Released")


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	if not is_grabbed or not is_instance_valid(_hand):
		return
	
	# Read trigger input
	var trigger_pressed: bool = false
	if is_instance_valid(_controller) and _controller.has_method("get_float"):
		var trigger_value = _controller.get_float("trigger")
		trigger_pressed = trigger_value > 0.5
	elif InputMap.has_action("trigger_click"):
		trigger_pressed = Input.is_action_pressed("trigger_click")
	
	# Handle trigger state changes
	if trigger_pressed and not _prev_trigger_pressed:
		_start_recording()
	elif not trigger_pressed and _prev_trigger_pressed:
		_stop_recording()
	
	# If recording, add points and update hull
	if _is_recording:
		_record_point()
	
	_prev_trigger_pressed = trigger_pressed


func _get_tip_world_position() -> Vector3:
	if grabbed_collision_shapes.size() > 0 and is_instance_valid(grabbed_collision_shapes[0]):
		var grabbed_transform = grabbed_collision_shapes[0].global_transform
		return grabbed_transform * tip_offset
	elif is_instance_valid(_hand):
		return _hand.global_transform * tip_offset
	return global_position + tip_offset


func _start_recording() -> void:
	if _is_recording:
		return
	
	_is_recording = true
	_hull_points.clear()
	_cleanup_point_previews()
	
	# Clear the live hull mesh
	if is_instance_valid(_hull_mesh_instance):
		_hull_mesh_instance.mesh = null
	
	print("VolumeHullPen: Started recording")


func _stop_recording() -> void:
	if not _is_recording:
		return
	
	_is_recording = false
	print("VolumeHullPen: Stopped recording with ", _hull_points.size(), " hull points")
	
	if _hull_points.size() >= min_points:
		_create_final_hull()
	else:
		print("VolumeHullPen: Not enough points (", _hull_points.size(), "/", min_points, ")")
	
	_hull_points.clear()
	_cleanup_previews()


func _record_point() -> void:
	"""Record the current tip position and update hull in real-time."""
	var tip_pos = _get_tip_world_position()
	
	# Check minimum distance from existing hull points
	for existing_point in _hull_points:
		if tip_pos.distance_to(existing_point) < min_distance:
			return
	
	# Add point and recompute hull
	_hull_points.append(tip_pos)
	
	# Create visual preview point
	_create_preview_point(tip_pos)
	
	# Update hull mesh if we have enough points
	if _hull_points.size() >= min_points:
		_update_live_hull_mesh()


func _create_preview_point(pos: Vector3) -> void:
	if not is_instance_valid(_preview_container):
		return
	
	var sphere = MeshInstance3D.new()
	sphere.mesh = _preview_sphere_mesh
	sphere.material_override = _preview_material
	sphere.global_position = pos
	
	_preview_container.add_child(sphere)
	_preview_spheres.append(sphere)


func _update_live_hull_mesh() -> void:
	"""Regenerate the hull mesh from current points, pruning internal points."""
	if _hull_points.size() < min_points:
		return
	
	# Use ConvexPolygonShape3D to compute hull vertices (this prunes internal points)
	var temp_shape = ConvexPolygonShape3D.new()
	temp_shape.points = _hull_points
	
	# Get the actual hull vertices (internal points are removed)
	var hull_vertices = temp_shape.points
	
	if hull_vertices.size() < 4:
		return
	
	# Replace our points with hull vertices (efficiently prunes internal points)
	_hull_points = hull_vertices
	
	# Update preview points to only show hull vertices
	_sync_preview_points_with_hull()
	
	# Generate the mesh
	var mesh = _create_convex_hull_mesh(hull_vertices)
	if mesh and is_instance_valid(_hull_mesh_instance):
		_hull_mesh_instance.mesh = mesh


func _sync_preview_points_with_hull() -> void:
	"""Update preview spheres to match current hull points."""
	# Remove excess preview spheres
	while _preview_spheres.size() > _hull_points.size():
		var sphere = _preview_spheres.pop_back()
		if is_instance_valid(sphere):
			sphere.queue_free()
	
	# Update positions of remaining spheres
	for i in range(min(_preview_spheres.size(), _hull_points.size())):
		if is_instance_valid(_preview_spheres[i]):
			_preview_spheres[i].global_position = _hull_points[i]
	
	# Add new spheres if needed
	while _preview_spheres.size() < _hull_points.size():
		var idx = _preview_spheres.size()
		_create_preview_point(_hull_points[idx])


func _create_convex_hull_mesh(points: PackedVector3Array) -> ArrayMesh:
	"""Create a filled convex hull mesh from the given points."""
	if points.size() < 4:
		return null
	
	# Calculate centroid
	var centroid = Vector3.ZERO
	for p in points:
		centroid += p
	centroid /= points.size()
	
	# Build triangles using quickhull-style face generation
	# For a convex hull, we triangulate each face from the centroid
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Get faces using the convex hull algorithm approach
	var faces = _compute_convex_hull_faces(points, centroid)
	
	for face in faces:
		if face.size() < 3:
			continue
		
		# Triangulate the face (fan from first vertex)
		var v0 = face[0]
		for i in range(1, face.size() - 1):
			var v1 = face[i]
			var v2 = face[i + 1]
			
			# Calculate face normal
			var edge1 = v1 - v0
			var edge2 = v2 - v0
			var normal = edge1.cross(edge2).normalized()
			
			# Ensure normal points outward (away from centroid)
			var face_center = (v0 + v1 + v2) / 3.0
			var to_centroid = centroid - face_center
			if normal.dot(to_centroid) > 0:
				normal = -normal
				# Swap winding
				var temp = v1
				v1 = v2
				v2 = temp
			
			st.set_normal(normal)
			st.add_vertex(v0)
			st.set_normal(normal)
			st.add_vertex(v1)
			st.set_normal(normal)
			st.add_vertex(v2)
	
	st.generate_normals()
	return st.commit()


func _compute_convex_hull_faces(points: PackedVector3Array, centroid: Vector3) -> Array:
	"""Compute the faces of a convex hull using incremental algorithm."""
	var faces: Array = []
	
	if points.size() < 4:
		return faces
	
	# Start with a tetrahedron from first 4 non-coplanar points
	var initial_points = _find_initial_tetrahedron(points)
	if initial_points.size() < 4:
		# Fallback: create simple triangulation from centroid
		return _fallback_triangulation(points, centroid)
	
	# Initialize with tetrahedron faces
	var p0 = initial_points[0]
	var p1 = initial_points[1]
	var p2 = initial_points[2]
	var p3 = initial_points[3]
	
	# Create 4 faces of tetrahedron with correct winding
	faces.append(_make_face_ccw([p0, p1, p2], centroid))
	faces.append(_make_face_ccw([p0, p2, p3], centroid))
	faces.append(_make_face_ccw([p0, p3, p1], centroid))
	faces.append(_make_face_ccw([p1, p3, p2], centroid))
	
	# Add remaining points incrementally
	for i in range(points.size()):
		var p = points[i]
		if p in initial_points:
			continue
		
		# Find faces visible from this point
		var visible_faces: Array = []
		var boundary_edges: Array = []
		
		for face_idx in range(faces.size() - 1, -1, -1):
			var face = faces[face_idx]
			if _is_point_above_face(p, face, centroid):
				visible_faces.append(face)
				faces.remove_at(face_idx)
		
		if visible_faces.is_empty():
			continue
		
		# Collect boundary edges (edges that appear in only one visible face)
		var edge_count: Dictionary = {}
		for face in visible_faces:
			for j in range(face.size()):
				var e0 = face[j]
				var e1 = face[(j + 1) % face.size()]
				var edge_key = _edge_key(e0, e1)
				if edge_count.has(edge_key):
					edge_count[edge_key] += 1
				else:
					edge_count[edge_key] = 1
					edge_count[edge_key + "_verts"] = [e0, e1]
		
		# Create new faces from boundary edges to new point
		for key in edge_count:
			if "_verts" in key:
				continue
			if edge_count[key] == 1:
				var verts = edge_count[key + "_verts"]
				var new_face = _make_face_ccw([verts[0], verts[1], p], centroid)
				faces.append(new_face)
	
	return faces


func _find_initial_tetrahedron(points: PackedVector3Array) -> Array:
	"""Find 4 non-coplanar points to form initial tetrahedron."""
	if points.size() < 4:
		return []
	
	var result: Array = [points[0]]
	
	# Find second point (furthest from first)
	var max_dist = 0.0
	var second_idx = 1
	for i in range(1, points.size()):
		var d = points[0].distance_to(points[i])
		if d > max_dist:
			max_dist = d
			second_idx = i
	result.append(points[second_idx])
	
	# Find third point (furthest from line)
	max_dist = 0.0
	var third_idx = -1
	var line_dir = (result[1] - result[0]).normalized()
	for i in range(points.size()):
		if i == second_idx or points[i] == result[0]:
			continue
		var to_point = points[i] - result[0]
		var proj = to_point.dot(line_dir)
		var closest_on_line = result[0] + line_dir * proj
		var d = points[i].distance_to(closest_on_line)
		if d > max_dist:
			max_dist = d
			third_idx = i
	
	if third_idx < 0:
		return []
	result.append(points[third_idx])
	
	# Find fourth point (furthest from plane)
	var plane_normal = (result[1] - result[0]).cross(result[2] - result[0]).normalized()
	max_dist = 0.0
	var fourth_idx = -1
	for i in range(points.size()):
		if points[i] in result:
			continue
		var d = abs((points[i] - result[0]).dot(plane_normal))
		if d > max_dist:
			max_dist = d
			fourth_idx = i
	
	if fourth_idx < 0 or max_dist < 0.001:
		return []
	result.append(points[fourth_idx])
	
	return result


func _make_face_ccw(verts: Array, centroid: Vector3) -> Array:
	"""Ensure face vertices are in counter-clockwise order when viewed from outside."""
	var v0 = verts[0]
	var v1 = verts[1]
	var v2 = verts[2]
	
	var normal = (v1 - v0).cross(v2 - v0)
	var face_center = (v0 + v1 + v2) / 3.0
	var to_centroid = centroid - face_center
	
	if normal.dot(to_centroid) > 0:
		# Normal points inward, reverse winding
		return [v0, v2, v1]
	return verts


func _is_point_above_face(point: Vector3, face: Array, centroid: Vector3) -> bool:
	"""Check if point is above the face (visible from outside)."""
	var v0 = face[0]
	var v1 = face[1]
	var v2 = face[2]
	
	var normal = (v1 - v0).cross(v2 - v0).normalized()
	var face_center = (v0 + v1 + v2) / 3.0
	var to_centroid = centroid - face_center
	
	if normal.dot(to_centroid) > 0:
		normal = -normal
	
	var to_point = point - face_center
	return to_point.dot(normal) > 0.0001


func _edge_key(v0: Vector3, v1: Vector3) -> String:
	"""Create a unique key for an edge regardless of direction."""
	var k0 = "%0.4f,%0.4f,%0.4f" % [v0.x, v0.y, v0.z]
	var k1 = "%0.4f,%0.4f,%0.4f" % [v1.x, v1.y, v1.z]
	if k0 < k1:
		return k0 + "_" + k1
	return k1 + "_" + k0


func _fallback_triangulation(points: PackedVector3Array, centroid: Vector3) -> Array:
	"""Simple fallback triangulation using centroid fan."""
	var faces: Array = []
	
	# Order points and create simple triangulation
	var ordered = _order_points_around_axis(points, centroid)
	
	for i in range(ordered.size()):
		var p1 = ordered[i]
		var p2 = ordered[(i + 1) % ordered.size()]
		faces.append([centroid, p1, p2])
	
	return faces


func _order_points_around_axis(points: PackedVector3Array, centroid: Vector3) -> Array:
	"""Order points around the centroid for simple triangulation."""
	if points.size() < 3:
		var result: Array = []
		for p in points:
			result.append(p)
		return result
	
	# Find best axis to project onto
	var normal = Vector3.UP
	for i in range(points.size() - 2):
		var v1 = points[i + 1] - points[i]
		var v2 = points[i + 2] - points[i]
		var cross = v1.cross(v2)
		if cross.length() > 0.001:
			normal = cross.normalized()
			break
	
	var tangent = normal.cross(Vector3.UP)
	if tangent.length() < 0.001:
		tangent = normal.cross(Vector3.FORWARD)
	tangent = tangent.normalized()
	var bitangent = normal.cross(tangent).normalized()
	
	var point_angles: Array = []
	for p in points:
		var offset = p - centroid
		var x = offset.dot(tangent)
		var y = offset.dot(bitangent)
		var angle = atan2(y, x)
		point_angles.append({"point": p, "angle": angle})
	
	point_angles.sort_custom(func(a, b): return a["angle"] < b["angle"])
	
	var ordered: Array = []
	for pa in point_angles:
		ordered.append(pa["point"])
	
	return ordered


func _create_final_hull() -> void:
	"""Create the final RigidBody3D hull from the current points."""
	if _hull_points.size() < min_points:
		return
	
	print("VolumeHullPen: Creating final hull from ", _hull_points.size(), " points")
	
	# Calculate centroid for positioning
	var centroid = Vector3.ZERO
	for p in _hull_points:
		centroid += p
	centroid /= _hull_points.size()
	
	# Offset points relative to centroid
	var offset_points: PackedVector3Array = PackedVector3Array()
	for p in _hull_points:
		offset_points.append(p - centroid)
	
	# Create collision shape
	var hull_shape = ConvexPolygonShape3D.new()
	hull_shape.points = offset_points
	
	# Create mesh
	var hull_mesh = _create_convex_hull_mesh(offset_points)
	if hull_mesh == null:
		print("VolumeHullPen: Failed to create hull mesh")
		return
	
	# Create RigidBody3D
	var hull_body = RigidBody3D.new()
	hull_body.name = "VolumeHull_" + str(randi() % 10000)
	hull_body.mass = 0.5
	hull_body.gravity_scale = 1.0
	
	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = hull_shape
	hull_body.add_child(collision_shape)
	
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = hull_mesh
	mesh_instance.material_override = _hull_material.duplicate()
	hull_body.add_child(mesh_instance)
	
	# Add to scene at centroid position
	var current_scene = get_tree().current_scene
	if current_scene:
		current_scene.add_child(hull_body)
		hull_body.global_position = centroid
		hull_body.add_to_group("grabbable")
		print("VolumeHullPen: Created hull at ", centroid)
	else:
		hull_body.queue_free()


func _cleanup_point_previews() -> void:
	for sphere in _preview_spheres:
		if is_instance_valid(sphere):
			sphere.queue_free()
	_preview_spheres.clear()


func _cleanup_previews() -> void:
	_cleanup_point_previews()
	if is_instance_valid(_hull_mesh_instance):
		_hull_mesh_instance.mesh = null


func _exit_tree() -> void:
	if is_instance_valid(_preview_container):
		_preview_container.queue_free()
	super._exit_tree()
