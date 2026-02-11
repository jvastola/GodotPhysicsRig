# Canvas Painting Systems Overview

This document provides an overview of the canvas painting systems available in the project.

## Systems

### 1. Canvas Painter (Single Surface)
**Location**: `src/systems/canvas_painter.gd`

A simple 2D canvas painter for painting on a single flat surface.

**Best For**:
- Whiteboards
- Notepads
- Single image creation
- Quick sketches

**Features**:
- Configurable resolution (1x1 to 2048x2048)
- Adjustable brush size
- Color picker
- Pixel perfect mode
- Save/load PNG

**Test Scene**: `src/test/CanvasPainterTest.tscn`

### 2. Canvas Cube Painter (6 Faces)
**Location**: `src/systems/canvas_cube_painter.gd`

A specialized painter for cube faces with GridPainter integration.

**Best For**:
- Voxel block textures
- Avatar/character skins
- Cube-based objects
- Minecraft-style blocks

**Features**:
- 6 separate canvases (one per face)
- Face switching UI
- GridPainter sync
- Pixel perfect mode (default ON)
- Save/load JSON (all faces)
- Auto-sync to grid

**Test Scene**: `src/test/CanvasCubePainterTest.tscn`

### 3. Grid Painter (Existing)
**Location**: `src/systems/grid_painter.gd`

The existing grid-based painter for avatar surfaces and voxel blocks.

**Best For**:
- Avatar customization
- Player skins
- Complex multi-surface objects
- Voxel world blocks

## Comparison

| Feature | Canvas Painter | Canvas Cube Painter | Grid Painter |
|---------|---------------|---------------------|--------------|
| Surfaces | 1 | 6 (cube faces) | Multiple (configurable) |
| Resolution | 1-2048 | 1-512 per face | Grid-based |
| Format | PNG | JSON | JSON |
| GridPainter Sync | No | Yes | N/A (is GridPainter) |
| Best Use | Single images | Block textures | Avatar skins |
| Pixel Perfect | Optional | Default ON | Always ON |
| VR Support | Yes | Yes | Yes |

## When to Use Each

### Use Canvas Painter When:
- You need a simple drawing surface
- Creating standalone images
- Building a whiteboard or notepad
- Don't need cube/grid integration

### Use Canvas Cube Painter When:
- Creating voxel block textures
- Need to paint all 6 faces of a cube
- Want to sync with GridPainter
- Building Minecraft-style blocks
- Creating cube-based game assets

### Use Grid Painter When:
- Customizing avatar/character skins
- Need complex multi-surface layouts
- Working with existing voxel system
- Require precise grid-based painting

## Integration Examples

### Canvas Cube → Grid Painter
```gdscript
# Paint a block texture and sync to grid
var cube_painter = $CanvasCubePainter
cube_painter.grid_painter_path = $GridPainter.get_path()
cube_painter.target_surface_id = "block_texture"
cube_painter.auto_sync_to_grid = true

# Paint on faces...
# Automatically syncs to GridPainter
```

### Grid Painter → Canvas Cube
```gdscript
# Load existing grid texture into cube painter
var cube_painter = $CanvasCubePainter
for face in cube_painter.FACE_NAMES:
    cube_painter.load_from_grid_painter(face)

# Now edit in cube painter
# Sync back when done
cube_painter.sync_all_to_grid_painter()
```

### Standalone Canvas
```gdscript
# Simple whiteboard
var canvas = $CanvasPainter
canvas.canvas_width = 1024
canvas.canvas_height = 768
canvas.pixel_perfect = false  # Smooth for writing
canvas.save_path = "user://whiteboard.png"
```

## File Structure

```
src/
├── systems/
│   ├── canvas_painter.gd              # Single canvas
│   ├── canvas_painter_handler.gd      # Single canvas handler
│   ├── canvas_cube_painter.gd         # Cube painter
│   ├── canvas_cube_painter_handler.gd # Cube handler
│   └── grid_painter.gd                # Existing grid system
├── ui/
│   ├── CanvasPainterUI.tscn          # Single canvas UI
│   ├── canvas_painter_ui.gd
│   ├── CanvasPainterViewport3D.tscn
│   ├── canvas_painter_viewport_3d.gd
│   ├── CanvasCubePainterUI.tscn      # Cube painter UI
│   ├── canvas_cube_painter_ui.gd
│   ├── CanvasCubePainterViewport3D.tscn
│   └── canvas_cube_painter_viewport_3d.gd
└── test/
    ├── CanvasPainterTest.tscn         # Single canvas test
    └── CanvasCubePainterTest.tscn     # Cube painter test

docs/
├── CANVAS_PAINTER.md                  # Single canvas docs
├── CANVAS_PAINTER_INTEGRATION.md      # Integration guide
├── CANVAS_CUBE_PAINTER.md             # Cube painter docs
└── CANVAS_SYSTEMS_OVERVIEW.md         # This file
```

## Quick Start

### Desktop Testing

1. **Single Canvas**: Open `src/test/CanvasPainterTest.tscn` and run
2. **Cube Painter**: Open `src/test/CanvasCubePainterTest.tscn` and run

### VR Integration

Add to watch menu or spawn as panel:
```gdscript
# Single canvas
var canvas_panel = preload("res://src/ui/CanvasPainterPanel.tscn").instantiate()
add_child(canvas_panel)

# Cube painter
var cube_panel = preload("res://src/ui/CanvasCubePainterUI.tscn").instantiate()
add_child(cube_panel)
```

## Common Workflows

### Creating a Voxel Block
1. Open Canvas Cube Painter
2. Set resolution to 16x16
3. Enable Pixel Perfect
4. Paint each face (top, bottom, sides)
5. Click "Sync to Grid"
6. Block texture applied to voxel system

### Creating a Whiteboard
1. Open Canvas Painter
2. Set size to 1024x768
3. Disable Pixel Perfect
4. Paint/write content
5. Save to PNG

### Customizing Avatar
1. Use Grid Painter directly
2. Or: Load into Canvas Cube Painter
3. Edit faces individually
4. Sync back to Grid Painter

## Tips

- **Pixel Art**: Use Canvas Cube Painter with 16x16 or 32x32 resolution
- **Smooth Art**: Use Canvas Painter with Pixel Perfect OFF
- **Performance**: Lower resolution = better performance
- **VR Painting**: Both systems work with hand pointer raycast
- **Desktop Testing**: Both have mouse input support

## See Also

- `CANVAS_PAINTER.md` - Detailed single canvas documentation
- `CANVAS_CUBE_PAINTER.md` - Detailed cube painter documentation
- `VOXEL_SYSTEM.md` - Voxel tool integration
- `PROJECT_STRUCTURE.md` - Overall project structure
