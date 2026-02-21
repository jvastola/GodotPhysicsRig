extends PanelContainer
class_name ParticipantsList
## Participants List - Shows connected participants with volume/mute controls

signal participant_volume_changed(identity: String, volume: float)
signal participant_muted(identity: String, muted: bool)

# UI References
@onready var count_label: Label = $VBox/Header/Count
@onready var scroll_container: ScrollContainer = $VBox/ScrollContainer
@onready var list_container: VBoxContainer = $VBox/ScrollContainer/ParticipantList

# State
var participants: Dictionary = {} # identity -> { player, level, level_bar, muted, volume, status_dot, name_label }
var participant_usernames: Dictionary = {} # identity -> display name
var audio_playback_enabled: bool = false

# Avatar color palette — vibrant, distinct colors for each participant
const AVATAR_COLORS = [
	Color(0.35, 0.55, 0.95),  # Blue
	Color(0.45, 0.78, 0.45),  # Green
	Color(0.90, 0.45, 0.45),  # Red
	Color(0.85, 0.65, 0.30),  # Orange
	Color(0.70, 0.45, 0.85),  # Purple
	Color(0.40, 0.80, 0.80),  # Teal
	Color(0.90, 0.55, 0.70),  # Pink
	Color(0.65, 0.75, 0.35),  # Lime
]


func _process(delta):
	# Update participant levels and connection status
	for p_id in participants:
		var p_data = participants[p_id]
		
		# Decay audio level
		p_data["level"] = lerp(float(p_data["level"]), 0.0, 10.0 * delta)
		
		# Update level bar
		if p_data.has("level_bar") and p_data["level_bar"] and is_instance_valid(p_data["level_bar"]):
			p_data["level_bar"].value = p_data["level"] * 100
		
		# Update connection status dot and sync name
		if p_data.get("status_dot") and is_instance_valid(p_data["status_dot"]):
			var network_player = _find_network_player(p_id)
			if network_player:
				p_data["status_dot"].color = Color(0.30, 0.85, 0.40)  # Green — connected
				
				# Sync the name to the 3D player if we haven't yet
				if not p_data.get("name_synced", false) and participant_usernames.has(p_id):
					if network_player.has_method("set_player_name"):
						network_player.set_player_name(participant_usernames[p_id])
						p_data["name_synced"] = true
			else:
				p_data["status_dot"].color = Color(0.50, 0.50, 0.50)  # Gray — not found
				p_data["name_synced"] = false # Reset if player disappears


func add_participant(identity: String):
	"""Add a participant to the list"""
	if participants.has(identity):
		return
	
	participants[identity] = {
		"player": null,
		"level": 0.0,
		"level_bar": null,
		"muted": false,
		"volume": 1.0,
		"status_dot": null,
		"name_label": null,
		"name_synced": false,
	}
	print("ParticipantsList: Added ", identity)
	_rebuild_list()


func remove_participant(identity: String):
	"""Remove a participant from the list"""
	if not participants.has(identity):
		return
	
	var p_data = participants[identity]
	if p_data.get("player") and is_instance_valid(p_data["player"]):
		p_data["player"].queue_free()
	
	participants.erase(identity)
	print("ParticipantsList: Removed ", identity)
	_rebuild_list()


func set_participant_username(identity: String, username: String):
	"""Set display name for a participant"""
	participant_usernames[identity] = username
	
	# Sync the name down to the 3D player model in the world
	var network_player = _find_network_player(identity)
	if network_player and network_player.has_method("set_player_name"):
		network_player.set_player_name(username)
		if participants.has(identity):
			participants[identity]["name_synced"] = true
	else:
		if participants.has(identity):
			participants[identity]["name_synced"] = false
		
	# Update name_label in-place if it exists (avoids full rebuild flicker)
	if participants.has(identity):
		var p_data = participants[identity]
		if p_data.get("name_label") and is_instance_valid(p_data["name_label"]):
			p_data["name_label"].text = username
			return
	_rebuild_list()


func update_audio_level(identity: String, level: float):
	"""Update the audio level for a participant"""
	if participants.has(identity):
		participants[identity]["level"] = max(participants[identity]["level"], level)


func process_audio_frame(identity: String, frame: PackedVector2Array):
	"""Process incoming audio frame for a participant"""
	if not participants.has(identity):
		return # Do not recreate ghost participants from late audio frames
	
	var p_data = participants[identity]
	
	# Create audio player if needed
	if p_data["player"] == null:
		_create_audio_player(identity)
		p_data = participants[identity]
	
	# Calculate level
	var max_amp = 0.0
	for sample in frame:
		var amp = max(abs(sample.x), abs(sample.y))
		max_amp = max(max_amp, amp)
	p_data["level"] = max(p_data["level"], max_amp)
	
	# Play audio if enabled and not muted
	var player = p_data["player"]
	if player and is_instance_valid(player) and not p_data["muted"] and audio_playback_enabled:
		var playback = player.get_stream_playback()
		if playback:
			var vol = p_data.get("volume", 1.0)
			if vol != 1.0:
				var scaled = PackedVector2Array()
				scaled.resize(frame.size())
				for i in range(frame.size()):
					scaled[i] = frame[i] * vol
				playback.push_buffer(scaled)
			else:
				playback.push_buffer(frame)


func _create_audio_player(identity: String):
	"""Create an audio player for a participant"""
	if not participants.has(identity):
		return
	
	var p_data = participants[identity]
	if p_data["player"] != null:
		return
	
	var player = AudioStreamPlayer.new()
	var generator = AudioStreamGenerator.new()
	generator.buffer_length = 0.1
	generator.mix_rate = 48000
	player.stream = generator
	player.autoplay = true
	add_child(player)
	player.play()
	
	p_data["player"] = player
	print("ParticipantsList: Created audio player for ", identity)


func clear():
	"""Clear all participants"""
	for p_id in participants:
		var p_data = participants[p_id]
		if p_data.get("player") and is_instance_valid(p_data["player"]):
			p_data["player"].queue_free()
	
	participants.clear()
	participant_usernames.clear()
	_rebuild_list()


func _rebuild_list():
	"""Rebuild the participant list UI"""
	# Clear existing
	for child in list_container.get_children():
		child.queue_free()
	
	# Update count
	if count_label:
		count_label.text = "(%d)" % participants.size()
	
	# Add all participants
	for identity in participants.keys():
		var p_data = participants[identity]
		var row = _create_participant_row(identity, p_data)
		list_container.add_child(row)


func _create_participant_row(identity: String, p_data: Dictionary) -> PanelContainer:
	"""Create a modern UI card for a participant"""
	var row_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
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
	
	# Main vertical layout: top row (info + controls) and bottom (level bar)
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	row_panel.add_child(main_vbox)
	
	# Top row: avatar + info + controls
	var top_row = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	main_vbox.add_child(top_row)
	
	# --- Avatar circle ---
	var display_name = participant_usernames.get(identity, identity)
	var avatar_idx = identity.hash() % AVATAR_COLORS.size()
	var avatar_color = AVATAR_COLORS[avatar_idx]
	
	var avatar_container = PanelContainer.new()
	avatar_container.custom_minimum_size = Vector2(42, 42)
	var avatar_style = StyleBoxFlat.new()
	avatar_style.bg_color = avatar_color
	avatar_style.corner_radius_top_left = 21
	avatar_style.corner_radius_top_right = 21
	avatar_style.corner_radius_bottom_right = 21
	avatar_style.corner_radius_bottom_left = 21
	avatar_container.add_theme_stylebox_override("panel", avatar_style)
	avatar_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var letter = Label.new()
	letter.text = display_name.substr(0, 1).to_upper()
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.add_theme_font_size_override("font_size", 20)
	letter.add_theme_color_override("font_color", Color.WHITE)
	letter.anchors_preset = Control.PRESET_FULL_RECT
	avatar_container.add_child(letter)
	top_row.add_child(avatar_container)
	
	# --- Info column (name + subtitle) ---
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 2)
	top_row.add_child(info_vbox)
	
	# Name row: status dot + display name
	var name_row = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	info_vbox.add_child(name_row)
	
	# Connection status dot
	var status_dot = ColorRect.new()
	status_dot.custom_minimum_size = Vector2(8, 8)
	status_dot.color = Color(0.50, 0.50, 0.50)  # Gray = not yet connected
	status_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(status_dot)
	p_data["status_dot"] = status_dot
	
	# Display name (bold, large)
	var name_label = Label.new()
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.93, 0.93, 0.95))
	name_row.add_child(name_label)
	p_data["name_label"] = name_label
	
	# Subtitle: truncated identity (UUID)
	if display_name != identity:
		var subtitle = Label.new()
		var short_id = identity.substr(0, 8) + "…" if identity.length() > 8 else identity
		subtitle.text = short_id
		subtitle.add_theme_font_size_override("font_size", 11)
		subtitle.add_theme_color_override("font_color", Color(0.45, 0.47, 0.55))
		info_vbox.add_child(subtitle)
	
	# --- Controls column (volume + mute) ---
	var controls = HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	controls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_row.add_child(controls)
	
	# Volume slider
	var vol_slider = HSlider.new()
	vol_slider.custom_minimum_size = Vector2(70, 0)
	vol_slider.min_value = 0.0
	vol_slider.max_value = 2.0
	vol_slider.step = 0.1
	vol_slider.value = p_data.get("volume", 1.0)
	vol_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vol_slider.value_changed.connect(_on_volume_changed.bind(identity))
	controls.add_child(vol_slider)
	
	# Mute button
	var mute_btn = Button.new()
	mute_btn.text = "🔇" if p_data["muted"] else "🔊"
	mute_btn.toggle_mode = true
	mute_btn.button_pressed = p_data["muted"]
	mute_btn.custom_minimum_size = Vector2(34, 34)
	mute_btn.add_theme_font_size_override("font_size", 14)
	var mute_style = StyleBoxFlat.new()
	mute_style.bg_color = Color(0.20, 0.22, 0.28)
	mute_style.corner_radius_top_left = 6
	mute_style.corner_radius_top_right = 6
	mute_style.corner_radius_bottom_right = 6
	mute_style.corner_radius_bottom_left = 6
	mute_btn.add_theme_stylebox_override("normal", mute_style)
	mute_btn.pressed.connect(_on_mute_pressed.bind(identity, mute_btn))
	controls.add_child(mute_btn)
	
	# --- Audio level bar (full width, at bottom of card) ---
	var level_bar = ProgressBar.new()
	level_bar.custom_minimum_size = Vector2(0, 4)
	level_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_bar.show_percentage = false
	# Style the level bar
	var bar_bg_style = StyleBoxFlat.new()
	bar_bg_style.bg_color = Color(0.10, 0.11, 0.14)
	bar_bg_style.corner_radius_top_left = 2
	bar_bg_style.corner_radius_top_right = 2
	bar_bg_style.corner_radius_bottom_right = 2
	bar_bg_style.corner_radius_bottom_left = 2
	level_bar.add_theme_stylebox_override("background", bar_bg_style)
	var bar_fill_style = StyleBoxFlat.new()
	bar_fill_style.bg_color = Color(0.30, 0.75, 0.45)
	bar_fill_style.corner_radius_top_left = 2
	bar_fill_style.corner_radius_top_right = 2
	bar_fill_style.corner_radius_bottom_right = 2
	bar_fill_style.corner_radius_bottom_left = 2
	level_bar.add_theme_stylebox_override("fill", bar_fill_style)
	main_vbox.add_child(level_bar)
	p_data["level_bar"] = level_bar
	
	return row_panel


func _on_volume_changed(value: float, identity: String):
	if participants.has(identity):
		participants[identity]["volume"] = value
		participant_volume_changed.emit(identity, value)


func _on_mute_pressed(identity: String, btn: Button):
	if participants.has(identity):
		var p_data = participants[identity]
		p_data["muted"] = not p_data["muted"]
		btn.text = "🔇" if p_data["muted"] else "🔊"
		participant_muted.emit(identity, p_data["muted"])


func _find_network_player(peer_id: String) -> Node:
	"""Find NetworkPlayer node for a peer"""
	var root = get_tree().root
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


func set_audio_playback_enabled(enabled: bool):
	audio_playback_enabled = enabled
