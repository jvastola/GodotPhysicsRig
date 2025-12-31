# WebView Implementation - Next Steps

## Current Status

The cross-platform WebView panel infrastructure is complete:
- ✅ Platform abstraction layer (WebViewBackend base class)
- ✅ Android WebView backend (native Java plugin)
- ✅ Desktop CEF backend (gdCEF wrapper)
- ✅ Placeholder backend (fallback with instructions)
- ✅ VR pointer interaction
- ✅ Panel grab/scale interface
- ✅ UI panel manager integration
- ✅ Android plugin built and deployed to `android/plugins/`

## Immediate Next Steps

### 1. Test on Quest 3

The Android plugin is built and ready. To test:
1. Open the project in Godot
2. Export to Quest 3 (ensure "GodotAndroidWebView" plugin is enabled in export settings)
3. Open the "🌐 Web Browser" panel from quick access menu
4. The webview should load and display web content

### 2. Install Desktop CEF Backend (Optional)

For desktop browser support, you need gdCEF or similar:

1. Download gdCEF from: https://github.com/nicemicro/gdcef (or search for Godot 4 CEF)
2. Extract to `addons/gdcef/`
3. Download CEF artifacts (~100MB) to `cef_artifacts/`
4. Enable plugin in Project Settings

**Note:** Desktop support is optional - the panel works on Quest without it.

### 2. Test the WebView Panel

1. Open the project in Godot
2. Run on desktop (will show placeholder if CEF not installed)
3. Export to Quest 3 (enable "GodotAndroidWebView" in export plugins)
4. Open the "🌐 Web Browser" panel from quick access menu

## Future Enhancements

### Phase 2: Browser UI Controls

- [ ] URL bar with text input
- [ ] Back/Forward/Reload buttons
- [ ] Loading progress indicator
- [ ] Page title display

### Phase 3: Advanced Features

- [ ] Virtual keyboard integration
- [ ] Bookmarks/history
- [ ] Multiple tabs (optional)
- [ ] Download handling

### Phase 4: Performance Optimization

- [ ] Hardware buffer mode for Android (API 26+)
- [ ] Texture compression
- [ ] Adaptive frame rate
- [ ] Memory management

## File Structure

```
src/ui/webview/
├── webview_viewport_3d.gd       # Main panel (platform-agnostic)
├── WebviewViewport3D.tscn       # Panel scene
├── NEXT_STEPS.md                # This file
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
    ├── build_plugin.bat         # Windows build script
    ├── build_plugin.sh          # macOS/Linux build script
    ├── build.gradle
    ├── settings.gradle
    ├── gradle.properties
    ├── libs/                    # Place godot-lib.release.aar here
    └── src/main/java/com/godot/webview/
        └── GodotAndroidWebView.java

android/plugins/
├── GodotAndroidWebView.gdap     # Plugin descriptor
└── GodotAndroidWebView.aar      # Built plugin (after build)
```

## Troubleshooting

### Android: Plugin not loading
- Check logcat for errors: `adb logcat | grep -i godot`
- Verify AAR is in `android/plugins/`
- Verify GDAP file exists and is correct
- Enable plugin in Android export settings

### Android: Black/white texture
- Check INTERNET permission in export settings
- Try simple URL first: `https://www.google.com`
- Check logcat for WebView errors

### Desktop: CEF not initializing
- Verify CEF artifacts are in correct location
- Check console for error messages
- Ensure plugin is enabled

### VR: Touch not working
- Enable debug_coordinates on the panel
- Verify UV coordinates are in 0-1 range
- Check collision layer (should be 32)

## API Reference

```gdscript
# Load a URL
webview.load_url("https://example.com")

# Navigation
webview.go_back()
webview.go_forward()
webview.reload()
webview.stop_loading()

# State
var url = webview.get_current_url()
var can_back = webview.can_go_back()
var can_forward = webview.can_go_forward()
var backend = webview.get_backend_name()
var available = webview.is_backend_available()

# Signals
webview.page_loaded.connect(_on_page_loaded)
webview.page_loading.connect(_on_page_loading)
```

## Performance Notes

- Android texture updates are rate-limited to ~30 FPS
- Recommended resolution: 1280x720 for Quest 3
- Memory usage depends on web content complexity
- Consider lowering resolution for complex pages

## Contributing

To add a new backend:
1. Create a new class extending `WebViewBackend`
2. Implement all abstract methods
3. Add platform detection in `webview_viewport_3d.gd`
4. Update this documentation
