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
	var surface_tool = SurfaceTool.new()
	
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Create a convex hull-like structure by connecting center to outer points
	var center_idx = 0
	
	# Build triangles connecting adjacent outer vertices through the center
	for i in range(1, initial_vertices.size()):
		var next_idx = (i % (initial_vertices.size() - 1)) + 1
		
		# Get snapped positions
		var v0 = _snap_vertex_to_grid(initial_vertices[center_idx])
		var v1 = _snap_vertex_to_grid(initial_vertices[i])
		var v2 = _snap_vertex_to_grid(initial_vertices[next_idx])
		
		# Calculate normal for this face
		var edge1 = v1 - v0
		var edge2 = v2 - v0
		var normal = edge1.cross(edge2).normalized()
		
		# Add vertices with UVs and normals
		surface_tool.set_normal(normal)
		surface_tool.set_uv(Vector2(0.5, 0.5))
		surface_tool.add_vertex(v0)
		
		surface_tool.set_normal(normal)
		surface_tool.set_uv(Vector2(0, 0))
		surface_tool.add_vertex(v1)
		
		surface_tool.set_normal(normal)
		surface_tool.set_uv(Vector2(1, 0))
		surface_tool.add_vertex(v2)
	
	# Apply material if available
	if mesh_material:
		surface_tool.set_material(mesh_material)
	
	# Generate normals and tangents (will use the ones we set)
	surface_tool.generate_normals()
	
	# Commit to the mesh
	surface_tool.commit(array_mesh)
	mesh_instance.mesh = array_mesh
	
	# Update collision shape to match mesh
	_update_collision_shape()

func _update_collision_shape() -> void:
	# Find or create collision shape
	var collision_shape = get_node_or_null("CollisionShape3D")
	if not collision_shape:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		add_child(collision_shape)
	
	# Create a convex collision shape from the vertices
	var shape = ConvexPolygonShape3D.new()
	var snapped_points = PackedVector3Array()
	for vertex in initial_vertices:
		snapped_points.append(_snap_vertex_to_grid(vertex))
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
	
	# Recreate the surface with updated vertices
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Create triangles connecting center to outer points
	var center_idx = 0
	
	for i in range(1, initial_vertices.size()):
		var next_idx = (i % (initial_vertices.size() - 1)) + 1
		
		# Get snapped positions
		var v0 = _snap_vertex_to_grid(initial_vertices[center_idx])
		var v1 = _snap_vertex_to_grid(initial_vertices[i])
		var v2 = _snap_vertex_to_grid(initial_vertices[next_idx])
		
		# Calculate normal for this face
		var edge1 = v1 - v0
		var edge2 = v2 - v0
		var normal = edge1.cross(edge2).normalized()
		
		# Add vertices with UVs and normals
		surface_tool.set_normal(normal)
		surface_tool.set_uv(Vector2(0.5, 0.5))
		surface_tool.add_vertex(v0)
		
		surface_tool.set_normal(normal)
		surface_tool.set_uv(Vector2(0, 0))
		surface_tool.add_vertex(v1)
		
		surface_tool.set_normal(normal)
		surface_tool.set_uv(Vector2(1, 0))
		surface_tool.add_vertex(v2)
	
	# Apply material if available
	if mesh_material:
		surface_tool.set_material(mesh_material)
	
	# Generate normals
	surface_tool.generate_normals()
	
	# Commit to the mesh
	surface_tool.commit(array_mesh)
	
	# Update collision shape
	_update_collision_shape()
