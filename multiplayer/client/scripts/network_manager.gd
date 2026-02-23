extends Node
## NetworkManager - Handles all network connections and player management via Nakama
## Singleton autoload that manages Nakama match state, player spawning, and network events

signal player_connected(peer_id: String)
signal player_disconnected(peer_id: String)
signal connection_failed()
signal connection_succeeded()
signal server_disconnected()
signal send_local_avatar()
signal ownership_request_received(object_id: String, requester_id: String)
signal ownership_changed(object_id: String, new_owner_id: String, previous_owner_id: String)
signal snapshot_reconstructed(snapshot_id: String, object_count: int)
signal network_object_despawn_requested(object_id: String)
signal object_property_updated(object_id: String, property_name: String, value: Variant, sender_peer_id: String)
signal player_name_updated(peer_id: String, display_name: String)

# Nakama is now the exclusive networking backend
var use_nakama: bool = true
var use_livekit_data_replication: bool = false

# Room data
var players: Dictionary = {} # user_id String -> player_info Dictionary
var local_player: Node3D = null
var _presence_join_order: Dictionary = {} # user_id -> join order
var _join_order_counter: int = 0
var _host_peer_id: String = ""
var peer_display_names: Dictionary = {} # peer_id -> display name

# Player info structure
var local_player_info: Dictionary = {
	"name": "Player",
	"head_position": Vector3.ZERO,
	"head_rotation": Vector3.ZERO,
	"left_hand_position": Vector3.ZERO,
	"left_hand_rotation": Vector3.ZERO,
	"right_hand_position": Vector3.ZERO,
	"right_hand_rotation": Vector3.ZERO,
	"player_scale": Vector3.ONE,
	"avatar_texture_data": PackedByteArray()
}

# Grabbable sync
var grabbed_objects: Dictionary = {} # object_id -> {owner_peer_id, position, rotation, is_grabbed}
var room_object_registry: Dictionary = {} # object_id -> state map
signal grabbable_grabbed(object_id: String, peer_id: String, hand_name: String, rel_pos: Vector3, rel_rot: Quaternion)
signal grabbable_released(object_id: String, peer_id: String)
signal grabbable_sync_update(object_id: String, data: Dictionary)
const OBJECT_STATE_HELD := "HELD"
const OBJECT_STATE_RELEASED_STATIC := "RELEASED_STATIC"
const OBJECT_STATE_RELEASED_DYNAMIC := "RELEASED_DYNAMIC"

# Avatar signals
signal avatar_texture_received(peer_id: String)

# Voxel sync signals
signal voxel_placed_network(world_pos: Vector3, color: Color)
signal voxel_removed_network(world_pos: Vector3)

# Voice chat
var voice_enabled: bool = false # Handled by LiveKit but kept for signal logic

# Connection quality monitoring
enum ConnectionQuality {
	EXCELLENT,  # < 50ms ping
	GOOD,       # 50-100ms ping
	FAIR,       # 100-200ms ping
	POOR        # > 200ms ping
}

var network_stats: Dictionary = {
	"ping_ms": 0.0,
	"bandwidth_up": 0.0,  # KB/s
	"bandwidth_down": 0.0,  # KB/s
	"packet_loss": 0.0,  # percentage
	"connection_quality": ConnectionQuality.GOOD
}

var _ping_check_interval: float = 1.0
var _monitor_timer: Timer = null
var _metrics := {
	"connect_attempts": 0,
	"connect_successes": 0,
	"connect_failures": 0,
	"last_connect_start_msec": 0,
	"last_connect_latency_ms": 0,
	"disconnects": 0,
	"reconnect_attempts": 0,
	"send_failures": 0,
	"last_send_failure": ""
}

signal connection_quality_changed(quality: ConnectionQuality)
signal network_stats_updated(stats: Dictionary)
signal metrics_updated(metrics: Dictionary)

# Push-to-talk
enum VoiceMode {
	ALWAYS_ON,
	PUSH_TO_TALK,
	VOICE_ACTIVATED
}

var voice_mode: VoiceMode = VoiceMode.PUSH_TO_TALK
var push_to_talk_key: Key = KEY_SPACE
var is_push_to_talk_pressed: bool = false

# Reconnection
var connection_timeout: float = 10.0
var _last_server_response_time: float = 0.0
var _snapshot_buffers: Dictionary = {} # snapshot_id -> {total_chunks:int, chunks:Dictionary, from_peer_id:String}
const SNAPSHOT_CHUNK_SIZE: int = 20
const PLAYER_TRANSFORM_RATE_HZ: float = 20.0
const HELD_OBJECT_TRANSFORM_RATE_HZ: float = 20.0
const PLAYER_TRANSFORM_INTERVAL_MS: int = int(1000.0 / PLAYER_TRANSFORM_RATE_HZ)
const HELD_OBJECT_TRANSFORM_INTERVAL_MS: int = int(1000.0 / HELD_OBJECT_TRANSFORM_RATE_HZ)
const LIVEKIT_TOPIC_REP_OBJECT := "rep/object"
const LIVEKIT_TOPIC_REP_TRANSFORM := "rep/transform"
const LIVEKIT_TOPIC_REP_PROPERTY := "rep/property"
var _livekit_wrapper: Node = null
var _last_object_rep_send_msec: Dictionary = {} # object_id -> int msec timestamp
var _replication_manifests: Dictionary = {
	"default": {
		"high_rate_unreliable": ["transform"],
		"reliable_on_change": ["material", "collision_enabled", "mesh_variant", "visible", "persist_mode"],
		"snapshot_only": []
	}
}


func _ready() -> void:
	if NakamaManager and not NakamaManager.display_name.is_empty():
		local_player_info.name = NakamaManager.display_name
	use_livekit_data_replication = ProjectSettings.get_setting("network/use_livekit_data_replication", false)
	# Initialize network stats monitoring
	_last_server_response_time = Time.get_ticks_msec() / 1000.0
	
	# Setup Nakama signals (deferred to ensure NakamaManager autoload is ready)
	call_deferred("_setup_nakama_integration")
	call_deferred("_setup_livekit_integration")
	
	# Timer-based connection monitoring
	_monitor_timer = Timer.new()
	_monitor_timer.wait_time = _ping_check_interval
	_monitor_timer.one_shot = false
	_monitor_timer.autostart = false
	add_child(_monitor_timer)
	_monitor_timer.timeout.connect(_on_monitor_timeout)
	set_process(false)
	_update_monitoring_state()


func _setup_nakama_integration() -> void:
	"""Connect to NakamaManager signals"""
	if NakamaManager:
		if not NakamaManager.match_joined.is_connected(_on_nakama_match_joined):
			NakamaManager.match_joined.connect(_on_nakama_match_joined)
		if not NakamaManager.match_left.is_connected(_on_nakama_match_left):
			NakamaManager.match_left.connect(_on_nakama_match_left)
		if not NakamaManager.match_presence.is_connected(_on_nakama_match_presence):
			NakamaManager.match_presence.connect(_on_nakama_match_presence)
		if not NakamaManager.match_state_received.is_connected(_on_nakama_match_state_received):
			NakamaManager.match_state_received.connect(_on_nakama_match_state_received)
			print("NetworkManager: Nakama integration initialized")


func _setup_livekit_integration() -> void:
	_livekit_wrapper = get_node_or_null("/root/LiveKitWrapper")
	if not _livekit_wrapper:
		return
	if _livekit_wrapper.has_signal("data_packet_received"):
		if not _livekit_wrapper.data_packet_received.is_connected(_on_livekit_data_packet_received):
			_livekit_wrapper.data_packet_received.connect(_on_livekit_data_packet_received)
	elif _livekit_wrapper.has_signal("data_received"):
		if not _livekit_wrapper.data_received.is_connected(_on_livekit_data_received_legacy):
			_livekit_wrapper.data_received.connect(_on_livekit_data_received_legacy)


## Disconnect from network
func disconnect_from_network() -> void:
	if NakamaManager:
		NakamaManager.leave_match()
	players.clear()
	print("Disconnected from network")


## Check if we are the "authority" (Nakama matches are usually hostless relay, 
## but we can treat the player with the lowest ID as authority for some tasks)
func is_server() -> bool:
	if not use_nakama:
		return true
	return _get_host_peer_id() == get_nakama_user_id()


## Get our multiplayer ID (Always string user ID for Nakama)
func get_multiplayer_id() -> String:
	return get_nakama_user_id()


## Get our Nakama User ID
func get_nakama_user_id() -> String:
	if NakamaManager:
		return NakamaManager.local_user_id
	return ""


func get_stable_network_id() -> String:
	return get_nakama_user_id()


func get_host_peer_id() -> String:
	return _get_host_peer_id()


func get_peer_display_name(peer_id: String) -> String:
	if peer_display_names.has(peer_id):
		return String(peer_display_names[peer_id])
	if players.has(peer_id):
		var p = players[peer_id]
		if p is Dictionary and p.has("name") and not String(p.name).is_empty():
			return String(p.name)
	return ""


func set_peer_display_name(peer_id: String, display_name: String, broadcast: bool = false) -> void:
	_set_peer_display_name(peer_id, display_name, broadcast)


func set_local_display_name(display_name: String, broadcast: bool = true) -> void:
	var my_id := get_nakama_user_id()
	if my_id.is_empty():
		return
	local_player_info.name = display_name
	_set_peer_display_name(my_id, display_name, broadcast)


func _resolve_local_display_name() -> String:
	if NakamaManager and not NakamaManager.display_name.is_empty():
		return NakamaManager.display_name
	return String(local_player_info.get("name", "Player"))


func _set_peer_display_name(peer_id: String, display_name: String, broadcast: bool) -> void:
	if peer_id.is_empty() or display_name.is_empty():
		return
	peer_display_names[peer_id] = display_name
	if players.has(peer_id):
		var p = players[peer_id].duplicate(true)
		p["name"] = display_name
		players[peer_id] = p
	elif peer_id == get_nakama_user_id():
		local_player_info.name = display_name
	player_name_updated.emit(peer_id, display_name)
	if broadcast and NakamaManager:
		NakamaManager.send_match_state(NakamaManager.MatchOpCode.PLAYER_NAME_UPDATE, {
			"peer_id": peer_id,
			"display_name": display_name
		})


## Register the local player node
func _register_local_player() -> void:
	var my_id = get_nakama_user_id()
	if not my_id.is_empty():
		var local_name := _resolve_local_display_name()
		local_player_info.name = local_name
		players[my_id] = local_player_info.duplicate(true)
		_set_peer_display_name(my_id, local_name, false)
		_assign_join_order_if_missing(my_id)
		print("Local player registered with ID: ", my_id)


func _make_default_remote_player_info(peer_id: String) -> Dictionary:
	var info := {
		"name": "Player",
		"head_position": Vector3.ZERO,
		"head_rotation": Vector3.ZERO,
		"left_hand_position": Vector3.ZERO,
		"left_hand_rotation": Vector3.ZERO,
		"right_hand_position": Vector3.ZERO,
		"right_hand_rotation": Vector3.ZERO,
		"player_scale": Vector3.ONE,
		"avatar_texture_data": PackedByteArray()
	}
	var known_name := get_peer_display_name(peer_id)
	if not known_name.is_empty():
		info["name"] = known_name
	return info


func _assign_join_order_if_missing(peer_id: String) -> void:
	if peer_id.is_empty() or _presence_join_order.has(peer_id):
		return
	_presence_join_order[peer_id] = _join_order_counter
	_join_order_counter += 1


func _get_host_peer_id() -> String:
	var my_id := get_nakama_user_id()
	if not _host_peer_id.is_empty():
		if _presence_join_order.has(_host_peer_id) or _host_peer_id == my_id or players.has(_host_peer_id):
			return _host_peer_id
	var host_id := ""
	var host_order := 1 << 30
	for peer_id in _presence_join_order.keys():
		var order = int(_presence_join_order.get(peer_id, host_order))
		if order < host_order:
			host_order = order
			host_id = peer_id
	if host_id.is_empty():
		var candidates: Array[String] = []
		if not my_id.is_empty():
			candidates.append(my_id)
		for peer_id in players.keys():
			var pid := String(peer_id)
			if pid.is_empty():
				continue
			if not candidates.has(pid):
				candidates.append(pid)
		candidates.sort()
		if candidates.size() > 0:
			host_id = candidates[0]
	if host_id.is_empty():
		return my_id
	return host_id


func _set_host_peer_id(peer_id: String) -> void:
	if peer_id.is_empty():
		return
	_host_peer_id = peer_id
	_assign_join_order_if_missing(peer_id)


## Update local player transform data (called by XRPlayer every frame)
func update_local_player_transform(head_pos: Vector3, head_rot: Vector3, 
		left_pos: Vector3, left_rot: Vector3, 
		right_pos: Vector3, right_rot: Vector3,
		scale: Vector3) -> void:
	
	local_player_info.head_position = head_pos
	local_player_info.head_rotation = head_rot
	local_player_info.left_hand_position = left_pos
	local_player_info.left_hand_rotation = left_rot
	local_player_info.right_hand_position = right_pos
	local_player_info.right_hand_rotation = right_rot
	local_player_info.player_scale = scale
	
	# Update our entry in players dictionary
	var my_id = get_nakama_user_id()
	if not my_id.is_empty():
		players[my_id] = local_player_info.duplicate(true)
		
		# SECURE COMPONENT: Rate limiting (e.g., 20Hz by default, adjustable)
		var now = Time.get_ticks_msec()
		if now - _metrics.get("last_transform_send_time", 0) < PLAYER_TRANSFORM_INTERVAL_MS:
			return
		_metrics["last_transform_send_time"] = now
		
		# SECURE COMPONENT: Binary serialization using var_to_bytes
		var transform_data = {
			"hp": head_pos,
			"hr": head_rot,
			"lp": left_pos,
			"lr": left_rot,
			"rp": right_pos,
			"rr": right_rot,
			"s": scale
		}

		if _can_use_livekit_realtime():
			var packet = {
				"packet_type": "player_transform",
				"sender_id": my_id,
				"hp": _vec3_to_dict(head_pos),
				"hr": _vec3_to_dict(head_rot),
				"lp": _vec3_to_dict(left_pos),
				"lr": _vec3_to_dict(left_rot),
				"rp": _vec3_to_dict(right_pos),
				"rr": _vec3_to_dict(right_rot),
				"s": _vec3_to_dict(scale)
			}
			_livekit_wrapper.send_json_packet(packet, LIVEKIT_TOPIC_REP_TRANSFORM, false)
			return

		var binary_data = var_to_bytes(transform_data)
		NakamaManager.send_match_state(NakamaManager.MatchOpCode.PLAYER_TRANSFORM, binary_data)


# ============================================================================
# Nakama Event Callbacks
# ============================================================================

func _on_nakama_match_joined(match_id: String) -> void:
	print("NetworkManager: Joined Nakama match: ", match_id)
	
	# Reset state
	players.clear()
	grabbed_objects.clear()
	room_object_registry.clear()
	_last_object_rep_send_msec.clear()
	_presence_join_order.clear()
	_join_order_counter = 0
	_host_peer_id = ""
	_snapshot_buffers.clear()
	peer_display_names.clear()

	# Seed known peers from match-join presences before registering ourselves.
	if NakamaManager:
		for peer_id in NakamaManager.match_peers.keys():
			if not peer_id.is_empty():
				players[peer_id] = _make_default_remote_player_info(peer_id)
				_assign_join_order_if_missing(peer_id)
	
	# Register ourselves
	_register_local_player()
	set_local_display_name(local_player_info.name, true)
	if NakamaManager and NakamaManager.match_peers.is_empty():
		_set_host_peer_id(get_nakama_user_id())
	else:
		_set_host_peer_id(_get_host_peer_id())
	
	# Notify listeners
	connection_succeeded.emit()
	
	# Trigger avatar send after a short delay
	await get_tree().create_timer(0.5).timeout
	send_local_avatar.emit()
	if not is_server():
		request_room_snapshot()
	_update_monitoring_state()

func _on_nakama_match_left() -> void:
	print("NetworkManager: Left Nakama match")
	players.clear()
	grabbed_objects.clear()
	room_object_registry.clear()
	_last_object_rep_send_msec.clear()
	_presence_join_order.clear()
	_host_peer_id = ""
	_snapshot_buffers.clear()
	peer_display_names.clear()
	server_disconnected.emit()
	_update_monitoring_state()

func _on_nakama_match_presence(joins: Array, leaves: Array) -> void:
	var my_id = get_nakama_user_id()
	
	for join in joins:
		var user_id = join.get("user_id", "")
		if user_id.is_empty() or user_id == my_id:
			continue
		
		print("NetworkManager: Nakama player joined: ", user_id)
		players[user_id] = _make_default_remote_player_info(user_id)
		_assign_join_order_if_missing(user_id)
		_set_host_peer_id(_get_host_peer_id())
		player_connected.emit(user_id)
		if is_server():
			_send_room_snapshot_to_peer(user_id)
		
	for leave in leaves:
		var user_id = leave.get("user_id", "")
		if user_id != my_id and not user_id.is_empty():
			print("NetworkManager: Nakama player left: ", user_id)
			if players.has(user_id):
				players.erase(user_id)
			if peer_display_names.has(user_id):
				peer_display_names.erase(user_id)
			if _presence_join_order.has(user_id):
				_presence_join_order.erase(user_id)
			if user_id == _host_peer_id:
				_host_peer_id = ""
				_set_host_peer_id(_get_host_peer_id())
			_handle_peer_disconnect_objects(user_id)
			player_disconnected.emit(user_id)


func _handle_nakama_player_transform(sender_id: String, data: Dictionary) -> void:
	if not players.has(sender_id):
		players[sender_id] = _make_default_remote_player_info(sender_id)
	
	var p = players[sender_id]
	if data.has("hp"): p.head_position = _dict_to_vec3(data.hp)
	if data.has("hr"): p.head_rotation = _dict_to_vec3(data.hr)
	if data.has("lp"): p.left_hand_position = _dict_to_vec3(data.lp)
	if data.has("lr"): p.left_hand_rotation = _dict_to_vec3(data.lr)
	if data.has("rp"): p.right_hand_position = _dict_to_vec3(data.rp)
	if data.has("rr"): p.right_hand_rotation = _dict_to_vec3(data.rr)
	if data.has("s"): p.player_scale = _dict_to_vec3(data.s)


func _vec3_to_dict(v: Vector3) -> Dictionary:
	return {"x": snappedf(v.x, 0.001), "y": snappedf(v.y, 0.001), "z": snappedf(v.z, 0.001)}

func _dict_to_vec3(d: Variant) -> Vector3:
	if d is Vector3:
		return d
	if d is Dictionary:
		return Vector3(d.get("x", 0), d.get("y", 0), d.get("z", 0))
	return Vector3.ZERO

func _quat_to_dict(q: Quaternion) -> Dictionary:
	return {"x": snappedf(q.x, 0.001), "y": snappedf(q.y, 0.001), "z": snappedf(q.z, 0.001), "w": snappedf(q.w, 0.001)}

func _dict_to_quat(d: Variant) -> Quaternion:
	if d is Quaternion:
		return d
	if d is Dictionary:
		return Quaternion(d.get("x", 0), d.get("y", 0), d.get("z", 0), d.get("w", 1))
	return Quaternion.IDENTITY


func _handle_nakama_avatar_data(sender_id: String, data: Dictionary) -> void:
	if data.is_empty(): return
	if not players.has(sender_id): players[sender_id] = _make_default_remote_player_info(sender_id)
	if not players[sender_id].has("avatar_textures"): players[sender_id].avatar_textures = {}
	
	for surface_name in data:
		var texture_base64 = data[surface_name]
		var texture_data = Marshalls.base64_to_raw(texture_base64)
		players[sender_id].avatar_textures[surface_name] = texture_data
	
	avatar_texture_received.emit(sender_id)


# ============================================================================
# Avatar Texture Sync
# ============================================================================

# SECURE COMPONENT: Payload validation constants (Issue #4)
const MAX_AVATAR_SIZE_BYTES = 2 * 1024 * 1024  # 2MB total
const MAX_AVATAR_DIMENSION = 512  # pixels

func set_local_avatar_textures(textures: Dictionary) -> void:
	var total_bytes = 0
	var avatar_data = {}
	
	for surface_name in textures:
		var texture: ImageTexture = textures[surface_name]
		var image = texture.get_image()
		
		# SECURE COMPONENT: Validate dimensions
		if image.get_width() > MAX_AVATAR_DIMENSION or \
		   image.get_height() > MAX_AVATAR_DIMENSION:
			push_error("NetworkManager: Avatar texture too large: ", surface_name, " (", image.get_width(), "x", image.get_height(), ")")
			continue
		
		var texture_data = image.save_png_to_buffer()
		total_bytes += texture_data.size()
		
		if total_bytes > MAX_AVATAR_SIZE_BYTES:
			push_error("NetworkManager: Total avatar size exceeds limit (2MB)")
			return
		
		avatar_data[surface_name] = Marshalls.raw_to_base64(texture_data)
	
	if NakamaManager:
		NakamaManager.send_match_state(NakamaManager.MatchOpCode.AVATAR_DATA, avatar_data)


func get_player_avatar_texture(peer_id: String) -> ImageTexture:
	if not players.has(peer_id): return null
	var texture_data = players[peer_id].get("avatar_texture_data", PackedByteArray())
	if texture_data.size() == 0: return null
	
	var image = Image.new()
	if image.load_png_from_buffer(texture_data) != OK: return null
	return ImageTexture.create_from_image(image)


# ============================================================================
# Grabbable Object Sync
# ============================================================================

func _ensure_object_registry(object_id: String) -> Dictionary:
	if not room_object_registry.has(object_id):
		room_object_registry[object_id] = {
			"object_id": object_id,
			"owner_id": _get_host_peer_id(),
			"held_by": "",
			"placed": false,
			"persist_mode": "transient_held",
			"sim_state": OBJECT_STATE_RELEASED_STATIC,
			"state_version": 0,
			"manifest_id": "",
			"seq": 0,
			"property_seq": 0,
			"properties": {},
			"scene_path": "",
			"position": _vec3_to_dict(Vector3.ZERO),
			"rotation": _quat_to_dict(Quaternion.IDENTITY),
			"spawned_by": ""
		}
	return room_object_registry[object_id]


func _update_object_registry_state(object_id: String, patch: Dictionary) -> Dictionary:
	var state = _ensure_object_registry(object_id).duplicate(true)
	for key in patch.keys():
		state[key] = patch[key]
	state["seq"] = int(state.get("seq", 0)) + 1
	room_object_registry[object_id] = state
	return state


func _get_object_state_version(object_id: String) -> int:
	return int(_ensure_object_registry(object_id).get("state_version", 0))


func _next_object_state_version(object_id: String) -> int:
	return _get_object_state_version(object_id) + 1


func _is_transform_version_valid(object_id: String, incoming_version: int) -> bool:
	if incoming_version <= 0:
		return true
	return incoming_version == _get_object_state_version(object_id)


func _is_transition_version_valid(object_id: String, incoming_version: int) -> bool:
	if incoming_version <= 0:
		return true
	return incoming_version >= _get_object_state_version(object_id)


func _trace_object_state(object_id: String, state_name: String, state_version: int, source: String) -> void:
	print("[ObjectState] ", object_id, " v", state_version, " ", state_name, " via ", source)


func request_object_ownership(object_id: String, hand_name: String = "", rel_pos: Vector3 = Vector3.ZERO, rel_rot: Quaternion = Quaternion.IDENTITY) -> void:
	var my_id := get_nakama_user_id()
	if my_id.is_empty() or object_id.is_empty():
		return

	if is_server():
		_handle_ownership_request(my_id, {
			"object_id": object_id,
			"requester_id": my_id,
			"hand_name": hand_name,
			"rel_pos": _vec3_to_dict(rel_pos),
			"rel_rot": _quat_to_dict(rel_rot)
		})
		return

	var request_data = {
		"object_id": object_id,
		"requester_id": my_id,
		"hand_name": hand_name,
		"rel_pos": _vec3_to_dict(rel_pos),
		"rel_rot": _quat_to_dict(rel_rot)
	}
	NakamaManager.send_match_state(NakamaManager.MatchOpCode.OWNERSHIP_REQUEST, request_data)


func _handle_ownership_request(sender_id: String, data: Dictionary) -> void:
	if not is_server():
		return

	var object_id: String = data.get("object_id", "")
	var requester_id: String = data.get("requester_id", sender_id)
	if object_id.is_empty() or requester_id.is_empty():
		return

	ownership_request_received.emit(object_id, requester_id)
	var state = _ensure_object_registry(object_id)
	var held_by: String = state.get("held_by", "")
	var approved := held_by.is_empty() or held_by == requester_id
	var previous_owner := String(state.get("owner_id", ""))

	if approved:
		var state_version := _next_object_state_version(object_id)
		state = _update_object_registry_state(object_id, {
			"owner_id": requester_id,
			"held_by": requester_id,
			"placed": false,
			"persist_mode": "transient_held",
			"sim_state": OBJECT_STATE_HELD,
			"state_version": state_version
		})
		_trace_object_state(object_id, OBJECT_STATE_HELD, state_version, "ownership_request")
		grabbed_objects[object_id] = {
			"owner_peer_id": requester_id,
			"is_grabbed": true,
			"hand_name": data.get("hand_name", "")
		}
		ownership_changed.emit(object_id, requester_id, previous_owner)
		# Important: server/host won't process its own OWNERSHIP_GRANTED packet due spoof guard.
		# Emit local grab transition now so host-side object components switch to remote-owned mode.
		grabbable_grabbed.emit(
			object_id,
			requester_id,
			data.get("hand_name", ""),
			_parse_vector3(data.get("rel_pos", {})),
			_parse_quaternion(data.get("rel_rot", {}))
		)
		grabbable_sync_update.emit(object_id, {
			"is_held": true,
			"state": OBJECT_STATE_HELD,
			"state_version": state_version
		})
		var grant_data = {
			"object_id": object_id,
			"requester_id": requester_id,
			"new_owner_id": requester_id,
			"previous_owner_id": previous_owner,
			"state": OBJECT_STATE_HELD,
			"state_version": state_version,
			"hand_name": data.get("hand_name", ""),
			"rel_pos": data.get("rel_pos", _vec3_to_dict(Vector3.ZERO)),
			"rel_rot": data.get("rel_rot", _quat_to_dict(Quaternion.IDENTITY)),
			"seq": state.get("seq", 0)
		}
		NakamaManager.send_match_state(NakamaManager.MatchOpCode.OWNERSHIP_GRANTED, grant_data)
		return

	var deny_data = {
		"object_id": object_id,
		"requester_id": requester_id,
		"reason": "already_held",
		"current_owner_id": state.get("owner_id", ""),
		"held_by": held_by
	}
	NakamaManager.send_match_state(NakamaManager.MatchOpCode.OWNERSHIP_DENIED, deny_data)


func _handle_ownership_granted(_sender_id: String, data: Dictionary) -> void:
	var object_id: String = data.get("object_id", "")
	if object_id.is_empty():
		return

	var incoming_version := int(data.get("state_version", 0))
	if not _is_transition_version_valid(object_id, incoming_version):
		return

	var new_owner_id: String = data.get("new_owner_id", data.get("requester_id", ""))
	var previous_owner := String(data.get("previous_owner_id", ""))
	var state_name: String = data.get("state", OBJECT_STATE_HELD)
	_update_object_registry_state(object_id, {
		"owner_id": new_owner_id,
		"held_by": new_owner_id,
		"placed": false,
		"persist_mode": "transient_held",
		"sim_state": state_name,
		"state_version": incoming_version
	})
	grabbed_objects[object_id] = {
		"owner_peer_id": new_owner_id,
		"is_grabbed": true,
		"hand_name": data.get("hand_name", "")
	}
	_trace_object_state(object_id, state_name, incoming_version, "ownership_granted")
	ownership_changed.emit(object_id, new_owner_id, previous_owner)
	grabbable_grabbed.emit(
		object_id,
		new_owner_id,
		data.get("hand_name", ""),
		_parse_vector3(data.get("rel_pos", {})),
		_parse_quaternion(data.get("rel_rot", {}))
	)
	grabbable_sync_update.emit(object_id, {
		"is_held": true,
		"state": state_name,
		"state_version": incoming_version
	})


func _handle_ownership_denied(_sender_id: String, data: Dictionary) -> void:
	var requester_id: String = data.get("requester_id", "")
	if requester_id != get_nakama_user_id():
		return
	var object_id: String = data.get("object_id", "")
	push_warning("NetworkManager: Ownership denied for %s (%s)" % [object_id, data.get("reason", "unknown")])


func _handle_ownership_released(sender_id: String, data: Dictionary) -> void:
	var object_id: String = data.get("object_id", "")
	if object_id.is_empty():
		return
	var incoming_version := int(data.get("state_version", 0))
	if not _is_transition_version_valid(object_id, incoming_version):
		return
	if _last_object_rep_send_msec.has(object_id):
		_last_object_rep_send_msec.erase(object_id)

	var persist_mode: String = data.get("persist_mode", "placed_room")
	var release_mode: String = data.get("release_mode", OBJECT_STATE_RELEASED_STATIC)
	if persist_mode == "transient_held":
		if grabbed_objects.has(object_id):
			grabbed_objects.erase(object_id)
		room_object_registry.erase(object_id)
		network_object_despawn_requested.emit(object_id)
		return

	if grabbed_objects.has(object_id):
		grabbed_objects.erase(object_id)
	_update_object_registry_state(object_id, {
		"owner_id": "",
		"held_by": "",
		"placed": true,
		"persist_mode": persist_mode,
		"sim_state": release_mode,
		"state_version": incoming_version
	})
	_trace_object_state(object_id, release_mode, incoming_version, "ownership_released")
	ownership_changed.emit(object_id, "", sender_id)


func grab_object(object_id: String, hand_name: String = "", rel_pos: Vector3 = Vector3.ZERO, rel_rot: Quaternion = Quaternion.IDENTITY) -> void:
	var my_id = get_nakama_user_id()
	request_object_ownership(object_id, hand_name, rel_pos, rel_rot)
	grabbed_objects[object_id] = {
		"owner_peer_id": my_id,
		"is_grabbed": true,
		"hand_name": hand_name
	}


func release_object(object_id: String, final_pos: Vector3, final_rot: Quaternion, lin_vel: Vector3 = Vector3.ZERO, ang_vel: Vector3 = Vector3.ZERO, persist_mode: String = "placed_room", release_mode: String = OBJECT_STATE_RELEASED_DYNAMIC) -> void:
	var my_id = get_nakama_user_id()
	if grabbed_objects.has(object_id): grabbed_objects.erase(object_id)
	if _last_object_rep_send_msec.has(object_id):
		_last_object_rep_send_msec.erase(object_id)
	var state_version := _next_object_state_version(object_id)
	
	var release_data = {
		"object_id": object_id,
		"owner_id": "",
		"pos": _vec3_to_dict(final_pos),
		"rot": _quat_to_dict(final_rot),
		"lin_vel": _vec3_to_dict(lin_vel),
		"ang_vel": _vec3_to_dict(ang_vel),
		"persist_mode": persist_mode,
		"release_mode": release_mode,
		"state_version": state_version
	}
	NakamaManager.send_match_state(NakamaManager.MatchOpCode.RELEASE_OBJECT, release_data)
	NakamaManager.send_match_state(NakamaManager.MatchOpCode.OWNERSHIP_RELEASED, {
		"object_id": object_id,
		"released_by": my_id,
		"owner_id": "",
		"persist_mode": persist_mode,
		"release_mode": release_mode,
		"state_version": state_version,
		"pos": _vec3_to_dict(final_pos),
		"rot": _quat_to_dict(final_rot)
	})
	_update_object_registry_state(object_id, {
		"owner_id": "",
		"held_by": "",
		"placed": true,
		"persist_mode": persist_mode,
		"sim_state": release_mode,
		"state_version": state_version,
		"position": _vec3_to_dict(final_pos),
		"rotation": _quat_to_dict(final_rot)
	})
	grabbable_released.emit(object_id, my_id)


func update_grabbed_object(object_id: String, pos: Vector3, rot: Quaternion, rel_pos: Variant = null, rel_rot: Variant = null) -> void:
	if object_id.is_empty():
		return
	var my_id := get_nakama_user_id()
	var state := _ensure_object_registry(object_id)
	if String(state.get("sim_state", "")) != OBJECT_STATE_HELD:
		return
	if String(state.get("owner_id", "")) != my_id:
		return
	var state_version := int(state.get("state_version", 0))
	if state_version <= 0:
		return
	var now := Time.get_ticks_msec()
	var last_sent := int(_last_object_rep_send_msec.get(object_id, 0))
	if now - last_sent < HELD_OBJECT_TRANSFORM_INTERVAL_MS:
		return
	_last_object_rep_send_msec[object_id] = now

	var update_data = {
		"object_id": object_id,
		"pos": pos,
		"rot": rot,
		"state": OBJECT_STATE_HELD,
		"state_version": state_version,
		"is_held": true
	}
	if rel_pos is Vector3: update_data["rel_pos"] = rel_pos
	if rel_rot is Quaternion: update_data["rel_rot"] = rel_rot

	if _can_use_livekit_realtime():
		var packet = {
			"packet_type": "object_update",
			"object_id": object_id,
			"pos": _vec3_to_dict(pos),
			"rot": _quat_to_dict(rot),
			"sender_id": my_id,
			"state": OBJECT_STATE_HELD,
			"state_version": state_version,
			"is_held": true
		}
		if rel_pos is Vector3: packet["rel_pos"] = _vec3_to_dict(rel_pos)
		if rel_rot is Quaternion: packet["rel_rot"] = _quat_to_dict(rel_rot)
		_livekit_wrapper.send_json_packet(packet, LIVEKIT_TOPIC_REP_OBJECT, false)
		return

	# Fallback path: Nakama match relay
	var binary_data = var_to_bytes(update_data)
	NakamaManager.send_match_state(NakamaManager.MatchOpCode.OBJECT_UPDATE, binary_data)


func is_object_grabbed_by_other(object_id: String) -> bool:
	var state := _ensure_object_registry(object_id)
	var holder: String = state.get("held_by", "")
	return not holder.is_empty() and holder != get_nakama_user_id()

func get_object_owner(object_id: String) -> String:
	var state := _ensure_object_registry(object_id)
	return state.get("owner_id", "")


func set_object_persist_mode(object_id: String, persist_mode: String) -> void:
	if object_id.is_empty() or persist_mode.is_empty():
		return
	_update_object_registry_state(object_id, {"persist_mode": persist_mode})
	var node := get_tree().current_scene.get_node_or_null(object_id) if get_tree().current_scene else null
	if node and node.has_method("set_release_persist_mode"):
		node.call("set_release_persist_mode", persist_mode)


func register_replication_manifest(manifest_id: String, manifest: Dictionary) -> void:
	if manifest_id.is_empty():
		return
	_replication_manifests[manifest_id] = manifest.duplicate(true)


func get_replication_manifest(manifest_id: String = "default") -> Dictionary:
	if _replication_manifests.has(manifest_id):
		return _replication_manifests[manifest_id]
	return _replication_manifests.get("default", {}).duplicate(true)


func set_object_manifest_id(object_id: String, manifest_id: String) -> void:
	if object_id.is_empty() or manifest_id.is_empty():
		return
	_update_object_registry_state(object_id, {"manifest_id": manifest_id})


func replicate_object_property(object_id: String, property_name: String, value: Variant, reliable: bool = true) -> void:
	if object_id.is_empty() or property_name.is_empty():
		return
	var my_id := get_nakama_user_id()
	if my_id.is_empty():
		return
	var state := _ensure_object_registry(object_id)
	var active_owner: String = state.get("held_by", state.get("owner_id", ""))
	if not active_owner.is_empty() and active_owner != my_id:
		return
	var prop_seq: int = int(state.get("property_seq", 0)) + 1
	_update_object_registry_state(object_id, {
		"property_seq": prop_seq,
		"properties": _merge_object_property_map(state.get("properties", {}), property_name, value)
	})
	var packet = {
		"packet_type": "object_property_update",
		"object_id": object_id,
		"property_name": property_name,
		"value": value,
		"sender_id": my_id,
		"property_seq": prop_seq
	}
	if _can_use_livekit_realtime():
		_livekit_wrapper.send_json_packet(packet, LIVEKIT_TOPIC_REP_PROPERTY, reliable)
		return
	NakamaManager.send_match_state(NakamaManager.MatchOpCode.OBJECT_PROPERTY_UPDATE, packet)


func _merge_object_property_map(current: Variant, property_name: String, value: Variant) -> Dictionary:
	var properties: Dictionary = {}
	if current is Dictionary:
		properties = (current as Dictionary).duplicate(true)
	properties[property_name] = value
	return properties


# ============================================================================
# Networked Object Spawning
# ============================================================================

func spawn_network_object(scene_path: String, position: Vector3) -> String:
	return spawn_network_object_with_mode(scene_path, position, "placed_room")


func spawn_network_object_with_mode(scene_path: String, position: Vector3, persist_mode: String = "placed_room", manifest_id: String = "default") -> String:
	var object_id = "obj_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 1000)
	var spawn_data = {
		"scene_path": scene_path,
		"pos": _vec3_to_dict(position),
		"object_id": object_id,
		"owner_id": get_nakama_user_id(),
		"persist_mode": persist_mode,
		"sim_state": OBJECT_STATE_RELEASED_STATIC,
		"state_version": 0,
		"manifest_id": manifest_id
	}
	NakamaManager.send_match_state(NakamaManager.MatchOpCode.SPAWN_OBJECT, spawn_data)
	_do_spawn_object(scene_path, position, object_id, persist_mode)
	_update_object_registry_state(object_id, {
		"scene_path": scene_path,
		"position": _vec3_to_dict(position),
		"owner_id": get_nakama_user_id(),
		"held_by": "",
		"placed": true,
		"persist_mode": persist_mode,
		"sim_state": OBJECT_STATE_RELEASED_STATIC,
		"state_version": 0,
		"manifest_id": manifest_id,
		"spawned_by": get_nakama_user_id()
	})
	return object_id


func _do_spawn_object(scene_path: String, position: Vector3, object_id: String, persist_mode: String = "") -> void:
	if scene_path.begins_with("primitive:"):
		var primitive_type := scene_path.trim_prefix("primitive:")
		_do_spawn_primitive_object(primitive_type, position, object_id)
		return

	var scene = load(scene_path)
	if not scene: return
	
	var instance = scene.instantiate()
	instance.name = object_id
	if instance.has_method("set"): instance.set("save_id", object_id)
		
	var world = get_tree().current_scene
	if world:
		world.add_child(instance)
		if instance is Node3D:
			instance.global_position = position
		elif instance is Node2D:
			instance.global_position = Vector2(position.x, position.y)
		if not persist_mode.is_empty() and instance.has_method("set_release_persist_mode"):
			instance.call("set_release_persist_mode", persist_mode)
		print("NetworkManager: Spawned object ", object_id, " at ", position)


func _do_spawn_primitive_object(shape_type: String, position: Vector3, object_id: String) -> void:
	var world := get_tree().current_scene
	if world == null:
		return

	var body := RigidBody3D.new()
	body.name = object_id
	body.set_script(load("res://src/objects/grabbable.gd"))
	if body.has_method("set"):
		body.set("save_id", object_id)

	body.gravity_scale = 0.0
	body.collision_layer = (1 << 0) | (1 << 7) # world + selectable_shapes
	body.collision_mask = 1 << 0
	body.add_to_group("selectable_shapes")

	var mesh_instance := MeshInstance3D.new()
	var collision_shape := CollisionShape3D.new()
	var mesh: Mesh = _build_primitive_mesh(shape_type)
	var shape: Shape3D = _build_primitive_collision_shape(shape_type)

	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	collision_shape.shape = shape

	body.add_child(collision_shape)
	body.add_child(mesh_instance)
	world.add_child(body)
	body.global_position = position
	print("NetworkManager: Spawned primitive ", shape_type, " ", object_id, " at ", position)


func _build_primitive_mesh(shape_type: String) -> Mesh:
	match shape_type:
		"cube":
			var box := BoxMesh.new()
			box.size = Vector3(0.5, 0.5, 0.5)
			return box
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = 0.25
			sphere.height = 0.5
			return sphere
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.25
			cylinder.bottom_radius = 0.25
			cylinder.height = 0.5
			return cylinder
		"cone":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.25
			cone.height = 0.5
			return cone
		"capsule":
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.2
			capsule.height = 0.6
			return capsule
		"prism":
			var prism := PrismMesh.new()
			prism.size = Vector3(0.5, 0.5, 0.5)
			return prism
		_:
			var fallback := BoxMesh.new()
			fallback.size = Vector3(0.5, 0.5, 0.5)
			return fallback


func _build_primitive_collision_shape(shape_type: String) -> Shape3D:
	match shape_type:
		"cube", "prism":
			var box := BoxShape3D.new()
			box.size = Vector3(0.5, 0.5, 0.5)
			return box
		"sphere":
			var sphere := SphereShape3D.new()
			sphere.radius = 0.25
			return sphere
		"cylinder", "cone":
			var cylinder := CylinderShape3D.new()
			cylinder.radius = 0.25
			cylinder.height = 0.5
			return cylinder
		"capsule":
			var capsule := CapsuleShape3D.new()
			capsule.radius = 0.2
			capsule.height = 0.6
			return capsule
		_:
			var fallback := BoxShape3D.new()
			fallback.size = Vector3(0.5, 0.5, 0.5)
			return fallback


# ============================================================================
# Voxel Build Sync
# ============================================================================

func sync_voxel_placed(world_pos: Vector3, color: Color) -> void:
	var data = {
		"pos": _vec3_to_dict(world_pos),
		"color": {"r": color.r, "g": color.g, "b": color.b, "a": color.a}
	}
	NakamaManager.send_match_state(NakamaManager.MatchOpCode.VOXEL_PLACE, data)
	print("NetworkManager: Voxel placement sent via Nakama (JSON for Authority)")

func sync_voxel_removed(world_pos: Vector3) -> void:
	var data = {"pos": _vec3_to_dict(world_pos)}
	NakamaManager.send_match_state(NakamaManager.MatchOpCode.VOXEL_REMOVE, data)
	print("NetworkManager: Voxel removal sent via Nakama")


# ============================================================================
# Nakama State Handling
# ============================================================================

func _on_nakama_match_state_received(peer_id: String, op_code: int, data: Variant) -> void:
	# SECURE COMPONENT: Basic Authority Validation
	# Check if another peer is trying to spoof our local player state
	if peer_id == get_nakama_user_id() and peer_id != "":
		push_warning("NetworkManager: Received match state for local player from remote! Possible spoofing attempt.")
		return

	if op_code == NakamaManager.MatchOpCode.PLAYER_TRANSFORM:
		if data is PackedByteArray:
			var binary_data = bytes_to_var(data)
			if binary_data is Dictionary:
				_handle_nakama_player_transform(peer_id, binary_data)
		else:
			_handle_nakama_player_transform(peer_id, data)
			
	elif op_code == NakamaManager.MatchOpCode.AVATAR_DATA:
		_handle_nakama_avatar_data(peer_id, data)
	elif op_code == NakamaManager.MatchOpCode.VOXEL_PLACE:
		var place_data = data
		if data is PackedByteArray: place_data = bytes_to_var(data)
		
		if place_data is Dictionary and place_data.has("pos"):
			var pos = _parse_vector3(place_data.pos)
			var color = _parse_color(place_data.get("color", Color.WHITE))
			voxel_placed_network.emit(pos, color)
			
	elif op_code == NakamaManager.MatchOpCode.VOXEL_REMOVE:
		var remove_data = data
		if data is PackedByteArray: remove_data = bytes_to_var(data)
		
		if remove_data is Dictionary and remove_data.has("pos"):
			voxel_removed_network.emit(_parse_vector3(remove_data.pos))
			
	elif op_code == NakamaManager.MatchOpCode.SPAWN_OBJECT:
		var spawn_data = data
		if data is PackedByteArray: spawn_data = bytes_to_var(data)
		
		if spawn_data is Dictionary and spawn_data.has("scene_path") and spawn_data.has("pos") and spawn_data.has("object_id"):
			_do_spawn_object(
				spawn_data.scene_path,
				_parse_vector3(spawn_data.pos),
				spawn_data.object_id,
				spawn_data.get("persist_mode", "placed_room")
			)
			_update_object_registry_state(spawn_data.object_id, {
				"scene_path": spawn_data.scene_path,
				"position": spawn_data.get("pos", _vec3_to_dict(Vector3.ZERO)),
				"owner_id": spawn_data.get("owner_id", peer_id),
				"held_by": "",
				"placed": true,
				"persist_mode": spawn_data.get("persist_mode", "placed_room"),
				"sim_state": spawn_data.get("sim_state", OBJECT_STATE_RELEASED_STATIC),
				"state_version": int(spawn_data.get("state_version", 0)),
				"manifest_id": spawn_data.get("manifest_id", "default"),
				"spawned_by": peer_id
			})
			
	elif op_code == NakamaManager.MatchOpCode.GRAB_OBJECT:
		var grab_data = data
		if data is PackedByteArray: grab_data = bytes_to_var(data)
		
		if grab_data is Dictionary and grab_data.has("object_id"):
			var incoming_version := int(grab_data.get("state_version", 0))
			if not _is_transition_version_valid(grab_data.object_id, incoming_version):
				return
			var state_name: String = grab_data.get("state", OBJECT_STATE_HELD)
			_update_object_registry_state(grab_data.object_id, {
				"owner_id": peer_id,
				"held_by": peer_id,
				"placed": false,
				"persist_mode": "transient_held",
				"sim_state": state_name,
				"state_version": incoming_version
			})
			grabbable_grabbed.emit(grab_data.object_id, peer_id, grab_data.get("hand_name", ""), _parse_vector3(grab_data.get("rel_pos", {})), _parse_quaternion(grab_data.get("rel_rot", {})))
			grabbable_sync_update.emit(grab_data.object_id, {
				"is_held": true,
				"state": state_name,
				"state_version": incoming_version
			})
			
	elif op_code == NakamaManager.MatchOpCode.RELEASE_OBJECT:
		var release_data = data
		if data is PackedByteArray: release_data = bytes_to_var(data)
		
		if release_data is Dictionary and release_data.has("object_id"):
			var incoming_version := int(release_data.get("state_version", 0))
			if not _is_transition_version_valid(release_data.object_id, incoming_version):
				return
			var release_mode: String = release_data.get("release_mode", OBJECT_STATE_RELEASED_STATIC)
			if grabbed_objects.has(release_data.object_id):
				grabbed_objects.erase(release_data.object_id)
			_update_object_registry_state(release_data.object_id, {
				"owner_id": String(release_data.get("owner_id", "")),
				"held_by": "",
				"placed": true,
				"persist_mode": release_data.get("persist_mode", "placed_room"),
				"sim_state": release_mode,
				"state_version": incoming_version,
				"position": release_data.get("pos", _vec3_to_dict(Vector3.ZERO)),
				"rotation": release_data.get("rot", _quat_to_dict(Quaternion.IDENTITY))
			})
			_trace_object_state(release_data.object_id, release_mode, incoming_version, "release_packet")
			grabbable_released.emit(release_data.object_id, peer_id)
			if release_data.has("pos"): 
				grabbable_sync_update.emit(release_data.object_id, {
					"position": _parse_vector3(release_data.pos),
					"rotation": _parse_quaternion(release_data.get("rot", {})),
					"linear_velocity": _parse_vector3(release_data.get("lin_vel", {})),
					"angular_velocity": _parse_vector3(release_data.get("ang_vel", {})),
					"is_held": false,
					"state": release_mode,
					"state_version": incoming_version,
					"release_mode": release_mode
				})
	elif op_code == NakamaManager.MatchOpCode.OBJECT_UPDATE:
		var update_data = data
		if data is PackedByteArray:
			update_data = bytes_to_var(data)
			
		if update_data is Dictionary and update_data.has("object_id") and update_data.has("pos") and update_data.has("rot"):
			var state = _ensure_object_registry(update_data.object_id)
			var incoming_version := int(update_data.get("state_version", 0))
			if not _is_transform_version_valid(update_data.object_id, incoming_version):
				return
			if String(state.get("sim_state", OBJECT_STATE_RELEASED_STATIC)) != OBJECT_STATE_HELD:
				return
			var active_owner: String = state.get("held_by", state.get("owner_id", ""))
			if not active_owner.is_empty() and active_owner != peer_id:
				return
			var sync_data = {
				"position": _parse_vector3(update_data.pos),
				"rotation": _parse_quaternion(update_data.rot),
				"is_held": bool(update_data.get("is_held", true)),
				"state": update_data.get("state", OBJECT_STATE_HELD),
				"state_version": incoming_version
			}
			if update_data.has("rel_pos"): sync_data["rel_pos"] = _parse_vector3(update_data.rel_pos)
			if update_data.has("rel_rot"): sync_data["rel_rot"] = _parse_quaternion(update_data.rel_rot)
			_update_object_registry_state(update_data.object_id, {
				"position": update_data.pos,
				"rotation": update_data.rot
			})
			grabbable_sync_update.emit(update_data.object_id, sync_data)
	elif op_code == NakamaManager.MatchOpCode.OBJECT_PROPERTY_UPDATE:
		var prop_data = data
		if data is PackedByteArray:
			prop_data = bytes_to_var(data)
		if prop_data is Dictionary:
			_apply_property_update(peer_id, prop_data)
	elif op_code == NakamaManager.MatchOpCode.PLAYER_NAME_UPDATE:
		var name_data = data
		if data is PackedByteArray:
			name_data = bytes_to_var(data)
		if name_data is Dictionary:
			var updated_peer_id := String(name_data.get("peer_id", peer_id))
			var display_name := String(name_data.get("display_name", ""))
			if not updated_peer_id.is_empty() and not display_name.is_empty():
				_set_peer_display_name(updated_peer_id, display_name, false)
	elif op_code == NakamaManager.MatchOpCode.OWNERSHIP_REQUEST:
		if data is Dictionary:
			_handle_ownership_request(peer_id, data)
	elif op_code == NakamaManager.MatchOpCode.OWNERSHIP_GRANTED:
		if data is Dictionary:
			_handle_ownership_granted(peer_id, data)
	elif op_code == NakamaManager.MatchOpCode.OWNERSHIP_DENIED:
		if data is Dictionary:
			_handle_ownership_denied(peer_id, data)
	elif op_code == NakamaManager.MatchOpCode.OWNERSHIP_RELEASED:
		if data is Dictionary:
			_handle_ownership_released(peer_id, data)
	elif op_code == NakamaManager.MatchOpCode.SNAPSHOT_REQUEST:
		if data is Dictionary and is_server():
			var requester_id: String = data.get("requester_id", peer_id)
			_send_room_snapshot_to_peer(requester_id)
	elif op_code == NakamaManager.MatchOpCode.SNAPSHOT_CHUNK:
		if data is Dictionary:
			_handle_snapshot_chunk(peer_id, data)
	elif op_code == NakamaManager.MatchOpCode.SNAPSHOT_DONE:
		if data is Dictionary:
			_handle_snapshot_done(peer_id, data)


func _parse_vector3(data) -> Vector3:
	if data is Vector3: return data
	if data is Dictionary: return Vector3(data.get("x", 0), data.get("y", 0), data.get("z", 0))
	return Vector3.ZERO

func _parse_color(data) -> Color:
	if data is Color: return data
	if data is Dictionary: return Color(data.get("r", 1), data.get("g", 1), data.get("b", 1), data.get("a", 1))
	return Color.WHITE

func _parse_quaternion(data) -> Quaternion:
	if data is Quaternion: return data
	if data is Dictionary: return Quaternion(data.get("x", 0), data.get("y", 0), data.get("z", 0), data.get("w", 1))
	return Quaternion.IDENTITY


func _can_use_livekit_realtime() -> bool:
	if not use_livekit_data_replication:
		return false
	if not _livekit_wrapper:
		return false
	if _livekit_wrapper.has_method("is_room_connected"):
		return _livekit_wrapper.is_room_connected()
	return false


func _on_livekit_data_packet_received(sender_identity: String, payload: PackedByteArray, topic: String, _reliable: bool) -> void:
	var my_id := get_nakama_user_id()
	if sender_identity == my_id:
		return
	var data_str := payload.get_string_from_utf8()
	var parsed = JSON.parse_string(data_str)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	if topic == LIVEKIT_TOPIC_REP_OBJECT:
		_apply_livekit_object_update(sender_identity, parsed)
	elif topic == LIVEKIT_TOPIC_REP_TRANSFORM:
		_apply_livekit_player_transform(sender_identity, parsed)
	elif topic == LIVEKIT_TOPIC_REP_PROPERTY:
		_apply_property_update(sender_identity, parsed)


func _on_livekit_data_received_legacy(sender_identity: String, data: String) -> void:
	# Legacy fallback when packet signal is unavailable.
	if not use_livekit_data_replication:
		return
	var my_id := get_nakama_user_id()
	if sender_identity == my_id:
		return
	var parsed = JSON.parse_string(data)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var packet_type: String = parsed.get("packet_type", "")
	if packet_type == "object_property_update":
		_apply_property_update(sender_identity, parsed)
	elif packet_type == "object_update":
		_apply_livekit_object_update(sender_identity, parsed)
	elif packet_type == "player_transform" or parsed.has("hp"):
		_apply_livekit_player_transform(sender_identity, parsed)
	elif parsed.has("object_id") and parsed.has("pos") and parsed.has("rot"):
		_apply_livekit_object_update(sender_identity, parsed)


func _apply_livekit_object_update(sender_identity: String, update_data: Dictionary) -> void:
	if not update_data.has("object_id") or not update_data.has("pos") or not update_data.has("rot"):
		return
	var object_id: String = update_data.object_id
	var state = _ensure_object_registry(object_id)
	var incoming_version := int(update_data.get("state_version", 0))
	if not _is_transform_version_valid(object_id, incoming_version):
		return
	if String(state.get("sim_state", OBJECT_STATE_RELEASED_STATIC)) != OBJECT_STATE_HELD:
		return
	var active_owner: String = state.get("held_by", state.get("owner_id", ""))
	if not active_owner.is_empty() and active_owner != sender_identity:
		return
	var sync_data = {
		"position": _parse_vector3(update_data.pos),
		"rotation": _parse_quaternion(update_data.rot),
		"is_held": bool(update_data.get("is_held", true)),
		"state": update_data.get("state", OBJECT_STATE_HELD),
		"state_version": incoming_version
	}
	if update_data.has("rel_pos"): sync_data["rel_pos"] = _parse_vector3(update_data.rel_pos)
	if update_data.has("rel_rot"): sync_data["rel_rot"] = _parse_quaternion(update_data.rel_rot)
	_update_object_registry_state(object_id, {
		"position": update_data.pos,
		"rotation": update_data.rot
	})
	grabbable_sync_update.emit(object_id, sync_data)


func _apply_livekit_player_transform(sender_identity: String, data: Dictionary) -> void:
	if sender_identity.is_empty():
		return
	if not players.has(sender_identity):
		players[sender_identity] = _make_default_remote_player_info(sender_identity)
	var p = players[sender_identity]
	if data.has("hp"): p.head_position = _dict_to_vec3(data.hp)
	if data.has("hr"): p.head_rotation = _dict_to_vec3(data.hr)
	if data.has("lp"): p.left_hand_position = _dict_to_vec3(data.lp)
	if data.has("lr"): p.left_hand_rotation = _dict_to_vec3(data.lr)
	if data.has("rp"): p.right_hand_position = _dict_to_vec3(data.rp)
	if data.has("rr"): p.right_hand_rotation = _dict_to_vec3(data.rr)
	if data.has("s"): p.player_scale = _dict_to_vec3(data.s)


func _apply_property_update(sender_identity: String, data: Dictionary) -> void:
	if not data.has("object_id") or not data.has("property_name"):
		return
	var object_id: String = String(data.get("object_id", ""))
	var property_name: String = String(data.get("property_name", ""))
	if object_id.is_empty() or property_name.is_empty():
		return
	var state := _ensure_object_registry(object_id)
	var active_owner: String = state.get("held_by", state.get("owner_id", ""))
	if not active_owner.is_empty() and active_owner != sender_identity:
		return
	var incoming_seq: int = int(data.get("property_seq", 0))
	var current_seq: int = int(state.get("property_seq", 0))
	if incoming_seq > 0 and incoming_seq < current_seq:
		return
	var value: Variant = data.get("value", null)
	_update_object_registry_state(object_id, {
		"property_seq": maxi(incoming_seq, current_seq + 1),
		"properties": _merge_object_property_map(state.get("properties", {}), property_name, value)
	})
	_apply_network_property_to_node(object_id, property_name, value)
	object_property_updated.emit(object_id, property_name, value, sender_identity)


func _apply_network_property_to_node(object_id: String, property_name: String, value: Variant) -> void:
	if object_id.is_empty() or property_name.is_empty():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var node := scene.get_node_or_null(object_id)
	if node == null:
		return
	if node.has_method("apply_network_property_update"):
		node.call("apply_network_property_update", property_name, value)
		return
	var normalized := NodePath(property_name)
	if node.has_method("set_indexed"):
		node.call("set_indexed", normalized, value)
		return
	node.set(property_name, value)


func request_room_snapshot() -> void:
	var my_id := get_nakama_user_id()
	if my_id.is_empty():
		return
	NakamaManager.send_match_state(NakamaManager.MatchOpCode.SNAPSHOT_REQUEST, {
		"requester_id": my_id,
		"room_id": NakamaManager.current_match_id if NakamaManager else ""
	})


func _send_room_snapshot_to_peer(requester_id: String) -> void:
	if requester_id.is_empty():
		return
	var snapshot_id = "snap_%d_%d" % [Time.get_ticks_usec(), randi() % 100000]
	var objects: Array = []
	for object_id in room_object_registry.keys():
		objects.append(room_object_registry[object_id])

	var total_chunks = maxi(1, int(ceil(float(objects.size()) / float(SNAPSHOT_CHUNK_SIZE))))
	for chunk_index in range(total_chunks):
		var start_i = chunk_index * SNAPSHOT_CHUNK_SIZE
		var end_i = mini(objects.size(), start_i + SNAPSHOT_CHUNK_SIZE)
		var chunk_objects: Array = []
		for i in range(start_i, end_i):
			chunk_objects.append(objects[i])
		NakamaManager.send_match_state(NakamaManager.MatchOpCode.SNAPSHOT_CHUNK, {
			"snapshot_id": snapshot_id,
			"target_peer_id": requester_id,
			"host_peer_id": _get_host_peer_id(),
			"chunk_index": chunk_index,
			"total_chunks": total_chunks,
			"objects": chunk_objects
		})

	NakamaManager.send_match_state(NakamaManager.MatchOpCode.SNAPSHOT_DONE, {
		"snapshot_id": snapshot_id,
		"target_peer_id": requester_id,
		"host_peer_id": _get_host_peer_id(),
		"total_chunks": total_chunks
	})


func _handle_snapshot_chunk(peer_id: String, data: Dictionary) -> void:
	var target_peer_id: String = data.get("target_peer_id", "")
	var my_id := get_nakama_user_id()
	if target_peer_id != my_id:
		return

	var snapshot_id: String = data.get("snapshot_id", "")
	if snapshot_id.is_empty():
		return
	var host_peer_id: String = data.get("host_peer_id", "")
	if not host_peer_id.is_empty():
		_set_host_peer_id(host_peer_id)
	var total_chunks: int = int(data.get("total_chunks", 1))
	var chunk_index: int = int(data.get("chunk_index", 0))
	var chunk_objects: Array = data.get("objects", [])

	if not _snapshot_buffers.has(snapshot_id):
		_snapshot_buffers[snapshot_id] = {
			"from_peer_id": peer_id,
			"total_chunks": total_chunks,
			"chunks": {}
		}

	var bucket = _snapshot_buffers[snapshot_id]
	bucket["total_chunks"] = total_chunks
	bucket["chunks"][chunk_index] = chunk_objects
	_snapshot_buffers[snapshot_id] = bucket


func _handle_snapshot_done(_peer_id: String, data: Dictionary) -> void:
	var target_peer_id: String = data.get("target_peer_id", "")
	var my_id := get_nakama_user_id()
	if target_peer_id != my_id:
		return

	var snapshot_id: String = data.get("snapshot_id", "")
	if snapshot_id.is_empty() or not _snapshot_buffers.has(snapshot_id):
		return
	var host_peer_id: String = data.get("host_peer_id", "")
	if not host_peer_id.is_empty():
		_set_host_peer_id(host_peer_id)
	var bucket = _snapshot_buffers[snapshot_id]
	var total_chunks: int = int(bucket.get("total_chunks", 0))
	var chunks: Dictionary = bucket.get("chunks", {})
	var restored_count := 0

	for chunk_index in range(total_chunks):
		if not chunks.has(chunk_index):
			continue
		var chunk_objects: Array = chunks[chunk_index]
		for object_state in chunk_objects:
			if object_state is Dictionary:
				_apply_snapshot_object_state(object_state)
				restored_count += 1

	_snapshot_buffers.erase(snapshot_id)
	snapshot_reconstructed.emit(snapshot_id, restored_count)


func _apply_snapshot_object_state(object_state: Dictionary) -> void:
	var object_id: String = object_state.get("object_id", "")
	if object_id.is_empty():
		return

	var normalized := _ensure_object_registry(object_id).duplicate(true)
	for key in object_state.keys():
		normalized[key] = object_state[key]
	room_object_registry[object_id] = normalized
	var path: String = object_state.get("scene_path", "")
	var pos: Vector3 = _parse_vector3(object_state.get("position", object_state.get("pos", {})))
	if path.is_empty():
		return
	var existing := get_tree().current_scene.get_node_or_null(object_id) if get_tree().current_scene else null
	if existing:
		return
	_do_spawn_object(path, pos, object_id, object_state.get("persist_mode", "placed_room"))


func _handle_peer_disconnect_objects(peer_id: String) -> void:
	var host_id := _get_host_peer_id()
	var to_remove: Array = []
	for object_id in room_object_registry.keys():
		var state: Dictionary = room_object_registry[object_id]
		var held_by: String = state.get("held_by", "")
		var owner_id: String = state.get("owner_id", "")
		var persist_mode: String = state.get("persist_mode", "placed_room")
		if held_by == peer_id and persist_mode == "transient_held":
			to_remove.append(object_id)
			continue
		if held_by == peer_id or owner_id == peer_id:
			state["held_by"] = ""
			state["owner_id"] = host_id
			state["sim_state"] = OBJECT_STATE_RELEASED_STATIC
			state["state_version"] = int(state.get("state_version", 0)) + 1
			room_object_registry[object_id] = state

	for object_id in to_remove:
		room_object_registry.erase(object_id)
		network_object_despawn_requested.emit(object_id)


# ============================================================================
# Monitoring
# ============================================================================

func _on_monitor_timeout() -> void:
	if not _is_connection_active():
		_update_monitoring_state()
		return
	
	# Simulate stats for Nakama
	network_stats["ping_ms"] = randf_range(40.0, 100.0)
	network_stats_updated.emit(network_stats.duplicate())

func _is_connection_active() -> bool:
	return use_nakama and NakamaManager and NakamaManager.is_socket_connected

func _update_monitoring_state() -> void:
	if _monitor_timer:
		var should_run := _is_connection_active()
		_monitor_timer.paused = not should_run
		if should_run: _monitor_timer.start()
		else: _monitor_timer.stop()
	set_process(voice_mode == VoiceMode.PUSH_TO_TALK and _is_connection_active())

func get_network_stats() -> Dictionary: return network_stats.duplicate()
func get_metrics() -> Dictionary: return _metrics.duplicate()
func get_connection_quality() -> ConnectionQuality: return network_stats["connection_quality"]
func get_connection_quality_string() -> String: return "Good" # Placeholder

func set_voice_activation_mode(mode: VoiceMode) -> void: voice_mode = mode
func set_push_to_talk_key(key: Key) -> void: push_to_talk_key = key
func is_voice_transmitting() -> bool:
	if not voice_enabled: return false
	match voice_mode:
		VoiceMode.ALWAYS_ON: return true
		VoiceMode.PUSH_TO_TALK: return is_push_to_talk_pressed
	return false
