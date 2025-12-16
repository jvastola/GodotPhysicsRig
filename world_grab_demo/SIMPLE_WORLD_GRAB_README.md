# Simple World Grab Demo

This is a minimal implementation of the world grab functionality with only 5 scripts instead of the original 40+ scripts.

## Files

1. **simple_world_grab.tscn** - Main scene file
2. **simple_xr_setup.gd** - Basic XR initialization
3. **simple_player_body.gd** - Player physics body that follows the camera
4. **simple_pickup.gd** - Hand controller pickup functionality
5. **simple_world_grab.gd** - World grab movement logic
6. **simple_grab_area.gd** - Grabbable area definition

## Features

- ✅ Basic XR setup and initialization
- ✅ Player body with physics and collision
- ✅ Hand controller grip detection
- ✅ World grab locomotion (single and dual hand)
- ✅ Rotation when using both hands
- ✅ Scaling when using both hands
- ✅ Zero gravity area for world grab

## How it Works

1. **XR Setup**: Automatically initializes OpenXR if available
2. **Player Body**: CharacterBody3D that follows the camera with basic physics
3. **Hand Pickup**: Detects grip button presses and finds nearby grab areas
4. **World Grab**: When gripping a grab area, calculates movement offset and applies it to the player
5. **Dual Hand**: When both hands grab, enables rotation and scaling

## Usage

1. Load the `simple_world_grab.tscn` scene
2. In VR, use grip buttons to grab the invisible world grab area
3. Move your hands to move through the world
4. Use both hands to rotate and scale

## Differences from Original

- Removed complex movement provider system
- Simplified physics calculations
- No advanced features like velocity averaging, collision hand, etc.
- Direct implementation instead of modular system
- Minimal error checking and edge cases

This version maintains the core world grab functionality while being much easier to understand and modify.