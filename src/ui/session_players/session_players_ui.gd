extends Control

const FRIEND_STATE_UNKNOWN := -99
const FRIEND_STATE_FRIEND := 0
const FRIEND_STATE_OUTGOING := 1
const FRIEND_STATE_INCOMING := 2
const FRIEND_STATE_BLOCKED := 3
const FRIEND_REFRESH_INTERVAL_SEC := 3.0

@onready var room_label: Label = $Margin/VBox/Header/RoomLabel
@onready var status_label: Label = $Margin/VBox/Header/StatusLabel
@onready var participants_list: ParticipantsList = $Margin/VBox/Content/SessionPanel/ParticipantsList
@onready var friends_count_label: Label = $Margin/VBox/Content/FriendsPanel/VBox/Header/Count
@onready var friends_list_container: VBoxContainer = $Margin/VBox/Content/FriendsPanel/VBox/ScrollContainer/FriendsList

var livekit_manager: Node = null
var network_manager: Node = null
var _friend_refresh_timer: float = 0.0
var _friend_refresh_in_flight: bool = false
var _friend_action_states: Dictionary = {}
var _last_friend_entries: Array = []


func _ready() -> void:
	livekit_manager = get_node_or_null("/root/LiveKitWrapper")
	network_manager = get_node_or_null("/root/NetworkManager")

	if participants_list:
		participants_list.set_title("SESSION PLAYERS")
		participants_list.participant_volume_changed.connect(_on_participant_volume_changed)
		participants_list.participant_muted.connect(_on_participant_muted)
		participants_list.participant_friend_requested.connect(_on_participant_friend_requested)

	_connect_livekit_signals()
	if NakamaManager and NakamaManager.has_signal("display_name_changed"):
		if not NakamaManager.display_name_changed.is_connected(_on_local_display_name_changed):
			NakamaManager.display_name_changed.connect(_on_local_display_name_changed)

	_update_room_label()
	call_deferred("_refresh_all")


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_friend_refresh_timer += delta
	if _friend_refresh_timer >= FRIEND_REFRESH_INTERVAL_SEC:
		_friend_refresh_timer = 0.0
		call_deferred("_refresh_friend_data")


func _connect_livekit_signals() -> void:
	if not livekit_manager:
		return
	if livekit_manager.has_signal("room_connected") and not livekit_manager.room_connected.is_connected(_on_room_connected):
		livekit_manager.room_connected.connect(_on_room_connected)
	if livekit_manager.has_signal("room_disconnected") and not livekit_manager.room_disconnected.is_connected(_on_room_disconnected):
		livekit_manager.room_disconnected.connect(_on_room_disconnected)
	if livekit_manager.has_signal("participant_joined") and not livekit_manager.participant_joined.is_connected(_on_participant_joined):
		livekit_manager.participant_joined.connect(_on_participant_joined)
	if livekit_manager.has_signal("participant_left") and not livekit_manager.participant_left.is_connected(_on_participant_left):
		livekit_manager.participant_left.connect(_on_participant_left)
	if livekit_manager.has_signal("audio_frame_received") and not livekit_manager.audio_frame_received.is_connected(_on_audio_frame_received):
		livekit_manager.audio_frame_received.connect(_on_audio_frame_received)
	if livekit_manager.has_signal("participant_metadata_changed") and not livekit_manager.participant_metadata_changed.is_connected(_on_participant_metadata_changed):
		livekit_manager.participant_metadata_changed.connect(_on_participant_metadata_changed)


func _refresh_all() -> void:
	_populate_current_session_players()
	call_deferred("_refresh_friend_data")


func _populate_current_session_players() -> void:
	if not participants_list:
		return

	participants_list.clear()
	if not _is_room_connected():
		_update_room_label()
		return

	var local_identity := _get_local_identity()
	if not local_identity.is_empty():
		participants_list.add_participant(local_identity)
		participants_list.set_participant_username(local_identity, _format_local_display_name(_resolve_local_display_name()))

	if livekit_manager and livekit_manager.has_method("get_participant_identities"):
		var identities: PackedStringArray = livekit_manager.get_participant_identities()
		for identity_variant in identities:
			var identity := String(identity_variant).strip_edges()
			if identity.is_empty() or identity == local_identity:
				continue
			participants_list.add_participant(identity)

	_update_room_label()


func _refresh_friend_data() -> void:
	if _friend_refresh_in_flight:
		return
	if not NakamaManager or not NakamaManager.has_method("list_friends") or not NakamaManager.is_authenticated:
		if participants_list:
			participants_list.apply_friend_states({})
		_render_friend_entries([])
		return

	_friend_refresh_in_flight = true
	var list_result: Dictionary = await NakamaManager.list_friends()
	_friend_refresh_in_flight = false
	if not is_inside_tree():
		return
	if not bool(list_result.get("ok", false)):
		_set_status("Failed to refresh friends", true)
		return

	var friend_states_variant: Variant = list_result.get("friend_states", {})
	if participants_list and friend_states_variant is Dictionary:
		participants_list.apply_friend_states(friend_states_variant)

	var entries: Array = []
	var friends_variant: Variant = list_result.get("friends", [])
	if friends_variant is Array:
		entries = _build_friend_entries(friends_variant)
	_render_friend_entries(entries)


func _build_friend_entries(raw_entries: Array) -> Array:
	var entries: Array = []
	for entry_variant in raw_entries:
		if not (entry_variant is Dictionary):
			continue
		var friend_entry: Dictionary = entry_variant
		var user_variant: Variant = friend_entry.get("user", {})
		if not (user_variant is Dictionary):
			continue
		var user_dict: Dictionary = user_variant
		var user_id := String(user_dict.get("id", "")).strip_edges()
		if user_id.is_empty():
			continue

		var state := int(friend_entry.get("state", FRIEND_STATE_UNKNOWN))
		var display_name := _resolve_friend_display_name(user_dict, user_id)
		var subtitle := user_id.substr(0, 8) + "..." if user_id.length() > 8 else user_id
		entries.append({
			"user_id": user_id,
			"display_name": display_name,
			"subtitle": subtitle,
			"state": state,
		})

	entries.sort_custom(_sort_friend_entries)
	return entries


func _sort_friend_entries(a: Dictionary, b: Dictionary) -> bool:
	var a_state := int(a.get("state", FRIEND_STATE_UNKNOWN))
	var b_state := int(b.get("state", FRIEND_STATE_UNKNOWN))
	var a_priority := _friend_state_sort_priority(a_state)
	var b_priority := _friend_state_sort_priority(b_state)
	if a_priority == b_priority:
		return String(a.get("display_name", "")).to_lower() < String(b.get("display_name", "")).to_lower()
	return a_priority < b_priority


func _friend_state_sort_priority(state: int) -> int:
	match state:
		FRIEND_STATE_INCOMING:
			return 0
		FRIEND_STATE_OUTGOING:
			return 1
		FRIEND_STATE_FRIEND:
			return 2
		FRIEND_STATE_BLOCKED:
			return 3
		_:
			return 4


func _render_friend_entries(entries: Array) -> void:
	_last_friend_entries = entries.duplicate(true)
	for child in friends_list_container.get_children():
		child.queue_free()

	var pending_count := 0
	for entry_variant in entries:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		var state := int(entry.get("state", FRIEND_STATE_UNKNOWN))
		if state == FRIEND_STATE_INCOMING or state == FRIEND_STATE_OUTGOING:
			pending_count += 1
		friends_list_container.add_child(_create_friend_row(entry))

	if friends_count_label:
		friends_count_label.text = "(%d total | %d pending)" % [entries.size(), pending_count]

	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No friends or pending requests yet."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.add_theme_color_override("font_color", Color(0.58, 0.62, 0.70))
		empty_label.custom_minimum_size = Vector2(0, 80)
		friends_list_container.add_child(empty_label)


func _create_friend_row(entry: Dictionary) -> PanelContainer:
	var user_id := String(entry.get("user_id", ""))
	var display_name := String(entry.get("display_name", user_id))
	var subtitle := String(entry.get("subtitle", ""))
	var state := int(entry.get("state", FRIEND_STATE_UNKNOWN))
	var action_state := String(_friend_action_states.get(user_id, ""))

	var row_panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.15, 0.20)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	style.border_width_bottom = 1
	style.border_color = Color(0.20, 0.22, 0.28)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	row_panel.add_theme_stylebox_override("panel", style)

	var root_row := HBoxContainer.new()
	root_row.add_theme_constant_override("separation", 12)
	row_panel.add_child(root_row)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 2)
	root_row.add_child(info_vbox)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.93, 0.93, 0.95))
	info_vbox.add_child(name_label)

	var subtitle_label := Label.new()
	subtitle_label.text = subtitle
	subtitle_label.add_theme_font_size_override("font_size", 11)
	subtitle_label.add_theme_color_override("font_color", Color(0.45, 0.47, 0.55))
	info_vbox.add_child(subtitle_label)

	var action_button := Button.new()
	action_button.custom_minimum_size = Vector2(96, 32)
	action_button.focus_mode = Control.FOCUS_NONE
	_configure_friend_action_button(action_button, user_id, state, action_state)
	root_row.add_child(action_button)

	return row_panel


func _configure_friend_action_button(button: Button, user_id: String, state: int, action_state: String) -> void:
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6

	button.disabled = true

	if action_state == "sending":
		button.text = "Sending..."
		style.bg_color = Color(0.28, 0.28, 0.32)
	elif action_state == "error":
		button.text = "Retry"
		button.disabled = false
		style.bg_color = Color(0.48, 0.22, 0.18)
		button.pressed.connect(_on_friend_action_pressed.bind(user_id))
	else:
		match state:
			FRIEND_STATE_FRIEND:
				button.text = "Friends"
				style.bg_color = Color(0.20, 0.46, 0.28)
			FRIEND_STATE_OUTGOING:
				button.text = "Pending"
				style.bg_color = Color(0.45, 0.36, 0.18)
			FRIEND_STATE_INCOMING:
				button.text = "Accept"
				button.disabled = false
				style.bg_color = Color(0.26, 0.44, 0.72)
				button.pressed.connect(_on_friend_action_pressed.bind(user_id))
			FRIEND_STATE_BLOCKED:
				button.text = "Blocked"
				style.bg_color = Color(0.34, 0.18, 0.18)
			_:
				button.text = "Unknown"
				style.bg_color = Color(0.20, 0.22, 0.28)

	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style.duplicate())
	button.add_theme_stylebox_override("pressed", style.duplicate())
	button.add_theme_stylebox_override("disabled", style.duplicate())


func _resolve_friend_display_name(user_dict: Dictionary, user_id: String) -> String:
	if network_manager and network_manager.has_method("get_peer_display_name"):
		var network_name := String(network_manager.get_peer_display_name(user_id)).strip_edges()
		if not network_name.is_empty():
			return network_name

	var display_name := String(user_dict.get("display_name", "")).strip_edges()
	if not display_name.is_empty():
		return display_name
	display_name = String(user_dict.get("displayName", "")).strip_edges()
	if not display_name.is_empty():
		return display_name
	display_name = String(user_dict.get("username", "")).strip_edges()
	if not display_name.is_empty():
		return display_name
	display_name = String(user_dict.get("user_name", "")).strip_edges()
	if not display_name.is_empty():
		return display_name
	return user_id


func _on_participant_volume_changed(identity: String, volume: float) -> void:
	if livekit_manager and livekit_manager.has_method("set_participant_volume"):
		livekit_manager.set_participant_volume(identity, volume)


func _on_participant_muted(identity: String, muted: bool) -> void:
	if livekit_manager and livekit_manager.has_method("set_participant_muted"):
		livekit_manager.set_participant_muted(identity, muted)


func _on_participant_friend_requested(identity: String) -> void:
	_request_friend_action(identity)


func _on_friend_action_pressed(user_id: String) -> void:
	_request_friend_action(user_id)


func _request_friend_action(user_id: String) -> void:
	if not NakamaManager or not NakamaManager.has_method("add_friend_by_id"):
		_set_status("Friend requests unavailable", true)
		return

	_friend_action_states[user_id] = "sending"
	if participants_list:
		participants_list.mark_friend_request_started(user_id)
	_render_friend_entries(_last_friend_entries)
	call_deferred("_refresh_friend_data")
	_set_status("Updating friend request...", false)

	var result: Dictionary = await NakamaManager.add_friend_by_id(user_id)
	if not is_inside_tree():
		return

	if not bool(result.get("ok", false)):
		_friend_action_states[user_id] = "error"
		if participants_list:
			participants_list.mark_friend_request_failed(user_id)
		_render_friend_entries(_last_friend_entries)
		_set_status("Friend request failed", true)
		return

	_friend_action_states.erase(user_id)
	_set_status("Friend request updated", false)
	await _refresh_friend_data()


func _on_room_connected() -> void:
	_populate_current_session_players()
	_update_room_label()
	_set_status("Connected", false)
	call_deferred("_refresh_friend_data")


func _on_room_disconnected() -> void:
	if participants_list:
		participants_list.clear()
	_update_room_label()
	_set_status("Voice room disconnected", true)


func _on_participant_joined(identity: String, _name: String = "") -> void:
	if participants_list:
		participants_list.add_participant(identity)
	call_deferred("_refresh_friend_data")


func _on_participant_left(identity: String) -> void:
	if participants_list:
		participants_list.remove_participant(identity)


func _on_audio_frame_received(peer_id: String, frame: PackedVector2Array) -> void:
	if participants_list:
		participants_list.process_audio_frame(peer_id, frame)


func _on_participant_metadata_changed(identity: String, metadata: String) -> void:
	var parsed: Variant = JSON.parse_string(metadata)
	if not (parsed is Dictionary):
		return
	var parsed_dict: Dictionary = parsed
	var resolved_username := String(parsed_dict.get("username", "")).strip_edges()
	if resolved_username.is_empty():
		return

	if participants_list:
		participants_list.set_participant_username(identity, resolved_username)
	if network_manager and network_manager.has_method("set_peer_display_name"):
		network_manager.set_peer_display_name(identity, resolved_username, false)


func _on_local_display_name_changed(new_name: String) -> void:
	var local_identity := _get_local_identity()
	if local_identity.is_empty() or not participants_list:
		return
	participants_list.set_participant_username(local_identity, _format_local_display_name(new_name))


func _resolve_local_display_name() -> String:
	if NakamaManager and not NakamaManager.display_name.is_empty():
		return NakamaManager.display_name
	if network_manager and network_manager.has_method("get_peer_display_name"):
		var local_identity := _get_local_identity()
		var network_name := String(network_manager.get_peer_display_name(local_identity)).strip_edges()
		if not network_name.is_empty():
			return network_name
	return "You"


func _format_local_display_name(display_name: String) -> String:
	var normalized_name := display_name.strip_edges()
	if normalized_name.is_empty() or normalized_name == "You":
		return "You"
	return normalized_name + " (You)"


func _get_local_identity() -> String:
	if livekit_manager and livekit_manager.has_method("get_local_identity"):
		var livekit_identity := String(livekit_manager.get_local_identity()).strip_edges()
		if not livekit_identity.is_empty():
			return livekit_identity
	if NakamaManager:
		return String(NakamaManager.local_user_id).strip_edges()
	return ""


func _is_room_connected() -> bool:
	if not livekit_manager or not livekit_manager.has_method("is_room_connected"):
		return false
	return bool(livekit_manager.is_room_connected())


func _update_room_label() -> void:
	if not room_label:
		return
	if not _is_room_connected():
		room_label.text = "Room: Not connected"
		return
	var room_name := ""
	if livekit_manager and livekit_manager.has_method("get_current_room"):
		room_name = String(livekit_manager.get_current_room()).strip_edges()
	room_label.text = "Room: " + ("LiveKit" if room_name.is_empty() else room_name)


func _set_status(text: String, is_error: bool) -> void:
	if not status_label:
		return
	status_label.text = text
	status_label.add_theme_color_override("font_color", Color(0.90, 0.45, 0.40) if is_error else Color(0.55, 0.70, 0.95))
