extends Control
## NetworkUI - User interface for hosting and joining multiplayer games

@onready var host_button: Button = $Panel/VBoxContainer/ButtonsContainer/HostButton
@onready var join_button: Button = $Panel/VBoxContainer/ButtonsContainer/JoinButton
@onready var disconnect_button: Button = $Panel/VBoxContainer/DisconnectButton
@onready var address_input: LineEdit = get_node_or_null("Panel/VBoxContainer/AddressInput")
@onready var room_code_input: LineEdit = $Panel/VBoxContainer/RoomCodeInput
@onready var port_input: LineEdit = $Panel/VBoxContainer/PortInput
@onready var use_room_code_check: CheckButton = get_node_or_null("Panel/VBoxContainer/UseRoomCodeCheck")
@onready var keyboard_button: Button = $Panel/VBoxContainer/KeyboardButton

var virtual_keyboard: Node = null
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel
@onready var player_list_label: Label = $Panel/VBoxContainer/PlayerListLabel
@onready var voice_button: Button = $Panel/VBoxContainer/FeaturesContainer/VoiceButton
@onready var avatar_button: Button = $Panel/VBoxContainer/FeaturesContainer/AvatarButton

# Room browser
@onready var refresh_button: Button = $Panel/VBoxContainer/RoomListHeaderContainer/RefreshButton
@onready var room_list_vbox: VBoxContainer = $Panel/VBoxContainer/RoomListScroll/RoomListVBox
var room_refresh_timer: float = 0.0
const ROOM_REFRESH_INTERVAL: float = 5.0

# Network stats labels (optional nodes - may not exist in scene yet)
@onready var ping_label: Label = get_node_or_null("Panel/VBoxContainer/StatsContainer/PingLabel")
@onready var bandwidth_label: Label = get_node_or_null("Panel/VBoxContainer/StatsContainer/BandwidthLabel")
@onready var quality_label: Label = get_node_or_null("Panel/VBoxContainer/StatsContainer/QualityLabel")
@onready var quality_indicator: ColorRect = get_node_or_null("Panel/VBoxContainer/StatsContainer/QualityIndicator")

var network_manager: Node = null
var nakama_manager: Node = null
var xr_player: Node = null
var voice_enabled: bool = false
var is_nakama_authenticated: bool = false


func _ready() -> void:
	network_manager = get_node_or_null("/root/NetworkManager")
	nakama_manager = get_node_or_null("/root/NakamaManager")
	
	if not network_manager:
		push_error("NetworkUI: NetworkManager not found!")
		status_label.text = "ERROR: NetworkManager not found"
		return
	
	if not nakama_manager:
		push_error("NetworkUI: NakamaManager not found!")
		status_label.text = "ERROR: NakamaManager not found"
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
	keyboard_button.pressed.connect(_on_keyboard_button_pressed)
	refresh_button.pressed.connect(_on_refresh_rooms_pressed)
	
	# Connect network signals
	network_manager.player_connected.connect(_on_player_connected)
	network_manager.player_disconnected.connect(_on_player_disconnected)
	network_manager.connection_succeeded.connect(_on_connection_succeeded)
	network_manager.connection_failed.connect(_on_connection_failed)
	network_manager.server_disconnected.connect(_on_server_disconnected)
	network_manager.room_code_generated.connect(_on_room_code_generated)
	
	# Connect Nakama signals
	nakama_manager.authenticated.connect(_on_nakama_authenticated)
	nakama_manager.authentication_failed.connect(_on_nakama_auth_failed)
	nakama_manager.match_created.connect(_on_nakama_match_created)
	nakama_manager.match_joined.connect(_on_nakama_match_joined)
	nakama_manager.match_error.connect(_on_nakama_match_error)
	nakama_manager.match_list_received.connect(_on_nakama_match_list_received)
	
	# Set defaults
	port_input.text = "7777"
	if room_code_input:
		room_code_input.text = ""
		room_code_input.placeholder_text = "Match ID"
		room_code_input.max_length = 64  # Nakama match IDs are 37 chars (UUID + '.')
	
	# Disable buttons until authenticated
	host_button.disabled = true
	join_button.disabled = true
	disconnect_button.disabled = true
	voice_button.text = "Enable Voice"
	avatar_button.text = "Send Avatar"
	
	status_label.text = "Authenticating with Nakama..."
	
	# Connect network stats signals if available
	if network_manager:
		network_manager.network_stats_updated.connect(_on_network_stats_updated)
		network_manager.connection_quality_changed.connect(_on_connection_quality_changed)
	
	_update_status()
	_update_network_stats_visibility()
	
	# Start Nakama authentication
	nakama_manager.authenticate_device()


func _process(_delta: float) -> void:
	_update_player_list()
	_update_voice_button_text()
	
	# Auto-refresh room list when authenticated, socket connected, but not in a match
	if is_nakama_authenticated and nakama_manager.is_socket_connected and not network_manager.use_nakama:
		room_refresh_timer += _delta
		if room_refresh_timer >= ROOM_REFRESH_INTERVAL:
			room_refresh_timer = 0.0
			nakama_manager.list_matches()


func _on_host_pressed() -> void:
	if not is_nakama_authenticated:
		status_label.text = "Not authenticated. Please wait..."
		return
	
	status_label.text = "Creating Nakama match..."
	host_button.disabled = true
	join_button.disabled = true
	
	# Create match via Nakama
	nakama_manager.create_match()


func _on_join_pressed() -> void:
	if not is_nakama_authenticated:
		status_label.text = "Not authenticated. Please wait..."
		return
	
	var match_code = room_code_input.text.strip_edges()
	print("NetworkUI: _on_join_pressed - match_code from input: '", match_code, "' (length: ", match_code.length(), ")")
	
	if match_code.is_empty():
		status_label.text = "Enter match ID"
		return
	
	# Disable UI during connection
	host_button.disabled = true
	join_button.disabled = true
	room_code_input.editable = false
	
	status_label.text = "Joining match..."
	print("NetworkUI: Calling nakama_manager.join_match with: '", match_code, "'")
	nakama_manager.join_match(match_code)


func _on_disconnect_pressed() -> void:
	nakama_manager.leave_match()
	network_manager.use_nakama = false
	status_label.text = "Disconnected"
	host_button.disabled = false
	join_button.disabled = false
	disconnect_button.disabled = true
	if room_code_input:
		room_code_input.text = ""
		room_code_input.editable = true


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

	port_input.editable = true


func _on_server_disconnected() -> void:
	status_label.text = "Server disconnected"
	host_button.disabled = false
	join_button.disabled = false
	disconnect_button.disabled = true

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
			# Support both int (ENet) and String (Nakama) peer IDs
			var is_local = false
			if network_manager.use_nakama:
				is_local = (str(peer_id) == network_manager.get_nakama_user_id())
			else:
				is_local = (str(peer_id) == str(network_manager.get_multiplayer_id()))
			
			var marker = " (You)" if is_local else ""
			var display_id = str(peer_id).substr(0, 8) if peer_id is String else str(peer_id)
			player_list_label.text += "  - Player " + display_id + marker + "\n"


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
# Nakama Signal Handlers
# ============================================================================

func _on_nakama_authenticated(session: Dictionary) -> void:
	print("NetworkUI: Nakama authenticated")
	is_nakama_authenticated = true
	status_label.text = "Ready to connect"
	host_button.disabled = false
	join_button.disabled = false


func _on_nakama_auth_failed(error: String) -> void:
	push_error("NetworkUI: Nakama authentication failed: ", error)
	status_label.text = "Auth failed: " + error
	host_button.disabled = true
	join_button.disabled = true


func _on_nakama_match_created(match_id: String, match_label: String) -> void:
	print("NetworkUI: Match created: ", match_id)
	status_label.text = "Match Created!"
	
	# Display match ID in room code input (read-only)
	if room_code_input:
		room_code_input.text = match_id
		room_code_input.editable = false
	
	# Enable disconnect button
	disconnect_button.disabled = false
	
	# Set NetworkManager to use Nakama
	network_manager.use_nakama = true


func _on_nakama_match_joined(match_id: String) -> void:
	print("NetworkUI: Joined match: ", match_id)
	status_label.text = "Connected to match"
	disconnect_button.disabled = false
	
	# Set NetworkManager to use Nakama
	network_manager.use_nakama = true


func _on_nakama_match_error(error: Variant) -> void:
	push_error("NetworkUI: Match error: ", error)
	status_label.text = "Match error: " + str(error)
	host_button.disabled = false
	join_button.disabled = false
	if room_code_input:
		room_code_input.editable = true


# ============================================================================
# Room Browser
# ============================================================================

func _on_refresh_rooms_pressed() -> void:
	"""Refresh the room list"""
	if nakama_manager and is_nakama_authenticated and nakama_manager.is_socket_connected:
		nakama_manager.list_matches()
		status_label.text = "Refreshing rooms..."
	elif not nakama_manager.is_socket_connected:
		status_label.text = "Connecting to server..."


func _on_nakama_match_list_received(matches: Array) -> void:
	"""Update UI with available matches"""
	# Clear existing list
	for child in room_list_vbox.get_children():
		child.queue_free()
	
	if matches.is_empty():
		var label = Label.new()
		label.text = "No rooms available"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 1))
		label.add_theme_font_size_override("font_size", 12)
		room_list_vbox.add_child(label)
		return
	
	# Create entry for each match
	for match_data in matches:
		var match_id = match_data.get("match_id", "")
		var size = match_data.get("size", 0)
		
		if match_id.is_empty():
			continue
		
		var entry = HBoxContainer.new()
		entry.add_theme_constant_override("separation", 10)
		
		var label = Label.new()
		label.text = "🎮 " + match_id.substr(0, 8) + "... (" + str(size) + " player" + ("s" if size != 1 else "") + ")"
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.85, 0.9, 1, 1))
		entry.add_child(label)
		
		var join_btn = Button.new()
		join_btn.text = "Join"
		join_btn.add_theme_color_override("font_color", Color(0.4, 0.8, 1, 1))
		join_btn.add_theme_font_size_override("font_size", 12)
		join_btn.pressed.connect(_join_room_from_list.bind(match_id))
		entry.add_child(join_btn)
		
		room_list_vbox.add_child(entry)


func _join_room_from_list(match_id: String) -> void:
	"""Join a match from the room list"""
	print("NetworkUI: _join_room_from_list called with match_id: '", match_id, "' (length: ", match_id.length(), ")")
	print("NetworkUI: RoomCodeInput max_length before: ", room_code_input.max_length)
	room_code_input.text = match_id
	print("NetworkUI: RoomCodeInput.text after assignment: '", room_code_input.text, "' (length: ", room_code_input.text.length(), ")")
	_on_join_pressed()


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
