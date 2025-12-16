class_name SceneEnvironmentSetup
extends Node
## Configures the environment settings when a scene loads.
## Add this to scenes that should have specific passthrough/environment settings.

## Whether passthrough should be enabled for this scene
@export var enable_passthrough: bool = false

## Whether to restore the skybox when passthrough is disabled
@export var restore_skybox: bool = true

var _xr_interface: XRInterface
var _world_environment: WorldEnvironment
var _root_viewport: Viewport


func _ready() -> void:
	call_deferred("_setup_environment")


func _setup_environment() -> void:
	_xr_interface = XRServer.find_interface("OpenXR")
	_root_viewport = get_viewport()
	_find_world_environment()
	
	if enable_passthrough:
		_enable_passthrough()
	else:
		_disable_passthrough()


func _find_world_environment() -> void:
	var parent := get_parent()
	if parent:
		var env_node := parent.get_node_or_null("WorldEnvironment")
		if env_node and env_node is WorldEnvironment:
			_world_environment = env_node
			return
	
	# Search in tree
	var root := get_tree().root
	if root:
		var found := root.find_child("WorldEnvironment", true, false)
		if found and found is WorldEnvironment:
			_world_environment = found


func _enable_passthrough() -> void:
	if not _xr_interface:
		return
	
	var supports_alpha := _supports_alpha_passthrough()
	if not supports_alpha:
		print("SceneEnvironmentSetup: Passthrough not supported")
		return
	
	_set_blend_mode(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND)
	
	if _root_viewport:
		_root_viewport.transparent_bg = true
	
	if _world_environment and _world_environment.environment:
		var env := _world_environment.environment
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.background_color = Color(0, 0, 0, 0)
	
	print("SceneEnvironmentSetup: Passthrough enabled")


func _disable_passthrough() -> void:
	if not _xr_interface:
		return
	
	_set_blend_mode(XRInterface.XR_ENV_BLEND_MODE_OPAQUE)
	
	if _root_viewport:
		_root_viewport.transparent_bg = false
	
	if restore_skybox and _world_environment and _world_environment.environment:
		var env := _world_environment.environment
		# Restore to sky mode if available
		if env.sky:
			env.background_mode = Environment.BG_SKY
		else:
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.3, 0.3, 0.4, 1.0)
	
	print("SceneEnvironmentSetup: Passthrough disabled")


func _supports_alpha_passthrough() -> bool:
	if not _xr_interface:
		return false
	if _xr_interface.has_method("get_supported_environment_blend_modes"):
		var supported: PackedInt32Array = _xr_interface.get_supported_environment_blend_modes()
		return XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in supported
	return true


func _set_blend_mode(mode: int) -> void:
	if not _xr_interface:
		return
	if _xr_interface.has_method("set_environment_blend_mode"):
		_xr_interface.set_environment_blend_mode(mode)
	else:
		_xr_interface.environment_blend_mode = mode as XRInterface.EnvironmentBlendMode
