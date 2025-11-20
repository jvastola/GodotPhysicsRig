# Grabbable Object
# Can be picked up by physics hands in VR
extends RigidBody3D
class_name Grabbable

enum GrabMode {
	FREE_GRAB,      # Object maintains its orientation relative to hand
	ANCHOR_GRAB     # Object snaps to a specific anchor point/rotation
}

@export var grab_mode: GrabMode = GrabMode.ANCHOR_GRAB
@export var grab_anchor_offset: Vector3 = Vector3.ZERO
@export var grab_anchor_rotation: Vector3 = Vector3.ZERO
@export var save_id: String = ""  # Unique ID for persistence (defaults to node name)

# Optional prototype PackedScene for reinstancing this grabbable when missing
@export var prototype_scene: PackedScene

# Scene persistence tracking
var _scene_of_origin: String = ""  # Track which scene this object belongs to

# Internal state
var is_grabbed := false
var grabbing_hand: RigidBody3D = null
var original_parent: Node = null
var grab_offset: Vector3 = Vector3.ZERO
var grab_rotation_offset: Quaternion = Quaternion.IDENTITY

# Store collision data during grab
var grabbed_collision_shapes: Array = []
var grabbed_mesh_instances: Array = []

# Network sync
var network_manager: Node = null
var is_network_owner: bool = true
var network_update_timer: float = 0.0
const NETWORK_UPDATE_RATE = 0.05 # 20Hz

signal grabbed(hand: RigidBody3D)
signal released()


func _ready() -> void:
	# Enable contact monitoring for grab detection
	contact_monitor = true
	max_contacts_reported = 10
	
	# Add to grabbable group for easy detection
	add_to_group("grabbable")
	
	# Connect to collision signals for physics interaction
	body_entered.connect(_on_collision_entered)
	
	# Set save_id if not manually set
	if save_id.is_empty():
		save_id = name
	
	# Store scene of origin
	var current_scene = get_tree().current_scene
	if current_scene:
		_scene_of_origin = current_scene.scene_file_path
		print("Grabbable: ", save_id, " scene of origin: ", _scene_of_origin)
	
	# Setup network sync
	_setup_network_sync()
	
	# No need to restore - player persists across scenes so grabbed items stay grabbed
	
	# Debug: Check grab state
	if is_grabbed:
		print("Grabbable: ", save_id, " is already grabbed on _ready!")
		print("  - grabbing_hand valid: ", is_instance_valid(grabbing_hand))
		print("  - collision shapes count: ", grabbed_collision_shapes.size())
		if grabbed_collision_shapes.size() > 0:
			print("  - first shape valid: ", is_instance_valid(grabbed_collision_shapes[0]))
			if is_instance_valid(grabbed_collision_shapes[0]):
				print("  - first shape parent: ", grabbed_collision_shapes[0].get_parent())


func try_grab(hand: RigidBody3D) -> bool:
	"""Attempt to grab this object with a hand"""
	if is_grabbed:
		return false
	
	# Check if another player owns this object
	if network_manager and network_manager.is_object_grabbed_by_other(save_id):
		print("Grabbable: ", save_id, " is grabbed by another player")
		return false
	
	is_grabbed = true
	grabbing_hand = hand
	original_parent = get_parent()
	is_network_owner = true
	
	# Sync with hand's held_object
	if hand.has_method("set") and hand.get("held_object") != self:
		hand.set("held_object", self)
	
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
	
	# Notify network
	if network_manager and is_network_owner:
		network_manager.grab_object(save_id)
	
	grabbed.emit(hand)
	print("Grabbable: Object grabbed by ", hand.name)
	
	# Save grab state
	_save_grab_state(hand)
	
	return true


func release() -> void:
	"""Release the object from the hand"""
	if not is_grabbed:
		return
	
	print("Grabbable: Object released")
	
	# Notify network
	if network_manager and is_network_owner:
		network_manager.release_object(save_id, global_position, global_transform.basis.get_rotation_quaternion())
	
	is_network_owner = false
	
	# Calculate global transform from first grabbed collision shape if available
	var release_global_transform = global_transform
	if grabbed_collision_shapes.size() > 0 and is_instance_valid(grabbed_collision_shapes[0]):
		release_global_transform = grabbed_collision_shapes[0].global_transform
	elif is_instance_valid(grabbing_hand):
		# If no valid collision shape, use hand position with grab offset
		release_global_transform = grabbing_hand.global_transform * Transform3D(Basis(grab_rotation_offset), grab_offset)
	
	# Store hand velocity
	var hand_velocity = Vector3.ZERO
	var hand_angular_velocity = Vector3.ZERO
	
	if is_instance_valid(grabbing_hand):
		hand_velocity = grabbing_hand.linear_velocity
		hand_angular_velocity = grabbing_hand.angular_velocity * 0.5
		
		# Remove all grabbed collision shapes and meshes from hand
		for collision_shape in grabbed_collision_shapes:
			if is_instance_valid(collision_shape) and collision_shape.get_parent() == grabbing_hand:
				grabbing_hand.remove_child(collision_shape)
				collision_shape.queue_free()
		
		for mesh_instance in grabbed_mesh_instances:
			if is_instance_valid(mesh_instance) and mesh_instance.get_parent() == grabbing_hand:
				grabbing_hand.remove_child(mesh_instance)
				mesh_instance.queue_free()
	else:
		# Hand is invalid, just clean up what we can
		print("Grabbable: Warning - hand invalid during release, cleaning up")
		for collision_shape in grabbed_collision_shapes:
			if is_instance_valid(collision_shape):
				collision_shape.queue_free()
		for mesh_instance in grabbed_mesh_instances:
			if is_instance_valid(mesh_instance):
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
	
	# Clear hand's held_object reference
	if is_instance_valid(grabbing_hand) and grabbing_hand.has_method("get"):
		if grabbing_hand.get("held_object") == self:
			grabbing_hand.set("held_object", null)
	
	is_grabbed = false
	var _prev_hand = grabbing_hand
	grabbing_hand = null
	
	released.emit()
	
	# Save release state
	_save_grab_state(null)
	
	print("Grabbable: Release complete for ", name)


func _physics_process(_delta: float) -> void:
	# When grabbed, object is frozen and moves with hand automatically as child
	# No need to update position - it's part of the hand's rigid body now
	if is_grabbed:
		# Update network position if we own this object
		if is_network_owner and network_manager:
			network_update_timer += _delta
			if network_update_timer >= NETWORK_UPDATE_RATE:
				network_update_timer = 0.0
				network_manager.update_grabbed_object(save_id, global_position, global_transform.basis.get_rotation_quaternion())
		
		# If hand is invalid, auto-release
		if not is_instance_valid(grabbing_hand):
			print("Grabbable: Auto-releasing due to invalid hand")
			release()
			return
		
		# If grabbed collision shapes are missing (e.g., after scene transition), force release
		if grabbed_collision_shapes.is_empty():
			print("Grabbable: WARNING - No grabbed collision shapes, forcing full release")
			# Force complete cleanup
			is_grabbed = false
			visible = true
			freeze = false
			collision_layer = 1
			collision_mask = 1
			if is_instance_valid(grabbing_hand) and grabbing_hand.has_method("set"):
				grabbing_hand.set("held_object", null)
			grabbing_hand = null
			_save_grab_state(null)
			return
		
		# Validate first collision shape still exists and is a child of hand
		if not is_instance_valid(grabbed_collision_shapes[0]):
			print("Grabbable: WARNING - Grabbed collision shape invalid, forcing release")
			is_grabbed = false
			visible = true
			freeze = false
			collision_layer = 1
			collision_mask = 1
			grabbed_collision_shapes.clear()
			grabbed_mesh_instances.clear()
			if is_instance_valid(grabbing_hand) and grabbing_hand.has_method("set"):
				grabbing_hand.set("held_object", null)
			grabbing_hand = null
			_save_grab_state(null)
			return
		
		# Update invisible body position to follow first grabbed shape
		if is_instance_valid(grabbed_collision_shapes[0]):
			global_transform = grabbed_collision_shapes[0].global_transform


func _on_collision_entered(body: Node) -> void:
	"""Handle physics interaction when hand collides with object (even when not grabbed)"""
	# Skip if this object is currently grabbed
	if is_grabbed:
		return
	
	# Check if colliding body is a physics hand
	if not body.is_in_group("physics_hand"):
		return
	
	var hand = body as RigidBody3D
	if not is_instance_valid(hand):
		return
	
	# Get player rigidbody from hand if available
	var player_body = hand.get("player_rigidbody")
	if not is_instance_valid(player_body):
		return
	
	# Calculate collision force based on relative velocity
	var relative_velocity = hand.linear_velocity - linear_velocity
	var collision_normal = (global_position - hand.global_position).normalized()
	
	# Apply equal and opposite forces (Newton's third law)
	# Use physics delta time
	var delta = 1.0 / Engine.get_physics_ticks_per_second()
	var force_magnitude = relative_velocity.length() * mass * 50
	var force_on_object = collision_normal * force_magnitude
	apply_central_impulse(force_on_object * delta)

	# Object pushes player back (through hand)
	var force_on_player = -force_on_object * 0.3  # Reduced for player comfort
	player_body.apply_central_impulse(force_on_player * delta)


func _save_grab_state(hand: RigidBody3D) -> void:
	"""Save current grab state to SaveManager"""
	if not SaveManager:
		return
	
	var hand_name := ""
	if is_instance_valid(hand):
		# Determine which hand (left or right)
		if "left" in hand.name.to_lower():
			hand_name = "left"
		elif "right" in hand.name.to_lower():
			hand_name = "right"
		else:
			hand_name = hand.name
	
	# Save with scene information. Prefer an explicit prototype_scene resource
	var scene_to_save := _scene_of_origin
	if prototype_scene and prototype_scene.resource_path and prototype_scene.resource_path != "":
		scene_to_save = prototype_scene.resource_path

	# If we have a hand, compute the transform of the object relative to that hand
	var rel_pos_arr: Array = []
	var rel_rot_arr: Array = []
	if is_instance_valid(hand):
		var hand_inv = hand.global_transform.affine_inverse()
		var rel_tf: Transform3D = hand_inv * global_transform
		var rel_pos: Vector3 = rel_tf.origin
		var rel_quat: Quaternion = rel_tf.basis.get_rotation_quaternion()
		rel_pos_arr = [rel_pos.x, rel_pos.y, rel_pos.z]
		rel_rot_arr = [rel_quat.x, rel_quat.y, rel_quat.z, rel_quat.w]
		# Debug: log hand and relative transforms being saved
		print("Grabbable: Saving state for ", save_id)
		print("  - hand global_transform: ", hand.global_transform)
		print("  - object global_transform: ", global_transform)
		print("  - relative transform (pos, quat): ", rel_pos_arr, rel_rot_arr)

	SaveManager.save_grabbed_object(
		save_id,
		is_grabbed,
		hand_name,
		global_position,
		global_transform.basis.get_rotation_quaternion(),
		scene_to_save,
		rel_pos_arr,
		rel_rot_arr
	)


# ============================================================================
# Network Sync Functions
# ============================================================================

func _setup_network_sync() -> void:
	"""Connect to network manager for multiplayer sync"""
	network_manager = get_node_or_null("/root/NetworkManager")
	
	if not network_manager:
		return
	
	# Connect to network events
	network_manager.grabbable_grabbed.connect(_on_network_grab)
	network_manager.grabbable_released.connect(_on_network_release)
	network_manager.grabbable_sync_update.connect(_on_network_sync)
	
	print("Grabbable: ", save_id, " network sync initialized")


func _on_network_grab(object_id: String, peer_id: int) -> void:
	"""Handle another player grabbing this object"""
	if object_id != save_id:
		return
	
	# Don't process our own grabs
	if network_manager and peer_id == network_manager.get_multiplayer_id():
		return
	
	print("Grabbable: ", save_id, " grabbed by remote player ", peer_id)
	is_network_owner = false
	
	# Make object semi-transparent to show it's grabbed by someone else
	_set_remote_grabbed_visual(true)


func _on_network_release(object_id: String, peer_id: int) -> void:
	"""Handle another player releasing this object"""
	if object_id != save_id:
		return
	
	# Don't process our own releases
	if network_manager and peer_id == network_manager.get_multiplayer_id():
		return
	
	print("Grabbable: ", save_id, " released by remote player ", peer_id)
	_set_remote_grabbed_visual(false)


func _on_network_sync(object_id: String, data: Dictionary) -> void:
	"""Receive position update for this object from network"""
	if object_id != save_id:
		return
	
	# Only update if we don't own it
	if is_network_owner or is_grabbed:
		return
	
	# Smoothly interpolate to network position
	if data.has("position"):
		var target_pos = data["position"]
		global_position = global_position.lerp(target_pos, 0.3)
	
	if data.has("rotation"):
		var target_rot = data["rotation"]
		var current_quat = global_transform.basis.get_rotation_quaternion()
		var interpolated = current_quat.slerp(target_rot, 0.3)
		global_transform.basis = Basis(interpolated)


func _set_remote_grabbed_visual(grabbed: bool) -> void:
	"""Visual feedback when object is grabbed by remote player"""
	for child in get_children():
		if child is MeshInstance3D:
			if grabbed:
				# Make semi-transparent
				if not child.material_override:
					var mat = StandardMaterial3D.new()
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat.albedo_color = Color(1, 1, 1, 0.5)
					child.material_override = mat
			else:
				# Restore normal appearance
				child.material_override = null
