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

# Track whether we've attached right-click listeners to a control
var _context_hooked: Dictionary = {}

# Active popup menu for "bring keyboard" action
var _active_popup: PopupMenu = null


func _ready() -> void:
	instance = self
	# Watch the scene tree so any input-capable Control gets a right-click hook
	_start_watching_tree()
	_scan_existing_controls()


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


# -----------------------------------------------------------------------------
# Context menu support to summon keyboard on right-click
# -----------------------------------------------------------------------------

func _start_watching_tree() -> void:
	var tree := get_tree()
	if not tree:
		return
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	if not tree.node_removed.is_connected(_on_node_removed):
		tree.node_removed.connect(_on_node_removed)


func _scan_existing_controls() -> void:
	var root := get_tree().get_root()
	if not root:
		return
	_scan_node_for_inputs(root)


func _scan_node_for_inputs(node: Node) -> void:
	if node is Control:
		_try_attach_context_listener(node)
	for child in node.get_children():
		_scan_node_for_inputs(child)


func _on_node_added(node: Node) -> void:
	if node is Control:
		_try_attach_context_listener(node)


func _on_node_removed(node: Node) -> void:
	if node is Control and _context_hooked.has(node):
		_context_hooked.erase(node)


func _try_attach_context_listener(control: Control) -> void:
	# Only attach to controls that can accept text input
	if not _is_input_candidate(control):
		return
	if _context_hooked.get(control, false):
		return
	_context_hooked[control] = true
	# Listen for right-click to offer keyboard summon
	control.gui_input.connect(_on_control_gui_input.bind(control))


func _is_input_candidate(control: Control) -> bool:
	return control is LineEdit or control is TextEdit or control is CodeEdit or control is SpinBox


func _resolve_input_target(control: Control) -> Control:
	if control is SpinBox:
		var sb := control as SpinBox
		if sb.has_method("get_line_edit"):
			var le: LineEdit = sb.get_line_edit()
			if le:
				return le
	return control


func _is_control_editable(control: Control) -> bool:
	if control is LineEdit:
		var le := control as LineEdit
		return le.editable
	if control is TextEdit or control is CodeEdit:
		var te := control as TextEdit
		return te.editable
	if control is SpinBox:
		var le2: LineEdit = (control as SpinBox).get_line_edit()
		return le2 != null and le2.editable
	return true


func _on_control_gui_input(event: InputEvent, control: Control) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_RIGHT or not mb.pressed:
		return
	# Use the event position in the control's viewport; global_position is already
	# in viewport space for UI events.
	var popup_pos: Vector2 = mb.global_position
	if popup_pos == Vector2.ZERO:
		popup_pos = mb.position
	_show_keyboard_popup(control, popup_pos)
	# Stop default context menus so ours is always visible
	control.accept_event()


func _show_keyboard_popup(control: Control, global_pos: Vector2) -> void:
	var viewport: SubViewport = control.get_viewport()
	if not viewport:
		return
	if _active_popup and is_instance_valid(_active_popup):
		_active_popup.queue_free()
		_active_popup = null
	
	var popup := PopupMenu.new()
	popup.name = "KeyboardSummonContext"
	popup.add_item("Bring keyboard here", 0)
	
	var target := _resolve_input_target(control)
	var has_target := target != null and is_instance_valid(target) and _is_control_editable(target)
	popup.set_item_disabled(0, not has_target)
	
	popup.set_meta("target_control", target)
	popup.set_meta("target_viewport", viewport)
	popup.id_pressed.connect(_on_popup_id_pressed.bind(popup))
	popup.popup_hide.connect(func(): _active_popup = null)
	
	viewport.add_child(popup)
	popup.position = global_pos
	popup.popup()
	_active_popup = popup


func _on_popup_id_pressed(id: int, popup: PopupMenu) -> void:
	if id == 0:
		var control: Control = popup.get_meta("target_control")
		var viewport: SubViewport = popup.get_meta("target_viewport")
		_focus_control_and_summon_keyboard(control, viewport)
	
	if is_instance_valid(popup):
		popup.queue_free()
	_active_popup = null


func _focus_control_and_summon_keyboard(control: Control, viewport: SubViewport) -> void:
	if not control or not is_instance_valid(control):
		return
	register_control(control, viewport)
	control.grab_focus()
	
	if control is LineEdit:
		var le := control as LineEdit
		le.caret_column = le.text.length()
	elif control is TextEdit or control is CodeEdit:
		var te := control as TextEdit
		var line := te.get_caret_line()
		var column := te.get_line(line).length()
		te.set_caret_line(line, true, true)
		te.set_caret_column(column, true)
	
	set_focus(control, viewport)
	_summon_keyboard_to_player()


func _summon_keyboard_to_player() -> void:
	var scene := get_tree().get_current_scene()
	if not scene:
		return
	var keyboard_node: Node3D = scene.get_node_or_null("KeyboardFullViewport3D") as Node3D
	if not keyboard_node:
		return
	
	# Find the XR camera to position keyboard in front of the user
	var xr_player: Node = get_tree().get_first_node_in_group("xr_player")
	if not xr_player:
		xr_player = get_tree().root.find_child("XRPlayer", true, false)
	var camera: XRCamera3D = null
	if xr_player and xr_player.has_node("PlayerBody/XROrigin3D/XRCamera3D"):
		camera = xr_player.get_node("PlayerBody/XROrigin3D/XRCamera3D") as XRCamera3D
	if not camera:
		return
	
	var cam_tf := camera.global_transform
	var forward := -cam_tf.basis.z.normalized()
	var target_origin := cam_tf.origin + forward * 1.2 + Vector3(0, 0.05, 0)
	
	var xf := keyboard_node.global_transform
	var original_scale := xf.basis.get_scale()
	xf.origin = target_origin
	
	var dir := cam_tf.origin - target_origin
	dir.y = 0
	if dir.length_squared() > 0.0001:
		dir = dir.normalized()
		# Keyboard mesh faces +Z, so orient +Z toward camera (invert dir)
		var look_basis := Basis().looking_at(-dir, Vector3.UP)
		# Preserve existing scale so we don't blow up the keyboard size
		look_basis = look_basis.scaled(original_scale)
		xf.basis = look_basis
	
	keyboard_node.global_transform = xf
	if keyboard_node.has_method("set_interactive"):
		keyboard_node.call("set_interactive", true)
