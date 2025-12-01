package com.jvastola.physicshand.livekit

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.core.content.edit
import io.livekit.android.*
import io.livekit.android.events.*
import io.livekit.android.room.*
import io.livekit.android.room.track.*
import io.livekit.android.room.participant.*
import io.livekit.android.util.flow
import kotlinx.coroutines.*
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import org.godotengine.godot.Dictionary
import org.godotengine.godot.type.GodotArray
import org.godotengine.godot.type.GodotString
import java.nio.ByteBuffer
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

class GodotLiveKitPlugin : GodotPlugin() {

    companion object {
        const val PLUGIN_NAME = "GodotLiveKit"
    }

    private var room: Room? = null
    private var scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var audioFrameHandler = Handler(Looper.getMainLooper())
    private var micTrack: LocalAudioTrack? = null
    private var remoteAudioListeners = mutableMapOf<String, (FloatArray) -> Unit>()
    private var prefs = mutableMapOf<String, Any?>()

    override fun getPluginName(): String = PLUGIN_NAME

    override fun getPluginSignals(): MutableList<String> {
        return mutableListOf(
            "room_connected",
            "room_disconnected",
            "participant_joined",
            "participant_left",
            "data_received",
            "audio_frame"
        )
    }

    @UsedByGodot
    fun connectToRoom(url: GodotString, token: GodotString) {
        scope.launch {
            try {
                room = Room.connect(
                    getActivity(),
                    url.toPlatformString(),
                    token.toPlatformString(),
                    ConnectOptions()
                )
                setupRoomListeners()
                // Auto enable mic
                room?.localParticipant?.setMicrophoneEnabled(true)
                emitSignal("room_connected")
            } catch (e: Exception) {
                emitSignal("error_occurred", e.message ?: "Connection failed")
            }
        }
    }

    @UsedByGodot
    fun disconnectFromRoom() {
        room?.disconnect()
        room = null
        micTrack?.release()
        micTrack = null
        emitSignal("room_disconnected")
    }

    @UsedByGodot
    fun isRoomConnected(): Boolean = room?.connectionState == ConnectionState.CONNECTED

    @UsedByGodot
    fun getParticipantIdentities(): GodotArray<String> {
        val identities = GodotArray<String>()
        room?.remoteParticipants?.keys?.forEach { identities.add(it) }
        return identities
    }

    @UsedByGodot
    fun sendData(data: ByteArray, topic: GodotString) {
        scope.launch {
            room?.localParticipant?.publishData(
                ByteBuffer.wrap(data),
                DataPublishOptions(topic = topic.toPlatformString(), reliable = true)
            )
        }
    }

    private suspend fun setupRoomListeners() {
        room?.let { r ->
            r.events.collect { event ->
                when (event) {
                    is ParticipantConnected -> emitSignal("participant_joined", event.participant.identity)
                    is ParticipantDisconnected -> emitSignal("participant_left", event.participant.identity)
                    is DataReceived -> emitSignal("data_received", event.participant.identity, event.data.array(), event.topic)
                    is LocalParticipantCreated -> { /* mic already enabled */ }
                }
            }
        }
    }

    // Audio: Remote tracks
    private fun onRemoteAudioSamples(participantId: String, samples: FloatArray) {
        emitSignal("audio_frame", participantId, samples.toGodotArray())
    }

    // Setup per remote audio track listener (call when participant joined)
    private fun setupRemoteAudio(participant: RemoteParticipant) {
        participant.audioTracks.values.forEach { track ->
            (track as? RemoteAudioTrack)?.setSamplesReadyListener { buffer ->
                val samples = FloatArray(buffer.remaining())
                buffer.get(samples)
                audioFrameHandler.post { onRemoteAudioSamples(participant.identity, samples) }
            }
        }
    }

    private fun FloatArray.toGodotArray(): GodotArray<Float> {
        val arr = GodotArray<Float>()
        this.forEach { arr.add(it) }
        return arr
    }

    override fun onMainPauseActivity() {
        room?.localParticipant?.setMicrophoneEnabled(false)
        super.onMainPauseActivity()
    }

    override fun onMainResumeActivity() {
        room?.localParticipant?.setMicrophoneEnabled(true)
        super.onMainResumeActivity()
    }

    override fun onMainDestroyActivity() {
        disconnectFromRoom()
        scope.cancel()
        super.onMainDestroyActivity()
    }
}
