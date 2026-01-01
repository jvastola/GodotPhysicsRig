extends Node3D
class_name WebviewViewport3D

## WebView Viewport 3D - Cross-platform web content display in VR
## Automatically selects the appropriate backend based on platform:
## - Android/Quest: GodotAndroidWebView
## - Desktop: gdCEF (Chromium Embedded Framework)
## - Fallback: Placeholder with installation instructions

@export var pointer_group: StringName = &"pointer_interactable"
@export var default_url: String = "https://www.google.com"
@export var ui_size: Vector2 = Vector2(1280, 720)
@export var quad_size: Vector2 = Vector2(2.56, 1.44)  # 16:9 aspect ratio
@export var debug_coordinates: bool = false
@export var flip_v: bool = true
@export var enable_resize: bool = true  # Enable corner resize handles
@export var min_scale: float = 0.5
@export var max_scale: float = 3.0

signal page_loaded(url: String)
signal page_loading(url: String)
signal close_requested
signal resize_started
signal resize_ended

@onready var viewport: SubViewport = $SubViewport
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var _static_body: StaticBody3D = $MeshInstance3D/StaticBody3D
@onready var _texture_rect: TextureRect = $SubViewport/BrowserUI/WebContent/ContentContainer/TextureRect
@onready var _placeholder_label: Label = $SubViewport/BrowserUI/WebContent/PlaceholderLabel
@onready var _scroll_bar: VScrollBar = $SubViewport/BrowserUI/WebContent/ContentContainer/ScrollBar

# URL Bar controls
@onready var _url_input: LineEdit = $SubViewport/BrowserUI/URLBar/URLInput
@onready var _back_button: Button = $SubViewport/BrowserUI/URLBar/BackButton
@onready var _forward_button: Button = $SubViewport/BrowserUI/URLBar/ForwardButton
@onready var _reload_button: Button = $SubViewport/BrowserUI/URLBar/ReloadButton
@onready var _go_button: Button = $SubViewport/BrowserUI/URLBar/GoButton
@onready var _loading_bar: ProgressBar = $SubViewport/BrowserUI/LoadingBar

# URL bar height in pixels (for determining if click is on URL bar or web content)
const URL_BAR_HEIGHT: int = 44
const RESIZE_CORNER_SIZE: float = 0.15  # Size of resize corner in UV space (0-1)

var _saved_static_body_layer: int = 0
var _last_mouse_pos: Vector2 = Vector2(-1, -1)
var _is_hovering: bool = false
var _is_pressed: bool = false
var _has_focus: bool = false
var _last_backend_press_pos: Vector2 = Vector2(-1, -1)

# Backend reference
var _backend: WebViewBackend = null
var _backend_available: bool = false
var _current_url: String = ""

# Scroll state - using simple JS scrolling
var _scroll_y: int = 0
var _scroll_height: int = 0
var _client_height: int = 0
var _scroll_info_timer: float = 0.0
const SCROLL_INFO_INTERVAL: float = 0.5

# Drag-to-scroll state
var _drag_start_pos: Vector2 = Vector2.ZERO
var _last_drag_pos: Vector2 = Vector2.ZERO
var _is_dragging: bool = false
var _accumulated_scroll: float = 0.0  # Accumulate small movements

# Resize state
var _is_resizing: bool = false
var _resize_start_scale: float = 1.0
var _resize_start_distance: float = 0.0
var _resize_corner: String = ""  # "bl", "br", "tl", "tr" for corners


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
	
	# Setup URL bar controls
	_setup_url_bar()
	
	# Initialize the appropriate backend
	_initialize_backend()
	
	set_process_input(true)


func _setup_url_bar() -> void:
	# Connect URL bar buttons
	if _back_button:
		_back_button.pressed.connect(_on_back_pressed)
	if _forward_button:
		_forward_button.pressed.connect(_on_forward_pressed)
	if _reload_button:
		_reload_button.pressed.connect(_on_reload_pressed)
	if _go_button:
		_go_button.pressed.connect(_on_go_pressed)
	
	# Connect URL input
	if _url_input:
		_url_input.text = default_url
		_url_input.text_submitted.connect(_on_url_submitted)
		# Connect focus signal to notify KeyboardManager
		_url_input.focus_entered.connect(_on_url_input_focus_entered)
		# Register with KeyboardManager for virtual keyboard support
		_register_url_input_with_keyboard()
	
	# Hide loading bar initially
	if _loading_bar:
		_loading_bar.visible = false
	
	# Hide Godot scrollbar - we use JS scrolling only to avoid double scrollbars
	if _scroll_bar:
		_scroll_bar.visible = false


func _on_url_input_focus_entered() -> void:
	# When URL input gets focus, notify KeyboardManager
	if KeyboardManager and KeyboardManager.instance and _url_input:
		KeyboardManager.instance.set_focus(_url_input, viewport)
		print("WebviewViewport3D: URL input received focus")


func _register_url_input_with_keyboard() -> void:
	call_deferred("_deferred_register_keyboard")


func _deferred_register_keyboard() -> void:
	if KeyboardManager and KeyboardManager.instance and _url_input:
		KeyboardManager.instance.register_control(_url_input, viewport)
		print("WebviewViewport3D: Registered URL input with KeyboardManager")


## Focus the URL input field and summon the keyboard
func focus_url_input() -> void:
	if _url_input:
		_url_input.grab_focus()
		_url_input.select_all()
		# Register and set focus with KeyboardManager
		if KeyboardManager and KeyboardManager.instance:
			KeyboardManager.instance.register_control(_url_input, viewport)
			KeyboardManager.instance.set_focus(_url_input, viewport)
			print("WebviewViewport3D: URL input focused")


func _on_back_pressed() -> void:
	go_back()


func _on_forward_pressed() -> void:
	go_forward()


func _on_reload_pressed() -> void:
	reload()


func _on_go_pressed() -> void:
	if _url_input:
		_navigate_to_url(_url_input.text)


func _on_url_submitted(url: String) -> void:
	_navigate_to_url(url)


func _navigate_to_url(url: String) -> void:
	if not url.begins_with("http://") and not url.begins_with("https://"):
		url = "https://" + url
	load_url(url)


func _update_nav_buttons() -> void:
	if _back_button:
		_back_button.disabled = not can_go_back()
	if _forward_button:
		_forward_button.disabled = not can_go_forward()


func _initialize_backend() -> void:
	var platform := OS.get_name()
	print("WebviewViewport3D: Initializing on platform: ", platform)
	
	# Calculate web content height (total height minus URL bar)
	var web_content_height: int = int(ui_size.y) - URL_BAR_HEIGHT
	
	var settings := {
		"width": int(ui_size.x),
		"height": web_content_height,
		"url": default_url,
		"parent_node": self,
		"texture_rect": _texture_rect,
	}
	
	if platform == "Android":
		_backend = _try_android_backend(settings)
	else:
		_backend = _try_desktop_backend(settings)
	
	if not _backend:
		_backend = _create_placeholder_backend(settings)
	
	if _backend:
		if _backend.has_signal("page_loaded"):
			_backend.page_loaded.connect(_on_backend_page_loaded)
		if _backend.has_signal("page_loading"):
			_backend.page_loading.connect(_on_backend_page_loading)
		if _backend.has_signal("load_progress"):
			_backend.load_progress.connect(_on_backend_load_progress)
		if _backend.has_signal("scroll_info_received"):
			_backend.scroll_info_received.connect(_on_backend_scroll_info)
		
		print("WebviewViewport3D: Using backend: ", _backend.get_backend_name())


func _try_android_backend(settings: Dictionary) -> WebViewBackend:
	if not Engine.has_singleton("GodotAndroidWebView"):
		print("WebviewViewport3D: GodotAndroidWebView not available")
		return null
	
	var backend := AndroidWebViewBackend.new()
	if backend.initialize(settings):
		_backend_available = true
		_hide_placeholder()
		return backend
	
	return null


func _try_desktop_backend(settings: Dictionary) -> WebViewBackend:
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
	if _url_input:
		_url_input.text = url
	_update_nav_buttons()
	if _loading_bar:
		_loading_bar.visible = false
	page_loaded.emit(url)


func _on_backend_page_loading(url: String) -> void:
	if _loading_bar:
		_loading_bar.visible = true
		_loading_bar.value = 0.0
	page_loading.emit(url)


func _on_backend_load_progress(progress: float) -> void:
	if _loading_bar:
		_loading_bar.value = progress
		if progress >= 1.0:
			_loading_bar.visible = false


func _on_backend_scroll_info(_scroll_y: int, _scroll_height: int, _client_height: int) -> void:
	# Scroll info received but not used - Godot scrollbar is hidden
	# JS scrolling handles everything directly
	pass


func _on_scroll_bar_changed(_value: float) -> void:
	# VScrollBar is hidden - scrolling handled via JS in handle_pointer_event
	pass


func _process(delta: float) -> void:
	if _backend and _backend.has_method("update"):
		_backend.update(delta)
	
	# Periodically request scroll info to keep scrollbar in sync
	if _backend_available and _backend and _backend.has_method("request_scroll_info"):
		_scroll_info_timer += delta
		if _scroll_info_timer >= SCROLL_INFO_INTERVAL:
			_scroll_info_timer = 0.0
			_backend.request_scroll_info()


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
	if _url_input:
		_url_input.text = url
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
# POINTER EVENT HANDLING - Forward to SubViewport UI or WebView backend
# ============================================================================

func handle_pointer_event(event: Dictionary) -> void:
	if not viewport or not mesh_instance:
		return
	
	var event_type: String = String(event.get("type", ""))
	var hit_pos: Vector3 = event.get("global_position", Vector3.ZERO)
	var local_hit: Vector3 = mesh_instance.global_transform.affine_inverse() * hit_pos
	var uv: Vector2 = _world_to_uv(local_hit)
	var pointer: Node3D = event.get("pointer", null)
	
	if debug_coordinates:
		print("WebviewViewport3D: uv=", uv, " type=", event_type)
	
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		if _is_hovering:
			_send_mouse_exit()
		return
	
	var viewport_pos: Vector2 = Vector2(uv.x * ui_size.x, uv.y * ui_size.y)
	var is_on_url_bar: bool = viewport_pos.y < URL_BAR_HEIGHT
	var corner := _get_resize_corner(uv)
	
	match event_type:
		"enter", "hover":
			_send_mouse_motion(viewport_pos)
			_is_hovering = true
		"press":
			_send_mouse_motion(viewport_pos)
			_is_pressed = true
			
			# Check if pressing on resize corner
			if enable_resize and corner != "" and pointer:
				_start_resize(corner, pointer)
			else:
				_send_mouse_button(viewport_pos, true, event.get("action_just_pressed", true))
				# Start drag tracking for scrolling
				if not is_on_url_bar and _backend_available:
					_is_dragging = true
					_drag_start_pos = viewport_pos
					_last_drag_pos = viewport_pos
					_accumulated_scroll = 0.0
			set_focus(true)
		"hold":
			if _is_resizing and pointer:
				_update_resize(pointer)
			elif _is_dragging and not is_on_url_bar and _backend_available:
				# Calculate scroll delta
				var delta_y: float = viewport_pos.y - _last_drag_pos.y
				_last_drag_pos = viewport_pos
				
				# Accumulate scroll for smoother feel
				_accumulated_scroll += delta_y
				
				# Send scroll when accumulated enough (reduces jitter)
				if abs(_accumulated_scroll) > 2.0:
					# Invert and amplify for natural scrolling feel
					var scroll_amount: int = int(_accumulated_scroll * -1.5)
					_backend.scroll_by_amount(scroll_amount)
					_accumulated_scroll = 0.0
					if debug_coordinates:
						print("WebviewViewport3D: Scroll amount=", scroll_amount)
			else:
				_send_mouse_motion(viewport_pos)
				if not _is_pressed:
					_send_mouse_button(viewport_pos, true, true)
					_is_pressed = true
					if not is_on_url_bar and _backend_available:
						_is_dragging = true
						_drag_start_pos = viewport_pos
						_last_drag_pos = viewport_pos
						_accumulated_scroll = 0.0
		"release":
			if _is_resizing:
				_end_resize()
			else:
				_send_mouse_motion(viewport_pos)
				_send_mouse_button(viewport_pos, false, event.get("action_just_released", true))
				
				# Check if this was a tap (click) vs drag (scroll)
				if _is_dragging and _backend_available:
					var drag_distance := viewport_pos.distance_to(_drag_start_pos)
					if drag_distance < 15.0:  # Tap threshold
						var backend_pos := _viewport_to_backend_pos(viewport_pos)
						if _backend.has_method("tap"):
							_backend.tap(int(backend_pos.x), int(backend_pos.y))
						else:
							_backend.send_mouse_down(int(backend_pos.x), int(backend_pos.y), 0)
							_backend.send_mouse_up(int(backend_pos.x), int(backend_pos.y), 0)
						if debug_coordinates:
							print("WebviewViewport3D: Tap at ", backend_pos)
			
			# Clear states
			_is_dragging = false
			_drag_start_pos = Vector2.ZERO
			_last_drag_pos = Vector2.ZERO
			_accumulated_scroll = 0.0
			_last_backend_press_pos = Vector2(-1, -1)
			_is_pressed = false
		"scroll":
			_send_mouse_motion(viewport_pos)
			var scroll_value: float = event.get("scroll_value", 0.0)
			_send_scroll(viewport_pos, scroll_value)
			if not is_on_url_bar and _backend_available:
				var scroll_delta := int(scroll_value * 100)
				_backend.scroll_by_amount(-scroll_delta)
		"exit":
			_send_mouse_exit()
			_is_hovering = false
			if _is_resizing:
				_end_resize()
			_is_dragging = false
			_drag_start_pos = Vector2.ZERO
			_last_drag_pos = Vector2.ZERO
			_accumulated_scroll = 0.0
			_last_backend_press_pos = Vector2(-1, -1)
			_is_pressed = false


## Check if UV position is in a resize corner, returns corner name or empty string
func _get_resize_corner(uv: Vector2) -> String:
	if not enable_resize:
		return ""
	
	var corner_size := RESIZE_CORNER_SIZE
	
	# Bottom-left
	if uv.x < corner_size and uv.y > (1.0 - corner_size):
		return "bl"
	# Bottom-right
	if uv.x > (1.0 - corner_size) and uv.y > (1.0 - corner_size):
		return "br"
	# Top-left
	if uv.x < corner_size and uv.y < corner_size:
		return "tl"
	# Top-right
	if uv.x > (1.0 - corner_size) and uv.y < corner_size:
		return "tr"
	
	return ""


func _start_resize(corner: String, pointer: Node3D) -> void:
	_is_resizing = true
	_resize_corner = corner
	_resize_start_scale = scale.x
	_resize_start_distance = global_position.distance_to(pointer.global_position)
	resize_started.emit()
	if debug_coordinates:
		print("WebviewViewport3D: Resize started from corner ", corner)


func _update_resize(pointer: Node3D) -> void:
	if not _is_resizing or not pointer:
		return
	
	var current_distance := global_position.distance_to(pointer.global_position)
	var scale_factor := current_distance / _resize_start_distance
	var new_scale := clamp(_resize_start_scale * scale_factor, min_scale, max_scale)
	
	scale = Vector3.ONE * new_scale


func _end_resize() -> void:
	_is_resizing = false
	_resize_corner = ""
	resize_ended.emit()
	if debug_coordinates:
		print("WebviewViewport3D: Resize ended, scale=", scale.x)


func _viewport_to_backend_pos(viewport_pos: Vector2) -> Vector2:
	# Convert viewport position to backend position (offset by URL bar height)
	return Vector2(viewport_pos.x, viewport_pos.y - URL_BAR_HEIGHT)


func _world_to_uv(local_pos: Vector3) -> Vector2:
	var half_size: Vector2 = quad_size * 0.5
	if half_size.x == 0 or half_size.y == 0:
		return Vector2(-1, -1)
	
	var u: float = (local_pos.x / half_size.x) * 0.5 + 0.5
	var v: float = (local_pos.y / half_size.y) * 0.5 + 0.5
	
	if flip_v:
		v = 1.0 - v
	
	return Vector2(u, v)


func _send_mouse_motion(pos: Vector2) -> void:
	if not viewport:
		return
	
	var motion_event := InputEventMouseMotion.new()
	motion_event.position = pos
	motion_event.global_position = pos
	
	if _last_mouse_pos.x >= 0:
		motion_event.relative = pos - _last_mouse_pos
	else:
		motion_event.relative = Vector2.ZERO
	
	_last_mouse_pos = pos
	viewport.push_input(motion_event)
	
	# Don't send mouse move to backend during normal hover - only during active interactions
	# This prevents interference with scrolling


func _send_mouse_button(pos: Vector2, pressed: bool, just_changed: bool) -> void:
	if not viewport or not just_changed:
		return
	
	var button_event := InputEventMouseButton.new()
	button_event.position = pos
	button_event.global_position = pos
	button_event.button_index = MOUSE_BUTTON_LEFT
	button_event.pressed = pressed
	
	viewport.push_input(button_event)


func _send_scroll(pos: Vector2, amount: float) -> void:
	if not viewport:
		return
	if abs(amount) <= 0.001:
		return
	
	var scroll_event := InputEventMouseButton.new()
	scroll_event.position = pos
	scroll_event.global_position = pos
	scroll_event.button_index = MOUSE_BUTTON_WHEEL_UP if amount > 0.0 else MOUSE_BUTTON_WHEEL_DOWN
	scroll_event.pressed = true
	scroll_event.factor = abs(amount)
	viewport.push_input(scroll_event)


func _send_mouse_exit() -> void:
	if _last_mouse_pos.x >= 0 and viewport:
		var exit_pos := Vector2(-100, -100)
		var motion_event := InputEventMouseMotion.new()
		motion_event.position = exit_pos
		motion_event.global_position = exit_pos
		motion_event.relative = exit_pos - _last_mouse_pos
		viewport.push_input(motion_event)
	
	_last_mouse_pos = Vector2(-1, -1)
	_is_hovering = false
	_is_pressed = false


# ============================================================================
# KEYBOARD INPUT
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
