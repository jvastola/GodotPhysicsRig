# Design Document: WebView Scroll Fix

## Overview

This design fixes the scrolling behavior in the WebView panel for VR. The current implementation incorrectly routes scroll gestures through a Godot VScrollBar UI element, causing visual artifacts, wrong scroll direction, and type errors. The fix implements direct drag-to-scroll behavior that sends touch/scroll events directly to the Android WebView backend.

## Architecture

The fix modifies two components:

1. **webview_viewport_3d.gd** - The main panel script that handles pointer events
2. **android_webview_backend.gd** - The Android backend that communicates with the native WebView

### Current Flow (Broken)
```
Pointer Drag → VScrollBar.value → scrollToPosition() → WebView
                    ↓
              Godot UI scrolls (wrong!)
```

### Fixed Flow
```
Pointer Drag → Track delta → scrollByAmount(delta) → WebView JavaScript scroll
```

## Components and Interfaces

### WebviewViewport3D Changes

**New State Variables:**
- `_drag_start_pos: Vector2` - Position where drag started
- `_last_drag_pos: Vector2` - Previous frame's drag position
- `_is_dragging: bool` - Whether user is currently dragging to scroll

**Modified Methods:**
- `handle_pointer_event()` - Track drag state and calculate scroll delta
- Remove VScrollBar-based scrolling logic

### AndroidWebViewBackend Changes

**Modified Methods:**
- `_on_scroll_info_received()` - Fix type error by properly handling null/invalid JSON

## Data Models

### Drag State
```gdscript
var _drag_start_pos: Vector2 = Vector2.ZERO
var _last_drag_pos: Vector2 = Vector2.ZERO  
var _is_dragging: bool = false
```

### Scroll Delta Calculation
```gdscript
# When dragging:
var delta_y = current_pos.y - _last_drag_pos.y
# Positive delta_y (drag down in screen space) = scroll content down = positive scroll
# Negative delta_y (drag up in screen space) = scroll content up = negative scroll
_backend.scroll_by_amount(int(-delta_y))  # Invert for natural scrolling feel
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system-essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Scroll Direction Consistency
*For any* drag gesture with a Y delta, the scroll command sent to the backend SHALL have the opposite sign (drag up = negative delta = scroll up/content moves up).
**Validates: Requirements 1.2, 1.3**

### Property 2: Scroll Magnitude Proportionality  
*For any* drag delta, the absolute value of the scroll amount sent to the backend SHALL equal the absolute value of the drag delta (1:1 mapping).
**Validates: Requirements 1.4**

### Property 3: Drag State Release
*For any* pointer release event, the drag state SHALL be cleared and no further scroll commands SHALL be sent until a new press event.
**Validates: Requirements 1.5**

### Property 4: Direct Backend Scrolling
*For any* scroll gesture on web content, the system SHALL call the backend's scrollByAmount method directly without modifying any Godot UI scroll controls.
**Validates: Requirements 2.1, 2.2**

### Property 5: Scroll Info Null Safety
*For any* scroll_info_received signal with null, empty, or malformed JSON, the handler SHALL not throw a type error and SHALL handle the data gracefully.
**Validates: Requirements 3.1, 3.2**

## Error Handling

### Scroll Info Parsing
The current error occurs because `json.data` returns `null` when parsing fails or when the JSON is empty, but the code tries to assign it to a `Dictionary` typed variable.

**Fix:**
```gdscript
func _on_scroll_info_received(json_str: String) -> void:
    if json_str.is_empty() or json_str == "null":
        push_warning("AndroidWebViewBackend: Received empty scroll info")
        return
    
    var json := JSON.new()
    var error := json.parse(json_str)
    if error != OK:
        push_warning("AndroidWebViewBackend: Failed to parse scroll info: ", json_str)
        return
    
    var data = json.data  # Don't type as Dictionary yet
    if data == null or not data is Dictionary:
        push_warning("AndroidWebViewBackend: Invalid scroll info data type")
        return
    
    # Now safe to use as Dictionary
    var scroll_y: int = int(data.get("scrollY", 0))
    # ... rest of handling
```

## Testing Strategy

### Unit Tests
- Test scroll delta calculation with various input positions
- Test drag state transitions (press → drag → release)
- Test JSON parsing edge cases (null, empty, malformed)

### Property-Based Tests
Using GdUnit4 or similar framework:

1. **Scroll Direction Property Test**
   - Generate random drag deltas
   - Verify scroll command sign is opposite to delta sign

2. **Scroll Magnitude Property Test**
   - Generate random drag deltas
   - Verify |scroll_amount| == |delta|

3. **Null Safety Property Test**
   - Generate various malformed JSON strings
   - Verify no exceptions thrown

### Integration Tests
- Manual testing on Quest 3 to verify:
  - Drag up scrolls content up
  - Drag down scrolls content down
  - No blank regions appear
  - Scrolling feels responsive and 1:1

