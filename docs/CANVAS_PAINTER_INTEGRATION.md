# Canvas Painter Integration Guide

This guide shows how to integrate the Canvas Painter into your VR application.

## Quick Start

### 1. Desktop Testing

Open and run `src/test/CanvasPainterTest.tscn` to test the canvas painter with mouse input.

### 2. VR Integration

Add the canvas painter panel to your VR scene:

```gdscript
# In your VR scene or watch menu
var canvas_panel = preload("res://src/ui/CanvasPainterPanel.tscn").instantiate()
add_child(canvas_panel)
canvas_panel.global_position = Vector3(0, 1.5, -1)  # Position in front of player
```

## Watch Menu Integration

To add a Canvas Painter button to the watch menu:

### Step 1: Add Button to Watch Menu UI

Edit `src/ui/WatchMenuUI.tscn` and add a new button:

```
[node name="CanvasPainterButton" type="Button" parent="..."]
text = "Canvas Painter"
```

### Step 2: Connect Button Signal

In `src/ui/watch_menu_ui.gd`, add:

```gdscript
@onready var canvas_painter_button: Button = $Path/To/CanvasPainterButton

func _ready():
    # ... existing code ...
    canvas_painter_button.pressed.connect(_on_canvas_painter_pressed)

func _on_canvas_painter_pressed():
    var panel_manager = get_node("/root/MainScene/UIPanelManager")
    if panel_manager and panel_manager.has_method("spawn_panel"):
        panel_manager.spawn_panel("canvas_painter")
```

### Step 3: Register Panel Type

In `src/ui/ui_panel_manager.gd`, add the canvas painter panel:

```gdscript
const PANEL_SCENES = {
    # ... existing panels ...
    "canvas_painter": "res://src/ui/CanvasPainterPanel.tscn"
}
```

## Standalone Usage

### Create a Grabbable Canvas

```gdscript
extends Node3D

@onready var canvas_painter = $CanvasPainter
@onready var canvas_mesh = $CanvasMesh

func _ready():
    # Configure canvas
    canvas_painter.canvas_width = 1024
    canvas_painter.canvas_height = 1024
    canvas_painter.brush_size = 8
    canvas_painter.default_brush_color = Color(0.2, 0.5, 1.0)
    
    # Make it grabbable (if using grabbable system)
    add_to_group("grabbable")
```

### Floating Canvas in World

```gdscript
# Spawn a canvas at a specific location
func spawn_canvas_at(position: Vector3):
    var canvas = preload("res://src/ui/CanvasPainterPanel.tscn").instantiate()
    get_parent().add_child(canvas)
    canvas.global_position = position
    canvas.look_at(get_viewport().get_camera_3d().global_position)
```

## Customization Examples

### Art Gallery Canvas

```gdscript
# Large high-res canvas for detailed artwork
canvas_painter.canvas_width = 2048
canvas_painter.canvas_height = 2048
canvas_painter.canvas_physical_size = Vector2(2.0, 2.0)
canvas_painter.brush_size = 3
canvas_painter.save_path = "user://gallery/artwork_01.png"
```

### Quick Sketch Pad

```gdscript
# Small fast canvas for quick notes
canvas_painter.canvas_width = 256
canvas_painter.canvas_height = 256
canvas_painter.canvas_physical_size = Vector2(0.3, 0.3)
canvas_painter.brush_size = 15
canvas_painter.background_color = Color(1, 1, 0.9)  # Notepad yellow
```

### Whiteboard

```gdscript
# Whiteboard-style canvas
canvas_painter.canvas_width = 1024
canvas_painter.canvas_height = 768
canvas_painter.canvas_physical_size = Vector2(1.6, 1.2)
canvas_painter.background_color = Color.WHITE
canvas_painter.default_brush_color = Color.BLACK
canvas_painter.brush_size = 6
```

## Advanced Features

### Multi-User Painting

For networked painting, sync paint events:

```gdscript
# On local paint
func _on_local_paint(uv: Vector2, color: Color):
    rpc("remote_paint", uv, color)

@rpc("any_peer", "call_remote")
func remote_paint(uv: Vector2, color: Color):
    canvas_painter.paint_at_uv(uv, color)
```

### Recording Painting Session

```gdscript
var paint_history: Array = []

func record_paint(uv: Vector2, color: Color):
    paint_history.append({"uv": uv, "color": color, "time": Time.get_ticks_msec()})
    canvas_painter.paint_at_uv(uv, color)

func replay_painting():
    canvas_painter.clear_canvas()
    for stroke in paint_history:
        await get_tree().create_timer(0.01).timeout
        canvas_painter.paint_at_uv(stroke.uv, stroke.color)
```

### Color Palette System

```gdscript
const PALETTE = [
    Color.RED, Color.GREEN, Color.BLUE,
    Color.YELLOW, Color.MAGENTA, Color.CYAN,
    Color.BLACK, Color.WHITE
]

var current_color_index = 0

func cycle_color():
    current_color_index = (current_color_index + 1) % PALETTE.size()
    canvas_painter.default_brush_color = PALETTE[current_color_index]
```

## Performance Tips

1. **Resolution**: Start with 512x512 and increase only if needed
2. **Brush Size**: Larger brushes (>20) can impact performance
3. **Auto-Save**: Disable for temporary canvases
4. **Texture Format**: RGBA8 is optimal for most use cases

## Troubleshooting

### Canvas appears black
- Check that `background_color` is set
- Verify lighting in the scene
- Ensure material is unshaded

### Painting is laggy
- Reduce canvas resolution
- Decrease brush size
- Check if auto-save is causing delays

### Can't paint with VR controllers
- Verify hand pointer system is active
- Check that canvas mesh is in `pointer_interactable` group
- Ensure handler script is attached

### Saved images are corrupted
- Check disk space
- Verify write permissions for save path
- Use `user://` directory for saves

## Example Scenes

Check these example scenes for reference:

- `src/test/CanvasPainterTest.tscn` - Desktop test
- `src/ui/CanvasPainterPanel.tscn` - VR panel
- `src/ui/CanvasPainterViewport3D.tscn` - Viewport setup

## API Reference

See `docs/CANVAS_PAINTER.md` for complete API documentation.
