extends PanelContainer

signal accepted

@export_file("*.md") var tos_path: String = "res://docs/tos.md"
@export_file("*.md") var privacy_path: String = "res://docs/privacy.md"
@export_range(0.5, 5.0, 0.1) var required_hold_time: float = 1.5

const DEFAULT_TOS_TEXT := "# Terms of Service\n\nWelcome to the project. By using this software you agree to the current terms. The software is provided as-is without warranties. Do not use it unlawfully. Contributions may be distributed under the project license."
const DEFAULT_PRIVACY_TEXT := "# Privacy Policy\n\nThis project does not intentionally collect personal data by default. Networked features may send identifiers needed for connectivity. Secure your own device and credentials."

@onready var tos_label: RichTextLabel = get_node_or_null("MarginContainer/VBoxContainer/TabContainer/TOS/TOSLabel")
@onready var privacy_label: RichTextLabel = get_node_or_null("MarginContainer/VBoxContainer/TabContainer/Privacy/PrivacyLabel")
@onready var tos_path_label: Label = get_node_or_null("MarginContainer/VBoxContainer/TOSPath")
@onready var privacy_path_label: Label = get_node_or_null("MarginContainer/VBoxContainer/PrivacyPath")
@onready var status_label: Label = get_node_or_null("MarginContainer/VBoxContainer/StatusLabel")
@onready var reload_button: Button = get_node_or_null("MarginContainer/VBoxContainer/Buttons/ReloadButton")
@onready var accept_button: Button = get_node_or_null("MarginContainer/VBoxContainer/AcceptRow/AcceptButton")
@onready var accept_progress: ProgressBar = get_node_or_null("MarginContainer/VBoxContainer/AcceptRow/AcceptProgress")
@onready var overlay_button: Button = get_node_or_null("MarginContainer/VBoxContainer/TabContainer/OverlayAcceptButton")

var _hold_active := false
var _hold_elapsed := 0.0


func _ready() -> void:
	set_process(false)
	_update_path_labels()
	if reload_button:
		reload_button.pressed.connect(_on_reload_pressed)
	if accept_button:
		accept_button.button_down.connect(_on_accept_down)
		accept_button.button_up.connect(_on_accept_up)
	if overlay_button:
		overlay_button.pressed.connect(_on_overlay_accept)
	_reset_hold()
	load_documents()
	_set_ready_status()


func _process(delta: float) -> void:
	if not _hold_active:
		return
	_hold_elapsed += delta
	_update_hold_ui()
	if _hold_elapsed >= required_hold_time:
		_complete_accept()


func load_documents() -> void:
	var tos_text := _load_markdown_text(tos_path)
	if tos_text.is_empty():
		tos_text = DEFAULT_TOS_TEXT
	var privacy_text := _load_markdown_text(privacy_path)
	if privacy_text.is_empty():
		privacy_text = DEFAULT_PRIVACY_TEXT
	_set_label_text(tos_label, tos_text, "Terms of Service", tos_path)
	_set_label_text(privacy_label, privacy_text, "Privacy Policy", privacy_path)
	if status_label:
		status_label.text = "Loaded legal documents"


func _on_reload_pressed() -> void:
	load_documents()


func _on_accept_down() -> void:
	if _hold_active:
		return
	_hold_active = true
	_hold_elapsed = 0.0
	set_process(true)
	if status_label:
		status_label.text = "Hold to accept..."
	_update_hold_ui()


func _on_accept_up() -> void:
	if _hold_active:
		_reset_hold()
		if status_label:
			status_label.text = "Hold cancelled"


func _complete_accept() -> void:
	_hold_active = false
	set_process(false)
	_hold_elapsed = required_hold_time
	_update_hold_ui()
	if status_label:
		status_label.text = "TOS/Privacy accepted"
	emit_signal("accepted")


func _reset_hold() -> void:
	_hold_active = false
	_hold_elapsed = 0.0
	set_process(false)
	_update_hold_ui()


func _update_hold_ui() -> void:
	if not accept_progress:
		return
	var pct: float = clamp(_hold_elapsed / required_hold_time, 0.0, 1.0) * 100.0
	accept_progress.value = pct
	if accept_button:
		accept_button.text = "Hold A/X/Space to accept (%.0f%%)" % pct
	if overlay_button:
		overlay_button.text = "Tap/Click/Press A/X/Space to accept (%.0f%%)" % pct


func _update_path_labels() -> void:
	if tos_path_label:
		tos_path_label.text = "TOS: %s" % tos_path
	if privacy_path_label:
		privacy_path_label.text = "Privacy: %s" % privacy_path


func _set_label_text(label: RichTextLabel, text: String, fallback_title: String, path: String) -> void:
	if not label:
		return
	var content := text
	if content.is_empty():
		content = "[b]%s[/b]\nNo content found at %s" % [fallback_title, path]
	label.clear()
	label.append_text(_markdown_to_bbcode(content))
	label.scroll_to_line(0)


func _load_markdown_text(path: String) -> String:
	if path.is_empty():
		return ""
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file:
		return file.get_as_text()
	return ""


func _markdown_to_bbcode(text: String) -> String:
	var lines := text.split("\n")
	var converted: PackedStringArray = []
	for line in lines:
		if line.begins_with("### "):
			converted.append("[b]" + line.substr(4) + "[/b]")
		elif line.begins_with("## "):
			converted.append("[b]" + line.substr(3) + "[/b]")
		elif line.begins_with("# "):
			converted.append("[b]" + line.substr(2) + "[/b]")
		elif line.begins_with("- "):
			converted.append("• " + line.substr(2))
		else:
			converted.append(line)
	return "\n".join(converted)


func _unhandled_input(event: InputEvent) -> void:
	# Desktop convenience: hold Space to accept.
	if event is InputEventKey and event.keycode == KEY_SPACE:
		if event.is_pressed() and not event.is_echo():
			_on_accept_down()
		elif not event.is_pressed():
			_on_accept_up()
	elif event is InputEventJoypadButton and (event.button_index == JOY_BUTTON_A or event.button_index == JOY_BUTTON_X):
		if event.is_pressed():
			_on_accept_down()
		else:
			_on_accept_up()


func begin_accept_hold() -> void:
	_on_accept_down()


func end_accept_hold() -> void:
	_on_accept_up()


func _set_ready_status() -> void:
	if status_label:
		status_label.text = "Hold A/X (VR) or Space (desktop) to accept"


func _on_overlay_accept() -> void:
	_complete_accept()
