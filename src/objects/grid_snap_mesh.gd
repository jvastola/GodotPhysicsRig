extends Grabbable
## A grabbable mesh that maintains fixed vertex offsets from center, but snaps vertices to grid positions

## Grid size for snapping vertices
@export var grid_size: float = 0.25

## Number of random vertices to generate for the low-poly shape
@export var vertex_count: int = 12

## Radius of the random shape
@export var shape_radius: float = 0.3

## Material for the mesh
@export var mesh_material: Material

var array_mesh: ArrayMesh
var initial_vertices: PackedVector3Array
var last_position: Vector3
var mesh_instance: MeshInstance3D

func _ready() -> void:
	super._ready()
	
	# Generate random low-poly vertices
	_generate_random_vertices()
	
	# Create the mesh instance as a child
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	
	# Create the ArrayMesh
	_create_mesh()
	last_position = global_position

func _generate_random_vertices() -> void:
	# Generate random vertices on and inside a sphere
	initial_vertices = PackedVector3Array()
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	# Always add center point
	initial_vertices.append(Vector3.ZERO)
	
	for i in range(vertex_count):
		# Generate random point in sphere
		var theta = rng.randf() * TAU
		var phi = acos(2.0 * rng.randf() - 1.0)
		var r = pow(rng.randf(), 1.0/3.0) * shape_radius
		
		var x = r * sin(phi) * cos(theta)
		var y = r * sin(phi) * sin(theta)
		var z = r * cos(phi)
		
		initial_vertices.append(Vector3(x, y, z))

func _create_mesh() -> void:
	array_mesh = ArrayMesh.new()
	
	# Get unique snapped vertices
	var snapped_vertices = _get_unique_snapped_vertices()
	
	# Create mesh from snapped vertices using convex hull
	_create_convex_mesh(snapped_vertices)
	
	mesh_instance.mesh = array_mesh
	
	# Update collision shape to match mesh
	_update_collision_shape()

func _get_unique_snapped_vertices() -> PackedVector3Array:
	# Track which grid positions are used
	var used_grid_positions = {}
	var result = PackedVector3Array()
	
	for vertex in initial_vertices:
		var snapped_pos = _snap_vertex_to_grid(vertex)
		
		# Create a key for this grid position
		var grid_key = _vector_to_grid_key(snapped_pos)
		
		# If this position is already used, try to find a nearby free position
		if grid_key in used_grid_positions:
			snapped_pos = _find_nearby_free_grid_position(snapped_pos, used_grid_positions)
			grid_key = _vector_to_grid_key(snapped_pos)
		
		used_grid_positions[grid_key] = true
		result.append(snapped_pos)
	
	return result

func _vector_to_grid_key(pos: Vector3) -> String:
	# Convert position to a string key for dictionary lookup
	return "%d,%d,%d" % [
		int(round(pos.x / grid_size)),
		int(round(pos.y / grid_size)),
		int(round(pos.z / grid_size))
	]

func _find_nearby_free_grid_position(original_pos: Vector3, used_positions: Dictionary) -> Vector3:
	# Try to find a nearby grid position that's not occupied
	var offsets = [
		Vector3(grid_size, 0, 0), Vector3(-grid_size, 0, 0),
		Vector3(0, grid_size, 0), Vector3(0, -grid_size, 0),
		Vector3(0, 0, grid_size), Vector3(0, 0, -grid_size),
	]
	
	for offset in offsets:
		var test_pos = original_pos + offset
		var key = _vector_to_grid_key(test_pos)
		if not (key in used_positions):
			return test_pos
	
	# If all immediate neighbors are taken, just use a diagonal offset
	return original_pos + Vector3(grid_size, grid_size, 0)

func _create_convex_mesh(vertices: PackedVector3Array) -> void:
	if vertices.size() < 4:
		return  # Need at least 4 vertices for a volume
	
	# Use Godot's built-in convex hull generation
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Create arrays for the mesh
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	# Generate convex hull triangles using a simple approach
	var triangles = _generate_convex_hull_triangles(vertices)
	
	# Build mesh from triangles
	var final_vertices = PackedVector3Array()
	var final_normals = PackedVector3Array()
	var final_uvs = PackedVector2Array()
	
	for tri in triangles:
		var v0 = vertices[tri[0]]
		var v1 = vertices[tri[1]]
		var v2 = vertices[tri[2]]
		
		# Calculate normal
		var edge1 = v1 - v0
		var edge2 = v2 - v0
		var normal = edge1.cross(edge2).normalized()
		
		# Add each vertex of the triangle
		final_vertices.append(v0)
		final_vertices.append(v1)
		final_vertices.append(v2)
		
		final_normals.append(normal)
		final_normals.append(normal)
		final_normals.append(normal)
		
		final_uvs.append(Vector2(0, 0))
		final_uvs.append(Vector2(1, 0))
		final_uvs.append(Vector2(0.5, 1))
	
	# Set the arrays
	arrays[Mesh.ARRAY_VERTEX] = final_vertices
	arrays[Mesh.ARRAY_NORMAL] = final_normals
	arrays[Mesh.ARRAY_TEX_UV] = final_uvs
	
	# Add the mesh surface
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	# Apply material
	if mesh_material:
		array_mesh.surface_set_material(0, mesh_material)

func _generate_convex_hull_triangles(vertices: PackedVector3Array) -> Array:
	# Use a ConvexPolygonShape3D to generate the hull, then extract triangles
	var hull_shape = ConvexPolygonShape3D.new()
	hull_shape.points = vertices
	
	# For rendering, we'll use a simpler approach: create a mesh from the points
	# by connecting to centroid and between neighbors
	var triangles = []
	var _centroid = Vector3.ZERO
	for v in vertices:
		_centroid += v
	_centroid /= vertices.size()
	
	# Find the convex hull using a gift wrapping approach (simplified)
	# For simplicity, we'll create triangles by connecting vertices
	for i in range(vertices.size()):
		for j in range(i + 1, vertices.size()):
			for k in range(j + 1, vertices.size()):
				# Check if this triangle is on the convex hull
				if _is_hull_triangle(vertices, i, j, k):
					triangles.append([i, j, k])
	
	return triangles

func _is_hull_triangle(vertices: PackedVector3Array, i: int, j: int, k: int) -> bool:
	# A triangle is on the hull if all other points are on one side
	var v0 = vertices[i]
	var v1 = vertices[j]
	var v2 = vertices[k]
	
	var edge1 = v1 - v0
	var edge2 = v2 - v0
	var normal = edge1.cross(edge2)
	
	if normal.length_squared() < 0.0001:
		return false  # Degenerate triangle
	
	var positive_count = 0
	var negative_count = 0
	
	for idx in range(vertices.size()):
		if idx == i or idx == j or idx == k:
			continue
		
		var to_point = vertices[idx] - v0
		var dot = normal.dot(to_point)
		
		if dot > 0.0001:
			positive_count += 1
		elif dot < -0.0001:
			negative_count += 1
	
	# Triangle is on hull if all points are on one side (or on the plane)
	return positive_count == 0 or negative_count == 0

func _update_collision_shape() -> void:
	# Find or create collision shape
	var collision_shape = get_node_or_null("CollisionShape3D")
	if not collision_shape:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		add_child(collision_shape)
	
	# Create a convex collision shape from the unique snapped vertices
	var shape = ConvexPolygonShape3D.new()
	var snapped_points = _get_unique_snapped_vertices()
	shape.points = snapped_points
	collision_shape.shape = shape

func _snap_vertex_to_grid(vertex: Vector3) -> Vector3:
	# Get the vertex in world space
	var world_vertex := global_position + vertex
	
	# Snap to grid
	var snapped_pos := Vector3(
		round(world_vertex.x / grid_size) * grid_size,
		round(world_vertex.y / grid_size) * grid_size,
		round(world_vertex.z / grid_size) * grid_size
	)
	
	# Convert back to local space
	return snapped_pos - global_position

func _process(_delta: float) -> void:
	# Update mesh if position has changed
	if global_position != last_position:
		_update_mesh_vertices()
		last_position = global_position

func _update_mesh_vertices() -> void:
	# Clear the existing mesh
	array_mesh.clear_surfaces()
	
	# Get unique snapped vertices for current position
	var snapped_vertices = _get_unique_snapped_vertices()
	
	# Recreate mesh with updated vertices
	_create_convex_mesh(snapped_vertices)
	
	# Update collision shape
	_update_collision_shape()
