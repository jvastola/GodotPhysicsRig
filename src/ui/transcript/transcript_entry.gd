class_name TranscriptEntry
extends RefCounted

## Data class for a single transcript entry from voice-to-text transcription.
## Stores speaker identity, transcribed text, timestamp, and metadata.

## The LiveKit participant identity of the speaker
var speaker_identity: String = ""

## Display name of the speaker (if available from participant metadata)
var speaker_name: String = ""

## The transcribed text content
var text: String = ""

## Unix timestamp in milliseconds when the transcript was created
var timestamp: int = 0

## True if this transcript is from the local user
var is_local: bool = false

## True if this is a final transcript (not interim/partial)
var is_final: bool = true


## Format the timestamp as HH:MM:SS string
func format_time() -> String:
	var unix_seconds := timestamp / 1000
	var dt := Time.get_datetime_dict_from_unix_time(unix_seconds)
	return "%02d:%02d:%02d" % [dt.hour, dt.minute, dt.second]


## Get the display name, falling back to identity if name is empty
func get_display_name() -> String:
	if speaker_name.is_empty():
		return speaker_identity
	return speaker_name


## Convert to dictionary for serialization
func to_dict() -> Dictionary:
	return {
		"speaker_identity": speaker_identity,
		"speaker_name": speaker_name,
		"text": text,
		"timestamp": timestamp,
		"is_local": is_local,
		"is_final": is_final
	}


## Create a TranscriptEntry from a dictionary
static func from_dict(data: Dictionary) -> TranscriptEntry:
	var entry := TranscriptEntry.new()
	entry.speaker_identity = data.get("speaker_identity", "")
	entry.speaker_name = data.get("speaker_name", "")
	entry.text = data.get("text", "")
	entry.timestamp = data.get("timestamp", 0)
	entry.is_local = data.get("is_local", false)
	entry.is_final = data.get("is_final", true)
	return entry


## Create a TranscriptEntry from a JSON transcript message
static func from_transcript_message(data: Dictionary, local_identity: String = "") -> TranscriptEntry:
	var entry := TranscriptEntry.new()
	entry.speaker_identity = data.get("speaker_identity", "")
	entry.speaker_name = data.get("speaker_name", "")
	entry.text = data.get("text", "")
	entry.timestamp = data.get("timestamp", Time.get_unix_time_from_system() * 1000)
	entry.is_final = data.get("is_final", true)
	entry.is_local = (entry.speaker_identity == local_identity) if not local_identity.is_empty() else false
	return entry
