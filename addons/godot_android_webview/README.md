# Godot Android WebView Plugin

A native Android WebView plugin for Godot 4 that renders web content to a texture for use in VR applications.

## Features

- Full Android WebView functionality
- Renders to texture for 3D display
- Touch input support (tap, scroll)
- JavaScript enabled
- Navigation controls (back, forward, reload)
- Progress and title change signals

## Building the Plugin

### Prerequisites

1. Android Studio or Gradle
2. Godot 4.2+ Android export templates
3. JDK 17+

### Build Steps

1. Copy `godot-lib.aar` from your Godot Android export templates to:
   ```
   addons/godot_android_webview/android_plugin/libs/
   ```
   
   The AAR file is located in your Godot export templates folder:
   - Windows: `%APPDATA%\Godot\export_templates\4.x.x\android\godot-lib.template_release.aar`
   - macOS: `~/Library/Application Support/Godot/export_templates/4.x.x/android/godot-lib.template_release.aar`
   - Linux: `~/.local/share/godot/export_templates/4.x.x/android/godot-lib.template_release.aar`

2. Navigate to the plugin directory:
   ```bash
   cd addons/godot_android_webview/android_plugin
   ```

3. Build the plugin:
   ```bash
   ./gradlew assembleRelease
   ```
   
   Or on Windows:
   ```cmd
   gradlew.bat assembleRelease
   ```

4. Copy the built AAR to your project's android plugins folder:
   ```bash
   cp build/outputs/aar/android_plugin-release.aar ../../../android/plugins/GodotAndroidWebView.aar
   ```

5. Create the plugin configuration file at `android/plugins/GodotAndroidWebView.gdap`:
   ```ini
   [config]
   name="GodotAndroidWebView"
   binary_type="local"
   binary="GodotAndroidWebView.aar"
   
   [dependencies]
   local=[]
   remote=["androidx.appcompat:appcompat:1.6.1", "androidx.webkit:webkit:1.8.0"]
   ```

## Usage in Godot

The plugin is automatically detected by the WebviewViewport3D panel. Once built and installed:

1. Enable the plugin in Project Settings > Plugins
2. Export to Android with the plugin enabled
3. The webview panel will automatically use the Android backend on Quest/Android devices

## API

The plugin exposes these methods via the `GodotAndroidWebView` singleton:

```gdscript
# Initialize with dimensions and URL
initialize(width: int, height: int, url: String) -> bool

# Navigation
loadUrl(url: String)
getUrl() -> String
goBack()
goForward()
canGoBack() -> bool
canGoForward() -> bool
reload()
stopLoading()

# Input
touchDown(x: int, y: int)
touchMove(x: int, y: int)
touchUp(x: int, y: int)
scroll(x: int, y: int, deltaY: int)
inputText(text: String)

# Texture
getPixelData() -> PackedByteArray
getWidth() -> int
getHeight() -> int
resize(width: int, height: int)

# Lifecycle
isInitialized() -> bool
destroy()
```

## Signals

- `page_loaded(url: String)` - Page finished loading
- `page_started(url: String)` - Page started loading
- `progress_changed(progress: int)` - Loading progress (0-100)
- `title_changed(title: String)` - Page title changed
- `texture_updated()` - Texture data was updated

## Performance Notes

- Texture updates are rate-limited to ~30 FPS to balance performance
- The WebView runs in a hidden container but still renders
- Memory usage depends on web content complexity
- For Quest 3, recommend 1280x720 resolution for good balance

## Troubleshooting

### Plugin not found
- Ensure the AAR is in `android/plugins/`
- Ensure the GDAP file exists and is correct
- Check that the plugin is enabled in export settings

### Black texture
- Check logcat for WebView errors
- Ensure INTERNET permission is granted
- Try a simple URL like `https://www.google.com`

### Touch not working
- Verify coordinate conversion in the viewport script
- Check that touch events are being forwarded

## License

MIT License
