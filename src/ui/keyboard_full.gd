extends Control
class_name KeyboardFullUI

## KeyboardFullUI - Full MacBook-style virtual keyboard with modifier keys
## Designed for worldspace rendering via SubViewport

signal key_pressed(key_event: Dictionary)  # {key: String, shift: bool, ctrl: bool, alt: bool, cmd: bool}
signal text_input(character: String)
signal special_key(key_name: String)  # "enter", "backspace", "tab", "escape", "arrow_up", etc.

# Modifier states
var is_shift_left: bool = false
var is_shift_right: bool = false
var is_ctrl: bool = false
var is_alt: bool = false
var is_cmd: bool = false
var is_caps_lock: bool = false

# References to modifier buttons for visual feedback
var _shift_left_btn: Button
var _shift_right_btn: Button
var _ctrl_btn: Button
var _alt_left_btn: Button
var _alt_right_btn: Button
var _cmd_left_btn: Button
var _cmd_right_btn: Button
var _caps_btn: Button

# Static instance for global keyboard input
static var instance: KeyboardFullUI = null

# Key layouts - MacBook style
const ROW_FUNCTION = ["Esc", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"]
const ROW_NUMBERS = ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "⌫"]
const ROW_QWERTY = ["Tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\\"]
const ROW_HOME = ["Caps", "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'", "Enter"]
const ROW_BOTTOM = ["⇧L", "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", "⇧R"]
const ROW_SPACE = ["Ctrl", "Alt", "⌘", "Space", "⌘R", "AltR", "←", "↑", "↓", "→"]

# Shift mappings
const SHIFT_MAP = {
	"`": "~", "1": "!", "2": "@", "3": "#", "4": "$", "5": "%",
	"6": "^", "7": "&", "8": "*", "9": "(", "0": ")", "-": "_", "=": "+",
	"[": "{", "]": "}", "\\": "|", ";": ":", "'": "\"",
	",": "<", ".": ">", "/": "?"
}

# Key sizes (relative to standard key)
const KEY_WIDTHS = {
	"Esc": 1.0, "⌫": 1.5, "Tab": 1.3, "\\": 1.0, "Caps": 1.6, "Enter": 1.8,
	"⇧L": 2.0, "⇧R": 2.0, "Ctrl": 1.2, "Alt": 1.0, "⌘": 1.2, "Space": 5.0,
	"⌘R": 1.2, "AltR": 1.0, "←": 1.0, "↑": 1.0, "↓": 1.0, "→": 1.0
}

const KEY_SIZE = Vector2(44, 36)
const KEY_SPACING = 3


func _ready() -> void:
	instance = self
	_build_keyboard()
	
	# Connect to KeyboardManager if available
	if KeyboardManager and KeyboardManager.instance:
		text_input.connect(_on_text_for_manager)
		special_key.connect(_on_special_for_manager)


func _on_text_for_manager(character: String) -> void:
	if KeyboardManager and KeyboardManager.instance:
		KeyboardManager.instance.send_text(character)


func _on_special_for_manager(key_name: String) -> void:
	if KeyboardManager and KeyboardManager.instance:
		KeyboardManager.instance.send_special_key(key_name)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if instance == self:
			instance = null


func _build_keyboard() -> void:
	var main_vbox = VBoxContainer.new()
	main_vbox.name = "MainVBox"
	main_vbox.add_theme_constant_override("separation", KEY_SPACING)
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(main_vbox)
	
	# Function row
	var func_row = _create_row(ROW_FUNCTION, "FunctionRow")
	main_vbox.add_child(func_row)
	
	# Numbers row
	var num_row = _create_row(ROW_NUMBERS, "NumbersRow")
	main_vbox.add_child(num_row)
	
	# QWERTY row
	var qwerty_row = _create_row(ROW_QWERTY, "QWERTYRow")
	main_vbox.add_child(qwerty_row)
	
	# Home row
	var home_row = _create_row(ROW_HOME, "HomeRow")
	main_vbox.add_child(home_row)
	
	# Bottom row
	var bottom_row = _create_row(ROW_BOTTOM, "BottomRow")
	main_vbox.add_child(bottom_row)
	
	# Space row
	var space_row = _create_row(ROW_SPACE, "SpaceRow")
	main_vbox.add_child(space_row)


func _create_row(keys: Array, row_name: String) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.name = row_name
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", KEY_SPACING)
	
	for key in keys:
		var btn = _create_key_button(key)
		row.add_child(btn)
		
		# Store references to modifier buttons
		match key:
			"⇧L": _shift_left_btn = btn
			"⇧R": _shift_right_btn = btn
			"Ctrl": _ctrl_btn = btn
			"Alt": _alt_left_btn = btn
			"AltR": _alt_right_btn = btn
			"⌘": _cmd_left_btn = btn
			"⌘R": _cmd_right_btn = btn
			"Caps": _caps_btn = btn
	
	return row


func _create_key_button(key: String) -> Button:
	var btn = Button.new()
	btn.name = key.replace(" ", "_")
	
	# IMPORTANT: Prevent keyboard buttons from stealing focus from input fields
	btn.focus_mode = Control.FOCUS_NONE
	
	# Set display text
	var display = key
	match key:
		"⇧L", "⇧R": display = "⇧"
		"⌘", "⌘R": display = "⌘"
		"AltR": display = "Alt"
		"⌫": display = "⌫"
	btn.text = display
	
	# Calculate size
	var width_mult = KEY_WIDTHS.get(key, 1.0)
	btn.custom_minimum_size = Vector2(KEY_SIZE.x * width_mult, KEY_SIZE.y)
	
	# Style based on key type
	_style_key(btn, key)
	
	# Connect signal
	btn.pressed.connect(_on_key_pressed.bind(key))
	
	return btn


func _style_key(btn: Button, key: String) -> void:
	btn.add_theme_font_size_override("font_size", 12)
	
	# Color by type
	if key in ["Esc", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"]:
		btn.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))  # Gray for function keys
	elif key in ["⇧L", "⇧R", "Ctrl", "Alt", "AltR", "⌘", "⌘R", "Caps"]:
		btn.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))  # Blue for modifiers
	elif key in ["⌫", "Tab", "Enter"]:
		btn.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))  # Green for special
	elif key in ["←", "↑", "↓", "→"]:
		btn.add_theme_color_override("font_color", Color(0.9, 0.75, 0.5))  # Orange for arrows
	elif key == "Space":
		btn.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))


func _on_key_pressed(key: String) -> void:
	match key:
		# Modifier keys - toggle
		"⇧L":
			is_shift_left = not is_shift_left
			_update_modifier_visuals()
		"⇧R":
			is_shift_right = not is_shift_right
			_update_modifier_visuals()
		"Ctrl":
			is_ctrl = not is_ctrl
			_update_modifier_visuals()
		"Alt", "AltR":
			is_alt = not is_alt
			_update_modifier_visuals()
		"⌘", "⌘R":
			is_cmd = not is_cmd
			_update_modifier_visuals()
		"Caps":
			is_caps_lock = not is_caps_lock
			_update_modifier_visuals()
		
		# Special keys
		"Esc":
			special_key.emit("escape")
		"Tab":
			special_key.emit("tab")
			text_input.emit("\t")
		"⌫":
			special_key.emit("backspace")
		"Enter":
			special_key.emit("enter")
			text_input.emit("\n")
		"←":
			special_key.emit("arrow_left")
		"→":
			special_key.emit("arrow_right")
		"↑":
			special_key.emit("arrow_up")
		"↓":
			special_key.emit("arrow_down")
		"Space":
			_emit_character(" ")
		
		# Function keys
		"F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12":
			special_key.emit(key.to_lower())
		
		# Regular keys
		_:
			var char = _get_character(key)
			_emit_character(char)


func _get_character(key: String) -> String:
	var is_shifted = is_shift_left or is_shift_right
	
	# Check for shift mappings (symbols)
	if is_shifted and SHIFT_MAP.has(key):
		_clear_shift()
		return SHIFT_MAP[key]
	
	# Letters
	if key.length() == 1 and key >= "A" and key <= "Z":
		if is_shifted or is_caps_lock:
			_clear_shift()
			return key.to_upper()
		else:
			return key.to_lower()
	
	return key


func _emit_character(char: String) -> void:
	text_input.emit(char)
	
	key_pressed.emit({
		"key": char,
		"shift": is_shift_left or is_shift_right,
		"ctrl": is_ctrl,
		"alt": is_alt,
		"cmd": is_cmd
	})
	
	# Clear modifiers after character input (except caps lock)
	_clear_shift()
	is_ctrl = false
	is_alt = false
	is_cmd = false
	_update_modifier_visuals()


func _clear_shift() -> void:
	if not is_caps_lock:
		is_shift_left = false
		is_shift_right = false
		_update_modifier_visuals()


func _update_modifier_visuals() -> void:
	var active_color = Color(0.2, 0.5, 1.0)  # Bright blue when active
	var inactive_color = Color(0.5, 0.7, 1.0)  # Dim blue when inactive
	var caps_active = Color(0.2, 1.0, 0.5)  # Green for caps lock
	
	if _shift_left_btn:
		_shift_left_btn.add_theme_color_override("font_color", active_color if is_shift_left else inactive_color)
	if _shift_right_btn:
		_shift_right_btn.add_theme_color_override("font_color", active_color if is_shift_right else inactive_color)
	if _ctrl_btn:
		_ctrl_btn.add_theme_color_override("font_color", active_color if is_ctrl else inactive_color)
	if _alt_left_btn:
		_alt_left_btn.add_theme_color_override("font_color", active_color if is_alt else inactive_color)
	if _alt_right_btn:
		_alt_right_btn.add_theme_color_override("font_color", active_color if is_alt else inactive_color)
	if _cmd_left_btn:
		_cmd_left_btn.add_theme_color_override("font_color", active_color if is_cmd else inactive_color)
	if _cmd_right_btn:
		_cmd_right_btn.add_theme_color_override("font_color", active_color if is_cmd else inactive_color)
	if _caps_btn:
		_caps_btn.add_theme_color_override("font_color", caps_active if is_caps_lock else inactive_color)


## Check if shift is active
func is_shifted() -> bool:
	return is_shift_left or is_shift_right or is_caps_lock


## Simulate a key press programmatically
func simulate_key(key: String) -> void:
	_on_key_pressed(key)
