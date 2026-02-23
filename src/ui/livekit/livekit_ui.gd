extends Control
## LiveKit UI Coordinator - Wires together component panels and LiveKitWrapper

# Component references (assigned after instancing)
var connection_panel: ConnectionPanel
var audio_settings: AudioSettingsPanel
var participants_list: ParticipantsList

# LiveKit manager reference
var livekit_manager: Node
# Current room (used for status/labels)
var _current_room_name: String = ""
var current_room_name: String:
	get:
		return _current_room_name
	set(value):
		_current_room_name = value
		_update_room_name_label()

# Status label
@onready var status_label: Label = $Margin/VBox/TitleRow/StatusLabel
@onready var close_button: Button = $Margin/VBox/TitleRow/CloseButton

# Preloaded component scenes
const ConnectionPanelScene = preload("res://src/ui/livekit/components/ConnectionPanel.tscn")
const AudioSettingsScene = preload("res://src/ui/livekit/components/AudioSettingsPanel.tscn")
const ParticipantsListScene = preload("res://src/ui/livekit/components/ParticipantsList.tscn")


func _ready():
	print("=== LiveKit UI Coordinator Ready ===")
	
	# Connect close button
	if close_button:
		close_button.pressed.connect(func(): visible = false)
	
	# Get LiveKitWrapper autoload
	livekit_manager = get_node_or_null("/root/LiveKitWrapper")
	if not livekit_manager:
		_set_status("❌ LiveKitWrapper not found")
		return
	
	# Instance components
	_setup_components()
	
	# Connect LiveKit signals
	_connect_livekit_signals()
	
	# Connect component signals
	_connect_component_signals()
	
	# Set initial sample rate
	var mix_rate = AudioServer.get_mix_rate()
	livekit_manager.set_mic_sample_rate(int(mix_rate))
	
	_set_status("Ready to connect")
	print("✅ LiveKit UI initialized")


func _setup_components():
	# Get container references
	var left_column = $Margin/VBox/Content/LeftColumn
	var right_column = $Margin/VBox/Content/RightColumn
	
	# Clear existing children in left column (except separators)
	for child in left_column.get_children():
		child.queue_free()
	for child in right_column.get_children():
		child.queue_free()
	
	# Instance connection panel
	connection_panel = ConnectionPanelScene.instantiate()
	left_column.add_child(connection_panel)
	
	# Add separator
	var sep = HSeparator.new()
	left_column.add_child(sep)
	
	# Instance audio settings
	audio_settings = AudioSettingsScene.instantiate()
	audio_settings.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_column.add_child(audio_settings)
	
	# Instance participants list
	participants_list = ParticipantsListScene.instantiate()
	participants_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_column.add_child(participants_list)
	
	# Reflect any pre-set room name
	_update_room_name_label()


func _connect_livekit_signals():
	if not livekit_manager:
		return
	
	livekit_manager.room_connected.connect(_on_room_connected)
	livekit_manager.room_disconnected.connect(_on_room_disconnected)
	livekit_manager.participant_joined.connect(_on_participant_joined)
	livekit_manager.participant_left.connect(_on_participant_left)
	livekit_manager.audio_frame_received.connect(_on_audio_frame)
	livekit_manager.participant_metadata_changed.connect(_on_participant_metadata_changed)
	livekit_manager.connection_error.connect(_on_error)


func _connect_component_signals():
	# Connection panel signals
	connection_panel.connect_requested.connect(_on_connect_requested)
	connection_panel.disconnect_requested.connect(_on_disconnect_requested)
	connection_panel.username_changed.connect(_on_username_changed)
	connection_panel.auto_connect_requested.connect(_on_auto_connect_requested)
	
	# Audio settings signals
	audio_settings.mute_toggled.connect(_on_mute_toggled)
	audio_settings.audio_buffer_ready.connect(_on_audio_buffer_ready)
	
	# Participants list signals
	participants_list.participant_volume_changed.connect(_on_participant_volume_changed)
	participants_list.participant_muted.connect(_on_participant_muted)


# === Connection Panel Handlers ===

func _on_connect_requested(server_url: String, token: String):
	_set_status("⏳ Connecting...")
	livekit_manager.connect_to_room(server_url, token)


func _on_disconnect_requested():
	livekit_manager.disconnect_from_room()
	_set_status("Disconnected")
	connection_panel.set_connected(false)
	participants_list.clear()
	
	# Clean up voice component audio players
	var xr_player = get_tree().get_first_node_in_group("xr_player")
	if not xr_player:
		xr_player = get_tree().root.find_child("XRPlayer", true, false)
	if xr_player and xr_player.get("voice_component"):
		xr_player.voice_component.cleanup()


func _on_auto_connect_requested():
	var nakama_manager = get_node_or_null("/root/NakamaManager")
	if not nakama_manager:
		_set_status("❌ NakamaManager not found")
		return
	
	var nakama_id = nakama_manager.local_user_id
	if nakama_id.is_empty() or not nakama_manager.is_authenticated:
		_set_status("⚠️ Connect to Nakama first")
		return
	
	if not nakama_manager.has_method("request_livekit_token"):
		_set_status("❌ Nakama RPC client missing")
		return
	
	var room_name = "godot-oracle-room"
	var token_result: Dictionary = await nakama_manager.request_livekit_token(room_name, nakama_id)
	if not token_result.get("ok", false):
		_set_status("❌ Token RPC failed: " + token_result.get("error", "unknown"))
		return
	
	var token: String = token_result.get("token", "")
	var server_url: String = token_result.get("ws_url", "")
	if server_url.is_empty():
		server_url = "ws://158.101.21.99:7880"
	
	if connection_panel:
		connection_panel.set_server_url(server_url)
		connection_panel.set_token_and_connect(token)
		
	_set_status("✅ Voice token ready for: " + nakama_id)


func _on_username_changed(new_name: String):
	# Sync to LiveKit metadata so other participants see it
	if livekit_manager and livekit_manager.is_room_connected():
		var metadata = JSON.stringify({"username": new_name})
		livekit_manager.set_metadata(metadata)
		print("✅ Username updated in LiveKit: ", new_name)
	
	# Sync to Nakama so it persists across sessions
	if NakamaManager and NakamaManager.is_authenticated:
		NakamaManager.update_display_name(new_name)
		print("✅ Username synced to Nakama: ", new_name)


# === Audio Settings Handlers ===

func _on_mute_toggled(is_muted: bool):
	if livekit_manager and livekit_manager.is_room_connected():
		livekit_manager.set_audio_enabled(!is_muted)
	
	# Also mute XR player voice component
	var xr_player = get_tree().get_first_node_in_group("xr_player")
	if not xr_player:
		xr_player = get_tree().root.find_child("XRPlayer", true, false)
	
	if xr_player and xr_player.has_method("set_muted"):
		xr_player.set_muted(is_muted)


func _on_audio_buffer_ready(buffer: PackedVector2Array):
	if livekit_manager and livekit_manager.is_room_connected():
		livekit_manager.push_mic_audio(buffer)


# === Participants List Handlers ===

func _on_participant_volume_changed(identity: String, volume: float):
	if livekit_manager and livekit_manager.has_method("set_participant_volume"):
		livekit_manager.set_participant_volume(identity, volume)


func _on_participant_muted(identity: String, muted: bool):
	if livekit_manager and livekit_manager.has_method("set_participant_muted"):
		livekit_manager.set_participant_muted(identity, muted)


# === LiveKit Event Handlers ===

func _on_room_connected():
	print("✅ Connected to room")
	
	var room_name = ""
	if livekit_manager.has_method("get_current_room"):
		room_name = livekit_manager.get_current_room()
	# Keep local state in sync for external UI updates
	current_room_name = room_name
	
	_set_status("✅ Connected" + (" to: " + room_name if not room_name.is_empty() else ""))
	connection_panel.set_connected(true, room_name)
	
	# Broadcast our local metadata so others see our username instead of UUID
	var initial_name = connection_panel.local_username
	if livekit_manager.has_method("set_metadata") and not initial_name.is_empty():
		var metadata = JSON.stringify({"username": initial_name})
		livekit_manager.set_metadata(metadata)
		print("✅ Initial metadata (username) broadcasted: ", initial_name)
	
	# Add local participant to the list using our actual identity and name
	var my_identity = livekit_manager.get_local_identity()
	participants_list.add_participant(my_identity)
	
	# And immediately set our display name
	var display_name = initial_name if not initial_name.is_empty() else "You (local)"
	participants_list.set_participant_username(my_identity, display_name + " (You)")
	
	# Query existing participants
	if livekit_manager.has_method("get_participant_identities"):
		var existing = livekit_manager.get_participant_identities()
		for identity in existing:
			if not identity.is_empty() and identity != my_identity:
				participants_list.add_participant(identity)


func _on_room_disconnected():
	print("📴 Disconnected from room")
	current_room_name = ""
	_set_status("Disconnected")
	connection_panel.set_connected(false)
	
	# Force wipe the entire participant UI list so ghosts from ungraceful
	# disconnects don't bleed into the next reconnect attempt
	if participants_list and is_instance_valid(participants_list):
		participants_list.clear()


func _on_participant_joined(identity: String, _name: String = ""):
	print("👤 Joined: ", identity)
	participants_list.add_participant(identity)


func _on_participant_left(identity: String):
	print("👋 Left: ", identity)
	participants_list.remove_participant(identity)


func _on_audio_frame(peer_id: String, frame: PackedVector2Array):
	participants_list.process_audio_frame(peer_id, frame)


func _on_participant_metadata_changed(identity: String, metadata: String):
	var data = JSON.parse_string(metadata)
	if data and data.has("username"):
		participants_list.set_participant_username(identity, data.username)


func _on_error(msg: String):
	print("❌ Error: ", msg)
	_set_status("Error: " + msg)
	connection_panel.set_connected(false)


# === Utility ===

func _set_status(text: String):
	if status_label:
		status_label.text = text


func _update_room_name_label():
	# Update the room label shown in the connection panel
	if connection_panel and connection_panel.room_info_label:
		if _current_room_name.is_empty():
			connection_panel.room_info_label.text = "Room: Not connected"
		else:
			connection_panel.room_info_label.text = "🎙️ Room: " + _current_room_name
