extends Control
## LiveKit UI Coordinator - Wires together component panels and LiveKitWrapper

# Component references (assigned after instancing)
var connection_panel: ConnectionPanel
var audio_settings: AudioSettingsPanel
var participants_list: ParticipantsList

# LiveKit manager reference
var livekit_manager: Node

# Status label
@onready var status_label: Label = $CenterContainer/MainCard/Margin/VBox/Header/StatusLabel

# Preloaded component scenes
const ConnectionPanelScene = preload("res://src/ui/livekit/components/ConnectionPanel.tscn")
const AudioSettingsScene = preload("res://src/ui/livekit/components/AudioSettingsPanel.tscn")
const ParticipantsListScene = preload("res://src/ui/livekit/components/ParticipantsList.tscn")


func _ready():
	print("=== LiveKit UI Coordinator Ready ===")
	
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
	var left_column = $CenterContainer/MainCard/Margin/VBox/Content/LeftColumn
	var right_column = $CenterContainer/MainCard/Margin/VBox/Content/RightColumn
	
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


func _on_auto_connect_requested():
	var network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager:
		_set_status("❌ NetworkManager not found")
		return
	
	var nakama_id = network_manager.get_nakama_user_id()
	if nakama_id.is_empty():
		_set_status("⚠️ Connect to Nakama first")
		return
	
	connection_panel.request_sandbox_token(nakama_id)


func _on_username_changed(new_name: String):
	if livekit_manager and livekit_manager.is_room_connected():
		var metadata = JSON.stringify({"username": new_name})
		livekit_manager.set_metadata(metadata)
		print("✅ Username updated: ", new_name)


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
	
	_set_status("✅ Connected" + (" to: " + room_name if not room_name.is_empty() else ""))
	connection_panel.set_connected(true, room_name)
	
	# Add local participant
	participants_list.add_participant("You (local)")
	
	# Query existing participants
	if livekit_manager.has_method("get_participant_identities"):
		var existing = livekit_manager.get_participant_identities()
		for identity in existing:
			if not identity.is_empty():
				participants_list.add_participant(identity)


func _on_room_disconnected():
	print("📴 Disconnected from room")
	_set_status("Disconnected")
	connection_panel.set_connected(false)
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
