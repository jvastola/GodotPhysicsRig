extends Node
## NakamaTest - Multi-user test scene for Nakama integration
## Tests authentication, matchmaking, and state synchronization

@onready var status_label = $UI/VBoxContainer/Status
@onready var match_info_label = $UI/VBoxContainer/MatchInfo
@onready var players_info_label = $UI/VBoxContainer/PlayersInfo
@onready var console_text = $UI/VBoxContainer/Console
@onready var match_id_input = $UI/VBoxContainer/JoinContainer/MatchIDInput
@onready var host_button = $UI/VBoxContainer/HostButton
@onready var join_button = $UI/VBoxContainer/JoinContainer/JoinButton
@onready var leave_button = $UI/VBoxContainer/LeaveButton
@onready var test_button = $UI/VBoxContainer/TestButton

var test_counter: int = 0


func _ready():
	log_console("==== Nakama Multi-User Test ====")
	log_console("Initializing...")
	
	# Connect signals
	NakamaManager.authenticated.connect(_on_authenticated)
	NakamaManager.authentication_failed.connect(_on_auth_failed)
	NakamaManager.connection_restored.connect(_on_socket_connected)
	NakamaManager.connection_lost.connect(_on_socket_lost)
	NakamaManager.match_created.connect(_on_match_created)
	NakamaManager.match_joined.connect(_on_match_joined)
	NakamaManager.match_left.connect(_on_match_left)
	NakamaManager.match_presence.connect(_on_match_presence)
	NakamaManager.match_state_received.connect(_on_match_state)
	NakamaManager.match_error.connect(_on_match_error)
	
	# Connect UI
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	test_button.pressed.connect(_on_test_pressed)
	
	# Disable buttons until connected
	_update_button_states()
	
	status_label.text = "Authenticating..."
	log_console("Starting authentication...")
	NakamaManager.authenticate_device()


func log_console(text: String):
	print(text)
	console_text.text += text + "\n"
	# Auto-scroll to bottom
	await get_tree().process_frame
	console_text.scroll_vertical = console_text.get_line_count()


func _update_button_states():
	var is_connected = NakamaManager.is_socket_connected
	var in_match = not NakamaManager.current_match_id.is_empty()
	
	host_button.disabled = not is_connected or in_match
	join_button.disabled = not is_connected or in_match
	leave_button.disabled = not in_match
	test_button.disabled = not in_match


func _on_authenticated(session):
	log_console("✓ Authentication successful!")
	log_console("  User ID: " + str(session.get("user_id", "unknown")))
	status_label.text = "Authenticated - Connecting socket..."


func _on_auth_failed(error):
	log_console("✗ Authentication failed: " + str(error))
	status_label.text = "Authentication failed: " + str(error)
	status_label.add_theme_color_override("font_color", Color.RED)


func _on_socket_connected():
	log_console("✓ WebSocket connected!")
	log_console("  Ready for multiplayer!")
	status_label.text = "Connected - Ready!"
	status_label.add_theme_color_override("font_color", Color.GREEN)
	_update_button_states()


func _on_socket_lost():
	log_console("✗ WebSocket disconnected!")
	status_label.text = "Disconnected - Reconnecting..."
	status_label.add_theme_color_override("font_color", Color.ORANGE)
	_update_button_states()


func _on_match_created(match_id, label):
	log_console("✓ Match created!")
	log_console("  Match ID: " + match_id)
	log_console("  Label: " + label)
	log_console("  >> Share this ID with other players!")
	match_info_label.text = "Match: " + match_id
	match_id_input.text = match_id  # Auto-fill for easy copying
	_update_button_states()


func _on_match_joined(match_id):
	log_console("✓ Joined match: " + match_id)
	match_info_label.text = "In Match: " + match_id
	_update_button_states()
	
	# Update player count immediately (match_peers is already populated from match join)
	_update_player_count()


func _on_match_left():
	log_console("Left match")
	match_info_label.text = "Not in match"
	players_info_label.text = "Players: 0"
	_update_button_states()


func _on_match_presence(joins, leaves):
	log_console("--- Match Presence Update ---")
	for join in joins:
		var user_id = join.get("user_id", "unknown")
		log_console("  + Player joined: " + user_id)
	for leave in leaves:
		var user_id = leave.get("user_id", "unknown")
		log_console("  - Player left: " + user_id)
	
	# Update player count
	_update_player_count()


func _update_player_count():
	# match_peers tracks all OTHER players (not including self)
	# So total = peers + 1 for self
	var peer_count = NakamaManager.match_peers.size()
	var total = peer_count + 1  # +1 for self
	players_info_label.text = "Players: " + str(total) + " (you + " + str(peer_count) + " others)"


func _on_match_state(peer_id, op_code, data):
	var op_name = "UNKNOWN"
	match op_code:
		NakamaManager.MatchOpCode.PLAYER_TRANSFORM:
			op_name = "TRANSFORM"
		NakamaManager.MatchOpCode.GRAB_OBJECT:
			op_name = "GRAB"
		NakamaManager.MatchOpCode.VOICE_DATA:
			op_name = "VOICE"
		_:
			op_name = "OP_" + str(op_code)
	
	log_console("← Received [" + op_name + "] from " + peer_id.substr(0, 8) + "...")
	if data is Dictionary and data.has("test_id"):
		log_console("  Test ID: " + str(data.test_id))
	if data is Dictionary and data.has("position"):
		log_console("  Position: " + str(data.position))
	if data is PackedByteArray:
		log_console("  Data: " + str(data.size()) + " bytes (Raw)")


func _on_match_error(error):
	log_console("✗ Match error: " + str(error))


func _on_host_pressed():
	log_console("\n[HOST] Creating match...")
	NakamaManager.create_match()


func _on_join_pressed():
	var match_id = match_id_input.text.strip_edges()
	if match_id.is_empty():
		log_console("✗ Please enter a Match ID")
		return
	
	log_console("\n[JOIN] Joining match: " + match_id)
	NakamaManager.join_match(match_id)


func _on_leave_pressed():
	log_console("\n[LEAVE] Leaving match...")
	NakamaManager.leave_match()


func _on_test_pressed():
	test_counter += 1
	log_console("\n[TEST] Sending test data #" + str(test_counter))
	
	NakamaManager.send_match_state(
		NakamaManager.MatchOpCode.PLAYER_TRANSFORM,
		{
			"test_id": test_counter,
			"position": {
				"x": randf() * 10,
				"y": randf() * 10,
				"z": randf() * 10
			},
			"timestamp": Time.get_ticks_msec()
		}
	)
	log_console("→ Sent test data")


func _test_voice():
	log_console("\n[TEST] Sending fake voice data...")
	
	# Create fake audio data (100 samples of silence/noise)
	var dummy_audio = PackedByteArray()
	dummy_audio.resize(400) # 100 samples * 4 bytes
	for i in range(400):
		dummy_audio[i] = randi() % 256
		
	NakamaManager.send_match_state(
		NakamaManager.MatchOpCode.VOICE_DATA,
		dummy_audio
	)
	log_console("→ Sent " + str(dummy_audio.size()) + " bytes of voice data")


func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_H:
				if not host_button.disabled:
					_on_host_pressed()
			KEY_J:
				if not join_button.disabled:
					_on_join_pressed()
			KEY_L:
				if not leave_button.disabled:
					_on_leave_pressed()
			KEY_T:
				if not test_button.disabled:
					_on_test_pressed()
			KEY_V:
				if not test_button.disabled:
					_test_voice()


func _process(_delta):
	# Update window title with status
	var title = "Nakama Test"
	if NakamaManager.is_authenticated:
		if NakamaManager.is_socket_connected:
			if not NakamaManager.current_match_id.is_empty():
				title += " - IN MATCH (" + str(NakamaManager.match_peers.size() + 1) + " players)"
			else:
				title += " - Connected (H=Host J=Join)"
		else:
			title += " - Connecting..."
	else:
		title += " - Authenticating..."
	
	DisplayServer.window_set_title(title)
