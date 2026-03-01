extends Node3D

## Simple loading scene that displays a 10-second timer/progress.
## Transition logic is handled by the parent (LegalGate).

@onready var xr_camera: XRCamera3D = get_node_or_null("MinimalXRPointerRig/XROrigin3D/XRCamera3D") as XRCamera3D
@onready var desktop_camera: Camera3D = get_node_or_null("MinimalXRPointerRig/DesktopCamera") as Camera3D

func _ready() -> void:
	_configure_cameras()
	_play_delayed_sound()


func _play_delayed_sound() -> void:
	await get_tree().create_timer(0.5).timeout
	var spawn_sound = get_node_or_null("Floor/Spawn") as AudioStreamPlayer3D
	if spawn_sound:
		spawn_sound.play()


func _configure_cameras() -> void:
	var xr_interface := XRServer.find_interface("OpenXR")
	var xr_active := xr_interface != null and xr_interface.is_initialized()
	if xr_active and xr_camera:
		xr_camera.current = true
	if not xr_active and desktop_camera:
		desktop_camera.current = true
