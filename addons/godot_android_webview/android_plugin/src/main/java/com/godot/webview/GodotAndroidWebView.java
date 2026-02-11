package com.godot.webview;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.SurfaceTexture;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.view.MotionEvent;
import android.view.Surface;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;

import androidx.annotation.NonNull;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.nio.ByteBuffer;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Godot Android WebView Plugin
 * Renders Android WebView content to a byte buffer that can be used as a texture in Godot.
 * Supports hardware-accelerated video playback via SurfaceTexture.
 */
public class GodotAndroidWebView extends GodotPlugin {
    
    private static final String TAG = "GodotAndroidWebView";
    
    private WebView webView;
    private Handler mainHandler;
    private int width = 1280;
    private int height = 720;
    private Bitmap bitmap;
    private ByteBuffer pixelBuffer;
    private Canvas canvas;
    private Paint paint;
    private AtomicBoolean isInitialized = new AtomicBoolean(false);
    private AtomicBoolean needsUpdate = new AtomicBoolean(false);
    private String currentUrl = "";
    private int loadProgress = 0;
    private boolean canGoBack = false;
    private boolean canGoForward = false;
    
    // Touch state tracking for proper gesture handling
    private long touchDownTime = 0;
    private boolean isTouchActive = false;
    
    // Update rate limiting - faster for smoother scrolling
    private long lastUpdateTime = 0;
    private long lastForceUpdateTime = 0;
    private static final long MIN_UPDATE_INTERVAL_MS = 16; // ~60 FPS for smooth scrolling
    private static final long FORCE_UPDATE_INTERVAL_MS = 100; // Force update every 100ms
    
    public GodotAndroidWebView(Godot godot) {
        super(godot);
        mainHandler = new Handler(Looper.getMainLooper());
    }
    
    @NonNull
    @Override
    public String getPluginName() {
        return "GodotAndroidWebView";
    }
    
    @NonNull
    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo("page_loaded", String.class));
        signals.add(new SignalInfo("page_started", String.class));
        signals.add(new SignalInfo("progress_changed", Integer.class));
        signals.add(new SignalInfo("title_changed", String.class));
        signals.add(new SignalInfo("texture_updated"));
        signals.add(new SignalInfo("scroll_info_received", String.class));
        return signals;
    }
    
    @UsedByGodot
    public boolean initialize(int viewWidth, int viewHeight, String initialUrl) {
        if (isInitialized.get()) {
            return true;
        }
        
        this.width = viewWidth;
        this.height = viewHeight;
        
        // Create bitmap and buffer for texture capture
        bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        pixelBuffer = ByteBuffer.allocateDirect(width * height * 4);
        canvas = new Canvas(bitmap);
        paint = new Paint();
        paint.setFilterBitmap(true);
        
        mainHandler.post(() -> {
            Activity activity = getActivity();
            if (activity == null) {
                return;
            }
            
            // Create WebView with hardware acceleration
            webView = new WebView(activity);
            webView.setLayoutParams(new FrameLayout.LayoutParams(width, height));
            
            // Enable hardware acceleration for video playback
            webView.setLayerType(View.LAYER_TYPE_HARDWARE, null);

            // Configure WebView settings for desktop-like experience
            WebSettings settings = webView.getSettings();
            settings.setJavaScriptEnabled(true);
            settings.setDomStorageEnabled(true);
            settings.setDatabaseEnabled(true);
            settings.setMediaPlaybackRequiresUserGesture(false);
            settings.setUseWideViewPort(true);
            settings.setLoadWithOverviewMode(true);
            settings.setSupportZoom(true);
            settings.setBuiltInZoomControls(true);
            settings.setDisplayZoomControls(false);
            settings.setAllowFileAccess(true);
            settings.setAllowContentAccess(true);
            settings.setCacheMode(WebSettings.LOAD_DEFAULT);
            
            // Force desktop mode with Chrome user agent
            String desktopUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
            settings.setUserAgentString(desktopUserAgent);
            
            // Text settings
            settings.setTextZoom(100);
            settings.setMinimumFontSize(8);
            settings.setMinimumLogicalFontSize(8);
            
            // Enable mixed content for HTTPS pages with HTTP resources
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                settings.setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);
            }
            
            // Set WebView client for page events
            webView.setWebViewClient(new WebViewClient() {
                @Override
                public void onPageStarted(WebView view, String url, Bitmap favicon) {
                    super.onPageStarted(view, url, favicon);
                    currentUrl = url;
                    emitSignal("page_started", url);
                }
                
                @Override
                public void onPageFinished(WebView view, String url) {
                    super.onPageFinished(view, url);
                    currentUrl = url;
                    canGoBack = view.canGoBack();
                    canGoForward = view.canGoForward();
                    
                    // Inject CSS to hide scrollbars (we handle scrolling via touch)
                    view.evaluateJavascript(
                        "(function() {" +
                        "  var style = document.createElement('style');" +
                        "  style.textContent = '::-webkit-scrollbar { display: none !important; } " +
                        "    html, body { scrollbar-width: none !important; -ms-overflow-style: none !important; }';" +
                        "  document.head.appendChild(style);" +
                        "})();",
                        null
                    );
                    
                    emitSignal("page_loaded", url);
                    requestRender();
                }
                
                @Override
                public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                    return false;
                }
            });
            
            // Set Chrome client for progress, title, and fullscreen video
            webView.setWebChromeClient(new WebChromeClient() {
                @Override
                public void onProgressChanged(WebView view, int newProgress) {
                    loadProgress = newProgress;
                    emitSignal("progress_changed", newProgress);
                    if (newProgress % 10 == 0) {
                        requestRender();
                    }
                }
                
                @Override
                public void onReceivedTitle(WebView view, String title) {
                    emitSignal("title_changed", title);
                }
            });
            
            // Add WebView to activity (invisible but rendering)
            FrameLayout container = new FrameLayout(activity);
            container.setLayoutParams(new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            ));
            container.addView(webView);
            container.setVisibility(View.INVISIBLE);
            
            ViewGroup rootView = activity.findViewById(android.R.id.content);
            if (rootView != null) {
                rootView.addView(container);
            }
            
            // Load initial URL
            if (initialUrl != null && !initialUrl.isEmpty()) {
                webView.loadUrl(initialUrl);
            }
            
            isInitialized.set(true);
            
            // Force initial render
            mainHandler.postDelayed(() -> needsUpdate.set(true), 500);
        });
        
        return true;
    }
    
    @UsedByGodot
    public void loadUrl(String url) {
        if (!isInitialized.get() || webView == null) return;
        mainHandler.post(() -> webView.loadUrl(url));
    }
    
    @UsedByGodot
    public String getUrl() {
        return currentUrl;
    }
    
    @UsedByGodot
    public int getProgress() {
        return loadProgress;
    }
    
    @UsedByGodot
    public boolean canGoBack() {
        return canGoBack;
    }
    
    @UsedByGodot
    public boolean canGoForward() {
        return canGoForward;
    }
    
    @UsedByGodot
    public void goBack() {
        if (!isInitialized.get() || webView == null) return;
        mainHandler.post(() -> {
            if (webView.canGoBack()) webView.goBack();
        });
    }
    
    @UsedByGodot
    public void goForward() {
        if (!isInitialized.get() || webView == null) return;
        mainHandler.post(() -> {
            if (webView.canGoForward()) webView.goForward();
        });
    }
    
    @UsedByGodot
    public void reload() {
        if (!isInitialized.get() || webView == null) return;
        mainHandler.post(() -> webView.reload());
    }
    
    @UsedByGodot
    public void stopLoading() {
        if (!isInitialized.get() || webView == null) return;
        mainHandler.post(() -> webView.stopLoading());
    }
    
    @UsedByGodot
    public void resize(int newWidth, int newHeight) {
        if (!isInitialized.get()) return;
        
        this.width = newWidth;
        this.height = newHeight;
        
        bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        pixelBuffer = ByteBuffer.allocateDirect(width * height * 4);
        canvas = new Canvas(bitmap);
        
        mainHandler.post(() -> {
            if (webView != null) {
                webView.setLayoutParams(new FrameLayout.LayoutParams(width, height));
                webView.requestLayout();
            }
        });
    }

    
    /**
     * Send touch down event - starts a touch gesture
     */
    @UsedByGodot
    public void touchDown(int x, int y) {
        if (!isInitialized.get() || webView == null) return;
        
        mainHandler.post(() -> {
            touchDownTime = android.os.SystemClock.uptimeMillis();
            isTouchActive = true;
            
            MotionEvent event = MotionEvent.obtain(
                touchDownTime, touchDownTime,
                MotionEvent.ACTION_DOWN,
                x, y, 0
            );
            webView.dispatchTouchEvent(event);
            event.recycle();
            requestRender();
        });
    }
    
    /**
     * Send touch move event - continues a touch gesture (for scrolling)
     */
    @UsedByGodot
    public void touchMove(int x, int y) {
        if (!isInitialized.get() || webView == null || !isTouchActive) return;
        
        mainHandler.post(() -> {
            long eventTime = android.os.SystemClock.uptimeMillis();
            MotionEvent event = MotionEvent.obtain(
                touchDownTime, eventTime,
                MotionEvent.ACTION_MOVE,
                x, y, 0
            );
            webView.dispatchTouchEvent(event);
            event.recycle();
            requestRender();
        });
    }
    
    /**
     * Send touch up event - ends a touch gesture
     */
    @UsedByGodot
    public void touchUp(int x, int y) {
        if (!isInitialized.get() || webView == null) return;
        
        mainHandler.post(() -> {
            long eventTime = android.os.SystemClock.uptimeMillis();
            MotionEvent event = MotionEvent.obtain(
                touchDownTime, eventTime,
                MotionEvent.ACTION_UP,
                x, y, 0
            );
            webView.dispatchTouchEvent(event);
            event.recycle();
            isTouchActive = false;
            requestRender();
        });
    }
    
    /**
     * Send touch cancel event - cancels current touch gesture
     */
    @UsedByGodot
    public void touchCancel() {
        if (!isInitialized.get() || webView == null || !isTouchActive) return;
        
        mainHandler.post(() -> {
            long eventTime = android.os.SystemClock.uptimeMillis();
            MotionEvent event = MotionEvent.obtain(
                touchDownTime, eventTime,
                MotionEvent.ACTION_CANCEL,
                0, 0, 0
            );
            webView.dispatchTouchEvent(event);
            event.recycle();
            isTouchActive = false;
        });
    }
    
    /**
     * Perform a tap (click) at the specified position
     */
    @UsedByGodot
    public void tap(int x, int y) {
        if (!isInitialized.get() || webView == null) return;
        
        mainHandler.post(() -> {
            long downTime = android.os.SystemClock.uptimeMillis();
            
            // Send DOWN
            MotionEvent downEvent = MotionEvent.obtain(
                downTime, downTime,
                MotionEvent.ACTION_DOWN,
                x, y, 0
            );
            webView.dispatchTouchEvent(downEvent);
            downEvent.recycle();
            
            // Send UP after short delay for proper click detection
            mainHandler.postDelayed(() -> {
                long upTime = android.os.SystemClock.uptimeMillis();
                MotionEvent upEvent = MotionEvent.obtain(
                    downTime, upTime,
                    MotionEvent.ACTION_UP,
                    x, y, 0
                );
                webView.dispatchTouchEvent(upEvent);
                upEvent.recycle();
                requestRender();
            }, 50);
        });
    }
    
    @UsedByGodot
    public void scroll(int x, int y, int deltaY) {
        // Deprecated - use native touch scrolling instead
    }
    
    @UsedByGodot
    public void scrollDrag(int x, int startY, int currentY) {
        // Deprecated - use native touch scrolling instead
    }
    
    @UsedByGodot
    public void scrollEnd(int x, int y) {
        // Deprecated - use native touch scrolling instead
    }
    
    @UsedByGodot
    public void scrollToPosition(int scrollY) {
        if (!isInitialized.get() || webView == null) return;
        mainHandler.post(() -> {
            webView.evaluateJavascript("window.scrollTo(0, " + scrollY + ");", null);
            requestRender();
        });
    }
    
    @UsedByGodot
    public void scrollByAmount(int deltaY) {
        if (!isInitialized.get() || webView == null) return;
        mainHandler.post(() -> {
            webView.evaluateJavascript("window.scrollBy(0, " + deltaY + ");", null);
            requestRender();
        });
    }
    
    @UsedByGodot
    public void getScrollInfo() {
        if (!isInitialized.get() || webView == null) {
            emitSignal("scroll_info_received", "{\"scrollY\":0,\"scrollHeight\":0,\"clientHeight\":0}");
            return;
        }
        
        mainHandler.post(() -> {
            webView.evaluateJavascript(
                "(function() { " +
                "  return JSON.stringify({" +
                "    scrollY: window.scrollY || document.documentElement.scrollTop || 0," +
                "    scrollHeight: document.documentElement.scrollHeight || document.body.scrollHeight || 0," +
                "    clientHeight: window.innerHeight || document.documentElement.clientHeight || 0" +
                "  });" +
                "})()",
                value -> {
                    String result = value;
                    if (result != null && result.startsWith("\"") && result.endsWith("\"")) {
                        result = result.substring(1, result.length() - 1);
                        result = result.replace("\\\"", "\"");
                    }
                    emitSignal("scroll_info_received", result != null ? result : "{}");
                }
            );
        });
    }
    
    @UsedByGodot
    public void inputText(String text) {
        if (!isInitialized.get() || webView == null) return;
        mainHandler.post(() -> {
            String escapedText = text.replace("\\", "\\\\")
                                    .replace("'", "\\'")
                                    .replace("\n", "\\n");
            webView.evaluateJavascript(
                "if(document.activeElement){document.activeElement.value+='" + escapedText + "';}",
                null
            );
        });
    }
    
    @UsedByGodot
    public void executeJavaScript(String script) {
        if (!isInitialized.get() || webView == null) return;
        mainHandler.post(() -> webView.evaluateJavascript(script, null));
    }
    
    private void requestRender() {
        needsUpdate.set(true);
    }

    
    @UsedByGodot
    public byte[] getPixelData() {
        if (!isInitialized.get() || webView == null || bitmap == null) {
            return new byte[0];
        }
        
        // Rate limit updates for performance
        long now = System.currentTimeMillis();
        boolean forceUpdate = (now - lastForceUpdateTime) >= FORCE_UPDATE_INTERVAL_MS;
        
        if (!forceUpdate && (now - lastUpdateTime < MIN_UPDATE_INTERVAL_MS) && !needsUpdate.get()) {
            return new byte[0];
        }
        
        if (forceUpdate) {
            lastForceUpdateTime = now;
        }
        
        lastUpdateTime = now;
        needsUpdate.set(false);
        
        // Render WebView to bitmap on main thread
        final Object lock = new Object();
        final AtomicBoolean done = new AtomicBoolean(false);
        
        mainHandler.post(() -> {
            synchronized (lock) {
                try {
                    // Clear canvas with white background
                    canvas.drawColor(android.graphics.Color.WHITE);
                    
                    // For hardware-accelerated content, we need to use a different approach
                    // First try software rendering for the WebView
                    webView.setDrawingCacheEnabled(true);
                    webView.buildDrawingCache(true);
                    Bitmap cache = webView.getDrawingCache();
                    
                    if (cache != null) {
                        // Scale the cached bitmap to our target size
                        canvas.drawBitmap(cache, 0, 0, paint);
                    } else {
                        // Fallback to direct draw
                        webView.draw(canvas);
                    }
                    
                    webView.setDrawingCacheEnabled(false);
                } catch (Exception e) {
                    android.util.Log.e(TAG, "Error rendering WebView: " + e.getMessage());
                }
                done.set(true);
                lock.notify();
            }
        });
        
        // Wait for render to complete
        synchronized (lock) {
            try {
                if (!done.get()) {
                    lock.wait(100);
                }
            } catch (InterruptedException e) {
                return new byte[0];
            }
        }
        
        // Copy bitmap pixels to buffer
        pixelBuffer.rewind();
        bitmap.copyPixelsToBuffer(pixelBuffer);
        
        byte[] pixels = new byte[pixelBuffer.capacity()];
        pixelBuffer.rewind();
        pixelBuffer.get(pixels);
        
        emitSignal("texture_updated");
        return pixels;
    }
    
    @UsedByGodot
    public int getWidth() {
        return width;
    }
    
    @UsedByGodot
    public int getHeight() {
        return height;
    }
    
    @UsedByGodot
    public boolean isInitialized() {
        return isInitialized.get();
    }
    
    @UsedByGodot
    public void destroy() {
        if (!isInitialized.get()) return;
        
        mainHandler.post(() -> {
            if (webView != null) {
                webView.stopLoading();
                webView.clearHistory();
                webView.clearCache(true);
                webView.loadUrl("about:blank");
                webView.onPause();
                webView.removeAllViews();
                
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
            }
            
            bitmap = null;
            pixelBuffer = null;
            canvas = null;
            isInitialized.set(false);
        });
    }
    @Override
    public void onMainDestroy() {
        // Ensure we clean up the WebView when the activity is destroyed
        destroy();
        super.onMainDestroy();
    }
}
