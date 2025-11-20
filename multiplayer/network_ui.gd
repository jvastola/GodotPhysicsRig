extends Control
## NetworkUI - User interface for hosting and joining multiplayer games

@onready var host_button: Button = $VBoxContainer/HostButton
@onready var join_button: Button = $VBoxContainer/JoinButton
@onready var disconnect_button: Button = $VBoxContainer/DisconnectButton
@onready var address_input: LineEdit = $VBoxContainer/AddressInput
@onready var room_code_input: LineEdit = $VBoxContainer/RoomCodeInput
@onready var port_input: LineEdit = $VBoxContainer/PortInput
@onready var use_room_code_check: CheckButton = $VBoxContainer/UseRoomCodeCheck
@onready var keyboard_button: Button = $VBoxContainer/KeyboardButton

var virtual_keyboard: Node = null
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var player_list_label: Label = $VBoxContainer/PlayerListLabel
@onready var voice_button: Button = $VBoxContainer/VoiceButton
@onready var avatar_button: Button = $VBoxContainer/AvatarButton

# Network stats labels (optional nodes - may not exist in scene yet)
@onready var ping_label: Label = get_node_or_null("VBoxContainer/StatsContainer/PingLabel")
@onready var bandwidth_label: Label = get_node_or_null("VBoxContainer/StatsContainer/BandwidthLabel")
@onready var quality_label: Label = get_node_or_null("VBoxContainer/StatsContainer/QualityLabel")
@onready var quality_indicator: ColorRect = get_node_or_null("VBoxContainer/StatsContainer/QualityIndicator")

var network_manager: Node = null
var xr_player: Node = null
var voice_enabled: bool = false
var use_room_code: bool = true


func _ready() -> void:
	network_manager = get_node_or_null("/root/NetworkManager")
	
	if not network_manager:
		push_error("NetworkUI: NetworkManager not found!")
		status_label.text = "ERROR: NetworkManager not found"
		return
	
	# Find XRPlayer
	await get_tree().process_frame
	xr_player = get_tree().get_first_node_in_group("xr_player")
	if not xr_player:
		# Try to find by name
		xr_player = get_tree().root.get_node_or_null("MainScene/XRPlayer")
	
	# Connect UI signals
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)
	voice_button.pressed.connect(_on_voice_pressed)
	avatar_button.pressed.connect(_on_avatar_pressed)
	if use_room_code_check:
		use_room_code_check.toggled.connect(_on_use_room_code_toggled)
	keyboard_button.pressed.connect(_on_keyboard_button_pressed)
	
	# Connect network signals
	network_manager.player_connected.connect(_on_player_connected)
	network_manager.player_disconnected.connect(_on_player_disconnected)
	network_manager.connection_succeeded.connect(_on_connection_succeeded)
	network_manager.connection_failed.connect(_on_connection_failed)
	network_manager.server_disconnected.connect(_on_server_disconnected)
	network_manager.room_code_generated.connect(_on_room_code_generated)
	
	# Set defaults
	address_input.text = "127.0.0.1"
	port_input.text = "7777"
	if room_code_input:
		room_code_input.text = ""
		room_code_input.placeholder_text = "Enter 6-char code"
		room_code_input.max_length = 6
	if use_room_code_check:
		use_room_code_check.button_pressed = true
	disconnect_button.disabled = true
	voice_button.text = "Enable Voice"
	avatar_button.text = "Send Avatar"
	
	# Connect network stats signals if available
	if network_manager:
		network_manager.network_stats_updated.connect(_on_network_stats_updated)
		network_manager.connection_quality_changed.connect(_on_connection_quality_changed)
	
	_update_input_visibility()
	_update_status()
	_update_network_stats_visibility()


func _process(_delta: float) -> void:
	_update_player_list()
	_update_voice_button_text()


func _on_host_pressed() -> void:
	var port = int(port_input.text)
	var error = network_manager.create_server(port, use_room_code)
	
	if error == OK:
		status_label.text = "Creating room..."
		host_button.disabled = true
		join_button.disabled = true
		disconnect_button.disabled = false
		address_input.editable = false
		port_input.editable = false
		if room_code_input:
			room_code_input.editable = false
	else:
		status_label.text = "Failed to host: " + str(error)


func _on_join_pressed() -> void:
	var error: Error
	
	if use_room_code and room_code_input and room_code_input.text.length() == 6:
		# Join by room code using matchmaking
		var code = room_code_input.text.to_upper()
		status_label.text = "Looking up room " + code + "..."
		network_manager.join_by_room_code(code)
		# UI state will be updated by connection callbacks
		host_button.disabled = true
		join_button.disabled = true
		if room_code_input:
			room_code_input.editable = false
	else:
		# Join by IP
		var address = address_input.text
		var port = int(port_input.text)
		error = network_manager.join_server(address, port)
		status_label.text = "Connecting to " + address + ":" + str(port) + "..."
		
		if error == OK:
			host_button.disabled = true
			join_button.disabled = true
			address_input.editable = false
			port_input.editable = false
			if room_code_input:
				room_code_input.editable = false
		else:
			status_label.text = "Failed to connect: " + str(error)


func _on_disconnect_pressed() -> void:
	network_manager.disconnect_from_network()
	status_label.text = "Disconnected"
	host_button.disabled = false
	join_button.disabled = false
	disconnect_button.disabled = true
	address_input.editable = true
	port_input.editable = true


func _on_player_connected(peer_id: int) -> void:
	print("NetworkUI: Player connected: ", peer_id)
	_update_status()


func _on_player_disconnected(peer_id: int) -> void:
	print("NetworkUI: Player disconnected: ", peer_id)
	_update_status()


func _on_connection_succeeded() -> void:
	status_label.text = "Connected to server!"
	disconnect_button.disabled = false


func _on_connection_failed() -> void:
	status_label.text = "Connection failed"
	host_button.disabled = false
	join_button.disabled = false
	address_input.editable = true
	port_input.editable = true


func _on_server_disconnected() -> void:
	status_label.text = "Server disconnected"
	host_button.disabled = false
	join_button.disabled = false
	disconnect_button.disabled = true
	address_input.editable = true
	port_input.editable = true


func _update_status() -> void:
	if not network_manager or not network_manager.peer:
		status_label.text = "Not connected"
		return
	
	if network_manager.is_server():
		status_label.text = "Hosting (ID: " + str(network_manager.get_multiplayer_id()) + ")"
	else:
		status_label.text = "Connected (ID: " + str(network_manager.get_multiplayer_id()) + ")"


func _update_player_list() -> void:
	if not network_manager:
		return
	
	var player_count = network_manager.players.size()
	player_list_label.text = "Players: " + str(player_count)
	
	if player_count > 0:
		player_list_label.text += "\n"
		for peer_id in network_manager.players.keys():
			var marker = " (You)" if peer_id == network_manager.get_multiplayer_id() else ""
			player_list_label.text += "  - Player " + str(peer_id) + marker + "\n"


func _on_voice_pressed() -> void:
	voice_enabled = not voice_enabled
	
	if xr_player and xr_player.has_method("toggle_voice_chat"):
		xr_player.toggle_voice_chat(voice_enabled)
	
	voice_button.text = "Disable Voice" if voice_enabled else "Enable Voice"
	print("NetworkUI: Voice chat ", "enabled" if voice_enabled else "disabled")


func _on_avatar_pressed() -> void:
	if xr_player and xr_player.has_method("send_avatar_texture"):
		xr_player.send_avatar_texture()
		avatar_button.text = "Avatar Sent!"
		await get_tree().create_timer(2.0).timeout
		avatar_button.text = "Send Avatar"
	else:
		print("NetworkUI: XRPlayer not found or doesn't have send_avatar_texture method")


func _on_use_room_code_toggled(enabled: bool) -> void:
	use_room_code = enabled
	_update_input_visibility()


func _update_input_visibility() -> void:
	if not room_code_input or not address_input:
		return
	
	if use_room_code:
		room_code_input.visible = true
		address_input.visible = false
		join_button.text = "Join Room"
		keyboard_button.visible = true
	else:
		room_code_input.visible = false
		address_input.visible = true
		join_button.text = "Join Server"
		keyboard_button.visible = false
func _on_keyboard_button_pressed() -> void:
	if virtual_keyboard:
		virtual_keyboard.queue_free()
		virtual_keyboard = null
		return

	var keyboard_scene = preload("res://src/ui/KeyboardQWERTY.tscn")
	virtual_keyboard = keyboard_scene.instantiate()
	add_child(virtual_keyboard)
	
	# Configure for room code entry
	virtual_keyboard.max_length = 6
	virtual_keyboard.placeholder_text = "Enter 6-char code"
	virtual_keyboard.allow_symbols = false  # Room codes don't use symbols

	# Connect signals
	virtual_keyboard.text_changed.connect(_on_keyboard_text_changed)
	virtual_keyboard.text_submitted.connect(_on_keyboard_text_submitted)

	# Position the keyboard below the entire NetworkUI panel
	# This positions it relative to the room code input but offset downward
	virtual_keyboard.position = Vector2(10, room_code_input.global_position.y + 200)
	
	# Alternative: position it at a fixed location below the UI
	# Uncomment this if you want a fixed position instead
	# virtual_keyboard.position = Vector2(50, 400)


func _on_keyboard_text_changed(text: String) -> void:
	"""Update room code input as user types"""
	if room_code_input:
		# Convert to uppercase for room codes
		var upper_text = text.to_upper()
		if text != upper_text:
			virtual_keyboard.set_text(upper_text)
		else:
			room_code_input.text = upper_text
			room_code_input.set_caret_column(upper_text.length())


func _on_keyboard_text_submitted(code: String) -> void:
	"""Handle Enter key on keyboard"""
	if room_code_input:
		room_code_input.text = code.to_upper()
		room_code_input.set_caret_column(code.length())
	
	# Auto-submit if code is 6 characters
	if code.length() == 6:
		_on_join_pressed()
	
	# Hide keyboard after submission
	if virtual_keyboard:
		virtual_keyboard.queue_free()
		virtual_keyboard = null



func _on_room_code_generated(code: String) -> void:
	if room_code_input:
		room_code_input.text = code
		room_code_input.editable = false
	status_label.text = "Room Code: " + code + " (Share this!)"
	print("NetworkUI: Room code generated: ", code)


# ============================================================================
# Network Stats Display
# ============================================================================

func _update_network_stats_visibility() -> void:
	"""Show/hide network stats based on whether nodes exist"""
	# Stats labels are optional - they may not exist in the scene
	if ping_label:
		ping_label.visible = false
	if bandwidth_label:
		bandwidth_label.visible = false
	if quality_label:
		quality_label.visible = false
	if quality_indicator:
		quality_indicator.visible = false


func _on_network_stats_updated(stats: Dictionary) -> void:
	"""Handle network stats update from NetworkManager"""
	if not network_manager or not network_manager.peer:
		return
	
	# Update ping label
	if ping_label:
		var ping = stats.get("ping_ms", 0.0)
		ping_label.text = "Ping: " + str(int(ping)) + "ms"
		ping_label.visible = true
	
	# Update bandwidth label
	if bandwidth_label:
		var bandwidth_up = stats.get("bandwidth_up", 0.0)
		var bandwidth_down = stats.get("bandwidth_down", 0.0)
		bandwidth_label.text = "↑ %.1f KB/s  ↓ %.1f KB/s" % [bandwidth_up, bandwidth_down]
		bandwidth_label.visible = true
	
	# Update quality label
	if quality_label:
		var quality_str = network_manager.get_connection_quality_string()
		quality_label.text = "Connection: " + quality_str
		quality_label.visible = true
	
	# Update quality indicator color
	if quality_indicator:
		_update_quality_indicator_color(stats.get("connection_quality", 1))


func _on_connection_quality_changed(quality: int) -> void:
	"""Handle connection quality change"""
	_update_quality_indicator_color(quality)
	
	# Show notification for quality changes
	var quality_str = network_manager.get_connection_quality_string() if network_manager else "Unknown"
	
	# Only show warnings for poor/fair quality
	if quality >= 2:  # FAIR or POOR
		print("NetworkUI: Connection quality changed to ", quality_str)


func _update_quality_indicator_color(quality: int) -> void:
	"""Update the color of the quality indicator"""
	if not quality_indicator:
		return
	
	quality_indicator.visible = true
	
	# Color coding: Green = Excellent/Good, Yellow = Fair, Red = Poor
	match quality:
		0:  # EXCELLENT
			quality_indicator.color = Color(0.0, 1.0, 0.0)  # Green
		1:  # GOOD
			quality_indicator.color = Color(0.5, 1.0, 0.0)  # Light green
		2:  # FAIR
			quality_indicator.color = Color(1.0, 1.0, 0.0)  # Yellow
		3:  # POOR
			quality_indicator.color = Color(1.0, 0.0, 0.0)  # Red
		_:
			quality_indicator.color = Color(0.5, 0.5, 0.5)  # Gray (unknown)


func _update_voice_button_text() -> void:
	"""Update voice button text to reflect current mode and state"""
	if not network_manager:
		return
	
	# Update voice button based on mode
	match network_manager.voice_mode:
		0:  # ALWAYS_ON
			voice_button.text = "Voice: Always On" if voice_enabled else "Enable Voice"
		1:  # PUSH_TO_TALK
			if network_manager.is_voice_transmitting():
				voice_button.text = "Voice: TRANSMITTING"
				voice_button.add_theme_color_override("font_color", Color(0.0, 1.0, 0.0))
			else:
				voice_button.text = "Voice: Push to Talk"
				voice_button.remove_theme_color_override("font_color")
		2:  # VOICE_ACTIVATED
			voice_button.text = "Voice: Activated" if voice_enabled else "Enable Voice"
