extends PanelContainer
class_name ScriptEditorUI

# Script Editor UI - Editable code viewer with syntax highlighting
# Works with KeyboardFullUI for text input
# Supports: Save, Undo, Redo, Copy, Paste, Drag-Select

signal script_opened(script_path: String)
signal script_modified(script_path: String)
signal script_saved(script_path: String)

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var path_label: Label = $MarginContainer/VBoxContainer/PathLabel
@onready var code_edit: CodeEdit = $MarginContainer/VBoxContainer/CodeEdit
@onready var no_script_label: Label = $MarginContainer/VBoxContainer/NoScriptLabel

var _current_script_path: String = ""
var _current_script: Script = null
var _is_modified: bool = false
var _original_content: String = ""  # Track original for comparison

# Static instance for global access
static var instance: ScriptEditorUI = null


func _ready() -> void:
	instance = self
	_setup_code_edit()
	_show_no_script()
	
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
	hl.add_color_region("@", " ", Color(0.9, 0.6, 0.4), true)
	hl.add_color_region("@", "\n", Color(0.9, 0.6, 0.4), true)
	
	# Comments
	hl.add_color_region("#", "\n", comment_color, true)
	hl.add_color_region("##", "\n", Color(0.55, 0.55, 0.6), true)
	
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
	if not code_edit or not code_edit.has_focus():
		return
	
	code_edit.insert_text_at_caret(character)


func _on_keyboard_special(key_name: String) -> void:
	if not code_edit or not code_edit.has_focus():
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
			code_edit.set_caret_column(col + 1)
		"arrow_up":
			var line = code_edit.get_caret_line()
			if line > 0:
				code_edit.set_caret_line(line - 1)
		"arrow_down":
			var line = code_edit.get_caret_line()
			code_edit.set_caret_line(line + 1)


func _connect_to_keyboard_shortcuts() -> void:
	if KeyboardFullUI.instance:
		if not KeyboardFullUI.instance.shortcut_action.is_connected(_on_shortcut_action):
			KeyboardFullUI.instance.shortcut_action.connect(_on_shortcut_action)
			print("ScriptEditorUI: Connected to keyboard shortcuts")


func _on_shortcut_action(action: String) -> void:
	if not code_edit or not code_edit.has_focus():
		return
	
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
	
	# 2. Save to disk
	var file = FileAccess.open(_current_script_path, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
		
		# Update state
		_original_content = content
		_is_modified = false
		if title_label and title_label.text.ends_with(" *"):
			title_label.text = title_label.text.substr(0, title_label.text.length() - 2)
		
		print("ScriptEditorUI: Saved script to ", _current_script_path)
		script_saved.emit(_current_script_path)
		
		# Show visual feedback (optional)
		if title_label:
			var original_color = title_label.get_theme_color("font_color")
			title_label.add_theme_color_override("font_color", Color.GREEN)
			var tween = create_tween()
			tween.tween_interval(0.5)
			tween.tween_callback(func(): title_label.add_theme_color_override("font_color", original_color))
	else:
		push_error("ScriptEditorUI: Failed to open file for writing: ", _current_script_path)


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
	
	if not ResourceLoader.exists(path):
		_show_no_script()
		push_warning("ScriptEditorUI: Script not found: ", path)
		return
	
	var script = load(path)
	if not script is Script:
		_show_no_script()
		return
	
	_current_script_path = path
	_current_script = script
	_is_modified = false
	_display_script()
	script_opened.emit(path)


## Open and display a script resource directly
func open_script_resource(script: Script) -> void:
	if not script:
		_show_no_script()
		return
	
	_current_script = script
	_current_script_path = script.resource_path
	_is_modified = false
	_display_script()
	script_opened.emit(_current_script_path)


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
		var filename = _current_script_path.get_file()
		title_label.text = "📝 " + filename
	
	if path_label:
		path_label.text = _current_script_path
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
