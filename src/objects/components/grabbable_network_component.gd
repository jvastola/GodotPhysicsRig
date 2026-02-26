class_name GrabbableNetworkComponent
extends Node

signal network_grab(peer_id: String, hand_name: String, rel_pos: Vector3, rel_rot: Quaternion)
signal network_release(peer_id: String)
signal network_sync(data: Dictionary)

var network_manager: Node = null
var parent_grabbable: RigidBody3D
var save_id: String = ""
var is_network_owner: bool = true
var is_grabbed: bool = false

var network_update_timer: float = 0.0
const NETWORK_UPDATE_RATE = 0.05 # 20Hz base rate
const NETWORK_UPDATE_RATE_SLOW = 0.2 # 5Hz when not moving much
var last_network_position: Vector3 = Vector3.ZERO
var last_network_rotation: Quaternion = Quaternion.IDENTITY
const NETWORK_DELTA_THRESHOLD = 0.01 # Only send if moved > 1cm or rotated

func setup(p_grabbable: RigidBody3D, p_save_id: String) -> void:
	parent_grabbable = p_grabbable
	save_id = p_save_id
	_setup_network_sync()

func set_grabbed(grabbed: bool) -> void:
	is_grabbed = grabbed

func set_network_owner(is_owner: bool) -> void:
	is_network_owner = is_owner

func notify_grab(p_save_id: String, hand_name: String = "", rel_pos: Vector3 = Vector3.ZERO, rel_rot: Quaternion = Quaternion.IDENTITY, scale: Variant = null) -> void:
	if network_manager and is_network_owner:
		if network_manager.has_method("request_object_ownership"):
			network_manager.request_object_ownership(p_save_id, hand_name, rel_pos, rel_rot, scale)
		else:
			network_manager.grab_object(p_save_id, hand_name, rel_pos, rel_rot)

func notify_release(p_save_id: String, position: Vector3, rotation: Quaternion, lin_vel: Vector3 = Vector3.ZERO, ang_vel: Vector3 = Vector3.ZERO, release_mode: String = "RELEASED_DYNAMIC", scale: Variant = null) -> void:
	if network_manager and is_network_owner:
		network_manager.release_object(p_save_id, position, rotation, lin_vel, ang_vel, "placed_room", release_mode, scale)

func notify_update(p_save_id: String, position: Vector3, rotation: Quaternion, scale: Variant = null) -> void:
	if network_manager and is_network_owner:
		network_manager.update_grabbed_object(p_save_id, position, rotation, scale)

func notify_update_with_offsets(p_save_id: String, position: Vector3, rotation: Quaternion, rel_pos: Vector3, rel_rot: Quaternion, scale: Variant = null) -> void:
	if network_manager and is_network_owner:
		network_manager.update_grabbed_object(p_save_id, position, rotation, scale, rel_pos, rel_rot)

func process_network_sync(delta: float) -> void:
	# Update network position if we own this object (with delta compression)
	if not is_network_owner or not network_manager:
		return
		
	# Skip if not grabbed - handled by automatic world sync
	if not is_grabbed:
		return
		
	network_update_timer += delta
	
	# Current transform
	var current_pos = parent_grabbable.global_position
	var current_rot = parent_grabbable.global_transform.basis.get_rotation_quaternion()
	
	# Check if we moved enough to warrant an update
	var moved = current_pos.distance_to(last_network_position) > NETWORK_DELTA_THRESHOLD
	var rotated = last_network_rotation.angle_to(current_rot) > 0.01
	
	# Update rate logic
	var current_rate = NETWORK_UPDATE_RATE if (moved or rotated) else NETWORK_UPDATE_RATE_SLOW
	
	if network_update_timer >= current_rate:
		network_update_timer = 0.0
		
		# For desktop grab, we also check if the RELATIVE offset changed (distance/rotation)
		var current_scale = parent_grabbable.scale
		if parent_grabbable.get("is_desktop_grabbed"):
			var rel_pos = parent_grabbable.get("remote_grab_offset_pos")
			var rel_rot = parent_grabbable.get("remote_grab_offset_rot")
			notify_update_with_offsets(save_id, current_pos, current_rot, rel_pos, rel_rot, current_scale)
		else:
			notify_update(save_id, current_pos, current_rot, current_scale)
			
		last_network_position = current_pos
		last_network_rotation = current_rot

func _setup_network_sync() -> void:
	"""Connect to network manager for multiplayer sync"""
	network_manager = get_node_or_null("/root/NetworkManager")
	
	if not network_manager:
		return
	
	# Connect to network events
	network_manager.grabbable_grabbed.connect(_on_network_grab)
	network_manager.grabbable_released.connect(_on_network_release)
	network_manager.grabbable_sync_update.connect(_on_network_sync)
	
	print("GrabbableNetworkComponent: ", save_id, " network sync initialized")

func _on_network_grab(object_id: String, peer_id: Variant, hand_name: String = "", rel_pos: Vector3 = Vector3.ZERO, rel_rot: Quaternion = Quaternion.IDENTITY) -> void:
	"""Handle another player grabbing this object"""
	if object_id != save_id:
		return
	
	# Don't process our own grabs
	var is_local := false
	if network_manager:
		if network_manager.use_nakama:
			is_local = (str(peer_id) == network_manager.get_nakama_user_id())
		else:
			is_local = (str(peer_id) == str(network_manager.get_multiplayer_id()))
			
	if is_local:
		return
	
	print("GrabbableNetworkComponent: ", save_id, " grabbed by remote player ", peer_id)
	is_network_owner = false
	
	network_grab.emit(str(peer_id), hand_name, rel_pos, rel_rot)

func _on_network_release(object_id: String, peer_id: Variant) -> void:
	"""Handle another player releasing this object"""
	if object_id != save_id:
		return
	
	# Don't process our own releases
	var is_local := false
	if network_manager:
		if network_manager.use_nakama:
			is_local = (str(peer_id) == network_manager.get_nakama_user_id())
		else:
			is_local = (str(peer_id) == str(network_manager.get_multiplayer_id()))
			
	if is_local:
		return
	
	print("GrabbableNetworkComponent: ", save_id, " released by remote player ", peer_id)
	
	network_release.emit(str(peer_id))

func _on_network_sync(object_id: String, data: Dictionary) -> void:
	"""Receive position update for this object from network"""
	if object_id != save_id:
		return
	
	# Only update if we don't own it
	if is_network_owner or is_grabbed:
		return
	
	network_sync.emit(data)

func _parse_vector3(data: Dictionary) -> Vector3:
	return Vector3(data.get("x", 0), data.get("y", 0), data.get("z", 0))

func _parse_quaternion(data: Dictionary) -> Quaternion:
	return Quaternion(data.get("x", 0), data.get("y", 0), data.get("z", 0), data.get("w", 1))
