class_name WorldTranscriptPanel
extends PanelContainer

## UI panel displaying the world transcript of all voice activity in a room.
## Shows real-time transcriptions with speaker names and timestamps.

## Emitted when user requests to send text to the LLM
signal send_to_llm_requested(text: String)

## UI References
@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleRow/TitleLabel
@onready var status_label: Label = $MarginContainer/VBoxContainer/TitleRow/StatusLabel
@onready var transcript_scroll: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer
@onready var transcript_output: RichTextLabel = $MarginContainer/VBoxContainer/ScrollContainer/TranscriptOutput
@onready var copy_button: Button = $MarginContainer/VBoxContainer/ButtonRow/CopyButton
@onready var export_button: Button = $MarginContainer/VBoxContainer/ButtonRow/ExportButton
@onready var clear_button: Button = $MarginContainer/VBoxContainer/ButtonRow/ClearButton

## Reference to the transcript store
var transcript_store: WorldTranscriptStore

## Auto-scroll to bottom when new entries arrive
@export var auto_scroll: bool = true

## Colors for different speakers
const LOCAL_COLOR := Color(0.4, 0.7, 1.0)  # Blue for local user
const REMOTE_COLOR := Color(0.7, 0.7, 0.7)  # Gray for remote users
const TIMESTAMP_COLOR := Color(0.5, 0.5, 0.55)


func _ready() -> void:
	_setup_ui()
	_connect_store()


func _setup_ui() -> void:
	if transcript_output:
		transcript_output.bbcode_enabled = true
		transcript_output.scroll_following = auto_scroll
		transcript_output.selection_enabled = true
	
	if copy_button:
		copy_button.pressed.connect(_on_copy_pressed)
	if export_button:
		export_button.pressed.connect(_on_export_pressed)
	if clear_button:
		clear_button.pressed.connect(_on_clear_pressed)
	
	_update_status("Not connected")


func _connect_store() -> void:
	if not transcript_store:
		# Try to find or create a store
		transcript_store = get_node_or_null("WorldTranscriptStore")
		if not transcript_store:
			transcript_store = WorldTranscriptStore.new()
			transcript_store.name = "WorldTranscriptStore"
			add_child(transcript_store)
	
	if transcript_store:
		transcript_store.entry_added.connect(_on_entry_added)
		transcript_store.entries_cleared.connect(_on_entries_cleared)


## Set the transcript store to use
func set_transcript_store(store: WorldTranscriptStore) -> void:
	# Disconnect from old store
	if transcript_store:
		if transcript_store.entry_added.is_connected(_on_entry_added):
			transcript_store.entry_added.disconnect(_on_entry_added)
		if transcript_store.entries_cleared.is_connected(_on_entries_cleared):
			transcript_store.entries_cleared.disconnect(_on_entries_cleared)
	
	transcript_store = store
	
	# Connect to new store
	if transcript_store:
		transcript_store.entry_added.connect(_on_entry_added)
		transcript_store.entries_cleared.connect(_on_entries_cleared)
		# Refresh display with existing entries
		_refresh_display()


## Handle new transcript entry
func _on_entry_added(entry: TranscriptEntry) -> void:
	_append_entry(entry)
	_update_status("Connected - %d entries" % transcript_store.get_entry_count())


## Handle entries cleared
func _on_entries_cleared() -> void:
	if transcript_output:
		transcript_output.text = ""
	_update_status("Cleared")


## Append a single entry to the display
func _append_entry(entry: TranscriptEntry) -> void:
	if not transcript_output:
		return
	
	var color := LOCAL_COLOR if entry.is_local else REMOTE_COLOR
	var speaker := entry.get_display_name()
	var time_str := entry.format_time()
	
	var bbcode := "[color=#%s][%s][/color] [color=#%s][b]%s:[/b][/color] %s\n" % [
		TIMESTAMP_COLOR.to_html(false),
		time_str,
		color.to_html(false),
		_escape_bbcode(speaker),
		_escape_bbcode(entry.text)
	]
	
	transcript_output.append_text(bbcode)
	
	# Auto-scroll
	if auto_scroll and transcript_scroll:
		await get_tree().process_frame
		transcript_scroll.scroll_vertical = transcript_scroll.get_v_scroll_bar().max_value


## Refresh the entire display from the store
func _refresh_display() -> void:
	if not transcript_output or not transcript_store:
		return
	
	transcript_output.text = ""
	for entry in transcript_store.get_entries():
		_append_entry(entry)


## Update the status label
func _update_status(status: String) -> void:
	if status_label:
		status_label.text = status


## Escape BBCode special characters
func _escape_bbcode(text: String) -> String:
	return text.replace("[", "［").replace("]", "］")


## Copy transcript to clipboard
func _on_copy_pressed() -> void:
	if not transcript_store:
		return
	
	var text := transcript_store.export_to_text()
	DisplayServer.clipboard_set(text)
	_update_status("Copied to clipboard")


## Export transcript to file
func _on_export_pressed() -> void:
	if not transcript_store:
		return
	
	if transcript_store.save_to_file():
		_update_status("Exported to user://")
	else:
		_update_status("Export failed")


## Clear all entries
func _on_clear_pressed() -> void:
	if transcript_store:
		transcript_store.clear()


## Send selected or last entry text to LLM
func send_last_entry_to_llm() -> void:
	if not transcript_store or transcript_store.get_entry_count() == 0:
		return
	
	var entries := transcript_store.get_entries()
	var last_entry := entries[entries.size() - 1]
	send_to_llm_requested.emit(last_entry.text)


## Send specific text to LLM
func send_text_to_llm(text: String) -> void:
	send_to_llm_requested.emit(text)
