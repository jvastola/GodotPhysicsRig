package com.jvastola.physicshand.livekit

import android.os.Handler
import android.os.Looper
import io.livekit.android.*
import io.livekit.android.events.*
import io.livekit.android.room.*
import io.livekit.android.room.track.*
import io.livekit.android.room.participant.*
import kotlinx.coroutines.*
import livekit.org.webrtc.AudioTrackSink
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.nio.ByteBuffer
import java.nio.ByteOrder

class GodotLiveKitPlugin(godot: Godot) : GodotPlugin(godot) {

    companion object {
        const val PLUGIN_NAME = "GodotLiveKit"
    }

    private var room: Room? = null
    private var scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var isMuted: Boolean = false  // Track user's mute preference
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pcmSpatialAudioEnabled: Boolean = true

    private data class RemoteAudioSinkBinding(
        val participantIdentity: String,
        val trackSid: String,
        val track: RemoteAudioTrack,
        val sink: AudioTrackSink
    )

    private val remoteAudioSinks = mutableMapOf<String, RemoteAudioSinkBinding>()

    override fun getPluginName(): String = PLUGIN_NAME

    override fun getPluginSignals(): Set<SignalInfo> {
        return setOf(
            SignalInfo("room_connected"),
            SignalInfo("room_disconnected"),
            SignalInfo("participant_joined", String::class.java),
            SignalInfo("participant_left", String::class.java),
            SignalInfo("participant_metadata_changed", String::class.java, String::class.java),
            SignalInfo("data_received", String::class.java, ByteArray::class.java, String::class.java),
            SignalInfo("audio_frame", String::class.java, FloatArray::class.java),
            SignalInfo("track_subscribed", String::class.java, String::class.java),
            SignalInfo("track_unsubscribed", String::class.java, String::class.java),
            SignalInfo("audio_track_published"),
            SignalInfo("audio_track_unpublished"),
            SignalInfo("error_occurred", String::class.java)
        )
    }

    @UsedByGodot
    fun connectToRoom(url: String, token: String) {
        android.util.Log.d("GodotLiveKit", "connectToRoom called: $url")
        scope.launch {
            try {
                removeAllRemoteAudioSinks()
                val currentActivity = activity
                if (currentActivity == null) {
                    android.util.Log.e("GodotLiveKit", "Activity is null")
                    emitSignal("error_occurred", "Activity is null")
                    return@launch
                }

                android.util.Log.d("GodotLiveKit", "Creating LiveKit room...")
                // LK 2.x: Create room then connect
                room = LiveKit.create(currentActivity)
                android.util.Log.d("GodotLiveKit", "Room created, setting up listeners...")
                
                setupRoomListeners()
                
                android.util.Log.d("GodotLiveKit", "Connecting to room...")
                room?.connect(
                    url,
                    token
                )
                android.util.Log.d("GodotLiveKit", "Connected successfully!")
                
                // Only enable mic if not muted
                if (!isMuted) {
                    room?.localParticipant?.setMicrophoneEnabled(true)
                    android.util.Log.d("GodotLiveKit", "connectToRoom: Mic enabled (not muted) with HQ settings")
                } else {
                    android.util.Log.d("GodotLiveKit", "connectToRoom: Mic disabled (user muted)")
                }
                
                emitSignal("room_connected")
            } catch (e: Exception) {
                android.util.Log.e("GodotLiveKit", "Connection error: ${e.javaClass.name}: ${e.message}", e)
                emitSignal("error_occurred", "${e.javaClass.simpleName}: ${e.message ?: "Connection failed"}")
            } catch (t: Throwable) {
                android.util.Log.e("GodotLiveKit", "Connection throwable: ${t.javaClass.name}: ${t.message}", t)
                emitSignal("error_occurred", "${t.javaClass.simpleName}: ${t.message ?: "Connection failed"}")
            }
        }
    }

    @UsedByGodot
    fun disconnectFromRoom() {
        scope.launch {
            removeAllRemoteAudioSinks()
            room?.disconnect()
            room = null
            emitSignal("room_disconnected")
        }
    }

    @UsedByGodot
    fun isRoomConnected(): Boolean = room?.state == Room.State.CONNECTED

    @UsedByGodot
    fun get_local_identity(): String {
        return room?.localParticipant?.identity?.value ?: ""
    }

    @UsedByGodot
    fun getParticipantIdentities(): String {
        val identities = mutableListOf<String>()
        room?.remoteParticipants?.keys?.forEach { identities.add(it.value) }
        return identities.joinToString(",")
    }

    @UsedByGodot
    fun isPcmSpatialAudioEnabled(): Boolean = pcmSpatialAudioEnabled

    @UsedByGodot
    fun sendData(data: ByteArray, topic: String) {
        sendDataReliable(data, topic)
    }

    @UsedByGodot
    fun sendDataReliable(data: ByteArray, topic: String) {
        scope.launch {
            room?.localParticipant?.publishData(
                data,
                DataPublishReliability.RELIABLE,
                topic
            )
        }
    }

    @UsedByGodot
    fun sendDataUnreliable(data: ByteArray, topic: String) {
        scope.launch {
            room?.localParticipant?.publishData(
                data,
                DataPublishReliability.LOSSY,
                topic
            )
        }
    }

    @UsedByGodot
    fun sendDataTo(data: ByteArray, identity: String, topic: String) {
        sendDataToReliable(data, identity, topic)
    }

    @UsedByGodot
    fun sendDataToReliable(data: ByteArray, identity: String, topic: String) {
        publishDataToIdentity(data, identity, topic, DataPublishReliability.RELIABLE)
    }

    @UsedByGodot
    fun sendDataToUnreliable(data: ByteArray, identity: String, topic: String) {
        publishDataToIdentity(data, identity, topic, DataPublishReliability.LOSSY)
    }

    @UsedByGodot
    fun setAudioEnabled(enabled: Boolean) {
        isMuted = !enabled  // Remember user preference
        android.util.Log.d("GodotLiveKit", "setAudioEnabled: $enabled, isMuted: $isMuted")
        scope.launch {
            room?.localParticipant?.setMicrophoneEnabled(enabled)
        }
    }

    private fun publishDataToIdentity(
        data: ByteArray,
        identity: String,
        topic: String,
        reliability: DataPublishReliability
    ) {
        scope.launch {
            val participant = room?.remoteParticipants?.values?.find { it.identity?.value == identity }
            if (participant != null && participant.identity != null) {
                room?.localParticipant?.publishData(
                    data,
                    reliability,
                    topic,
                    listOf(participant.identity!!)
                )
            }
        }
    }

    @UsedByGodot
    fun setParticipantVolume(identity: String, volume: Double) {
        if (pcmSpatialAudioEnabled) {
            // In PCM spatial mode, remote audio is rendered by Godot's AudioStreamPlayer3D.
            return
        }
        // LiveKit volume range is 0.0 to 10.0 (1.0 = normal)
        android.util.Log.d("GodotLiveKit", "setParticipantVolume: $identity -> $volume")
        scope.launch {
            val participant = room?.remoteParticipants?.values?.find { it.identity?.value == identity }
            // audioTrackPublications returns List<Pair<TrackPublication, Track?>>
            participant?.audioTrackPublications?.forEach { (_, track) ->
                (track as? io.livekit.android.room.track.RemoteAudioTrack)?.setVolume(volume)
            }
        }
    }

    @UsedByGodot
    fun setParticipantMuted(identity: String, muted: Boolean) {
        // Mute by setting volume to 0, unmute by setting to 1
        val volume = if (muted) 0.0 else 1.0
        android.util.Log.d("GodotLiveKit", "setParticipantMuted: $identity -> $muted (volume: $volume)")
        setParticipantVolume(identity, volume)
    }

    @UsedByGodot
    fun setMetadata(metadata: String) {
        scope.launch {
            room?.localParticipant?.updateMetadata(metadata)
        }
    }

    private suspend fun setupRoomListeners() {
        room?.let { r ->
            scope.launch {
                r.events.collect { event ->
                    when (event) {
                        is RoomEvent.ParticipantConnected -> emitSignal("participant_joined", event.participant.identity?.value ?: "")
                        is RoomEvent.ParticipantDisconnected -> {
                            val participantIdentity = event.participant.identity?.value ?: ""
                            removeRemoteAudioSinksForParticipant(participantIdentity)
                            emitSignal("participant_left", participantIdentity)
                        }
                        is RoomEvent.ParticipantMetadataChanged -> emitSignal("participant_metadata_changed", event.participant.identity?.value ?: "", event.participant.metadata ?: "")
                        is RoomEvent.TrackSubscribed -> {
                            val participantIdentity = event.participant.identity?.value ?: ""
                            val trackSid = event.track.sid ?: ""
                            emitSignal("track_subscribed", participantIdentity, trackSid)
                            val remoteAudioTrack = event.track as? RemoteAudioTrack
                            if (remoteAudioTrack != null) {
                                attachRemoteAudioSink(participantIdentity, remoteAudioTrack, trackSid)
                            }
                        }
                        is RoomEvent.TrackUnsubscribed -> {
                            val participantIdentity = event.participant.identity?.value ?: ""
                            val trackSid = event.track.sid ?: ""
                            removeRemoteAudioSink(trackSid)
                            emitSignal("track_unsubscribed", participantIdentity, trackSid)
                        }
                        is RoomEvent.DataReceived -> {
                            emitSignal("data_received", event.participant?.identity?.value ?: "", event.data, event.topic ?: "")
                        }
                        else -> {}
                    }
                }
            }
        }
    }

    override fun onMainPause() {
        scope.launch {
            room?.localParticipant?.setMicrophoneEnabled(false)
        }
        super.onMainPause()
    }

    override fun onMainResume() {
        scope.launch {
            // Only re-enable mic if user hasn't muted
            if (!isMuted) {
                room?.localParticipant?.setMicrophoneEnabled(true)
                android.util.Log.d("GodotLiveKit", "onMainResume: Re-enabling mic (not muted)")
            } else {
                android.util.Log.d("GodotLiveKit", "onMainResume: Keeping mic disabled (muted)")
            }
        }
        super.onMainResume()
    }

    override fun onMainDestroy() {
        // IMPORTANT: Don't launch coroutines during destruction - ART may already be shutting down
        // Safely disconnect by canceling scope first, then cleaning up room reference
        try {
            removeAllRemoteAudioSinks()
            // Cancel all pending coroutines first to prevent any callbacks
            scope.cancel()
            
            // Synchronously clean up room reference without launching new coroutines
            // The LiveKit SDK will handle cleanup when the activity is destroyed
            val currentRoom = room
            room = null
            
            // Try to disconnect if room is still valid, but don't wait for it
            // and don't emit signals since Godot may also be shutting down
            currentRoom?.let { r ->
                try {
                    // Use runBlocking with a short timeout to attempt graceful disconnect
                    // but don't crash if it fails
                    kotlinx.coroutines.runBlocking {
                        kotlinx.coroutines.withTimeoutOrNull(500) {
                            r.disconnect()
                        }
                    }
                } catch (e: Exception) {
                    android.util.Log.w("GodotLiveKit", "Room disconnect during destroy failed (expected): ${e.message}")
                } catch (t: Throwable) {
                    android.util.Log.w("GodotLiveKit", "Room disconnect during destroy threw: ${t.message}")
                }
            }
        } catch (e: Exception) {
            android.util.Log.w("GodotLiveKit", "Error during plugin destroy: ${e.message}")
        } catch (t: Throwable) {
            android.util.Log.w("GodotLiveKit", "Throwable during plugin destroy: ${t.message}")
        }
        
        super.onMainDestroy()
    }

    private fun attachRemoteAudioSink(participantIdentity: String, remoteAudioTrack: RemoteAudioTrack, trackSid: String) {
        if (!pcmSpatialAudioEnabled) {
            return
        }

        val effectiveSid = if (trackSid.isNotEmpty()) trackSid else "${participantIdentity}_${remoteAudioTrack.hashCode()}"
        removeRemoteAudioSink(effectiveSid)

        val sink = AudioTrackSink { audioData, bitsPerSample, _sampleRate, channelCount, numberOfFrames, _timestamp ->
            if (!pcmSpatialAudioEnabled) {
                return@AudioTrackSink
            }
            if (bitsPerSample != 16 || channelCount <= 0 || numberOfFrames <= 0) {
                return@AudioTrackSink
            }
            val frame = pcm16ToStereoFloat(audioData, channelCount, numberOfFrames)
            if (frame.isEmpty()) {
                return@AudioTrackSink
            }
            mainHandler.post {
                emitSignal("audio_frame", participantIdentity, frame)
            }
        }

        try {
            remoteAudioTrack.addSink(sink)
            // Prevent non-spatial Android mixer output (we render spatialized audio in Godot).
            remoteAudioTrack.setVolume(0.0)
            remoteAudioSinks[effectiveSid] = RemoteAudioSinkBinding(participantIdentity, effectiveSid, remoteAudioTrack, sink)
        } catch (e: Exception) {
            android.util.Log.e("GodotLiveKit", "Failed to attach audio sink for $effectiveSid: ${e.message}", e)
            pcmSpatialAudioEnabled = false
        } catch (t: Throwable) {
            android.util.Log.e("GodotLiveKit", "Failed to attach audio sink (throwable) for $effectiveSid: ${t.message}", t)
            pcmSpatialAudioEnabled = false
        }
    }

    private fun removeRemoteAudioSink(trackSid: String) {
        if (trackSid.isEmpty()) {
            return
        }
        val binding = remoteAudioSinks.remove(trackSid) ?: return
        try {
            binding.track.removeSink(binding.sink)
        } catch (_: Exception) {
        } catch (_: Throwable) {
        }
    }

    private fun removeRemoteAudioSinksForParticipant(participantIdentity: String) {
        if (participantIdentity.isEmpty()) {
            return
        }
        val trackSids = remoteAudioSinks.values
            .filter { it.participantIdentity == participantIdentity }
            .map { it.trackSid }
            .toList()
        trackSids.forEach { removeRemoteAudioSink(it) }
    }

    private fun removeAllRemoteAudioSinks() {
        val trackSids = remoteAudioSinks.keys.toList()
        trackSids.forEach { removeRemoteAudioSink(it) }
        remoteAudioSinks.clear()
    }

    private fun pcm16ToStereoFloat(audioData: ByteBuffer, channelCount: Int, numberOfFrames: Int): FloatArray {
        if (channelCount <= 0 || numberOfFrames <= 0) {
            return FloatArray(0)
        }

        val bytesPerSample = 2
        val requiredBytes = numberOfFrames * channelCount * bytesPerSample
        val source = audioData.duplicate().order(ByteOrder.LITTLE_ENDIAN)
        if (source.remaining() < requiredBytes) {
            return FloatArray(0)
        }

        val output = FloatArray(numberOfFrames * 2)
        var outputIndex = 0

        for (frameIndex in 0 until numberOfFrames) {
            val left = source.short.toInt() / 32768.0f
            val right = if (channelCount > 1) {
                source.short.toInt() / 32768.0f
            } else {
                left
            }

            // Skip channels beyond stereo if present.
            for (extraChannel in 2 until channelCount) {
                source.short
            }

            output[outputIndex++] = left.coerceIn(-1.0f, 1.0f)
            output[outputIndex++] = right.coerceIn(-1.0f, 1.0f)
        }

        return output
    }
}
