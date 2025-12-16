extends Node3D

# Simple XR Setup - handles basic XR initialization

func _ready():
	# Initialize XR
	var xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		print("OpenXR initialized")
		get_viewport().use_xr = true
	else:
		print("OpenXR not available, running in desktop mode")