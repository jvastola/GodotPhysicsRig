# Optimized Voxel Building System

## 🎯 Overview

This system transforms individual cube spawning into an optimized voxel-based chunk system with intelligent mesh generation and collision handling. Instead of creating thousands of individual StaticBody3D nodes, voxels are organized into 32×32×32 world-space chunks with merged meshes and culled internal faces.

## 📊 Performance Benefits

### Node Count Reduction
- **Before**: 1000 cubes = 3000 nodes (StaticBody3D + MeshInstance3D + CollisionShape3D each)
- **After**: 1000 voxels ≈ 3-10 nodes depending on distribution (99.7%+ reduction)

### Memory & Physics
- Single collision mesh per chunk instead of per-voxel
- Internal faces removed (only external surfaces rendered/collided)
- Automatic chunk cleanup when empty
- Dirty-flag system prevents unnecessary rebuilds

## 🏗️ Architecture

### Core Components

1. **VoxelChunkManager** (`voxel_chunk_manager.gd`)
   - Manages all chunks and voxel data
   - Handles coordinate conversion (world ↔ chunk ↔ local)
   - Generates optimized meshes with face culling
   - Creates efficient collision shapes

2. **VoxelChunk** (inner class)
   - Stores voxel data for one 32³ region
   - Maintains mesh and collision nodes
   - Tracks dirty state for rebuild optimization

3. **GridSnapIndicator** (enhanced)
   - Integrates with voxel system
   - Falls back to traditional cubes if disabled
   - Supports both add and remove operations

## 🚀 Quick Start

### Method 1: Automatic Setup

1. Open Godot editor
2. Go to **Editor → Run Script**
3. Select `setup_voxel_system.gd`
4. Click **Run**
5. Restart the scene

### Method 2: Manual Setup

1. Open `XRPlayer.tscn`
2. Add a **Node** as child of root
3. Rename it to `VoxelChunkManager`
4. Attach `voxel_chunk_manager.gd` script
5. Select `GridSnapIndicator` node
6. In Inspector:
   - ✅ Enable `Use Voxel Chunks`
   - Set `Voxel Chunk Manager Path` to `../../../../../VoxelChunkManager`
7. Save scene

## 🎮 Controls

- **Trigger**: Place voxel
- **Grip + Trigger**: Remove voxel (new!)
- Grid snapping automatically aligns placement

## 📝 Key Features

### Intelligent Face Culling
Only external faces are rendered and collided:
```
Before:           After:
█ █ █            ███
█ █ █     →      ███  (hollow inside)
█ █ █            ███
```

### Cross-Chunk Boundaries
Voxels at chunk edges correctly cull faces with neighbors in adjacent chunks:
```
Chunk A | Chunk B
   █ █ | █ █
   █ █ | █ █   → Seamless, no gaps
```

### Automatic Chunk Management
- Chunks created on-demand when first voxel added
- Chunks deleted when last voxel removed
- Adjacent chunks marked dirty for boundary updates

## 💻 API Usage

### Basic Operations
```gdscript
# Get manager reference
var voxel_manager = $VoxelChunkManager

# Add voxels
voxel_manager.add_voxel(Vector3(10, 0, 5))
voxel_manager.add_voxel(Vector3(10, 1, 5))

# Remove voxels
voxel_manager.remove_voxel(Vector3(10, 0, 5))

# Batch operations
for pos in voxel_positions:
    voxel_manager.add_voxel(pos)
voxel_manager.update_dirty_chunks()  # Rebuild once at end

# Query
if voxel_manager.has_voxel(some_position):
    print("Voxel exists!")

# Statistics
var stats = voxel_manager.get_stats()
print("Chunks: ", stats.chunks)
print("Total voxels: ", stats.voxels)
```

### Coordinate Conversion
```gdscript
# World position to chunk coordinate
var chunk_coord = voxel_manager.world_to_chunk(world_pos)

# World position to local voxel in chunk
var local_pos = voxel_manager.world_to_local_voxel(world_pos, chunk_coord)

# Back to world position
var world_pos = voxel_manager.chunk_local_to_world(chunk_coord, local_pos)
```

## 🔧 Configuration

### VoxelChunkManager Properties
- `CHUNK_SIZE`: Chunk dimension (32 by default)
- Voxel size set via `set_voxel_size()`

### GridSnapIndicator Properties
- `use_voxel_chunks`: Enable voxel system
- `voxel_chunk_manager_path`: Path to manager node
- `grid_size`: Size of placement grid
- `build_scale_multiplier`: Scale factor for voxels

## 📈 Debug Overlay

Add real-time statistics to your scene:

```gdscript
# Add voxel_debug_overlay.gd to a Control node
var overlay = Control.new()
overlay.set_script(load("res://voxel_debug_overlay.gd"))
add_child(overlay)
```

Shows:
- Active chunk count
- Total voxel count
- Average voxels per chunk
- Node count comparison
- Memory reduction percentage

## 🧪 Testing

1. **Basic Placement**: Add several blocks in a line
2. **Internal Culling**: Place 3×3×3 cube, verify hollow interior
3. **Chunk Boundaries**: Place blocks at x/y/z = 32, 64, etc.
4. **Removal**: Hold grip and trigger to remove blocks
5. **Performance**: Place 1000+ blocks, check FPS

## 🔍 Technical Details

### Mesh Generation Algorithm
```
For each voxel in chunk:
    For each face direction (±X, ±Y, ±Z):
        Calculate neighbor position
        If neighbor in same chunk:
            Check chunk.voxels dictionary
        Else:
            Get neighbor chunk
            Check neighbor chunk's dictionary
        If no neighbor voxel:
            Generate face vertices (4 verts, 2 tris)
            Add to mesh arrays
            Add to collision arrays
```

### Collision Shape
- Uses `ConcavePolygonShape3D` for complex geometry
- Built from same face list as visual mesh
- Automatically updates when chunk modified
- Much faster than individual box colliders

### Memory Layout
```
VoxelChunkManager
├─ _chunks: Dictionary
│  └─ Vector3i(x,y,z) → VoxelChunk
│     ├─ coord: Vector3i
│     ├─ voxels: Dictionary
│     │  └─ Vector3i(x,y,z) → true
│     ├─ static_body: StaticBody3D
│     │  ├─ mesh_instance: MeshInstance3D
│     │  └─ collision_shape: CollisionShape3D
│     └─ dirty: bool
```

## 📚 File Reference

- `voxel_chunk_manager.gd` - Core voxel system
- `grid_snap_indicator.gd` - Enhanced with voxel integration
- `voxel_debug_overlay.gd` - Statistics overlay
- `setup_voxel_system.gd` - Auto-setup script
- `VOXEL_SYSTEM.md` - Detailed documentation
- `VOXEL_SETUP.md` - Setup instructions

## 🚧 Future Enhancements

### Near-term
- [ ] Greedy meshing (merge coplanar faces)
- [ ] Voxel types (different materials/colors)
- [ ] Async mesh generation (threading)

### Long-term  
- [ ] LOD system for distant chunks
- [ ] Serialization (save/load worlds)
- [ ] Ambient occlusion on vertices
- [ ] Network synchronization
- [ ] Lighting/shadows optimization

## ⚠️ Known Limitations

- Chunk size is fixed at compile time (32)
- No greedy meshing yet (each face is separate)
- Removal only works with voxel system enabled
- Single material per chunk

## 🐛 Troubleshooting

**Nothing appears when placing blocks:**
- Check console for "GridSnapIndicator: Using voxel chunk system"
- Verify VoxelChunkManager is in scene tree
- Ensure `use_voxel_chunks` is enabled

**Gaps between voxels:**
- Verify voxel size matches grid size
- Check that face vertices use correct coordinates

**Poor performance:**
- Don't call `update_dirty_chunks()` in tight loops
- Consider async generation for very large structures
- Profile to identify actual bottleneck

**Collision issues:**
- Confirm collision layers (should be layer 1)
- Check that collision shape has valid faces
- Verify StaticBody3D is in correct scene position

## 📄 License

Part of GodotPhysicsRig project.
