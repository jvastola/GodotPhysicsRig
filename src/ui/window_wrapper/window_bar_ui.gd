extends Control

# window_bar_ui.gd
# 2D Logic for the window title bar.

signal close_pressed

@onready var title_label: Label = $HBoxContainer/TitleLabel
@onready var close_button: Button = $HBoxContainer/CloseButton

func _ready() -> void:
    if close_button:
        close_button.pressed.connect(func(): close_pressed.emit())

func set_title(text: String) -> void:
    if title_label:
        title_label.text = text
