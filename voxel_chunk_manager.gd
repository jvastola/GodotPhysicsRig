extends Node
class_name VoxelChunkManager

## Manages voxel chunks in 32x32x32 world-space units
## Generates optimized mesh colliders with internal faces removed

const CHUNK_SIZE: int = 32
const VOXEL_FACES: Array[Vector3i] = [
	Vector3i(1, 0, 0),   # +X
	Vector3i(-1, 0, 0),  # -X
	Vector3i(0, 1, 0),   # +Y
	Vector3i(0, -1, 0),  # -Y
	Vector3i(0, 0, 1),   # +Z
	Vector3i(0, 0, -1)   # -Z
]

# Face vertices for each direction (counter-clockwise when viewed from outside)
const FACE_VERTICES: Array[Array] = [
	# +X face (right)
	[Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
	# -X face (left)
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1)],
	# +Y face (top)
	[Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	# -Y face (bottom)
	[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0)],
	# +Z face (front)
	[Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	# -Z face (back)
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)]
]

# Dictionary of chunks: Vector3i (chunk coord) -> VoxelChunk
var _chunks: Dictionary = {}

# Voxel grid size (size of each individual voxel cube)
var _voxel_size: float = 1.0

signal chunk_updated(chunk_coord: Vector3i)

class VoxelChunk:
	var coord: Vector3i  # Chunk coordinate
	var voxels: Dictionary = {}  # Vector3i (local voxel pos) -> bool (occupied)
	var mesh_instance: MeshInstance3D = null
	var static_body: StaticBody3D = null
	var collision_shape: CollisionShape3D = null
	var dirty: bool = true
	
	func _init(chunk_coord: Vector3i):
		coord = chunk_coord

func _ready() -> void:
	pass

## Set the size of individual voxels
func set_voxel_size(size: float) -> void:
	_voxel_size = size

## Add a voxel at world position
func add_voxel(world_pos: Vector3) -> void:
	var chunk_coord := world_to_chunk(world_pos)
	var local_pos := world_to_local_voxel(world_pos, chunk_coord)
	
	var chunk := _get_or_create_chunk(chunk_coord)
	if not chunk.voxels.has(local_pos):
		chunk.voxels[local_pos] = true
		chunk.dirty = true
		_mark_neighbors_dirty(chunk_coord, local_pos)

## Remove a voxel at world position
func remove_voxel(world_pos: Vector3) -> void:
	var chunk_coord := world_to_chunk(world_pos)
	var local_pos := world_to_local_voxel(world_pos, chunk_coord)
	
	if not _chunks.has(chunk_coord):
		return
	
	var chunk: VoxelChunk = _chunks[chunk_coord]
	if chunk.voxels.erase(local_pos):
		chunk.dirty = true
		_mark_neighbors_dirty(chunk_coord, local_pos)
		
		# Remove chunk if empty
		if chunk.voxels.is_empty():
			_remove_chunk(chunk_coord)

## Check if a voxel exists at world position
func has_voxel(world_pos: Vector3) -> bool:
	var chunk_coord := world_to_chunk(world_pos)
	var local_pos := world_to_local_voxel(world_pos, chunk_coord)
	
	if not _chunks.has(chunk_coord):
		return false
	
	var chunk: VoxelChunk = _chunks[chunk_coord]
	return chunk.voxels.has(local_pos)

## Update all dirty chunks (regenerate meshes and colliders)
func update_dirty_chunks() -> void:
	for chunk_coord in _chunks.keys():
		var chunk: VoxelChunk = _chunks[chunk_coord]
		if chunk.dirty:
			_rebuild_chunk_mesh(chunk)
			chunk.dirty = false
			chunk_updated.emit(chunk_coord)

## Force rebuild of a specific chunk
func rebuild_chunk(chunk_coord: Vector3i) -> void:
	if not _chunks.has(chunk_coord):
		return
	var chunk: VoxelChunk = _chunks[chunk_coord]
	_rebuild_chunk_mesh(chunk)
	chunk.dirty = false

## Convert world position to chunk coordinate
func world_to_chunk(world_pos: Vector3) -> Vector3i:
	var scaled_pos := world_pos / _voxel_size
	return Vector3i(
		floori(scaled_pos.x / CHUNK_SIZE),
		floori(scaled_pos.y / CHUNK_SIZE),
		floori(scaled_pos.z / CHUNK_SIZE)
	)

## Convert world position to local voxel position within chunk
func world_to_local_voxel(world_pos: Vector3, chunk_coord: Vector3i) -> Vector3i:
	var scaled_pos := world_pos / _voxel_size
	var chunk_origin := Vector3(chunk_coord) * CHUNK_SIZE
	var local_pos := scaled_pos - chunk_origin
	return Vector3i(
		int(floorf(local_pos.x + 0.5)),
		int(floorf(local_pos.y + 0.5)),
		int(floorf(local_pos.z + 0.5))
	)

## Convert chunk coordinate and local position to world position
func chunk_local_to_world(chunk_coord: Vector3i, local_pos: Vector3i) -> Vector3:
	var chunk_origin := Vector3(chunk_coord) * CHUNK_SIZE
	var world_voxel := (chunk_origin + Vector3(local_pos)) * _voxel_size
	return world_voxel + Vector3.ONE * _voxel_size * 0.5  # Center of voxel

## Get or create a chunk at the given coordinate
func _get_or_create_chunk(chunk_coord: Vector3i) -> VoxelChunk:
	if _chunks.has(chunk_coord):
		return _chunks[chunk_coord]
	
	var chunk := VoxelChunk.new(chunk_coord)
	_chunks[chunk_coord] = chunk
	
	# Create visual and collision nodes
	chunk.static_body = StaticBody3D.new()
	chunk.static_body.name = "VoxelChunk_%d_%d_%d" % [chunk_coord.x, chunk_coord.y, chunk_coord.z]
	chunk.static_body.collision_layer = 33  # World layer (1) + Pointer layer (32, which is bit 5)
	chunk.static_body.collision_mask = 0
	add_child(chunk.static_body)
	
	chunk.mesh_instance = MeshInstance3D.new()
	chunk.mesh_instance.name = "Mesh"
	chunk.static_body.add_child(chunk.mesh_instance)
	
	chunk.collision_shape = CollisionShape3D.new()
	chunk.collision_shape.name = "CollisionShape"
	chunk.static_body.add_child(chunk.collision_shape)
	
	return chunk

## Remove a chunk
func _remove_chunk(chunk_coord: Vector3i) -> void:
	if not _chunks.has(chunk_coord):
		return
	
	var chunk: VoxelChunk = _chunks[chunk_coord]
	if chunk.static_body:
		chunk.static_body.queue_free()
	
	_chunks.erase(chunk_coord)

## Mark neighboring chunks as dirty if voxel is on chunk boundary
func _mark_neighbors_dirty(chunk_coord: Vector3i, local_pos: Vector3i) -> void:
	# Check if voxel is on chunk boundary
	for i in range(6):
		var face_dir := VOXEL_FACES[i]
		var neighbor_local := local_pos + face_dir
		
		# Check if neighbor is in a different chunk
		var neighbor_chunk_coord := chunk_coord
		if neighbor_local.x < 0:
			neighbor_chunk_coord.x -= 1
		elif neighbor_local.x >= CHUNK_SIZE:
			neighbor_chunk_coord.x += 1
		elif neighbor_local.y < 0:
			neighbor_chunk_coord.y -= 1
		elif neighbor_local.y >= CHUNK_SIZE:
			neighbor_chunk_coord.y += 1
		elif neighbor_local.z < 0:
			neighbor_chunk_coord.z -= 1
		elif neighbor_local.z >= CHUNK_SIZE:
			neighbor_chunk_coord.z += 1
		
		if neighbor_chunk_coord != chunk_coord and _chunks.has(neighbor_chunk_coord):
			_chunks[neighbor_chunk_coord].dirty = true

## Rebuild mesh and collider for a chunk
func _rebuild_chunk_mesh(chunk: VoxelChunk) -> void:
	if chunk.voxels.is_empty():
		# Clear mesh and collider
		chunk.mesh_instance.mesh = null
		chunk.collision_shape.shape = null
		return
	
	# Generate optimized mesh with greedy meshing
	var mesh_data := _generate_chunk_mesh(chunk)
	
	# Create visual mesh
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_data.visual_arrays)
	chunk.mesh_instance.mesh = array_mesh
	
	# Apply material if not already set
	if not chunk.mesh_instance.material_override:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.7, 0.7, 0.7)
		mat.cull_mode = BaseMaterial3D.CULL_BACK  # Enable backface culling
		chunk.mesh_instance.material_override = mat
	
	# Create collision shape from mesh
	var collision_mesh := ConcavePolygonShape3D.new()
	collision_mesh.set_faces(mesh_data.collision_faces)
	chunk.collision_shape.shape = collision_mesh

## Generate mesh data for a chunk with internal face culling
func _generate_chunk_mesh(chunk: VoxelChunk) -> Dictionary:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var collision_faces: PackedVector3Array = PackedVector3Array()
	
	var vertex_offset: int = 0
	var chunk_world_origin := Vector3(chunk.coord) * CHUNK_SIZE * _voxel_size
	
	# Iterate through all voxels in chunk
	for local_pos in chunk.voxels.keys():
		# Calculate voxel center position (offset by half voxel size to center on grid)
		var voxel_world_pos := chunk_world_origin + Vector3(local_pos) * _voxel_size
		var voxel_offset := Vector3(-0.5, -0.5, -0.5) * _voxel_size  # Center the cube
		
		# Check each face direction
		for face_idx in range(6):
			var face_dir := VOXEL_FACES[face_idx]
			var neighbor_pos: Vector3i = local_pos + face_dir
			
			# Check if neighbor is occupied (with chunk boundary handling)
			if _is_voxel_occupied_with_neighbors(chunk, neighbor_pos):
				continue  # Internal face, skip it
			
			# Add face geometry
			var face_verts := FACE_VERTICES[face_idx]
			var face_normal := Vector3(face_dir)
			
			# Add 4 vertices for this face
			for i in range(4):
				var vert: Vector3 = voxel_world_pos + voxel_offset + face_verts[i] * _voxel_size
				vertices.append(vert)
				normals.append(face_normal)
			
			# Add 2 triangles (6 indices) for this face
			indices.append(vertex_offset + 0)
			indices.append(vertex_offset + 1)
			indices.append(vertex_offset + 2)
			
			indices.append(vertex_offset + 0)
			indices.append(vertex_offset + 2)
			indices.append(vertex_offset + 3)
			
			# Add collision triangles
			collision_faces.append(vertices[vertex_offset + 0])
			collision_faces.append(vertices[vertex_offset + 1])
			collision_faces.append(vertices[vertex_offset + 2])
			
			collision_faces.append(vertices[vertex_offset + 0])
			collision_faces.append(vertices[vertex_offset + 2])
			collision_faces.append(vertices[vertex_offset + 3])
			
			vertex_offset += 4
	
	# Build mesh arrays
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	
	return {
		"visual_arrays": arrays,
		"collision_faces": collision_faces
	}

## Check if a voxel position is occupied (handles chunk boundaries)
func _is_voxel_occupied_with_neighbors(chunk: VoxelChunk, local_pos: Vector3i) -> bool:
	# Check if within current chunk bounds
	if local_pos.x >= 0 and local_pos.x < CHUNK_SIZE and \
	   local_pos.y >= 0 and local_pos.y < CHUNK_SIZE and \
	   local_pos.z >= 0 and local_pos.z < CHUNK_SIZE:
		return chunk.voxels.has(local_pos)
	
	# Outside current chunk, check neighbor chunk
	var neighbor_chunk_coord := chunk.coord
	var neighbor_local := local_pos
	
	if local_pos.x < 0:
		neighbor_chunk_coord.x -= 1
		neighbor_local.x += CHUNK_SIZE
	elif local_pos.x >= CHUNK_SIZE:
		neighbor_chunk_coord.x += 1
		neighbor_local.x -= CHUNK_SIZE
	
	if local_pos.y < 0:
		neighbor_chunk_coord.y -= 1
		neighbor_local.y += CHUNK_SIZE
	elif local_pos.y >= CHUNK_SIZE:
		neighbor_chunk_coord.y += 1
		neighbor_local.y -= CHUNK_SIZE
	
	if local_pos.z < 0:
		neighbor_chunk_coord.z -= 1
		neighbor_local.z += CHUNK_SIZE
	elif local_pos.z >= CHUNK_SIZE:
		neighbor_chunk_coord.z += 1
		neighbor_local.z -= CHUNK_SIZE
	
	if not _chunks.has(neighbor_chunk_coord):
		return false
	
	var neighbor_chunk: VoxelChunk = _chunks[neighbor_chunk_coord]
	return neighbor_chunk.voxels.has(neighbor_local)

## Get chunk statistics
func get_stats() -> Dictionary:
	var total_voxels := 0
	var total_chunks := _chunks.size()
	
	for chunk_coord in _chunks.keys():
		var chunk: VoxelChunk = _chunks[chunk_coord]
		total_voxels += chunk.voxels.size()
	
	return {
		"chunks": total_chunks,
		"voxels": total_voxels,
		"avg_voxels_per_chunk": float(total_voxels) / max(total_chunks, 1)
	}
