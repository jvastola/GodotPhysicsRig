# Design Document: Webview Panel

## Overview

This design describes the implementation of a cross-platform webview panel for VR scenes. The panel renders web content to a 3D quad mesh that users can interact with using VR controllers, following the existing UI panel patterns in the project.

The system uses a platform abstraction layer to provide a unified API regardless of the underlying backend:
- **Desktop**: gdCEF (Chromium Embedded Framework)
- **Android/Quest**: Native Android WebView via Godot plugin

## Architecture

### High-Level Design

```
┌──────────────────────────────────────┐
│         Godot Application            │
│  ┌────────────────────────────────┐  │
│  │   WebviewViewport3D (GDScript) │  │
│  └──────────────┬─────────────────┘  │
│                 │                     │
│  ┌──────────────┴─────────────────┐  │
│  │  Platform Abstraction Layer    │  │
│  │     (WebViewBackend)           │  │
│  └──────────────┬─────────────────┘  │
│                 │                     │
│     ┌───────────┴───────────┐        │
│     │                       │        │
│  ┌──▼───────┐        ┌──────▼────┐  │
│  │ CEF      │        │ Android   │  │
│  │ Backend  │        │ WebView   │  │
│  │(Desktop) │        │ Backend   │  │
│  └──────────┘        └───────────┘  │
└──────────────────────────────────────┘
```

### Scene Structure

```
WebviewViewport3D (Node3D)
├── SubViewport
│   ├── TextureRect (receives browser texture)
│   └── PlaceholderLabel (shown when no backend)
├── MeshInstance3D (quad with viewport texture)
│   └── StaticBody3D
│       └── CollisionShape3D
```

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
signal close_requested

# Public Methods
func load_url(url: String) -> void
func get_current_url() -> String
func reload() -> void
func go_back() -> void
func go_forward() -> void
func can_go_back() -> bool
func can_go_forward() -> bool
func stop_loading() -> void
func is_backend_available() -> bool
func get_backend_name() -> String

# Pointer Interface (matches existing panels)
func handle_pointer_event(event: Dictionary) -> void
func pointer_grab_set_distance(new_distance: float, pointer: Node3D) -> void
func pointer_grab_set_scale(new_scale: float) -> void
func pointer_grab_set_rotation(pointer: Node3D, grab_point: Vector3) -> void
func pointer_grab_get_distance(pointer: Node3D) -> float
func pointer_grab_get_scale() -> float
func set_interactive(enabled: bool) -> void
```

### WebViewBackend (Abstract Base Class)

```gdscript
class_name WebViewBackend
extends RefCounted

# Signals
signal page_loaded(url: String)
signal page_loading(url: String)
signal load_progress(progress: float)
signal page_title_changed(title: String)
signal error_occurred(error_code: int, description: String)
signal texture_updated()

# Abstract Methods
func initialize(settings: Dictionary) -> bool
func shutdown() -> void
func load_url(url: String) -> void
func get_url() -> String
func is_loaded() -> bool
func reload() -> void
func go_back() -> void
func go_forward() -> void
func can_go_back() -> bool
func can_go_forward() -> bool
func stop_loading() -> void
func resize(width: int, height: int) -> void
func send_mouse_move(x: int, y: int) -> void
func send_mouse_down(x: int, y: int, button: int = 0) -> void
func send_mouse_up(x: int, y: int, button: int = 0) -> void
func send_scroll(x: int, y: int, delta: float) -> void
func send_key(keycode: int, pressed: bool, shift: bool, alt: bool, ctrl: bool) -> void
func send_text(text: String) -> void
func get_texture() -> Texture2D
static func is_available() -> bool
func get_backend_name() -> String
```

### DesktopCEFBackend

Wraps gdCEF for desktop platforms (Windows, macOS, Linux).

```gdscript
class_name DesktopCEFBackend
extends WebViewBackend

# CEF Settings
var _cef_settings := {
    "artifacts": "res://cef_artifacts/",
    "locale": "en-US",
    "remote_debugging_port": 0,
    "enable_media_stream": false,
    "cache_path": "user://cef_cache/"
}

var _browser_settings := {
    "javascript": true,
    "javascript_close_windows": false,
    "javascript_access_clipboard": false,
    "javascript_dom_paste": false,
    "image_loading": true,
    "databases": false,
    "webgl": true
}
```

### AndroidWebViewBackend

Uses native Android WebView via Godot plugin.

```gdscript
class_name AndroidWebViewBackend
extends WebViewBackend

# Update rate limiting (~30 FPS)
var _update_interval: float = 0.033

# Requires GodotAndroidWebView plugin singleton
# Texture updates via getPixelData() -> PackedByteArray
```

### Android Plugin (Java)

The `GodotAndroidWebView` Java class provides:
- WebView initialization and lifecycle management
- Bitmap rendering to ByteBuffer
- Touch event forwarding (touchDown, touchMove, touchUp, scroll)
- JavaScript execution
- Navigation (back, forward, reload)
- Signals: page_loaded, page_started, progress_changed, title_changed

### Pointer Event Translation

The panel translates VR pointer events to browser input:

| VR Event | Browser Action |
|----------|----------------|
| enter/hover | send_mouse_move(x, y) |
| press | send_mouse_down(x, y) |
| release | send_mouse_up(x, y) |
| scroll | send_scroll(x, y, delta) |

Coordinate translation from 3D hit position to browser coordinates:
1. Transform hit position to mesh local space
2. Convert to UV coordinates (0-1 range)
3. Scale to browser resolution (ui_size)
4. Apply flip_v if needed

## Data Models

### Backend Initialization Settings

```gdscript
var settings := {
    "width": int(ui_size.x),
    "height": int(ui_size.y),
    "url": default_url,
    "parent_node": self,
    "texture_rect": _texture_rect,
}
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: URL Loading Consistency

*For any* valid URL string, when `load_url(url)` is called, `get_current_url()` should eventually return that URL (after page load completes).

**Validates: Requirements 1.1, 2.1, 2.2**

### Property 2: Pointer Event Coordinate Translation

*For any* pointer hit position within the panel bounds, the translated browser coordinates should be within the range [0, ui_size.x] for X and [0, ui_size.y] for Y.

**Validates: Requirements 3.1, 3.2, 3.5**

### Property 3: Panel Interactivity Toggle

*For any* panel state, calling `set_interactive(false)` should disable collision detection, and calling `set_interactive(true)` should restore it.

**Validates: Requirements 3.4, 4.4**

### Property 4: Platform Detection Consistency

*For any* platform, the system should select exactly one backend (Android, Desktop, or Placeholder) and that backend should remain consistent for the lifetime of the panel.

**Validates: Requirements 6.1, 6.2, 6.3, 6.4**

## Error Handling

### Backend Initialization Failures

```gdscript
func _initialize_backend() -> void:
    var platform := OS.get_name()
    
    if platform == "Android":
        _backend = _try_android_backend(settings)
    else:
        _backend = _try_desktop_backend(settings)
    
    # Fallback to placeholder if no backend available
    if not _backend:
        _backend = _create_placeholder_backend(settings)
```

### Missing Dependencies

If the required addon/plugin is not installed:
1. Display a placeholder message with installation instructions
2. Log an error with details
3. Panel remains interactive but non-functional
4. `is_backend_available()` returns false

## Testing Strategy

### Unit Tests

Unit tests should verify:
- Panel initialization with valid/invalid backend availability
- URL loading and retrieval
- Coordinate translation accuracy (UV to pixel)
- Event forwarding to backend
- Platform detection logic

### Property-Based Tests

Property tests should use GUT with custom generators to verify:
- **Property 1**: Generate random valid URLs and verify round-trip consistency
- **Property 2**: Generate random hit positions and verify coordinate bounds
- **Property 3**: Generate random sequences of interactive state changes
- **Property 4**: Verify backend selection is deterministic

### Integration Tests

- Verify panel appears via UIPanelManager
- Verify panel is accessible via quick access menu
- Verify pointer interaction works end-to-end
- Test on both desktop and Quest 3

### Performance Tests

- Frame rate benchmarks (Quest 3 target: 72+ fps maintained)
- Texture update latency measurements
- Memory profiling (target: <200MB on Quest)

## File Structure

```
src/ui/webview/
├── webview_viewport_3d.gd       # Main panel script (platform-agnostic)
├── WebviewViewport3D.tscn       # Panel scene
├── NEXT_STEPS.md                # Implementation notes
└── backends/
    ├── webview_backend.gd       # Abstract base class
    ├── android_webview_backend.gd
    ├── desktop_cef_backend.gd
    └── placeholder_backend.gd

addons/godot_android_webview/
├── plugin.cfg
├── godot_android_webview.gd
├── README.md
└── android_plugin/
    ├── build_plugin.sh
    ├── build.gradle
    ├── settings.gradle
    ├── libs/                    # godot-lib.release.aar
    └── src/main/java/com/godot/webview/
        └── GodotAndroidWebView.java

android/plugins/
├── GodotAndroidWebView.gdap     # Plugin descriptor
└── GodotAndroidWebView.aar      # Built plugin

addons/gdcef/                    # Desktop CEF (external dependency)
cef_artifacts/                   # CEF binaries (external dependency)
```

## Dependencies

- **Android**: GodotAndroidWebView plugin (included in project)
- **Desktop**: gdCEF addon (must be installed separately)
- **Both**: Existing UI infrastructure (UIPanelManager, pointer system)

## Performance Considerations

### Quest 3 Optimization

- Texture updates rate-limited to ~30 FPS
- Default resolution: 1280x720 (configurable)
- ByteBuffer capture mode (stable, compatible)
- Memory target: <200MB

### Desktop Optimization

- CEF handles rendering efficiently
- Texture updates at 60 FPS
- Higher resolution supported (1920x1080)

## Security Considerations

- JavaScript enabled by default (required for most sites)
- No clipboard access
- No file system access beyond cache
- Sandboxed WebView processes (both CEF and Android provide this)
