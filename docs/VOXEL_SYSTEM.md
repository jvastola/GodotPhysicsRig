# Voxel Chunk System Documentation

## Overview
The voxel chunk system provides optimized mesh generation and collision handling for grid-based building. It groups voxels into 32×32×32 world-space chunks and generates merged mesh colliders with internal face culling for maximum performance.

## Architecture

### VoxelChunkManager (`voxel_chunk_manager.gd`)
Central manager that handles chunk creation, voxel placement, and mesh generation.

**Key Features:**
- **Chunk-based organization**: Divides world into 32×32×32 unit chunks
- **Internal face culling**: Removes faces between adjacent voxels (greedy optimization)
- **Automatic mesh generation**: Rebuilds chunk meshes when voxels are added/removed
- **Efficient collision**: Single ConcavePolygonShape3D per chunk instead of per-voxel
- **Cross-chunk boundary handling**: Correctly handles voxels on chunk edges

### VoxelChunk (Inner Class)
Represents a single chunk containing:
- `coord`: Chunk coordinate in chunk-space
- `voxels`: Dictionary mapping local positions to voxel data
- `mesh_instance`: Visual mesh representation
- `static_body`: Physics body with collision shape
- `dirty`: Flag indicating mesh needs rebuilding

## Usage

### Setup in Scene
1. Add a `VoxelChunkManager` node to your scene (e.g., under XRPlayer or as root child)
2. In `GridSnapIndicator` inspector:
   - Enable `use_voxel_chunks`
   - Set `voxel_chunk_manager_path` to the manager node (or leave empty for auto-find)

### API Reference

#### VoxelChunkManager Methods

```gdscript
# Set the size of individual voxels (default: 1.0)
func set_voxel_size(size: float) -> void

# Add a voxel at world position
func add_voxel(world_pos: Vector3) -> void

# Remove a voxel at world position
func remove_voxel(world_pos: Vector3) -> void

# Check if a voxel exists at world position
func has_voxel(world_pos: Vector3) -> bool

# Update all dirty chunks (call after batch operations)
func update_dirty_chunks() -> void

# Force rebuild of a specific chunk
func rebuild_chunk(chunk_coord: Vector3i) -> void

# Get statistics
func get_stats() -> Dictionary  # Returns: chunks, voxels, avg_voxels_per_chunk
```

#### Coordinate Conversion

```gdscript
# Convert world position to chunk coordinate
func world_to_chunk(world_pos: Vector3) -> Vector3i

# Convert world position to local voxel position within chunk
func world_to_local_voxel(world_pos: Vector3, chunk_coord: Vector3i) -> Vector3i

# Convert chunk coordinate and local position to world position
func chunk_local_to_world(chunk_coord: Vector3i, local_pos: Vector3i) -> Vector3
```

## Performance Characteristics

### Memory Efficiency
- **Individual cubes**: N cubes × (StaticBody3D + CollisionShape3D + MeshInstance3D) = ~3N nodes
- **Voxel chunks**: N voxels / 32768 chunks × 3 nodes = ~N/10922 nodes (99.99% reduction)

### Mesh Generation
- **Face culling**: Only external faces are generated
- **Chunk boundaries**: Correctly handles voxels at chunk edges
- **Dirty tracking**: Only rebuilds modified chunks
- **Batch updates**: Call `update_dirty_chunks()` after multiple adds/removes

### Collision Performance
- Single `ConcavePolygonShape3D` per chunk instead of per-voxel
- Only external faces included in collision mesh
- Automatic cleanup when chunks become empty

## Algorithm Details

### Internal Face Culling
For each voxel, the system checks all 6 neighboring positions:
1. If neighbor is within same chunk → check chunk's voxel dictionary
2. If neighbor is in adjacent chunk → check neighbor chunk's dictionary
3. If neighbor exists → skip face (internal)
4. If neighbor doesn't exist → generate face (external)

### Chunk Boundary Handling
When a voxel is added/removed at a chunk boundary:
1. Mark current chunk as dirty
2. Check if voxel is at boundary (x/y/z = 0 or 31)
3. Mark adjacent chunks as dirty if they exist
4. All affected chunks rebuild on next `update_dirty_chunks()`

### Mesh Generation Process
1. Iterate through all voxels in chunk
2. For each voxel, check all 6 face directions
3. If face is external (no neighbor), add 4 vertices + 2 triangles
4. Build ArrayMesh for rendering
5. Build ConcavePolygonShape3D for collision
6. Assign to chunk's MeshInstance3D and CollisionShape3D

## Integration with GridSnapIndicator

The `GridSnapIndicator` automatically uses the voxel system when:
- `use_voxel_chunks` is enabled
- `VoxelChunkManager` is found in scene

When trigger is pressed:
1. `_spawn_build_cube()` checks if voxel system is enabled
2. Calls `_voxel_manager.add_voxel(spawn_pos)`
3. Calls `_voxel_manager.update_dirty_chunks()`
4. Chunk mesh regenerates with new voxel included

## Future Enhancements

### Potential Optimizations
- **Greedy meshing**: Merge coplanar adjacent faces into larger quads
- **Mesh simplification**: Reduce vertex count for large flat surfaces
- **LOD system**: Multiple detail levels based on distance
- **Async mesh generation**: Build meshes in threads for large chunks
- **Material atlas**: Single texture for all voxel types

### Additional Features
- **Voxel types**: Different materials, colors, or properties per voxel
- **Destruction**: Ray-based voxel removal tool
- **Serialization**: Save/load voxel data to files
- **Networking**: Synchronize voxel changes across clients
- **Lighting**: Baked ambient occlusion for voxel vertices

## Troubleshooting

**Chunks not appearing:**
- Check that `VoxelChunkManager` is in scene tree
- Verify `use_voxel_chunks` is enabled
- Ensure `set_voxel_size()` matches your grid size

**Performance issues:**
- Call `update_dirty_chunks()` once per frame, not per voxel
- Consider async mesh generation for very large chunks
- Profile with Godot's debugger to identify bottlenecks

**Visual artifacts:**
- Verify face vertices are counter-clockwise from outside
- Check normal vectors point outward
- Ensure voxel size matches grid size

**Collision problems:**
- Confirm collision layers are set correctly (default: layer 1)
- Check that `ConcavePolygonShape3D` has valid faces
- Verify chunks are children of manager node
