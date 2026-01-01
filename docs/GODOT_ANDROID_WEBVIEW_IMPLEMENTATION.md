# GodotAndroidWebView Plugin Implementation

**Author:** VR Project  
**Version:** 1.0.0  
**Godot Version:** 4.2+  
**Platform:** Android (API 24+, Android 7.0+)  
**Date:** December 31, 2025

---

## Overview

The GodotAndroidWebView plugin is a native Android plugin for Godot 4 that integrates the Android WebView component to render web content directly to a texture. This enables in-game web browsing capabilities for VR and non-VR applications, with full touch input support and real-time rendering.

### Key Capabilities

- **Hardware-Accelerated WebView Rendering** - Uses native Android WebView for optimal performance
- **Real-Time Texture Updates** - Captures WebView content to byte buffer at ~30 FPS
- **Touch Input Handling** - Full touch event support (tap, move, up)
- **JavaScript Execution** - Can execute arbitrary JavaScript in the web context
- **Web Navigation** - Back, forward, reload, stop loading controls
- **Loading State Tracking** - Progress signals and page lifecycle events
- **Scroll Control** - JavaScript-based scrolling for reliable texture capture
- **Dynamic Resizing** - Supports runtime viewport size changes

---

## Architecture

### Plugin Structure

```
addons/godot_android_webview/
├── plugin.cfg                    # Godot plugin metadata
├── godot_android_webview.gd      # EditorPlugin stub
├── README.md                     # User-facing documentation
└── android_plugin/               # Android library source
    ├── build.gradle              # Gradle configuration
    ├── src/main/
    │   ├── AndroidManifest.xml   # Android manifest with plugin registration
    │   └── java/com/godot/webview/
    │       └── GodotAndroidWebView.java  # Main plugin implementation
    ├── libs/
    │   └── godot-lib.release.aar # Godot engine library (runtime dependency)
    └── gradle/                   # Gradle wrapper scripts
```

### Deployment Structure

After successful build:

```
android/plugins/
├── GodotAndroidWebView.aar       # Compiled plugin binary
└── GodotAndroidWebView.gdap      # Plugin configuration file
```

---

## Implementation Details

### 1. Plugin Registration

**File:** `android_plugin/src/main/AndroidManifest.xml`

```xml
<!-- Godot v2 Android Plugin registration -->
<meta-data
    android:name="org.godotengine.plugin.v2.GodotAndroidWebView"
    android:value="com.godot.webview.GodotAndroidWebView" />
```

This meta-data entry allows Godot's Android runtime to discover and load the plugin automatically. The format follows Godot's plugin v2 specification.

**File:** `android/plugins/GodotAndroidWebView.gdap`

```ini
[config]
name="GodotAndroidWebView"
binary_type="local"
binary="GodotAndroidWebView.aar"

[dependencies]
local=[]
remote=["androidx.appcompat:appcompat:1.6.1", "androidx.webkit:webkit:1.8.0"]
```

The GDAP file declares:
- Plugin name and binary location
- Remote Maven dependencies (AndroidX libraries)
- Local inter-plugin dependencies (none in this case)

### 2. Core Plugin Class

**File:** `android_plugin/src/main/java/com/godot/webview/GodotAndroidWebView.java`

#### Class Inheritance
```java
public class GodotAndroidWebView extends GodotPlugin
```

The plugin extends `GodotPlugin` from the Godot engine, providing the bridge between Godot's scripting layer and Android's native APIs.

#### Key Components

##### Initialization
```java
private WebView webView;
private Handler mainHandler;
private int width = 1280;
private int height = 720;
private Bitmap bitmap;
private ByteBuffer pixelBuffer;
private Canvas canvas;
private AtomicBoolean isInitialized = new AtomicBoolean(false);
private AtomicBoolean needsUpdate = new AtomicBoolean(false);
```

- **webView**: The Android WebView instance
- **mainHandler**: Handler for posting tasks to the Android main thread (required for UI operations)
- **Rendering Pipeline**: Bitmap → Canvas → ByteBuffer → Byte Array → Godot Texture
- **Thread Safety**: AtomicBoolean for lock-free state management

##### Signals

```java
signals.add(new SignalInfo("page_loaded", String.class));
signals.add(new SignalInfo("page_started", String.class));
signals.add(new SignalInfo("progress_changed", Integer.class));
signals.add(new SignalInfo("title_changed", String.class));
signals.add(new SignalInfo("texture_updated"));
signals.add(new SignalInfo("scroll_info_received", String.class));
```

These signals allow Godot scripts to react to web events:
- **page_loaded** - Emitted when page finishes loading
- **page_started** - Emitted when page begins loading
- **progress_changed** - Loading progress (0-100)
- **title_changed** - Page title updates
- **texture_updated** - New texture data available
- **scroll_info_received** - Response to scroll info query

### 3. WebView Configuration

#### Settings Applied

```java
WebSettings settings = webView.getSettings();
settings.setJavaScriptEnabled(true);           // Enable JS execution
settings.setDomStorageEnabled(true);           // LocalStorage/SessionStorage
settings.setDatabaseEnabled(true);             // IndexedDB
settings.setMediaPlaybackRequiresUserGesture(false);  // Autoplay media
settings.setUseWideViewPort(true);             // Responsive layout
settings.setLoadWithOverviewMode(true);        // Initial zoom
settings.setSupportZoom(true);                 // User zoom allowed
settings.setBuiltInZoomControls(true);         // Zoom buttons
settings.setDisplayZoomControls(false);        // Hide zoom UI
settings.setAllowFileAccess(true);             // file:// URLs
settings.setAllowContentAccess(true);          // content:// URIs
settings.setCacheMode(WebSettings.LOAD_DEFAULT);  // Cache strategy
```

#### Mixed Content Handling (Android 5.0+)

```java
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
    settings.setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);
}
```

Allows HTTPS pages to load HTTP resources (for compatibility).

#### WebViewClient

Handles page lifecycle events:

```java
webView.setWebViewClient(new WebViewClient() {
    @Override
    public void onPageStarted(WebView view, String url, Bitmap favicon) {
        currentUrl = url;
        emitSignal("page_started", url);
    }
    
    @Override
    public void onPageFinished(WebView view, String url) {
        currentUrl = url;
        canGoBack = view.canGoBack();
        canGoForward = view.canGoForward();
        emitSignal("page_loaded", url);
        requestRender();  // Update texture
    }
});
```

#### WebChromeClient

Handles progress and title updates:

```java
webView.setWebChromeClient(new WebChromeClient() {
    @Override
    public void onProgressChanged(WebView view, int newProgress) {
        loadProgress = newProgress;
        emitSignal("progress_changed", newProgress);
        if (newProgress % 10 == 0) {
            requestRender();  // Update on major progress milestones
        }
    }
    
    @Override
    public void onReceivedTitle(WebView view, String title) {
        emitSignal("title_changed", title);
    }
});
```

### 4. Texture Rendering Pipeline

#### Rendering to Bitmap

```java
private void renderToBitmap() {
    mainHandler.post(() -> {
        synchronized (lock) {
            try {
                canvas.drawColor(android.graphics.Color.WHITE);  // Clear
                webView.draw(canvas);                             // Draw WebView
            } catch (Exception e) {
                // Ignore rendering errors
            }
        }
    });
}
```

Key points:
- **Main Thread Requirement**: All WebView operations must occur on Android's main thread
- **Canvas Drawing**: Calls `WebView.draw()` to render content to the canvas
- **Clear Background**: Fills canvas with white before drawing
- **Error Handling**: Catches and ignores rendering exceptions

#### Pixel Data Extraction

```java
public byte[] getPixelData() {
    // Rate limiting
    if (!forceUpdate && (now - lastUpdateTime < MIN_UPDATE_INTERVAL_MS) && !needsUpdate.get()) {
        return new byte[0];  // No update needed
    }
    
    // Render on main thread
    mainHandler.post(() -> {
        canvas.drawColor(android.graphics.Color.WHITE);
        webView.draw(canvas);
        done.set(true);
    });
    
    // Wait for render completion (100ms timeout)
    
    // Convert bitmap to byte array
    pixelBuffer.rewind();
    bitmap.copyPixelsToBuffer(pixelBuffer);
    byte[] pixels = new byte[pixelBuffer.capacity()];
    pixelBuffer.get(pixels);
    
    return pixels;
}
```

#### Rate Limiting

```java
private static final long MIN_UPDATE_INTERVAL_MS = 33;      // ~30 FPS
private static final long FORCE_UPDATE_INTERVAL_MS = 500;   // 500ms force update
```

Limits texture updates to:
- **30 FPS max** under normal conditions (~33ms between frames)
- **Force update every 500ms** to ensure texture doesn't stall

#### Color Format

The bitmap uses ARGB_8888 format, but `copyPixelsToBuffer()` on Android produces RGBA byte order:
- Android device memory (little-endian): `[R, G, B, A]` bytes
- Godot expects RGBA format
- **No color channel swapping required** - Android native order matches Godot's expectation

### 5. Touch Input Handling

#### Input Event Creation

```java
@UsedByGodot
public void touchDown(int x, int y) {
    mainHandler.post(() -> {
        long downTime = android.os.SystemClock.uptimeMillis();
        android.view.MotionEvent event = android.view.MotionEvent.obtain(
            downTime, downTime,
            android.view.MotionEvent.ACTION_DOWN,
            x, y, 0  // 0 = no pressure data
        );
        webView.dispatchTouchEvent(event);
        event.recycle();
    });
}
```

Similar methods for `touchMove()` and `touchUp()` using:
- `MotionEvent.ACTION_DOWN` - Finger pressed
- `MotionEvent.ACTION_MOVE` - Finger dragged
- `MotionEvent.ACTION_UP` - Finger released

#### Scroll Handling

**Summary:** Native WebView scrolling (via MotionEvents) is intentionally disabled in this plugin because it often caused rendering desynchronization and visible artifacts when capturing the WebView to a bitmap. Instead, the plugin exposes two JavaScript-based scrolling methods that are reliable with the texture capture pipeline:

- `scrollToPosition(int scrollY)` — jump to an absolute vertical position (in page/CSS pixels)
- `scrollByAmount(int deltaY)` — scroll by a relative amount (in page/CSS pixels)

```java
@UsedByGodot
public void scrollToPosition(int scrollY) {
    mainHandler.post(() -> {
        webView.evaluateJavascript(
            "window.scrollTo(0, " + scrollY + ");",
            null
        );
        requestRender();
    });
}

@UsedByGodot
public void scrollByAmount(int deltaY) {
    mainHandler.post(() -> {
        webView.evaluateJavascript(
            "window.scrollBy(0, " + deltaY + ");",
            null
        );
        requestRender();
    });
}
```

Important notes and guidance:

- Units: Both API parameters are interpreted as CSS (document) pixels. This matches the values returned by `getScrollInfo()` (see below). In many cases the WebView texture pixel height equals CSS pixels (no DPR scaling), but if your content is zoomed or the page/device pixel ratio differs, you may need to convert between viewport pixels and CSS pixels before calling these methods.

- How to compute positions reliably:
  1. Call `_plugin.getScrollInfo()` from GDScript; the plugin emits `scroll_info_received` with JSON: `{ "scrollY": number, "scrollHeight": number, "clientHeight": number }`.
  2. Use `scrollY` and `clientHeight` to clamp values and compute targets (all values in CSS pixels).

- Mouse wheel / touchpad behavior:
  - When handling wheel events in GDScript, translate wheel delta to a sensible pixel amount (e.g., 40 px per notch for coarse scrolling):

```gdscript
# Example in GDScript (inside webview backend or UI node)
func _on_wheel(delta: float):
    var pixels_per_step := 40
    var amount := int(delta * pixels_per_step)
    _backend.scroll_by_amount(amount)
```

  - For small, smooth scrolling, call `scrollByAmount()` repeatedly with scaled deltas.

- Drag / momentum gestures:
  - The plugin does not implement native fling/inertia. You can emulate momentum on the Godot side by scheduling repeated `scrollByAmount()` calls with decreasing deltas.

- Programmatic positioning:
  - For precise control (e.g., scroll to an element), use `executeJavaScript()` with `element.scrollIntoView()` or compute the element offset in JS and call `scrollToPosition()`.

- Debugging and validation:
  - Call `getScrollInfo()` after a scroll to verify the resulting `scrollY` and compare to the expected value.
  - If content appears to shift unexpectedly, check whether the page has CSS transforms, zoom, or a different `devicePixelRatio`.

**Rationale:** Direct MotionEvent-based native scrolling resulted in inconsistency between the rendered WebView content and the captured bitmap. JavaScript-based scrolling operates on the page/document model and keeps the visual state consistent with `window.scrollX`/`window.scrollY`, making texture captures deterministic and predictable.

**Known limitation:** If your content relies on complex touch gestures (pinch-to-zoom or native kinetic scrolling), behavior may differ from an on-screen WebView; consider offering UI affordances in the page that call `scrollBy`/`scrollTo` via postMessage or exposing a small JS bridge for advanced interactions.

### Input coordinate mapping & drag-handling fix 🧭

**Problem:** Input coordinates coming from world-space -> UV -> UI pixels were not consistently mapped to the WebView coordinate space, resulting in clicks/drag behavior appearing inverted or offset (top vs bottom mismatch).

**Fix implemented:**
- Invert the Y coordinate when converting UV -> viewport pixels so that the web content's top-left origin matches Android's coordinate system: `viewport_y = (1.0 - uv.y) * ui_size.y`.
- Clamp and offset coordinates by the UI URL bar height when mapping into backend pixels:

```gdscript
# Map a UV hit to viewport pixels (now with Y inverted)
var viewport_pos := Vector2(uv.x * ui_size.x, (1.0 - uv.y) * ui_size.y)

# Convert viewport -> backend (pixels), clamped and offset from the URL bar
func _viewport_to_backend_pos(viewport_pos: Vector2) -> Vector2:
    var x := clamp(viewport_pos.x, 0.0, ui_size.x)
    var y := clamp(viewport_pos.y - URL_BAR_HEIGHT, 0.0, ui_size.y - URL_BAR_HEIGHT)
    return Vector2(x, y)
```

**Drag scrolling change:** To avoid visual lag/jitter from native MotionEvent-based scrolling, drag motion is now translated into JS scrolling (calls `scrollByAmount`) instead of calling `touchMove` on the WebView. Example implementation in `_send_mouse_motion`:

```gdscript
# When the pointer is pressed (dragging), convert y delta -> JS scroll
if _is_pressed and prev_mouse_pos.x >= 0:
    var delta_y := pos.y - prev_mouse_pos.y
    var scroll_amount := int(delta_y * 2.0) # sensitivity
    if scroll_amount != 0:
        _backend.scroll_by_amount(-scroll_amount)
else:
    _backend.send_mouse_move(int(backend_pos.x), int(backend_pos.y))
```

This preserves hover/mouse-move behavior for pointer move events, while using JS scrolling for drag gestures (smoother, deterministic rendering).

**Testing checklist:**
- [ ] Point at an element near the top (e.g., search bar) and trigger a click — the element should now receive focus.
- [ ] Drag up/down and confirm the page scrolls smoothly without the heavy/jittery behavior from native MotionEvent scrolling.

---

### 6. JavaScript Execution

#### Direct Script Execution

```java
@UsedByGodot
public void executeJavaScript(String script) {
    mainHandler.post(() -> {
        webView.evaluateJavascript(script, null);
    });
}
```

Executes arbitrary JavaScript with no callback.

#### Scroll Info Query

```java
@UsedByGodot
public void getScrollInfo() {
    mainHandler.post(() -> {
        webView.evaluateJavascript(
            "(function() { " +
            "  return JSON.stringify({" +
            "    scrollY: window.scrollY || document.documentElement.scrollTop || 0," +
            "    scrollHeight: document.documentElement.scrollHeight || 0," +
            "    clientHeight: window.innerHeight || 0" +
            "  });" +
            "})()",
            value -> {
                // Parse and emit signal with JSON data
                emitSignal("scroll_info_received", result);
            }
        );
    });
}
```

Executes an IIFE (Immediately Invoked Function Expression) to query scroll state with callback result handling.

#### Text Input

```java
@UsedByGodot
public void inputText(String text) {
    String escapedText = text.replace("\\", "\\\\")
                             .replace("'", "\\'")
                             .replace("\n", "\\n");
    webView.evaluateJavascript(
        "if(document.activeElement){document.activeElement.value+='" + escapedText + "';}",
        null
    );
}
```

Injects text into the focused form element.

### 7. Lifecycle Management

#### Initialization

```java
@UsedByGodot
public boolean initialize(int viewWidth, int viewHeight, String initialUrl) {
    if (isInitialized.get()) {
        return true;  // Already initialized
    }
    
    // Store dimensions
    this.width = viewWidth;
    this.height = viewHeight;
    
    // Create rendering buffers
    bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
    pixelBuffer = ByteBuffer.allocateDirect(width * height * 4);
    canvas = new Canvas(bitmap);
    
    // Create WebView on main thread
    mainHandler.post(() -> {
        // ... WebView setup ...
        isInitialized.set(true);
        
        // Force initial render after 500ms
        mainHandler.postDelayed(() -> {
            needsUpdate.set(true);
        }, 500);
    });
    
    return true;
}
```

Key steps:
1. Allocate rendering buffers (bitmap, pixel buffer, canvas)
2. Create WebView on main thread
3. Configure WebView settings and clients
4. Load initial URL
5. Schedule first render update

#### Resizing

```java
@UsedByGodot
public void resize(int newWidth, int newHeight) {
    this.width = newWidth;
    this.height = newHeight;
    
    // Recreate buffers
    bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
    pixelBuffer = ByteBuffer.allocateDirect(width * height * 4);
    canvas = new Canvas(bitmap);
    
    // Update WebView layout
    mainHandler.post(() -> {
        webView.setLayoutParams(new FrameLayout.LayoutParams(width, height));
        webView.requestLayout();
    });
}
```

#### Cleanup

```java
@UsedByGodot
public void destroy() {
    mainHandler.post(() -> {
        webView.stopLoading();
        webView.clearHistory();
        webView.clearCache(true);
        webView.loadUrl("about:blank");
        webView.onPause();
        
        // Remove from view hierarchy
        ViewGroup parent = (ViewGroup) webView.getParent();
        if (parent != null) {
            parent.removeView(webView);
            ViewGroup grandParent = (ViewGroup) parent.getParent();
            if (grandParent != null) {
                grandParent.removeView(parent);
            }
        }
        
        webView.destroy();
        webView = null;
        
        // Clear buffers
        bitmap = null;
        pixelBuffer = null;
        canvas = null;
        isInitialized.set(false);
    });
}
```

---

## Build Process

### Prerequisites

1. **JDK 17+** - Required by Android Gradle Plugin 8.2.0
2. **Android SDK 33** - Target compilation target (minimum SDK 24)
3. **Gradle 8.2.0** - Via gradle wrapper
4. **Godot Export Templates** - For godot-lib.release.aar
5. **AndroidX Dependencies** - Fetched from Maven Central

### Build Configuration

**File:** `android_plugin/build.gradle`

```groovy
android {
    namespace 'com.godot.webview'
    compileSdk 33

    defaultConfig {
        minSdk 24          // Android 7.0+
        targetSdk 33       // Android 13
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}

dependencies {
    compileOnly files('libs/godot-lib.release.aar')
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'androidx.webkit:webkit:1.8.0'
}
```

### Build Steps

1. **Prepare Godot Library**
   ```bash
   # Copy from Godot export templates
   cp ~/Library/Application\ Support/Godot/export_templates/4.x.x/android/godot-lib.template_release.aar \
      addons/godot_android_webview/android_plugin/libs/godot-lib.release.aar
   ```

2. **Gradle Setup**
   ```bash
   cd addons/godot_android_webview/android_plugin
   # gradle wrapper files already present (copied from livekit plugin)
   ```

3. **Build Release AAR**
   ```bash
   ./gradlew clean assembleRelease
   ```
   
   Output: `build/outputs/aar/GodotAndroidWebView-release.aar`

4. **Deploy to Godot**
   ```bash
   cp build/outputs/aar/GodotAndroidWebView-release.aar ../../../android/plugins/GodotAndroidWebView.aar
   ```

5. **Create Plugin Configuration**
   ```ini
   # android/plugins/GodotAndroidWebView.gdap
   [config]
   name="GodotAndroidWebView"
   binary_type="local"
   binary="GodotAndroidWebView.aar"
   
   [dependencies]
   local=[]
   remote=["androidx.appcompat:appcompat:1.6.1", "androidx.webkit:webkit:1.8.0"]
   ```

### Build Output

- **AAR File** (10.0 KB) - Compiled plugin binary containing:
  - Compiled Java classes
  - AndroidManifest.xml with plugin metadata
  - Resources (if any)
- **GDAP File** - Plugin descriptor for Godot

---

## Godot Integration

### Accessing the Plugin in GDScript

```gdscript
# Get plugin reference
var webview = GodotAndroidWebView

# Check if available
if webview.is_initialized():
    webview.loadUrl("https://example.com")

# Connect to signals
webview.page_loaded.connect(_on_page_loaded)
webview.texture_updated.connect(_on_texture_updated)
```

### Typical Workflow

```gdscript
# 1. Initialize
webview.initialize(1280, 720, "https://example.com")

# 2. Connect signals
webview.page_loaded.connect(func(url):
    print("Page loaded: ", url)
)
webview.texture_updated.connect(func():
    # Get pixel data and update texture
    var pixels = webview.getPixelData()
    # Create/update Godot ImageTexture with pixels
)

# 3. Handle input
func _on_touch_input(position: Vector2) -> void:
    webview.touchDown(int(position.x), int(position.y))

# 4. Cleanup
func _exit_tree() -> void:
    webview.destroy()
```

---

## Performance Characteristics

### Rendering Performance

| Metric | Value | Notes |
|--------|-------|-------|
| Max Framerate | 30 FPS | Rate-limited to balance load |
| Force Update | 500 ms | Ensures texture freshness |
| Texture Size | 1280x720 | Typical resolution (10 KB AAR) |
| Memory (Bitmap) | ~3.6 MB | 1280×720×4 bytes |
| Memory (Buffer) | ~3.6 MB | Duplicate for pixel copy |
| Total Memory | ~7.2 MB | Per WebView instance |

### Optimization Notes

1. **Update Rate Limiting**: 30 FPS max prevents GPU/CPU overload
2. **Forced Updates**: 500ms ensures texture doesn't stall completely
3. **Hidden Container**: WebView rendered off-screen (invisible)
4. **Async Rendering**: WebView.draw() called on main thread with timeout
5. **Bitmap Caching**: Reused between frames (recreated on resize)

### Recommended Settings

- **Quest 3**: 1280×720 resolution (optimal balance)
- **High-End Android**: 1920×1080 (if system allows)
- **Low-End Android**: 960×540 (reduced memory usage)

---

## Known Limitations & Workarounds

### Limitation 1: Native Scroll Rendering Artifacts
**Issue**: Direct scroll via MotionEvents causes texture desynchronization  
**Workaround**: Use JavaScript-based scrolling (`scrollToPosition()`, `scrollByAmount()`)

### Limitation 2: Hidden WebView Rendering
**Issue**: WebView renders off-screen, some visual effects may not display correctly  
**Workaround**: Test with target web content; most modern websites render fine

### Limitation 3: No Hardware Accelerated Rendering to Texture
**Issue**: WebView renders to bitmap (CPU), then copied to GPU texture  
**Workaround**: Inherent limitation; 30 FPS limit mitigates performance impact

### Limitation 4: Package Attribute Deprecation
**Issue**: AndroidManifest.xml `package` attribute ignored on newer Android  
**Warning**: Non-critical; namespace set via build.gradle `namespace` property

---

## Security Considerations

### Permissions

**Required** (in AndroidManifest.xml):
- `android.permission.INTERNET` - Network access
- `android.permission.ACCESS_NETWORK_STATE` - Network status checking

### Content Security

1. **File Access Enabled** - `setAllowFileAccess(true)` allows file:// URLs
2. **Content URI Access** - `setAllowContentAccess(true)` allows content:// URIs
3. **JavaScript Enabled** - `setJavaScriptEnabled(true)` allows script execution
4. **Mixed Content** - HTTPS pages can load HTTP resources

### Best Practices

1. **Validate URLs** - Only load trusted content
2. **Restrict JavaScript** - Disable if not needed for your use case
3. **Use HTTPS** - Prefer encrypted connections
4. **Monitor Cache** - Clear cache periodically for sensitive content

---

## Troubleshooting

### Plugin Not Loading

**Symptoms**: "Plugin 'GodotAndroidWebView' not found"

**Checklist**:
- [ ] AAR file exists: `android/plugins/GodotAndroidWebView.aar`
- [ ] GDAP file exists: `android/plugins/GodotAndroidWebView.gdap`
- [ ] GDAP points to correct AAR filename
- [ ] Plugin enabled in export settings
- [ ] Build is clean (no caching issues)

### Black/White Texture

**Symptoms**: WebView renders but shows only solid color

**Causes & Fixes**:
- **INTERNET permission missing** - Check AndroidManifest.xml
- **Invalid URL** - Test with `https://www.google.com`
- **WebView rendering blocked** - Check Android version compatibility
- **Timeout in rendering** - Increase wait time in `getPixelData()`

**Debug**: Add logging in `GodotAndroidWebView.java`:
```java
android.util.Log.d(TAG, "Canvas cleared and WebView drawn");
```

### Touch Not Working

**Symptoms**: No response to touch events

**Checklist**:
- [ ] Viewport coordinates correctly converted to WebView coordinates
- [ ] Touch events actually reaching the plugin (add logging)
- [ ] WebView layout matches expected dimensions
- [ ] No other views intercepting touch events

### Memory Issues

**Symptoms**: App crashes after WebView operations

**Causes**:
- **Bitmap allocation failure** - Reduce resolution or free memory
- **Buffer allocation** - ByteBuffer limited by JVM heap
- **Memory leak** - Ensure `destroy()` is called

**Fix**:
```gdscript
# Periodically cleanup
if webview.is_initialized():
    webview.destroy()
    yield(get_tree(), "process_frame")
    webview.initialize(width, height, url)
```

---

## Future Enhancements

### Potential Improvements

1. **Hardware Acceleration** - DirectX/OpenGL interop for faster texture transfer
2. **Streaming** - Progressive pixel updates instead of full frame
3. **Multiple WebViews** - Support multiple instances
4. **Video Playback** - Optimize video in WebView
5. **Gesture Recognition** - Pinch zoom, swipe gestures
6. **Screenshot Capture** - Export current frame as image file

### Performance Optimizations

1. **Reduce Update Frequency** - Configurable FPS limit
2. **Partial Updates** - Only redraw changed regions
3. **Texture Compression** - ASTC or PVRTC compression
4. **Memory Pooling** - Reuse buffers across multiple WebViews

---

## References

### Android Documentation
- [WebView Class](https://developer.android.com/reference/android/webkit/WebView)
- [WebViewClient](https://developer.android.com/reference/android/webkit/WebViewClient)
- [WebChromeClient](https://developer.android.com/reference/android/webkit/WebChromeClient)
- [MotionEvent](https://developer.android.com/reference/android/view/MotionEvent)

### Godot Documentation
- [Creating Android Plugins](https://docs.godotengine.org/en/stable/tutorials/platform/android/android_plugin.html)
- [GodotPlugin Class](https://docs.godotengine.org/en/stable/tutorials/platform/android/android_plugin.html#godotplugin)

### Project Files
- Source: `/addons/godot_android_webview/android_plugin/src/main/java/com/godot/webview/GodotAndroidWebView.java`
- Build Config: `/addons/godot_android_webview/android_plugin/build.gradle`
- Plugin Config: `/android/plugins/GodotAndroidWebView.gdap`
- Compiled Binary: `/android/plugins/GodotAndroidWebView.aar`

---

## Build Artifacts & Deployment

### Final Deployment Checklist

- [ ] `android/plugins/GodotAndroidWebView.aar` (10.0 KB)
- [ ] `android/plugins/GodotAndroidWebView.gdap` (154 bytes)
- [ ] Both files present before Android export
- [ ] Plugin enabled in export template settings
- [ ] Correct permissions in export manifest
- [ ] Dependencies resolved (AndroidX libraries)

### Version Information

- **Plugin Version**: 1.0.0
- **Build Date**: December 31, 2025
- **Last Build**: Gradle `./gradlew clean assembleRelease`
- **Target Platforms**: Android 7.0+ (API 24-33)
- **Godot Version**: 4.2+

---

## Conclusion

The GodotAndroidWebView plugin provides a robust integration of Android's WebView component into Godot 4, enabling real-time web content rendering to textures. Its architecture leverages Android's main thread handling, careful memory management, and rate-limited updates to deliver reliable performance in VR and interactive applications.

The implementation demonstrates best practices for native Android plugin development for Godot:
- Proper thread synchronization
- Lifecycle management and resource cleanup
- Signal-based event communication
- Rate limiting for performance optimization
- Comprehensive error handling and fallbacks
