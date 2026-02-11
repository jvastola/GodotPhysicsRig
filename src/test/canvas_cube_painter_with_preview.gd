extends Control

## Test scene that shows canvas cube painter with live 3D preview

@onready var rotate_check: CheckBox = %RotateCheck
@onready var speed_slider: HSlider = %SpeedSlider

var painted_cube: PaintedCube
var canvas_cube_painter: CanvasCubePainter

func _ready() -> void:
	# Find the painted cube
	painted_cube = find_child("PaintedCube", true, false) as PaintedCube
	
	# Find the canvas cube painter
	var ui_node = find_child("CanvasCubePainterUI", true, false)
	if ui_node:
		var viewport_node = ui_node.find_child("CanvasViewport", true, false)
		if viewport_node and viewport_node.has_method("get_canvas_cube_painter"):
			canvas_cube_painter = viewport_node.get_canvas_cube_painter()
	
	# Connect cube to painter
	if painted_cube and canvas_cube_painter:
		painted_cube.canvas_cube_painter_path = canvas_cube_painter.get_path()
		call_deferred("_connect_cube")
		print("Connected painted cube to canvas cube painter")
	
	# Connect UI controls
	if rotate_check:
		rotate_check.toggled.connect(_on_rotate_toggled)
	if speed_slider:
		speed_slider.value_changed.connect(_on_speed_changed)

func _connect_cube() -> void:
	if painted_cube and canvas_cube_painter:
		painted_cube.set_canvas_cube_painter(canvas_cube_painter)

func _on_rotate_toggled(toggled: bool) -> void:
	if painted_cube:
		painted_cube.auto_rotate = toggled

func _on_speed_changed(value: float) -> void:
	if painted_cube:
		painted_cube.rotation_speed = value
