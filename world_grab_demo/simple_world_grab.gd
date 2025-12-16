extends Node3D

# Simple World Grab Movement - handles world grab locomotion
# Based on the original XRToolsMovementWorldGrab

@onready var origin_node: XROrigin3D = get_parent()
@onready var camera_node: XRCamera3D = origin_node.get_node("XRCamera3D")
@onready var left_pickup: Node3D = origin_node.get_node("LeftHand/SimplePickup")
@onready var right_pickup: Node3D = origin_node.get_node("RightHand/SimplePickup")
@onready var left_controller: XRController3D = origin_node.get_node("LeftHand")
@onready var right_controller: XRController3D = origin_node.get_node("RightHand")

var left_handle = null
var right_handle = null
var is_grabbing = false

# Debug timer to avoid spam
var debug_timer = 0.0

func _ready():
	# Connect pickup signals
	if left_pickup:
		left_pickup.grabbed.connect(_on_left_grabbed)
		left_pickup.released.connect(_on_left_released)
	if right_pickup:
		right_pickup.grabbed.connect(_on_right_grabbed)
		right_pickup.released.connect(_on_right_released)

func _physics_process(delta):
	debug_timer += delta
	
	# Check for valid handles
	if not is_instance_valid(left_handle):
		left_handle = null
	if not is_instance_valid(right_handle):
		right_handle = null
	
	# Update grabbing state
	is_grabbing = left_handle != null or right_handle != null
	
	# Skip if no handles
	if not is_grabbing:
		return
	
	# Calculate movement offset
	var offset = Vector3.ZERO
	
	if left_handle and not right_handle:
		# Left hand only
		var left_pickup_pos = left_controller.global_position
		var left_grab_pos = left_handle.global_position
		offset = left_pickup_pos - left_grab_pos
		
	elif right_handle and not left_handle:
		# Right hand only
		var right_pickup_pos = right_controller.global_position
		var right_grab_pos = right_handle.global_position
		offset = right_pickup_pos - right_grab_pos
		
	else:
		# Both hands - rotation and scaling (matching original logic)
		var left_grab_pos = left_handle.global_position
		var right_grab_pos = right_handle.global_position
		
		# Use slide to get horizontal component (like original uses up_player)
		var up_vector = Vector3.UP
		var grab_l2r = (right_grab_pos - left_grab_pos).slide(up_vector)
		var grab_mid = (left_grab_pos + right_grab_pos) * 0.5
		
		var left_pickup_pos = left_controller.global_position
		var right_pickup_pos = right_controller.global_position
		var pickup_l2r = (right_pickup_pos - left_pickup_pos).slide(up_vector)
		var pickup_mid = (left_pickup_pos + right_pickup_pos) * 0.5
		
		# Debug output
		if debug_timer > 0.5:
			debug_timer = 0.0
			print("=== Two Hand Grab Debug ===")
			print("grab_l2r: ", grab_l2r, " len: ", grab_l2r.length())
			print("pickup_l2r: ", pickup_l2r, " len: ", pickup_l2r.length())
		
		# Apply rotation (matching original - uses up_vector for signed_angle_to)
		if grab_l2r.length() > 0.01 and pickup_l2r.length() > 0.01:
			var angle = grab_l2r.signed_angle_to(pickup_l2r, up_vector)
			
			if debug_timer < 0.1:
				print("Rotation angle: ", rad_to_deg(angle), " degrees")
			
			_rotate_player(angle)
		
		# Apply scale
		if grab_l2r.length() > 0.01 and pickup_l2r.length() > 0.01:
			var new_world_scale = XRServer.world_scale * grab_l2r.length() / pickup_l2r.length()
			new_world_scale = clamp(new_world_scale, 0.5, 10.0)
			XRServer.world_scale = new_world_scale
		
		# Calculate offset from midpoint
		offset = pickup_mid - grab_mid
	
	# Apply movement (move origin opposite to offset)
	if offset.length() > 0.001:
		origin_node.global_transform.origin -= offset

func _rotate_player(angle: float):
	# Rotate the XROrigin3D around the camera (matching original player_body.rotate_player)
	if not camera_node:
		return
	
	var t1 = Transform3D()
	var t2 = Transform3D()
	var rot = Transform3D()
	
	# Original uses Vector3.DOWN for rotation axis
	t1.origin = -camera_node.transform.origin
	t2.origin = camera_node.transform.origin
	rot = rot.rotated(Vector3.DOWN, angle)
	
	origin_node.transform = (origin_node.transform * t2 * rot * t1).orthonormalized()

func _on_left_grabbed(_what):
	left_handle = left_pickup.get_grab_handle()
	print("Left grabbed, handle: ", left_handle)

func _on_left_released():
	left_handle = null
	print("Left released")

func _on_right_grabbed(_what):
	right_handle = right_pickup.get_grab_handle()
	print("Right grabbed, handle: ", right_handle)

func _on_right_released():
	right_handle = null
	print("Right released")