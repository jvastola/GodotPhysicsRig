# Canvas Painter System

A 2D canvas painting system for VR that allows finger/pointer painting on a flat surface with configurable resolution and the ability to save/load images.

## Features

- **Configurable Canvas Size**: Set width and height (64-2048 pixels)
- **Brush Painting**: Adjustable brush size (1-50 pixels) with smooth line interpolation
- **Color Selection**: Full color picker for brush color
- **Auto-Save**: Automatically saves canvas to file with debouncing
- **Load/Save**: Manual save and load functionality
- **Clear Canvas**: Reset canvas to background color
- **VR Compatible**: Works with hand pointer raycast system
- **Desktop Compatible**: Mouse painting support in viewport

## Files

### Core System
- `src/systems/canvas_painter.gd` - Main canvas painter logic
- `src/systems/canvas_painter_handler.gd` - Pointer event handler for canvas mesh

### UI Components
- `src/ui/CanvasPainterUI.tscn` - 2D UI panel with controls
- `src/ui/canvas_painter_ui.gd` - UI controller script
- `src/ui/CanvasPainterViewport3D.tscn` - 3D viewport for canvas
- `src/ui/canvas_painter_viewport_3d.gd` - Viewport controller with mouse input
- `src/ui/CanvasPainterPanel.tscn` - VR-ready panel with canvas and UI

### Test Scene
- `src/test/CanvasPainterTest.tscn` - Desktop test scene

## Usage

### Basic Setup

1. **Add to Scene**: Instance `CanvasPainterPanel.tscn` in your scene
2. **Configure**: Set canvas size and other properties in the inspector
3. **Paint**: Use hand pointer or mouse to paint on the canvas

### Canvas Painter Properties

```gdscript
@export var canvas_width: int = 512          # Canvas width in pixels
@export var canvas_height: int = 512         # Canvas height in pixels
@export var background_color: Color = Color.WHITE
@export var default_brush_color: Color = Color.BLACK
@export var brush_size: int = 5              # Brush radius in pixels
@export var canvas_physical_size: Vector2 = Vector2(1.0, 1.0)  # Size in 3D space
@export var auto_save: bool = true           # Auto-save on changes
@export var save_path: String = "user://canvas_painter.png"
```

### API Methods

```gdscript
# Painting
paint_at_uv(uv: Vector2, color: Color)  # Paint at UV coordinates (0-1)
start_painting()                         # Begin continuous painting
stop_painting()                          # End continuous painting

# Canvas Management
clear_canvas(color: Color = Color.WHITE) # Clear to specified color
save_canvas(path: String = "")           # Save to PNG file
load_canvas(path: String = "")           # Load from PNG file

# Getters
get_canvas_texture() -> ImageTexture     # Get current canvas texture
get_canvas_image() -> Image              # Get current canvas image
```

### Integration with Watch Menu

To add the canvas painter to the watch menu:

1. Open `src/ui/watch_menu_ui.gd`
2. Add a button for the canvas painter
3. Instance `CanvasPainterPanel.tscn` when button is pressed

Example:
```gdscript
func _on_canvas_painter_button_pressed():
    var canvas_panel = preload("res://src/ui/CanvasPainterPanel.tscn").instantiate()
    add_child(canvas_panel)
```

### VR Hand Pointer Integration

The canvas painter automatically works with the hand pointer system:

1. The canvas mesh has the `pointer_interactable` group
2. The handler script processes pointer events
3. UV coordinates are computed from local hit position
4. Painting is applied with smooth line interpolation

### Desktop Testing

Use `CanvasPainterTest.tscn` for desktop testing:
- Click and drag to paint
- Use UI controls to adjust settings
- Test save/load functionality

## Technical Details

### Canvas Structure

The canvas uses:
- **Image**: RGBA8 format for pixel data
- **ImageTexture**: GPU texture updated on paint
- **Plane Mesh**: Quad with proper UV mapping
- **StandardMaterial3D**: Unshaded material with nearest filtering

### Painting Algorithm

1. Convert pointer position to UV coordinates (0-1 range)
2. Map UV to pixel coordinates
3. Draw circular brush at pixel position
4. Interpolate between last position and current for smooth lines
5. Update texture from modified image
6. Schedule debounced save

### Performance Considerations

- **Debounced Saves**: Saves are delayed by 1 second to avoid excessive file I/O
- **Texture Updates**: Only updated regions are modified
- **Line Interpolation**: Prevents gaps in fast brush strokes
- **Resolution Limits**: 64-2048 pixels to balance quality and performance

## Examples

### Creating a Custom Canvas

```gdscript
extends Node3D

var canvas_painter: CanvasPainter

func _ready():
    canvas_painter = CanvasPainter.new()
    canvas_painter.canvas_width = 1024
    canvas_painter.canvas_height = 768
    canvas_painter.brush_size = 10
    canvas_painter.default_brush_color = Color.RED
    add_child(canvas_painter)
```

### Programmatic Painting

```gdscript
# Paint a red dot at center
canvas_painter.paint_at_uv(Vector2(0.5, 0.5), Color.RED)

# Paint a line
canvas_painter.start_painting()
for i in range(100):
    var t = float(i) / 100.0
    canvas_painter.paint_at_uv(Vector2(t, 0.5), Color.BLUE)
canvas_painter.stop_painting()
```

### Export Canvas

```gdscript
# Save to custom location
canvas_painter.save_canvas("user://my_artwork.png")

# Get image for further processing
var img = canvas_painter.get_canvas_image()
img.resize(256, 256)
img.save_png("user://thumbnail.png")
```

## Future Enhancements

- [ ] Undo/Redo system
- [ ] Multiple layers
- [ ] Eraser tool
- [ ] Fill bucket tool
- [ ] Shape tools (line, rectangle, circle)
- [ ] Texture stamps/brushes
- [ ] Pressure sensitivity (if supported)
- [ ] Color palette presets
- [ ] Export to different formats (JPG, WebP)
- [ ] Import images as canvas background

## Troubleshooting

### Canvas not appearing
- Check that `canvas_mesh_path` is set correctly
- Ensure mesh is visible in scene tree
- Verify camera can see the canvas

### Painting not working
- Confirm handler script is attached to mesh
- Check that mesh is in `pointer_interactable` group
- Verify painter node path in handler

### Performance issues
- Reduce canvas resolution
- Decrease brush size
- Disable auto-save for large canvases

### Save/Load not working
- Check file permissions for save path
- Verify path is in `user://` directory
- Check console for error messages
