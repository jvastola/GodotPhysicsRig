extends PanelContainer

@export_file("*.md") var tos_path: String = "res://docs/tos.md"
@export_file("*.md") var privacy_path: String = "res://docs/privacy.md"

@onready var tos_label: RichTextLabel = get_node_or_null("MarginContainer/VBoxContainer/TabContainer/TOS/TOSLabel")
@onready var privacy_label: RichTextLabel = get_node_or_null("MarginContainer/VBoxContainer/TabContainer/Privacy/PrivacyLabel")
@onready var tos_path_label: Label = get_node_or_null("MarginContainer/VBoxContainer/TOSPath")
@onready var privacy_path_label: Label = get_node_or_null("MarginContainer/VBoxContainer/PrivacyPath")
@onready var status_label: Label = get_node_or_null("MarginContainer/VBoxContainer/StatusLabel")
@onready var reload_button: Button = get_node_or_null("MarginContainer/VBoxContainer/Buttons/ReloadButton")


func _ready() -> void:
	_update_path_labels()
	if reload_button:
		reload_button.pressed.connect(_on_reload_pressed)
	load_documents()


func load_documents() -> void:
	var tos_text := _load_markdown_text(tos_path)
	var privacy_text := _load_markdown_text(privacy_path)
	_set_label_text(tos_label, tos_text, "Terms of Service", tos_path)
	_set_label_text(privacy_label, privacy_text, "Privacy Policy", privacy_path)
	if status_label:
		status_label.text = "Loaded legal documents"


func _on_reload_pressed() -> void:
	load_documents()


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
	label.scroll_vertical = 0


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
