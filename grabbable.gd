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

# Store collision data during grab
var grabbed_collision_shapes: Array = []
var grabbed_mesh_instances: Array = []

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
	
	# Calculate the offset in hand's local space
	var hand_inv = hand.global_transform.affine_inverse()
	var obj_to_hand = hand_inv * global_transform
	
	if grab_mode == GrabMode.FREE_GRAB:
		# Store relative position and rotation at moment of grab in local space
		grab_offset = obj_to_hand.origin
		grab_rotation_offset = obj_to_hand.basis.get_rotation_quaternion()
	else:  # ANCHOR_GRAB
		# Use the exported anchor offset and rotation
		grab_offset = grab_anchor_offset
		grab_rotation_offset = Quaternion(Vector3.FORWARD, grab_anchor_rotation.z) * \
		                       Quaternion(Vector3.UP, grab_anchor_rotation.y) * \
		                       Quaternion(Vector3.RIGHT, grab_anchor_rotation.x)
	
	# Clone collision shapes and meshes as direct children of the hand
	grabbed_collision_shapes.clear()
	grabbed_mesh_instances.clear()
	
	for child in get_children():
		if child is CollisionShape3D and child.shape:
			# Create new collision shape as direct child of hand
			var new_collision = CollisionShape3D.new()
			new_collision.shape = child.shape
			# Transform is relative to this object, need to convert to hand space
			new_collision.transform = Transform3D(Basis(grab_rotation_offset), grab_offset) * child.transform
			new_collision.name = name + "_grabbed_collision_" + str(grabbed_collision_shapes.size())
			hand.add_child(new_collision)
			grabbed_collision_shapes.append(new_collision)
			
		elif child is MeshInstance3D and child.mesh:
			# Create new mesh instance as visual
			var new_mesh = MeshInstance3D.new()
			new_mesh.mesh = child.mesh
			new_mesh.transform = Transform3D(Basis(grab_rotation_offset), grab_offset) * child.transform
			new_mesh.name = name + "_grabbed_mesh_" + str(grabbed_mesh_instances.size())
			hand.add_child(new_mesh)
			grabbed_mesh_instances.append(new_mesh)
	
	# Hide original object (keep it around for release)
	visible = false
	# Disable collision on the original
	collision_layer = 0
	collision_mask = 0
	# Freeze it in place
	freeze = true
	
	grabbed.emit(hand)
	print("Grabbable: Object grabbed by ", hand.name)
	return true


func release() -> void:
	"""Release the object from the hand"""
	if not is_grabbed:
		return
	
	print("Grabbable: Object released")
	
	# Calculate global transform from first grabbed collision shape if available
	var release_global_transform = global_transform
	if grabbed_collision_shapes.size() > 0 and is_instance_valid(grabbed_collision_shapes[0]):
		release_global_transform = grabbed_collision_shapes[0].global_transform
	
	# Store hand velocity
	var hand_velocity = Vector3.ZERO
	var hand_angular_velocity = Vector3.ZERO
	
	if is_instance_valid(grabbing_hand):
		hand_velocity = grabbing_hand.linear_velocity
		hand_angular_velocity = grabbing_hand.angular_velocity * 0.5
		
		# Remove all grabbed collision shapes and meshes from hand
		for collision_shape in grabbed_collision_shapes:
			if is_instance_valid(collision_shape):
				grabbing_hand.remove_child(collision_shape)
				collision_shape.queue_free()
		
		for mesh_instance in grabbed_mesh_instances:
			if is_instance_valid(mesh_instance):
				grabbing_hand.remove_child(mesh_instance)
				mesh_instance.queue_free()
	
	grabbed_collision_shapes.clear()
	grabbed_mesh_instances.clear()
	
	# Restore object visibility and physics
	visible = true
	freeze = false
	gravity_scale = 1.0
	collision_layer = 1  # Default layer
	collision_mask = 1   # Collide with world
	
	# Set global transform to where the grabbed shape was
	global_transform = release_global_transform
	
	# Inherit hand velocity for throwing
	linear_velocity = hand_velocity
	angular_velocity = hand_angular_velocity
	
	is_grabbed = false
	grabbing_hand = null
	
	released.emit()


func _physics_process(_delta: float) -> void:
	# When grabbed, object is frozen and moves with hand automatically as child
	# No need to update position - it's part of the hand's rigid body now
	if is_grabbed and not is_instance_valid(grabbing_hand):
		release()
