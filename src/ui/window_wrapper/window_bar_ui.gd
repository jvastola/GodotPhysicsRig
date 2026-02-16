extends Control

# window_bar_ui.gd
# 2D Logic for the window title bar.

signal close_pressed
signal pin_pressed
signal dock_left_pressed
signal dock_right_pressed
signal dock_head_pressed
signal bring_close_pressed

@onready var title_label: Label = $HBoxContainer/TitleLabel
@onready var close_button: Button = $HBoxContainer/CloseButton
@onready var pin_button: Button = $HBoxContainer/PinButton
@onready var dock_left_button: Button = $HBoxContainer/DockLeftButton
@onready var dock_right_button: Button = $HBoxContainer/DockRightButton
@onready var dock_head_button: Button = $HBoxContainer/DockHeadButton
@onready var bring_close_button: Button = $HBoxContainer/BringCloseButton

func _ready() -> void:
    if close_button:
        close_button.pressed.connect(func(): close_pressed.emit())
    if pin_button:
        pin_button.pressed.connect(func(): pin_pressed.emit())
    if dock_left_button:
        dock_left_button.pressed.connect(func(): dock_left_pressed.emit())
    if dock_right_button:
        dock_right_button.pressed.connect(func(): dock_right_pressed.emit())
    if dock_head_button:
        dock_head_button.pressed.connect(func(): dock_head_pressed.emit())
    if bring_close_button:
        bring_close_button.pressed.connect(func(): bring_close_pressed.emit())

func set_title(text: String) -> void:
    if title_label:
        title_label.text = text

func set_pin_state(is_pinned: bool) -> void:
    if pin_button:
        pin_button.text = "📍" if is_pinned else "📌"
