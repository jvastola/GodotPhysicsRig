# Instructions for adding VoxelChunkManager to XRPlayer.tscn

## Manual Setup (Godot Editor)

1. Open `XRPlayer.tscn` in the Godot editor
2. Right-click on the root `XRPlayer` node
3. Select "Add Child Node"
4. Search for "Node" and add it
5. Rename the new node to "VoxelChunkManager"
6. In the Inspector, click the script icon and select "Load"
7. Navigate to `voxel_chunk_manager.gd` and load it
8. Select the `GridSnapIndicator` node (under LeftController/HandPointer)
9. In the Inspector, enable `Use Voxel Chunks`
10. Set `Voxel Chunk Manager Path` to `../../../../../VoxelChunkManager`
11. Save the scene (Ctrl+S)

## Alternative: Scene Code Structure

Add this to XRPlayer.tscn after the BuildRoot node:

```
[node name="VoxelChunkManager" type="Node" parent="."]
script = ExtResource("10_voxel_manager")
```

And add this to the ext_resource list at the top:
```
[ext_resource type="Script" path="res://voxel_chunk_manager.gd" id="10_voxel_manager"]
```

Then update the GridSnapIndicator node configuration:
```
[node name="GridSnapIndicator" type="Node3D" parent="PlayerBody/XROrigin3D/LeftController/HandPointer"]
script = ExtResource("8_grid_snap")
follow_mode = "always"
maintain_visibility_without_hit = true
pointer_node_path = NodePath("..")
build_cube_scene = ExtResource("9_build_cube")
build_parent_path = NodePath("../../../../../BuildRoot")
raycast_path = NodePath("../PointerRayCast")
hide_without_hit = false
use_voxel_chunks = true
voxel_chunk_manager_path = NodePath("../../../../../VoxelChunkManager")
```

## Verification

After setup, run the game and check the console output:
- You should see: "GridSnapIndicator: Using voxel chunk system"
- When placing blocks, you should see: "GridSnapIndicator: Added voxel at (x, y, z)"
- Blocks should appear as optimized merged meshes in chunks

## Testing

1. Place several blocks in a small area
2. Notice they merge into a single mesh with shared faces removed
3. Place blocks across chunk boundaries (every 32 units)
4. Observe new chunks being created automatically
5. Check collision - you should be able to walk on the voxel structures
