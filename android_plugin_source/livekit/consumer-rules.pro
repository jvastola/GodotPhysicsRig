# Consumer proguard rules - applied to consuming apps

# Keep LiveKit classes
-keep class io.livekit.** { *; }

# Keep WebRTC classes  
-keep class org.webrtc.** { *; }

# Keep the plugin classes
-keep class com.jvastola.physicshand.livekit.** { *; }
