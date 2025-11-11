# Grabbable Objects System

## Overview
The grabbable object system allows VR players to pick up, hold, and throw objects in the game world using their physics hands.

## Features
- **Two Grab Modes**: Anchor grab (fixed orientation) and free grab (maintains relative orientation)
- **Quest Controller Support**: Both trigger and grip buttons can be used to grab
- **Physics-Based**: Objects use forces to follow hands smoothly
- **Throwing**: Objects inherit hand velocity when released
- **Multiple Hands**: Each hand can grab independently

## Usage

### Making an Object Grabbable

1. Add the `grabbable.gd` script to any RigidBody3D
2. Enable `contact_monitor = true` and `max_contacts_reported = 4`
3. Add the object to the "grabbable" group
4. Configure grab mode in the inspector

### Grab Modes

#### Anchor Grab (Default)
Objects snap to a fixed position/rotation relative to the hand. Best for:
- Tools (swords, hammers, etc.)
- Items with a specific "grip" point
- Objects that should always be held the same way

Properties:
- `grab_anchor_offset`: Position offset from hand (Vector3)
- `grab_anchor_rotation`: Rotation offset in degrees (Vector3)

#### Free Grab
Objects maintain their orientation relative to the hand at the moment of grab. Best for:
- Generic objects (boxes, balls, etc.)
- Items that can be held from any angle
- Natural "pick up where you touch it" behavior

### Controller Input

**Quest Controllers:**
- **Trigger** or **Grip**: Grab nearby object
- **B/Y Button** (right/left hand): Release held object
- **Release trigger/grip**: Auto-release if both below 30%

The system automatically detects which button to use based on controller input values.

### Example Scene Setup

```gdscript
# In SecondRoom.tscn, we have two examples:

# 1. Anchor Grab Cube
[node name="GrabbableCube" type="RigidBody3D" groups=["grabbable"]]
script = ExtResource("grabbable.gd")
grab_mode = 1  # ANCHOR_GRAB
grab_anchor_offset = Vector3(0, 0, 0)
grab_anchor_rotation = Vector3(0, 0, 0)

# 2. Free Grab Ball
[node name="GrabbableBall" type="RigidBody3D" groups=["grabbable"]]
script = ExtResource("grabbable.gd")
grab_mode = 0  # FREE_GRAB
```

## How It Works

### Physics Hand Detection
1. PhysicsHand uses `body_entered` signal to detect nearby grabbables
2. Maintains `nearby_grabbables` array of objects in range
3. On grab input, finds closest grabbable and calls `try_grab()`

### Grabbing Process
1. Hand calls `grabbable.try_grab(hand)`
2. Grabbable stores grab offset/rotation based on mode
3. Gravity disabled, collision mask reduced
4. Object position/rotation updated in `_physics_process()`

### Following Hand
Objects use forces (not direct transform setting) to smoothly follow the hand:
- Position: Spring force toward target position
- Rotation: Torque toward target rotation
- Damping: Reduces velocity to prevent oscillation

### Releasing
When released:
1. Object inherits hand velocity (linear and angular)
2. Gravity re-enabled
3. Collision mask restored
4. Object flies with throwing motion

## Customization

### Adjust Grab Feel
In `grabbable.gd` `_follow_hand()` method:
```gdscript
var force_strength = 1000.0  # Higher = more responsive, may oscillate
var damping = 10.0           # Higher = less bouncy
var torque_strength = 500.0  # Rotation responsiveness
```

### Change Controller Buttons
In `physics_hand.gd` `_ready()`:
```gdscript
grab_action_trigger = "trigger_click"
grab_action_grip = "grip_click"
release_button = "by_button"  # or "ax_button"
```

### Custom Grab Logic
Override or extend `try_grab()` and `release()` in a custom script:
```gdscript
extends "res://grabbable.gd"

func try_grab(hand: RigidBody3D) -> bool:
    if not super.try_grab(hand):
        return false
    
    # Custom behavior on grab
    print("Special object grabbed!")
    return true
```

## Debugging

Enable debug prints in both scripts:
- `grabbable.gd`: Shows grab/release events
- `physics_hand.gd`: Shows nearby objects and grab attempts

Check console for:
- "PhysicsHand: Grabbable nearby - [name]"
- "PhysicsHand: Grabbed [name]"
- "Grabbable: Object grabbed by [hand]"
- "Grabbable: Object released"

## Known Limitations

1. **Desktop Mode**: Grabbing currently only works in VR mode
2. **One Object Per Hand**: Each hand can only hold one object at a time
3. **Collision**: Held objects have reduced collision to prevent physics bugs
4. **Hand Distance**: Must be within collision range to grab

## Future Enhancements

- [ ] Desktop mode grabbing with mouse
- [ ] Distance grabbing (ray-based)
- [ ] Two-handed grabbing
- [ ] Snap zones (holsters, shelves, etc.)
- [ ] Haptic feedback on grab/release
- [ ] Highlight nearby grabbables
