# Painted Cube 3D Preview

A live 3D preview cube that displays textures from the Canvas Cube Painter in real-time.

## Overview

The `PaintedCube` component creates a 3D cube mesh that automatically updates as you paint on the Canvas Cube Painter. Perfect for seeing your block textures or cube designs in 3D while you work!

## Features

- **Live Updates**: Cube texture updates in real-time as you paint
- **Auto Rotation**: Optional automatic rotation to see all sides
- **Adjustable Speed**: Control rotation speed
- **Pixel Perfect Support**: Respects the painter's pixel perfect setting
- **Texture Atlas**: Efficiently combines all 6 faces into one texture

## Files

- `src/objects/painted_cube.gd` - PaintedCube class
- `src/objects/PaintedCube.tscn` - Cube scene
- `src/test/CanvasCubePainterWithPreview.tscn` - Test scene with split view
- `src/test/canvas_cube_painter_with_preview.gd` - Test scene controller

## Usage

### Test Scene

Run `src/test/CanvasCubePainterWithPreview.tscn` to see:
- **Left Side**: Canvas Cube Painter UI with face selector
- **Right Side**: Live 3D preview of the painted cube

### Adding to Your Scene

```gdscript
# Method 1: Set path in inspector
var painted_cube = PaintedCube.new()
painted_cube.canvas_cube_painter_path = $CanvasCubePainter.get_path()
add_child(painted_cube)

# Method 2: Set reference directly
var painted_cube = PaintedCube.new()
painted_cube.set_canvas_cube_painter($CanvasCubePainter)
add_child(painted_cube)
```

### Properties

```gdscript
@export var canvas_cube_painter_path: NodePath  # Path to CanvasCubePainter
@export var cube_size: float = 1.0              # Size of the cube
@export var auto_rotate: bool = true            # Enable auto rotation
@export var rotation_speed: float = 0.5         # Rotation speed (radians/sec)
```

## How It Works

### Texture Atlas Layout

The cube uses a texture atlas that combines all 6 faces:

```
Row 1: [Left] [Top] [Right]
Row 2: [Back] [Front] [Bottom]
```

This matches the GridPainter layout for consistency.

### UV Mapping

Each face of the cube is UV mapped to its corresponding section in the atlas:
- Front: Center bottom (1/3, 1/2)
- Back: Left bottom (0, 1/2)
- Right: Right top (2/3, 0)
- Left: Left top (0, 0)
- Top: Center top (1/3, 0)
- Bottom: Right bottom (2/3, 1/2)

### Real-Time Updates

The cube connects to the Canvas Cube Painter's signals:
- `canvas_updated(face_name)` - Rebuilds atlas when any face is painted
- `face_changed(face_name)` - Optional: could highlight current face

## Examples

### Basic Preview Window

```gdscript
extends Node3D

@onready var painted_cube = $PaintedCube
@onready var canvas_painter = $CanvasCubePainter

func _ready():
    painted_cube.set_canvas_cube_painter(canvas_painter)
    painted_cube.auto_rotate = true
    painted_cube.rotation_speed = 1.0
```

### Side-by-Side Editor

```gdscript
# Split screen with painter on left, preview on right
var hsplit = HSplitContainer.new()

# Left: Canvas painter UI
var painter_ui = preload("res://src/ui/CanvasCubePainterUI.tscn").instantiate()
hsplit.add_child(painter_ui)

# Right: 3D preview
var preview_viewport = SubViewportContainer.new()
var viewport = SubViewport.new()
var camera = Camera3D.new()
var cube = preload("res://src/objects/PaintedCube.tscn").instantiate()

viewport.add_child(camera)
viewport.add_child(cube)
preview_viewport.add_child(viewport)
hsplit.add_child(preview_viewport)

# Connect them
cube.canvas_cube_painter_path = painter_ui.canvas_cube_painter.get_path()
```

### VR Block Editor

```gdscript
# Floating cube preview in VR
var cube = preload("res://src/objects/PaintedCube.tscn").instantiate()
cube.canvas_cube_painter_path = $CanvasCubePainter.get_path()
cube.global_position = player.global_position + Vector3(0, 1.5, -1)
cube.auto_rotate = true
add_child(cube)
```

### Multiple Cubes (Block Palette)

```gdscript
# Show multiple painted cubes in a grid
var block_types = ["grass", "stone", "wood", "dirt"]
var x_offset = 0.0

for block_type in block_types:
    var cube = preload("res://src/objects/PaintedCube.tscn").instantiate()
    cube.canvas_cube_painter_path = get_node("Painters/" + block_type).get_path()
    cube.position = Vector3(x_offset, 0, 0)
    cube.auto_rotate = false
    add_child(cube)
    x_offset += 2.0
```

## Integration with Voxel System

The painted cube can be used to preview voxel blocks before placing them:

```gdscript
# Preview block before placing
func preview_block(block_id: int):
    var painter = get_block_painter(block_id)
    preview_cube.set_canvas_cube_painter(painter)
    preview_cube.visible = true

func place_block():
    # Use the same textures from the preview
    var textures = preview_cube._canvas_cube_painter.get_all_face_textures()
    voxel_tool.place_block_with_textures(textures)
```

## Performance Tips

- **Resolution**: Lower resolution (16x16) updates faster than high-res
- **Auto Rotate**: Disable if you have many cubes
- **Pixel Perfect**: NEAREST filtering is faster than LINEAR
- **Atlas Caching**: Atlas is only rebuilt when faces change

## Customization

### Custom Cube Size

```gdscript
painted_cube.cube_size = 2.0  # Larger cube
```

### Custom Rotation

```gdscript
# Disable auto-rotate and control manually
painted_cube.auto_rotate = false

func _process(delta):
    painted_cube.rotate_y(delta * custom_speed)
    painted_cube.rotate_x(delta * custom_speed * 0.5)
```

### Highlight Current Face

You could extend the PaintedCube to highlight the currently selected face:

```gdscript
func _on_face_changed(face_name: String):
    # Add emission to current face
    # Or draw an outline
    # Or scale that face slightly
    pass
```

## Troubleshooting

### Cube not updating
- Check that `canvas_cube_painter_path` is set correctly
- Verify signals are connected (check console for "Connected to canvas cube painter")
- Ensure Canvas Cube Painter is in the scene tree

### Textures look wrong
- Verify UV mapping matches your atlas layout
- Check that all 6 faces are painted
- Ensure pixel_perfect setting matches your needs

### Performance issues
- Reduce canvas resolution
- Disable auto_rotate
- Use pixel_perfect mode (NEAREST filtering)

### Cube appears black
- Check that DirectionalLight3D is in the scene
- Verify material is set to UNSHADED mode
- Ensure textures are being created

## See Also

- `CANVAS_CUBE_PAINTER.md` - Canvas Cube Painter documentation
- `VOXEL_SYSTEM.md` - Voxel integration
- `CANVAS_SYSTEMS_OVERVIEW.md` - Overview of all canvas systems
