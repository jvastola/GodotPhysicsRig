# Grabbable Object
# Can be picked up by physics hands in VR
extends RigidBody3D
class_name Grabbable

enum GrabMode {
	FREE_GRAB,      # Object maintains its orientation relative to hand
	ANCHOR_GRAB     # Object snaps to a specific anchor point/rotation
}
const NETWORK_STATE_HELD := "HELD"
const NETWORK_STATE_RELEASED_STATIC := "RELEASED_STATIC"
const NETWORK_STATE_RELEASED_DYNAMIC := "RELEASED_DYNAMIC"

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

# Desktop grab state (separate from VR physics hand grab)
var is_desktop_grabbed := false
var desktop_grabber: Node = null

# Store collision data during grab
var grabbed_collision_shapes: Array = []
var grabbed_mesh_instances: Array = []

# Collision layer/mask management for proper physics integration
var original_collision_layer: int = 0
var original_collision_mask: int = 0

# Components
var network_component: GrabbableNetworkComponent

# Remote grab state (for smooth interpolation to remote player hands)
var remote_grab_hand: Node3D = null
var remote_grab_offset_pos: Vector3 = Vector3.ZERO
var remote_grab_offset_rot: Quaternion = Quaternion.IDENTITY
var _pending_remote_peer_id: String = ""
var _pending_remote_hand_name: String = ""
var _network_state: String = NETWORK_STATE_RELEASED_STATIC
var _network_state_version: int = 0

signal grabbed(hand: RigidBody3D)
signal released()


func _ready() -> void:
	# Enable contact monitoring for grab detection
	contact_monitor = true
	max_contacts_reported = 10
	
	# Store original collision settings for restoration on release
	original_collision_layer = collision_layer
	original_collision_mask = collision_mask
	
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
	
	# Setup network component
	_setup_components()
	
	# Setup interaction component for new interaction system
	_setup_interactable_component()
	
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


func _exit_tree() -> void:
	# Force cleanup if still grabbed when being removed from tree
	# This prevents orphaned collision shapes on the physics hand during scene transitions
	# For desktop grab, we ignore this as it often happens during reparenting to camera
	if is_grabbed and not is_desktop_grabbed:
		print("Grabbable: ", save_id, " exiting tree while grabbed - forcing cleanup")
		_force_cleanup_grab_state()


func _force_cleanup_grab_state() -> void:
	"""Force cleanup of grab state and all collision shapes attached to hand.
	Uses name-based matching to find shapes even if references are stale."""
	print("Grabbable: _force_cleanup_grab_state for ", save_id)
	
	if is_instance_valid(grabbing_hand):
		# Find and remove all shapes/meshes matching our naming pattern
		# This is more robust than relying on array references which may be stale
		var children_to_remove: Array = []
		for child in grabbing_hand.get_children():
			if child.name.begins_with(name + "_grabbed_"):
				children_to_remove.append(child)
		
		for child in children_to_remove:
			print("Grabbable: Removing orphaned shape: ", child.name)
			grabbing_hand.remove_child(child)
			child.queue_free()
		
		# Clear hand's held_object reference
		if grabbing_hand.has_method("set"):
			if grabbing_hand.get("held_object") == self:
				grabbing_hand.set("held_object", null)
	
	# Also clean up any shapes in our arrays
	for shape in grabbed_collision_shapes:
		if is_instance_valid(shape):
			var parent = shape.get_parent()
			if parent:
				parent.remove_child(shape)
			shape.queue_free()
	
	for mesh in grabbed_mesh_instances:
		if is_instance_valid(mesh):
			var parent = mesh.get_parent()
			if parent:
				parent.remove_child(mesh)
			mesh.queue_free()
	
	grabbed_collision_shapes.clear()
	grabbed_mesh_instances.clear()
	
	# Reset grab state
	is_grabbed = false
	grabbing_hand = null
	is_desktop_grabbed = false
	desktop_grabber = null
	
	# Update save state to reflect release
	_save_grab_state(null)


func _setup_components() -> void:
	network_component = GrabbableNetworkComponent.new()
	network_component.name = "GrabbableNetworkComponent"
	add_child(network_component)
	network_component.setup(self, save_id)
	
	network_component.network_grab.connect(_on_network_grab)
	network_component.network_release.connect(_on_network_release)
	network_component.network_sync.connect(_on_network_sync)


func _setup_interactable_component() -> void:
	"""Setup BaseInteractable component for new interaction system"""
	var interactable = BaseInteractable.new()
	interactable.name = "InteractableComponent"
	add_child(interactable)
	
	# Configure interactable
	interactable.interaction_layers = 1 << 5  # Layer 6
	interactable.select_mode = BaseInteractable.SelectMode.SINGLE
	interactable.highlight_on_hover = true
	
	# Connect to interaction signals
	interactable.selected.connect(_on_interactable_selected)
	interactable.deselected.connect(_on_interactable_deselected)


func _on_interactable_selected(interactor: BaseInteractor) -> void:
	"""Called when an interactor selects this grabbable"""
	# Try to grab - need to find the hand from the interactor
	var hand = _find_hand_from_interactor(interactor)
	if hand:
		try_grab(hand)


func _on_interactable_deselected(_interactor: BaseInteractor) -> void:
	"""Called when an interactor deselects this grabbable"""
	# Release if we're grabbed, but NOT if we're in desktop grab mode
	# DesktopInteractionComponent reparents objects to the camera, which can trigger
	# deselection signals that we want to ignore while held.
	if is_grabbed and not is_desktop_grabbed:
		release()


func _find_hand_from_interactor(interactor: BaseInteractor) -> RigidBody3D:
	"""Find the physics hand associated with an interactor"""
	# Walk up the tree to find a RigidBody3D in the physics_hand group
	var node = interactor as Node
	while node:
		if node is RigidBody3D and node.is_in_group("physics_hand"):
			return node as RigidBody3D
		node = node.get_parent()
	return null


func try_grab(hand: RigidBody3D) -> bool:
	"""Attempt to grab this object with a hand"""
	if is_grabbed:
		return false
	
	# Check if another player owns this object
	if network_component and network_component.network_manager and network_component.network_manager.is_object_grabbed_by_other(save_id):
		print("Grabbable: ", save_id, " is grabbed by another player")
		return false
	
	is_grabbed = true
	grabbing_hand = hand
	original_parent = get_parent()
	
	if network_component:
		network_component.set_network_owner(true)
		network_component.set_grabbed(true)
	
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
	
	_create_hand_collision_shapes(hand)
	
	# Notify hand to integrate collision shapes (if hand supports it)
	if hand.has_method("integrate_grabbed_collision"):
		hand.integrate_grabbed_collision(grabbed_collision_shapes)
	
	
	# Hide original object visuals but keep the parent and other nodes (like SubViewport) active
	_set_original_visuals_visible(false)
	# Disable collision on the original
	collision_layer = 0
	collision_mask = 0
	# Freeze it in place
	freeze = true
	
	# Notify network
	if network_component:
		network_component.notify_grab(save_id)
	
	grabbed.emit(hand)
	print("Grabbable: Object grabbed by ", hand.name)
	
	# Save grab state
	_save_grab_state(hand)
	
	return true


func release() -> void:
	"""Release the object from the hand"""
	if not is_grabbed:
		return
	
	print("Grabbable: Object released - ", name)
	
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
	var hand_ref = grabbing_hand  # Store reference before clearing
	
	if is_instance_valid(hand_ref):
		hand_velocity = hand_ref.linear_velocity
		hand_angular_velocity = hand_ref.angular_velocity * 0.5
		
		# ROBUST CLEANUP: Use name-based matching to find ALL shapes/meshes
		# This works even if grabbed_collision_shapes array has stale references
		var children_to_remove: Array = []
		for child in hand_ref.get_children():
			if child.name.begins_with(name + "_grabbed_"):
				children_to_remove.append(child)
		
		for child in children_to_remove:
			print("Grabbable: Releasing shape: ", child.name)
			hand_ref.remove_child(child)
			child.queue_free()
		
		# Also clean up any shapes still in the arrays (belt and suspenders)
		for collision_shape in grabbed_collision_shapes:
			if is_instance_valid(collision_shape) and collision_shape.get_parent() == hand_ref:
				hand_ref.remove_child(collision_shape)
				collision_shape.queue_free()
		
		for mesh_instance in grabbed_mesh_instances:
			if is_instance_valid(mesh_instance) and mesh_instance.get_parent() == hand_ref:
				hand_ref.remove_child(mesh_instance)
				mesh_instance.queue_free()
		
		# Clear hand's held_object reference
		if hand_ref.has_method("get"):
			if hand_ref.get("held_object") == self:
				hand_ref.set("held_object", null)
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
	_set_original_visuals_visible(true)
	var release_mode: String = NETWORK_STATE_RELEASED_DYNAMIC
	if hand_velocity.length() <= 0.05 and hand_angular_velocity.length() <= 0.05:
		release_mode = NETWORK_STATE_RELEASED_STATIC
	_apply_network_state_mode(release_mode, {
		"linear_velocity": hand_velocity,
		"angular_velocity": hand_angular_velocity
	})
	# Restore original collision settings
	collision_layer = original_collision_layer
	collision_mask = original_collision_mask
	
	# Set global transform to where the grabbed shape was
	global_transform = release_global_transform
	
	# Notify network with final authoritative release transform + throw velocity
	if network_component:
		network_component.notify_release(
			save_id,
			release_global_transform.origin,
			release_global_transform.basis.get_rotation_quaternion(),
			hand_velocity,
			hand_angular_velocity,
			release_mode
		)
		network_component.set_network_owner(false)
		network_component.set_grabbed(false)
	
	is_grabbed = false
	grabbing_hand = null
	is_desktop_grabbed = false
	desktop_grabber = null
	
	released.emit()
	
	# Save release state
	_save_grab_state(null)
	
	print("Grabbable: Release complete for ", name)


func _physics_process(_delta: float) -> void:
	if not _pending_remote_peer_id.is_empty() and not is_instance_valid(remote_grab_hand):
		_attach_to_remote_player(_pending_remote_peer_id, _pending_remote_hand_name, remote_grab_offset_pos, remote_grab_offset_rot)
		if is_instance_valid(remote_grab_hand):
			_pending_remote_peer_id = ""
			_pending_remote_hand_name = ""

	# Keep object smoothed to remote player's hand if grabbed remotely
	if is_instance_valid(remote_grab_hand):
		# Interpolate global transform to match remote hand with grabbing offset
		var target_transform = remote_grab_hand.global_transform * Transform3D(Basis(remote_grab_offset_rot), remote_grab_offset_pos)
		global_transform = global_transform.interpolate_with(target_transform, 15.0 * _delta)
		return
		
	# When grabbed, object is frozen and moves with hand automatically as child
	# No need to update position - it's part of the hand's rigid body now
	if is_grabbed:
		# Update network position if we own this object (with delta compression)
		if network_component:
			network_component.process_network_sync(_delta)
		
		# For desktop grab, skip VR-specific validation and positioning
		if is_desktop_grabbed:
			# Update relative offsets for network sync (DesktopInteractionComponent modifies position/rotation)
			remote_grab_offset_pos = position
			remote_grab_offset_rot = quaternion
			return
			
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
			_set_original_visuals_visible(true)
			freeze = false
			collision_layer = original_collision_layer
			collision_mask = original_collision_mask
			if is_instance_valid(grabbing_hand) and grabbing_hand.has_method("set"):
				grabbing_hand.set("held_object", null)
			grabbing_hand = null
			_save_grab_state(null)
			return
		
		# Validate first collision shape still exists and is a child of hand
		if not is_instance_valid(grabbed_collision_shapes[0]) or grabbed_collision_shapes[0].get_parent() != grabbing_hand:
			is_grabbed = false
			_set_original_visuals_visible(true)
			freeze = false
			collision_layer = original_collision_layer
			collision_mask = original_collision_mask
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


func _create_hand_collision_shapes(hand: RigidBody3D) -> void:
	"""Create collision shapes and meshes as children of the hand with proper physics integration"""
	for child in get_children():
		if child is CollisionShape3D and child.shape:
			# Create new collision shape as direct child of hand
			var new_collision = CollisionShape3D.new()
			new_collision.shape = child.shape
			
			# Transform is relative to this object, need to convert to hand space
			new_collision.transform = Transform3D(Basis(grab_rotation_offset), grab_offset) * child.transform
			new_collision.name = name + "_grabbed_collision_" + str(grabbed_collision_shapes.size())
			
			# Add to hand first, then configure (required for set_collision_layer_value to work)
			hand.add_child(new_collision)
			grabbed_collision_shapes.append(new_collision)
			
			# The collision shape inherits the RigidBody3D's layer/mask by being a child
			# No explicit layer/mask setting needed - it uses the hand's collision settings
			
		elif child is MeshInstance3D and child.mesh:
			# Create new mesh instance as visual
			var new_mesh = MeshInstance3D.new()
			new_mesh.mesh = child.mesh
			new_mesh.transform = Transform3D(Basis(grab_rotation_offset), grab_offset) * child.transform
			new_mesh.name = name + "_grabbed_mesh_" + str(grabbed_mesh_instances.size())
			
			# COPY MATERIAL OVERRIDES
			if child.material_override:
				new_mesh.material_override = child.material_override
			for i in child.get_surface_override_material_count():
				var mat = child.get_surface_override_material(i)
				if mat:
					new_mesh.set_surface_override_material(i, mat)
			
			hand.add_child(new_mesh)
			grabbed_mesh_instances.append(new_mesh)


func _set_original_visuals_visible(p_visible: bool) -> void:
	"""Selectively hide meshes/labels of the original object without hiding the whole node tree.
	This ensures SubViewport children continue to render."""
	for child in get_children():
		if child is VisualInstance3D:
			child.visible = p_visible


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


func _on_network_grab(peer_id: String, hand_name: String, rel_pos: Vector3, rel_rot: Quaternion) -> void:
	"""Handle another player grabbing this object"""
	# Make object semi-transparent to show it's grabbed by someone else
	_set_remote_grabbed_visual(true)
	_apply_network_state_mode(NETWORK_STATE_HELD)
	
	# Try to find the remote player's hand to attach to visually
	_attach_to_remote_player(peer_id, hand_name, rel_pos, rel_rot)
	if not is_instance_valid(remote_grab_hand):
		_pending_remote_peer_id = peer_id
		_pending_remote_hand_name = hand_name


func _on_network_release(_peer_id: String) -> void:
	"""Handle another player releasing this object"""
	_set_remote_grabbed_visual(false)
	remote_grab_hand = null
	_pending_remote_peer_id = ""
	_pending_remote_hand_name = ""


func _attach_to_remote_player(peer_id: String, hand_name: String, rel_pos: Vector3, rel_rot: Quaternion) -> void:
	# Clear existing
	remote_grab_hand = null
	
	var target_player = null
	# Find the NetworkPlayer instance matching this peer_id
	var candidates := get_tree().get_nodes_in_group("network_players")
	for candidate in candidates:
		if not (candidate is Node):
			continue
		if candidate.has_method("get_peer_id"):
			if str(candidate.call("get_peer_id")) == str(peer_id):
				target_player = candidate
				break

	if target_player:
		# Found the player. Use the indicated hand (or head for desktop)
		var hand_node = null
		if "left" in hand_name.to_lower() and target_player.get("left_hand_visual"):
			hand_node = target_player.left_hand_visual
		elif "right" in hand_name.to_lower() and target_player.get("right_hand_visual"):
			hand_node = target_player.right_hand_visual
		elif "desktop" in hand_name.to_lower() and target_player.get("head_visual"):
			hand_node = target_player.head_visual
		else:
			# Fallback if specific hand wasn't found
			hand_node = target_player.get("right_hand_visual")
			if not hand_node: hand_node = target_player.get("head_visual")
		
		if hand_node:
			remote_grab_hand = hand_node
			remote_grab_offset_pos = rel_pos
			remote_grab_offset_rot = rel_rot
			print("Grabbable: Visually attached to remote player ", peer_id, " hand: ", hand_name)


func _on_network_sync(data: Dictionary) -> void:
	"""Receive position update for this object from network"""
	if data.has("state_version"):
		_network_state_version = int(data["state_version"])
	if data.has("state"):
		_apply_network_state_mode(String(data["state"]), data)
	elif data.has("release_mode"):
		_apply_network_state_mode(String(data["release_mode"]), data)
	elif data.has("is_held"):
		if bool(data["is_held"]):
			_apply_network_state_mode(NETWORK_STATE_HELD, data)
		else:
			_apply_network_state_mode(NETWORK_STATE_RELEASED_DYNAMIC, data)
	
	# Update relative offsets if provided (e.g. desktop distance/rotation changes)
	if data.has("rel_pos"):
		remote_grab_offset_pos = data["rel_pos"]
	if data.has("rel_rot"):
		remote_grab_offset_rot = data["rel_rot"]
		
	# Ignore direct position/rotation syncs if we're actively attached to a moving hand
	if is_instance_valid(remote_grab_hand):
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


func _apply_network_state_mode(mode: String, data: Dictionary = {}) -> void:
	_network_state = mode
	if data.has("state_version"):
		_network_state_version = int(data["state_version"])

	match mode:
		NETWORK_STATE_HELD:
			freeze = true
			gravity_scale = 0.0
			collision_layer = 0
			collision_mask = 0
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
		NETWORK_STATE_RELEASED_STATIC:
			_set_remote_grabbed_visual(false)
			remote_grab_hand = null
			_pending_remote_peer_id = ""
			_pending_remote_hand_name = ""
			freeze = true
			gravity_scale = 0.0
			collision_layer = original_collision_layer
			collision_mask = original_collision_mask
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
		NETWORK_STATE_RELEASED_DYNAMIC:
			_set_remote_grabbed_visual(false)
			remote_grab_hand = null
			_pending_remote_peer_id = ""
			_pending_remote_hand_name = ""
			freeze = false
			gravity_scale = 1.0
			collision_layer = original_collision_layer
			collision_mask = original_collision_mask
			if data.has("linear_velocity"):
				linear_velocity = data["linear_velocity"]
			if data.has("angular_velocity"):
				angular_velocity = data["angular_velocity"]


func _set_remote_grabbed_visual(is_grabbed_visual: bool) -> void:
	"""Visual feedback when object is grabbed by remote player"""
	for child in get_children():
		if child is MeshInstance3D:
			if is_grabbed_visual:
				# Make semi-transparent
				if not child.material_override:
					var mat = StandardMaterial3D.new()
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat.albedo_color = Color(1, 1, 1, 0.5)
					child.material_override = mat
			else:
				# Restore normal appearance
				child.material_override = null


# ============================================================================
# POINTER GRAB INTERFACE (for hand_pointer grip grab mode)
# ============================================================================

func pointer_grab_set_distance(new_distance: float, pointer: Node3D) -> void:
	"""Set the distance of this object from the pointer origin.
	Called by hand_pointer during grip grab mode.
	Works independently of physics hand grab."""
	if not pointer or not is_instance_valid(pointer):
		return
	
	# Get pointer direction
	var pointer_forward: Vector3 = -pointer.global_transform.basis.z.normalized()
	var pointer_origin: Vector3 = pointer.global_transform.origin
	
	# Position object at the specified distance along pointer ray
	global_position = pointer_origin + pointer_forward * new_distance


func pointer_grab_set_scale(new_scale: float) -> void:
	"""Set the uniform scale of this object.
	Called by hand_pointer during grip grab mode."""
	# Apply uniform scale (clamped for safety)
	new_scale = clamp(new_scale, 0.1, 10.0)
	scale = Vector3.ONE * new_scale


func pointer_grab_get_distance(pointer: Node3D) -> float:
	"""Get current distance from the pointer origin."""
	if not pointer or not is_instance_valid(pointer):
		return 0.0
	return global_position.distance_to(pointer.global_transform.origin)


func pointer_grab_get_scale() -> float:
	"""Get current uniform scale."""
	return scale.x


# ============================================================================
# DESKTOP GRAB INTERFACE (for DesktopInteractionComponent keyboard pickup)
# ============================================================================

func desktop_grab(grabber: Node, slot: int = -1) -> void:
	"""Called by DesktopInteractionComponent when picked up with E/F keys.
	Emits grabbed signal so tools (shape_tool, etc.) can enable their functionality."""
	if is_grabbed or is_desktop_grabbed:
		return
	
	is_grabbed = true  # Set this so tool _physics_process doesn't early-exit
	is_desktop_grabbed = true
	desktop_grabber = grabber
	
	# Freeze physics while held
	freeze = true
	
	# Emit grabbed signal with null hand (desktop has no physics hand)
	# Tools should check for null hand and handle desktop mode appropriately
	grabbed.emit(null)
	
	# Notify network of desktop pickup
	if network_component:
		network_component.set_network_owner(true)
		network_component.set_grabbed(true)
		
		# For desktop grab, the object is placed in a slot in front of the camera (head)
		# We need to pass the target slot offset rather than current world offset,
		# because current world offset might be "on the ground" before reparenting.
		var slot_offset = Vector3.ZERO
		if slot == 0 and desktop_grabber:
			slot_offset = desktop_grabber.get("left_slot_offset")
			slot_offset.z = -desktop_grabber.get("_left_hold_distance")
		elif slot == 1 and desktop_grabber:
			slot_offset = desktop_grabber.get("right_slot_offset")
			slot_offset.z = -desktop_grabber.get("_right_hold_distance")
		elif desktop_grabber and desktop_grabber.has_method("_get_held_item"):
			# Fallback for callers that don't pass explicit slot
			if desktop_grabber.get("_left_held_item") == self:
				slot_offset = desktop_grabber.get("left_slot_offset")
				slot_offset.z = -desktop_grabber.get("_left_hold_distance")
			else:
				slot_offset = desktop_grabber.get("right_slot_offset")
				slot_offset.z = -desktop_grabber.get("_right_hold_distance")
		else:
			# Fallback default
			slot_offset = Vector3(0.4, -0.2, -0.6)
			
		# Store as our local "remote grab offset" so process_network_sync can pick it up
		remote_grab_offset_pos = slot_offset
		remote_grab_offset_rot = quaternion
		
		# Only send network grab if we successfully got ownership
		if is_grabbed:
			network_component.notify_grab(save_id, "desktop", remote_grab_offset_pos, remote_grab_offset_rot)


func desktop_release() -> void:
	"""Called by DesktopInteractionComponent when dropped.
	Emits released signal so tools can clean up."""
	if not is_desktop_grabbed:
		return
	
	# release() handles restoring physics, visibility, and resetting flags
	release()
