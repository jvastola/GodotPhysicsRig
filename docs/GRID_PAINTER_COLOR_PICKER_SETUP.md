# Grid Painter Color Picker Integration

## Overview
The grid painter system now supports color picking from the ColorPickerUI. When you interact with the color picker, the selected color will automatically be used when painting on grid painter surfaces.

## Setup Instructions

### 1. Enable Color Picker Integration on Hand Pointers

For each hand pointer (left and right) in your XRPlayer:

1. Select the hand pointer node (e.g., `LeftController/HandPointer` or `RightController/HandPointer`)
2. In the Inspector, find the property `Include Pointer Color`
3. Check the box to enable it

This tells the hand pointer to:
- Find the ColorPickerUI in the scene
- Continuously update its `pointer_color` from the color picker's current color
- Pass that color in pointer events to handlers

### 2. Default Configuration Loading

The grid painter system now automatically loads default surfaces from:
```
res://assets/textures/grid_painter_surfaces.json
```

If no saved user data exists at `user://grid_painter_surfaces.json`, the system will:
- Load the default configuration on first run
- Apply it to both player and preview surfaces
- Save user changes to the user directory for persistence

### 3. How It Works

When painting on a grid painter surface:

1. The hand pointer checks if `include_pointer_color` is enabled
2. If enabled, it gets the current color from `ColorPickerUI.instance.get_current_color()`
3. The color is included in the pointer event as `event["pointer_color"]`
4. The `grid_painter_handler.gd` receives the event and uses the `pointer_color` if available
5. The color is painted onto the grid at the UV coordinates

### 4. Testing

To test the integration:

1. Open your main scene with the XRPlayer
2. Enable `Include Pointer Color` on both hand pointers
3. Run the scene
4. Open the Color Picker UI from the watch menu
5. Select a color
6. Point at a grid painter surface (hands, head, body)
7. Pull the trigger to paint
8. The selected color should be painted on the surface

### 5. Troubleshooting

If colors aren't being picked up:

- **Check `include_pointer_color` is enabled** on the hand pointer nodes
- **Verify ColorPickerUI exists** in the scene and is in the `color_picker_ui` group
- **Check the console** for any error messages about missing nodes
- **Ensure grid_painter_handler.gd** is attached to the paintable surfaces
- **Verify the pointer is hitting** the surface (check ray visualization)

### 6. Code Changes Made

#### `src/player/hand_pointer.gd`
- Added `_color_picker_ui` variable to cache the ColorPickerUI instance
- Added `_find_color_picker()` to locate the ColorPickerUI
- Added `_update_pointer_color_from_picker()` to update the pointer color
- Modified `_ready()` to find the color picker when enabled
- Modified `_physics_process()` to continuously update the color

#### `src/systems/grid_painter.gd`
- Modified `load_grid_data()` to load from default file if no saved file exists
- Default path: `res://assets/textures/grid_painter_surfaces.json`
- Fallback ensures consistent starting state for all users

## Related Files

- `src/player/hand_pointer.gd` - Hand pointer with color picker integration
- `src/systems/grid_painter_handler.gd` - Receives pointer events with color
- `src/systems/grid_painter.gd` - Manages grid surfaces and painting
- `src/ui/color_picker_ui.gd` - Color picker UI component
- `assets/textures/grid_painter_surfaces.json` - Default surface configuration
