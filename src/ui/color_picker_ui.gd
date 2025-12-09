class_name ColorPickerUI
extends PanelContainer

static var instance: ColorPickerUI = null

@onready var color_picker: ColorPicker = get_node_or_null("MarginContainer/VBoxContainer/ColorPicker") as ColorPicker
@onready var preview: ColorRect = get_node_or_null("MarginContainer/VBoxContainer/ColorPreview") as ColorRect
@onready var hex_label: Label = get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer/HexLabel") as Label
@onready var copy_button: Button = get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer/CopyButton") as Button
@onready var status_label: Label = get_node_or_null("MarginContainer/VBoxContainer/StatusLabel") as Label


func _ready() -> void:
	instance = self
	if color_picker:
		color_picker.color_changed.connect(_on_color_changed)
		_on_color_changed(color_picker.color)
	if copy_button:
		copy_button.pressed.connect(_on_copy_pressed)
	if status_label and status_label.text == "":
		status_label.text = "Pick a color to see values"


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _on_color_changed(color: Color) -> void:
	if preview:
		preview.color = color
	var hex_text: String = color.to_html(color.a < 0.999)
	if hex_label:
		hex_label.text = "#" + hex_text.to_upper()
	if status_label:
		status_label.text = "RGB %d, %d, %d" % [
			roundi(color.r * 255.0),
			roundi(color.g * 255.0),
			roundi(color.b * 255.0),
		]


func _on_copy_pressed() -> void:
	if not hex_label:
		return
	DisplayServer.clipboard_set(hex_label.text)
	if status_label:
		status_label.text = "Copied %s" % hex_label.text


func get_current_color() -> Color:
	if color_picker:
		return color_picker.color
	return Color.WHITE
