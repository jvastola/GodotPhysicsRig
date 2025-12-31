# Implementation Plan: Cross-Platform VR WebView

## Overview

This plan implements a cross-platform webview solution for Godot 4 VR with support for both desktop (CEF) and Android/Quest (TLabWebView). The implementation uses a platform abstraction layer to provide a unified API regardless of the underlying backend.

## Tasks

- [x] 1. Create core webview panel structure
  - [x] 1.1 Create WebviewViewport3D.tscn scene file
    - Node3D root with SubViewport, TextureRect, MeshInstance3D, and collision
    - Configure quad mesh with 16:9 aspect ratio (2.56 x 1.44)
    - Set up viewport texture material
    - _Requirements: 1.3, 1.4_

  - [x] 1.2 Create webview_viewport_3d.gd script with platform detection
    - Implement exports for URL, size, and pointer group
    - Add platform detection (OS.get_name())
    - Initialize appropriate backend based on platform
    - _Requirements: 1.1, 3.4_

- [x] 2. Create platform abstraction layer
  - [x] 2.1 Create WebViewBackend base class
    - Define abstract interface for all backends
    - Methods: initialize(), load_url(), get_url(), send_mouse_event(), etc.
    - Signals: page_loaded, page_loading, error_occurred
    - _Requirements: 2.1, 2.2, 2.3_

  - [x] 2.2 Create backend factory
    - Auto-detect platform and instantiate correct backend
    - Fallback to placeholder if no backend available
    - _Requirements: 1.1_

- [x] 3. Implement Android/Quest backend (Native Android WebView)
  - [x] 3.1 Create Android plugin Java source
    - GodotAndroidWebView.java with WebView rendering to texture
    - Build configuration (build.gradle, settings.gradle)
    - Plugin configuration (GDAP file)
    - _Requirements: 1.1_

  - [x] 3.2 Create AndroidWebViewBackend class
    - Implement WebViewBackend interface
    - Bridge to native Android plugin
    - Handle texture updates from pixel data
    - _Requirements: 1.1, 1.2_

  - [x] 3.3 Implement input forwarding for Android
    - Convert VR pointer events to touch events
    - Handle scroll as touch drag
    - _Requirements: 3.1, 3.2, 3.3_

  - [x] 3.4 Build Android plugin AAR
    - Copy godot-lib.aar to libs folder
    - Run gradle build
    - Copy output to android/plugins/
    - _Requirements: 1.1_

- [x] 4. Implement Desktop backend (CEF)
  - [ ] 4.1 Integrate CEF/gdCEF addon
    - Download and place in addons/gdcef/
    - Configure CEF artifacts path
    - _Requirements: 1.1_

  - [x] 4.2 Create DesktopCEFBackend class
    - Implement WebViewBackend interface
    - Initialize CEF with appropriate settings
    - Handle browser creation and texture output
    - _Requirements: 1.1, 1.2_

  - [x] 4.3 Implement input forwarding for CEF
    - Convert VR pointer events to mouse events
    - Handle keyboard input
    - _Requirements: 3.1, 3.2, 3.3_

- [x] 5. Implement VR pointer interaction
  - [x] 5.1 Implement handle_pointer_event() method
    - Translate 3D hit position to UV coordinates
    - Convert UV to browser pixel coordinates
    - Forward to active backend
    - _Requirements: 3.1, 3.2_

  - [x] 5.2 Implement scroll event handling
    - Translate scroll events to backend scroll calls
    - _Requirements: 3.3_

- [x] 6. Implement pointer grab interface
  - [x] 6.1 Add pointer grab methods for repositioning
    - pointer_grab_set_distance(), pointer_grab_set_scale()
    - pointer_grab_set_rotation(), pointer_grab_get_distance()
    - _Requirements: 4.2, 4.3_

  - [x] 6.2 Implement set_interactive() method
    - Toggle collision layer for pointer detection
    - _Requirements: 4.1_

- [ ] 7. Checkpoint - Test platform detection
  - Verify correct backend loads on each platform
  - Test placeholder shows when no backend available

- [x] 8. Integrate with UI system
  - [x] 8.1 Add to UIPanelManager scene paths
    - _Requirements: 5.3_

  - [x] 8.2 Add to quick access menu in ui_panel.gd
    - _Requirements: 5.3_

  - [ ] 8.3 Add WebviewViewport3D instance to MainScene (optional)
    - Position at accessible default location
    - _Requirements: 5.1, 5.2_

- [ ] 9. Create browser UI controls (Phase 3)
  - [ ] 9.1 Create URL bar component
    - Text input for URL entry
    - Go button
    - _Requirements: 2.1_

  - [ ] 9.2 Create navigation buttons
    - Back, Forward, Reload, Stop buttons
    - Connect to backend methods
    - _Requirements: 2.1_

- [ ] 10. Final checkpoint
  - Test on desktop (Windows/Mac/Linux)
  - Test on Quest 3
  - Verify all VR interactions work

## Notes

- TLabWebView is the recommended Android backend (MIT license, active development)
- CEF provides full Chromium on desktop but requires ~100MB of binaries
- Platform detection happens at runtime via OS.get_name()
- Both backends render to a texture that's applied to the 3D quad
- The abstraction layer allows adding new backends (e.g., GeckoView) later

## File Structure

```
src/ui/webview/
├── webview_viewport_3d.gd       # Main panel script (platform-agnostic)
├── WebviewViewport3D.tscn       # Panel scene
├── backends/
│   ├── webview_backend.gd       # Abstract base class
│   ├── android_webview_backend.gd
│   ├── desktop_cef_backend.gd
│   └── placeholder_backend.gd   # Fallback when no real backend
└── ui/
    ├── browser_controls.tscn    # Back/forward/reload UI
    └── url_bar.tscn             # URL input
```

## Dependencies

- **Android**: TLabWebView plugin (addons/tlab_webview/)
- **Desktop**: gdCEF or similar CEF wrapper (addons/gdcef/)
- **Both**: Existing UI infrastructure (UIPanelManager, pointer system)
