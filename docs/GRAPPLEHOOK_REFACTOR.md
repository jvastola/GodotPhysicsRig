# GrappleHook Refactor - Composition Pattern

## Problem
The GrappleHook was extending the `Grabbable` class but Godot's parser couldn't resolve the class reference, causing errors:
- `Parser Error: Could not resolve class 'Grabbable'`
- Multiple inheritance approaches failed (class_name, relative paths)
- Likely caused by timing issues with class_name resolution in Godot 4

## Solution: Composition via Flattening
Instead of inheritance, we **flattened the Grabbable functionality directly into GrappleHook**. This creates a self-contained class that doesn't rely on class resolution.

### What Was Changed

#### 1. Changed Inheritance
```gdscript
# BEFORE
extends "../grabbable.gd"

# AFTER
extends RigidBody3D
```

#### 2. Added All Grabbable Properties
```gdscript
# Grab mode enum
enum GrabMode { FREE_GRAB, ANCHOR_GRAB }

# Core grab properties
@export var grab_mode: GrabMode = GrabMode.FREE_GRAB
@export var grab_anchor_offset: Vector3 = Vector3.ZERO
@export var grab_anchor_rotation: Vector3 = Vector3.ZERO
@export var save_id: String = ""

# Runtime state
var is_grabbed: bool = false
var grabbing_hand: RigidBody3D = null
var is_network_owner: bool = false
var network_manager = null

# Visual tracking
var grabbed_collision_shapes: Array = []
var grabbed_mesh_instances: Array = []
var grab_offset: Vector3 = Vector3.ZERO
var grab_rotation_offset: Quaternion = Quaternion.IDENTITY
var original_parent: Node = null

# Signals
signal grabbed(hand: RigidBody3D)
signal released()
```

#### 3. Added All Grabbable Methods
- `try_grab(hand)` - Attempt to grab with network ownership check
- `release()` - Release object and restore physics
- `_setup_network_sync()` - Connect to NetworkManager signals
- `_on_network_grab()` - Handle remote grab events
- `_on_network_release()` - Handle remote release events
- `_on_network_sync()` - Interpolate remote position/rotation
- `_set_remote_grabbed_visual()` - Show semi-transparent when grabbed by others
- `_on_collision_entered()` - Collision handling

#### 4. Integrated Network Sync
In `_ready()`:
```gdscript
# Setup network sync for grabbable functionality
_setup_network_sync()
```

In `_physics_process()`:
```gdscript
# Network sync: Send position updates if we own this object
if is_network_owner and network_manager:
    network_manager.update_grabbed_object(
        save_id,
        global_position,
        global_transform.basis.get_rotation_quaternion()
    )
```

## Benefits of This Approach

✅ **No Class Resolution Issues** - Doesn't depend on Godot's class_name system
✅ **Self-Contained** - All functionality in one file, easier to debug
✅ **Network Sync Works** - Full multiplayer grabbable support
✅ **No Parser Errors** - Extends RigidBody3D directly

## Trade-offs

⚠️ **Code Duplication** - Grabbable methods duplicated in GrappleHook
⚠️ **Maintenance** - Changes to grabbable system need to be applied to both files
⚠️ **Not DRY** - Violates "Don't Repeat Yourself" principle

## Future Improvements

If Godot's class resolution improves or if inheritance becomes reliable:

1. **Revert to Inheritance** - Change back to `extends Grabbable`
2. **Component Pattern** - Create a GrabbableComponent node that can be added as a child
3. **Interface System** - Use duck typing with consistent method names

## Testing

The GrappleHook should now:
- ✅ Be grabbable in VR
- ✅ Sync across multiplayer (position, grab state)
- ✅ Show visual feedback when grabbed by remote players
- ✅ Support both FREE_GRAB and ANCHOR_GRAB modes
- ✅ Work with the grappling hook mechanics (raycast, winch, rope visuals)

## Files Modified

- `grabbables/GrappleHook.gd` - Complete refactor from inheritance to composition (844 lines)
  - Added all Grabbable enums, properties, signals
  - Added all Grabbable methods (try_grab, release, network sync)
  - Integrated network sync into _ready() and _physics_process()
  - Preserved all original grappling hook functionality
