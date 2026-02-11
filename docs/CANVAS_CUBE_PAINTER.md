# Canvas Cube Painter System

A specialized canvas painting system for cube faces that integrates with GridPainter. Paint each face of a cube separately (top, bottom, front, back, left, right) and sync to voxel blocks or avatar surfaces.

## Features

- **6 Separate Canvases**: One for each cube face
- **Face Switching**: Easy navigation between faces with button grid
- **GridPainter Integration**: Sync painted textures to GridPainter surfaces
- **Pixel Perfect Mode**: Perfect for low-res textures like Minecraft blocks
- **Per-Face Editing**: Paint each face independently
- **Auto-Save**: Saves all 6 faces to JSON
- **Configurable Resolution**: 1x1 to 512x512 per face
- **VR Compatible**: Works with hand pointer system

## Files

### Core System
- `src/systems/canvas_cube_painter.gd` - Main cube painter logic
- `src/systems/canvas_cube_painter_handler.gd` - Pointer event handler

### UI Components
- `src/ui/CanvasCubePainterUI.tscn` - UI with face selector and controls
- `src/ui/canvas_cube_painter_ui.gd` - UI controller
- `src/ui/CanvasCubePainterViewport3D.tscn` - 3D viewport showing current face
- `src/ui/canvas_cube_painter_viewport_3d.gd` - Viewport controller

### Test Scene
- `src/test/CanvasCubePainterTest.tscn` - Desktop test scene

## Face Layout

The 6 faces follow this naming convention:
- **front** - +Z direction (facing you)
- **back** - -Z direction (behind)
- **right** - +X direction
- **left** - -X direction
- **top** - +Y direction
- **bottom** - -Y direction

This matches the GridPainter FACE_DEFS order for seamless integration.

## Usage

### Basic Setup

1. **Add to Scene**: Instance `CanvasCubePainterUI.tscn`
2. **Select Face**: Click face buttons to switch between faces
3. **Paint**: Click and drag to paint on the current face
4. **Sync**: Click "Sync to Grid" to apply to GridPainter

### Canvas Cube Painter Properties

```gdscript
@export var canvas_resolution: int = 16      # Resolution per face (1-512)
@export var background_color: Color = Color.WHITE
@export var default_brush_color: Color = Color.BLACK
@export var brush_size: int = 2
@export var pixel_perfect: bool = true       # Crisp pixels for low-res
@export var grid_painter_path: NodePath      # Path to GridPainter node
@export var auto_sync_to_grid: bool = true   # Auto-sync on paint
@export var target_surface_id: String = ""   # GridPainter surface ID
@export var auto_save: bool = true
@export var save_path: String = "user://canvas_cube_painter.json"
```

### API Methods

```gdscript
# Face Management
get_current_face() -> String
set_current_face(face_name: String)

# Painting
paint_at_uv(uv: Vector2, color: Color, face_name: String = "")
start_painting()
stop_painting()

# Canvas Management
clear_canvas(color: Color = Color.WHITE, face_name: String = "")
get_face_texture(face_name: String) -> ImageTexture
get_face_image(face_name: String) -> Image
get_all_face_textures() -> Array[ImageTexture]

# GridPainter Integration
sync_all_to_grid_painter()
load_from_grid_painter(face_name: String)

# Persistence
save_all_canvases(path: String = "")
load_all_canvases(path: String = "")
```

### Signals

```gdscript
signal face_changed(face_name: String)  # Emitted when active face changes
signal canvas_updated(face_name: String)  # Emitted when face is painted
```

## GridPainter Integration

### Linking to GridPainter

```gdscript
# In your scene setup
var cube_painter = $CanvasCubePainter
var grid_painter = $GridPainter

cube_painter.grid_painter_path = grid_painter.get_path()
cube_painter.target_surface_id = "left_hand"  # or "body", "head", etc.
cube_painter.auto_sync_to_grid = true
```

### Manual Sync

```gdscript
# Sync all faces to GridPainter
cube_painter.sync_all_to_grid_painter()

# Load from GridPainter
for face in ["front", "back", "left", "right", "top", "bottom"]:
    cube_painter.load_from_grid_painter(face)
```

### Voxel Block Texturing

Perfect for creating custom voxel block textures:

```gdscript
# Create a 16x16 block texture
cube_painter.canvas_resolution = 16
cube_painter.pixel_perfect = true

# Paint each face
cube_painter.set_current_face("top")
# ... paint grass texture ...

cube_painter.set_current_face("bottom")
# ... paint dirt texture ...

cube_painter.set_current_face("front")
# ... paint grass side texture ...

# Sync to voxel system
cube_painter.sync_all_to_grid_painter()
```

## UI Controls

### Face Selector Grid
```
    [Top]
[Left] [Front] [Right]
    [Back]
    [Bottom]
```

### Controls
- **Resolution**: Set pixels per face (1-512)
- **Brush Size**: Adjust brush radius (1-20)
- **Color Picker**: Choose brush color
- **Pixel Perfect**: Toggle crisp/smooth rendering
- **Clear Face**: Clear current face only
- **Clear All**: Clear all 6 faces
- **Save/Load**: Persist to JSON file
- **Sync to Grid**: Apply to GridPainter

## Examples

### Minecraft-Style Block

```gdscript
extends Node3D

@onready var cube_painter = $CanvasCubePainter

func _ready():
    cube_painter.canvas_resolution = 16
    cube_painter.pixel_perfect = true
    
    # Create grass block
    create_grass_block()

func create_grass_block():
    # Top - grass
    cube_painter.set_current_face("top")
    paint_grass_top()
    
    # Bottom - dirt
    cube_painter.set_current_face("bottom")
    paint_dirt()
    
    # Sides - grass side
    for side in ["front", "back", "left", "right"]:
        cube_painter.set_current_face(side)
        paint_grass_side()

func paint_grass_top():
    # Fill with green
    cube_painter.clear_canvas(Color(0.2, 0.8, 0.2))
    # Add some variation...

func paint_dirt():
    cube_painter.clear_canvas(Color(0.6, 0.4, 0.2))

func paint_grass_side():
    # Top half green, bottom half brown
    for y in range(16):
        for x in range(16):
            var color = Color(0.2, 0.8, 0.2) if y < 8 else Color(0.6, 0.4, 0.2)
            var uv = Vector2(float(x) / 16.0, float(y) / 16.0)
            cube_painter.paint_at_uv(uv, color)
```

### Avatar Skin Editor

```gdscript
# Link to player avatar GridPainter
cube_painter.grid_painter_path = player.get_node("GridPainter").get_path()
cube_painter.target_surface_id = "body"
cube_painter.canvas_resolution = 32
cube_painter.auto_sync_to_grid = true

# Load existing skin
for face in cube_painter.FACE_NAMES:
    cube_painter.load_from_grid_painter(face)

# Now paint to customize
# Changes automatically sync to avatar
```

### Dice Creator

```gdscript
func create_dice():
    cube_painter.canvas_resolution = 64
    cube_painter.pixel_perfect = false  # Smooth for dice
    
    var faces = ["front", "back", "left", "right", "top", "bottom"]
    var dots = [1, 6, 2, 5, 3, 4]  # Opposite faces sum to 7
    
    for i in range(6):
        cube_painter.set_current_face(faces[i])
        cube_painter.clear_canvas(Color.WHITE)
        draw_dots(dots[i])

func draw_dots(count: int):
    # Draw dots in standard dice pattern
    var center = Vector2(0.5, 0.5)
    # ... draw dots based on count ...
```

## Performance Considerations

- **Resolution**: 16x16 is optimal for pixel art, 64x64 for detailed work
- **Auto-Sync**: Disable for better performance during intensive painting
- **Pixel Perfect**: NEAREST filtering is faster than LINEAR
- **Save Frequency**: Auto-save debounced to 1 second

## Integration with Voxel Tool

The Canvas Cube Painter is designed to work seamlessly with the voxel system:

```gdscript
# In voxel tool
var block_texture = cube_painter.get_all_face_textures()
voxel_tool.set_block_texture(block_id, block_texture)
```

## Troubleshooting

### Faces not syncing to GridPainter
- Check `grid_painter_path` is set correctly
- Verify `target_surface_id` matches GridPainter surface
- Ensure GridPainter has matching subdivisions

### Wrong face orientation
- Face normals follow Godot's coordinate system (+Y is up)
- Check FACE_NORMALS array for reference

### Painting not working
- Verify handler script is attached to face mesh
- Check that mesh is in `pointer_interactable` group
- Ensure painter path is set in handler

### Performance issues
- Reduce canvas resolution
- Disable auto-sync during painting
- Use pixel_perfect mode for better performance

## Future Enhancements

- [ ] 3D cube preview showing all faces
- [ ] Copy/paste between faces
- [ ] Mirror/flip face tools
- [ ] Rotate face 90/180/270 degrees
- [ ] Import image to face
- [ ] Export individual faces as PNG
- [ ] Symmetry painting mode
- [ ] Face templates library
- [ ] Undo/redo per face
- [ ] Animation frames (multiple cubes)

## See Also

- `docs/CANVAS_PAINTER.md` - Single canvas painter
- `docs/VOXEL_SYSTEM.md` - Voxel tool integration
- `src/systems/grid_painter.gd` - GridPainter system
