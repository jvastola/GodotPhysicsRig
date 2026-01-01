# Implementation Plan: WebView Scroll Fix

## Overview

This plan fixes the webview scrolling to use direct drag-to-scroll behavior instead of routing through a Godot VScrollBar.

## Tasks

- [ ] 1. Fix scroll info type error in AndroidWebViewBackend
  - [x] 1.1 Update _on_scroll_info_received to handle null/invalid JSON gracefully
    - Add null/empty string check before parsing
    - Check if parsed data is Dictionary before using
    - Log warnings instead of throwing errors
    - _Requirements: 3.1, 3.2, 3.3_

- [x] 2. Implement drag-to-scroll in WebviewViewport3D
  - [x] 2.1 Add drag state tracking variables
    - Add _drag_start_pos, _last_drag_pos, _is_dragging variables
    - Initialize in _ready()
    - _Requirements: 4.1_

  - [x] 2.2 Modify handle_pointer_event for drag scrolling
    - On "press": Set _is_dragging = true, store start position
    - On "hold": Calculate delta from _last_drag_pos, send scroll command
    - On "release": Clear drag state
    - Remove VScrollBar-based scroll logic
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 2.1, 2.2_

  - [x] 2.3 Implement scroll delta calculation with correct direction
    - Calculate delta_y = current_pos.y - _last_drag_pos.y
    - Invert delta for natural scrolling (drag up = scroll up)
    - Call backend.scroll_by_amount() with inverted delta
    - _Requirements: 1.2, 1.3, 1.4, 4.2, 4.3_

- [ ]* 2.4 Write property test for scroll direction
  - **Property 1: Scroll Direction Consistency**
  - **Validates: Requirements 1.2, 1.3**

- [ ]* 2.5 Write property test for scroll magnitude
  - **Property 2: Scroll Magnitude Proportionality**
  - **Validates: Requirements 1.4**

- [x] 3. Remove VScrollBar scroll control
  - [x] 3.1 Remove or disable VScrollBar value_changed connection for scrolling
    - Keep VScrollBar for visual indication only (optional)
    - Remove _on_scroll_bar_changed scroll logic
    - _Requirements: 2.1_

- [ ] 4. Checkpoint - Verify scrolling works
  - Ensure all tests pass, ask the user if questions arise.

- [ ]* 4.1 Write property test for null safety
  - **Property 5: Scroll Info Null Safety**
  - **Validates: Requirements 3.1, 3.2**

## Notes

- The scroll direction inversion is key: when user drags pointer up (positive Y in viewport), the webpage should scroll up (content moves up in the viewport)
- The VScrollBar can remain visible as a scroll position indicator but should not control scrolling
- Testing on Quest 3 is essential to verify the fix feels natural

