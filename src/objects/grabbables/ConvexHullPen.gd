# ConvexHullPen - A grabbable pen that creates convex hull meshes
# Hold trigger while gripping to record points, release to generate hull
extends Grabbable


# Configuration
@export var tip_offset: Vector3 = Vector3(0, 0, -0.15)  # Offset from center to pen tip
@export var min_distance: float = 0.02  # Minimum distance between recorded points
@export var min_points: int = 4  # Minimum points needed for a hull
@export var max_points: int = 100  # Maximum points to prevent performance issues
@export var hull_color: Color = Color(0.3, 0.7, 1.0, 0.8)
@export var preview_sphere_radius: float = 0.01
@export var preview_sphere_color: Color = Color(1.0, 0.5, 0.0, 1.0)

# State
var _recorded_points: Array[Vector3] = []
var _is_recording: bool = false
var _preview_spheres: Array[MeshInstance3D] = []
var _preview_container: Node3D = null
var _tip_marker: MeshInstance3D = null
var _controller: Node = null
var _hand: RigidBody3D = null
var _prev_trigger_pressed: bool = false

# Shared resources for preview spheres
var _preview_sphere_mesh: SphereMesh = null
var _preview_material: StandardMaterial3D = null
const POOL_TYPE := "convex_hull"


func _ready() -> void:
	# Call parent Grabbable._ready() for standard grabbable setup
	super._ready()
	var pool := ToolPoolManager.find()
	if pool:
		pool.register_instance(POOL_TYPE, self)
	
	# Connect to our own signals
	grabbed.connect(_on_pen_grabbed)
	released.connect(_on_pen_released)
	
	# Create shared resources for preview spheres
	_preview_sphere_mesh = SphereMesh.new()
	_preview_sphere_mesh.radius = preview_sphere_radius
	_preview_sphere_mesh.height = preview_sphere_radius * 2
	_preview_sphere_mesh.radial_segments = 8
	_preview_sphere_mesh.rings = 4
	
	_preview_material = StandardMaterial3D.new()
	_preview_material.albedo_color = preview_sphere_color
	_preview_material.emission_enabled = true
	_preview_material.emission = preview_sphere_color
	_preview_material.emission_energy_multiplier = 0.5
	
	# Create preview container at root level for persistence
	_create_preview_container()
	
	# Find tip marker if it exists in scene
	var tip_node = get_node_or_null("TipMarker/TipMesh")
	if tip_node and tip_node is MeshInstance3D:
		_tip_marker = tip_node
	
	print("ConvexHullPen: Ready")


func _create_preview_container() -> void:
	"""Create a container node at root level to hold preview spheres"""
	_preview_container = Node3D.new()
	_preview_container.name = "ConvexHullPenPreview"
	# Add to root so it persists during scene changes
	var root = get_tree().root
	if root:
		root.call_deferred("add_child", _preview_container)
	else:
		call_deferred("_create_preview_container")


func _on_pen_grabbed(hand: RigidBody3D) -> void:
	"""Called when the pen is grabbed"""
	_hand = hand
	_controller = null
	
	if is_instance_valid(hand) and hand.has_method("get"):
		var maybe_target = hand.get("target")
		if maybe_target and maybe_target is Node3D:
			_controller = maybe_target
	
	set_physics_process(true)
	print("ConvexHullPen: Grabbed by ", hand.name)


func _on_pen_released() -> void:
	"""Called when the pen is released"""
	# If we were recording, stop and generate hull
	if _is_recording:
		_stop_recording()
	
	_cleanup_previews()
	_hand = null
	_controller = null
	set_physics_process(false)
	print("ConvexHullPen: Released")


func _physics_process(delta: float) -> void:
	# Call parent physics process for grabbable functionality
	super._physics_process(delta)
	
	if not is_grabbed:
		return
	if not is_instance_valid(_hand):
		return
	
	# Read trigger input
	var trigger_pressed: bool = false
	if is_instance_valid(_controller) and _controller.has_method("get_float"):
		var trigger_value = _controller.get_float("trigger")
		trigger_pressed = trigger_value > 0.5
	elif is_instance_valid(_controller) and _controller.has_method("is_button_pressed"):
		trigger_pressed = _controller.is_button_pressed("trigger_click")
	elif InputMap.has_action("trigger_click"):
		trigger_pressed = Input.is_action_pressed("trigger_click")
	
	# Handle trigger state changes (rising/falling edge)
	if trigger_pressed and not _prev_trigger_pressed:
		# Trigger just pressed - start recording
		_start_recording()
	elif not trigger_pressed and _prev_trigger_pressed:
		# Trigger just released - stop recording and generate hull
		_stop_recording()
	
	# If recording, add points
	if _is_recording:
		_record_point()
	
	_prev_trigger_pressed = trigger_pressed


func _get_tip_world_position() -> Vector3:
	"""Get the world position of the pen tip"""
	# The tip position is relative to the first grabbed collision shape (which follows the hand)
	if grabbed_collision_shapes.size() > 0 and is_instance_valid(grabbed_collision_shapes[0]):
		var grabbed_transform = grabbed_collision_shapes[0].global_transform
		return grabbed_transform * tip_offset
	elif is_instance_valid(_hand):
		# Fallback to hand position
		return _hand.global_transform * tip_offset
	return global_position + tip_offset


func _start_recording() -> void:
	"""Start recording points"""
	if _is_recording:
		return
	
	_is_recording = true
	_recorded_points.clear()
	_cleanup_previews()
	
	print("ConvexHullPen: Started recording")


func _stop_recording() -> void:
	"""Stop recording and generate hull if we have enough points"""
	if not _is_recording:
		return
	
	_is_recording = false
	print("ConvexHullPen: Stopped recording with ", _recorded_points.size(), " points")
	
	if _recorded_points.size() >= min_points:
		_generate_convex_hull()
	else:
		print("ConvexHullPen: Not enough points (", _recorded_points.size(), "/", min_points, ")")
	
	_recorded_points.clear()
	_cleanup_previews()


func _record_point() -> void:
	"""Record the current tip position if far enough from last point"""
	if _recorded_points.size() >= max_points:
		return
	
	var tip_pos = _get_tip_world_position()
	
	# Check distance from last point
	if _recorded_points.size() > 0:
		var last_point = _recorded_points[_recorded_points.size() - 1]
		var dist = tip_pos.distance_to(last_point)
		if dist < min_distance:
			return
	
	_recorded_points.append(tip_pos)
	_create_preview_sphere(tip_pos)


func _create_preview_sphere(pos: Vector3) -> void:
	"""Create a small sphere at the given position as visual feedback"""
	if not is_instance_valid(_preview_container):
		return
	
	var sphere = MeshInstance3D.new()
	sphere.mesh = _preview_sphere_mesh
	sphere.material_override = _preview_material
	sphere.global_transform = Transform3D(Basis(), pos)
	
	_preview_container.add_child(sphere)
	_preview_spheres.append(sphere)


func _cleanup_previews() -> void:
	"""Remove all preview spheres"""
	for sphere in _preview_spheres:
		if is_instance_valid(sphere):
			sphere.queue_free()
	_preview_spheres.clear()


func _generate_convex_hull() -> void:
	"""Generate a convex hull mesh and physics body from recorded points"""
	if _recorded_points.size() < min_points:
		print("ConvexHullPen: Cannot generate hull - not enough points")
		return
	
	print("ConvexHullPen: Generating convex hull from ", _recorded_points.size(), " points")
	
	# Create ConvexPolygonShape3D from the points
	var hull_shape = ConvexPolygonShape3D.new()
	hull_shape.points = PackedVector3Array(_recorded_points)
	
	# Create the hull mesh using ArrayMesh and SurfaceTool
	var hull_mesh = _create_hull_mesh(hull_shape.points)
	if hull_mesh == null:
		print("ConvexHullPen: Failed to create hull mesh")
		return
	
	# Create RigidBody3D for the hull
	var hull_body = RigidBody3D.new()
	hull_body.name = "GeneratedHull_" + str(randi() % 10000)
	hull_body.mass = 0.5
	hull_body.gravity_scale = 1.0
	
	# Add collision shape
	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = hull_shape
	hull_body.add_child(collision_shape)
	
	# Add mesh visual
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = hull_mesh
	
	# Create material
	var material = StandardMaterial3D.new()
	material.albedo_color = hull_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if hull_color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	material.metallic = 0.2
	material.roughness = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material
	
	hull_body.add_child(mesh_instance)
	
	# Add to current scene
	var current_scene = get_tree().current_scene
	if current_scene:
		# Register hull with pool manager (will remove oldest if at limit)
		var pool := ToolPoolManager.find()
		if pool:
			pool.register_hull(hull_body)
		
		current_scene.add_child(hull_body)
		# Position at origin of the points (centroid)
		var centroid = _calculate_centroid(_recorded_points)
		hull_body.global_position = centroid
		
		# Offset all collision/mesh data to be relative to centroid
		# The points are already in world space, so we need to offset them
		var offset_points: PackedVector3Array = PackedVector3Array()
		for point in _recorded_points:
			offset_points.append(point - centroid)
		
		# Recreate shape with offset points
		hull_shape.points = offset_points
		
		# Recreate mesh with offset points
		var offset_mesh = _create_hull_mesh(offset_points)
		if offset_mesh:
			mesh_instance.mesh = offset_mesh
		
		# Add to grabbable group so it can be picked up
		hull_body.add_to_group("grabbable")
		
		print("ConvexHullPen: Created hull at ", centroid)
	else:
		hull_body.queue_free()
		print("ConvexHullPen: No current scene to add hull to")


func _calculate_centroid(points: Array[Vector3]) -> Vector3:
	"""Calculate the centroid of a set of points"""
	if points.size() == 0:
		return Vector3.ZERO
	
	var sum = Vector3.ZERO
	for point in points:
		sum += point
	return sum / points.size()


func _create_hull_mesh(points: PackedVector3Array) -> ArrayMesh:
	"""Create an ArrayMesh from convex hull points using SurfaceTool"""
	if points.size() < 4:
		return null
	
	# Get the convex hull geometry using Geometry3D
	# We'll create triangles by connecting points from the convex hull
	
	# Use QuickHull or simple approach - for a convex hull we can use
	# the built-in ConvexPolygonShape3D which computes the hull
	var temp_shape = ConvexPolygonShape3D.new()
	temp_shape.points = points
	
	# The shape's points are now the hull vertices
	# We need to create triangles - use a simple approach:
	# Connect all points to form triangles using a fan from centroid
	
	var hull_points = temp_shape.points
	if hull_points.size() < 4:
		return null
	
	# Calculate centroid of hull points
	var centroid = Vector3.ZERO
	for p in hull_points:
		centroid += p
	centroid /= hull_points.size()
	
	# Create mesh using SurfaceTool
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# For each pair of adjacent hull vertices, create a triangle with centroid
	# This works well for convex shapes
	# First, we need to order the points - use a simple heuristic
	var ordered_points = _order_points_for_mesh(hull_points, centroid)
	
	# Create triangulated faces using the ordered points
	# Simple approach: create triangle fan from centroid to each edge
	for i in range(ordered_points.size()):
		var p1 = ordered_points[i]
		var p2 = ordered_points[(i + 1) % ordered_points.size()]
		
		# Calculate normal for this triangle
		var edge1 = p1 - centroid
		var edge2 = p2 - centroid
		var normal = edge1.cross(edge2).normalized()
		
		# Add triangle (centroid, p1, p2)
		st.set_normal(normal)
		st.add_vertex(centroid)
		st.set_normal(normal)
		st.add_vertex(p1)
		st.set_normal(normal)
		st.add_vertex(p2)
		
		# Add reverse triangle for double-sided rendering
		st.set_normal(-normal)
		st.add_vertex(centroid)
		st.set_normal(-normal)
		st.add_vertex(p2)
		st.set_normal(-normal)
		st.add_vertex(p1)
	
	# Generate the mesh
	st.generate_normals()
	return st.commit()


func _order_points_for_mesh(points: PackedVector3Array, centroid: Vector3) -> Array[Vector3]:
	"""Order points around the centroid for proper mesh generation"""
	if points.size() < 3:
		var result: Array[Vector3] = []
		for p in points:
			result.append(p)
		return result
	
	# Find a reference plane - use the first three non-collinear points
	var normal = Vector3.UP
	for i in range(points.size() - 2):
		var v1 = points[i + 1] - points[i]
		var v2 = points[i + 2] - points[i]
		var cross = v1.cross(v2)
		if cross.length() > 0.001:
			normal = cross.normalized()
			break
	
	# Create tangent vectors for the plane
	var tangent = normal.cross(Vector3.UP)
	if tangent.length() < 0.001:
		tangent = normal.cross(Vector3.FORWARD)
	tangent = tangent.normalized()
	var bitangent = normal.cross(tangent).normalized()
	
	# Project points onto 2D plane and sort by angle
	var point_angles: Array = []
	for p in points:
		var offset = p - centroid
		var x = offset.dot(tangent)
		var y = offset.dot(bitangent)
		var angle = atan2(y, x)
		point_angles.append({"point": p, "angle": angle})
	
	# Sort by angle
	point_angles.sort_custom(func(a, b): return a["angle"] < b["angle"])
	
	# Extract ordered points
	var ordered: Array[Vector3] = []
	for pa in point_angles:
		ordered.append(pa["point"])
	
	return ordered


func on_pooled() -> void:
	set_physics_process(false)
	_is_recording = false
	_recorded_points.clear()
	_prev_trigger_pressed = false
	_cleanup_previews()
	if is_instance_valid(_preview_container):
		_preview_container.queue_free()
		_preview_container = null
	_controller = null
	_hand = null
	visible = false


func on_unpooled() -> void:
	visible = true
	if not is_instance_valid(_preview_container):
		_create_preview_container()
	_recorded_points.clear()
	_prev_trigger_pressed = false
	set_physics_process(false)


func _exit_tree() -> void:
	# Clean up preview container
	if is_instance_valid(_preview_container):
		_preview_container.queue_free()
	
	# Call parent
	super._exit_tree()
