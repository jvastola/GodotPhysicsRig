# Implementation Plan: Cross-Platform VR WebView

## Overview

This plan implements a cross-platform webview solution for Godot 4 VR with support for both desktop (CEF) and Android/Quest (native WebView). The implementation uses a platform abstraction layer to provide a unified API regardless of the underlying backend.

## Completed Tasks

- [x] 1. Create core webview panel structure
  - [x] 1.1 Create WebviewViewport3D.tscn scene file
    - Node3D root with SubViewport, TextureRect, MeshInstance3D, and collision
    - Configure quad mesh with 16:9 aspect ratio (2.56 x 1.44)
    - Set up viewport texture material
    - _Requirements: 1.3, 1.4, 1.5_

  - [x] 1.2 Create webview_viewport_3d.gd script with platform detection
    - Implement exports for URL, size, and pointer group
    - Add platform detection (OS.get_name())
    - Initialize appropriate backend based on platform
    - _Requirements: 1.1, 3.4, 6.1_

- [x] 2. Create platform abstraction layer
  - [x] 2.1 Create WebViewBackend base class
    - Define abstract interface for all backends
    - Methods: initialize(), load_url(), get_url(), send_mouse_event(), etc.
    - Signals: page_loaded, page_loading, error_occurred
    - _Requirements: 2.1, 2.2, 2.3, 6.5_

  - [x] 2.2 Create backend factory logic in webview_viewport_3d.gd
    - Auto-detect platform and instantiate correct backend
    - Fallback to placeholder if no backend available
    - _Requirements: 6.1, 6.2, 6.3, 6.4_

- [x] 3. Implement Android/Quest backend (Native Android WebView)
  - [x] 3.1 Create Android plugin Java source
    - GodotAndroidWebView.java with WebView rendering to ByteBuffer
    - Build configuration (build.gradle, settings.gradle)
    - Plugin configuration (GDAP file)
    - _Requirements: 6.2_

  - [x] 3.2 Create AndroidWebViewBackend class
    - Implement WebViewBackend interface
    - Bridge to native Android plugin via Engine.get_singleton()
    - Handle texture updates from pixel data
    - _Requirements: 6.2, 1.1, 1.2_

  - [x] 3.3 Implement input forwarding for Android
    - Convert VR pointer events to touch events (touchDown, touchMove, touchUp)
    - Handle scroll as scrollBy
    - _Requirements: 3.1, 3.2, 3.3_

  - [x] 3.4 Build Android plugin AAR
    - Copy godot-lib.aar to libs folder
    - Run gradle build
    - Copy output to android/plugins/
    - _Requirements: 6.2_

- [x] 4. Implement Desktop backend (CEF)
  - [x] 4.1 Create DesktopCEFBackend class
    - Implement WebViewBackend interface
    - Initialize CEF with appropriate settings
    - Handle browser creation and texture output
    - _Requirements: 6.3, 1.1, 1.2_

  - [x] 4.2 Implement input forwarding for CEF
    - Convert VR pointer events to mouse events
    - Handle keyboard input
    - _Requirements: 3.1, 3.2, 3.3_

- [x] 5. Implement VR pointer interaction
  - [x] 5.1 Implement handle_pointer_event() method
    - Translate 3D hit position to UV coordinates
    - Convert UV to browser pixel coordinates
    - Forward to active backend
    - _Requirements: 3.1, 3.2, 3.5_

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
    - _Requirements: 4.4_

- [x] 7. Integrate with UI system
  - [x] 7.1 Add to UIPanelManager scene paths
    - Added "WebviewViewport3D" to UI_SCENE_PATHS
    - _Requirements: 5.1_

  - [x] 7.2 Add to quick access menu in ui_panel.gd
    - Added "🌐 Web Browser" button
    - _Requirements: 5.2_

## Remaining Tasks

- [ ] 8. Verify and test gdCEF integration
  - [ ] 8.1 Verify gdCEF addon is properly installed
    - Check addons/gdcef/ structure
    - Verify CEF artifacts in cef_artifacts/
    - Enable plugin in Project Settings if needed
    - _Requirements: 6.3_

  - [ ] 8.2 Test desktop webview functionality
    - Run on desktop and verify CEF backend loads
    - Test URL loading and navigation
    - Test pointer interaction
    - _Requirements: 1.1, 2.1, 3.1_

- [ ] 9. Test Android/Quest functionality
  - [x] 9.1 Export to Quest 3 with plugin enabled
    - Ensure "GodotAndroidWebView" plugin is enabled in export settings
    - Ensure INTERNET permission is enabled
    - _Requirements: 6.2_

  - [ ] 9.2 Test webview on Quest 3
    - Open "🌐 Web Browser" from quick access menu
    - Verify page loads and displays
    - Test touch/click interaction
    - Test scrolling
    - _Requirements: 1.1, 3.1, 3.2, 3.3_

  - [ ] 9.3 Verify performance targets
    - Confirm VR maintains 72+ FPS
    - Check texture update rate (~30 FPS)
    - Monitor memory usage (<200MB target)
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

- [ ] 10. Create browser UI controls (Phase 2)
  - [x] 10.1 Create URL bar component
    - Text input for URL entry
    - Go button to navigate
    - Display current URL
    - Integrated with KeyboardManager for virtual keyboard support
    - _Requirements: 8.1_

  - [x] 10.2 Create navigation buttons
    - Back, Forward, Reload buttons
    - Connect to backend methods (go_back, go_forward, reload)
    - Visual feedback for can_go_back/can_go_forward state
    - _Requirements: 8.2_

  - [x] 10.3 Add loading progress indicator
    - Connect to load_progress signal
    - Visual progress bar
    - _Requirements: 8.3_

  - [ ] 10.4 Display page title
    - Connect to page_title_changed signal
    - Show in URL bar or header area
    - _Requirements: 8.4_

- [ ] 11. Optional: Add WebviewViewport3D instance to MainScene
  - Position at accessible default location
  - _Requirements: 5.3_

- [ ] 12. Final checkpoint
  - [ ] 12.1 Test on desktop (Windows/Mac/Linux)
  - [ ] 12.2 Test on Quest 3
  - [ ] 12.3 Verify all VR interactions work
  - [ ] 12.4 Document any known issues

## Notes

- The Android plugin uses ByteBuffer capture mode for stability and compatibility
- CEF provides full Chromium on desktop but requires ~100MB of binaries
- Platform detection happens at runtime via OS.get_name()
- Both backends render to a texture that's applied to the 3D quad
- The abstraction layer allows adding new backends (e.g., GeckoView) later

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

addons/godot_android_webview/    # Android plugin addon
addons/gdcef/                    # Desktop CEF addon (external)
cef_artifacts/                   # CEF binaries (external)
android/plugins/                 # Built Android plugin AAR
```

## Dependencies

- **Android**: GodotAndroidWebView plugin (included, built)
- **Desktop**: gdCEF addon (present in addons/gdcef/)
- **Both**: Existing UI infrastructure (UIPanelManager, pointer system)
