extends Node3D
class_name WebviewViewport3D

## WebView Viewport 3D - Cross-platform web content display in VR
## Automatically selects the appropriate backend based on platform:
## - Android/Quest: TLabWebView
## - Desktop: gdCEF (Chromium Embedded Framework)
## - Fallback: Placeholder with installation instructions

@export var pointer_group: StringName = &"pointer_interactable"
@export var default_url: String = "https://www.google.com"
@export var ui_size: Vector2 = Vector2(1280, 720)
@export var quad_size: Vector2 = Vector2(2.56, 1.44)  # 16:9 aspect ratio
@export var debug_coordinates: bool = false
@export var flip_v: bool = true

signal page_loaded(url: String)
signal page_loading(url: String)
signal close_requested

@onready var viewport: SubViewport = $SubViewport
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var _static_body: StaticBody3D = $MeshInstance3D/StaticBody3D
@onready var _texture_rect: TextureRect = $SubViewport/TextureRect
@onready var _placeholder_label: Label = $SubViewport/PlaceholderLabel

var _saved_static_body_layer: int = 0
var _last_mouse_pos: Vector2 = Vector2(-1, -1)
var _is_hovering: bool = false
var _is_pressed: bool = false
var _has_focus: bool = false

# Backend reference
var _backend: WebViewBackend = null
var _backend_available: bool = false
var _current_url: String = ""


func _ready() -> void:
	if pointer_group != StringName(""):
		add_to_group(pointer_group)
	
	if viewport:
		viewport.size = Vector2i(int(ui_size.x), int(ui_size.y))
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.transparent_bg = false
		viewport.gui_embed_subwindows = true
		viewport.handle_input_locally = true
		viewport.gui_disable_input = false
	
	if _static_body:
		_saved_static_body_layer = _static_body.collision_layer
	
	if mesh_instance and _static_body:
		mesh_instance.visible = true
		_static_body.collision_layer = _saved_static_body_layer
	
	# Initialize the appropriate backend
	_initialize_backend()
	
	set_process_input(true)


func _initialize_backend() -> void:
	var platform := OS.get_name()
	print("WebviewViewport3D: Initializing on platform: ", platform)
	
	var settings := {
		"width": int(ui_size.x),
		"height": int(ui_size.y),
		"url": default_url,
		"parent_node": self,
		"texture_rect": _texture_rect,
	}
	
	# Try platform-specific backends first
	if platform == "Android":
		_backend = _try_android_backend(settings)
	else:
		_backend = _try_desktop_backend(settings)
	
	# Fallback to placeholder if no backend available
	if not _backend:
		_backend = _create_placeholder_backend(settings)
	
	# Connect backend signals
	if _backend:
		if _backend.has_signal("page_loaded"):
			_backend.page_loaded.connect(_on_backend_page_loaded)
		if _backend.has_signal("page_loading"):
			_backend.page_loading.connect(_on_backend_page_loading)
		
		print("WebviewViewport3D: Using backend: ", _backend.get_backend_name())


func _try_android_backend(settings: Dictionary) -> WebViewBackend:
	# Check if TLabWebView is available
	if not Engine.has_singleton("TLabWebView"):
		print("WebviewViewport3D: TLabWebView not available")
		return null
	
	var backend := AndroidWebViewBackend.new()
	if backend.initialize(settings):
		_backend_available = true
		_hide_placeholder()
		return backend
	
	return null


func _try_desktop_backend(settings: Dictionary) -> WebViewBackend:
	# Check if gdCEF is available
	if not ClassDB.class_exists("GDCef"):
		print("WebviewViewport3D: gdCEF not available")
		return null
	
	var backend := DesktopCEFBackend.new()
	if backend.initialize(settings):
		_backend_available = true
		_hide_placeholder()
		return backend
	
	return null


func _create_placeholder_backend(settings: Dictionary) -> WebViewBackend:
	var backend := PlaceholderBackend.new()
	backend.initialize(settings)
	_backend_available = false
	_show_placeholder(backend.get_message())
	return backend


func _show_placeholder(message: String) -> void:
	if _placeholder_label:
		_placeholder_label.text = message
		_placeholder_label.visible = true
	if _texture_rect:
		_texture_rect.visible = false


func _hide_placeholder() -> void:
	if _placeholder_label:
		_placeholder_label.visible = false
	if _texture_rect:
		_texture_rect.visible = true


func _on_backend_page_loaded(url: String) -> void:
	_current_url = url
	page_loaded.emit(url)


func _on_backend_page_loading(url: String) -> void:
	page_loading.emit(url)


func _process(delta: float) -> void:
	# Update backend (needed for Android texture updates)
	if _backend and _backend.has_method("update"):
		_backend.update(delta)


func _exit_tree() -> void:
	if _backend:
		_backend.shutdown()
		_backend = null


# ============================================================================
# PUBLIC API
# ============================================================================

func load_url(url: String) -> void:
	if not _backend:
		return
	_current_url = url
	_backend.load_url(url)


func get_current_url() -> String:
	if _backend:
		return _backend.get_url()
	return _current_url


func reload() -> void:
	if _backend:
		_backend.reload()


func go_back() -> void:
	if _backend:
		_backend.go_back()


func go_forward() -> void:
	if _backend:
		_backend.go_forward()


func can_go_back() -> bool:
	if _backend:
		return _backend.can_go_back()
	return false


func can_go_forward() -> bool:
	if _backend:
		return _backend.can_go_forward()
	return false


func stop_loading() -> void:
	if _backend:
		_backend.stop_loading()


func is_backend_available() -> bool:
	return _backend_available


func get_backend_name() -> String:
	if _backend:
		return _backend.get_backend_name()
	return "None"


# ============================================================================
# INPUT HANDLING
# ============================================================================

func _input(event: InputEvent) -> void:
	if not _has_focus or not _backend_available:
		return
	
	if event is InputEventKey and _backend:
		var key_event := event as InputEventKey
		_backend.send_key(
			key_event.keycode,
			key_event.pressed,
			key_event.shift_pressed,
			key_event.alt_pressed,
			key_event.ctrl_pressed
		)
		get_viewport().set_input_as_handled()


func set_focus(focused: bool) -> void:
	_has_focus = focused


func handle_pointer_event(event: Dictionary) -> void:
	if not mesh_instance:
		return
	
	var event_type: String = String(event.get("type", ""))
	var hit_pos: Vector3 = event.get("global_position", Vector3.ZERO)
	
	var local_hit: Vector3 = mesh_instance.global_transform.affine_inverse() * hit_pos
	var uv: Vector2 = _world_to_uv(local_hit)
	
	if debug_coordinates:
		print("WebviewViewport3D: Hit uv=", uv)
	
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		if _is_hovering:
			_send_mouse_exit()
		return
	
	var pixel_x: int = int(uv.x * ui_size.x)
	var pixel_y: int = int(uv.y * ui_size.y)
	
	match event_type:
		"enter", "hover":
			_send_mouse_motion(pixel_x, pixel_y)
			_is_hovering = true
		"press":
			_send_mouse_motion(pixel_x, pixel_y)
			_send_mouse_button(pixel_x, pixel_y, true)
			_is_pressed = true
			set_focus(true)
		"hold":
			_send_mouse_motion(pixel_x, pixel_y)
			if not _is_pressed:
				_send_mouse_button(pixel_x, pixel_y, true)
				_is_pressed = true
		"release":
			_send_mouse_motion(pixel_x, pixel_y)
			_send_mouse_button(pixel_x, pixel_y, false)
			_is_pressed = false
		"scroll":
			_send_mouse_motion(pixel_x, pixel_y)
			var scroll_value: float = event.get("scroll_value", 0.0)
			_send_scroll(pixel_x, pixel_y, scroll_value)
		"exit":
			_send_mouse_exit()
			_is_hovering = false
			_is_pressed = false


func _world_to_uv(local_pos: Vector3) -> Vector2:
	var half_size: Vector2 = quad_size * 0.5
	if half_size.x == 0 or half_size.y == 0:
		return Vector2(-1, -1)
	
	var u: float = (local_pos.x / half_size.x) * 0.5 + 0.5
	var v: float = (local_pos.y / half_size.y) * 0.5 + 0.5
	
	if flip_v:
		v = 1.0 - v
	
	return Vector2(u, v)


func _send_mouse_motion(x: int, y: int) -> void:
	if not _backend_available or not _backend:
		return
	_backend.send_mouse_move(x, y)
	_last_mouse_pos = Vector2(x, y)


func _send_mouse_button(x: int, y: int, pressed: bool) -> void:
	if not _backend_available or not _backend:
		return
	
	if pressed:
		_backend.send_mouse_down(x, y, 0)
	else:
		_backend.send_mouse_up(x, y, 0)


func _send_scroll(x: int, y: int, delta: float) -> void:
	if not _backend_available or not _backend:
		return
	_backend.send_scroll(x, y, delta)


func _send_mouse_exit() -> void:
	_last_mouse_pos = Vector2(-1, -1)
	_is_hovering = false
	_is_pressed = false


# ============================================================================
# INTERACTIVITY
# ============================================================================

func set_interactive(enabled: bool) -> void:
	if mesh_instance:
		mesh_instance.visible = enabled
	if _static_body:
		if enabled:
			_static_body.collision_layer = _saved_static_body_layer
		else:
			_static_body.collision_layer = 0


# ============================================================================
# POINTER GRAB INTERFACE
# ============================================================================

func pointer_grab_set_distance(new_distance: float, pointer: Node3D) -> void:
	if not pointer or not is_instance_valid(pointer):
		return
	var pointer_forward: Vector3 = -pointer.global_transform.basis.z.normalized()
	var pointer_origin: Vector3 = pointer.global_transform.origin
	var new_position: Vector3 = pointer_origin + pointer_forward * new_distance
	global_position = new_position
	var direction: Vector3 = (global_position - pointer_origin).normalized()
	if direction.length_squared() > 0.001:
		var look_away_point: Vector3 = global_position + direction
		look_at(look_away_point, Vector3.UP)


func pointer_grab_set_scale(new_scale: float) -> void:
	scale = Vector3.ONE * new_scale


func pointer_grab_set_rotation(pointer: Node3D, grab_point: Vector3 = Vector3.INF) -> void:
	if not pointer or not is_instance_valid(pointer):
		return
	
	var pointer_origin: Vector3 = pointer.global_transform.origin
	var direction: Vector3 = Vector3.ZERO
	
	if grab_point.is_finite():
		direction = (grab_point - pointer_origin).normalized()
	else:
		direction = (global_position - pointer_origin).normalized()
	
	if direction.length_squared() > 0.001:
		var look_away_point: Vector3 = global_position + direction
		look_at(look_away_point, Vector3.UP)


func pointer_grab_get_distance(pointer: Node3D) -> float:
	if not pointer or not is_instance_valid(pointer):
		return 1.0
	return global_position.distance_to(pointer.global_position)


func pointer_grab_get_scale() -> float:
	return scale.x
