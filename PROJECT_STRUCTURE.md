# Project Structure Guide

## Overview
This Godot VR project is now organized into modular, reusable scenes with portal-based scene transitions.

## Scene Hierarchy

### XRPlayer.tscn
**Purpose**: Reusable VR player with physics-based hands
**Components**:
- RigidBody3D (player body)
- XROrigin3D (VR tracking origin)
  - XRCamera3D (VR headset)
  - LeftController (left hand controller)
  - RightController (right hand controller)
- PhysicsHandLeft (physics-based left hand)
- PhysicsHandRight (physics-based right hand)

**Script**: `xr_player.gd`
**Methods**:
- `teleport_to(position: Vector3)` - Teleport player to position
- `get_camera_position()` - Get actual camera world position
- `get_camera_forward()` - Get camera forward direction

### Portal.tscn
**Purpose**: Scene transition portals
**Components**:
- Area3D (collision detection)
- MeshInstance3D (visual portal mesh)
- GPUParticles3D (portal effect)
- Label3D (portal label)

**Script**: `portal.gd`
**Exports**:
- `target_scene` - Path to destination scene file
- `spawn_point_name` - Name of spawn point in target scene
- `portal_color` - Visual color of the portal

**Methods**:
- `set_target(scene_path, spawn_name)` - Set portal destination

### MainScene.tscn
**Purpose**: Starting scene/room
**Contains**:
- WorldEnvironment
- DirectionalLight3D
- Floor (StaticBody3D)
- SpawnPoint (Marker3D)
- XRPlayer (instanced)
- Portal (to SecondRoom)

### SecondRoom.tscn
**Purpose**: Example secondary scene
**Contains**:
- Different colored environment
- Floor (StaticBody3D)
- SpawnPoint (Marker3D)
- PortalBack (returns to MainScene)
- WelcomeLabel (3D text)

## Scripts

### game_manager.gd (Autoload)
**Purpose**: Global game state and scene management
**Features**:
- Manages player persistence across scenes
- Handles scene transitions
- Spawns player at spawn points
- Preserves player velocity between scenes

**Methods**:
- `change_scene_with_player(scene_path, player_state)` - Change scene with player data
- `get_player()` - Get current player node

### xr_origin_3d.gd
**Purpose**: XR/VR initialization and management
**Features**:
- Initializes OpenXR
- Handles VR session events
- Sets up refresh rate
- Allows desktop mode when VR unavailable

### physics_hand.gd
**Purpose**: Physics-based hand controller
**Features**:
- PID controller for position tracking
- PID controller for rotation tracking
- Hooke's law spring for climbing
- Collision detection

## How to Use

### Adding a New Scene

1. Create new scene file (e.g., `ThirdRoom.tscn`)
2. Add essential nodes:
   - WorldEnvironment
   - DirectionalLight3D
   - Floor StaticBody3D
   - SpawnPoint (Marker3D)
3. Instance Portal.tscn
4. Set portal's target_scene to your new scene

### Creating a Portal

1. Instance Portal.tscn in your scene
2. Position where you want the portal
3. In Inspector, set:
   - `Target Scene`: Path to destination scene
   - `Spawn Point Name`: Name of Marker3D in destination
   - `Portal Color`: Visual appearance (optional)

### Setting Spawn Points

1. Add a Marker3D node to your scene
2. Name it "SpawnPoint" (or custom name)
3. Position where player should appear
4. Set portal's `spawn_point_name` to match

### Player Setup

The player is automatically managed by GameManager:
- On scene load, spawned at "SpawnPoint"
- Velocity preserved through portals
- Only one player instance exists

### Testing Without VR

The project works in desktop mode:
- XR features gracefully disabled
- Player still functions as physics body
- Use for testing scene layouts

## Project Settings

### Autoloads
- **GameManager**: `res://game_manager.gd`

### Physics Layers
1. World - Static environment
2. Player - Player body
3. Hand - Physics hands
4. Portal - Portal triggers

### Main Scene
Set to `res://MainScene.tscn`

## Development Tips

### Adding New Features to Player
Edit `xr_player.gd` to add player abilities:
```gdscript
func new_ability() -> void:
    # Your code here
```

### Custom Portal Effects
Edit `Portal.tscn`:
- Adjust GPUParticles3D for different effects
- Modify material for different visuals
- Add sound effects

### Scene Transition Events
In `game_manager.gd`, you can add hooks:
```gdscript
# Before scene change
func on_scene_exit():
    pass

# After scene change
func on_scene_enter():
    pass
```

## File Organization

```
GodotPhysicsRig/
├── XRPlayer.tscn           # Player prefab
├── xr_player.gd            # Player controller
├── Portal.tscn             # Portal prefab
├── portal.gd               # Portal logic
├── MainScene.tscn          # Starting scene
├── SecondRoom.tscn         # Example second scene
├── game_manager.gd         # Global manager (autoload)
├── xr_origin_3d.gd         # VR initialization
├── physics_hand.gd         # Hand physics
├── PhysicsHand.tscn        # (Original scene - can archive)
└── project.godot           # Project settings
```

## Next Steps

1. **Add More Rooms**: Copy SecondRoom.tscn as template
2. **Improve Portals**: Add sound, better effects
3. **Player Abilities**: Add teleport, grab, etc.
4. **Save System**: Extend GameManager for saves
5. **UI**: Add menus, HUD elements
6. **Interactables**: Create pickup objects
7. **Puzzle Elements**: Buttons, doors, keys
