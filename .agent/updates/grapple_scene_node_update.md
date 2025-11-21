# Grapple Hook Updates

## Summary
Updated the GrappleHook to have a visual node for the hit target in its scene (instead of just creating it in script), and changed it to use FREE_GRAB mode to work like other grabbables with physics hand collision.

## Changes Made

### 1. GrappleHook.tscn
- Added `HitTargetMarker` Node3D with a `MarkerMesh` MeshInstance3D child
- The hitmarker is now a proper scene node that can be edited in the Godot editor
- Added SphereMesh and StandardMaterial3D resources for the hitmarker visual
- Added `grabbable` group and proper mass (0.5) to the root RigidBody3D node

### 2. GrappleHook.gd
- Changed default `grab_mode` from `ANCHOR_GRAB` to `FREE_GRAB`
  - This makes the grapple work more naturally like other grabbables
  - Physics hand collision now works properly for grabbing
- Updated `_ready()` to get the hitmarker from the scene instead of creating it programmatically
- Updated `_attach_visuals_to_root()` to skip reparenting the scene-based hitmarker
- Updated `_ensure_visuals_parent()` to skip reparenting the scene-based hitmarker
- Updated `_exit_tree()` to just hide the hitmarker instead of queue_free (since it's a scene node)

## Benefits

1. **Scene-Based Hitmarker**: The hit target marker is now a proper scene node that can be:
   - Edited visually in the Godot editor
   - Modified without touching code
   - Easily customized per instance

2. **Free Grab Mode**: The grapple now uses FREE_GRAB by default, which:
   - Feels more natural when picking up
   - Works properly with physics hand collision detection
   - Allows the player to grab it from any angle
   - Matches the behavior of other grabbable objects

3. **Consistency**: The grapple now behaves like other grabbables (GrabbableBall, GrabbableCube, etc.)

## Testing
To test the changes:
1. Open the GrappleScene (src/levels/GrappleScene.tscn)
2. Run the scene and try to grab the grapple hook with the VR controllers
3. Verify that the hitmarker appears when aiming at surfaces
4. Verify that the grapple can be picked up freely from any angle
5. Test the grapple functionality (shooting, winching, rope visuals)
