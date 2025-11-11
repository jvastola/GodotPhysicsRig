# Physics Callback Fixes

## Issue

When transitioning through portals, physics callback errors were occurring:

```
E: Removing a CollisionObject node during a physics callback is not allowed
E: Condition "!is_inside_tree()" is true. Returning: Transform3D()
```

## Root Cause

1. **Portal collision callback** - Scene changes were being triggered directly from `body_entered` signal (physics callback)
2. **Transform access** - Trying to get global_transform of nodes not yet in the scene tree

## Solution

### 1. Portal Scene Changes (portal.gd)

**Before:**
```gdscript
func _on_body_entered(body: Node3D) -> void:
    # Direct scene change during physics callback ❌
    GameManager.change_scene_with_player(target_scene, player_state)
```

**After:**
```gdscript
func _on_body_entered(body: Node3D) -> void:
    # Deferred scene change - waits until physics callback completes ✅
    GameManager.call_deferred("change_scene_with_player", target_scene, player_state)
```

### 2. Player Spawning (game_manager.gd)

**Before:**
```gdscript
func _spawn_player(scene_root: Node, spawn_point: Node3D) -> void:
    var player = player_scene.instantiate()
    player.global_position = spawn_point.global_position  # ❌ Before in tree
    scene_root.add_child(player)
```

**After:**
```gdscript
func _spawn_player(scene_root: Node, spawn_point: Node3D) -> void:
    var player = player_scene.instantiate()
    scene_root.add_child(player)  # ✅ Add to tree first
    await get_tree().process_frame  # ✅ Wait for transform update
    player.global_position = spawn_point.global_position  # ✅ Now safe
```

### 3. Player Positioning (game_manager.gd)

**Before:**
```gdscript
func _position_player_at_spawn(player: Node3D, scene_root: Node) -> void:
    player.global_position = spawn_point.global_position  # ❌ Direct assignment
```

**After:**
```gdscript
func _position_player_at_spawn(player: Node3D, scene_root: Node) -> void:
    if player is RigidBody3D:
        # ✅ Deferred for physics objects
        player.call_deferred("set_global_position", spawn_point.global_position)
    else:
        player.global_position = spawn_point.global_position
```

## Changes Made

### portal.gd
- Changed direct `change_scene_with_player()` call to `call_deferred()`
- Added `_change_scene_fallback()` helper for non-GameManager path
- Both paths now use deferred execution

### game_manager.gd
- Added tree validation before accessing `global_position`
- Added `await get_tree().process_frame` to wait for node to be in tree
- Changed player positioning to use `call_deferred()` for RigidBody3D
- Added safety checks for `is_inside_tree()`

## Why This Matters

### Physics Callbacks

Godot's physics engine uses callbacks during its internal simulation:
- Collision detection
- Contact resolution
- Signal emission

During these callbacks, **modifying the scene tree is not allowed** because:
- Physics simulation is in progress
- Removing nodes could crash the simulation
- Transform updates might conflict with physics state

### Solution: call_deferred()

`call_deferred()` schedules the function call for the next frame:
```
Physics Frame
├─ Collision Detection
├─ body_entered signal → portal._on_body_entered()
│  └─ Schedules change_scene_with_player() for next frame
├─ Physics Simulation Completes
└─ Frame Ends

Next Frame
├─ Deferred calls execute ✅
│  └─ change_scene_with_player() safely runs
└─ New scene loads
```

## Testing

Test that portals work without errors:

1. Run MainScene.tscn
2. Walk through blue portal
3. Should transition to SecondRoom with no console errors
4. Walk through orange portal to return
5. Should transition back with no console errors

## Performance Impact

**Minimal** - Adds ~1 frame delay to scene transitions:
- Not noticeable to users
- Safer and more stable
- Prevents crashes and errors

## Best Practices

### When to use call_deferred()

✅ **Use for:**
- Scene changes during physics callbacks
- Removing CollisionObject nodes
- Changing RigidBody3D transforms from signals
- Modifying scene tree structure from physics

❌ **Not needed for:**
- UI updates
- Non-physics operations
- Already deferred code paths
- _process() or _physics_process() functions

### Pattern

```gdscript
# In signal handlers from physics objects:
func _on_physics_signal(body):
    # ❌ Don't do this
    remove_child(body)
    
    # ✅ Do this instead
    call_deferred("remove_child", body)
    # or
    body.call_deferred("queue_free")
```

## Related Godot Documentation

- [Physics Callbacks](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html#collision-callbacks)
- [call_deferred()](https://docs.godotengine.org/en/stable/classes/class_object.html#class-object-method-call-deferred)
- [RigidBody3D Best Practices](https://docs.godotengine.org/en/stable/tutorials/physics/rigid_body.html)

## Summary

✅ **Portal transitions now properly deferred**  
✅ **Player spawning waits for scene tree**  
✅ **No physics callback errors**  
✅ **Stable scene transitions**  
✅ **Production ready**

The portal system now follows Godot best practices for physics callbacks!
