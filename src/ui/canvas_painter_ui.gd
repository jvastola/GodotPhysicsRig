extends Control

## UI controller for the Canvas Painter

@onready var width_spinbox: SpinBox = %WidthSpinBox
@onready var height_spinbox: SpinBox = %HeightSpinBox
@onready var apply_size_button: Button = %ApplySizeButton
@onready var brush_size_slider: HSlider = %BrushSizeSlider
@onready var brush_size_label: Label = %BrushSizeLabel
@onready var color_picker: ColorPickerButton = %ColorPickerButton
@onready var pixel_perfect_check: CheckBox = %PixelPerfectCheck
@onready var clear_button: Button = %ClearButton
@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton

var canvas_painter: CanvasPainter

func _ready() -> void:
	# Connect signals
	apply_size_button.pressed.connect(_on_apply_size_pressed)
	brush_size_slider.value_changed.connect(_on_brush_size_changed)
	color_picker.color_changed.connect(_on_color_changed)
	pixel_perfect_check.toggled.connect(_on_pixel_perfect_toggled)
	clear_button.pressed.connect(_on_clear_pressed)
	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)
	
	# Find canvas painter in viewport
	call_deferred("_find_canvas_painter")

func _find_canvas_painter() -> void:
	# Look for CanvasPainterViewport3D child
	var viewport_node = find_child("CanvasViewport", true, false)
	if viewport_node and viewport_node.has_method("get_canvas_painter"):
		canvas_painter = viewport_node.get_canvas_painter()
		if canvas_painter:
			_sync_ui_with_painter()
			print("CanvasPainterUI: Connected to canvas painter")
	else:
		print("CanvasPainterUI: Canvas painter not found")

func _sync_ui_with_painter() -> void:
	if not canvas_painter:
		return
	width_spinbox.value = canvas_painter.canvas_width
	height_spinbox.value = canvas_painter.canvas_height
	brush_size_slider.value = canvas_painter.brush_size
	color_picker.color = canvas_painter.default_brush_color
	pixel_perfect_check.button_pressed = canvas_painter.pixel_perfect
	_update_brush_size_label(canvas_painter.brush_size)

func _on_apply_size_pressed() -> void:
	if not canvas_painter:
		return
	canvas_painter.canvas_width = int(width_spinbox.value)
	canvas_painter.canvas_height = int(height_spinbox.value)
	print("Canvas size changed to: ", canvas_painter.canvas_width, "x", canvas_painter.canvas_height)

func _on_brush_size_changed(value: float) -> void:
	if canvas_painter:
		canvas_painter.brush_size = int(value)
	_update_brush_size_label(int(value))

func _update_brush_size_label(size: int) -> void:
	brush_size_label.text = "Size: " + str(size)

func _on_color_changed(color: Color) -> void:
	if canvas_painter:
		canvas_painter.default_brush_color = color

func _on_pixel_perfect_toggled(toggled: bool) -> void:
	if canvas_painter:
		canvas_painter.pixel_perfect = toggled
		print("Pixel perfect mode: ", "ON" if toggled else "OFF")

func _on_clear_pressed() -> void:
	if canvas_painter:
		canvas_painter.clear_canvas(Color.WHITE)

func _on_save_pressed() -> void:
	if canvas_painter:
		canvas_painter.save_canvas()

func _on_load_pressed() -> void:
	if canvas_painter:
		canvas_painter.load_canvas()
