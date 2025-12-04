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
var participants: Dictionary = {} # identity -> { player, level, level_bar, muted, volume, pos_label }
var participant_usernames: Dictionary = {} # identity -> display name
var audio_playback_enabled: bool = false


func _process(delta):
	# Update participant levels and positions
	for p_id in participants:
		var p_data = participants[p_id]
		
		# Decay level
		p_data["level"] = lerp(float(p_data["level"]), 0.0, 10.0 * delta)
		
		if p_data.has("level_bar") and p_data["level_bar"]:
			p_data["level_bar"].value = p_data["level"] * 100
		
		# Update position label from NetworkPlayer
		if p_data.get("pos_label"):
			var network_player = _find_network_player(p_id)
			if network_player:
				var head = network_player.get_node_or_null("Head")
				if head:
					var pos = head.global_position
					p_data["pos_label"].text = "Pos: (%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z]
					p_data["pos_label"].modulate = Color.GREEN
				else:
					p_data["pos_label"].text = "Pos: No Head"
					p_data["pos_label"].modulate = Color.ORANGE
			else:
				p_data["pos_label"].text = "Pos: --"
				p_data["pos_label"].modulate = Color.RED


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
		"pos_label": null
	}
	print("ParticipantsList: Added ", identity)
	_rebuild_list()


func remove_participant(identity: String):
	"""Remove a participant from the list"""
	if not participants.has(identity):
		return
	
	var p_data = participants[identity]
	if p_data.get("player"):
		p_data["player"].queue_free()
	
	participants.erase(identity)
	print("ParticipantsList: Removed ", identity)
	_rebuild_list()


func set_participant_username(identity: String, username: String):
	"""Set display name for a participant"""
	participant_usernames[identity] = username
	_rebuild_list()


func update_audio_level(identity: String, level: float):
	"""Update the audio level for a participant"""
	if participants.has(identity):
		participants[identity]["level"] = max(participants[identity]["level"], level)


func process_audio_frame(identity: String, frame: PackedVector2Array):
	"""Process incoming audio frame for a participant"""
	if not participants.has(identity):
		add_participant(identity)
	
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
	if player and not p_data["muted"] and audio_playback_enabled:
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
		if p_data.get("player"):
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
	"""Create a UI row for a participant"""
	var row_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.17, 0.22)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	row_panel.add_theme_stylebox_override("panel", style)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	row_panel.add_child(hbox)
	
	# Avatar
	var avatar = ColorRect.new()
	avatar.custom_minimum_size = Vector2(40, 40)
	avatar.color = Color(0.3, 0.5, 0.9)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var letter = Label.new()
	letter.text = identity.substr(0, 1).to_upper()
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.anchors_preset = Control.PRESET_FULL_RECT
	letter.add_theme_font_size_override("font_size", 20)
	avatar.add_child(letter)
	hbox.add_child(avatar)
	
	# Info column
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)
	
	# Name
	var name_label = Label.new()
	var display_name = participant_usernames.get(identity, identity)
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 18)
	info_vbox.add_child(name_label)
	
	# Details row
	var details = HBoxContainer.new()
	details.add_theme_constant_override("separation", 10)
	info_vbox.add_child(details)
	
	# Position label
	var pos_label = Label.new()
	pos_label.text = "Pos: --"
	pos_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pos_label.add_theme_font_size_override("font_size", 12)
	details.add_child(pos_label)
	p_data["pos_label"] = pos_label
	
	# Level bar
	var level_bar = ProgressBar.new()
	level_bar.custom_minimum_size = Vector2(60, 8)
	level_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	level_bar.show_percentage = false
	details.add_child(level_bar)
	p_data["level_bar"] = level_bar
	
	# Controls
	var controls = HBoxContainer.new()
	controls.add_theme_constant_override("separation", 5)
	details.add_child(controls)
	
	# Volume slider
	var vol_slider = HSlider.new()
	vol_slider.custom_minimum_size = Vector2(80, 0)
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
	mute_btn.custom_minimum_size = Vector2(30, 30)
	mute_btn.add_theme_font_size_override("font_size", 12)
	mute_btn.pressed.connect(_on_mute_pressed.bind(identity, mute_btn))
	controls.add_child(mute_btn)
	
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
