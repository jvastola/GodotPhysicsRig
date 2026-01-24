# Erase - Handles erase/undo functionality for the marker
# Based on VRCMarker implementation
extends RigidBody3D
class_name Erase

# Configuration
@export var marker_trail: Node

# State
var _last_time: float = 0.0
var _interact_down: bool = false
var _prev_trigger_pressed: bool = false
var _is_desktop_grabbed: bool = false
var disable_interactive: bool = false

const HoldDelay: float = 0.3
const InteractText: String = "Click - Undo\nHold - Erase All"

# Synced state
@export var last_remote_position: Vector3 = Vector3.ZERO
@export var erase_count: int = 0


func _ready() -> void:
	# Enable contact monitoring for interaction detection
	contact_monitor = true
	max_contacts_reported = 10
	
	# Connect to desktop grab signals
	# In a real implementation, you'd connect to the desktop grab system
	# For now, we'll use a simple approach
	
	print("Erase: Ready")


func _on_interacted() -> void:
	"""Called when the erase object is interacted with"""
	_last_time = Time.get_ticks_msec() / 1000.0
	_interact_down = true


func _physics_process(_delta: float) -> void:
	# Check for desktop grab (simplified - grab when mouse is over and clicked)
	# In a real implementation, you'd use raycasting or area detection
	# Check for desktop grab (simplified - grab when mouse is over and clicked)
	# In a real implementation, you'd use raycasting or area detection
	if disable_interactive:
		return
		
	if not _is_desktop_grabbed:
		# Check if mouse is over the object
		var mouse_pos = get_viewport().get_mouse_position()
		var camera = get_viewport().get_camera_3d()
		if camera:
			var ray_origin = camera.project_ray_origin(mouse_pos)
			var ray_end = ray_origin + camera.project_ray_normal(mouse_pos) * 100.0
			var space_state = get_world_3d().direct_space_state
			var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
			var result = space_state.intersect_ray(query)
			
			if result and result.collider == self:
				if Input.is_action_just_pressed("trigger_click"):
					_is_desktop_grabbed = true
					# Position the object in front of the camera
					global_position = camera.global_position + camera.global_transform.basis.z * -2.0
					print("Erase: Desktop grabbed")
	
	# Check for desktop release
	if _is_desktop_grabbed:
		if Input.is_action_just_pressed("trigger_click"):
			_is_desktop_grabbed = false
			_interact_down = false
			print("Erase: Desktop released")
			return
	
	if not _interact_down:
		return
	
	# Check for release
	var trigger_pressed: bool = false
	
	# Fallback to InputMap for desktop
	if InputMap.has_action("trigger_click") and Input.is_action_pressed("trigger_click"):
		trigger_pressed = true
	
	if not trigger_pressed and _prev_trigger_pressed:
		_on_interact_up()
		_interact_down = false
	
	_prev_trigger_pressed = trigger_pressed


func _on_interact_up() -> void:
	"""Called when interact is released"""
	var held_time = (Time.get_ticks_msec() / 1000.0) - _last_time
	
	if held_time < HoldDelay:
		undo()
	else:
		erase_all_networked()


func erase_all_networked() -> void:
	"""Erase all - networked version"""
	# In Godot, we'd send a network event
	# For now, just call erase_all directly
	erase_all()


func erase_all() -> void:
	"""Erase all lines"""
	if marker_trail and marker_trail.has_method("clear"):
		marker_trail.clear()


func undo() -> void:
	"""Undo last line"""
	if not marker_trail or not marker_trail.has_method("remove_last_line_connection"):
		return
	
	var length = marker_trail.remove_last_line_connection()
	erase_count = length
	last_remote_position = marker_trail.get_last_line_position()
	
	# In VRC, this would call RequestSerialization()
	# In Godot, we'd handle this through the network manager


func on_deserialization() -> void:
	"""Called when data is deserialized (network sync)"""
	# Check if trail was synced, if the last position locally matches the remote one
	if not marker_trail or not marker_trail.has_method("get_last_line_position"):
		return
	
	var last_position_local = marker_trail.get_last_line_position()
	if last_position_local == last_remote_position:
		if marker_trail.has_method("remove_last_lines"):
			marker_trail.remove_last_lines(erase_count)
