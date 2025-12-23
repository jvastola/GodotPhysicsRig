class_name PlayerVoiceComponent
extends Node

## PlayerVoiceComponent - LiveKit-based Spatial Audio
## Handles microphone capture and manages spatial audio for remote players

# LiveKit Integration
var livekit_manager: Node = null
var voice_enabled: bool = false
var is_muted: bool = false

# Audio Capture
var microphone_player: AudioStreamPlayer = null
var capture_effect: AudioEffectCapture = null
var audio_bus_name = "PlayerVoice"
var audio_bus_idx = -1

# Audio Settings
const BUFFER_SIZE = 4096
var mic_gain_db: float = 0.0

# Spatial Audio Management
var remote_players: Dictionary = {} # identity -> { "player_node": NetworkPlayer, "audio_player": AudioStreamPlayer3D }
var player_scene_root: Node = null # Reference to find NetworkPlayers in scene

# Log rate limiting
var _logged_missing_players: Dictionary = {} # peer_id -> last_log_time
const LOG_COOLDOWN_SEC: float = 10.0 # Only log once per 10 seconds per peer


func setup(p_livekit_manager: Node) -> void:
	"""Initialize voice component with LiveKit manager"""
	livekit_manager = p_livekit_manager
	
	if livekit_manager:
		_setup_microphone()
		_connect_livekit_signals()
		print("PlayerVoiceComponent: Setup with LiveKit manager")
	else:
		push_warning("PlayerVoiceComponent: No LiveKit manager provided")


func _setup_microphone() -> void:
	"""Initialize microphone capture for LiveKit"""
	# Create audio bus
	audio_bus_idx = AudioServer.bus_count
	AudioServer.add_bus(audio_bus_idx)
	AudioServer.set_bus_name(audio_bus_idx, audio_bus_name)
	
	# Add Capture effect
	capture_effect = AudioEffectCapture.new()
	AudioServer.add_bus_effect(audio_bus_idx, capture_effect)
	
	# Route to Master (muted by default)
	AudioServer.set_bus_send(audio_bus_idx, "Master")
	AudioServer.set_bus_volume_db(audio_bus_idx, -80.0) # Muted locally
	
	# Create microphone stream
	var mic_stream = AudioStreamMicrophone.new()
	
	# Create player
	microphone_player = AudioStreamPlayer.new()
	microphone_player.name = "MicrophonePlayer"
	microphone_player.stream = mic_stream
	microphone_player.bus = audio_bus_name
	add_child(microphone_player)
	
	print("PlayerVoiceComponent: Microphone initialized on bus '", audio_bus_name, "'")


func _connect_livekit_signals() -> void:
	"""Connect to LiveKit manager signals"""
	if not livekit_manager:
		return
	
	# Connect participant events
	if livekit_manager.has_signal("participant_joined"):
		livekit_manager.participant_joined.connect(_on_participant_joined)
	if livekit_manager.has_signal("participant_left"):
		livekit_manager.participant_left.connect(_on_participant_left)
	
	# Connect audio frame event
	if livekit_manager.has_signal("audio_frame_received"):
		livekit_manager.audio_frame_received.connect(_on_audio_frame)
	
	print("PlayerVoiceComponent: Connected to LiveKit signals")


func toggle_voice_chat(enabled: bool) -> void:
	"""Enable or disable voice chat"""
	voice_enabled = enabled
	
	if enabled and microphone_player:
		microphone_player.play()
		print("PlayerVoiceComponent: Voice chat enabled")
	elif microphone_player:
		microphone_player.stop()
		print("PlayerVoiceComponent: Voice chat disabled")


func _process(_delta: float) -> void:
	"""Capture and send audio to LiveKit"""
	if not voice_enabled or not livekit_manager or not capture_effect:
		return
	
	# Check if LiveKit is connected
	if not livekit_manager.has_method("is_room_connected") or not livekit_manager.is_room_connected():
		return
	
	# Capture audio and push to LiveKit
	if capture_effect.can_get_buffer(BUFFER_SIZE):
		var buffer = capture_effect.get_buffer(BUFFER_SIZE)
		
		# Only push if not muted
		if not is_muted and buffer.size() > 0 and livekit_manager.has_method("push_mic_audio"):
			livekit_manager.push_mic_audio(buffer)


func set_player_scene_root(root: Node) -> void:
	"""Set the scene root to search for NetworkPlayer nodes"""
	player_scene_root = root


func _on_participant_joined(identity: String, _name: String = "") -> void:
	"""Handle new participant joining LiveKit room"""
	print("PlayerVoiceComponent: Participant joined: ", identity)
	
	# We'll create the audio player when we receive the first audio frame
	# This ensures the NetworkPlayer exists in the scene
	if not remote_players.has(identity):
		remote_players[identity] = {
			"player_node": null,
			"audio_player": null
		}


func _on_participant_left(identity: String) -> void:
	"""Handle participant leaving LiveKit room"""
	print("PlayerVoiceComponent: Participant left: ", identity)
	
	if remote_players.has(identity):
		var player_data = remote_players[identity]
		
		# Clean up audio player
		if player_data["audio_player"]:
			player_data["audio_player"].queue_free()
		
		remote_players.erase(identity)


func _on_audio_frame(peer_id: String, frame: PackedVector2Array) -> void:
	"""Handle incoming audio frame from LiveKit participant"""
	
	# Debug: Log first few frames for each participant
	if not remote_players.has(peer_id):
		print("🎵 PlayerVoiceComponent: First audio frame from: ", peer_id)
	
	# Ensure we have an entry for this participant
	if not remote_players.has(peer_id):
		remote_players[peer_id] = {
			"player_node": null,
			"audio_player": null
		}
	
	var player_data = remote_players[peer_id]
	
	# Find the NetworkPlayer for this participant if we haven't yet
	if not player_data["player_node"]:
		player_data["player_node"] = _find_network_player(peer_id)
		if player_data["player_node"]:
			print("✅ PlayerVoiceComponent: Found NetworkPlayer for ", peer_id, ": ", player_data["player_node"].name)
	
	# Create spatial audio player if needed
	if not player_data["audio_player"] and player_data["player_node"]:
		_create_spatial_audio_player(peer_id, player_data["player_node"])
	
	# Push audio data to the spatial audio player
	if player_data["audio_player"]:
		var audio_player = player_data["audio_player"]
		var playback = audio_player.get_stream_playback()
		
		if playback:
			playback.push_buffer(frame)
	else:
		# Rate-limited logging for missing spatial player
		if frame.size() > 0:
			var now = Time.get_ticks_msec() / 1000.0
			var log_key = peer_id + "_spatial"
			if not _logged_missing_players.has(log_key) or (now - _logged_missing_players[log_key]) > LOG_COOLDOWN_SEC:
				_logged_missing_players[log_key] = now
				print("⚠️ PlayerVoiceComponent: No spatial audio player for ", peer_id, " (audio dropped)")


func _find_network_player(peer_id: String) -> Node:
	"""Find the NetworkPlayer node for a given peer ID"""
	# Try to find by searching the scene tree
	var root = player_scene_root if player_scene_root else get_tree().root
	
	# Search for NetworkPlayer nodes
	var network_players = _get_all_network_players(root)
	
	for player in network_players:
		# Check if the peer_id matches
		if player.has_method("get") and player.get("peer_id") == peer_id:
			return player
		# Also check as property
		if "peer_id" in player and str(player.peer_id) == str(peer_id):
			return player
	
	# Also try matching by identity string
	for player in network_players:
		var player_peer_id = str(player.peer_id) if "peer_id" in player else ""
		if player_peer_id == peer_id:
			return player
	
	# Rate-limited logging
	var now = Time.get_ticks_msec() / 1000.0
	if not _logged_missing_players.has(peer_id) or (now - _logged_missing_players[peer_id]) > LOG_COOLDOWN_SEC:
		_logged_missing_players[peer_id] = now
		print("PlayerVoiceComponent: Could not find NetworkPlayer for peer_id: ", peer_id)
	
	return null


func _get_all_network_players(node: Node) -> Array:
	"""Recursively find all NetworkPlayer nodes in the scene"""
	var players = []
	
	if node.get_script():
		var script_path = node.get_script().resource_path
		if "network_player" in script_path.to_lower():
			players.append(node)
	
	for child in node.get_children():
		players.append_array(_get_all_network_players(child))
	
	return players


func _create_spatial_audio_player(peer_id: String, network_player: Node) -> void:
	"""Create an AudioStreamPlayer3D for spatial audio"""
	if not remote_players.has(peer_id):
		return
	
	var player_data = remote_players[peer_id]
	
	# Find the Head visual node - this is where the actual player position is
	var head_node = network_player.get_node_or_null("Head")
	if not head_node:
		push_error("PlayerVoiceComponent: No Head node found on NetworkPlayer ", network_player.name)
		return
	
	# Create AudioStreamPlayer3D
	var audio_player = AudioStreamPlayer3D.new()
	audio_player.name = "VoicePlayer_" + peer_id
	
	# Create audio stream generator
	var stream = AudioStreamGenerator.new()
	stream.mix_rate = 48000 # Match LiveKit's sample rate
	stream.buffer_length = 0.1 # 100ms buffer
	audio_player.stream = stream
	
	# Configure 3D audio settings
	audio_player.max_distance = 100.0
	audio_player.unit_size = 5.0
	audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	audio_player.bus = "Master"
	
	# CRITICAL FIX: Add to Head node instead of NetworkPlayer root
	# The NetworkPlayer root stays at (0,0,0), but Head has the actual position
	head_node.add_child(audio_player)
	audio_player.autoplay = true
	audio_player.play()
	
	# Store reference
	player_data["audio_player"] = audio_player
	
	print("PlayerVoiceComponent: Created spatial audio player for ", peer_id, " on ", head_node.name, " (parent: ", network_player.name, ")")


func set_muted(muted: bool) -> void:
	"""Set mute status"""
	is_muted = muted
	print("PlayerVoiceComponent: Mute set to: ", is_muted)
	
	# Also notify LiveKit manager (important for Android native audio)
	if livekit_manager and livekit_manager.has_method("set_audio_enabled"):
		livekit_manager.set_audio_enabled(!muted)
		print("  ✓ Called livekit_manager.set_audio_enabled(", !muted, ")")


func set_mic_gain(gain_db: float) -> void:
	"""Set microphone gain"""
	mic_gain_db = gain_db
	if audio_bus_idx != -1:
		AudioServer.set_bus_volume_db(audio_bus_idx, gain_db)


func get_remote_player_count() -> int:
	"""Get the number of remote players with audio"""
	return remote_players.size()


func cleanup() -> void:
	"""Clean up all audio players and resources"""
	for peer_id in remote_players.keys():
		var player_data = remote_players[peer_id]
		if player_data["audio_player"]:
			player_data["audio_player"].queue_free()
	
	remote_players.clear()
	
	if microphone_player:
		microphone_player.queue_free()
		microphone_player = null
