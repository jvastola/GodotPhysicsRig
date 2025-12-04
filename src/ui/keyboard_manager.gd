extends Node
## KeyboardManager - Autoload singleton script (no class_name needed)

## KeyboardManager - Global singleton to track focused input controls
## Enables the 3D virtual keyboard to route input to the active control

signal focus_changed(control: Control, viewport: SubViewport)
signal focus_cleared()

# Currently focused input control
var _focused_control: Control = null
var _focused_viewport: SubViewport = null

# Static instance for global access
static var instance: KeyboardManager = null


func _ready() -> void:
	instance = self


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if instance == self:
			instance = null


## Register an input control to be tracked for focus
## Call this when creating LineEdit, TextEdit, CodeEdit controls
func register_control(control: Control, viewport: SubViewport = null) -> void:
	if not control:
		return
	
	# Connect to focus signals
	if not control.focus_entered.is_connected(_on_control_focus_entered.bind(control, viewport)):
		control.focus_entered.connect(_on_control_focus_entered.bind(control, viewport))
	
	if not control.focus_exited.is_connected(_on_control_focus_exited.bind(control)):
		control.focus_exited.connect(_on_control_focus_exited.bind(control))
	
	# Handle tree exit to clean up
	if not control.tree_exiting.is_connected(_on_control_tree_exiting.bind(control)):
		control.tree_exiting.connect(_on_control_tree_exiting.bind(control))


## Unregister a control from focus tracking
func unregister_control(control: Control) -> void:
	if not control:
		return
	
	if control.focus_entered.is_connected(_on_control_focus_entered):
		control.focus_entered.disconnect(_on_control_focus_entered)
	
	if control.focus_exited.is_connected(_on_control_focus_exited):
		control.focus_exited.disconnect(_on_control_focus_exited)
	
	if _focused_control == control:
		clear_focus()


## Set focus to a specific control programmatically
func set_focus(control: Control, viewport: SubViewport = null) -> void:
	if control == _focused_control:
		return
	
	_focused_control = control
	_focused_viewport = viewport
	
	if control:
		focus_changed.emit(control, viewport)
		print("KeyboardManager: Focus set to ", control.name)
	else:
		focus_cleared.emit()


## Clear the current focus
func clear_focus() -> void:
	if _focused_control:
		_focused_control = null
		_focused_viewport = null
		focus_cleared.emit()
		print("KeyboardManager: Focus cleared")


## Get the currently focused control
func get_focused_control() -> Control:
	return _focused_control


## Get the viewport containing the focused control
func get_focused_viewport() -> SubViewport:
	return _focused_viewport


## Check if any control is focused
func has_focus() -> bool:
	return _focused_control != null and is_instance_valid(_focused_control)


## Send text input to the focused control
func send_text(character: String) -> void:
	if not has_focus():
		return
	
	if _focused_control is LineEdit:
		var line_edit := _focused_control as LineEdit
		var pos = line_edit.caret_column
		line_edit.text = line_edit.text.substr(0, pos) + character + line_edit.text.substr(pos)
		line_edit.caret_column = pos + character.length()
	elif _focused_control is TextEdit:
		var text_edit := _focused_control as TextEdit
		text_edit.insert_text_at_caret(character)
	elif _focused_control is CodeEdit:
		var code_edit := _focused_control as CodeEdit
		code_edit.insert_text_at_caret(character)


## Send a special key action to the focused control
func send_special_key(key_name: String) -> void:
	if not has_focus():
		return
	
	match key_name:
		"backspace":
			_handle_backspace()
		"enter":
			_handle_enter()
		"arrow_left":
			_handle_arrow_left()
		"arrow_right":
			_handle_arrow_right()
		"arrow_up":
			_handle_arrow_up()
		"arrow_down":
			_handle_arrow_down()
		"tab":
			_handle_tab()
		"escape":
			clear_focus()


func _handle_backspace() -> void:
	if _focused_control is LineEdit:
		var line_edit := _focused_control as LineEdit
		var pos = line_edit.caret_column
		if pos > 0:
			line_edit.text = line_edit.text.substr(0, pos - 1) + line_edit.text.substr(pos)
			line_edit.caret_column = pos - 1
	elif _focused_control is TextEdit or _focused_control is CodeEdit:
		var text_edit := _focused_control as TextEdit
		text_edit.backspace()


func _handle_enter() -> void:
	if _focused_control is LineEdit:
		var line_edit := _focused_control as LineEdit
		line_edit.text_submitted.emit(line_edit.text)
	elif _focused_control is TextEdit or _focused_control is CodeEdit:
		var text_edit := _focused_control as TextEdit
		text_edit.insert_text_at_caret("\n")


func _handle_arrow_left() -> void:
	if _focused_control is LineEdit:
		var line_edit := _focused_control as LineEdit
		if line_edit.caret_column > 0:
			line_edit.caret_column -= 1
	elif _focused_control is TextEdit or _focused_control is CodeEdit:
		# Let the text edit handle arrow keys via input event
		pass


func _handle_arrow_right() -> void:
	if _focused_control is LineEdit:
		var line_edit := _focused_control as LineEdit
		if line_edit.caret_column < line_edit.text.length():
			line_edit.caret_column += 1


func _handle_arrow_up() -> void:
	# Only relevant for multiline text controls
	pass


func _handle_arrow_down() -> void:
	# Only relevant for multiline text controls
	pass


func _handle_tab() -> void:
	if _focused_control is TextEdit or _focused_control is CodeEdit:
		var text_edit := _focused_control as TextEdit
		text_edit.insert_text_at_caret("\t")


func _on_control_focus_entered(control: Control, viewport: SubViewport) -> void:
	set_focus(control, viewport)


func _on_control_focus_exited(control: Control) -> void:
	if _focused_control == control:
		# Small delay to allow focus to transfer to another control
		await get_tree().process_frame
		if _focused_control == control:
			clear_focus()


func _on_control_tree_exiting(control: Control) -> void:
	unregister_control(control)
