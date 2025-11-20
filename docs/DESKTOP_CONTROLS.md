# Desktop Controls Guide

## Overview

The XRPlayer now automatically switches between VR mode and Desktop mode based on whether an OpenXR headset is detected.

## Desktop Mode Controls

### Mouse & Keyboard

**Movement:**
- `W` - Move forward
- `S` - Move backward  
- `A` - Strafe left
- `D` - Strafe right
- `Space` - Jump
- `Shift` - Sprint (2x speed)

**Camera:**
- `Mouse Movement` - Look around
- `ESC` - Release/capture mouse cursor

**Interaction:**
- `Left Click` - Recapture mouse (when released)

## How It Works

### Automatic Mode Detection

When the game starts:
1. **xr_origin_3d.gd** checks if OpenXR is available
2. Emits `vr_mode_active(true/false)` signal
3. **xr_player.gd** receives signal and switches modes

### VR Mode (Headset Connected)
- XRCamera3D is active
- Physics hands are visible and functional
- Controller tracking enabled
- Desktop controls disabled

### Desktop Mode (No Headset)
- Standard Camera3D is active
- Physics hands are hidden and disabled
- Mouse look enabled
- WASD movement enabled
- Desktop controller active

## Technical Details

### Files Modified

1. **desktop_controller.gd** (NEW)
   - Handles mouse look and keyboard movement
   - Applies forces to RigidBody3D for movement
   - Implements ground detection for jumping

2. **xr_player.gd** (UPDATED)
   - Detects VR mode from xr_origin
   - Switches between VR and desktop components
   - Shows/hides physics hands based on mode

3. **xr_origin_3d.gd** (UPDATED)
   - Added `vr_mode_active` signal
   - Emits signal when VR initializes or fails
   - Tracks `is_vr_mode` state

4. **XRPlayer.tscn** (UPDATED)
   - Added DesktopCamera node
   - Added DesktopController node
   - Both start inactive until mode is determined

5. **project.godot** (UPDATED)
   - Added `jump` input action (Space)
   - Added `sprint` input action (Shift)
   - Fixed WASD mapping (W=forward, S=backward, A=left, D=right)

### Mode Switching Logic

```gdscript
# In xr_player.gd
func _on_vr_mode_changed(vr_active: bool) -> void:
    if vr_active:
        _activate_vr_mode()    # Enable VR camera & hands
    else:
        _activate_desktop_mode()  # Enable desktop camera & controls
```

### Desktop Movement Physics

Desktop movement uses the same RigidBody3D as VR mode:
- Forces applied relative to camera direction
- Horizontal damping when not moving
- Ground detection for jumping
- Arcade-style movement feel

## Testing

### Test Desktop Mode
1. Run project without VR headset connected
2. Console shows: "OpenXR not instantiated! Running in desktop mode."
3. Console shows: "XRPlayer: Desktop mode active"
4. Use WASD + mouse to move
5. Physics hands should be invisible

### Test VR Mode
1. Connect VR headset
2. Run project
3. Console shows: "OpenXR instantiated successfully."
4. Console shows: "XRPlayer: VR mode active"
5. VR camera and hand tracking work
6. Physics hands are visible

### Test Portal Transitions
Both modes should work through portals:
- Desktop: Walk with WASD through portal
- VR: Walk physically through portal
- Player state preserved in both cases

## Customization

### Adjust Movement Speed
Edit `desktop_controller.gd`:
```gdscript
@export var move_speed := 5.0          # Normal speed
@export var sprint_multiplier := 2.0   # Sprint multiplier
@export var jump_velocity := 6.0       # Jump height
```

### Adjust Mouse Sensitivity
Edit `desktop_controller.gd`:
```gdscript
@export var mouse_sensitivity := 0.003  # Lower = less sensitive
```

### Camera Height
Desktop camera is positioned at:
```gdscript
# In XRPlayer.tscn
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.5, 0)
# Y = 0.5 is head height relative to player body center
```

### Change Controls
Edit in Project Settings → Input Map or modify `project.godot`:
- `move_forward` - W key
- `move_backward` - S key  
- `move_left` - A key
- `move_right` - D key
- `jump` - Space
- `sprint` - Shift

## Troubleshooting

### Mouse Not Working
- Click in game window to capture mouse
- Press ESC to release mouse
- Check console for "Desktop mode active" message

### Can't Move
- Verify WASD keys are mapped correctly
- Check that DesktopController node exists in XRPlayer
- Ensure player RigidBody3D is not frozen

### Physics Hands Visible in Desktop Mode
- Check console for mode activation messages
- Verify xr_origin_3d.gd emits vr_mode_active signal
- Ensure PhysicsHandLeft/Right are properly referenced

### Controls Not Switching
- Make sure xr_origin is child of XRPlayer
- Verify signal connection: `xr_origin.vr_mode_active.connect(_on_vr_mode_changed)`
- Check that _check_initial_mode() is called deferred

## Code Reference

### Desktop Controller API

```gdscript
# Activate desktop controls
desktop_controller.activate(camera: Camera3D)

# Deactivate desktop controls  
desktop_controller.deactivate()
```

### Player Mode Check

```gdscript
# Check current mode
if player.is_vr_mode:
    print("In VR mode")
else:
    print("In desktop mode")
```

## Performance Notes

### Desktop Mode
- Lower resource usage than VR
- No hand physics processing
- Single camera rendering
- Good for development/testing

### VR Mode
- Full physics simulation for hands
- Dual camera rendering (stereo)
- OpenXR processing overhead
- Optimized for 72-90 fps

## Future Enhancements

Potential improvements:
- [ ] Smooth camera head bob in desktop mode
- [ ] Crouch/prone controls
- [ ] Configurable key bindings menu
- [ ] Gamepad support for desktop mode
- [ ] Interaction raycasts in desktop mode
- [ ] Crosshair UI for desktop mode
- [ ] Flashlight/torch toggle

## Summary

Desktop controls are now fully integrated:
- ✅ Automatic mode detection
- ✅ Mouse look camera control
- ✅ WASD movement
- ✅ Jump and sprint
- ✅ Physics hands disabled in desktop mode
- ✅ Seamless mode switching
- ✅ Works with portal system

The player experience is consistent whether in VR or desktop mode!
