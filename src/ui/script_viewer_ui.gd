extends PanelContainer
class_name ScriptViewerUI

# Script Viewer UI - Displays GDScript source code with syntax highlighting
# Works with NodeInspectorUI to view scripts attached to selected nodes

signal script_opened(script_path: String)

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var path_label: Label = $MarginContainer/VBoxContainer/PathLabel
@onready var scroll_container: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer
@onready var code_label: RichTextLabel = $MarginContainer/VBoxContainer/ScrollContainer/CodeLabel
@onready var no_script_label: Label = $MarginContainer/VBoxContainer/NoScriptLabel
@onready var line_numbers: RichTextLabel = $MarginContainer/VBoxContainer/ScrollContainer/LineNumbers

var _current_script_path: String = ""
var _current_script: Script = null

# Syntax highlighting colors
const KEYWORD_COLOR = Color(0.8, 0.5, 0.8)      # Purple for keywords
const STRING_COLOR = Color(0.6, 0.9, 0.6)       # Green for strings
const COMMENT_COLOR = Color(0.5, 0.5, 0.55)     # Gray for comments
const NUMBER_COLOR = Color(0.6, 0.85, 1.0)      # Light blue for numbers
const FUNCTION_COLOR = Color(0.9, 0.85, 0.5)   # Yellow for functions
const CLASS_COLOR = Color(0.5, 0.9, 0.9)        # Cyan for classes/types
const ANNOTATION_COLOR = Color(0.9, 0.6, 0.4)   # Orange for annotations
const DEFAULT_COLOR = Color(0.9, 0.9, 0.95)     # White for default text

# GDScript keywords
const KEYWORDS = [
	"if", "elif", "else", "for", "while", "match", "break", "continue", "pass",
	"return", "class", "class_name", "extends", "is", "in", "as", "self", "signal",
	"func", "static", "const", "enum", "var", "onready", "export", "setget", "tool",
	"yield", "assert", "breakpoint", "preload", "await", "true", "false", "null",
	"and", "or", "not", "PI", "TAU", "INF", "NAN"
]

# Built-in types
const TYPES = [
	"void", "bool", "int", "float", "String", "Vector2", "Vector2i", "Vector3",
	"Vector3i", "Vector4", "Vector4i", "Color", "Rect2", "Rect2i", "Transform2D",
	"Transform3D", "Basis", "Quaternion", "AABB", "Plane", "PackedByteArray",
	"PackedInt32Array", "PackedInt64Array", "PackedFloat32Array", "PackedFloat64Array",
	"PackedStringArray", "PackedVector2Array", "PackedVector3Array", "PackedColorArray",
	"Array", "Dictionary", "Callable", "Signal", "NodePath", "RID", "Object", "Node",
	"Node2D", "Node3D", "Control", "Resource"
]

# Static instance for global access
static var instance: PanelContainer = null

# Search/goto line input
var _search_field: LineEdit = null
var _parent_viewport: SubViewport = null


func _ready() -> void:
	instance = self
	_show_no_script()
	_setup_search_field()
	_register_with_keyboard_manager()


func _setup_search_field() -> void:
	# Create search/goto line field after the title
	var vbox = $MarginContainer/VBoxContainer
	if not vbox:
		return
	
	var search_container = HBoxContainer.new()
	search_container.name = "SearchContainer"
	search_container.add_theme_constant_override("separation", 4)
	
	var search_label = Label.new()
	search_label.text = "🔍"
	search_label.add_theme_font_size_override("font_size", 12)
	search_container.add_child(search_label)
	
	_search_field = LineEdit.new()
	_search_field.name = "SearchField"
	_search_field.placeholder_text = "Go to line..."
	_search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_field.add_theme_font_size_override("font_size", 11)
	_search_field.custom_minimum_size.y = 24
	_search_field.text_submitted.connect(_on_search_submitted)
	search_container.add_child(_search_field)
	
	# Insert after title
	vbox.add_child(search_container)
	vbox.move_child(search_container, 1)


func _register_with_keyboard_manager() -> void:
	# Find parent viewport for context
	var parent = get_parent()
	while parent:
		if parent is SubViewport:
			_parent_viewport = parent
			break
		parent = parent.get_parent()
	
	# Use deferred to ensure KeyboardManager is ready
	call_deferred("_deferred_register")


func _deferred_register() -> void:
	if KeyboardManager and KeyboardManager.instance and _search_field:
		KeyboardManager.instance.register_control(_search_field, _parent_viewport)
		print("ScriptViewerUI: Registered search field with KeyboardManager")


func _on_search_submitted(text: String) -> void:
	# Parse line number and scroll to it
	if text.is_valid_int():
		var line_num = text.to_int()
		_scroll_to_line(line_num)
		_search_field.clear()


func _scroll_to_line(line: int) -> void:
	if not scroll_container or not code_label:
		return
	
	# Estimate line height and scroll position
	var font_size = 11
	var line_height = font_size + 4
	var target_scroll = max(0, (line - 5) * line_height)
	scroll_container.scroll_vertical = target_scroll


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if instance == self:
			instance = null


## Open and display a script by path
func open_script(path: String) -> void:
	if path.is_empty():
		_show_no_script()
		return
	
	# Load the script resource
	if not ResourceLoader.exists(path):
		_show_no_script()
		push_warning("ScriptViewerUI: Script not found: ", path)
		return
	
	var script = load(path)
	if not script is Script:
		_show_no_script()
		return
	
	_current_script_path = path
	_current_script = script
	_display_script()
	script_opened.emit(path)


## Open and display a script resource directly
func open_script_resource(script: Script) -> void:
	if not script:
		_show_no_script()
		return
	
	_current_script = script
	_current_script_path = script.resource_path
	_display_script()
	script_opened.emit(_current_script_path)


## Static helper to open a script from anywhere
static func view_script(path: String) -> void:
	if instance:
		instance.open_script(path)


func _show_no_script() -> void:
	_current_script = null
	_current_script_path = ""
	
	if title_label:
		title_label.text = "📜 Script Viewer"
	if path_label:
		path_label.text = ""
		path_label.visible = false
	if scroll_container:
		scroll_container.visible = false
	if no_script_label:
		no_script_label.visible = true


func _display_script() -> void:
	if not _current_script:
		return
	
	# Update title
	if title_label:
		var filename = _current_script_path.get_file()
		title_label.text = "📜 " + filename
	
	if path_label:
		path_label.text = _current_script_path
		path_label.visible = true
	
	# Show scroll container, hide no-script label
	if scroll_container:
		scroll_container.visible = true
	if no_script_label:
		no_script_label.visible = false
	
	# Get script source code
	var source_code = _current_script.source_code
	if source_code.is_empty():
		if code_label:
			code_label.text = "[color=#888888](Script source not available)[/color]"
		return
	
	# Apply syntax highlighting
	var highlighted = _highlight_gdscript(source_code)
	
	if code_label:
		code_label.text = highlighted
	
	# Generate line numbers
	if line_numbers:
		var lines = source_code.split("\n")
		var line_nums_text = ""
		for i in range(lines.size()):
			line_nums_text += "[color=#555555]%4d[/color]\n" % (i + 1)
		line_numbers.text = line_nums_text


func _highlight_gdscript(source: String) -> String:
	var lines = source.split("\n")
	var result = ""
	
	for line in lines:
		result += _highlight_line(line) + "\n"
	
	return result


func _highlight_line(line: String) -> String:
	var result = ""
	var i = 0
	var in_string = false
	var string_char = ""
	var in_comment = false
	
	while i < line.length():
		var c = line[i]
		
		# Check for comments
		if not in_string and c == "#":
			# Rest of line is comment
			var comment_text = line.substr(i)
			result += "[color=#%s]%s[/color]" % [COMMENT_COLOR.to_html(false), _escape_bbcode(comment_text)]
			break
		
		# Check for strings
		if not in_comment and (c == '"' or c == "'"):
			if not in_string:
				in_string = true
				string_char = c
				result += "[color=#%s]%s" % [STRING_COLOR.to_html(false), c]
			elif c == string_char:
				result += "%s[/color]" % c
				in_string = false
			else:
				result += c
			i += 1
			continue
		
		if in_string:
			result += _escape_bbcode(c)
			i += 1
			continue
		
		# Check for annotations (@export, @onready, etc)
		if c == "@":
			var word = _extract_word(line, i + 1)
			if word.length() > 0:
				result += "[color=#%s]@%s[/color]" % [ANNOTATION_COLOR.to_html(false), word]
				i += word.length() + 1
				continue
		
		# Check for words (keywords, types, identifiers)
		if _is_word_char(c):
			var word = _extract_word(line, i)
			
			if word in KEYWORDS:
				result += "[color=#%s]%s[/color]" % [KEYWORD_COLOR.to_html(false), word]
			elif word in TYPES:
				result += "[color=#%s]%s[/color]" % [CLASS_COLOR.to_html(false), word]
			elif i + word.length() < line.length() and line[i + word.length()] == "(":
				# Function call
				result += "[color=#%s]%s[/color]" % [FUNCTION_COLOR.to_html(false), word]
			else:
				result += word
			
			i += word.length()
			continue
		
		# Check for numbers
		if c.is_valid_int() or (c == "." and i + 1 < line.length() and line[i + 1].is_valid_int()):
			var num = _extract_number(line, i)
			result += "[color=#%s]%s[/color]" % [NUMBER_COLOR.to_html(false), num]
			i += num.length()
			continue
		
		# Default: just add the character
		result += _escape_bbcode(c)
		i += 1
	
	return result


func _is_word_char(c: String) -> bool:
	return c.is_valid_identifier() or c == "_"


func _extract_word(line: String, start: int) -> String:
	var result = ""
	var i = start
	while i < line.length() and _is_word_char(line[i]):
		result += line[i]
		i += 1
	return result


func _extract_number(line: String, start: int) -> String:
	var result = ""
	var i = start
	var has_dot = false
	while i < line.length():
		var c = line[i]
		if c.is_valid_int():
			result += c
		elif c == "." and not has_dot:
			has_dot = true
			result += c
		elif c == "x" or c == "X" or c == "b" or c == "B":  # hex/binary
			result += c
		elif c in ["a", "b", "c", "d", "e", "f", "A", "B", "C", "D", "E", "F"]:  # hex digits
			result += c
		else:
			break
		i += 1
	return result


func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")
