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

func notify_grab(p_save_id: String, hand_name: String = "", rel_pos: Vector3 = Vector3.ZERO, rel_rot: Quaternion = Quaternion.IDENTITY) -> void:
	if network_manager and is_network_owner:
		network_manager.grab_object(p_save_id, hand_name, rel_pos, rel_rot)

func notify_release(p_save_id: String, position: Vector3, rotation: Quaternion, lin_vel: Vector3 = Vector3.ZERO, ang_vel: Vector3 = Vector3.ZERO) -> void:
	if network_manager and is_network_owner:
		network_manager.release_object(p_save_id, position, rotation, lin_vel, ang_vel)

func notify_update(p_save_id: String, position: Vector3, rotation: Quaternion) -> void:
	if network_manager and is_network_owner:
		network_manager.update_grabbed_object(p_save_id, position, rotation)

func notify_update_with_offsets(p_save_id: String, position: Vector3, rotation: Quaternion, rel_pos: Vector3, rel_rot: Quaternion) -> void:
	if network_manager and is_network_owner:
		network_manager.update_grabbed_object(p_save_id, position, rotation, rel_pos, rel_rot)

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
		if parent_grabbable.get("is_desktop_grabbed"):
			var rel_pos = parent_grabbable.get("remote_grab_offset_pos")
			var rel_rot = parent_grabbable.get("remote_grab_offset_rot")
			notify_update_with_offsets(save_id, current_pos, current_rot, rel_pos, rel_rot)
		else:
			notify_update(save_id, current_pos, current_rot)
			
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

func _on_network_grab(object_id: String, peer_id: int) -> void:
	"""Handle another player grabbing this object via ENet P2P (legacy)"""
	if object_id != save_id:
		return
	
	# Don't process our own grabs
	if network_manager and peer_id == network_manager.get_multiplayer_id():
		return
	
	print("GrabbableNetworkComponent: ", save_id, " grabbed by remote player ", peer_id)
	is_network_owner = false
	
	network_grab.emit(str(peer_id), "", Vector3.ZERO, Quaternion.IDENTITY)

func _on_nakama_match_state(sender_id: String, op_code: int, data: Variant) -> void:
	"""Handle incoming Nakama match state"""
	if not NakamaManager:
		return
		
	# Filter for this object
	# Data should be a dictionary for grabbable events
	if not data is Dictionary:
		return
		
	if data.get("object_id") != save_id:
		return
	
	# Map Nakama op codes to local actions
	match op_code:
		NakamaManager.MatchOpCode.GRAB_OBJECT:
			print("GrabbableNetworkComponent: ", save_id, " grabbed by Nakama peer ", sender_id)
			is_network_owner = false
			
			var hand_name = data.get("hand_name", "")
			var rel_pos = Vector3.ZERO
			if data.has("rel_pos"):
				rel_pos = _parse_vector3(data["rel_pos"])
			var rel_rot = Quaternion.IDENTITY
			if data.has("rel_rot"):
				rel_rot = _parse_quaternion(data["rel_rot"])
			
			network_grab.emit(sender_id, hand_name, rel_pos, rel_rot)
			
		NakamaManager.MatchOpCode.RELEASE_OBJECT:
			print("GrabbableNetworkComponent: ", save_id, " released by Nakama peer ", sender_id)
			
			# Sync final position/rotation from data
			var sync_data = {} # Initialize sync_data here
			if data.has("pos"):
				sync_data["position"] = _parse_vector3(data["pos"])
			if data.has("rot"):
				sync_data["rotation"] = _parse_quaternion(data["rot"])
			if data.has("lin_vel"):
				sync_data["linear_velocity"] = _parse_vector3(data["lin_vel"])
			if data.has("ang_vel"):
				sync_data["angular_velocity"] = _parse_vector3(data["ang_vel"])
			
			# Only emit sync if there's actual data to sync
			if not sync_data.is_empty():
				network_sync.emit(sync_data)
			
			is_network_owner = false
			network_release.emit(sender_id)
			
		NakamaManager.MatchOpCode.OBJECT_UPDATE:
			if is_network_owner or is_grabbed:
				return
				
			var sync_data = {}
			if data.has("pos"):
				sync_data["position"] = _parse_vector3(data["pos"])
			if data.has("rot"):
				sync_data["rotation"] = _parse_quaternion(data["rot"])
			if data.has("rel_pos"):
				sync_data["rel_pos"] = _parse_vector3(data["rel_pos"])
			if data.has("rel_rot"):
				sync_data["rel_rot"] = _parse_quaternion(data["rel_rot"])
			
			network_sync.emit(sync_data)

func _on_network_release(object_id: String, peer_id: int) -> void:
	"""Handle another player releasing this object via ENet P2P (legacy)"""
	if object_id != save_id:
		return
	
	# Don't process our own releases
	if network_manager and peer_id == network_manager.get_multiplayer_id():
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
