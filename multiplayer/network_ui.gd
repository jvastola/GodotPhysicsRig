extends Control
## NetworkUI - User interface for hosting and joining multiplayer games

@onready var host_button: Button = $VBoxContainer/HostButton
@onready var join_button: Button = $VBoxContainer/JoinButton
@onready var disconnect_button: Button = $VBoxContainer/DisconnectButton
@onready var address_input: LineEdit = $VBoxContainer/AddressInput
@onready var room_code_input: LineEdit = $VBoxContainer/RoomCodeInput
@onready var port_input: LineEdit = $VBoxContainer/PortInput
@onready var use_room_code_check: CheckButton = $VBoxContainer/UseRoomCodeCheck
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var player_list_label: Label = $VBoxContainer/PlayerListLabel
@onready var voice_button: Button = $VBoxContainer/VoiceButton
@onready var avatar_button: Button = $VBoxContainer/AvatarButton

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
	
	_update_input_visibility()
	_update_status()


func _process(_delta: float) -> void:
	_update_player_list()


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
		# Join by room code
		var code = room_code_input.text.to_upper()
		# For now, room codes are local only (no matchmaking server)
		# In the future, this would query a matchmaking server
		if network_manager.room_code_to_ip.has(code):
			var room_info = network_manager.room_code_to_ip[code]
			error = network_manager.join_server(room_info["ip"], room_info["port"])
			status_label.text = "Joining room " + code + "..."
		else:
			status_label.text = "Room code not found: " + code
			return
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
	else:
		room_code_input.visible = false
		address_input.visible = true
		join_button.text = "Join Server"


func _on_room_code_generated(code: String) -> void:
	if room_code_input:
		room_code_input.text = code
		room_code_input.editable = false
	status_label.text = "Room Code: " + code + " (Share this!)"
	print("NetworkUI: Room code generated: ", code)
