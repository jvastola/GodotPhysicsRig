package com.jvastola.physicshand.livekit;

import android.app.Activity;
import android.util.Log;

import androidx.annotation.NonNull;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.nio.ByteBuffer;
import java.util.HashSet;
import java.util.Set;

import io.livekit.android.LiveKit;
import io.livekit.android.events.RoomEvent;
import io.livekit.android.events.collect.FlowCollector;
import io.livekit.android.room.Room;
import io.livekit.android.room.participant.LocalParticipant;
import io.livekit.android.room.participant.Participant;
import io.livekit.android.room.participant.RemoteParticipant;
import io.livekit.android.room.track.LocalAudioTrack;
import io.livekit.android.room.track.Track;
import livekit.LivekitModels;

import kotlinx.coroutines.CoroutineScope;
import kotlinx.coroutines.Dispatchers;
import kotlinx.coroutines.Job;
import kotlinx.coroutines.SupervisorJob;

public class GodotLiveKit extends GodotPlugin {
    private static final String TAG = "GodotLiveKit";
    
    private Room room = null;
    private LocalAudioTrack localAudioTrack = null;
    private boolean isConnected = false;
    private final CoroutineScope coroutineScope;
    private Job connectionJob = null;
    
    public GodotLiveKit(Godot godot) {
        super(godot);
        coroutineScope = new CoroutineScope(Dispatchers.getMain().plus(new SupervisorJob()));
        Log.i(TAG, "GodotLiveKit plugin initialized");
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "GodotLiveKit";
    }

    @NonNull
    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        
        // Connection signals
        signals.add(new SignalInfo("room_connected"));
        signals.add(new SignalInfo("room_disconnected"));
        signals.add(new SignalInfo("connection_error", String.class));
        
        // Participant signals
        signals.add(new SignalInfo("participant_joined", String.class, String.class)); // identity, name
        signals.add(new SignalInfo("participant_left", String.class)); // identity
        signals.add(new SignalInfo("participant_metadata_changed", String.class, String.class)); // identity, metadata
        
        // Data signals
        signals.add(new SignalInfo("data_received", String.class, String.class)); // sender_identity, data
        
        // Track signals
        signals.add(new SignalInfo("track_subscribed", String.class, String.class)); // participant_identity, track_sid
        signals.add(new SignalInfo("track_unsubscribed", String.class, String.class)); // participant_identity, track_sid
        
        // Audio signals
        signals.add(new SignalInfo("audio_track_published"));
        signals.add(new SignalInfo("audio_track_unpublished"));
        
        return signals;
    }

    /**
     * Connect to a LiveKit room
     * @param url The LiveKit server URL (e.g., "wss://your-server.livekit.cloud")
     * @param token The access token for authentication
     */
    @UsedByGodot
    public void connect_to_room(String url, String token) {
        Activity activity = getActivity();
        if (activity == null) {
            Log.e(TAG, "Activity is null, cannot connect");
            emitSignal("connection_error", "Activity not available");
            return;
        }

        Log.i(TAG, "Connecting to room: " + url);
        
        // Run on main thread with coroutines
        activity.runOnUiThread(() -> {
            try {
                // Create room if needed
                if (room == null) {
                    room = LiveKit.create(activity.getApplicationContext());
                }
                
                // Connect using Kotlin coroutines bridge
                LiveKitCoroutineHelper.connect(room, url, token, new LiveKitCoroutineHelper.ConnectionCallback() {
                    @Override
                    public void onConnected() {
                        isConnected = true;
                        Log.i(TAG, "Connected to room successfully");
                        setupRoomEventListener();
                        emitSignal("room_connected");
                        
                        // Notify about existing participants
                        for (RemoteParticipant participant : room.getRemoteParticipants().values()) {
                            String identity = participant.getIdentity() != null ? 
                                participant.getIdentity().toString() : "unknown";
                            String name = participant.getName() != null ? 
                                participant.getName() : identity;
                            emitSignal("participant_joined", identity, name);
                        }
                    }

                    @Override
                    public void onError(String error) {
                        Log.e(TAG, "Connection error: " + error);
                        emitSignal("connection_error", error);
                    }
                });
                
            } catch (Exception e) {
                Log.e(TAG, "Failed to connect: " + e.getMessage(), e);
                emitSignal("connection_error", e.getMessage());
            }
        });
    }

    /**
     * Disconnect from the current room
     */
    @UsedByGodot
    public void disconnect() {
        Log.i(TAG, "Disconnecting from room");
        
        if (room != null) {
            Activity activity = getActivity();
            if (activity != null) {
                activity.runOnUiThread(() -> {
                    try {
                        // Unpublish audio track first
                        if (localAudioTrack != null) {
                            unpublish_audio_track();
                        }
                        
                        room.disconnect();
                        isConnected = false;
                        Log.i(TAG, "Disconnected from room");
                        emitSignal("room_disconnected");
                    } catch (Exception e) {
                        Log.e(TAG, "Error disconnecting: " + e.getMessage(), e);
                    }
                });
            }
        }
    }

    /**
     * Send data to all participants or a specific participant
     * @param data The string data to send
     * @param reliable Whether to send reliably (TCP-like) or unreliably (UDP-like)
     */
    @UsedByGodot
    public void send_data(String data, boolean reliable) {
        send_data_to(data, reliable, "");
    }

    /**
     * Send data to a specific participant
     * @param data The string data to send
     * @param reliable Whether to send reliably
     * @param destinationIdentity Target participant identity, or empty for broadcast
     */
    @UsedByGodot
    public void send_data_to(String data, boolean reliable, String destinationIdentity) {
        if (!isConnected || room == null) {
            Log.w(TAG, "Cannot send data: not connected");
            return;
        }

        Activity activity = getActivity();
        if (activity == null) return;

        activity.runOnUiThread(() -> {
            try {
                LocalParticipant localParticipant = room.getLocalParticipant();
                if (localParticipant == null) {
                    Log.e(TAG, "Local participant is null");
                    return;
                }

                byte[] bytes = data.getBytes();
                LivekitModels.DataPacket.Kind kind = reliable ? 
                    LivekitModels.DataPacket.Kind.RELIABLE : 
                    LivekitModels.DataPacket.Kind.LOSSY;

                if (destinationIdentity.isEmpty()) {
                    // Broadcast to all
                    LiveKitCoroutineHelper.publishData(localParticipant, bytes, kind, null, new LiveKitCoroutineHelper.SimpleCallback() {
                        @Override
                        public void onComplete() {
                            Log.d(TAG, "Data sent successfully (broadcast)");
                        }

                        @Override
                        public void onError(String error) {
                            Log.e(TAG, "Failed to send data: " + error);
                        }
                    });
                } else {
                    // Send to specific participant
                    LiveKitCoroutineHelper.publishData(localParticipant, bytes, kind, destinationIdentity, new LiveKitCoroutineHelper.SimpleCallback() {
                        @Override
                        public void onComplete() {
                            Log.d(TAG, "Data sent successfully to: " + destinationIdentity);
                        }

                        @Override
                        public void onError(String error) {
                            Log.e(TAG, "Failed to send data: " + error);
                        }
                    });
                }
            } catch (Exception e) {
                Log.e(TAG, "Error sending data: " + e.getMessage(), e);
            }
        });
    }

    /**
     * Publish the local microphone audio track
     */
    @UsedByGodot
    public void publish_audio_track() {
        if (!isConnected || room == null) {
            Log.w(TAG, "Cannot publish audio: not connected");
            return;
        }

        Activity activity = getActivity();
        if (activity == null) return;

        activity.runOnUiThread(() -> {
            try {
                LocalParticipant localParticipant = room.getLocalParticipant();
                if (localParticipant == null) {
                    Log.e(TAG, "Local participant is null");
                    return;
                }

                // Create and publish microphone track
                localAudioTrack = LocalAudioTrack.createTrack(activity.getApplicationContext(), null);
                
                LiveKitCoroutineHelper.publishAudioTrack(localParticipant, localAudioTrack, new LiveKitCoroutineHelper.SimpleCallback() {
                    @Override
                    public void onComplete() {
                        Log.i(TAG, "Audio track published");
                        emitSignal("audio_track_published");
                    }

                    @Override
                    public void onError(String error) {
                        Log.e(TAG, "Failed to publish audio track: " + error);
                    }
                });
                
            } catch (Exception e) {
                Log.e(TAG, "Error publishing audio: " + e.getMessage(), e);
            }
        });
    }

    /**
     * Unpublish the local audio track
     */
    @UsedByGodot
    public void unpublish_audio_track() {
        if (!isConnected || room == null || localAudioTrack == null) {
            Log.w(TAG, "Cannot unpublish audio: not connected or no track");
            return;
        }

        Activity activity = getActivity();
        if (activity == null) return;

        activity.runOnUiThread(() -> {
            try {
                LocalParticipant localParticipant = room.getLocalParticipant();
                if (localParticipant != null) {
                    localParticipant.unpublishTrack(localAudioTrack);
                }
                localAudioTrack.stop();
                localAudioTrack = null;
                Log.i(TAG, "Audio track unpublished");
                emitSignal("audio_track_unpublished");
            } catch (Exception e) {
                Log.e(TAG, "Error unpublishing audio: " + e.getMessage(), e);
            }
        });
    }

    /**
     * Set the local participant's metadata
     * @param metadata The metadata string (usually JSON)
     */
    @UsedByGodot
    public void set_metadata(String metadata) {
        if (!isConnected || room == null) {
            Log.w(TAG, "Cannot set metadata: not connected");
            return;
        }

        Activity activity = getActivity();
        if (activity == null) return;

        activity.runOnUiThread(() -> {
            try {
                LocalParticipant localParticipant = room.getLocalParticipant();
                if (localParticipant != null) {
                    LiveKitCoroutineHelper.setMetadata(localParticipant, metadata, new LiveKitCoroutineHelper.SimpleCallback() {
                        @Override
                        public void onComplete() {
                            Log.d(TAG, "Metadata updated");
                        }

                        @Override
                        public void onError(String error) {
                            Log.e(TAG, "Failed to set metadata: " + error);
                        }
                    });
                }
            } catch (Exception e) {
                Log.e(TAG, "Error setting metadata: " + e.getMessage(), e);
            }
        });
    }

    /**
     * Check if currently connected to a room
     */
    @UsedByGodot
    public boolean is_connected() {
        return isConnected && room != null;
    }

    /**
     * Get the local participant's identity
     */
    @UsedByGodot
    public String get_local_identity() {
        if (room != null && room.getLocalParticipant() != null) {
            Participant.Identity identity = room.getLocalParticipant().getIdentity();
            return identity != null ? identity.toString() : "";
        }
        return "";
    }

    /**
     * Get list of remote participant identities as comma-separated string
     */
    @UsedByGodot
    public String get_participant_identities() {
        if (room == null) return "";
        
        StringBuilder sb = new StringBuilder();
        boolean first = true;
        for (RemoteParticipant participant : room.getRemoteParticipants().values()) {
            if (!first) sb.append(",");
            Participant.Identity identity = participant.getIdentity();
            sb.append(identity != null ? identity.toString() : "unknown");
            first = false;
        }
        return sb.toString();
    }

    /**
     * Enable or disable the local audio track
     */
    @UsedByGodot
    public void set_audio_enabled(boolean enabled) {
        if (localAudioTrack != null) {
            localAudioTrack.setEnabled(enabled);
            Log.d(TAG, "Audio track enabled: " + enabled);
        }
    }

    private void setupRoomEventListener() {
        if (room == null) return;

        LiveKitCoroutineHelper.collectRoomEvents(room, new LiveKitCoroutineHelper.RoomEventCallback() {
            @Override
            public void onParticipantConnected(RemoteParticipant participant) {
                String identity = participant.getIdentity() != null ? 
                    participant.getIdentity().toString() : "unknown";
                String name = participant.getName() != null ? 
                    participant.getName() : identity;
                Log.i(TAG, "Participant joined: " + identity);
                emitSignal("participant_joined", identity, name);
            }

            @Override
            public void onParticipantDisconnected(RemoteParticipant participant) {
                String identity = participant.getIdentity() != null ? 
                    participant.getIdentity().toString() : "unknown";
                Log.i(TAG, "Participant left: " + identity);
                emitSignal("participant_left", identity);
            }

            @Override
            public void onDataReceived(byte[] data, RemoteParticipant participant) {
                String senderIdentity = "unknown";
                if (participant != null && participant.getIdentity() != null) {
                    senderIdentity = participant.getIdentity().toString();
                }
                String dataStr = new String(data);
                Log.d(TAG, "Data received from " + senderIdentity + ": " + dataStr);
                emitSignal("data_received", senderIdentity, dataStr);
            }

            @Override
            public void onParticipantMetadataChanged(Participant participant, String prevMetadata) {
                String identity = participant.getIdentity() != null ? 
                    participant.getIdentity().toString() : "unknown";
                String metadata = participant.getMetadata() != null ? 
                    participant.getMetadata() : "";
                Log.d(TAG, "Participant metadata changed: " + identity);
                emitSignal("participant_metadata_changed", identity, metadata);
            }

            @Override
            public void onTrackSubscribed(Track track, RemoteParticipant participant) {
                String identity = participant.getIdentity() != null ? 
                    participant.getIdentity().toString() : "unknown";
                String trackSid = track.getSid() != null ? track.getSid().toString() : "";
                Log.i(TAG, "Track subscribed: " + trackSid + " from " + identity);
                emitSignal("track_subscribed", identity, trackSid);
            }

            @Override
            public void onTrackUnsubscribed(Track track, RemoteParticipant participant) {
                String identity = participant.getIdentity() != null ? 
                    participant.getIdentity().toString() : "unknown";
                String trackSid = track.getSid() != null ? track.getSid().toString() : "";
                Log.i(TAG, "Track unsubscribed: " + trackSid + " from " + identity);
                emitSignal("track_unsubscribed", identity, trackSid);
            }

            @Override
            public void onDisconnected() {
                isConnected = false;
                Log.i(TAG, "Room disconnected");
                emitSignal("room_disconnected");
            }
        });
    }

    @Override
    public void onMainDestroy() {
        super.onMainDestroy();
        if (room != null) {
            try {
                room.disconnect();
                room.release();
            } catch (Exception e) {
                Log.e(TAG, "Error cleaning up room: " + e.getMessage());
            }
            room = null;
        }
        isConnected = false;
    }
}
