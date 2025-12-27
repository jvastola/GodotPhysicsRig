extends PanelContainer
class_name ScriptEditorUI

# Script Editor UI - Editable code viewer with syntax highlighting
# Works with KeyboardFullUI for text input
# Supports: Save, Undo, Redo, Copy, Paste, Drag-Select

signal script_opened(script_path: String)
signal script_modified(script_path: String)
signal script_saved(script_path: String)
signal close_requested

@onready var title_label: Label = $MarginContainer/VBoxContainer/HeaderHBox/TitleLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderHBox/CloseButton
@onready var save_button: Button = $MarginContainer/VBoxContainer/HeaderHBox/SaveButton
@onready var path_label: Label = $MarginContainer/VBoxContainer/PathLabel
@onready var code_edit: CodeEdit = $MarginContainer/VBoxContainer/CodeEdit
@onready var no_script_label: Label = $MarginContainer/VBoxContainer/NoScriptLabel

var _current_script_path: String = ""
var _current_user_script_path: String = ""
var _current_script: Script = null
var _is_modified: bool = false
var _original_content: String = ""  # Track original for comparison

# Static instance for global access
static var instance: ScriptEditorUI = null


func _ready() -> void:
	instance = self
	_setup_code_edit()
	_show_no_script()
	
	if save_button:
		save_button.pressed.connect(save_script)
	
	if close_button:
		close_button.pressed.connect(func(): close_requested.emit())
	
	# Connect to keyboard if available
	call_deferred("_connect_to_keyboard")
	call_deferred("_connect_to_keyboard_shortcuts")


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if instance == self:
			instance = null


func _setup_code_edit() -> void:
	if not code_edit:
		return
	
	# Basic settings
	code_edit.editable = true
	code_edit.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	code_edit.scroll_smooth = true
	code_edit.minimap_draw = false
	code_edit.gutters_draw_line_numbers = true
	code_edit.gutters_draw_fold_gutter = true
	
	# Add GDScript syntax highlighter
	var highlighter = CodeHighlighter.new()
	_setup_gdscript_highlighter(highlighter)
	code_edit.syntax_highlighter = highlighter
	
	# Style
	code_edit.add_theme_font_size_override("font_size", 12)
	code_edit.add_theme_color_override("background_color", Color(0.06, 0.065, 0.08))
	code_edit.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	code_edit.add_theme_color_override("line_number_color", Color(0.4, 0.45, 0.5))
	code_edit.add_theme_color_override("caret_color", Color(1.0, 1.0, 1.0))
	code_edit.add_theme_color_override("selection_color", Color(0.2, 0.4, 0.7, 0.5))
	code_edit.add_theme_color_override("current_line_color", Color(0.15, 0.17, 0.2))
	
	# Connect signals
	code_edit.text_changed.connect(_on_text_changed)


func _setup_gdscript_highlighter(hl: CodeHighlighter) -> void:
	# Colors
	var keyword_color = Color(0.8, 0.5, 0.8)      # Purple
	var string_color = Color(0.6, 0.9, 0.6)       # Green
	var comment_color = Color(0.5, 0.5, 0.55)     # Gray
	var number_color = Color(0.6, 0.85, 1.0)      # Light blue
	var function_color = Color(0.9, 0.85, 0.5)    # Yellow
	var type_color = Color(0.5, 0.9, 0.9)         # Cyan
	var member_color = Color(0.9, 0.7, 0.5)       # Orange
	
	hl.number_color = number_color
	hl.symbol_color = Color(0.85, 0.85, 0.9)
	hl.function_color = function_color
	hl.member_variable_color = member_color
	
	# Keywords
	var keywords = [
		"if", "elif", "else", "for", "while", "match", "break", "continue", "pass",
		"return", "class", "class_name", "extends", "is", "in", "as", "self", "signal",
		"func", "static", "const", "enum", "var", "onready", "export", "tool",
		"await", "true", "false", "null", "and", "or", "not", "super"
	]
	for kw in keywords:
		hl.add_keyword_color(kw, keyword_color)
	
	# Types
	var types = [
		"void", "bool", "int", "float", "String", "Vector2", "Vector2i", "Vector3",
		"Vector3i", "Vector4", "Color", "Rect2", "Transform2D", "Transform3D",
		"Basis", "Quaternion", "AABB", "Plane", "Array", "Dictionary", "Callable",
		"Signal", "NodePath", "RID", "Object", "Node", "Node2D", "Node3D", "Control",
		"Resource", "RefCounted", "PackedScene"
	]
	for t in types:
		hl.add_keyword_color(t, type_color)
	
	# Annotations
	# Avoid color regions that end on whitespace/newline (Godot requires a symbol).
	# Annotation-like keywords are already colored via the keyword list above.
	
	# Comments
	hl.add_color_region("#", "", comment_color, true)
	hl.add_color_region("##", "", Color(0.55, 0.55, 0.6), true)
	
	# Strings
	hl.add_color_region("\"", "\"", string_color, false)
	hl.add_color_region("'", "'", string_color, false)
	hl.add_color_region("\"\"\"", "\"\"\"", string_color, false)


func _connect_to_keyboard() -> void:
	if KeyboardFullUI.instance:
		if not KeyboardFullUI.instance.text_input.is_connected(_on_keyboard_input):
			KeyboardFullUI.instance.text_input.connect(_on_keyboard_input)
		if not KeyboardFullUI.instance.special_key.is_connected(_on_keyboard_special):
			KeyboardFullUI.instance.special_key.connect(_on_keyboard_special)
		print("ScriptEditorUI: Connected to keyboard")


func _on_keyboard_input(character: String) -> void:
	if not code_edit or not code_edit.visible:
		return
	
	# In VR, accept input if editor is visible and has a script loaded
	if _current_script == null:
		return
	
	code_edit.insert_text_at_caret(character)


func _on_keyboard_special(key_name: String) -> void:
	if not code_edit or not code_edit.visible:
		return
	
	# In VR, the CodeEdit may not have strict focus when using virtual keyboard
	# Accept input if the editor is visible and has a script loaded
	if _current_script == null:
		return
	
	match key_name:
		"backspace":
			code_edit.backspace()
		"enter":
			code_edit.insert_text_at_caret("\n")
		"tab":
			code_edit.insert_text_at_caret("\t")
		"arrow_left":
			var col = code_edit.get_caret_column()
			if col > 0:
				code_edit.set_caret_column(col - 1)
		"arrow_right":
			var col = code_edit.get_caret_column()
			var line = code_edit.get_caret_line()
			var line_length = code_edit.get_line(line).length()
			if col < line_length:
				code_edit.set_caret_column(col + 1)
		"arrow_up":
			var line = code_edit.get_caret_line()
			if line > 0:
				code_edit.set_caret_line(line - 1)
		"arrow_down":
			var line = code_edit.get_caret_line()
			if line < code_edit.get_line_count() - 1:
				code_edit.set_caret_line(line + 1)
		"home":
			code_edit.set_caret_column(0)
		"end":
			var line = code_edit.get_caret_line()
			var line_length = code_edit.get_line(line).length()
			code_edit.set_caret_column(line_length)
		"delete":
			# Delete character at caret position
			var line = code_edit.get_caret_line()
			var col = code_edit.get_caret_column()
			var line_text = code_edit.get_line(line)
			if col < line_text.length():
				code_edit.select(line, col, line, col + 1)
				code_edit.delete_selection()


func _connect_to_keyboard_shortcuts() -> void:
	if KeyboardFullUI.instance:
		if not KeyboardFullUI.instance.shortcut_action.is_connected(_on_shortcut_action):
			KeyboardFullUI.instance.shortcut_action.connect(_on_shortcut_action)
			print("ScriptEditorUI: Connected to keyboard shortcuts")


func _on_shortcut_action(action: String) -> void:
	# Relaxed focus check: allow shortcuts if editor is visible
	if not code_edit or not code_edit.visible:
		return
	
	# Optional: Check if we are really the active window/control if needed
	# but for VR keyboard interaction, strictly requiring focus can be flaky
	# if the user clicked the keyboard buttons.
	
	match action:
		"undo":
			code_edit.undo()
		"redo":
			code_edit.redo()
		"copy":
			code_edit.copy()
		"paste":
			code_edit.paste()
		"cut":
			code_edit.cut()
		"select_all":
			code_edit.select_all()
		"save":
			save_script()


func save_script() -> void:
	if not _current_script or _current_script_path.is_empty():
		return
	
	var content = code_edit.text
	
	# 1. Update the script resource in memory
	_current_script.source_code = content
	var err = _current_script.reload()
	if err != OK:
		push_error("ScriptEditorUI: Failed to reload script: %s" % err)
	
	# 2. Save to disk (user repo copy)
	var target_path := _ensure_user_script_path(_current_script_path)
	var file = FileAccess.open(target_path, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
		
		# Update state
		_original_content = content
		_is_modified = false
		if title_label and title_label.text.ends_with(" *"):
			title_label.text = title_label.text.substr(0, title_label.text.length() - 2)
		
		print("ScriptEditorUI: Saved script to ", target_path)
		_current_user_script_path = target_path
		script_saved.emit(target_path)
		_notify_version_tracker(target_path)
		
		# Show visual feedback (optional)
		if title_label:
			var original_color = title_label.get_theme_color("font_color")
			title_label.add_theme_color_override("font_color", Color.GREEN)
			var tween = create_tween()
			tween.tween_interval(0.5)
			tween.tween_callback(func(): title_label.add_theme_color_override("font_color", original_color))
	else:
		push_error("ScriptEditorUI: Failed to open file for writing: %s" % target_path)
		# Still surface change to tracker so user sees pending work
		_notify_version_tracker(target_path)


func _on_text_changed() -> void:
	if _current_script:
		_is_modified = true
		if title_label and not title_label.text.ends_with("*"):
			title_label.text += " *"
		script_modified.emit(_current_script_path)


## Open and display a script by path
func open_script(path: String) -> void:
	if path.is_empty():
		_show_no_script()
		return
	
	var user_path := _ensure_user_script_path(path)
	if not ResourceLoader.exists(user_path):
		_show_no_script()
		push_warning("ScriptEditorUI: Script not found: ", user_path)
		return
	
	var script = load(user_path)
	if not script is Script:
		_show_no_script()
		return
	
	_current_script_path = path
	_current_user_script_path = user_path
	_current_script = script
	_is_modified = false
	_display_script()
	script_opened.emit(user_path)


## Open and display a script resource directly
func open_script_resource(script: Script) -> void:
	if not script:
		_show_no_script()
		return
	
	_current_script = script
	_current_script_path = script.resource_path
	_current_user_script_path = _ensure_user_script_path(_current_script_path)
	_is_modified = false
	_display_script()
	script_opened.emit(_current_user_script_path)


## Static helper to open a script from anywhere
static func view_script(path: String) -> void:
	if instance:
		instance.open_script(path)


func _show_no_script() -> void:
	_current_script = null
	_current_script_path = ""
	_is_modified = false
	
	if title_label:
		title_label.text = "📝 Script Editor"
	if path_label:
		path_label.text = ""
		path_label.visible = false
	if code_edit:
		code_edit.visible = false
	if no_script_label:
		no_script_label.visible = true


func _display_script() -> void:
	if not _current_script:
		return
	
	# Update title
	if title_label:
		var filename = _current_user_script_path.get_file() if not _current_user_script_path.is_empty() else _current_script_path.get_file()
		title_label.text = "📝 " + filename
	
	if path_label:
		path_label.text = _current_user_script_path if not _current_user_script_path.is_empty() else _current_script_path
		path_label.visible = true
	
	# Show code edit, hide no-script label
	if code_edit:
		code_edit.visible = true
	if no_script_label:
		no_script_label.visible = false
	
	# Get script source code
	var source_code = _current_script.source_code
	if source_code.is_empty():
		if code_edit:
			code_edit.text = "# (Script source not available)"
		return
	
	if code_edit:
		code_edit.text = source_code
		code_edit.set_caret_line(0)
		code_edit.set_caret_column(0)
		_original_content = source_code


func _notify_version_tracker(script_path: String) -> void:
	if script_path.is_empty():
		return
	var localized := ProjectSettings.localize_path(script_path)
	var panel := _get_git_panel()
	if panel:
		panel.stage_paths_and_refresh([localized])
		_refresh_git_panel(panel)
	else:
		# Fallback: stage silently so it appears when panel opens
		var git := GitService.new()
		git.stage_paths([localized])
		_refresh_git_panel(_get_git_panel())  # try again if panel loaded after staging


func _get_git_panel() -> GitPanelUI:
	if GitPanelUI.instance:
		return GitPanelUI.instance
	if get_tree():
		var node = get_tree().get_first_node_in_group("git_panel")
		if node and node is GitPanelUI:
			return node
	return null


func _refresh_git_panel(panel: GitPanelUI) -> void:
	if panel:
		panel.refresh_status()
		panel.refresh_history()


func _ensure_user_script_path(path: String) -> String:
	if path.is_empty():
		return path
	var user_path := _to_user_repo_path(path)
	if not FileAccess.file_exists(user_path) and FileAccess.file_exists(path):
		_make_dir_recursive(user_path.get_base_dir())
		var bytes := FileAccess.get_file_as_bytes(path)
		var f := FileAccess.open(user_path, FileAccess.WRITE)
		if f:
			f.store_buffer(bytes)
	return user_path


func _to_user_repo_path(path: String) -> String:
	if path.begins_with("user://workspace_repo/"):
		return path
	if path.begins_with("res://"):
		var relative := path.substr("res://".length())
		return "user://workspace_repo/" + relative
	# Already user:// but not in workspace; keep as-is
	return path


func _make_dir_recursive(path: String) -> void:
	var d := DirAccess.open("user://")
	if d:
		d.make_dir_recursive(path)


## Get the current script content
func get_content() -> String:
	if code_edit:
		return code_edit.text
	return ""


## Check if script has been modified
func is_modified() -> bool:
	return _is_modified


## Save changes back to the script (runtime and disk)
func apply_changes() -> bool:
	save_script()
	return true


## Focus the code editor
func focus_editor() -> void:
	if code_edit:
		code_edit.grab_focus()


## Set cursor position
func set_cursor(line: int, column: int) -> void:
	if code_edit:
		code_edit.set_caret_line(line)
		code_edit.set_caret_column(column)
