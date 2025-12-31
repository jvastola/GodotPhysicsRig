package com.godot.webview;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
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
    private AtomicBoolean isInitialized = new AtomicBoolean(false);
    private AtomicBoolean needsUpdate = new AtomicBoolean(false);
    private String currentUrl = "";
    private int loadProgress = 0;
    private boolean canGoBack = false;
    private boolean canGoForward = false;
    
    // Update rate limiting
    private long lastUpdateTime = 0;
    private static final long MIN_UPDATE_INTERVAL_MS = 33; // ~30 FPS max
    
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
        
        mainHandler.post(() -> {
            Activity activity = getActivity();
            if (activity == null) {
                return;
            }
            
            // Create WebView
            webView = new WebView(activity);
            webView.setLayoutParams(new FrameLayout.LayoutParams(width, height));
            
            // Configure WebView settings
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
                    emitSignal("page_loaded", url);
                    requestRender();
                }
                
                @Override
                public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                    return false; // Let WebView handle all URLs
                }
            });
            
            // Set Chrome client for progress and title
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
            
            // Add WebView to a hidden container (needed for rendering)
            FrameLayout container = new FrameLayout(activity);
            container.setLayoutParams(new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            ));
            container.addView(webView);
            
            // Make it invisible but still render
            container.setVisibility(View.INVISIBLE);
            
            // Add to activity's root view
            ViewGroup rootView = activity.findViewById(android.R.id.content);
            if (rootView != null) {
                rootView.addView(container);
            }
            
            // Load initial URL
            if (initialUrl != null && !initialUrl.isEmpty()) {
                webView.loadUrl(initialUrl);
            }
            
            isInitialized.set(true);
        });
        
        return true;
    }
    
    @UsedByGodot
    public void loadUrl(String url) {
        if (!isInitialized.get() || webView == null) return;
        
        mainHandler.post(() -> {
            webView.loadUrl(url);
        });
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
            if (webView.canGoBack()) {
                webView.goBack();
            }
        });
    }
    
    @UsedByGodot
    public void goForward() {
        if (!isInitialized.get() || webView == null) return;
        
        mainHandler.post(() -> {
            if (webView.canGoForward()) {
                webView.goForward();
            }
        });
    }
    
    @UsedByGodot
    public void reload() {
        if (!isInitialized.get() || webView == null) return;
        
        mainHandler.post(() -> {
            webView.reload();
        });
    }
    
    @UsedByGodot
    public void stopLoading() {
        if (!isInitialized.get() || webView == null) return;
        
        mainHandler.post(() -> {
            webView.stopLoading();
        });
    }
    
    @UsedByGodot
    public void resize(int newWidth, int newHeight) {
        if (!isInitialized.get()) return;
        
        this.width = newWidth;
        this.height = newHeight;
        
        // Recreate bitmap and buffer
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
    
    @UsedByGodot
    public void touchDown(int x, int y) {
        if (!isInitialized.get() || webView == null) return;
        
        mainHandler.post(() -> {
            long downTime = android.os.SystemClock.uptimeMillis();
            android.view.MotionEvent event = android.view.MotionEvent.obtain(
                downTime, downTime,
                android.view.MotionEvent.ACTION_DOWN,
                x, y, 0
            );
            webView.dispatchTouchEvent(event);
            event.recycle();
        });
    }
    
    @UsedByGodot
    public void touchMove(int x, int y) {
        if (!isInitialized.get() || webView == null) return;
        
        mainHandler.post(() -> {
            long downTime = android.os.SystemClock.uptimeMillis();
            android.view.MotionEvent event = android.view.MotionEvent.obtain(
                downTime, downTime,
                android.view.MotionEvent.ACTION_MOVE,
                x, y, 0
            );
            webView.dispatchTouchEvent(event);
            event.recycle();
        });
    }
    
    @UsedByGodot
    public void touchUp(int x, int y) {
        if (!isInitialized.get() || webView == null) return;
        
        mainHandler.post(() -> {
            long downTime = android.os.SystemClock.uptimeMillis();
            android.view.MotionEvent event = android.view.MotionEvent.obtain(
                downTime, downTime,
                android.view.MotionEvent.ACTION_UP,
                x, y, 0
            );
            webView.dispatchTouchEvent(event);
            event.recycle();
            requestRender();
        });
    }
    
    @UsedByGodot
    public void scroll(int x, int y, int deltaY) {
        if (!isInitialized.get() || webView == null) return;
        
        mainHandler.post(() -> {
            webView.scrollBy(0, -deltaY);
            requestRender();
        });
    }
    
    @UsedByGodot
    public void inputText(String text) {
        if (!isInitialized.get() || webView == null) return;
        
        mainHandler.post(() -> {
            // Inject text via JavaScript
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
        
        mainHandler.post(() -> {
            webView.evaluateJavascript(script, null);
        });
    }
    
    private void requestRender() {
        needsUpdate.set(true);
    }
    
    @UsedByGodot
    public byte[] getPixelData() {
        if (!isInitialized.get() || webView == null || bitmap == null) {
            return new byte[0];
        }
        
        // Rate limit updates
        long now = System.currentTimeMillis();
        if (now - lastUpdateTime < MIN_UPDATE_INTERVAL_MS && !needsUpdate.get()) {
            return new byte[0];
        }
        lastUpdateTime = now;
        needsUpdate.set(false);
        
        // Render WebView to bitmap on main thread
        final Object lock = new Object();
        final AtomicBoolean done = new AtomicBoolean(false);
        
        mainHandler.post(() -> {
            synchronized (lock) {
                try {
                    // Clear canvas
                    canvas.drawColor(android.graphics.Color.WHITE);
                    // Draw WebView
                    webView.draw(canvas);
                } catch (Exception e) {
                    // Ignore rendering errors
                }
                done.set(true);
                lock.notify();
            }
        });
        
        // Wait for render to complete (with timeout)
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
        
        // Convert to byte array
        byte[] pixels = new byte[pixelBuffer.capacity()];
        pixelBuffer.rewind();
        pixelBuffer.get(pixels);
        
        // ARGB to RGBA conversion
        for (int i = 0; i < pixels.length; i += 4) {
            byte a = pixels[i];
            byte r = pixels[i + 1];
            byte g = pixels[i + 2];
            byte b = pixels[i + 3];
            pixels[i] = r;
            pixels[i + 1] = g;
            pixels[i + 2] = b;
            pixels[i + 3] = a;
        }
        
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
}
