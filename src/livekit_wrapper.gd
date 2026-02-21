## LiveKit Platform Wrapper
## Automatically uses Rust GDExtension on Desktop, Android Plugin on Android
## Provides a unified API across all platforms
# class_name LiveKitWrapper removed to avoid autoload conflict
extends Node
const AppLogger = preload("res://src/systems/logger.gd")

func _log_debug(msg: String, extra: Variant = null) -> void:
	AppLogger.debug("LiveKit", msg, extra)

func _log_info(msg: String, extra: Variant = null) -> void:
	AppLogger.info("LiveKit", msg, extra)

func _log_warn(msg: String, extra: Variant = null) -> void:
	AppLogger.warn("LiveKit", msg, extra)

func _log_error(msg: String, extra: Variant = null) -> void:
	AppLogger.error("LiveKit", msg, extra)

func get_metrics() -> Dictionary:
	return _metrics.duplicate()

func _emit_metrics() -> void:
	metrics_updated.emit(_metrics.duplicate())

func _record_send_failure(reason: String) -> void:
	_metrics["send_failures"] += 1
	_metrics["last_send_failure"] = reason
	_emit_metrics()

# Signals - unified across platforms
signal room_connected()
signal room_disconnected()
signal connection_error(message: String)
signal participant_joined(identity: String, name: String)
signal participant_left(identity: String)
signal participant_metadata_changed(identity: String, metadata: String)
signal data_received(sender_identity: String, data: String)
signal track_subscribed(participant_identity: String, track_sid: String)
signal track_unsubscribed(participant_identity: String, track_sid: String)
signal audio_track_published()
signal audio_track_unpublished()
signal audio_frame_received(peer_id: String, frame: PackedVector2Array)
signal chat_message_received(sender: String, message: String, timestamp: int)
signal metrics_updated(metrics: Dictionary)

# Platform detection
enum Platform { DESKTOP, ANDROID }
var current_platform: Platform = Platform.DESKTOP

# Backend references
var _rust_manager: Node = null  # LiveKitManager from Rust GDExtension
var _android_plugin: Object = null  # GodotLiveKit Android plugin

# State
var _is_connected: bool = false
var _local_identity: String = ""
var _is_muted: bool = false  # Track mute state for desktop (Rust doesn't have enable_microphone)
var _current_room: String = ""
var _metrics := {
	"connect_attempts": 0,
	"connect_successes": 0,
	"connect_failures": 0,
	"last_connect_start_msec": 0,
	"last_connect_latency_ms": 0,
	"reconnect_attempts": 0,
	"send_failures": 0,
	"last_send_failure": "",
	"last_disconnect_msec": 0
}


func _ready() -> void:
	_detect_platform()
	_initialize_backend()


func _detect_platform() -> void:
	var os_name = OS.get_name()
	if os_name == "Android":
		current_platform = Platform.ANDROID
		_log_info("Platform: Android")
	else:
		current_platform = Platform.DESKTOP
		_log_info("Platform: Desktop (%s)" % os_name)


func _initialize_backend() -> void:
	if current_platform == Platform.ANDROID:
		_initialize_android()
	else:
		_initialize_desktop()


func _initialize_android() -> void:
	if Engine.has_singleton("GodotLiveKit"):
		_android_plugin = Engine.get_singleton("GodotLiveKit")
		_log_info("Android plugin loaded successfully")
		_connect_android_signals()
	else:
		push_error("[LiveKitWrapper] GodotLiveKit Android plugin not found! Make sure it's enabled in export settings.")


func _initialize_desktop() -> void:
	# Look for the Rust GDExtension LiveKitManager
	# It should be added to the scene tree or autoloaded
	if ClassDB.class_exists("LiveKitManager"):
		_rust_manager = ClassDB.instantiate("LiveKitManager")
		add_child(_rust_manager)
		_log_info("Rust LiveKitManager instantiated")
		_connect_rust_signals()
	else:
		push_error("[LiveKitWrapper] LiveKitManager class not found! Make sure the Rust GDExtension is loaded.")


func _connect_android_signals() -> void:
	if _android_plugin == null:
		return
	
	_android_plugin.connect("room_connected", _on_room_connected)
	_android_plugin.connect("room_disconnected", _on_room_disconnected)
	_android_plugin.connect("error_occurred", _on_connection_error)
	_android_plugin.connect("participant_joined", _on_participant_joined_android)  # Android sends only 1 arg
	_android_plugin.connect("participant_left", _on_participant_left)
	_android_plugin.connect("participant_metadata_changed", _on_participant_metadata_changed)
	_android_plugin.connect("data_received", _on_data_received)
	_android_plugin.connect("track_subscribed", _on_track_subscribed)
	_android_plugin.connect("track_unsubscribed", _on_track_unsubscribed)
	_android_plugin.connect("audio_track_published", _on_audio_track_published)
	_android_plugin.connect("audio_track_unpublished", _on_audio_track_unpublished)


func _connect_rust_signals() -> void:
	if _rust_manager == null:
		return
	
	_rust_manager.connect("room_connected", _on_room_connected)
	_rust_manager.connect("room_disconnected", _on_room_disconnected)
	_rust_manager.connect("error_occurred", _on_connection_error)
	_rust_manager.connect("participant_joined", _on_participant_joined_rust)
	_rust_manager.connect("participant_left", _on_participant_left)
	_rust_manager.connect("participant_name_changed", _on_participant_name_changed_rust)
	_rust_manager.connect("on_audio_frame", _on_audio_frame)
	_rust_manager.connect("chat_message_received", _on_chat_message)


# ============ PUBLIC API ============

## Connect to a LiveKit room
## @param url: The LiveKit server URL (e.g., "wss://your-server.livekit.cloud")
## @param token: The access token for authentication
func connect_to_room(url: String, token: String) -> void:
	_log_info("Connecting to room", url)
	_current_room = url
	_metrics["connect_attempts"] += 1
	_metrics["last_connect_start_msec"] = Time.get_ticks_msec()
	_emit_metrics()
	
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			# Android plugin uses camelCase (Kotlin @UsedByGodot convention)
			_android_plugin.connectToRoom(url, token)
		else:
			push_error("[LiveKitWrapper] Cannot connect: Android plugin not initialized")
	else:
		if _rust_manager:
			# Rust GDExtension uses snake_case (Godot convention)
			_rust_manager.connect_to_room(url, token)
		else:
			push_error("[LiveKitWrapper] Cannot connect: Rust manager not initialized")


## Disconnect from the current room
func disconnect_from_room() -> void:
	_log_info("Disconnecting from room")
	
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			# Android plugin uses camelCase
			_android_plugin.disconnectFromRoom()
	else:
		if _rust_manager:
			_rust_manager.disconnect_from_room()

	# Force local cleanup regardless of signal delivery
	if _is_connected:
		_is_connected = false
		_current_room = ""
		_metrics["last_disconnect_msec"] = Time.get_ticks_msec()
		_emit_metrics()
		_log_info("Room disconnected (local cleanup)")
		room_disconnected.emit()


## Send data to all participants
## @param data: The string data to send
## @param reliable: Whether to send reliably (default true)
func send_data(data: String, _reliable: bool = true) -> void:
	var reliable := _reliable
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			var bytes = data.to_utf8_buffer()
			_send_bytes_android(bytes, "", reliable)
		else:
			_record_send_failure("android_plugin_missing")
	else:
		if _rust_manager:
			_send_data_rust(data, reliable)
		else:
			_record_send_failure("rust_manager_missing")


## Send data to a specific participant
## @param data: The string data to send
## @param identity: Target participant identity
## @param reliable: Whether to send reliably
func send_data_to(data: String, identity: String, _reliable: bool = true) -> void:
	var reliable := _reliable
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			var bytes = data.to_utf8_buffer()
			_send_bytes_android(bytes, "", reliable, identity)
		else:
			_record_send_failure("android_plugin_missing")
	else:
		if _rust_manager:
			_send_data_rust(data, reliable, identity)
		else:
			_record_send_failure("rust_manager_missing")


# Internal: route data send to Android plugin with best-effort reliability handling.
func _send_bytes_android(bytes: PackedByteArray, topic: String, reliable: bool, identity: String = "") -> void:
	if not _android_plugin:
		return
	var wants_target := identity != ""
	if wants_target:
		if reliable and _android_plugin.has_method("sendDataToReliable"):
			_android_plugin.call("sendDataToReliable", bytes, identity, topic)
			return
		if not reliable and _android_plugin.has_method("sendDataToUnreliable"):
			_android_plugin.call("sendDataToUnreliable", bytes, identity, topic)
			return
		# Fallback to existing API
		_android_plugin.sendDataTo(bytes, identity, topic)
		return
	# Broadcast path
	if reliable and _android_plugin.has_method("sendDataReliable"):
		_android_plugin.call("sendDataReliable", bytes, topic)
		return
	if not reliable and _android_plugin.has_method("sendDataUnreliable"):
		_android_plugin.call("sendDataUnreliable", bytes, topic)
		return
	_android_plugin.sendData(bytes, topic)


# Internal: route data send to Rust backend with best-effort reliability handling.
func _send_data_rust(data: String, reliable: bool, identity: String = "") -> void:
	if not _rust_manager:
		return
	var wants_target := identity != ""
	if wants_target and _rust_manager.has_method("send_data_to"):
		_rust_manager.call("send_data_to", data, identity, reliable)
		return
	if reliable:
		if _rust_manager.has_method("send_reliable_data"):
			_rust_manager.call("send_reliable_data", data)
			return
	else:
		if _rust_manager.has_method("send_unreliable_data"):
			_rust_manager.call("send_unreliable_data", data)
			return
	# Fallback to generic data/chat message path
	if _rust_manager.has_method("send_data"):
		_rust_manager.call("send_data", data, reliable)
		return
	if _rust_manager.has_method("send_chat_message"):
		_rust_manager.call("send_chat_message", data)


## Publish the local microphone audio track
func publish_audio_track() -> void:
	_log_info("Publishing audio track")
	
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			# Android plugin auto-enables mic on connect
			_android_plugin.setAudioEnabled(true)
	else:
		# Desktop: The Rust client auto-publishes track on connect
		# We just need to ensure we're not muted
		_is_muted = false
		_log_debug("Desktop: Audio track publishing (unmuted)")


## Unpublish the local audio track
func unpublish_audio_track() -> void:
	_log_info("Unpublishing audio track")
	
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			_android_plugin.setAudioEnabled(false)
	else:
		# Desktop: Set muted flag, push_mic_audio will respect this
		_is_muted = true
		_log_debug("Desktop: Audio track unpublished (muted)")


## Set the local participant's metadata
## @param metadata: The metadata string (usually JSON)
func set_metadata(metadata: String) -> void:
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			_android_plugin.setMetadata(metadata)
	else:
		if _rust_manager and _rust_manager.has_method("update_username"):
			# Rust uses username as metadata
			var parsed = JSON.parse_string(metadata)
			if parsed and parsed.has("username"):
				_rust_manager.update_username(parsed.username)


## Check if currently connected to a room
func is_room_connected() -> bool:
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			return _android_plugin.isRoomConnected()
	else:
		if _rust_manager and _rust_manager.has_method("is_room_connected"):
			return _rust_manager.is_room_connected()
	return _is_connected


## Get the local participant's identity
func get_local_identity() -> String:
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			return _android_plugin.get_local_identity()
	else:
		if _rust_manager and _rust_manager.has_method("get_local_identity"):
			return _rust_manager.get_local_identity()
	return _local_identity


## Get list of remote participant identities
func get_participant_identities() -> PackedStringArray:
	var result: PackedStringArray = []
	
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			var csv = _android_plugin.getParticipantIdentities()  # camelCase for Android plugin
			if csv != "":
				result = PackedStringArray(csv.split(","))
	
	return result


## Enable or disable the local audio track
func set_audio_enabled(enabled: bool) -> void:
	_log_debug("set_audio_enabled", enabled)
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			_android_plugin.setAudioEnabled(enabled)
			_log_debug("Called Android plugin setAudioEnabled", enabled)
	else:
		# Desktop: Track mute state, push_mic_audio will respect this
		_is_muted = !enabled
		_log_debug("Desktop: _is_muted set", _is_muted)


## Push microphone audio buffer (Desktop/Rust only)
func push_mic_audio(buffer: PackedVector2Array) -> void:
	# Skip if muted on desktop
	if _is_muted:
		return
	
	if current_platform == Platform.DESKTOP and _rust_manager and _rust_manager.has_method("push_mic_audio"):
		_rust_manager.push_mic_audio(buffer)


## Set microphone sample rate (Desktop/Rust only)
func set_mic_sample_rate(rate: int) -> void:
	if current_platform == Platform.DESKTOP and _rust_manager and _rust_manager.has_method("set_mic_sample_rate"):
		_rust_manager.set_mic_sample_rate(rate)


## Get current room name
func get_current_room() -> String:
	return _current_room


## Set volume for a specific remote participant (Android only)
## @param identity: Participant identity
## @param volume: Volume level (0.0 = muted, 1.0 = normal, up to 10.0 for boost)
func set_participant_volume(identity: String, volume: float) -> void:
	_log_debug("set_participant_volume", [identity, volume])
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			_android_plugin.setParticipantVolume(identity, volume)


## Mute/unmute a specific remote participant (Android only)
## @param identity: Participant identity
## @param muted: Whether to mute the participant
func set_participant_muted(identity: String, muted: bool) -> void:
	_log_debug("set_participant_muted", [identity, muted])
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			_android_plugin.setParticipantMuted(identity, muted)


# ============ SIGNAL HANDLERS ============

func _on_room_connected() -> void:
	_is_connected = true
	if _metrics["last_connect_start_msec"] > 0:
		_metrics["last_connect_latency_ms"] = Time.get_ticks_msec() - int(_metrics["last_connect_start_msec"])
	_metrics["connect_successes"] += 1
	_metrics["reconnect_attempts"] = 0
	_emit_metrics()
	_log_info("Room connected")
	room_connected.emit()


func _on_room_disconnected() -> void:
	if not _is_connected:
		return  # Already cleaned up (e.g. from disconnect_from_room)
	_is_connected = false
	_current_room = ""
	_metrics["last_disconnect_msec"] = Time.get_ticks_msec()
	_emit_metrics()
	_log_info("Room disconnected")
	room_disconnected.emit()


func _on_connection_error(message: String) -> void:
	_is_connected = false
	_metrics["connect_failures"] += 1
	_metrics["last_disconnect_msec"] = Time.get_ticks_msec()
	_emit_metrics()
	_log_error("Connection error", message)
	connection_error.emit(message)


func _on_participant_joined(identity: String, participant_name: String) -> void:
	_log_info("Participant joined", [identity, participant_name])
	participant_joined.emit(identity, participant_name)


func _on_participant_joined_android(identity: String) -> void:
	# Android plugin only sends identity, use it as name too
	_log_info("Participant joined (Android)", identity)
	participant_joined.emit(identity, identity)


func _on_participant_joined_rust(identity: String) -> void:
	# Rust only sends identity, use it as name too
	_log_info("Participant joined (Rust)", identity)
	participant_joined.emit(identity, identity)


func _on_participant_left(identity: String) -> void:
	_log_info("Participant left", identity)
	participant_left.emit(identity)


func _on_participant_metadata_changed(identity: String, metadata: String) -> void:
	_log_debug("Participant metadata changed", identity)
	participant_metadata_changed.emit(identity, metadata)


func _on_participant_name_changed_rust(identity: String, username: String) -> void:
	# Map Rust's name change to metadata change
	var metadata = JSON.stringify({"username": username})
	participant_metadata_changed.emit(identity, metadata)


func _on_data_received(sender_identity: String, data, topic: String = "") -> void:
	# Handle both String and PackedByteArray data from different platforms
	var data_str: String
	if data is PackedByteArray:
		data_str = (data as PackedByteArray).get_string_from_utf8()
	elif data is String:
		data_str = data
	else:
		data_str = str(data)
	_log_debug("Data received", [sender_identity, data_str.left(100), topic])
	data_received.emit(sender_identity, data_str)


func _on_track_subscribed(participant_identity: String, track_sid: String) -> void:
	_log_debug("Track subscribed", [track_sid, participant_identity])
	track_subscribed.emit(participant_identity, track_sid)


func _on_track_unsubscribed(participant_identity: String, track_sid: String) -> void:
	_log_debug("Track unsubscribed", [track_sid, participant_identity])
	track_unsubscribed.emit(participant_identity, track_sid)


func _on_audio_track_published() -> void:
	_log_debug("Audio track published")
	audio_track_published.emit()


func _on_audio_track_unpublished() -> void:
	_log_debug("Audio track unpublished")
	audio_track_unpublished.emit()


func _on_audio_frame(peer_id: String, frame: PackedVector2Array) -> void:
	audio_frame_received.emit(peer_id, frame)


func _on_chat_message(sender: String, message: String, timestamp: int) -> void:
	# Also emit as data_received for compatibility
	data_received.emit(sender, message)
	chat_message_received.emit(sender, message, timestamp)

func _exit_tree() -> void:
	# During app shutdown, avoid calling Android plugin methods which can cause
	# SIGSEGV in art::ArtMethod::Invoke when ART is already shutting down
	if _is_connected:
		_is_connected = false
		_current_room = ""
		# Only try to disconnect on desktop - Android plugin handles its own cleanup in onMainDestroy
		if current_platform == Platform.DESKTOP:
			if _rust_manager and is_instance_valid(_rust_manager):
				_rust_manager.disconnect_from_room()
		# Don't call Android plugin methods during tree exit - the plugin's onMainDestroy handles cleanup
		# Calling it here can cause crashes during app shutdown
