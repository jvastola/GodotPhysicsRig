class_name WorldTranscriptStore
extends Node

## Stores and manages transcript entries from voice-to-text transcription.
## Enforces a maximum entry limit and provides export functionality.

## Emitted when a new entry is added
signal entry_added(entry: TranscriptEntry)

## Emitted when all entries are cleared
signal entries_cleared()

## Maximum number of entries to store (oldest removed when exceeded)
const MAX_ENTRIES: int = 500

## Array of transcript entries in chronological order
var entries: Array[TranscriptEntry] = []

## Name of the current room (for export metadata)
var room_name: String = ""


## Add a new transcript entry to the store
func add_entry(entry: TranscriptEntry) -> void:
	entries.append(entry)
	_enforce_limit()
	entry_added.emit(entry)


## Get all stored entries
func get_entries() -> Array[TranscriptEntry]:
	return entries


## Get the number of stored entries
func get_entry_count() -> int:
	return entries.size()


## Clear all entries
func clear() -> void:
	entries.clear()
	entries_cleared.emit()


## Enforce the maximum entry limit by removing oldest entries
func _enforce_limit() -> void:
	while entries.size() > MAX_ENTRIES:
		entries.pop_front()


## Export transcript to readable text format
func export_to_text() -> String:
	var lines: PackedStringArray = []
	
	# Header
	lines.append("# World Transcript - %s" % room_name if not room_name.is_empty() else "# World Transcript")
	lines.append("# Exported: %s" % Time.get_datetime_string_from_system())
	lines.append("# Entries: %d" % entries.size())
	lines.append("")
	
	# Entries
	for entry in entries:
		var line := "[%s] %s: %s" % [
			entry.format_time(),
			entry.get_display_name(),
			entry.text
		]
		lines.append(line)
	
	return "\n".join(lines)


## Export transcript to JSON format with full metadata
func export_to_json() -> String:
	var data := {
		"room_name": room_name,
		"export_timestamp": Time.get_unix_time_from_system(),
		"export_date": Time.get_datetime_string_from_system(),
		"entry_count": entries.size(),
		"entries": []
	}
	
	for entry in entries:
		data.entries.append(entry.to_dict())
	
	return JSON.stringify(data, "\t")


## Save transcript to a JSON file
func save_to_file(filepath: String = "") -> bool:
	if filepath.is_empty():
		var datetime := Time.get_datetime_dict_from_system()
		var filename := "world_transcript_%04d%02d%02d_%02d%02d%02d.json" % [
			datetime.year, datetime.month, datetime.day,
			datetime.hour, datetime.minute, datetime.second
		]
		filepath = "user://" + filename
	
	var json_content := export_to_json()
	var file := FileAccess.open(filepath, FileAccess.WRITE)
	if not file:
		push_error("WorldTranscriptStore: Failed to open file for writing: " + filepath)
		return false
	
	file.store_string(json_content)
	file.close()
	return true


## Load transcript from a JSON file
func load_from_file(filepath: String) -> bool:
	if not FileAccess.file_exists(filepath):
		push_error("WorldTranscriptStore: File not found: " + filepath)
		return false
	
	var file := FileAccess.open(filepath, FileAccess.READ)
	if not file:
		push_error("WorldTranscriptStore: Failed to open file: " + filepath)
		return false
	
	var json_content := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	if json.parse(json_content) != OK:
		push_error("WorldTranscriptStore: Failed to parse JSON: " + json.get_error_message())
		return false
	
	var data: Dictionary = json.data
	if not data.has("entries"):
		push_error("WorldTranscriptStore: Invalid file format - missing entries")
		return false
	
	# Clear existing and load new
	entries.clear()
	room_name = data.get("room_name", "")
	
	for entry_data in data.entries:
		var entry := TranscriptEntry.from_dict(entry_data)
		entries.append(entry)
	
	_enforce_limit()
	return true
