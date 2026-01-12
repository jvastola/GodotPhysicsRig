class_name WorldTranscriptPanel
extends PanelContainer

## UI panel displaying the world transcript of all voice activity in a room.
## Each transcript entry has a "Send to LLM" button for easy interaction.

signal send_to_llm_requested(text: String)
signal close_requested

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleRow/TitleLabel
@onready var status_label: Label = $MarginContainer/VBoxContainer/TitleRow/StatusLabel
@onready var transcript_scroll: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer
@onready var entries_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/EntriesContainer
@onready var copy_button: Button = $MarginContainer/VBoxContainer/ButtonRow/CopyButton
@onready var export_button: Button = $MarginContainer/VBoxContainer/ButtonRow/ExportButton
@onready var clear_button: Button = $MarginContainer/VBoxContainer/ButtonRow/ClearButton
@onready var close_button: Button = $MarginContainer/VBoxContainer/TitleRow/CloseButton

var transcript_store: WorldTranscriptStore

@export var auto_scroll: bool = true
@export var max_visible_entries: int = 100

const LOCAL_COLOR := Color(0.4, 0.7, 1.0)
const REMOTE_COLOR := Color(0.8, 0.8, 0.8)
const TIMESTAMP_COLOR := Color(0.5, 0.5, 0.55)


func _ready() -> void:
	_setup_ui()
	_connect_store()


func _setup_ui() -> void:
	if copy_button:
		copy_button.pressed.connect(_on_copy_pressed)
	if export_button:
		export_button.pressed.connect(_on_export_pressed)
	if clear_button:
		clear_button.pressed.connect(_on_clear_pressed)
	if close_button:
		close_button.pressed.connect(func(): close_requested.emit())
	
	_update_status("Not connected")


func _connect_store() -> void:
	if not transcript_store:
		transcript_store = get_node_or_null("WorldTranscriptStore")
		if not transcript_store:
			transcript_store = WorldTranscriptStore.new()
			transcript_store.name = "WorldTranscriptStore"
			add_child(transcript_store)
	
	if transcript_store:
		transcript_store.entry_added.connect(_on_entry_added)
		transcript_store.entries_cleared.connect(_on_entries_cleared)


func set_transcript_store(store: WorldTranscriptStore) -> void:
	if transcript_store:
		if transcript_store.entry_added.is_connected(_on_entry_added):
			transcript_store.entry_added.disconnect(_on_entry_added)
		if transcript_store.entries_cleared.is_connected(_on_entries_cleared):
			transcript_store.entries_cleared.disconnect(_on_entries_cleared)
	
	transcript_store = store
	
	if transcript_store:
		transcript_store.entry_added.connect(_on_entry_added)
		transcript_store.entries_cleared.connect(_on_entries_cleared)
		_refresh_display()


func _on_entry_added(entry: TranscriptEntry) -> void:
	_add_entry_ui(entry)
	_update_status("Connected - %d entries" % transcript_store.get_entry_count())
	_enforce_visible_limit()


func _on_entries_cleared() -> void:
	_clear_entries_ui()
	_update_status("Cleared")


func _add_entry_ui(entry: TranscriptEntry) -> void:
	if not entries_container:
		return
	
	var entry_row := HBoxContainer.new()
	entry_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Text container (timestamp + speaker + text)
	var text_container := VBoxContainer.new()
	text_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Header row (timestamp + speaker)
	var header := HBoxContainer.new()
	
	var time_label := Label.new()
	time_label.text = "[%s]" % entry.format_time()
	time_label.add_theme_color_override("font_color", TIMESTAMP_COLOR)
	time_label.add_theme_font_size_override("font_size", 11)
	header.add_child(time_label)
	
	var speaker_label := Label.new()
	speaker_label.text = " %s:" % entry.get_display_name()
	speaker_label.add_theme_color_override("font_color", LOCAL_COLOR if entry.is_local else REMOTE_COLOR)
	speaker_label.add_theme_font_size_override("font_size", 12)
	header.add_child(speaker_label)
	
	text_container.add_child(header)
	
	# Message text (selectable)
	var message_label := RichTextLabel.new()
	message_label.bbcode_enabled = true
	message_label.fit_content = true
	message_label.scroll_active = false
	message_label.selection_enabled = true
	message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_label.text = entry.text
	message_label.add_theme_font_size_override("normal_font_size", 13)
	text_container.add_child(message_label)
	
	entry_row.add_child(text_container)
	
	# Send to LLM button
	var send_btn := Button.new()
	send_btn.text = "→ LLM"
	send_btn.tooltip_text = "Send this message to LLM Chat"
	send_btn.custom_minimum_size = Vector2(60, 0)
	send_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	# Store the entry text for the button callback
	var entry_text := "%s: %s" % [entry.get_display_name(), entry.text]
	send_btn.pressed.connect(func(): _send_to_llm(entry_text))
	
	entry_row.add_child(send_btn)
	
	# Add separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	
	entries_container.add_child(entry_row)
	entries_container.add_child(sep)
	
	# Auto-scroll
	if auto_scroll and transcript_scroll:
		await get_tree().process_frame
		transcript_scroll.scroll_vertical = int(transcript_scroll.get_v_scroll_bar().max_value)


func _send_to_llm(text: String) -> void:
	send_to_llm_requested.emit(text)
	_update_status("Sent to LLM")


func _clear_entries_ui() -> void:
	if not entries_container:
		return
	for child in entries_container.get_children():
		child.queue_free()


func _refresh_display() -> void:
	_clear_entries_ui()
	if not transcript_store:
		return
	for entry in transcript_store.get_entries():
		_add_entry_ui(entry)


func _enforce_visible_limit() -> void:
	if not entries_container:
		return
	# Each entry has 2 children (row + separator)
	while entries_container.get_child_count() > max_visible_entries * 2:
		var child := entries_container.get_child(0)
		if child:
			child.queue_free()
		child = entries_container.get_child(0)
		if child:
			child.queue_free()


func _update_status(status: String) -> void:
	if status_label:
		status_label.text = status


func _on_copy_pressed() -> void:
	if transcript_store:
		DisplayServer.clipboard_set(transcript_store.export_to_text())
		_update_status("Copied to clipboard")


func _on_export_pressed() -> void:
	if transcript_store and transcript_store.save_to_file():
		_update_status("Exported to user://")
	else:
		_update_status("Export failed")


func _on_clear_pressed() -> void:
	if transcript_store:
		transcript_store.clear()


func send_last_entry_to_llm() -> void:
	if transcript_store and transcript_store.get_entry_count() > 0:
		var entries := transcript_store.get_entries()
		var last := entries[entries.size() - 1]
		send_to_llm_requested.emit(last.text)
