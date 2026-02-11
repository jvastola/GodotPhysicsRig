extends SubViewportContainer

## Viewport container for the Canvas Painter 3D view

@onready var viewport: SubViewport = $SubViewport
@onready var camera: Camera3D = $SubViewport/Camera3D
@onready var canvas_painter: CanvasPainter = $SubViewport/CanvasPainter

var _mouse_down: bool = false

func _ready() -> void:
	# Ensure viewport is set up correctly
	if viewport:
		viewport.handle_input_locally = false
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_mouse_down = mb.pressed
			_handle_mouse_event(mb, mb.pressed, not mb.pressed)
	elif event is InputEventMouseMotion and _mouse_down:
		_handle_mouse_event(event, false, false)

func _handle_mouse_event(event: InputEvent, just_pressed: bool, just_released: bool) -> void:
	var canvas_mesh := get_node_or_null("SubViewport/CanvasMesh") as MeshInstance3D
	if not canvas_mesh:
		return
	
	# Convert 2D mouse position to 3D ray
	var mouse_pos: Vector2 = Vector2.ZERO
	if event is InputEventMouse:
		mouse_pos = (event as InputEventMouse).position
	else:
		return
	
	var from: Vector3 = camera.project_ray_origin(mouse_pos)
	var to: Vector3 = from + camera.project_ray_normal(mouse_pos) * 100.0
	
	# For now, do a simple plane intersection (Z=0 plane)
	var plane := Plane(Vector3(0, 0, 1), 0)
	var intersection: Variant = plane.intersects_ray(from, to - from)
	
	if intersection is Vector3:
		var hit_pos: Vector3 = intersection as Vector3
		var local_pos: Vector3 = canvas_mesh.to_local(hit_pos)
		
		# Create pointer event
		var pointer_event: Dictionary = {
			"local_position": local_pos,
			"global_position": hit_pos,
			"action_just_pressed": just_pressed,
			"action_pressed": _mouse_down,
			"action_just_released": just_released,
			"pointer_color": canvas_painter.default_brush_color if canvas_painter else Color.BLACK
		}
		
		# Send to handler
		if canvas_mesh.has_method("handle_pointer_event"):
			canvas_mesh.handle_pointer_event(pointer_event)

func get_canvas_painter() -> CanvasPainter:
	return canvas_painter
