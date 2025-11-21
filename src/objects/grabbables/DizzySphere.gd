extends Grabbable
class_name DizzySphere

# Fun grabbable that continuously rotates the camera while held
# Creates a dizzying spinning effect!

var xr_camera: Camera3D = null
var desktop_camera: Camera3D = null
var rotation_speed: float = 1.5  # Radians per second
var is_spinning: bool = false


func _ready() -> void:
	super._ready()
	
	# Connect to grab signals
	grabbed.connect(_on_grabbed)
	released.connect(_on_released)


func _on_grabbed(_hand: RigidBody3D) -> void:
	"""When grabbed, start rotating the camera"""
	# Find the cameras through the scene tree
	var xr_player = get_tree().get_first_node_in_group("xr_player")
	
	if xr_player:
		xr_camera = xr_player.get_node_or_null("PlayerBody/XROrigin3D/XRCamera3D")
		desktop_camera = xr_player.get_node_or_null("PlayerBody/DesktopCamera")
		
		is_spinning = true
		print("DizzySphere: Camera spinning started - hold on tight!")


func _on_released() -> void:
	"""When released, stop rotating the camera"""
	is_spinning = false
	
	xr_camera = null
	desktop_camera = null
	
	print("DizzySphere: Camera spinning stopped")


func _process(delta: float) -> void:
	if is_spinning:
		# Rotate cameras around their forward axis (roll)
		var rotation_delta = rotation_speed * delta
		
		if xr_camera and is_instance_valid(xr_camera):
			# Rotate around the Z-axis (forward/backward axis for roll)
			xr_camera.rotate_object_local(Vector3.FORWARD, rotation_delta)
		
		if desktop_camera and is_instance_valid(desktop_camera):
			# Rotate around the Z-axis (forward/backward axis for roll)
			desktop_camera.rotate_object_local(Vector3.FORWARD, rotation_delta)
