@tool
class_name XRToolsRumbleManager
extends Node

## Get the default haptics scale from project settings
static func get_default_haptics_scale() -> float:
	var scale = 1.0
	
	if ProjectSettings.has_setting("godot_xr_tools/input/haptics_scale"):
		scale = ProjectSettings.get_setting("godot_xr_tools/input/haptics_scale")
	
	if !(scale >= 0.0 and scale <= 1.0):
		# out of bounds? reset to default
		scale = 1.0
	
	return scale