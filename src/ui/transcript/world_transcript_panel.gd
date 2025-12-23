class_name WorldTranscriptPanel
extends PanelContainer

## UI panel displaying the world transcript of all voice activity in a room.
## Shows real-time transcriptions with speaker names and timestamps.
## Supports text selection, right-click context menu, and clickable entries.

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

## Context menu for right-click actions
var context_menu: PopupMenu

## Reference to the transcript store
var transcript_store: WorldTranscriptStore

## Auto-scroll to bottom when new entries arrive
@export var auto_scroll: bool = true

## Colors for different speakers
const LOCAL_COLOR := Color(0.4, 0.7, 1.0)  # Blue for local user
const REMOTE_COLOR := Color(0.7, 0.7, 0.7)  # Gray for remote users
const TIMESTAMP_COLOR := Color(0.5, 0.5, 0.55)

## Context menu item IDs
enum ContextMenuItem {
	COPY_SELECTION,
	COPY_ALL,
	SEND_SELECTION_TO_LLM,
	SEND_ENTRY_TO_LLM,
	SEPARATOR,
	CLEAR_ALL
}

## Currently hovered/clicked entry index
var _clicked_entry_index: int = -1


func _ready() -> void:
	_setup_ui()
	_setup_context_menu()
	_connect_store()


func _setup_ui() -> void:
	if transcript_output:
		transcript_output.bbcode_enabled = true
		transcript_output.scroll_following = auto_scroll
		transcript_output.selection_enabled = true
		transcript_output.context_menu_enabled = false  # We'll handle our own
		transcript_output.meta_clicked.connect(_on_meta_clicked)
		transcript_output.gui_input.connect(_on_transcript_gui_input)
	
	if copy_button:
		copy_button.pressed.connect(_on_copy_pressed)
	if export_button:
		export_button.pressed.connect(_on_export_pressed)
	if clear_button:
		clear_button.pressed.connect(_on_clear_pressed)
	
	_update_status("Not connected")


func _setup_context_menu() -> void:
	context_menu = PopupMenu.new()
	context_menu.name = "ContextMenu"
	add_child(context_menu)
	
	context_menu.add_item("Copy Selection", ContextMenuItem.COPY_SELECTION)
	context_menu.add_item("Copy All", ContextMenuItem.COPY_ALL)
	context_menu.add_separator()
	context_menu.add_item("Send Selection to LLM", ContextMenuItem.SEND_SELECTION_TO_LLM)
	context_menu.add_item("Send This Entry to LLM", ContextMenuItem.SEND_ENTRY_TO_LLM)
	context_menu.add_separator()
	context_menu.add_item("Clear All", ContextMenuItem.CLEAR_ALL)
	
	context_menu.id_pressed.connect(_on_context_menu_item_pressed)


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


## Handle GUI input on the transcript output
func _on_transcript_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			_show_context_menu(mouse_event.global_position)
			get_viewport().set_input_as_handled()


## Show context menu at position
func _show_context_menu(pos: Vector2) -> void:
	# Update menu item states based on selection
	var has_selection := transcript_output and not transcript_output.get_selected_text().is_empty()
	var has_entries := transcript_store and transcript_store.get_entry_count() > 0
	
	# Find which entry was clicked (approximate by line)
	_clicked_entry_index = _get_entry_index_at_position(pos)
	
	context_menu.set_item_disabled(context_menu.get_item_index(ContextMenuItem.COPY_SELECTION), not has_selection)
	context_menu.set_item_disabled(context_menu.get_item_index(ContextMenuItem.SEND_SELECTION_TO_LLM), not has_selection)
	context_menu.set_item_disabled(context_menu.get_item_index(ContextMenuItem.SEND_ENTRY_TO_LLM), _clicked_entry_index < 0)
	context_menu.set_item_disabled(context_menu.get_item_index(ContextMenuItem.COPY_ALL), not has_entries)
	context_menu.set_item_disabled(context_menu.get_item_index(ContextMenuItem.CLEAR_ALL), not has_entries)
	
	context_menu.position = Vector2i(int(pos.x), int(pos.y))
	context_menu.popup()


## Get entry index at a screen position (approximate)
func _get_entry_index_at_position(_pos: Vector2) -> int:
	if not transcript_output or not transcript_store:
		return -1
	
	# Get the line at the click position
	# This is approximate - we estimate based on scroll position and line height
	var entries := transcript_store.get_entries()
	if entries.is_empty():
		return -1
	
	# For now, return the last entry if we can't determine exact position
	# A more accurate implementation would parse the RichTextLabel layout
	return entries.size() - 1


## Handle context menu item selection
func _on_context_menu_item_pressed(id: int) -> void:
	match id:
		ContextMenuItem.COPY_SELECTION:
			_copy_selection()
		ContextMenuItem.COPY_ALL:
			_on_copy_pressed()
		ContextMenuItem.SEND_SELECTION_TO_LLM:
			_send_selection_to_llm()
		ContextMenuItem.SEND_ENTRY_TO_LLM:
			_send_entry_to_llm(_clicked_entry_index)
		ContextMenuItem.CLEAR_ALL:
			_on_clear_pressed()


## Copy selected text to clipboard
func _copy_selection() -> void:
	if transcript_output:
		var selected := transcript_output.get_selected_text()
		if not selected.is_empty():
			DisplayServer.clipboard_set(selected)
			_update_status("Selection copied")


## Send selected text to LLM
func _send_selection_to_llm() -> void:
	if transcript_output:
		var selected := transcript_output.get_selected_text()
		if not selected.is_empty():
			send_to_llm_requested.emit(selected)
			_update_status("Sent selection to LLM")


## Send a specific entry to LLM
func _send_entry_to_llm(entry_index: int) -> void:
	if not transcript_store or entry_index < 0:
		return
	
	var entries := transcript_store.get_entries()
	if entry_index >= entries.size():
		return
	
	var entry := entries[entry_index]
	var text := "%s: %s" % [entry.get_display_name(), entry.text]
	send_to_llm_requested.emit(text)
	_update_status("Sent entry to LLM")


## Handle meta (link) clicks in the transcript
func _on_meta_clicked(meta: Variant) -> void:
	var meta_str := str(meta)
	if meta_str.begins_with("entry:"):
		var index := int(meta_str.substr(6))
		_send_entry_to_llm(index)


## Set the transcript store to use
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


## Handle new transcript entry
func _on_entry_added(entry: TranscriptEntry) -> void:
	_append_entry(entry, transcript_store.get_entry_count() - 1)
	_update_status("Connected - %d entries" % transcript_store.get_entry_count())


## Handle entries cleared
func _on_entries_cleared() -> void:
	if transcript_output:
		transcript_output.text = ""
	_update_status("Cleared")


## Append a single entry to the display
func _append_entry(entry: TranscriptEntry, index: int = -1) -> void:
	if not transcript_output:
		return
	
	var color := LOCAL_COLOR if entry.is_local else REMOTE_COLOR
	var speaker := entry.get_display_name()
	var time_str := entry.format_time()
	
	# Make the entry clickable with a meta tag
	var meta_tag := ""
	if index >= 0:
		meta_tag = "[url=entry:%d]" % index
		var meta_end := "[/url]"
	
	# Build BBCode with clickable speaker name
	var bbcode := "[color=#%s][%s][/color] " % [TIMESTAMP_COLOR.to_html(false), time_str]
	
	if index >= 0:
		bbcode += "[url=entry:%d][color=#%s][b]%s:[/b][/color][/url] " % [
			index,
			color.to_html(false),
			_escape_bbcode(speaker)
		]
	else:
		bbcode += "[color=#%s][b]%s:[/b][/color] " % [
			color.to_html(false),
			_escape_bbcode(speaker)
		]
	
	bbcode += "%s\n" % _escape_bbcode(entry.text)
	
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
	var entries := transcript_store.get_entries()
	for i in entries.size():
		_append_entry(entries[i], i)


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
