extends Control

## UI controller for the Canvas Cube Painter

@onready var top_button: Button = %TopButton
@onready var bottom_button: Button = %BottomButton
@onready var front_button: Button = %FrontButton
@onready var back_button: Button = %BackButton
@onready var left_button: Button = %LeftButton
@onready var right_button: Button = %RightButton
@onready var current_face_label: Label = %CurrentFaceLabel
@onready var resolution_spinbox: SpinBox = %ResolutionSpinBox
@onready var apply_res_button: Button = %ApplyResButton
@onready var brush_size_slider: HSlider = %BrushSizeSlider
@onready var brush_size_label: Label = %BrushSizeLabel
@onready var color_picker: ColorPickerButton = %ColorPickerButton
@onready var pixel_perfect_check: CheckBox = %PixelPerfectCheck
@onready var clear_face_button: Button = %ClearFaceButton
@onready var clear_all_button: Button = %ClearAllButton
@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton
@onready var sync_button: Button = %SyncButton

var canvas_cube_painter: CanvasCubePainter

func _ready() -> void:
	# Connect face buttons
	top_button.pressed.connect(_on_face_button_pressed.bind("top"))
	bottom_button.pressed.connect(_on_face_button_pressed.bind("bottom"))
	front_button.pressed.connect(_on_face_button_pressed.bind("front"))
	back_button.pressed.connect(_on_face_button_pressed.bind("back"))
	left_button.pressed.connect(_on_face_button_pressed.bind("left"))
	right_button.pressed.connect(_on_face_button_pressed.bind("right"))
	
	# Connect control signals
	apply_res_button.pressed.connect(_on_apply_resolution_pressed)
	brush_size_slider.value_changed.connect(_on_brush_size_changed)
	color_picker.color_changed.connect(_on_color_changed)
	pixel_perfect_check.toggled.connect(_on_pixel_perfect_toggled)
	clear_face_button.pressed.connect(_on_clear_face_pressed)
	clear_all_button.pressed.connect(_on_clear_all_pressed)
	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)
	sync_button.pressed.connect(_on_sync_pressed)
	
	# Find canvas cube painter in viewport
	call_deferred("_find_canvas_cube_painter")

func _find_canvas_cube_painter() -> void:
	var viewport_node = find_child("CanvasViewport", true, false)
	if viewport_node and viewport_node.has_method("get_canvas_cube_painter"):
		canvas_cube_painter = viewport_node.get_canvas_cube_painter()
		if canvas_cube_painter:
			canvas_cube_painter.face_changed.connect(_on_face_changed)
			_sync_ui_with_painter()
			print("CanvasCubePainterUI: Connected to canvas cube painter")
	else:
		print("CanvasCubePainterUI: Canvas cube painter not found")

func _sync_ui_with_painter() -> void:
	if not canvas_cube_painter:
		return
	resolution_spinbox.value = canvas_cube_painter.canvas_resolution
	brush_size_slider.value = canvas_cube_painter.brush_size
	color_picker.color = canvas_cube_painter.default_brush_color
	pixel_perfect_check.button_pressed = canvas_cube_painter.pixel_perfect
	_update_brush_size_label(canvas_cube_painter.brush_size)
	_update_current_face_label(canvas_cube_painter.get_current_face())

func _on_face_button_pressed(face_name: String) -> void:
	if canvas_cube_painter:
		canvas_cube_painter.set_current_face(face_name)

func _on_face_changed(face_name: String) -> void:
	_update_current_face_label(face_name)
	_highlight_face_button(face_name)

func _update_current_face_label(face_name: String) -> void:
	current_face_label.text = "Current: " + face_name.capitalize()

func _highlight_face_button(face_name: String) -> void:
	# Reset all buttons
	for btn in [top_button, bottom_button, front_button, back_button, left_button, right_button]:
		btn.modulate = Color.WHITE
	
	# Highlight current
	match face_name:
		"top": top_button.modulate = Color.YELLOW
		"bottom": bottom_button.modulate = Color.YELLOW
		"front": front_button.modulate = Color.YELLOW
		"back": back_button.modulate = Color.YELLOW
		"left": left_button.modulate = Color.YELLOW
		"right": right_button.modulate = Color.YELLOW

func _on_apply_resolution_pressed() -> void:
	if canvas_cube_painter:
		canvas_cube_painter.canvas_resolution = int(resolution_spinbox.value)
		print("Canvas resolution changed to: ", canvas_cube_painter.canvas_resolution)

func _on_brush_size_changed(value: float) -> void:
	if canvas_cube_painter:
		canvas_cube_painter.brush_size = int(value)
	_update_brush_size_label(int(value))

func _update_brush_size_label(size: int) -> void:
	brush_size_label.text = "Size: " + str(size)

func _on_color_changed(color: Color) -> void:
	if canvas_cube_painter:
		canvas_cube_painter.default_brush_color = color

func _on_pixel_perfect_toggled(toggled: bool) -> void:
	if canvas_cube_painter:
		canvas_cube_painter.pixel_perfect = toggled

func _on_clear_face_pressed() -> void:
	if canvas_cube_painter:
		canvas_cube_painter.clear_canvas(Color.WHITE, canvas_cube_painter.get_current_face())

func _on_clear_all_pressed() -> void:
	if canvas_cube_painter:
		canvas_cube_painter.clear_canvas(Color.WHITE)

func _on_save_pressed() -> void:
	if canvas_cube_painter:
		canvas_cube_painter.save_all_canvases()

func _on_load_pressed() -> void:
	if canvas_cube_painter:
		canvas_cube_painter.load_all_canvases()

func _on_sync_pressed() -> void:
	if canvas_cube_painter:
		canvas_cube_painter.sync_all_to_grid_painter()
		print("Synced all faces to GridPainter")
