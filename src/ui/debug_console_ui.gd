extends PanelContainer

# Debug Console UI - Displays print output and errors in 3D worldspace
# Captures messages via a custom logger

signal console_cleared

@export var max_lines: int = 100
@export var auto_scroll: bool = true
@export var show_timestamps: bool = true
@export var font_size: int = 12

@onready var output_label: RichTextLabel = $MarginContainer/VBoxContainer/ScrollContainer/OutputLabel
@onready var clear_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/ClearButton
@onready var scroll_container: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer
@onready var filter_option: OptionButton = $MarginContainer/VBoxContainer/HBoxContainer/FilterOption

var _messages: Array[Dictionary] = []
var _filter: int = 0  # 0=All, 1=Info, 2=Warning, 3=Error

# Message types
enum MessageType { INFO, WARNING, ERROR, SYSTEM }

# Colors for different message types
const TYPE_COLORS = {
	MessageType.INFO: Color(0.9, 0.9, 0.95),
	MessageType.WARNING: Color(1.0, 0.85, 0.3),
	MessageType.ERROR: Color(1.0, 0.4, 0.4),
	MessageType.SYSTEM: Color(0.5, 0.8, 1.0),
}

# Static reference for global access
static var instance: PanelContainer = null


func _ready() -> void:
	instance = self
	
	if clear_button:
		clear_button.pressed.connect(_on_clear_pressed)
	
	if filter_option:
		filter_option.add_item("All", 0)
		filter_option.add_item("Info", 1)
		filter_option.add_item("Warning", 2)
		filter_option.add_item("Error", 3)
		filter_option.item_selected.connect(_on_filter_changed)
	
	if output_label:
		output_label.bbcode_enabled = true
		output_label.scroll_following = auto_scroll
		output_label.add_theme_font_size_override("normal_font_size", font_size)
	
	# Add startup message
	log_system("Debug Console initialized")
	log_system("Use DebugConsoleUI.log(), log_warning(), log_error() to output messages")


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if instance == self:
			instance = null


## Log an info message
static func log(message: String) -> void:
	if instance:
		instance._add_message(message, MessageType.INFO)
	else:
		print(message)


## Log a warning message
static func log_warning(message: String) -> void:
	if instance:
		instance._add_message(message, MessageType.WARNING)
	else:
		push_warning(message)


## Log an error message
static func log_error(message: String) -> void:
	if instance:
		instance._add_message(message, MessageType.ERROR)
	else:
		push_error(message)


## Log a system message
func log_system(message: String) -> void:
	_add_message(message, MessageType.SYSTEM)


## Add a message to the console
func _add_message(message: String, type: MessageType) -> void:
	var timestamp = Time.get_time_string_from_system()
	
	var msg_data = {
		"text": message,
		"type": type,
		"timestamp": timestamp,
	}
	
	_messages.append(msg_data)
	
	# Trim old messages
	while _messages.size() > max_lines:
		_messages.pop_front()
	
	_refresh_display()


## Refresh the display based on current filter
func _refresh_display() -> void:
	if not output_label:
		return
	
	var bbcode_text = ""
	
	for msg in _messages:
		var type: MessageType = msg["type"]
		
		# Apply filter
		if _filter > 0:
			match _filter:
				1:  # Info only
					if type != MessageType.INFO:
						continue
				2:  # Warning only
					if type != MessageType.WARNING:
						continue
				3:  # Error only
					if type != MessageType.ERROR:
						continue
		
		var color: Color = TYPE_COLORS[type]
		var color_hex = color.to_html(false)
		
		var line = ""
		if show_timestamps:
			line += "[color=#888888][%s][/color] " % msg["timestamp"]
		
		# Add type prefix
		match type:
			MessageType.WARNING:
				line += "[color=#%s]⚠ %s[/color]" % [color_hex, msg["text"]]
			MessageType.ERROR:
				line += "[color=#%s]❌ %s[/color]" % [color_hex, msg["text"]]
			MessageType.SYSTEM:
				line += "[color=#%s]🔧 %s[/color]" % [color_hex, msg["text"]]
			_:
				line += "[color=#%s]%s[/color]" % [color_hex, msg["text"]]
		
		bbcode_text += line + "\n"
	
	output_label.text = bbcode_text
	
	# Auto-scroll to bottom
	if auto_scroll and scroll_container:
		await get_tree().process_frame
		scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value


func _on_clear_pressed() -> void:
	_messages.clear()
	_refresh_display()
	log_system("Console cleared")
	console_cleared.emit()


func _on_filter_changed(index: int) -> void:
	_filter = index
	_refresh_display()


## Clear all messages
func clear() -> void:
	_messages.clear()
	_refresh_display()


## Get message count
func get_message_count() -> int:
	return _messages.size()
