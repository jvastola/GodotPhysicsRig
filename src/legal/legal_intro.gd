extends Node3D

signal legal_accepted

@export var panel_distance: float = 1.5
@export var panel_height_offset: float = 0.0
@export var required_hold_time: float = 1.5

@onready var pointer_rig: Node3D = get_node_or_null("MinimalXRPointerRig") as Node3D
@onready var xr_camera: XRCamera3D = get_node_or_null("MinimalXRPointerRig/XROrigin3D/XRCamera3D") as XRCamera3D
@onready var desktop_camera: Camera3D = get_node_or_null("MinimalXRPointerRig/DesktopCamera") as Camera3D
@onready var legal_panel: Node3D = get_node_or_null("LegalViewport3D") as Node3D
@onready var legal_ui: Node = get_node_or_null("LegalViewport3D/SubViewport/LegalPanelUI")
@onready var world_environment: WorldEnvironment = get_node_or_null("WorldEnvironment") as WorldEnvironment

var _blend_applied := false
var _input_hold_active := false


func _ready() -> void:
	_configure_passthrough_environment()
	_configure_cameras()
	_connect_panel()


func _process(_delta: float) -> void:
	_position_panel_in_front()
	_poll_accept_input()


func _configure_passthrough_environment() -> void:
	# Attempt to enable alpha-blend passthrough so the user sees their real world.
	var xr_interface := XRServer.find_interface("OpenXR")
	if xr_interface:
		var supports_alpha := true
		if xr_interface.has_method("get_supported_environment_blend_modes"):
			var modes: PackedInt32Array = xr_interface.get_supported_environment_blend_modes()
			supports_alpha = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in modes
		if supports_alpha:
			if xr_interface.has_method("set_environment_blend_mode"):
				xr_interface.set_environment_blend_mode(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND)
			else:
				xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
			_blend_applied = true
	
	var root_viewport := get_viewport()
	if root_viewport:
		root_viewport.transparent_bg = true
	
	if world_environment and world_environment.environment:
		var env := world_environment.environment
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.background_color = Color(0, 0, 0, 0)


func _connect_panel() -> void:
	if not legal_ui:
		return
	if legal_ui.has_method("set"):
		legal_ui.set("required_hold_time", required_hold_time)
	if legal_ui.has_signal("accepted"):
		legal_ui.connect("accepted", Callable(self, "_on_panel_accepted"))


func _position_panel_in_front() -> void:
	var cam := _get_active_camera()
	if not cam or not legal_panel:
		return
	var forward: Vector3 = -cam.global_transform.basis.z.normalized()
	if forward.length_squared() < 0.0001:
		return
	var target_position: Vector3 = cam.global_position + forward * panel_distance + Vector3(0, panel_height_offset, 0)
	var basis := Basis()
	basis = basis.looking_at(forward, Vector3.UP)
	legal_panel.global_transform = Transform3D(basis, target_position)


func _on_panel_accepted() -> void:
	emit_signal("legal_accepted")


func _configure_cameras() -> void:
	var xr_interface := XRServer.find_interface("OpenXR")
	var xr_active := xr_interface != null and xr_interface.is_initialized()
	if xr_active and xr_camera:
		xr_camera.current = true
	if not xr_active and desktop_camera:
		desktop_camera.current = true


func _get_active_camera() -> Camera3D:
	var xr_interface := XRServer.find_interface("OpenXR")
	var xr_active := xr_interface != null and xr_interface.is_initialized()
	if xr_active and xr_camera:
		return xr_camera
	return desktop_camera


func _poll_accept_input() -> void:
	var pressed := _is_accept_pressed()
	if pressed and not _input_hold_active:
		_input_hold_active = true
		if legal_ui and legal_ui.has_method("begin_accept_hold"):
			legal_ui.call("begin_accept_hold")
	elif not pressed and _input_hold_active:
		_input_hold_active = false
		if legal_ui and legal_ui.has_method("end_accept_hold"):
			legal_ui.call("end_accept_hold")


func _is_accept_pressed() -> bool:
	# Support A/X (common on Quest controllers), trigger_click action, and Space for desktop.
	if InputMap.has_action("trigger_click") and Input.is_action_pressed("trigger_click"):
		return true
	if Input.is_key_pressed(KEY_SPACE):
		return true
	# Check common joypad devices (0 and 1) for A/X
	if Input.is_joy_button_pressed(0, JOY_BUTTON_A) or Input.is_joy_button_pressed(0, JOY_BUTTON_X):
		return true
	if Input.is_joy_button_pressed(1, JOY_BUTTON_A) or Input.is_joy_button_pressed(1, JOY_BUTTON_X):
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	# Forward accept holds at the scene level so the user does not need to point at the UI.
	if not legal_ui:
		return
	var is_accept_btn: bool = event is InputEventJoypadButton and (event.button_index == JOY_BUTTON_A or event.button_index == JOY_BUTTON_X)
	var is_space: bool = event is InputEventKey and event.keycode == KEY_SPACE
	if is_accept_btn or is_space:
		if event.is_pressed() and not event.is_echo():
			if legal_ui.has_method("begin_accept_hold"):
				legal_ui.call("begin_accept_hold")
		elif not event.is_pressed():
			if legal_ui.has_method("end_accept_hold"):
				legal_ui.call("end_accept_hold")
