extends Control

# LiveKit Voice Chat UI - Dashboard Design

# UI References - Dashboard Structure
@onready var status_label = $CenterContainer/MainCard/Margin/VBox/Header/StatusLabel

# Left Column - Connection
@onready var username_entry = $"CenterContainer/MainCard/Margin/VBox/Content/LeftColumn/ConnectionSection/UsernameRow/UsernameEntry"
@onready var update_name_button = $"CenterContainer/MainCard/Margin/VBox/Content/LeftColumn/ConnectionSection/UsernameRow/UpdateNameButton"
@onready var server_entry = $"CenterContainer/MainCard/Margin/VBox/Content/LeftColumn/ConnectionSection/ServerEntry"
@onready var token_entry = $"CenterContainer/MainCard/Margin/VBox/Content/LeftColumn/ConnectionSection/TokenEntry"
@onready var connect_button = $"CenterContainer/MainCard/Margin/VBox/Content/LeftColumn/ConnectionSection/Buttons/ConnectButton"
@onready var disconnect_button = $"CenterContainer/MainCard/Margin/VBox/Content/LeftColumn/ConnectionSection/Buttons/DisconnectButton"
@onready var auto_connect_button = $"CenterContainer/MainCard/Margin/VBox/Content/LeftColumn/ConnectionSection/HelperButtons/AutoConnectButton"
@onready var generate_token_button = $"CenterContainer/MainCard/Margin/VBox/Content/LeftColumn/ConnectionSection/HelperButtons/GenerateTokenButton"
@onready var room_info_label = $"CenterContainer/MainCard/Margin/VBox/Content/LeftColumn/ConnectionSection/RoomInfo"

# Left Column - Audio
@onready var mute_button = $"CenterContainer/MainCard/Margin/VBox/Content/LeftColumn/AudioSection/MuteButton"
@onready var mic_level_bar = $"CenterContainer/MainCard/Margin/VBox/Content/LeftColumn/AudioSection/MicLevelBar"
@onready var device_container = $"CenterContainer/MainCard/Margin/VBox/Content/LeftColumn/AudioSection/DeviceContainer"
@onready var gain_slider = $"CenterContainer/MainCard/Margin/VBox/Content/LeftColumn/AudioSection/GainSection/GainSlider"
@onready var gain_value_label = $"CenterContainer/MainCard/Margin/VBox/Content/LeftColumn/AudioSection/GainSection/HBox/Value"
@onready var threshold_slider = $"CenterContainer/MainCard/Margin/VBox/Content/LeftColumn/AudioSection/ThresholdSection/ThresholdSlider"
@onready var threshold_label = $"CenterContainer/MainCard/Margin/VBox/Content/LeftColumn/AudioSection/ThresholdSection/HBox/Value"
@onready var hear_self_check = $"CenterContainer/MainCard/Margin/VBox/Content/LeftColumn/AudioSection/OptionsSection/HearSelfCheck"
@onready var play_global_check = $"CenterContainer/MainCard/Margin/VBox/Content/LeftColumn/AudioSection/OptionsSection/PlayGlobalCheck"

# Right Column - People
@onready var participant_count_label = $"CenterContainer/MainCard/Margin/VBox/Content/RightColumn/Header/Count"
@onready var participant_list = $"CenterContainer/MainCard/Margin/VBox/Content/RightColumn/ScrollContainer/ParticipantList"

# Other
@onready var sandbox_http_request = $SandboxHTTPRequest

# Variables
var input_device_option: OptionButton # Will be added dynamically
var mic_threshold: float = 0.1
var is_muted: bool = false
var hear_own_audio: bool = false
const BUFFER_SIZE = 4096
var audio_bus_name = "LiveKit Mic"
var audio_bus_idx = -1
@export var audio_playback_enabled: bool = false # Default to false to avoid conflict with spatial audio

# Chat and username
var local_username: String = "User-" + str(randi() % 10000)

# Room info
var current_room_name: String = ""
var participant_usernames = {} # Dictionary of identity -> username

var livekit_manager: Node
var participants = {} # Dictionary of participant_id -> { "player": AudioStreamPlayer, "level": float, "level_bar": ProgressBar, "muted": bool, "volume": float }
var capture_effect: AudioEffectCapture
var amplify_effect: AudioEffectAmplify
var mic_player: AudioStreamPlayer


func _ready():
	print("=== LiveKit Audio Client UI - Unified Design ===")
	
	# Setup Audio
	_setup_audio()

	# Create LiveKitManager -> Use Wrapper
	livekit_manager = get_node_or_null("/root/LiveKitWrapper")
	if livekit_manager:
		# Connect signals
		if not livekit_manager.room_connected.is_connected(_on_room_connected):
			livekit_manager.room_connected.connect(_on_room_connected)
		if not livekit_manager.room_disconnected.is_connected(_on_room_disconnected):
			livekit_manager.room_disconnected.connect(_on_room_disconnected)
		if not livekit_manager.participant_joined.is_connected(_on_participant_joined):
			livekit_manager.participant_joined.connect(_on_participant_joined)
		if not livekit_manager.participant_left.is_connected(_on_participant_left):
			livekit_manager.participant_left.connect(_on_participant_left)
		if not livekit_manager.audio_frame_received.is_connected(_on_audio_frame):
			livekit_manager.audio_frame_received.connect(_on_audio_frame)
		if not livekit_manager.participant_metadata_changed.is_connected(_on_participant_metadata_changed):
			livekit_manager.participant_metadata_changed.connect(_on_participant_metadata_changed)
		if not livekit_manager.connection_error.is_connected(_on_error):
			livekit_manager.connection_error.connect(_on_error)
		
		# Set sample rate
		var mix_rate = AudioServer.get_mix_rate()
		livekit_manager.set_mic_sample_rate(int(mix_rate))
		print("🎤 Set LiveKit mic sample rate to: ", mix_rate)
	else:
		print("❌ LiveKitWrapper autoload not found!")
		status_label.text = "❌ Error: LiveKitWrapper not loaded"
		connect_button.disabled = true
		auto_connect_button.disabled = true

	# Connect UI signals - Connection Tab
	connect_button.pressed.connect(_on_connect_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)
	auto_connect_button.pressed.connect(_on_auto_connect_pressed)
	generate_token_button.pressed.connect(_on_generate_token_pressed)
	update_name_button.pressed.connect(_on_update_name_pressed)
	username_entry.text = local_username
	
	# Connect UI signals - Audio Tab
	mute_button.toggled.connect(_on_mute_toggle)
	gain_slider.value_changed.connect(_on_gain_changed)
	threshold_slider.value_changed.connect(_on_threshold_changed)
	hear_self_check.toggled.connect(_on_hear_audio_toggled)
	play_global_check.button_pressed = audio_playback_enabled
	play_global_check.toggled.connect(func(toggled): audio_playback_enabled = toggled)
	
	# Setup audio device selector
	_setup_input_device_selector()
	
	# Auto Connect signals
	sandbox_http_request.request_completed.connect(_on_sandbox_request_completed)
	
	# Initial state
	disconnect_button.disabled = true
	threshold_slider.value = mic_threshold
	_on_threshold_changed(mic_threshold)
	
	# Set default server values for easy testing
	server_entry.text = "ws://localhost:7880"
	token_entry.text = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3NjQxODc2NDcsImlzcyI6ImRldmtleSIsIm5iZiI6MTc2NDEwMTI0Nywic3ViIjoiY2xpZW50LTEiLCJ2aWRlbyI6eyJyb29tIjoidGVzdC1yb29tIiwicm9vbUpvaW4iOnRydWUsImNhblB1Ymxpc2giOnRydWUsImNhblN1YnNjcmliZSI6dHJ1ZX19.tR0faOukMG6GJFXrCRVtPmEJhnbig_pirRyjcqvqy3M"
	
	status_label.text = "Ready to connect"
	print("✅ LiveKit Audio UI Ready (Unified Tab Design)!")


func _setup_input_device_selector():
	"""Create input device selector dropdown"""
	var device_row = HBoxContainer.new()
	device_container.add_child(device_row)
	
	var device_label = Label.new()
	device_label.text = "Device:"
	device_label.custom_minimum_size = Vector2(70, 0)
	device_row.add_child(device_label)
	
	input_device_option = OptionButton.new()
	input_device_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_device_option.item_selected.connect(_on_input_device_selected)
	device_row.add_child(input_device_option)
	_update_input_device_list()
	

func _on_auto_connect_pressed():
	# Get Nakama ID for proper participant identity
	var network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager:
		status_label.text = "❌ Error: NetworkManager not found"
		return
	
	var nakama_id = network_manager.get_nakama_user_id()
	if nakama_id.is_empty():
		status_label.text = "⚠️ Connect to Nakama first for Auto Connect"
		print("⚠️ Auto Connect requires Nakama connection for ID sync")
		return
	
	status_label.text = "⏳ Fetching Sandbox Token..."
	connect_button.disabled = true
	auto_connect_button.disabled = true
	
	var url = "https://cloud-api.livekit.io/api/sandbox/connection-details"
	var headers = [
		"X-Sandbox-ID: conference-pkdo9w",
		"Content-Type: application/json"
	]
	
	# Use Nakama ID as participant name for ID synchronization
	var body = JSON.stringify({
		"room_name": "godot-demo2",
		"participant_name": nakama_id  # CRITICAL: Use Nakama ID here!
	})
	
	print("🔗 Auto Connect: Requesting sandbox token with Nakama ID: ", nakama_id)
	
	var error = sandbox_http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		status_label.text = "❌ HTTP Request Failed: " + str(error)
		connect_button.disabled = false
		auto_connect_button.disabled = false

func _on_sandbox_request_completed(result, response_code, _headers, body):
	auto_connect_button.disabled = false
	
	if result != HTTPRequest.RESULT_SUCCESS:
		status_label.text = "❌ Request Failed"
		connect_button.disabled = false
		return
		
	if response_code != 200:
		status_label.text = "❌ API Error: " + str(response_code)
		print("Response body: ", body.get_string_from_utf8())
		connect_button.disabled = false
		return
		
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json:
		var server_url = json.get("serverUrl", "")
		var token = json.get("participantToken", "")
		
		if server_url and token:
			server_entry.text = server_url
			token_entry.text = token
			print("✅ Received Sandbox Token for: ", json.get("participantName"))
			
			# Auto connect
			_on_connect_pressed()
		else:
			status_label.text = "❌ Invalid Response"
	else:
		status_label.text = "❌ JSON Parse Error"
		connect_button.disabled = false


func _setup_audio():
	# Always create a new bus to ensure clean state, matching mic_visualizer.gd
	# This avoids potential issues with reusing buses in unknown states
	audio_bus_idx = AudioServer.bus_count
	AudioServer.add_bus(audio_bus_idx)
	AudioServer.set_bus_name(audio_bus_idx, audio_bus_name)
	
	# Add Amplify effect first (for local playback)
	amplify_effect = AudioEffectAmplify.new()
	amplify_effect.volume_db = 0.0 # Default ~50x gain, adjustable via slider
	AudioServer.add_bus_effect(audio_bus_idx, amplify_effect)
	
	# Add Capture effect after amplification
	capture_effect = AudioEffectCapture.new()
	AudioServer.add_bus_effect(audio_bus_idx, capture_effect)
	
	# Route to Master
	AudioServer.set_bus_send(audio_bus_idx, "Master")
	
	# List available input devices
	var input_devices = AudioServer.get_input_device_list()
	print("🎤 Available Input Devices: ", input_devices)
	print("🎤 Current Input Device: ", AudioServer.get_input_device())
	print("🎤 Audio Mix Rate: ", AudioServer.get_mix_rate())
	
	# Start microphone input - IMPORTANT: Order matters!
	# Create the microphone stream first
	var mic_stream = AudioStreamMicrophone.new()
	
	# Create the player and configure it
	mic_player = AudioStreamPlayer.new()
	mic_player.stream = mic_stream
	mic_player.bus = audio_bus_name
	add_child(mic_player)
	mic_player.play()
	
	print("🎤 Audio capture initialized on '%s' bus (idx: %d)" % [audio_bus_name, audio_bus_idx])
	print("   - Send to: Master")
	# Use volume for "mute" to avoid disabling capture if that's the issue
	AudioServer.set_bus_mute(audio_bus_idx, false)
	AudioServer.set_bus_volume_db(audio_bus_idx, -80.0) # Effectively muted
	print("   - Muted (via volume): ", AudioServer.get_bus_volume_db(audio_bus_idx) < -60)
	print("   - Volume: ", AudioServer.get_bus_volume_db(audio_bus_idx))

var _debug_timer = 0.0
var _hint_update_timer = 0.0  # Timer for updating Nakama ID hint
func _process(delta):
	# Always process mic audio for visualization and local feedback
	_process_mic_audio()
	
	# Update Nakama ID hint periodically (every 2 seconds)
	# Debug audio state every 2 seconds
	_debug_timer += delta
	if _debug_timer > 2.0:
		_debug_timer = 0.0
		if audio_bus_idx != -1:
			var _is_bus_muted = AudioServer.is_bus_mute(audio_bus_idx)
			var is_player_playing = mic_player.playing
			# print("🔊 [Debug] Bus Muted: %s | Player Playing: %s | Hear Own: %s" % [is_bus_muted, is_player_playing, hear_own_audio])
			
			# Force play if stopped
			if not is_player_playing:
				print("⚠️ Player stopped! Restarting...")
				mic_player.play()

	# Update participant levels and positions
	for p_id in participants:
		var p_data = participants[p_id]
		
		# Decay level
		p_data["level"] = lerp(float(p_data["level"]), 0.0, 10.0 * delta)
		
		if p_data.has("level_bar") and p_data["level_bar"]:
			p_data["level_bar"].value = p_data["level"] * 100
			
		# Update Position Label
		if p_data.get("pos_label"):
			var network_player = _find_network_player(p_id)
			if network_player:
				# NetworkPlayer root stays at (0,0,0), use head visual position instead
				var head = network_player.get_node_or_null("Head")
				if head:
					var pos = head.global_position
					p_data["pos_label"].text = "Pos: (%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z]
					p_data["pos_label"].modulate = Color.GREEN
				else:
					p_data["pos_label"].text = "Pos: No Head Visual"
					p_data["pos_label"].modulate = Color.ORANGE
			else:
				p_data["pos_label"].text = "Pos: Not Found"
				p_data["pos_label"].modulate = Color.RED

var _audio_debug_counter = 0
func _process_mic_audio():
	if capture_effect and capture_effect.can_get_buffer(BUFFER_SIZE):
		var buffer = capture_effect.get_buffer(BUFFER_SIZE)
		
		# Debug: Print mute state periodically
		_audio_debug_counter += 1
		if _audio_debug_counter % 60 == 0:  # Every ~1 second at 60fps
			print("🔊 Audio check: is_muted=", is_muted, ", connected=", livekit_manager != null and livekit_manager.is_room_connected())
		
		# Audio is already amplified by AudioEffectAmplify on the bus
		# No need for additional software gain here
		
		# Only push to LiveKit if connected and not muted
		if livekit_manager and livekit_manager.is_room_connected() and not is_muted:
			livekit_manager.push_mic_audio(buffer)
		
		# Visualize level
		var max_amp = 0.0
		for frame in buffer:
			var amp = max(abs(frame.x), abs(frame.y))
			max_amp = max(max_amp, amp)
		
		# Update mic level bar
		mic_level_bar.value = max_amp * 100
		
		# Visual feedback for threshold
		if max_amp > mic_threshold and not is_muted:
			mic_level_bar.modulate = Color.GREEN
		else:
			mic_level_bar.modulate = Color.WHITE


func _on_connect_pressed():
	var server_url = server_entry.text
	var token = token_entry.text
	
	if server_url.is_empty() or token.is_empty():
		status_label.text = "❌ Error: Enter server URL and token"
		return
	
	print("=".repeat(60))
	print("🔗 ATTEMPTING LIVEKIT CONNECTION")
	print("   Server URL: ", server_url)
	print("   Token length: ", token.length())
	print("   LiveKitManager exists: ", livekit_manager != null)
	if livekit_manager:
		print("   LiveKitManager type: ", livekit_manager.get_class())
		print("   Has connect_to_room method: ", livekit_manager.has_method("connect_to_room"))
	print("=".repeat(60))
	
	status_label.text = "⏳ Connecting..."
	connect_button.disabled = true
	
	if livekit_manager:
		print("📞 Calling livekit_manager.connect_to_room()...")
		livekit_manager.connect_to_room(server_url, token)
		print("✅ connect_to_room() call returned (does not mean connected yet)")
	else:
		status_label.text = "❌ Error: LiveKitWrapper not initialized"
		connect_button.disabled = false

func _on_disconnect_pressed():
	if livekit_manager:
		livekit_manager.disconnect_from_room()
	
	# Reset UI state
	status_label.text = "Disconnected"
	connect_button.disabled = false
	disconnect_button.disabled = true
	
	# Clear participant list
	for child in participant_list.get_children():
		child.queue_free()
	
	# Stop all participant audio players
	for p_id in participants:
		var p_data = participants[p_id]
		if p_data and p_data.get("player"):
			p_data["player"].queue_free()
	
	participants.clear()


func _on_room_connected():
	print("✅ Connected to room!")
	
	# Try to get room name from LiveKit manager
	if livekit_manager and livekit_manager.has_method("get_current_room"):
		current_room_name = livekit_manager.get_current_room()
	
	# Update status with room name
	if current_room_name.is_empty():
		status_label.text = "✅ Connected"
	else:
		status_label.text = "✅ Connected to: " + current_room_name
	
	# Update room info label
	if room_info_label:
		if current_room_name.is_empty():
			room_info_label.text = "Room: Not connected"
		else:
			room_info_label.text = "🎙️ Room: " + current_room_name
	
	connect_button.disabled = true
	disconnect_button.disabled = false
	
	# Add local participant
	_add_participant("You (local)", 0.0)
	_update_participant_list()  # CRITICAL: Render the UI!

func _on_room_disconnected():
	print("📴 Disconnected")
	current_room_name = ""
	status_label.text = "Disconnected"
	connect_button.disabled = false
	disconnect_button.disabled = true
	
	# Update room info label
	if room_info_label:
		room_info_label.text = "Room: Not connected"
	
	# Clear participant list
	for child in participant_list.get_children():
		child.queue_free()
	participants.clear()

func _on_participant_joined(identity: String, _name: String = ""):
	print("👤 Participant joined: ", identity)
	_add_participant(identity, 0.0)
	_update_participant_list()

func _on_participant_left(identity: String):
	print("👋 Participant left: ", identity)
	if participants.has(identity):
		var p_data = participants[identity]
		if p_data and p_data.get("player"):
			p_data["player"].queue_free()
		participants.erase(identity)
		_update_participant_list()

func _on_audio_frame(peer_id: String, frame: PackedVector2Array):
	# Ensure participant exists in dictionary
	if not participants.has(peer_id):
		_add_participant(peer_id, 0.0)
		_update_participant_list()
	
	var p_data = participants[peer_id]
	
	# Create audio player if needed
	if p_data["player"] == null:
		_create_participant_audio(peer_id)
		p_data = participants[peer_id] # Refresh ref
	
	# Calculate level
	var max_amp = 0.0
	for sample in frame:
		var amp = max(abs(sample.x), abs(sample.y))
		max_amp = max(max_amp, amp)
	
	# Update level (keep max for visibility)
	p_data["level"] = max(p_data["level"], max_amp)

	var player = p_data["player"]
	if player and not p_data["muted"] and audio_playback_enabled:
		var playback = player.get_stream_playback()
		if playback:
			# Apply volume scaling
			var vol = p_data.get("volume", 1.0)
			if vol != 1.0:
				var scaled_frame = PackedVector2Array()
				scaled_frame.resize(frame.size())
				for i in range(frame.size()):
					scaled_frame[i] = frame[i] * vol
				playback.push_buffer(scaled_frame)
			else:
				playback.push_buffer(frame)

func _create_participant_audio(peer_id: String):
	# Only create if we don't already have a player for this participant
	if not participants.has(peer_id):
		_add_participant(peer_id, 0.0)
		
	var p_data = participants[peer_id]
	if p_data["player"] == null:
		var player = AudioStreamPlayer.new()
		var generator = AudioStreamGenerator.new()
		generator.buffer_length = 0.1 # 100ms buffer
		generator.mix_rate = 48000
		player.stream = generator
		player.autoplay = true
		add_child(player)
		player.play()
		
		p_data["player"] = player
		print("   Created audio player for: ", peer_id)
		_update_participant_list()

func _on_error(msg: String):
	print("❌ Error: ", msg)
	status_label.text = "Error: " + msg
	connect_button.disabled = false


func _on_mute_toggle(button_pressed: bool):
	# button_pressed = true means the button is pressed (muted)
	is_muted = button_pressed
	mute_button.text = "🔇 Muted" if is_muted else "🎤 Active"
	print("🎤 LiveKit UI Mute toggled: ", is_muted, " (button_pressed: ", button_pressed, ")")
	
	# CRITICAL: Tell LiveKit to enable/disable the audio track
	# This is especially important on Android where the native plugin handles audio
	if livekit_manager and livekit_manager.is_room_connected():
		livekit_manager.set_audio_enabled(!is_muted)
		print("   ✓ Called livekit_manager.set_audio_enabled(", !is_muted, ")")
	
	# Also mute the XR player's voice component (for spatial audio)
	var xr_player = get_tree().get_first_node_in_group("xr_player")
	print("   Looking for xr_player in group: found = ", xr_player != null)
	
	if not xr_player:
		# Fallback: try to find by name
		xr_player = get_tree().root.find_child("XRPlayer", true, false)
		print("   Fallback find_child: found = ", xr_player != null)
		
	if xr_player:
		print("   xr_player.has_method('set_muted'): ", xr_player.has_method("set_muted"))
		if xr_player.has_method("set_muted"):
			xr_player.set_muted(is_muted)
			print("   ✓ Called xr_player.set_muted(", is_muted, ")")
		else:
			print("   ❌ xr_player doesn't have set_muted method!")
	else:
		print("❌ LiveKit UI: Could not find XR player to mute! (Group count: ", get_tree().get_nodes_in_group("xr_player").size(), ")")
	
	# We don't stop the player so we can still see visualization if we wanted,
	# but for now let's just stop pushing audio in _process_mic_audio.
	# Also update visualizer color
	mic_level_bar.modulate = Color.GRAY if is_muted else Color.WHITE

func _on_threshold_changed(value: float):
	mic_threshold = value
	threshold_label.text = "%.2f" % mic_threshold

func _on_hear_audio_toggled(button_pressed: bool):
	hear_own_audio = button_pressed
	if audio_bus_idx != -1:
		# "Mute" by lowering volume, "Unmute" by raising it
		var volume_db = 0.0 if hear_own_audio else -80.0
		AudioServer.set_bus_volume_db(audio_bus_idx, volume_db)
		var actual_volume = AudioServer.get_bus_volume_db(audio_bus_idx)
		var master_mute = AudioServer.is_bus_mute(AudioServer.get_bus_index("Master"))
		print("🔊 Hear own audio: ", hear_own_audio, " (Volume: ", actual_volume, "dB, Master muted: ", master_mute, ")")

func _on_gain_changed(value: float):
	if amplify_effect:
		amplify_effect.volume_db = value
		print("🎚️ Mic gain changed to: ", value, " dB")
		
		# Update label
		gain_value_label.text = "%.1f dB" % value

func _update_input_device_list():
	input_device_option.clear()
	var devices = AudioServer.get_input_device_list()
	var current_device = AudioServer.get_input_device()
	for i in range(devices.size()):
		var device_name = devices[i]
		input_device_option.add_item(device_name)
		if device_name == current_device:
			input_device_option.selected = i

func _on_input_device_selected(index: int):
	var device_name = input_device_option.get_item_text(index)
	print("🎤 Switching Input Device to: ", device_name)
	
	# Stop current player first
	if mic_player:
		mic_player.stop()
	
	# Set the new device
	AudioServer.set_input_device(device_name)
	
	# Wait a frame for the audio driver to switch, then recreate the stream
	await get_tree().process_frame
	
	# Must recreate the AudioStreamMicrophone to pick up the new device
	if mic_player:
		mic_player.stream = AudioStreamMicrophone.new() # Create new stream for new device
		mic_player.play()
		print("   ✅ Microphone stream recreated and playing on: ", AudioServer.get_input_device())


func _add_participant(participant_name: String, _level: float):
	if not participants.has(participant_name):
		# Add participant with null audio player initially
		participants[participant_name] = {
			"player": null,
			"level": 0.0,
			"level_bar": null,
			"muted": false,
			"volume": 1.0
		}
		print("   Added participant to list: ", participant_name)


func _update_participant_list():
	print("📋 _update_participant_list called. participants count: ", participants.size())
	print("   participant_list node valid: ", participant_list != null)
	
	if not participant_list:
		print("   ❌ participant_list is NULL!")
		return
		
	# Clear existing
	for child in participant_list.get_children():
		child.queue_free()
	
	# Update participant count label
	if participant_count_label:
		participant_count_label.text = "(%d)" % participants.size()
		print("   Updated count label to: ", participant_count_label.text)
	
	# Add all participants
	for participant_id in participants.keys():
		var p_data = participants[participant_id]
		
		# Create a styled panel for the row
		var row_panel = PanelContainer.new()
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.17, 0.22) # Slightly darker
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
		avatar.color = Color(0.3, 0.5, 0.9) # Blue avatar
		avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		
		# Add letter
		var letter = Label.new()
		letter.text = participant_id.substr(0, 1).to_upper()
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter.anchors_preset = Control.PRESET_FULL_RECT
		letter.add_theme_font_size_override("font_size", 20)
		avatar.add_child(letter)
		
		hbox.add_child(avatar)
		
		# Info Column (VBox)
		var info_vbox = VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(info_vbox)
		
		# Name label
		var name_label = Label.new()
		# Use username if available, otherwise use identity
		var display_name = participant_usernames.get(participant_id, participant_id)
		name_label.text = display_name
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 18)
		info_vbox.add_child(name_label)
		
		# Details Row (HBox)
		var details_hbox = HBoxContainer.new()
		details_hbox.add_theme_constant_override("separation", 10)
		info_vbox.add_child(details_hbox)
		
		# Position Label (Monospace)
		var pos_label = Label.new()
		pos_label.text = "Pos: --"
		pos_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pos_label.add_theme_font_size_override("font_size", 12)
		details_hbox.add_child(pos_label)
		p_data["pos_label"] = pos_label
		
		# Audio level bar
		var level_bar = ProgressBar.new()
		level_bar.custom_minimum_size = Vector2(60, 8)
		level_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		level_bar.show_percentage = false
		details_hbox.add_child(level_bar)
		p_data["level_bar"] = level_bar
		
		# Controls Container
		var controls_box = HBoxContainer.new()
		controls_box.add_theme_constant_override("separation", 5)
		details_hbox.add_child(controls_box)
		
		# Volume Slider
		var vol_slider = HSlider.new()
		vol_slider.custom_minimum_size = Vector2(80, 0)
		vol_slider.min_value = 0.0
		vol_slider.max_value = 2.0
		vol_slider.step = 0.1
		vol_slider.value = p_data.get("volume", 1.0)
		vol_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		vol_slider.value_changed.connect(_on_participant_volume_changed.bind(participant_id))
		controls_box.add_child(vol_slider)
		
		# Mute Button
		var mute_btn = Button.new()
		mute_btn.text = "🔇" if p_data["muted"] else "🔊"
		mute_btn.toggle_mode = true
		mute_btn.button_pressed = p_data["muted"]
		mute_btn.custom_minimum_size = Vector2(30, 30)
		mute_btn.add_theme_font_size_override("font_size", 12)
		mute_btn.pressed.connect(_on_participant_mute_toggled.bind(participant_id, mute_btn))
		controls_box.add_child(mute_btn)
		
		participant_list.add_child(row_panel)

func _find_network_player(peer_id: String) -> Node:
	# Try to find the NetworkPlayer for this peer_id
	# NetworkPlayers are named "RemotePlayer_<id>" and have peer_id property
	
	# Get all NetworkPlayer nodes (they should all be in root)
	var root = get_tree().root
	
	# Search all nodes recursively
	var found = _search_for_network_player(root, peer_id)
	if found:
		return found
	
	return null


func _search_for_network_player(node: Node, peer_id: String) -> Node:
	# Check if this node is the NetworkPlayer we're looking for
	if node.name.begins_with("RemotePlayer_"):
		# Check peer_id property
		if node.get("peer_id"):
			if str(node.peer_id) == str(peer_id):
				return node
		# Also check if name contains the peer_id
		if node.name == "RemotePlayer_" + str(peer_id):
			return node
	
	# Recursively search children
	for child in node.get_children():
		var found = _search_for_network_player(child, peer_id)
		if found:
			return found
	
	return null

func _on_participant_volume_changed(value: float, participant_id: String):
	if participants.has(participant_id):
		participants[participant_id]["volume"] = value
		print("Volume for ", participant_id, " set to ", value)

func _on_participant_mute_toggled(participant_id: String, btn: Button):
	if participants.has(participant_id):
		var p_data = participants[participant_id]
		p_data["muted"] = !p_data["muted"]
		btn.text = "🔇" if p_data["muted"] else "🔊"
		print("Toggled mute for ", participant_id, ": ", p_data["muted"])


func _on_participant_metadata_changed(identity: String, metadata: String):
	"""Handle participant metadata changes (username updates)"""
	var data = JSON.parse_string(metadata)
	if data and data.has("username"):
		var username = data.username
		print("👤 Name changed for ", identity, ": ", username)
		participant_usernames[identity] = username
		# Update participant list to show new name
		_update_participant_list()


func _update_local_username(new_name: String):
	if new_name.strip_edges().is_empty():
		return
		
	local_username = new_name
	if livekit_manager and livekit_manager.is_room_connected():
		var metadata = JSON.stringify({"username": new_name})
		livekit_manager.set_metadata(metadata)
		print("✅ Username updated to: ", new_name)
		
		# Manually trigger local update since we might not get the event back for ourselves immediately
		# or at all depending on how LiveKit handles local metadata updates
		var identity = livekit_manager.get_local_identity() if livekit_manager.has_method("get_local_identity") else "local"
		_on_participant_name_changed(identity, new_name)
	else:
		print("⚠️ Not connected. Username will be sent on connect.")

func _on_participant_name_changed(identity: String, username: String):
	print("👤 Name changed for ", identity, ": ", username)
	participant_usernames[identity] = username
	
	# Update participant list to show new name
	_update_participant_list()

func _on_update_name_pressed():
	var new_name = username_entry.text.strip_edges()
	if not new_name.is_empty():
		_update_local_username(new_name)


# ============================================================================
# JWT Token Generation
# ============================================================================

func _generate_livekit_token(participant_id: String, room_name: String = "test-room") -> String:
	"""Generate a LiveKit JWT access token using HS256"""
	# LiveKit Cloud credentials
	const API_KEY = "APIbSEA2MXzP8Mf"
	const API_SECRET = "Kqw1FLCX3rq2IWbuWjilBMlgbODqlzxTkgyzKrzuF6I"
	const TOKEN_VALIDITY_HOURS = 24
	
	# Current time
	var now = Time.get_unix_time_from_system()
	var expire_time = now + (TOKEN_VALIDITY_HOURS * 3600)
	
	# JWT Header (HS256 algorithm)
	var header = {
		"alg": "HS256",
		"typ": "JWT"
	}
	
	# JWT Claims (Payload)
	var claims = {
		"exp": exp,
		"iss": API_KEY,
		"nbf": now,
		"sub": participant_id,  # CRITICAL: This must match Nakama user_id
		"video": {
			"room": room_name,
			"roomJoin": true,
			"canPublish": true,
			"canSubscribe": true
		}
	}
	
	# Encode header and payload as base64url
	var header_json = JSON.stringify(header)
	var claims_json = JSON.stringify(claims)
	
	var header_b64 = _base64url_encode(header_json.to_utf8_buffer())
	var payload_b64 = _base64url_encode(claims_json.to_utf8_buffer())
	
	# Create signing input
	var signing_input = header_b64 + "." + payload_b64
	
	# Generate HMAC-SHA256 signature
	var signature = _hmac_sha256(signing_input.to_utf8_buffer(), API_SECRET.to_utf8_buffer())
	var signature_b64 = _base64url_encode(signature)
	
	# Construct final JWT
	var jwt = signing_input + "." + signature_b64
	
	return jwt


func _base64url_encode(data: PackedByteArray) -> String:
	"""Encode data as base64url (JWT standard)"""
	var b64 = Marshalls.raw_to_base64(data)
	# Convert base64 to base64url: replace +/= with -_
	b64 = b64.replace("+", "-")
	b64 = b64.replace("/", "_")
	b64 = b64.replace("=", "")  # Remove padding
	return b64


func _hmac_sha256(message: PackedByteArray, key: PackedByteArray) -> PackedByteArray:
	"""Compute HMAC-SHA256"""
	var ctx = HMACContext.new()
	ctx.start(HashingContext.HASH_SHA256, key)
	ctx.update(message)
	return ctx.finish()


func _on_generate_token_pressed():
	"""Generate a LiveKit token using the Nakama user ID"""
	var network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager:
		status_label.text = "❌ Error: NetworkManager not found"
		return
	
	var nakama_id = network_manager.get_nakama_user_id()
	if nakama_id.is_empty():
		status_label.text = "⚠️ Connect to Nakama first to generate token"
		return
	
	# Generate token
	var token = _generate_livekit_token(nakama_id, "test-room")
	
	# Fill in the token entry
	token_entry.text = token
	
	status_label.text = "✅ Token generated for: " + nakama_id
	print("🎫 Generated LiveKit token for Nakama ID: ", nakama_id)
