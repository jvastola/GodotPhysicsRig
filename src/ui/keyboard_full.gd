extends Control
class_name KeyboardFullUI

## KeyboardFullUI - Full MacBook-style virtual keyboard with modifier keys
## Features: Dynamic case display, shortcut keys, text preview bar, drag-to-select

signal key_pressed(key_event: Dictionary)  # {key: String, shift: bool, ctrl: bool, alt: bool, cmd: bool}
signal text_input(character: String)
signal special_key(key_name: String)  # "enter", "backspace", "tab", "escape", "arrow_up", etc.
signal shortcut_action(action: String)  # "copy", "paste", "undo", "redo", "find", "replace", "save", "mic_input"
signal text_submitted(text: String)  # Emitted when Send button pressed in preview bar

# Modifier states
var is_shift_left: bool = false
var is_shift_right: bool = false
var is_ctrl: bool = false
var is_alt: bool = false
var is_cmd: bool = false
var is_caps_lock: bool = false

# Text preview state
var _pending_text: String = ""
var _selection_start: int = -1
var _selection_end: int = -1
var _is_dragging: bool = false

# References to modifier buttons for visual feedback
var _shift_left_btn: Button
var _shift_right_btn: Button
var _ctrl_btn: Button
var _alt_left_btn: Button
var _alt_right_btn: Button
var _cmd_left_btn: Button
var _cmd_right_btn: Button
var _caps_btn: Button

# References for dynamic label updates
var _letter_buttons: Dictionary = {}  # Key: original letter (A-Z), Value: Button
var _symbol_buttons: Dictionary = {}  # Key: original symbol, Value: Button
var _text_preview: LineEdit
var _send_btn: Button
var _clear_btn: Button

# Static instance for global keyboard input
static var instance: KeyboardFullUI = null

# Key layouts - MacBook style with shortcuts instead of F keys
const ROW_SHORTCUTS = ["Esc", "Undo", "Redo", "Find", "Replace", "Copy", "Paste", "SelAll", "Save", "🎤", "Home", "End", "Del"]
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
	"⌘R": 1.2, "AltR": 1.0, "←": 1.0, "↑": 1.0, "↓": 1.0, "→": 1.0,
	"Undo": 1.0, "Redo": 1.0, "Find": 1.0, "Replace": 1.2, "Copy": 1.0,
	"Paste": 1.0, "SelAll": 1.2, "Save": 1.0, "🎤": 1.0, "Home": 1.0,
	"End": 1.0, "Del": 1.0
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
	
	# Text preview bar at top
	var preview_container = _create_preview_bar()
	main_vbox.add_child(preview_container)
	
	# Shortcut row (replaces function keys)
	var shortcut_row = _create_row(ROW_SHORTCUTS, "ShortcutRow")
	main_vbox.add_child(shortcut_row)
	
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


func _create_preview_bar() -> HBoxContainer:
	var container = HBoxContainer.new()
	container.name = "PreviewBar"
	container.add_theme_constant_override("separation", 6)
	
	# Text preview LineEdit
	_text_preview = LineEdit.new()
	_text_preview.name = "TextPreview"
	_text_preview.placeholder_text = "Type here..."
	_text_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_preview.custom_minimum_size = Vector2(0, 32)
	_text_preview.editable = false  # Read-only, keyboard types into it
	_text_preview.focus_mode = Control.FOCUS_NONE
	
	# Style the preview
	_text_preview.add_theme_font_size_override("font_size", 14)
	_text_preview.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_text_preview.add_theme_color_override("font_placeholder_color", Color(0.5, 0.5, 0.6))
	
	# Connect drag signals for text selection
	_text_preview.gui_input.connect(_on_preview_gui_input)
	
	container.add_child(_text_preview)
	
	# Send button
	_send_btn = Button.new()
	_send_btn.name = "SendBtn"
	_send_btn.text = "Send"
	_send_btn.custom_minimum_size = Vector2(60, 32)
	_send_btn.focus_mode = Control.FOCUS_NONE
	_send_btn.add_theme_font_size_override("font_size", 12)
	_send_btn.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	_send_btn.pressed.connect(_on_send_pressed)
	container.add_child(_send_btn)
	
	# Clear button
	_clear_btn = Button.new()
	_clear_btn.name = "ClearBtn"
	_clear_btn.text = "Clear"
	_clear_btn.custom_minimum_size = Vector2(60, 32)
	_clear_btn.focus_mode = Control.FOCUS_NONE
	_clear_btn.add_theme_font_size_override("font_size", 12)
	_clear_btn.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	_clear_btn.pressed.connect(_on_clear_pressed)
	container.add_child(_clear_btn)
	
	return container


func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Start drag selection
				_is_dragging = true
				_selection_start = _get_char_at_position(mb.position.x)
				_selection_end = _selection_start
				_text_preview.select(_selection_start, _selection_end)
			else:
				# End drag
				_is_dragging = false
				if _selection_start != _selection_end:
					_show_selection_menu()
	
	elif event is InputEventMouseMotion and _is_dragging:
		var mm := event as InputEventMouseMotion
		_selection_end = _get_char_at_position(mm.position.x)
		var start = mini(_selection_start, _selection_end)
		var end = maxi(_selection_start, _selection_end)
		_text_preview.select(start, end)


func _get_char_at_position(x_pos: float) -> int:
	# Approximate character position from x coordinate
	var font = _text_preview.get_theme_font("font")
	var font_size = _text_preview.get_theme_font_size("font_size")
	if not font or font_size <= 0:
		return 0
	
	var text = _text_preview.text
	if text.is_empty():
		return 0
	
	# Calculate approximate char width
	var total_width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if total_width <= 0:
		return 0
	
	var char_width = total_width / float(text.length())
	var char_index = int(x_pos / char_width)
	return clampi(char_index, 0, text.length())


func _show_selection_menu() -> void:
	# Show a small popup with Copy, Cut, Delete options
	var popup = PopupMenu.new()
	popup.name = "SelectionMenu"
	popup.add_item("Copy", 0)
	popup.add_item("Cut", 1)
	popup.add_item("Delete", 2)
	popup.add_separator()
	popup.add_item("Select All", 3)
	
	popup.id_pressed.connect(_on_selection_menu_item.bind(popup))
	
	add_child(popup)
	popup.position = get_global_mouse_position()
	popup.popup()


func _on_selection_menu_item(id: int, popup: PopupMenu) -> void:
	var start = mini(_selection_start, _selection_end)
	var end = maxi(_selection_start, _selection_end)
	var selected_text = _pending_text.substr(start, end - start)
	
	match id:
		0:  # Copy
			DisplayServer.clipboard_set(selected_text)
		1:  # Cut
			DisplayServer.clipboard_set(selected_text)
			_pending_text = _pending_text.substr(0, start) + _pending_text.substr(end)
			_update_preview()
		2:  # Delete
			_pending_text = _pending_text.substr(0, start) + _pending_text.substr(end)
			_update_preview()
		3:  # Select All
			_selection_start = 0
			_selection_end = _pending_text.length()
			_text_preview.select_all()
	
	popup.queue_free()


func _on_send_pressed() -> void:
	if not _pending_text.is_empty():
		text_submitted.emit(_pending_text)
		# Also send to focused control
		if KeyboardManager and KeyboardManager.instance and KeyboardManager.instance.has_focus():
			KeyboardManager.instance.send_text(_pending_text)
		_pending_text = ""
		_update_preview()


func _on_clear_pressed() -> void:
	_pending_text = ""
	_update_preview()


func _update_preview() -> void:
	if _text_preview:
		_text_preview.text = _pending_text


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
		
		# Store references to letter and symbol buttons for dynamic updates
		if key.length() == 1 and key >= "A" and key <= "Z":
			_letter_buttons[key] = btn
		elif SHIFT_MAP.has(key):
			_symbol_buttons[key] = btn
	
	return row


func _create_key_button(key: String) -> Button:
	var btn = Button.new()
	btn.name = key.replace(" ", "_")
	
	# IMPORTANT: Prevent keyboard buttons from stealing focus from input fields
	btn.focus_mode = Control.FOCUS_NONE
	
	# Set display text (will be updated dynamically for letters)
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
	if key in ROW_SHORTCUTS:
		btn.add_theme_color_override("font_color", Color(0.9, 0.7, 0.4))  # Orange for shortcuts
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
			_update_key_labels()
		"⇧R":
			is_shift_right = not is_shift_right
			_update_modifier_visuals()
			_update_key_labels()
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
			_update_key_labels()
		
		# Special keys
		"Esc":
			special_key.emit("escape")
		"Tab":
			special_key.emit("tab")
			_add_to_pending("\t")
		"⌫":
			special_key.emit("backspace")
			_handle_backspace()
		"Del":
			special_key.emit("delete")
			_handle_delete()
		"Enter":
			special_key.emit("enter")
			_add_to_pending("\n")
		"←":
			special_key.emit("arrow_left")
		"→":
			special_key.emit("arrow_right")
		"↑":
			special_key.emit("arrow_up")
		"↓":
			special_key.emit("arrow_down")
		"Home":
			special_key.emit("home")
		"End":
			special_key.emit("end")
		"Space":
			_add_to_pending(" ")
		
		# Shortcut keys
		"Undo":
			shortcut_action.emit("undo")
		"Redo":
			shortcut_action.emit("redo")
		"Find":
			shortcut_action.emit("find")
		"Replace":
			shortcut_action.emit("replace")
		"Copy":
			shortcut_action.emit("copy")
			_copy_selection()
		"Paste":
			shortcut_action.emit("paste")
			_paste_clipboard()
		"SelAll":
			shortcut_action.emit("select_all")
			_select_all()
		"Save":
			shortcut_action.emit("save")
		"🎤":
			shortcut_action.emit("mic_input")
		
		# Regular keys
		_:
			var char = _get_character(key)
			_add_to_pending(char)


func _add_to_pending(char: String) -> void:
	_pending_text += char
	_update_preview()
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
	_update_key_labels()


func _handle_backspace() -> void:
	if not _pending_text.is_empty():
		_pending_text = _pending_text.substr(0, _pending_text.length() - 1)
		_update_preview()


func _handle_delete() -> void:
	# In preview context, delete does same as backspace from end
	_handle_backspace()


func _copy_selection() -> void:
	if _selection_start >= 0 and _selection_end >= 0 and _selection_start != _selection_end:
		var start = mini(_selection_start, _selection_end)
		var end = maxi(_selection_start, _selection_end)
		var selected_text = _pending_text.substr(start, end - start)
		DisplayServer.clipboard_set(selected_text)


func _paste_clipboard() -> void:
	var clipboard_text = DisplayServer.clipboard_get()
	if not clipboard_text.is_empty():
		_pending_text += clipboard_text
		_update_preview()
		text_input.emit(clipboard_text)


func _select_all() -> void:
	if _text_preview and not _pending_text.is_empty():
		_selection_start = 0
		_selection_end = _pending_text.length()
		_text_preview.select_all()


func _get_character(key: String) -> String:
	var is_shifted = is_shift_left or is_shift_right
	
	# Check for shift mappings (symbols)
	if is_shifted and SHIFT_MAP.has(key):
		return SHIFT_MAP[key]
	
	# Letters
	if key.length() == 1 and key >= "A" and key <= "Z":
		if is_shifted or is_caps_lock:
			return key.to_upper()
		else:
			return key.to_lower()
	
	return key


func _clear_shift() -> void:
	if not is_caps_lock:
		is_shift_left = false
		is_shift_right = false


func _update_key_labels() -> void:
	"""Update key button labels based on current shift/caps state."""
	var is_uppercase = is_shift_left or is_shift_right or is_caps_lock
	
	# Update letter keys
	for letter in _letter_buttons:
		var btn: Button = _letter_buttons[letter]
		if is_uppercase:
			btn.text = letter.to_upper()
		else:
			btn.text = letter.to_lower()
	
	# Update symbol keys (only when shifted, not caps lock)
	var is_shifted = is_shift_left or is_shift_right
	for symbol in _symbol_buttons:
		var btn: Button = _symbol_buttons[symbol]
		if is_shifted and SHIFT_MAP.has(symbol):
			btn.text = SHIFT_MAP[symbol]
		else:
			btn.text = symbol


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


## Get the current pending text
func get_pending_text() -> String:
	return _pending_text


## Set the pending text programmatically
func set_pending_text(text: String) -> void:
	_pending_text = text
	_update_preview()


## Clear the pending text
func clear_pending_text() -> void:
	_pending_text = ""
	_update_preview()


## Simulate a key press programmatically
func simulate_key(key: String) -> void:
	_on_key_pressed(key)
