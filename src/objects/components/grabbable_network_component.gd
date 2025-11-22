class_name GrabbableNetworkComponent
extends Node

signal network_grab(peer_id: int)
signal network_release(peer_id: int)
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

func notify_grab(p_save_id: String) -> void:
	if network_manager and is_network_owner:
		network_manager.grab_object(p_save_id)

func notify_release(p_save_id: String, position: Vector3, rotation: Quaternion) -> void:
	if network_manager and is_network_owner:
		network_manager.release_object(p_save_id, position, rotation)

func process_network_sync(delta: float) -> void:
	# Update network position if we own this object (with delta compression)
	if is_network_owner and network_manager and is_grabbed:
		network_update_timer += delta
		
		var current_pos = parent_grabbable.global_position
		var current_rot = parent_grabbable.global_transform.basis.get_rotation_quaternion()
		
		# Calculate movement delta
		var pos_delta = current_pos.distance_to(last_network_position)
		var rot_delta = current_rot.angle_to(last_network_rotation)
		
		# Use slower update rate if object is stationary
		var update_rate = NETWORK_UPDATE_RATE if (pos_delta > NETWORK_DELTA_THRESHOLD or rot_delta > 0.1) else NETWORK_UPDATE_RATE_SLOW
		
		if network_update_timer >= update_rate:
			# Only send if actually moved
			if pos_delta > NETWORK_DELTA_THRESHOLD or rot_delta > 0.01:
				network_update_timer = 0.0
				network_manager.update_grabbed_object(save_id, current_pos, current_rot)
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
	"""Handle another player grabbing this object"""
	if object_id != save_id:
		return
	
	# Don't process our own grabs
	if network_manager and peer_id == network_manager.get_multiplayer_id():
		return
	
	print("GrabbableNetworkComponent: ", save_id, " grabbed by remote player ", peer_id)
	is_network_owner = false
	
	network_grab.emit(peer_id)

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
		NakamaManager.MatchOpCode.GRABBABLE_GRAB:
			print("GrabbableNetworkComponent: ", save_id, " grabbed by Nakama peer ", sender_id)
			is_network_owner = false
			# We use a hash of the string for the int peer_id signal
			network_grab.emit(sender_id.hash())
			
		NakamaManager.MatchOpCode.GRABBABLE_RELEASE:
			print("GrabbableNetworkComponent: ", save_id, " released by Nakama peer ", sender_id)
			
			# Sync final position if provided
			if data.has("pos") and data.has("rot"):
				var sync_data = {}
				sync_data["position"] = _parse_vector3(data["pos"])
				sync_data["rotation"] = _parse_quaternion(data["rot"])
				network_sync.emit(sync_data)
				
			network_release.emit(sender_id.hash())
			
		NakamaManager.MatchOpCode.GRABBABLE_UPDATE:
			if is_network_owner or is_grabbed:
				return
				
			var sync_data = {}
			if data.has("pos"):
				sync_data["position"] = _parse_vector3(data["pos"])
			if data.has("rot"):
				sync_data["rotation"] = _parse_quaternion(data["rot"])
			
			network_sync.emit(sync_data)

func _on_network_release(object_id: String, peer_id: int) -> void:
	"""Handle another player releasing this object"""
	if object_id != save_id:
		return
	
	# Don't process our own releases
	if network_manager and peer_id == network_manager.get_multiplayer_id():
		return
	
	print("GrabbableNetworkComponent: ", save_id, " released by remote player ", peer_id)
	
	network_release.emit(peer_id)

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
