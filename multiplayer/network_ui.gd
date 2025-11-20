extends Control
## NetworkUI - User interface for hosting and joining multiplayer games

@onready var host_button: Button = $VBoxContainer/HostButton
@onready var join_button: Button = $VBoxContainer/JoinButton
@onready var disconnect_button: Button = $VBoxContainer/DisconnectButton
@onready var address_input: LineEdit = $VBoxContainer/AddressInput
@onready var port_input: LineEdit = $VBoxContainer/PortInput
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var player_list_label: Label = $VBoxContainer/PlayerListLabel

var network_manager: Node = null


func _ready() -> void:
	network_manager = get_node_or_null("/root/NetworkManager")
	
	if not network_manager:
		push_error("NetworkUI: NetworkManager not found!")
		status_label.text = "ERROR: NetworkManager not found"
		return
	
	# Connect UI signals
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)
	
	# Connect network signals
	network_manager.player_connected.connect(_on_player_connected)
	network_manager.player_disconnected.connect(_on_player_disconnected)
	network_manager.connection_succeeded.connect(_on_connection_succeeded)
	network_manager.connection_failed.connect(_on_connection_failed)
	network_manager.server_disconnected.connect(_on_server_disconnected)
	
	# Set defaults
	address_input.text = "127.0.0.1"
	port_input.text = "7777"
	disconnect_button.disabled = true
	
	_update_status()


func _process(_delta: float) -> void:
	_update_player_list()


func _on_host_pressed() -> void:
	var port = int(port_input.text)
	var error = network_manager.create_server(port)
	
	if error == OK:
		status_label.text = "Hosting on port " + str(port)
		host_button.disabled = true
		join_button.disabled = true
		disconnect_button.disabled = false
		address_input.editable = false
		port_input.editable = false
	else:
		status_label.text = "Failed to host: " + str(error)


func _on_join_pressed() -> void:
	var address = address_input.text
	var port = int(port_input.text)
	var error = network_manager.join_server(address, port)
	
	if error == OK:
		status_label.text = "Connecting to " + address + ":" + str(port) + "..."
		host_button.disabled = true
		join_button.disabled = true
		address_input.editable = false
		port_input.editable = false
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
