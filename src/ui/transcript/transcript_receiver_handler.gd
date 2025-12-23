class_name TranscriptReceiverHandler
extends Node

## Receives transcript messages from the LiveKit Agent via data channel.
## Parses incoming JSON messages and creates TranscriptEntry objects.

## Emitted when a transcript is received and parsed
signal transcript_received(entry: TranscriptEntry)

## Reference to the WorldTranscriptStore (optional, can be connected externally)
@export var transcript_store: WorldTranscriptStore

## The local user's LiveKit identity (for marking local entries)
var local_identity: String = ""

## Reference to the LiveKit wrapper
var _livekit: Node = null


func _ready() -> void:
	_connect_to_livekit()


func _connect_to_livekit() -> void:
	# Try to find LiveKitWrapper singleton
	_livekit = get_node_or_null("/root/LiveKitWrapper")
	if _livekit:
		if _livekit.has_signal("data_received"):
			_livekit.data_received.connect(_on_data_received)
		if _livekit.has_signal("room_connected"):
			_livekit.room_connected.connect(_on_room_connected)
		# Get identity if already connected
		if _livekit.has_method("get_local_identity"):
			var identity = _livekit.get_local_identity()
			if identity and not identity.is_empty():
				local_identity = identity
		print("TranscriptReceiverHandler: Connected to LiveKitWrapper")
	else:
		push_warning("TranscriptReceiverHandler: LiveKitWrapper not found, will retry on room join")


## Called when room connects to update local identity
func _on_room_connected() -> void:
	if _livekit and _livekit.has_method("get_local_identity"):
		local_identity = _livekit.get_local_identity()
		print("TranscriptReceiverHandler: Local identity set to: ", local_identity)


## Set the local user identity (call when joining a room)
func set_local_identity(identity: String) -> void:
	local_identity = identity


## Manually connect to a LiveKit wrapper node
func connect_to_livekit(livekit_node: Node) -> void:
	if _livekit and _livekit.has_signal("data_received"):
		if _livekit.data_received.is_connected(_on_data_received):
			_livekit.data_received.disconnect(_on_data_received)
	
	_livekit = livekit_node
	if _livekit and _livekit.has_signal("data_received"):
		_livekit.data_received.connect(_on_data_received)


## Handle incoming data from LiveKit data channel
func _on_data_received(sender_identity: String, data) -> void:
	# Handle both String and PackedByteArray data
	var data_str: String
	if data is PackedByteArray:
		data_str = data.get_string_from_utf8()
	elif data is String:
		data_str = data
	else:
		return
	
	# Try to parse as JSON
	var parsed = JSON.parse_string(data_str)
	if not parsed is Dictionary:
		return
	
	# Check if this is a transcript message
	var msg_type: String = parsed.get("type", "")
	if msg_type != "transcript":
		return
	
	print("TranscriptReceiverHandler: Received transcript from ", sender_identity)
	
	# Create transcript entry
	var entry := _parse_transcript_message(parsed)
	if entry:
		print("TranscriptReceiverHandler: Created entry - ", entry.speaker_identity, ": ", entry.text.left(50))
		# Add to store if connected
		if transcript_store:
			transcript_store.add_entry(entry)
		
		# Emit signal for other listeners
		transcript_received.emit(entry)


## Parse a transcript message dictionary into a TranscriptEntry
func _parse_transcript_message(data: Dictionary) -> TranscriptEntry:
	var entry := TranscriptEntry.new()
	
	# Required fields
	entry.speaker_identity = data.get("speaker_identity", "")
	entry.text = data.get("text", "")
	
	if entry.speaker_identity.is_empty() or entry.text.is_empty():
		push_warning("TranscriptReceiverHandler: Invalid transcript message - missing required fields")
		return null
	
	# Optional fields
	entry.speaker_name = data.get("speaker_name", "")
	entry.timestamp = data.get("timestamp", int(Time.get_unix_time_from_system() * 1000))
	entry.is_final = data.get("is_final", true)
	
	# Determine if local user
	entry.is_local = (entry.speaker_identity == local_identity) if not local_identity.is_empty() else false
	
	return entry


## Create a test transcript entry (for debugging)
func create_test_entry(speaker: String, text: String, is_local_user: bool = false) -> TranscriptEntry:
	var entry := TranscriptEntry.new()
	entry.speaker_identity = speaker
	entry.speaker_name = speaker
	entry.text = text
	entry.timestamp = int(Time.get_unix_time_from_system() * 1000)
	entry.is_local = is_local_user
	entry.is_final = true
	
	if transcript_store:
		transcript_store.add_entry(entry)
	
	transcript_received.emit(entry)
	return entry
