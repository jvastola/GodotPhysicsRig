# Grabbable Object
# Can be picked up by physics hands in VR
extends RigidBody3D

enum GrabMode {
	FREE_GRAB,      # Object maintains its orientation relative to hand
	ANCHOR_GRAB     # Object snaps to a specific anchor point/rotation
}

@export var grab_mode: GrabMode = GrabMode.ANCHOR_GRAB
@export var grab_anchor_offset: Vector3 = Vector3.ZERO
@export var grab_anchor_rotation: Vector3 = Vector3.ZERO

# Internal state
var is_grabbed := false
var grabbing_hand: RigidBody3D = null
var original_parent: Node = null
var grab_offset: Vector3 = Vector3.ZERO
var grab_rotation_offset: Quaternion = Quaternion.IDENTITY

signal grabbed(hand: RigidBody3D)
signal released()


func _ready() -> void:
	# Enable contact monitoring for grab detection
	contact_monitor = true
	max_contacts_reported = 4
	
	# Add to grabbable group for easy detection
	add_to_group("grabbable")


func try_grab(hand: RigidBody3D) -> bool:
	"""Attempt to grab this object with a hand"""
	if is_grabbed:
		return false
	
	is_grabbed = true
	grabbing_hand = hand
	original_parent = get_parent()
	
	# Store the offset based on grab mode
	if grab_mode == GrabMode.FREE_GRAB:
		# Store relative position and rotation at moment of grab
		grab_offset = global_position - hand.global_position
		var hand_quat = hand.global_transform.basis.get_rotation_quaternion()
		var obj_quat = global_transform.basis.get_rotation_quaternion()
		grab_rotation_offset = obj_quat * hand_quat.inverse()
	else:  # ANCHOR_GRAB
		# Use the exported anchor offset and rotation
		grab_offset = grab_anchor_offset
		grab_rotation_offset = Quaternion(Vector3.FORWARD, grab_anchor_rotation.z) * \
		                       Quaternion(Vector3.UP, grab_anchor_rotation.y) * \
		                       Quaternion(Vector3.RIGHT, grab_anchor_rotation.x)
	
	# Disable gravity while held
	gravity_scale = 0.0
	
	# Reduce collision with world while held
	collision_mask = 0
	
	grabbed.emit(hand)
	print("Grabbable: Object grabbed by ", hand.name)
	return true


func release() -> void:
	"""Release the object from the hand"""
	if not is_grabbed:
		return
	
	print("Grabbable: Object released")
	
	# Re-enable physics
	gravity_scale = 1.0
	collision_mask = 1
	
	# Inherit hand velocity for throwing
	if grabbing_hand:
		linear_velocity = grabbing_hand.linear_velocity
		angular_velocity = grabbing_hand.angular_velocity * 0.5
	
	is_grabbed = false
	grabbing_hand = null
	
	released.emit()


func _physics_process(_delta: float) -> void:
	if is_grabbed and grabbing_hand:
		_follow_hand()


func _follow_hand() -> void:
	"""Make the object follow the grabbing hand"""
	if not is_instance_valid(grabbing_hand):
		release()
		return
	
	# Calculate target position and rotation
	var target_pos: Vector3
	var target_rot: Quaternion
	
	if grab_mode == GrabMode.FREE_GRAB:
		# Maintain the offset from when we grabbed
		var hand_quat = grabbing_hand.global_transform.basis.get_rotation_quaternion()
		target_rot = hand_quat * grab_rotation_offset
		target_pos = grabbing_hand.global_position + hand_quat * grab_offset
	else:  # ANCHOR_GRAB
		# Follow hand with fixed anchor offset
		var hand_basis = grabbing_hand.global_transform.basis
		target_pos = grabbing_hand.global_position + hand_basis * grab_offset
		target_rot = grabbing_hand.global_transform.basis.get_rotation_quaternion() * grab_rotation_offset
	
	# Smoothly move to target (using forces for physics)
	var pos_error = target_pos - global_position
	var force_strength = 1000.0  # Adjust for responsiveness
	apply_central_force(pos_error * force_strength * mass)
	
	# Damp velocity to prevent oscillation
	apply_central_force(-linear_velocity * mass * 10.0)
	
	# Apply rotational forces
	var target_basis = Basis(target_rot)
	var current_basis = global_transform.basis
	
	# Calculate rotation needed
	var rotation_diff = target_basis * current_basis.inverse()
	var axis = rotation_diff.get_rotation_quaternion().get_axis()
	var angle = rotation_diff.get_rotation_quaternion().get_angle()
	
	if not axis.is_zero_approx() and abs(angle) > 0.001:
		var torque = axis * angle * 500.0  # Adjust for responsiveness
		apply_torque(torque)
	
	# Damp angular velocity
	apply_torque(-angular_velocity * 5.0)
