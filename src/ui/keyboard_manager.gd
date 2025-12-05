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
		"delete":
			_handle_delete()
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
		"home":
			_handle_home()
		"end":
			_handle_end()


## Send a shortcut action to the focused control (e.g., copy, paste, undo)
func send_shortcut(action: String) -> void:
	if not has_focus():
		return
	
	match action:
		"copy":
			_handle_copy()
		"paste":
			_handle_paste()
		"cut":
			_handle_cut()
		"undo":
			_handle_undo()
		"redo":
			_handle_redo()
		"select_all":
			_handle_select_all()
		"find":
			# Emit signal for UI to handle find dialog
			pass
		"replace":
			# Emit signal for UI to handle replace dialog
			pass
		"save":
			# Emit signal for save action
			pass


func _handle_delete() -> void:
	if _focused_control is LineEdit:
		var line_edit := _focused_control as LineEdit
		var pos = line_edit.caret_column
		if pos < line_edit.text.length():
			line_edit.text = line_edit.text.substr(0, pos) + line_edit.text.substr(pos + 1)
	elif _focused_control is TextEdit or _focused_control is CodeEdit:
		var text_edit := _focused_control as TextEdit
		# Use cut_to_clipboard with no selection effectively deletes at caret
		if text_edit.has_selection():
			text_edit.delete_selection()


func _handle_home() -> void:
	if _focused_control is LineEdit:
		var line_edit := _focused_control as LineEdit
		line_edit.caret_column = 0
	elif _focused_control is TextEdit or _focused_control is CodeEdit:
		var text_edit := _focused_control as TextEdit
		text_edit.set_caret_column(0)


func _handle_end() -> void:
	if _focused_control is LineEdit:
		var line_edit := _focused_control as LineEdit
		line_edit.caret_column = line_edit.text.length()
	elif _focused_control is TextEdit or _focused_control is CodeEdit:
		var text_edit := _focused_control as TextEdit
		var line = text_edit.get_caret_line()
		text_edit.set_caret_column(text_edit.get_line(line).length())


func _handle_copy() -> void:
	if _focused_control is LineEdit:
		var line_edit := _focused_control as LineEdit
		if line_edit.has_selection():
			var selected = line_edit.get_selected_text()
			DisplayServer.clipboard_set(selected)
	elif _focused_control is TextEdit or _focused_control is CodeEdit:
		var text_edit := _focused_control as TextEdit
		if text_edit.has_selection():
			var selected = text_edit.get_selected_text()
			DisplayServer.clipboard_set(selected)


func _handle_paste() -> void:
	var clipboard = DisplayServer.clipboard_get()
	if clipboard.is_empty():
		return
	
	if _focused_control is LineEdit:
		var line_edit := _focused_control as LineEdit
		var pos = line_edit.caret_column
		if line_edit.has_selection():
			line_edit.delete_text(line_edit.get_selection_from_column(), line_edit.get_selection_to_column())
			pos = line_edit.caret_column
		line_edit.text = line_edit.text.substr(0, pos) + clipboard + line_edit.text.substr(pos)
		line_edit.caret_column = pos + clipboard.length()
	elif _focused_control is TextEdit or _focused_control is CodeEdit:
		var text_edit := _focused_control as TextEdit
		text_edit.insert_text_at_caret(clipboard)


func _handle_cut() -> void:
	_handle_copy()
	if _focused_control is LineEdit:
		var line_edit := _focused_control as LineEdit
		if line_edit.has_selection():
			line_edit.delete_text(line_edit.get_selection_from_column(), line_edit.get_selection_to_column())
	elif _focused_control is TextEdit or _focused_control is CodeEdit:
		var text_edit := _focused_control as TextEdit
		if text_edit.has_selection():
			text_edit.delete_selection()


func _handle_undo() -> void:
	if _focused_control is TextEdit or _focused_control is CodeEdit:
		var text_edit := _focused_control as TextEdit
		text_edit.undo()


func _handle_redo() -> void:
	if _focused_control is TextEdit or _focused_control is CodeEdit:
		var text_edit := _focused_control as TextEdit
		text_edit.redo()


func _handle_select_all() -> void:
	if _focused_control is LineEdit:
		var line_edit := _focused_control as LineEdit
		line_edit.select_all()
	elif _focused_control is TextEdit or _focused_control is CodeEdit:
		var text_edit := _focused_control as TextEdit
		text_edit.select_all()


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
