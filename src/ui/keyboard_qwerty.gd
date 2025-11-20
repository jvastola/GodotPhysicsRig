extends Control
## KeyboardQWERTY - Full-featured standalone virtual QWERTY keyboard
## Can be used for any text input scenario, not just room codes

signal text_changed(text: String)
signal text_submitted(text: String)
signal text_cleared()

## Display label for current text
@onready var display_label: Label = $VBoxContainer/DisplayLabel

## Current text being typed
var current_text: String = ""

## Keyboard state
var is_shifted: bool = false
var is_caps_lock: bool = false

## Configuration
@export var max_length: int = 0  # 0 = unlimited
@export var placeholder_text: String = "Type here..."
@export var allow_numbers: bool = true
@export var allow_symbols: bool = true

## Keyboard layout definitions
const KEYS_ROW_1 = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
const KEYS_ROW_2 = ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"]
const KEYS_ROW_3 = ["A", "S", "D", "F", "G", "H", "J", "K", "L"]
const KEYS_ROW_4 = ["Z", "X", "C", "V", "B", "N", "M"]

## Symbol mappings for shifted numbers
const SHIFTED_NUMBERS = {
	"1": "!", "2": "@", "3": "#", "4": "$", "5": "%",
	"6": "^", "7": "&", "8": "*", "9": "(", "0": ")"
}

## Additional symbols
const SYMBOLS = [".", ",", "?", "!", "-", "_", "@", "#"]


func _ready() -> void:
	_build_keyboard()
	_update_display()


func _build_keyboard() -> void:
	"""Dynamically build the keyboard layout"""
	var vbox = $VBoxContainer
	
	# Numbers row (if enabled)
	if allow_numbers:
		var numbers_row = _create_row(KEYS_ROW_1, "NumbersRow")
		vbox.add_child(numbers_row)
		vbox.move_child(numbers_row, 1)  # After display label
	
	# QWERTY row
	var qwerty_row = _create_row(KEYS_ROW_2, "QWERTYRow")
	vbox.add_child(qwerty_row)
	
	# ASDFGH row
	var asdfgh_row = _create_row(KEYS_ROW_3, "ASDFGHRow")
	vbox.add_child(asdfgh_row)
	
	# ZXCVBN row
	var zxcvbn_row = _create_row(KEYS_ROW_4, "ZXCVBNRow")
	vbox.add_child(zxcvbn_row)
	
	# Symbols row (if enabled)
	if allow_symbols:
		var symbols_row = _create_row(SYMBOLS, "SymbolsRow")
		vbox.add_child(symbols_row)
	
	# Control buttons row
	var control_row = HBoxContainer.new()
	control_row.name = "ControlRow"
	control_row.alignment = BoxContainer.ALIGNMENT_CENTER
	
	# Shift button
	var shift_btn = _create_button("Shift", "shift")
	shift_btn.custom_minimum_size = Vector2(80, 40)
	shift_btn.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
	control_row.add_child(shift_btn)
	
	# Caps Lock button
	var caps_btn = _create_button("Caps", "caps")
	caps_btn.custom_minimum_size = Vector2(80, 40)
	caps_btn.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
	control_row.add_child(caps_btn)
	
	# Space button
	var space_btn = _create_button("Space", "space")
	space_btn.custom_minimum_size = Vector2(150, 40)
	control_row.add_child(space_btn)
	
	# Backspace button
	var backspace_btn = _create_button("⌫", "backspace")
	backspace_btn.custom_minimum_size = Vector2(80, 40)
	backspace_btn.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))
	control_row.add_child(backspace_btn)
	
	# Clear button
	var clear_btn = _create_button("Clear", "clear")
	clear_btn.custom_minimum_size = Vector2(80, 40)
	clear_btn.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	control_row.add_child(clear_btn)
	
	# Enter button
	var enter_btn = _create_button("Enter", "enter")
	enter_btn.custom_minimum_size = Vector2(80, 40)
	enter_btn.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	control_row.add_child(enter_btn)
	
	vbox.add_child(control_row)


func _create_row(keys: Array, row_name: String) -> HBoxContainer:
	"""Create a row of key buttons"""
	var row = HBoxContainer.new()
	row.name = row_name
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	
	for key in keys:
		var btn = _create_button(key, key)
		btn.custom_minimum_size = Vector2(40, 40)
		row.add_child(btn)
	
	return row


func _create_button(label: String, key_id: String) -> Button:
	"""Create a button and connect its signal"""
	var btn = Button.new()
	btn.text = label
	btn.pressed.connect(_on_key_pressed.bind(key_id))
	return btn


func _on_key_pressed(key: String) -> void:
	"""Handle key press"""
	match key:
		"shift":
			_toggle_shift()
		"caps":
			_toggle_caps_lock()
		"space":
			_add_character(" ")
		"backspace":
			_remove_character()
		"clear":
			_clear_text()
		"enter":
			_submit_text()
		_:
			# Regular character key
			_add_character(_get_character(key))


func _get_character(key: String) -> String:
	"""Get the actual character to type based on shift/caps state"""
	# Check if it's a number with shift
	if is_shifted and SHIFTED_NUMBERS.has(key):
		# Turn off shift after using it
		is_shifted = false
		_update_shift_indicators()
		return SHIFTED_NUMBERS[key]
	
	# Check if it's a letter
	if key.length() == 1 and key.to_upper() == key:
		# It's a letter key
		if is_shifted or is_caps_lock:
			# Turn off shift after using it (but not caps lock)
			if is_shifted and not is_caps_lock:
				is_shifted = false
				_update_shift_indicators()
			return key.to_upper()
		else:
			return key.to_lower()
	
	# Symbol or number
	return key


func _add_character(character: String) -> void:
	"""Add a character to the current text"""
	if max_length > 0 and current_text.length() >= max_length:
		return
	
	current_text += character
	_update_display()
	text_changed.emit(current_text)


func _remove_character() -> void:
	"""Remove the last character"""
	if current_text.length() > 0:
		current_text = current_text.substr(0, current_text.length() - 1)
		_update_display()
		text_changed.emit(current_text)


func _clear_text() -> void:
	"""Clear all text"""
	current_text = ""
	_update_display()
	text_cleared.emit()
	text_changed.emit(current_text)


func _submit_text() -> void:
	"""Submit the current text"""
	text_submitted.emit(current_text)


func _toggle_shift() -> void:
	"""Toggle shift state"""
	is_shifted = not is_shifted
	_update_shift_indicators()


func _toggle_caps_lock() -> void:
	"""Toggle caps lock state"""
	is_caps_lock = not is_caps_lock
	is_shifted = false  # Turn off shift when toggling caps
	_update_shift_indicators()


func _update_shift_indicators() -> void:
	"""Update visual indicators for shift/caps lock"""
	var shift_btn = get_node_or_null("VBoxContainer/ControlRow/Shift")
	var caps_btn = get_node_or_null("VBoxContainer/ControlRow/Caps")
	
	if shift_btn:
		if is_shifted:
			shift_btn.add_theme_color_override("font_color", Color(0.2, 0.4, 1.0))
		else:
			shift_btn.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
	
	if caps_btn:
		if is_caps_lock:
			caps_btn.add_theme_color_override("font_color", Color(0.2, 0.4, 1.0))
		else:
			caps_btn.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))


func _update_display() -> void:
	"""Update the display label"""
	if display_label:
		if current_text.is_empty():
			display_label.text = placeholder_text
			display_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		else:
			display_label.text = current_text
			display_label.remove_theme_color_override("font_color")


## Public API

func get_text() -> String:
	"""Get the current text"""
	return current_text


func set_text(text: String) -> void:
	"""Set the text programmatically"""
	current_text = text
	if max_length > 0:
		current_text = current_text.substr(0, max_length)
	_update_display()
	text_changed.emit(current_text)


func clear() -> void:
	"""Clear the keyboard text"""
	_clear_text()
