package com.jvastola.physicshand.livekit

import android.app.Activity
import android.os.Handler
import android.os.Looper
import io.livekit.android.*
import io.livekit.android.events.*
import io.livekit.android.room.*
import io.livekit.android.room.track.*
import io.livekit.android.room.participant.*
import kotlinx.coroutines.*
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.nio.ByteBuffer

class GodotLiveKitPlugin(godot: Godot) : GodotPlugin(godot) {

    companion object {
        const val PLUGIN_NAME = "GodotLiveKit"
    }

    private var room: Room? = null
    private var scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var isMuted: Boolean = false  // Track user's mute preference

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
        scope.launch {
            try {
                val currentActivity = activity
                if (currentActivity == null) {
                    emitSignal("error_occurred", "Activity is null")
                    return@launch
                }

                // LK 2.x: Create room then connect
                room = LiveKit.create(currentActivity)
                
                setupRoomListeners()
                
                room?.connect(
                    url,
                    token
                )
                
                // Only enable mic if not muted
                if (!isMuted) {
                    room?.localParticipant?.setMicrophoneEnabled(true)
                    android.util.Log.d("GodotLiveKit", "connectToRoom: Mic enabled (not muted) with HQ settings")
                } else {
                    android.util.Log.d("GodotLiveKit", "connectToRoom: Mic disabled (user muted)")
                }
                
                emitSignal("room_connected")
            } catch (e: Exception) {
                emitSignal("error_occurred", e.message ?: "Connection failed")
            }
        }
    }

    @UsedByGodot
    fun disconnectFromRoom() {
        scope.launch {
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
    fun sendData(data: ByteArray, topic: String) {
        scope.launch {
            room?.localParticipant?.publishData(
                data,
                DataPublishReliability.RELIABLE,
                topic
            )
        }
    }

    @UsedByGodot
    fun sendDataTo(data: ByteArray, identity: String, topic: String) {
         scope.launch {
            val participant = room?.remoteParticipants?.values?.find { it.identity?.value == identity }
            if (participant != null && participant.identity != null) {
                 room?.localParticipant?.publishData(
                    data,
                    DataPublishReliability.RELIABLE,
                    topic,
                    listOf(participant.identity!!)
                )
            }
        }
    }

    @UsedByGodot
    fun setAudioEnabled(enabled: Boolean) {
        isMuted = !enabled  // Remember user preference
        android.util.Log.d("GodotLiveKit", "setAudioEnabled: $enabled, isMuted: $isMuted")
        scope.launch {
            room?.localParticipant?.setMicrophoneEnabled(enabled)
        }
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
                        is RoomEvent.ParticipantDisconnected -> emitSignal("participant_left", event.participant.identity?.value ?: "")
                        is RoomEvent.ParticipantMetadataChanged -> emitSignal("participant_metadata_changed", event.participant.identity?.value ?: "", event.participant.metadata ?: "")
                        is RoomEvent.TrackSubscribed -> emitSignal("track_subscribed", event.participant.identity?.value ?: "", event.track.sid ?: "")
                        is RoomEvent.TrackUnsubscribed -> emitSignal("track_unsubscribed", event.participant.identity?.value ?: "", event.track.sid ?: "")
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
        disconnectFromRoom()
        scope.cancel()
        super.onMainDestroy()
    }
}
