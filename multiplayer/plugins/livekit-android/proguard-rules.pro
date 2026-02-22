# Add project specific ProGuard rules here.

# =============================================================================
# CONSCRYPT / OKHTTP SECURITY FIX (Meta VRC Compliance)
# =============================================================================
# Remove Conscrypt platform to use Android's default TLS/SSL
# This addresses Meta VRC security warnings about HostnameVerifier

# Suppress all Conscrypt warnings
-dontwarn org.conscrypt.**
-dontwarn okhttp3.internal.platform.ConscryptPlatform
-dontwarn okhttp3.internal.platform.ConscryptPlatform$*
-dontwarn okhttp3.internal.platform.android.ConscryptSocketAdapter
-dontwarn okhttp3.internal.platform.android.ConscryptSocketAdapter$*

# Force removal of Conscrypt-related classes
-assumenosideeffects class okhttp3.internal.platform.ConscryptPlatform { *; }
-assumenosideeffects class okhttp3.internal.platform.ConscryptPlatform$Companion { *; }
-assumenosideeffects class okhttp3.internal.platform.android.ConscryptSocketAdapter { *; }
-assumenosideeffects class org.conscrypt.** { *; }

# =============================================================================
# LIVEKIT & WEBRTC
# =============================================================================

# Keep LiveKit classes
-keep class io.livekit.** { *; }
-keepclassmembers class io.livekit.** { *; }

# Keep WebRTC classes
-keep class org.webrtc.** { *; }
-keepclassmembers class org.webrtc.** { *; }

# =============================================================================
# GODOT PLUGIN
# =============================================================================

# Keep the Godot plugin class
-keep class com.jvastola.physicshand.livekit.GodotLiveKitPlugin { *; }
-keep class com.jvastola.physicshand.livekit.LiveKitCoroutineHelper { *; }

# Keep methods annotated with @UsedByGodot
-keepclassmembers class * {
    @org.godotengine.godot.plugin.UsedByGodot *;
}

# =============================================================================
# KOTLIN COROUTINES
# =============================================================================

-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembernames class kotlinx.** {
    volatile <fields>;
}
-dontwarn kotlinx.coroutines.**

# =============================================================================
# OKHTTP & OKIO
# =============================================================================

-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
