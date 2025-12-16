# Simple World Grab

A minimal world grab implementation that works anywhere without needing Area3D zones.

## Files

### Demo Scene (standalone test)
- `simple_world_grab.tscn` - Standalone demo scene
- `simple_pickup.gd` - Creates virtual grab handles
- `simple_world_grab.gd` - Movement logic for demo
- `simple_player_body.gd` - Basic player body
- `simple_grab_area.gd` - (Optional) Area-based grab zones

### Main Game Integration
- `src/player/components/simple_world_grab_component.gd` - Component for XRPlayer

## Usage in Main Game

1. The SimpleWorldGrabComponent is already added to XRPlayer.tscn
2. Open the Movement Settings panel in VR (on your watch)
3. Find "Simple World Grab" section
4. Toggle "Enable Simple World Grab"

## How it Works

- Grip anywhere with either controller to create a virtual anchor point
- Move your hand to move through the world (opposite direction)
- Use both hands for rotation and scaling
- Release grip to stop

## Features

- ✅ Works everywhere - no Area3D zones needed
- ✅ Single hand grab for movement
- ✅ Two hand grab for rotation and scaling
- ✅ Toggle via Movement Settings UI
- ✅ Integrates with existing XRPlayer

## Differences from V1/V2/V3 World Grab

- Simpler implementation (~150 lines vs 500+)
- No smoothing or sensitivity options (yet)
- No visual indicators
- Works globally instead of in designated areas