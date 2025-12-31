# Design Document: Webview Panel

## Overview

This design describes the implementation of a webview panel for the VR scene using the gdCEF plugin (Chromium Embedded Framework). The panel will render web content to a 3D quad mesh that users can interact with using VR controllers, following the existing UI panel patterns in the project.

## Architecture

The webview panel follows the established pattern of other UI panels in the project:

```
WebviewViewport3D (Node3D)
├── GDCef (CEF Manager Node)
├── SubViewport
│   └── TextureRect (receives browser texture)
├── MeshInstance3D (quad with viewport texture)
│   └── StaticBody3D
│       └── CollisionShape3D
```

The gdCEF plugin provides:
- `GDCef` node: Manages CEF initialization and browser lifecycle
- `GDBrowserView`: Individual browser instance that renders to a texture

## Components and Interfaces

### WebviewViewport3D

Main script that manages the webview panel, extending the existing viewport pattern.

```gdscript
class_name WebviewViewport3D
extends Node3D

# Exports
@export var pointer_group: StringName = &"pointer_interactable"
@export var default_url: String = "https://www.google.com"
@export var ui_size: Vector2 = Vector2(1280, 720)
@export var quad_size: Vector2 = Vector2(2.56, 1.44)  # 16:9 aspect ratio
@export var debug_coordinates: bool = false
@export var flip_v: bool = true

# Signals
signal page_loaded(url: String)
signal page_loading(url: String)

# Public Methods
func load_url(url: String) -> void
func get_current_url() -> String
func reload() -> void
func go_back() -> void
func go_forward() -> void
func can_go_back() -> bool
func can_go_forward() -> bool

# Pointer Interface (matches existing panels)
func handle_pointer_event(event: Dictionary) -> void
func pointer_grab_set_distance(new_distance: float, pointer: Node3D) -> void
func pointer_grab_set_scale(new_scale: float) -> void
func pointer_grab_set_rotation(pointer: Node3D, grab_point: Vector3) -> void
func pointer_grab_get_distance(pointer: Node3D) -> float
func pointer_grab_get_scale() -> float
func set_interactive(enabled: bool) -> void
```

### GDCef Integration

The gdCEF plugin exposes these key methods:

```gdscript
# GDCef node methods
func initialize(settings: Dictionary) -> bool
func create_browser(url: String, texture_rect: TextureRect, settings: Dictionary) -> GDBrowserView
func shutdown() -> void

# GDBrowserView methods  
func load_url(url: String) -> void
func get_url() -> String
func is_loaded() -> bool
func resize(width: int, height: int) -> void
func on_mouse_moved(x: int, y: int) -> void
func on_mouse_left_down() -> void
func on_mouse_left_up() -> void
func on_mouse_wheel(delta: int) -> void
func on_key_pressed(key: int, pressed: bool, shift: bool, alt: bool, ctrl: bool) -> void
func get_texture() -> ImageTexture
```

### Pointer Event Translation

The panel translates VR pointer events to browser input:

| VR Event | Browser Action |
|----------|----------------|
| hover | on_mouse_moved(x, y) |
| press | on_mouse_left_down() |
| release | on_mouse_left_up() |
| scroll | on_mouse_wheel(delta) |

Coordinate translation from 3D hit position to browser coordinates:
1. Transform hit position to mesh local space
2. Convert to UV coordinates (0-1 range)
3. Scale to browser resolution (ui_size)

## Data Models

### CEF Initialization Settings

```gdscript
var cef_settings := {
    "artifacts": "res://cef_artifacts/",
    "locale": "en-US",
    "remote_debugging_port": 0,  # Disabled by default
    "enable_media_stream": false,
    "cache_path": "user://cef_cache/"
}
```

### Browser Settings

```gdscript
var browser_settings := {
    "javascript": true,
    "javascript_close_windows": false,
    "javascript_access_clipboard": false,
    "javascript_dom_paste": false,
    "image_loading": true,
    "databases": false,
    "webgl": true
}
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: URL Loading Consistency

*For any* valid URL string, when `load_url(url)` is called, `get_current_url()` should eventually return that URL (after page load completes).

**Validates: Requirements 1.1, 2.1, 2.2**

### Property 2: Pointer Event Coordinate Translation

*For any* pointer hit position within the panel bounds, the translated browser coordinates should be within the range [0, ui_size.x] for X and [0, ui_size.y] for Y.

**Validates: Requirements 3.1, 3.2, 3.3**

### Property 3: Panel Interactivity Toggle

*For any* panel state, calling `set_interactive(false)` should disable collision detection, and calling `set_interactive(true)` should restore it.

**Validates: Requirements 3.4, 4.1**

## Error Handling

### CEF Initialization Failures

```gdscript
func _initialize_cef() -> bool:
    if not _cef_node:
        push_error("WebviewViewport3D: GDCef node not found")
        return false
    
    if not _cef_node.initialize(cef_settings):
        push_error("WebviewViewport3D: Failed to initialize CEF")
        _show_error_placeholder("CEF initialization failed")
        return false
    
    return true
```

### Missing CEF Artifacts

If the gdCEF addon is not installed, the panel should:
1. Display a placeholder message
2. Log an error with installation instructions
3. Remain interactive but non-functional

### Browser Creation Failures

```gdscript
func _create_browser() -> bool:
    _browser = _cef_node.create_browser(default_url, _texture_rect, browser_settings)
    if not _browser:
        push_error("WebviewViewport3D: Failed to create browser")
        _show_error_placeholder("Browser creation failed")
        return false
    return true
```

## Testing Strategy

### Unit Tests

Unit tests should verify:
- Panel initialization with valid/invalid CEF installation
- URL loading and retrieval
- Coordinate translation accuracy
- Event forwarding to browser

### Property-Based Tests

Property tests should use a property-based testing library (e.g., GUT with custom generators) to verify:
- **Property 1**: Generate random valid URLs and verify round-trip consistency
- **Property 2**: Generate random hit positions and verify coordinate bounds
- **Property 3**: Generate random sequences of interactive state changes

### Integration Tests

- Verify panel appears in MainScene at correct position
- Verify panel is accessible via UIPanelManager
- Verify pointer interaction works end-to-end

## File Structure

```
src/ui/webview/
├── webview_viewport_3d.gd       # Main panel script
├── webview_viewport_3d.gd.uid
├── WebviewViewport3D.tscn       # Panel scene
└── webview_ui.gd                # Optional: URL bar UI (future)
```

## Dependencies

- **gdCEF addon**: Must be installed in `addons/gdcef/` with artifacts in `cef_artifacts/`
- **Existing UI infrastructure**: Uses patterns from `ui_viewport_3d.gd`
- **UIPanelManager**: For panel lifecycle management
