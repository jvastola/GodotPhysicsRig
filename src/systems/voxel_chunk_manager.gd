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

# Network sync
var network_manager: Node = null
var nakama_manager: Node = null

# Batching
var _voxel_queue: Array = [] # Array of {type: 0/1, pos: Vector3, color: Color}
var _batch_timer: float = 0.0
const BATCH_INTERVAL: float = 0.05 # 50ms
const MAX_BATCH_SIZE: int = 20

signal chunk_updated(chunk_coord: Vector3i)
signal voxel_placed(world_pos: Vector3, color: Color)
signal voxel_removed(world_pos: Vector3)

class VoxelData:
	var color: Color = Color.WHITE
	var texture: ImageTexture = null
	var face_colors: Array = []  # Optional: per-face color data for texture generation
	var grid_subdivisions: int = 1
	
	func _init(c: Color = Color.WHITE, tex: ImageTexture = null):
		color = c
		texture = tex

class VoxelChunk:
	var coord: Vector3i  # Chunk coordinate
	var voxels: Dictionary = {}  # Vector3i (local voxel pos) -> VoxelData
	var mesh_instance: MeshInstance3D = null
	var static_body: StaticBody3D = null
	var collision_shape: CollisionShape3D = null
	var dirty: bool = true
	
	func _init(chunk_coord: Vector3i):
		coord = chunk_coord

func _ready() -> void:
	# Setup network sync
	network_manager = get_node_or_null("/root/NetworkManager")
	nakama_manager = get_node_or_null("/root/NakamaManager")
	
	if network_manager:
		# Connect to receive voxel updates from network
		if network_manager.has_signal("voxel_placed_network"):
			network_manager.voxel_placed_network.connect(_on_network_voxel_placed)
		if network_manager.has_signal("voxel_removed_network"):
			network_manager.voxel_removed_network.connect(_on_network_voxel_removed)
	
	set_process(false)

func _process(delta: float) -> void:
	if _voxel_queue.size() > 0:
		_batch_timer += delta
		if _batch_timer >= BATCH_INTERVAL or _voxel_queue.size() >= MAX_BATCH_SIZE:
			_flush_voxel_queue()

## Set the size of individual voxels
func set_voxel_size(size: float) -> void:
	_voxel_size = size

## Add a voxel at world position with optional texture
func add_voxel(world_pos: Vector3, color: Color = Color.WHITE, sync_network: bool = true, texture: ImageTexture = null, face_colors: Array = [], grid_subdivisions: int = 1) -> void:
	var chunk_coord := world_to_chunk(world_pos)
	var local_pos := world_to_local_voxel(world_pos, chunk_coord)
	
	var chunk := _get_or_create_chunk(chunk_coord)
	var voxel_data := VoxelData.new(color, texture)
	voxel_data.face_colors = face_colors
	voxel_data.grid_subdivisions = grid_subdivisions
	
	if not chunk.voxels.has(local_pos):
		chunk.voxels[local_pos] = voxel_data
		chunk.dirty = true
		_mark_neighbors_dirty(chunk_coord, local_pos)
	else:
		# Update if voxel already exists
		chunk.voxels[local_pos] = voxel_data
		chunk.dirty = true
	
	# Sync to network
	if sync_network:
		if network_manager and network_manager.get("use_nakama") and nakama_manager:
			# Queue for Nakama batching
			_queue_voxel_update(0, world_pos, color)
		elif network_manager and network_manager.has_method("sync_voxel_placed"):
			# Send via ENet
			network_manager.sync_voxel_placed(world_pos, color)
	
	voxel_placed.emit(world_pos, color)

## Remove a voxel at world position
func remove_voxel(world_pos: Vector3, sync_network: bool = true) -> void:
	var chunk_coord := world_to_chunk(world_pos)
	var local_pos := world_to_local_voxel(world_pos, chunk_coord)
	
	if not _chunks.has(chunk_coord):
		return
	
	var chunk: VoxelChunk = _chunks[chunk_coord]
	if chunk.voxels.erase(local_pos):
		chunk.dirty = true
		_mark_neighbors_dirty(chunk_coord, local_pos)
		
		# Sync to network
		if sync_network:
			if network_manager and network_manager.get("use_nakama") and nakama_manager:
				# Queue for Nakama batching
				_queue_voxel_update(1, world_pos)
			elif network_manager and network_manager.has_method("sync_voxel_removed"):
				# Send via ENet
				network_manager.sync_voxel_removed(world_pos)
		
		voxel_removed.emit(world_pos)
		
		# Remove chunk if empty
		if chunk.voxels.is_empty():
			_remove_chunk(chunk_coord)


## Handle voxel placement from network (don't re-sync)
func _on_network_voxel_placed(world_pos: Vector3, color: Color) -> void:
	add_voxel(world_pos, color, false)


## Handle voxel removal from network (don't re-sync)
func _on_network_voxel_removed(world_pos: Vector3) -> void:
	remove_voxel(world_pos, false)


## Get all voxel positions (for syncing to new clients)
func get_all_voxels() -> Array[Dictionary]:
	var all_voxels: Array[Dictionary] = []
	for chunk_coord in _chunks.keys():
		var chunk: VoxelChunk = _chunks[chunk_coord]
		for local_pos in chunk.voxels.keys():
			var world_pos = local_to_world_voxel(local_pos, chunk_coord)
			var voxel_data: VoxelData = chunk.voxels.get(local_pos)
			var stored_color: Color = voxel_data.color if voxel_data else Color.WHITE
			all_voxels.append({"pos": world_pos, "color": stored_color})
	return all_voxels


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


## Convert local voxel position within a chunk to world position (convenience wrapper)
func local_to_world_voxel(local_pos: Vector3i, chunk_coord: Vector3i) -> Vector3:
	# Keep parameter order consistent with existing calls that pass local_pos, chunk_coord
	return chunk_local_to_world(chunk_coord, local_pos)

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
	
	# Group voxels by texture for efficient rendering
	var textured_voxels: Dictionary = {}  # texture_id -> Array of {local_pos, voxel_data}
	var colored_voxels: Array = []  # Voxels without textures
	
	for local_pos in chunk.voxels.keys():
		var voxel_data: VoxelData = chunk.voxels[local_pos]
		if voxel_data.texture:
			var tex_id := voxel_data.texture.get_rid().get_id()
			if not textured_voxels.has(tex_id):
				textured_voxels[tex_id] = {"texture": voxel_data.texture, "voxels": []}
			textured_voxels[tex_id]["voxels"].append({"pos": local_pos, "data": voxel_data})
		else:
			colored_voxels.append({"pos": local_pos, "data": voxel_data})
	
	var array_mesh := ArrayMesh.new()
	var collision_faces: PackedVector3Array = PackedVector3Array()
	
	# Add surfaces for each texture group
	for tex_id in textured_voxels.keys():
		var tex_group: Dictionary = textured_voxels[tex_id]
		var mesh_data := _generate_textured_mesh(chunk, tex_group["voxels"])
		if mesh_data.visual_arrays[Mesh.ARRAY_VERTEX].size() > 0:
			var surface_idx := array_mesh.get_surface_count()
			array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_data.visual_arrays)
			
			# Create material with texture
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = tex_group["texture"]
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mat.cull_mode = BaseMaterial3D.CULL_BACK
			array_mesh.surface_set_material(surface_idx, mat)
			
			collision_faces.append_array(mesh_data.collision_faces)
	
	# Add surface for colored voxels (no texture)
	if colored_voxels.size() > 0:
		var mesh_data := _generate_colored_mesh(chunk, colored_voxels)
		if mesh_data.visual_arrays[Mesh.ARRAY_VERTEX].size() > 0:
			var surface_idx := array_mesh.get_surface_count()
			array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_data.visual_arrays)
			
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.cull_mode = BaseMaterial3D.CULL_BACK
			array_mesh.surface_set_material(surface_idx, mat)
			
			collision_faces.append_array(mesh_data.collision_faces)
	
	chunk.mesh_instance.mesh = array_mesh
	chunk.mesh_instance.material_override = null  # Use per-surface materials
	
	# Create collision shape from mesh
	if collision_faces.size() > 0:
		var collision_mesh := ConcavePolygonShape3D.new()
		collision_mesh.set_faces(collision_faces)
		chunk.collision_shape.shape = collision_mesh
	else:
		chunk.collision_shape.shape = null

## Generate mesh data for textured voxels with UV coordinates
## Uses the same atlas layout as ReferenceBlock: 3x2 grid (faces 0-2 on top row, 3-5 on bottom)
func _generate_textured_mesh(chunk: VoxelChunk, voxel_list: Array) -> Dictionary:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var collision_faces: PackedVector3Array = PackedVector3Array()
	
	var vertex_offset: int = 0
	var chunk_world_origin := Vector3(chunk.coord) * CHUNK_SIZE * _voxel_size
	
	# UV coordinates for each face in the 3x2 atlas
	# Face 0 (+X): column 0, row 0
	# Face 1 (-X): column 1, row 0
	# Face 2 (+Y): column 2, row 0
	# Face 3 (-Y): column 0, row 1
	# Face 4 (+Z): column 1, row 1
	# Face 5 (-Z): column 2, row 1
	
	for voxel_entry in voxel_list:
		var local_pos: Vector3i = voxel_entry["pos"]
		var voxel_world_pos := chunk_world_origin + Vector3(local_pos) * _voxel_size
		var voxel_offset := Vector3(-0.5, -0.5, -0.5) * _voxel_size
		
		for face_idx in range(6):
			var face_dir := VOXEL_FACES[face_idx]
			var neighbor_pos: Vector3i = local_pos + face_dir
			
			if _is_voxel_occupied_with_neighbors(chunk, neighbor_pos):
				continue
			
			var face_verts := FACE_VERTICES[face_idx]
			var face_normal := Vector3(face_dir)
			
			# Calculate UV coordinates for this face in the atlas
			var atlas_col := face_idx % 3
			var atlas_row := int(face_idx / 3.0)
			var u0 := float(atlas_col) / 3.0
			var v0 := float(atlas_row) / 2.0
			var u1 := float(atlas_col + 1) / 3.0
			var v1 := float(atlas_row + 1) / 2.0
			
			# UV corners for the face (matching vertex order)
			var face_uvs := [
				Vector2(u0, v1),  # bottom-left
				Vector2(u1, v1),  # bottom-right
				Vector2(u1, v0),  # top-right
				Vector2(u0, v0)   # top-left
			]
			
			for i in range(4):
				var vert: Vector3 = voxel_world_pos + voxel_offset + face_verts[i] * _voxel_size
				vertices.append(vert)
				normals.append(face_normal)
				uvs.append(face_uvs[i])
			
			indices.append(vertex_offset + 0)
			indices.append(vertex_offset + 1)
			indices.append(vertex_offset + 2)
			indices.append(vertex_offset + 0)
			indices.append(vertex_offset + 2)
			indices.append(vertex_offset + 3)
			
			collision_faces.append(vertices[vertex_offset + 0])
			collision_faces.append(vertices[vertex_offset + 1])
			collision_faces.append(vertices[vertex_offset + 2])
			collision_faces.append(vertices[vertex_offset + 0])
			collision_faces.append(vertices[vertex_offset + 2])
			collision_faces.append(vertices[vertex_offset + 3])
			
			vertex_offset += 4
	
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	
	return {"visual_arrays": arrays, "collision_faces": collision_faces}


## Generate mesh data for colored voxels (no texture, uses vertex colors)
func _generate_colored_mesh(chunk: VoxelChunk, voxel_list: Array) -> Dictionary:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var collision_faces: PackedVector3Array = PackedVector3Array()
	
	var vertex_offset: int = 0
	var chunk_world_origin := Vector3(chunk.coord) * CHUNK_SIZE * _voxel_size
	
	for voxel_entry in voxel_list:
		var local_pos: Vector3i = voxel_entry["pos"]
		var voxel_data: VoxelData = voxel_entry["data"]
		var voxel_color: Color = voxel_data.color
		var voxel_world_pos := chunk_world_origin + Vector3(local_pos) * _voxel_size
		var voxel_offset := Vector3(-0.5, -0.5, -0.5) * _voxel_size
		
		for face_idx in range(6):
			var face_dir := VOXEL_FACES[face_idx]
			var neighbor_pos: Vector3i = local_pos + face_dir
			
			if _is_voxel_occupied_with_neighbors(chunk, neighbor_pos):
				continue
			
			var face_verts := FACE_VERTICES[face_idx]
			var face_normal := Vector3(face_dir)
			
			for i in range(4):
				var vert: Vector3 = voxel_world_pos + voxel_offset + face_verts[i] * _voxel_size
				vertices.append(vert)
				normals.append(face_normal)
				colors.append(voxel_color)
			
			indices.append(vertex_offset + 0)
			indices.append(vertex_offset + 1)
			indices.append(vertex_offset + 2)
			indices.append(vertex_offset + 0)
			indices.append(vertex_offset + 2)
			indices.append(vertex_offset + 3)
			
			collision_faces.append(vertices[vertex_offset + 0])
			collision_faces.append(vertices[vertex_offset + 1])
			collision_faces.append(vertices[vertex_offset + 2])
			collision_faces.append(vertices[vertex_offset + 0])
			collision_faces.append(vertices[vertex_offset + 2])
			collision_faces.append(vertices[vertex_offset + 3])
			
			vertex_offset += 4
	
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	
	return {"visual_arrays": arrays, "collision_faces": collision_faces}

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


func _queue_voxel_update(type: int, pos: Vector3, color: Color = Color.WHITE) -> void:
	_voxel_queue.append({
		"t": type,
		"p": pos,
		"c": color
	})
	set_process(true)


func _flush_voxel_queue() -> void:
	if _voxel_queue.is_empty() or not nakama_manager:
		return
		
	# Send batch
	nakama_manager.send_match_state(
		8, # VOXEL_BATCH
		{"updates": _voxel_queue.duplicate()}
	)
	
	_voxel_queue.clear()
	_batch_timer = 0.0
	set_process(false)
