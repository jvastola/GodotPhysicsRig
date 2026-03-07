extends PanelContainer
class_name ParticipantsList
## Participants List - Shows connected participants with friend/mute controls

signal participant_volume_changed(identity: String, volume: float)
signal participant_muted(identity: String, muted: bool)
signal participant_friend_requested(identity: String)

const FRIEND_STATE_UNKNOWN := -99
const FRIEND_STATE_SELF := -98
const FRIEND_STATE_SENDING := -97
const FRIEND_STATE_ERROR := -96
const FRIEND_STATE_FRIEND := 0
const FRIEND_STATE_OUTGOING := 1
const FRIEND_STATE_INCOMING := 2
const FRIEND_STATE_BLOCKED := 3

# UI References
@onready var title_label: Label = $VBox/Header/Title
@onready var count_label: Label = $VBox/Header/Count
@onready var scroll_container: ScrollContainer = $VBox/ScrollContainer
@onready var list_container: VBoxContainer = $VBox/ScrollContainer/ParticipantList

# State
var participants: Dictionary = {} # identity -> { player, level, level_bar, muted, ... }
var participant_usernames: Dictionary = {} # identity -> display name
var participant_friend_states: Dictionary = {} # identity -> Nakama friend state
var audio_playback_enabled: bool = false
var _network_manager: Node = null

# Avatar color palette — vibrant, distinct colors for each participant
const AVATAR_COLORS = [
	Color(0.35, 0.55, 0.95),
	Color(0.45, 0.78, 0.45),
	Color(0.90, 0.45, 0.45),
	Color(0.85, 0.65, 0.30),
	Color(0.70, 0.45, 0.85),
	Color(0.40, 0.80, 0.80),
	Color(0.90, 0.55, 0.70),
	Color(0.65, 0.75, 0.35),
]


func _ready() -> void:
	_network_manager = get_node_or_null("/root/NetworkManager")
	if _network_manager and _network_manager.has_signal("player_name_updated"):
		if not _network_manager.player_name_updated.is_connected(_on_network_player_name_updated):
			_network_manager.player_name_updated.connect(_on_network_player_name_updated)


func _process(delta: float) -> void:
	# Update participant levels, resolved names, and connection status.
	for identity in participants.keys():
		var p_data: Dictionary = participants[identity]

		p_data["level"] = lerp(float(p_data.get("level", 0.0)), 0.0, 10.0 * delta)

		var resolved_name := _resolve_display_name(identity)
		if not resolved_name.is_empty() and participant_usernames.get(identity, "") != resolved_name:
			_set_participant_username_internal(identity, resolved_name, false)

		if p_data.has("level_bar") and p_data["level_bar"] and is_instance_valid(p_data["level_bar"]):
			p_data["level_bar"].value = float(p_data["level"]) * 100.0

		if p_data.get("status_dot") and is_instance_valid(p_data["status_dot"]):
			var network_player = _find_network_player(identity)
			if network_player:
				p_data["status_dot"].color = Color(0.30, 0.85, 0.40)
				var synced_name: String = String(participant_usernames.get(identity, ""))
				if not synced_name.is_empty() and network_player.has_method("set_player_name"):
					if not p_data.get("name_synced", false):
						network_player.set_player_name(synced_name)
					p_data["name_synced"] = true
			else:
				p_data["status_dot"].color = Color(0.50, 0.50, 0.50)
				p_data["name_synced"] = false

		participants[identity] = p_data


func add_participant(identity: String) -> void:
	if identity.is_empty():
		return
	if participants.has(identity):
		var refreshed_name := _resolve_display_name(identity)
		if not refreshed_name.is_empty():
			_set_participant_username_internal(identity, refreshed_name, false)
		return

	var resolved_name := _resolve_display_name(identity)
	if resolved_name.is_empty():
		resolved_name = identity

	participant_usernames[identity] = resolved_name
	participants[identity] = {
		"player": null,
		"level": 0.0,
		"level_bar": null,
		"muted": false,
		"volume": 1.0,
		"status_dot": null,
		"name_label": null,
		"avatar_letter": null,
		"subtitle_label": null,
		"mute_button": null,
		"friend_button": null,
		"name_synced": false,
		"friend_state": _resolve_friend_state(identity),
	}
	print("ParticipantsList: Added ", identity)
	_rebuild_list()


func remove_participant(identity: String) -> void:
	if not participants.has(identity):
		return

	var p_data: Dictionary = participants[identity]
	if p_data.get("player") and is_instance_valid(p_data["player"]):
		p_data["player"].queue_free()

	participants.erase(identity)
	participant_usernames.erase(identity)
	print("ParticipantsList: Removed ", identity)
	_rebuild_list()


func set_participant_username(identity: String, username: String) -> void:
	_set_participant_username_internal(identity, username, true)


func _set_participant_username_internal(identity: String, username: String, rebuild_if_missing: bool) -> void:
	var normalized_name := username.strip_edges()
	if identity.is_empty() or normalized_name.is_empty():
		return

	participant_usernames[identity] = normalized_name

	var network_player = _find_network_player(identity)
	if network_player and network_player.has_method("set_player_name"):
		network_player.set_player_name(normalized_name)
		if participants.has(identity):
			participants[identity]["name_synced"] = true
	elif participants.has(identity):
		participants[identity]["name_synced"] = false

	if participants.has(identity):
		var p_data: Dictionary = participants[identity]
		if p_data.get("name_label") and is_instance_valid(p_data["name_label"]):
			p_data["name_label"].text = normalized_name
		if p_data.get("avatar_letter") and is_instance_valid(p_data["avatar_letter"]):
			p_data["avatar_letter"].text = normalized_name.substr(0, 1).to_upper()
		if p_data.get("subtitle_label") and is_instance_valid(p_data["subtitle_label"]):
			var subtitle_text := _get_identity_subtitle(identity, normalized_name)
			p_data["subtitle_label"].text = subtitle_text
			p_data["subtitle_label"].visible = not subtitle_text.is_empty()
		participants[identity] = p_data
		return

	if rebuild_if_missing:
		_rebuild_list()


func apply_friend_states(friend_states: Dictionary) -> void:
	participant_friend_states = friend_states.duplicate(true)
	for identity in participants.keys():
		set_participant_friend_state(identity, _resolve_friend_state(identity))


func set_participant_friend_state(identity: String, state: int) -> void:
	if identity.is_empty():
		return
	if state >= FRIEND_STATE_FRIEND:
		participant_friend_states[identity] = state
	elif state == FRIEND_STATE_UNKNOWN or state == FRIEND_STATE_ERROR:
		participant_friend_states.erase(identity)
	if not participants.has(identity):
		return
	participants[identity]["friend_state"] = state
	_refresh_friend_button(identity)


func mark_friend_request_started(identity: String) -> void:
	set_participant_friend_state(identity, FRIEND_STATE_SENDING)


func mark_friend_request_failed(identity: String) -> void:
	set_participant_friend_state(identity, FRIEND_STATE_ERROR)


func update_audio_level(identity: String, level: float) -> void:
	if participants.has(identity):
		participants[identity]["level"] = max(float(participants[identity].get("level", 0.0)), level)


func process_audio_frame(identity: String, frame: PackedVector2Array) -> void:
	if not participants.has(identity):
		return

	var p_data: Dictionary = participants[identity]
	if p_data["player"] == null:
		_create_audio_player(identity)
		p_data = participants[identity]

	var max_amp := 0.0
	for sample in frame:
		var amp = max(abs(sample.x), abs(sample.y))
		max_amp = max(max_amp, amp)
	p_data["level"] = max(float(p_data.get("level", 0.0)), max_amp)

	var player = p_data["player"]
	if player and is_instance_valid(player) and not bool(p_data.get("muted", false)) and audio_playback_enabled:
		var playback = player.get_stream_playback()
		if playback:
			var vol = float(p_data.get("volume", 1.0))
			if not is_equal_approx(vol, 1.0):
				var scaled := PackedVector2Array()
				scaled.resize(frame.size())
				for i in range(frame.size()):
					scaled[i] = frame[i] * vol
				playback.push_buffer(scaled)
			else:
				playback.push_buffer(frame)

	participants[identity] = p_data


func _create_audio_player(identity: String) -> void:
	if not participants.has(identity):
		return

	var p_data: Dictionary = participants[identity]
	if p_data["player"] != null:
		return

	var player := AudioStreamPlayer.new()
	var generator := AudioStreamGenerator.new()
	generator.buffer_length = 0.1
	generator.mix_rate = 48000
	player.stream = generator
	player.autoplay = true
	add_child(player)
	player.play()

	p_data["player"] = player
	participants[identity] = p_data
	print("ParticipantsList: Created audio player for ", identity)


func clear() -> void:
	for identity in participants.keys():
		var p_data: Dictionary = participants[identity]
		if p_data.get("player") and is_instance_valid(p_data["player"]):
			p_data["player"].queue_free()

	participants.clear()
	participant_usernames.clear()
	participant_friend_states.clear()
	_rebuild_list()


func set_title(new_title: String) -> void:
	if not title_label:
		return
	title_label.text = new_title.strip_edges()


func _rebuild_list() -> void:
	for child in list_container.get_children():
		child.queue_free()

	if count_label:
		count_label.text = "(%d)" % participants.size()

	for identity in participants.keys():
		var p_data: Dictionary = participants[identity]
		var row := _create_participant_row(identity, p_data)
		list_container.add_child(row)


func _create_participant_row(identity: String, p_data: Dictionary) -> PanelContainer:
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

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	row_panel.add_child(main_vbox)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	main_vbox.add_child(top_row)

	var display_name: String = String(participant_usernames.get(identity, identity))
	var avatar_idx: int = abs(identity.hash()) % AVATAR_COLORS.size()
	var avatar_color: Color = AVATAR_COLORS[avatar_idx]

	var avatar_container := PanelContainer.new()
	avatar_container.custom_minimum_size = Vector2(42, 42)
	var avatar_style := StyleBoxFlat.new()
	avatar_style.bg_color = avatar_color
	avatar_style.corner_radius_top_left = 21
	avatar_style.corner_radius_top_right = 21
	avatar_style.corner_radius_bottom_right = 21
	avatar_style.corner_radius_bottom_left = 21
	avatar_container.add_theme_stylebox_override("panel", avatar_style)
	avatar_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var letter := Label.new()
	letter.text = display_name.substr(0, 1).to_upper()
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.add_theme_font_size_override("font_size", 20)
	letter.add_theme_color_override("font_color", Color.WHITE)
	letter.anchors_preset = Control.PRESET_FULL_RECT
	avatar_container.add_child(letter)
	p_data["avatar_letter"] = letter
	top_row.add_child(avatar_container)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 2)
	top_row.add_child(info_vbox)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	info_vbox.add_child(name_row)

	var status_dot := ColorRect.new()
	status_dot.custom_minimum_size = Vector2(8, 8)
	status_dot.color = Color(0.50, 0.50, 0.50)
	status_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(status_dot)
	p_data["status_dot"] = status_dot

	var name_label := Label.new()
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.93, 0.93, 0.95))
	name_row.add_child(name_label)
	p_data["name_label"] = name_label

	var subtitle := Label.new()
	subtitle.text = _get_identity_subtitle(identity, display_name)
	subtitle.visible = not subtitle.text.is_empty()
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", Color(0.45, 0.47, 0.55))
	info_vbox.add_child(subtitle)
	p_data["subtitle_label"] = subtitle

	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	controls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_row.add_child(controls)

	var friend_btn := Button.new()
	friend_btn.custom_minimum_size = Vector2(92, 30)
	friend_btn.focus_mode = Control.FOCUS_NONE
	friend_btn.pressed.connect(_on_friend_pressed.bind(identity))
	controls.add_child(friend_btn)
	p_data["friend_button"] = friend_btn

	var mute_btn := Button.new()
	mute_btn.toggle_mode = true
	mute_btn.button_pressed = bool(p_data.get("muted", false))
	mute_btn.custom_minimum_size = Vector2(92, 30)
	mute_btn.focus_mode = Control.FOCUS_NONE
	mute_btn.pressed.connect(_on_mute_pressed.bind(identity, mute_btn))
	controls.add_child(mute_btn)
	p_data["mute_button"] = mute_btn
	participants[identity] = p_data
	_refresh_mute_button(identity)
	_refresh_friend_button(identity, friend_btn)

	var level_bar := ProgressBar.new()
	level_bar.custom_minimum_size = Vector2(0, 4)
	level_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_bar.show_percentage = false
	var bar_bg_style := StyleBoxFlat.new()
	bar_bg_style.bg_color = Color(0.10, 0.11, 0.14)
	bar_bg_style.corner_radius_top_left = 2
	bar_bg_style.corner_radius_top_right = 2
	bar_bg_style.corner_radius_bottom_right = 2
	bar_bg_style.corner_radius_bottom_left = 2
	level_bar.add_theme_stylebox_override("background", bar_bg_style)
	var bar_fill_style := StyleBoxFlat.new()
	bar_fill_style.bg_color = Color(0.30, 0.75, 0.45)
	bar_fill_style.corner_radius_top_left = 2
	bar_fill_style.corner_radius_top_right = 2
	bar_fill_style.corner_radius_bottom_right = 2
	bar_fill_style.corner_radius_bottom_left = 2
	level_bar.add_theme_stylebox_override("fill", bar_fill_style)
	main_vbox.add_child(level_bar)
	p_data["level_bar"] = level_bar

	participants[identity] = p_data
	return row_panel


func _get_identity_subtitle(identity: String, display_name: String) -> String:
	if display_name == identity:
		return ""
	var short_id := identity.substr(0, 8) + "..." if identity.length() > 8 else identity
	return short_id


func _resolve_display_name(identity: String) -> String:
	if participant_usernames.has(identity):
		var cached_name := String(participant_usernames[identity]).strip_edges()
		if not cached_name.is_empty() and cached_name != identity:
			return cached_name

	if _network_manager and _network_manager.has_method("get_peer_display_name"):
		var network_name := String(_network_manager.get_peer_display_name(identity)).strip_edges()
		if not network_name.is_empty():
			return network_name

	var local_identity := _get_local_identity()
	if identity == local_identity:
		if NakamaManager and not NakamaManager.display_name.is_empty():
			return NakamaManager.display_name + " (You)"
		return "You"

	return String(participant_usernames.get(identity, identity)).strip_edges()


func _get_local_identity() -> String:
	var livekit_manager := get_node_or_null("/root/LiveKitWrapper")
	if livekit_manager and livekit_manager.has_method("get_local_identity"):
		var livekit_identity := String(livekit_manager.get_local_identity()).strip_edges()
		if not livekit_identity.is_empty():
			return livekit_identity
	if NakamaManager:
		return String(NakamaManager.local_user_id).strip_edges()
	return ""


func _resolve_friend_state(identity: String) -> int:
	if identity == _get_local_identity():
		return FRIEND_STATE_SELF
	if participant_friend_states.has(identity):
		return int(participant_friend_states[identity])
	if participants.has(identity):
		var existing_state := int(participants[identity].get("friend_state", FRIEND_STATE_UNKNOWN))
		if existing_state in [FRIEND_STATE_SENDING, FRIEND_STATE_ERROR]:
			return existing_state
	return FRIEND_STATE_UNKNOWN


func _refresh_friend_button(identity: String, override_button: Button = null) -> void:
	if not participants.has(identity):
		return
	var p_data: Dictionary = participants[identity]
	var button: Button = override_button if override_button != null else p_data.get("friend_button")
	if not button or not is_instance_valid(button):
		return

	var state := int(p_data.get("friend_state", _resolve_friend_state(identity)))
	p_data["friend_state"] = state

	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6

	match state:
		FRIEND_STATE_SELF:
			button.text = "You"
			button.disabled = true
			style.bg_color = Color(0.18, 0.24, 0.30)
		FRIEND_STATE_FRIEND:
			button.text = "Friends"
			button.disabled = true
			style.bg_color = Color(0.20, 0.46, 0.28)
		FRIEND_STATE_OUTGOING:
			button.text = "Pending"
			button.disabled = true
			style.bg_color = Color(0.45, 0.36, 0.18)
		FRIEND_STATE_INCOMING:
			button.text = "Accept"
			button.disabled = false
			style.bg_color = Color(0.26, 0.44, 0.72)
		FRIEND_STATE_BLOCKED:
			button.text = "Blocked"
			button.disabled = true
			style.bg_color = Color(0.34, 0.18, 0.18)
		FRIEND_STATE_SENDING:
			button.text = "Sending..."
			button.disabled = true
			style.bg_color = Color(0.28, 0.28, 0.32)
		FRIEND_STATE_ERROR:
			button.text = "Retry"
			button.disabled = false
			style.bg_color = Color(0.48, 0.22, 0.18)
		_:
			button.text = "Add Friend"
			button.disabled = false
			style.bg_color = Color(0.24, 0.33, 0.52)

	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style.duplicate())
	button.add_theme_stylebox_override("pressed", style.duplicate())
	button.add_theme_stylebox_override("disabled", style.duplicate())
	p_data["friend_button"] = button
	participants[identity] = p_data


func _refresh_mute_button(identity: String) -> void:
	if not participants.has(identity):
		return
	var p_data: Dictionary = participants[identity]
	var button: Button = p_data.get("mute_button")
	if not button or not is_instance_valid(button):
		return

	var muted := bool(p_data.get("muted", false))
	button.text = "Unmute" if muted else "Mute"
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.bg_color = Color(0.42, 0.18, 0.18) if muted else Color(0.20, 0.22, 0.28)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("pressed", style.duplicate())
	button.add_theme_stylebox_override("hover", style.duplicate())


func _on_friend_pressed(identity: String) -> void:
	if not participants.has(identity):
		return
	var current_state := int(participants[identity].get("friend_state", FRIEND_STATE_UNKNOWN))
	if current_state in [FRIEND_STATE_SELF, FRIEND_STATE_FRIEND, FRIEND_STATE_OUTGOING, FRIEND_STATE_BLOCKED, FRIEND_STATE_SENDING]:
		return
	participant_friend_requested.emit(identity)


func _on_volume_changed(value: float, identity: String) -> void:
	if participants.has(identity):
		participants[identity]["volume"] = value
		participant_volume_changed.emit(identity, value)


func _on_mute_pressed(identity: String, _btn: Button) -> void:
	if not participants.has(identity):
		return
	var p_data: Dictionary = participants[identity]
	p_data["muted"] = not bool(p_data.get("muted", false))
	participants[identity] = p_data
	_refresh_mute_button(identity)
	participant_muted.emit(identity, bool(p_data["muted"]))


func _on_network_player_name_updated(peer_id: String, display_name: String) -> void:
	if peer_id.is_empty() or display_name.strip_edges().is_empty():
		return
	_set_participant_username_internal(peer_id, display_name, false)


func _find_network_player(peer_id: String) -> Node:
	var root := get_tree().root
	return _search_network_player(root, peer_id)


func _search_network_player(node: Node, peer_id: String) -> Node:
	if node.name.begins_with("RemotePlayer_"):
		if node.get("peer_id") and str(node.peer_id) == str(peer_id):
			return node
		if node.name == "RemotePlayer_" + str(peer_id):
			return node

	for child in node.get_children():
		var found = _search_network_player(child, peer_id)
		if found:
			return found

	return null


func get_participant_count() -> int:
	return participants.size()


func set_audio_playback_enabled(enabled: bool) -> void:
	audio_playback_enabled = enabled
