## LiveKit Platform Wrapper
## Automatically uses Rust GDExtension on Desktop, Android Plugin on Android
## Provides a unified API across all platforms
class_name LiveKitWrapper
extends Node

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

# Platform detection
enum Platform { DESKTOP, ANDROID }
var current_platform: Platform = Platform.DESKTOP

# Backend references
var _rust_manager: Node = null  # LiveKitManager from Rust GDExtension
var _android_plugin: Object = null  # GodotLiveKit Android plugin

# State
var _is_connected: bool = false
var _local_identity: String = ""


func _ready() -> void:
	_detect_platform()
	_initialize_backend()


func _detect_platform() -> void:
	var os_name = OS.get_name()
	if os_name == "Android":
		current_platform = Platform.ANDROID
		print("[LiveKitWrapper] Platform: Android")
	else:
		current_platform = Platform.DESKTOP
		print("[LiveKitWrapper] Platform: Desktop (%s)" % os_name)


func _initialize_backend() -> void:
	if current_platform == Platform.ANDROID:
		_initialize_android()
	else:
		_initialize_desktop()


func _initialize_android() -> void:
	if Engine.has_singleton("GodotLiveKit"):
		_android_plugin = Engine.get_singleton("GodotLiveKit")
		print("[LiveKitWrapper] Android plugin loaded successfully")
		_connect_android_signals()
	else:
		push_error("[LiveKitWrapper] GodotLiveKit Android plugin not found! Make sure it's enabled in export settings.")


func _initialize_desktop() -> void:
	# Look for the Rust GDExtension LiveKitManager
	# It should be added to the scene tree or autoloaded
	if ClassDB.class_exists("LiveKitManager"):
		_rust_manager = ClassDB.instantiate("LiveKitManager")
		add_child(_rust_manager)
		print("[LiveKitWrapper] Rust LiveKitManager instantiated")
		_connect_rust_signals()
	else:
		push_error("[LiveKitWrapper] LiveKitManager class not found! Make sure the Rust GDExtension is loaded.")


func _connect_android_signals() -> void:
	if _android_plugin == null:
		return
	
	_android_plugin.connect("room_connected", _on_room_connected)
	_android_plugin.connect("room_disconnected", _on_room_disconnected)
	_android_plugin.connect("connection_error", _on_connection_error)
	_android_plugin.connect("participant_joined", _on_participant_joined)
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
	print("[LiveKitWrapper] Connecting to room: %s" % url)
	
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			_android_plugin.connect_to_room(url, token)
	else:
		if _rust_manager:
			_rust_manager.connect_to_room(url, token)


## Disconnect from the current room
func disconnect_from_room() -> void:
	print("[LiveKitWrapper] Disconnecting from room")
	
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			_android_plugin.disconnect()
	else:
		if _rust_manager:
			_rust_manager.disconnect()


## Send data to all participants
## @param data: The string data to send
## @param reliable: Whether to send reliably (default true)
func send_data(data: String, reliable: bool = true) -> void:
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			_android_plugin.send_data(data, reliable)
	else:
		if _rust_manager:
			_rust_manager.send_chat_message(data)  # Rust uses chat message API


## Send data to a specific participant
## @param data: The string data to send
## @param identity: Target participant identity
## @param reliable: Whether to send reliably
func send_data_to(data: String, identity: String, reliable: bool = true) -> void:
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			_android_plugin.send_data_to(data, reliable, identity)
	else:
		if _rust_manager:
			# Rust backend might not support targeted sending directly
			# Fall back to broadcast
			_rust_manager.send_chat_message(data)


## Publish the local microphone audio track
func publish_audio_track() -> void:
	print("[LiveKitWrapper] Publishing audio track")
	
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			_android_plugin.publish_audio_track()
	else:
		if _rust_manager:
			_rust_manager.enable_microphone(true)


## Unpublish the local audio track
func unpublish_audio_track() -> void:
	print("[LiveKitWrapper] Unpublishing audio track")
	
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			_android_plugin.unpublish_audio_track()
	else:
		if _rust_manager:
			_rust_manager.enable_microphone(false)


## Set the local participant's metadata
## @param metadata: The metadata string (usually JSON)
func set_metadata(metadata: String) -> void:
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			_android_plugin.set_metadata(metadata)
	else:
		if _rust_manager and _rust_manager.has_method("set_username"):
			# Rust uses username as metadata
			var parsed = JSON.parse_string(metadata)
			if parsed and parsed.has("username"):
				_rust_manager.set_username(parsed.username)


## Check if currently connected to a room
func is_connected() -> bool:
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			return _android_plugin.is_connected()
	else:
		if _rust_manager and _rust_manager.has_method("is_connected"):
			return _rust_manager.is_connected()
	return _is_connected


## Get the local participant's identity
func get_local_identity() -> String:
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			return _android_plugin.get_local_identity()
	return _local_identity


## Get list of remote participant identities
func get_participant_identities() -> PackedStringArray:
	var result: PackedStringArray = []
	
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			var csv = _android_plugin.get_participant_identities()
			if csv != "":
				result = PackedStringArray(csv.split(","))
	
	return result


## Enable or disable the local audio track
func set_audio_enabled(enabled: bool) -> void:
	if current_platform == Platform.ANDROID:
		if _android_plugin:
			_android_plugin.set_audio_enabled(enabled)
	else:
		if _rust_manager:
			_rust_manager.enable_microphone(enabled)


# ============ SIGNAL HANDLERS ============

func _on_room_connected() -> void:
	_is_connected = true
	print("[LiveKitWrapper] Room connected")
	room_connected.emit()


func _on_room_disconnected() -> void:
	_is_connected = false
	print("[LiveKitWrapper] Room disconnected")
	room_disconnected.emit()


func _on_connection_error(message: String) -> void:
	_is_connected = false
	print("[LiveKitWrapper] Connection error: %s" % message)
	connection_error.emit(message)


func _on_participant_joined(identity: String, name: String) -> void:
	print("[LiveKitWrapper] Participant joined: %s (%s)" % [identity, name])
	participant_joined.emit(identity, name)


func _on_participant_joined_rust(identity: String) -> void:
	# Rust only sends identity, use it as name too
	print("[LiveKitWrapper] Participant joined: %s" % identity)
	participant_joined.emit(identity, identity)


func _on_participant_left(identity: String) -> void:
	print("[LiveKitWrapper] Participant left: %s" % identity)
	participant_left.emit(identity)


func _on_participant_metadata_changed(identity: String, metadata: String) -> void:
	print("[LiveKitWrapper] Participant metadata changed: %s" % identity)
	participant_metadata_changed.emit(identity, metadata)


func _on_participant_name_changed_rust(identity: String, username: String) -> void:
	# Map Rust's name change to metadata change
	var metadata = JSON.stringify({"username": username})
	participant_metadata_changed.emit(identity, metadata)


func _on_data_received(sender_identity: String, data: String) -> void:
	print("[LiveKitWrapper] Data received from %s: %s" % [sender_identity, data])
	data_received.emit(sender_identity, data)


func _on_track_subscribed(participant_identity: String, track_sid: String) -> void:
	print("[LiveKitWrapper] Track subscribed: %s from %s" % [track_sid, participant_identity])
	track_subscribed.emit(participant_identity, track_sid)


func _on_track_unsubscribed(participant_identity: String, track_sid: String) -> void:
	print("[LiveKitWrapper] Track unsubscribed: %s from %s" % [track_sid, participant_identity])
	track_unsubscribed.emit(participant_identity, track_sid)


func _on_audio_track_published() -> void:
	print("[LiveKitWrapper] Audio track published")
	audio_track_published.emit()


func _on_audio_track_unpublished() -> void:
	print("[LiveKitWrapper] Audio track unpublished")
	audio_track_unpublished.emit()


func _on_audio_frame(peer_id: String, frame: PackedVector2Array) -> void:
	audio_frame_received.emit(peer_id, frame)


func _on_chat_message(sender: String, message: String, timestamp: int) -> void:
	# Also emit as data_received for compatibility
	data_received.emit(sender, message)
	chat_message_received.emit(sender, message, timestamp)


func _exit_tree() -> void:
	if _is_connected:
		disconnect_from_room()
