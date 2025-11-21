extends Grabbable
class_name CameraFlipper

# Fun grabbable that flips the camera upside down when held
# Makes for a disorienting but hilarious experience!

var xr_camera: Camera3D = null
var desktop_camera: Camera3D = null
var original_xr_rotation: Basis = Basis.IDENTITY
var original_desktop_rotation: Basis = Basis.IDENTITY
var is_flipped: bool = false


func _ready() -> void:
	super._ready()
	
	# Connect to grab signals
	grabbed.connect(_on_grabbed)
	released.connect(_on_released)


func _on_grabbed(_hand: RigidBody3D) -> void:
	"""When grabbed, flip the camera upside down"""
	# Find the cameras through the scene tree
	var xr_player = get_tree().get_first_node_in_group("xr_player")
	
	if xr_player:
		xr_camera = xr_player.get_node_or_null("PlayerBody/XROrigin3D/XRCamera3D")
		desktop_camera = xr_player.get_node_or_null("PlayerBody/DesktopCamera")
		
		# Store original rotations
		if xr_camera:
			original_xr_rotation = xr_camera.transform.basis
		if desktop_camera:
			original_desktop_rotation = desktop_camera.transform.basis
		
		# Flip both cameras
		_flip_cameras(true)
		
		print("CameraFlipper: Camera flipped upside down!")


func _on_released() -> void:
	"""When released, restore the camera orientation"""
	_flip_cameras(false)
	
	xr_camera = null
	desktop_camera = null
	
	print("CameraFlipper: Camera restored")


func _flip_cameras(flip: bool) -> void:
	"""Flip or unflip the cameras"""
	is_flipped = flip
	
	if xr_camera and is_instance_valid(xr_camera):
		if flip:
			# Rotate 180 degrees around the forward axis (Z-axis)
			var flip_rotation = Basis(Vector3.FORWARD, PI)
			xr_camera.transform.basis = original_xr_rotation * flip_rotation
		else:
			# Restore original rotation
			xr_camera.transform.basis = original_xr_rotation
	
	if desktop_camera and is_instance_valid(desktop_camera):
		if flip:
			# Rotate 180 degrees around the forward axis (Z-axis)
			var flip_rotation = Basis(Vector3.FORWARD, PI)
			desktop_camera.transform.basis = original_desktop_rotation * flip_rotation
		else:
			# Restore original rotation
			desktop_camera.transform.basis = original_desktop_rotation
