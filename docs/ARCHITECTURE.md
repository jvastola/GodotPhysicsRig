# Scene Architecture Diagram

## Project Structure Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    GameManager (Autoload)                    │
│  • Manages scene transitions                                │
│  • Preserves player state                                   │
│  • Spawns player at spawn points                            │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
        ┌───────────────────────────────────────┐
        │         Scene Loading Flow             │
        └───────────────────────────────────────┘
                            │
        ┌───────────────────┴───────────────────┐
        ▼                                       ▼
┌────────────────────┐              ┌────────────────────┐
│   MainScene.tscn   │              │  SecondRoom.tscn   │
│                    │              │                    │
│  ┌──────────────┐  │              │  ┌──────────────┐  │
│  │  XRPlayer    │  │              │  │  XRPlayer    │  │
│  │  (instanced) │  │              │  │  (spawned)   │  │
│  └──────────────┘  │              │  └──────────────┘  │
│         │          │              │         │          │
│         │          │              │         │          │
│  ┌──────▼───────┐  │              │  ┌──────▼───────┐  │
│  │   Portal     │──┼──────────────┼─>│ PortalBack   │  │
│  │   (blue)     │  │ Transition   │  │  (orange)    │  │
│  └──────────────┘  │              │  └──────────────┘  │
│                    │              │                    │
│  • Floor           │              │  • Floor           │
│  • Lighting        │              │  • Lighting        │
│  • SpawnPoint      │              │  • SpawnPoint      │
└────────────────────┘              └────────────────────┘
```

## XRPlayer Structure

```
XRPlayer (RigidBody3D) [group: player]
│
├── CollisionShape3D (sphere)
├── MeshInstance3D (visual body)
│
├── XROrigin3D (VR tracking origin)
│   ├── XRCamera3D (headset view)
│   ├── LeftController (left hand tracking)
│   └── RightController (right hand tracking)
│
├── PhysicsHandLeft (RigidBody3D)
│   └── CollisionShape3D
│       └── Follows LeftController
│
└── PhysicsHandRight (RigidBody3D)
    └── CollisionShape3D
        └── Follows RightController
```

## Portal Interaction Flow

```
1. Player Walks Toward Portal
        │
        ▼
2. Player Body Enters Portal Area3D
        │
        ▼
3. Portal.gd Detects body_entered Signal
        │
        ▼
4. Portal Checks if Body is Player
        │
        ▼
5. Portal Stores Player State
        │   • Velocity
        │   • Spawn point name
        │
        ▼
6. Portal Calls GameManager.change_scene_with_player()
        │
        ▼
7. GameManager Stores Player Data
        │
        ▼
8. Scene Changes (get_tree().change_scene_to_file())
        │
        ▼
9. New Scene Loads
        │
        ▼
10. GameManager Detects New Scene
        │
        ▼
11. Player Spawned at SpawnPoint
        │
        ▼
12. Player State Restored (velocity, position)
```

## Physics Layers Interaction

```
Layer 1: World (0001)
├── Floors
├── Walls
└── Static objects

Layer 2: Player (0010)
└── Player body
    └── Collides with: World, Hand

Layer 3: Hand (0100)
├── PhysicsHandLeft
└── PhysicsHandRight
    └── Collides with: World, Player

Layer 4: Portal (1000)
└── Portal Areas
    └── Detects: Player layer
```

## Script Communication

```
┌─────────────────┐
│  game_manager.gd│ (Autoload - Always Active)
│   (Singleton)   │
└────────┬────────┘
         │ Communicates with:
         │
    ┌────┼────┬────────────┬──────────┐
    │    │    │            │          │
    ▼    ▼    ▼            ▼          ▼
┌───────┐ ┌────────┐ ┌──────────┐ ┌──────────┐
│portal │ │xr_player│ │xr_origin│ │physics   │
│  .gd  │ │   .gd   │ │  _3d.gd │ │_hand.gd  │
└───────┘ └────────┘ └──────────┘ └──────────┘
    │         │            │            │
    │         │            │            │
    └─────────┴────────────┴────────────┘
              Scene Tree Signals
```

## Scene Transition Timeline

```
Time    Event                           State
──────────────────────────────────────────────────────────
0.0s    Player in MainScene             Normal play
        
1.0s    Player approaches portal        Portal visible
        
1.5s    Player enters portal Area3D     Signal triggered
        
1.51s   portal.gd._on_body_entered()    Check if player
        
1.52s   GameManager stores state        {velocity, spawn}
        
1.53s   Scene change initiated          Fade/transition
        
1.8s    MainScene unloaded              Memory freed
        
2.0s    SecondRoom loaded               New scene ready
        
2.01s   GameManager._on_node_added()    Detect new scene
        
2.02s   Find SpawnPoint                 Located at (0,2,5)
        
2.03s   Spawn/Move player               Player positioned
        
2.04s   Restore velocity                Physics applied
        
2.1s    Player in SecondRoom            Normal play resumes
```

## File Dependencies

```
MainScene.tscn
├── depends on: XRPlayer.tscn
├── depends on: Portal.tscn
└── depends on: game_manager.gd (autoload)

XRPlayer.tscn
├── depends on: xr_player.gd
├── depends on: xr_origin_3d.gd
└── depends on: physics_hand.gd

Portal.tscn
└── depends on: portal.gd

SecondRoom.tscn
├── depends on: Portal.tscn
└── depends on: game_manager.gd (autoload)
```

## Typical Game Flow

```
┌─────────────────┐
│  Game Starts    │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────┐
│  MainScene.tscn loads       │
│  • GameManager initializes  │
│  • XRPlayer spawned         │
│  • VR/Desktop mode set      │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  Player Explores            │
│  • Physics hands active     │
│  • Can climb/interact       │
│  • Sees portal              │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  Player Enters Portal       │
│  • State saved              │
│  • Scene changes            │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  SecondRoom.tscn loads      │
│  • Player at SpawnPoint     │
│  • Can return via portal    │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  Cycle repeats...           │
│  Build more rooms!          │
└─────────────────────────────┘
```

## Extension Points

### Add New Room Type
```
1. Create scene from Node3D
2. Add: Environment, Light, Floor, SpawnPoint
3. Instance Portal.tscn
4. Set portal target_scene
5. Done!
```

### Add Player Ability
```gdscript
# In xr_player.gd
func new_ability() -> void:
    # Your code
    pass
```

### Custom Portal Effect
```
1. Open Portal.tscn
2. Modify GPUParticles3D
3. Adjust material properties
4. Add AudioStreamPlayer3D
```

### Save System
```gdscript
# In game_manager.gd
func save_game() -> void:
    var save_data = {
        "current_scene": get_tree().current_scene.scene_file_path,
        "player_position": get_player().global_position,
        # ... more data
    }
    # Save to file
```

## Performance Notes

### Memory Management
- Old scenes automatically freed
- Player persists across transitions
- GameManager stays in memory (singleton)

### Physics Optimization
- Hands use PID controllers (efficient)
- Player uses RigidBody3D (native physics)
- Static bodies for environment (no processing)

### VR Performance
- Physics runs on separate thread
- OpenXR handles refresh rate matching
- Foveated rendering enabled
