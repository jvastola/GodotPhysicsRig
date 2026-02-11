extends SubViewportContainer

## Viewport container for the Canvas Cube Painter 3D view
## Shows the current face being edited

@onready var viewport: SubViewport = $SubViewport
@onready var camera: Camera3D = $SubViewport/Camera3D
@onready var canvas_cube_painter: CanvasCubePainter = $SubViewport/CanvasCubePainter
@onready var face_mesh: MeshInstance3D = $SubViewport/CurrentFaceMesh

var _mouse_down: bool = false
var _handler_script: Script

func _ready() -> void:
	if viewport:
		viewport.handle_input_locally = false
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	
	# Connect to painter signals
	if canvas_cube_painter:
		canvas_cube_painter.face_changed.connect(_on_face_changed)
		canvas_cube_painter.canvas_updated.connect(_on_canvas_updated)
	
	call_deferred("_setup_face_mesh")

func _setup_face_mesh() -> void:
	# Create plane mesh for current face
	_update_face_display(canvas_cube_painter.get_current_face())
	
	# Attach handler script - use the cube painter specific handler
	if FileAccess.file_exists("res://src/systems/canvas_cube_painter_handler.gd"):
		_handler_script = preload("res://src/systems/canvas_cube_painter_handler.gd")
	
	if _handler_script and face_mesh:
		face_mesh.set_script(_handler_script)
		if face_mesh.has_method("set"):
			face_mesh.set("painter", canvas_cube_painter.get_path())
			face_mesh.set("brush_size", canvas_cube_painter.brush_size)
		face_mesh.add_to_group("pointer_interactable")

func _on_face_changed(face_name: String) -> void:
	_update_face_display(face_name)

func _on_canvas_updated(face_name: String) -> void:
	if face_name == canvas_cube_painter.get_current_face():
		_update_face_display(face_name)

func _update_face_display(face_name: String) -> void:
	if not face_mesh:
		return
	
	# Create plane mesh
	var plane_mesh := _create_plane_mesh()
	face_mesh.mesh = plane_mesh
	
	# Get texture for current face
	var texture := canvas_cube_painter.get_face_texture(face_name)
	if not texture:
		return
	
	# Create material
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if canvas_cube_painter.pixel_perfect else BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	face_mesh.material_override = mat

func _create_plane_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var half_size := 0.8
	
	var verts := [
		Vector3(-half_size, -half_size, 0),
		Vector3(half_size, -half_size, 0),
		Vector3(half_size, half_size, 0),
		Vector3(-half_size, half_size, 0)
	]
	
	var uvs := [
		Vector2(0, 1),
		Vector2(1, 1),
		Vector2(1, 0),
		Vector2(0, 0)
	]
	
	var normal := Vector3(0, 0, 1)
	
	# First triangle
	st.set_normal(normal)
	st.set_uv(uvs[0])
	st.add_vertex(verts[0])
	st.set_normal(normal)
	st.set_uv(uvs[1])
	st.add_vertex(verts[1])
	st.set_normal(normal)
	st.set_uv(uvs[2])
	st.add_vertex(verts[2])
	
	# Second triangle
	st.set_normal(normal)
	st.set_uv(uvs[0])
	st.add_vertex(verts[0])
	st.set_normal(normal)
	st.set_uv(uvs[2])
	st.add_vertex(verts[2])
	st.set_normal(normal)
	st.set_uv(uvs[3])
	st.add_vertex(verts[3])
	
	return st.commit()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_mouse_down = mb.pressed
			_handle_mouse_event(mb, mb.pressed, not mb.pressed)
	elif event is InputEventMouseMotion and _mouse_down:
		_handle_mouse_event(event, false, false)

func _handle_mouse_event(event: InputEvent, just_pressed: bool, just_released: bool) -> void:
	if not face_mesh:
		return
	
	var mouse_pos: Vector2 = Vector2.ZERO
	if event is InputEventMouse:
		mouse_pos = (event as InputEventMouse).position
	else:
		return
	
	var from: Vector3 = camera.project_ray_origin(mouse_pos)
	var to: Vector3 = from + camera.project_ray_normal(mouse_pos) * 100.0
	
	var plane := Plane(Vector3(0, 0, 1), 0)
	var intersection: Variant = plane.intersects_ray(from, to - from)
	
	if intersection is Vector3:
		var hit_pos: Vector3 = intersection as Vector3
		var local_pos: Vector3 = face_mesh.to_local(hit_pos)
		
		var pointer_event: Dictionary = {
			"local_position": local_pos,
			"global_position": hit_pos,
			"action_just_pressed": just_pressed,
			"action_pressed": _mouse_down,
			"action_just_released": just_released,
			"pointer_color": canvas_cube_painter.default_brush_color
		}
		
		# Handle painting state
		if just_pressed:
			canvas_cube_painter.start_painting()
		elif just_released:
			canvas_cube_painter.stop_painting()
		
		# Send to handler
		if face_mesh.has_method("handle_pointer_event"):
			face_mesh.handle_pointer_event(pointer_event)

func get_canvas_cube_painter() -> CanvasCubePainter:
	return canvas_cube_painter
