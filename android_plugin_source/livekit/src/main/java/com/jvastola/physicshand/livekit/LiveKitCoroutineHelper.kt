package com.jvastola.physicshand.livekit

import android.util.Log
import io.livekit.android.room.Room
import io.livekit.android.room.participant.LocalParticipant
import io.livekit.android.room.participant.Participant
import io.livekit.android.room.participant.RemoteParticipant
import io.livekit.android.room.track.LocalAudioTrack
import io.livekit.android.room.track.Track
import io.livekit.android.events.RoomEvent
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collectLatest
import livekit.LivekitModels

/**
 * Helper class to bridge Kotlin coroutines with Java callbacks
 * This allows the Java GodotLiveKit class to call suspend functions
 */
object LiveKitCoroutineHelper {
    private const val TAG = "LiveKitCoroutineHelper"
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    interface ConnectionCallback {
        fun onConnected()
        fun onError(error: String)
    }

    interface SimpleCallback {
        fun onComplete()
        fun onError(error: String)
    }

    interface RoomEventCallback {
        fun onParticipantConnected(participant: RemoteParticipant)
        fun onParticipantDisconnected(participant: RemoteParticipant)
        fun onDataReceived(data: ByteArray, participant: RemoteParticipant?)
        fun onParticipantMetadataChanged(participant: Participant, prevMetadata: String?)
        fun onTrackSubscribed(track: Track, participant: RemoteParticipant)
        fun onTrackUnsubscribed(track: Track, participant: RemoteParticipant)
        fun onDisconnected()
    }

    @JvmStatic
    fun connect(room: Room, url: String, token: String, callback: ConnectionCallback) {
        scope.launch {
            try {
                Log.d(TAG, "Connecting to: $url")
                room.connect(url, token)
                Log.d(TAG, "Connected successfully")
                callback.onConnected()
            } catch (e: Exception) {
                Log.e(TAG, "Connection failed: ${e.message}", e)
                callback.onError(e.message ?: "Unknown connection error")
            }
        }
    }

    @JvmStatic
    fun publishData(
        localParticipant: LocalParticipant,
        data: ByteArray,
        kind: LivekitModels.DataPacket.Kind,
        destinationIdentity: String?,
        callback: SimpleCallback
    ) {
        scope.launch {
            try {
                val identities = if (destinationIdentity.isNullOrEmpty()) {
                    emptyList()
                } else {
                    listOf(Participant.Identity(destinationIdentity))
                }
                
                localParticipant.publishData(
                    data = data,
                    reliability = if (kind == LivekitModels.DataPacket.Kind.RELIABLE) {
                        io.livekit.android.room.types.DataPublishReliability.RELIABLE
                    } else {
                        io.livekit.android.room.types.DataPublishReliability.LOSSY
                    },
                    destinationIdentities = identities
                )
                callback.onComplete()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to publish data: ${e.message}", e)
                callback.onError(e.message ?: "Unknown error publishing data")
            }
        }
    }

    @JvmStatic
    fun publishAudioTrack(
        localParticipant: LocalParticipant,
        audioTrack: LocalAudioTrack,
        callback: SimpleCallback
    ) {
        scope.launch {
            try {
                localParticipant.publishAudioTrack(audioTrack)
                callback.onComplete()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to publish audio track: ${e.message}", e)
                callback.onError(e.message ?: "Unknown error publishing audio")
            }
        }
    }

    @JvmStatic
    fun setMetadata(
        localParticipant: LocalParticipant,
        metadata: String,
        callback: SimpleCallback
    ) {
        scope.launch {
            try {
                localParticipant.updateMetadata(metadata)
                callback.onComplete()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to set metadata: ${e.message}", e)
                callback.onError(e.message ?: "Unknown error setting metadata")
            }
        }
    }

    @JvmStatic
    fun collectRoomEvents(room: Room, callback: RoomEventCallback) {
        scope.launch {
            room.events.collect { event ->
                when (event) {
                    is RoomEvent.ParticipantConnected -> {
                        callback.onParticipantConnected(event.participant)
                    }
                    is RoomEvent.ParticipantDisconnected -> {
                        callback.onParticipantDisconnected(event.participant)
                    }
                    is RoomEvent.DataReceived -> {
                        callback.onDataReceived(
                            event.data,
                            event.participant as? RemoteParticipant
                        )
                    }
                    is RoomEvent.ParticipantMetadataChanged -> {
                        callback.onParticipantMetadataChanged(
                            event.participant,
                            event.prevMetadata
                        )
                    }
                    is RoomEvent.TrackSubscribed -> {
                        callback.onTrackSubscribed(
                            event.track,
                            event.participant
                        )
                    }
                    is RoomEvent.TrackUnsubscribed -> {
                        callback.onTrackUnsubscribed(
                            event.track,
                            event.participant
                        )
                    }
                    is RoomEvent.Disconnected -> {
                        callback.onDisconnected()
                    }
                    else -> {
                        // Log other events for debugging
                        Log.v(TAG, "Room event: ${event::class.simpleName}")
                    }
                }
            }
        }
    }

    @JvmStatic
    fun cleanup() {
        scope.cancel()
    }
}
