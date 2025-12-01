# Add project specific ProGuard rules here.

# Keep LiveKit classes
-keep class io.livekit.** { *; }
-keepclassmembers class io.livekit.** { *; }

# Keep WebRTC classes
-keep class org.webrtc.** { *; }
-keepclassmembers class org.webrtc.** { *; }

# Keep the Godot plugin class
-keep class com.jvastola.physicshand.livekit.GodotLiveKit { *; }
-keep class com.jvastola.physicshand.livekit.LiveKitCoroutineHelper { *; }

# Keep methods annotated with @UsedByGodot
-keepclassmembers class * {
    @org.godotengine.godot.plugin.UsedByGodot *;
}

# Kotlin coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembernames class kotlinx.** {
    volatile <fields>;
}
