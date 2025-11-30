extends Control
## UnifiedRoomUI - Combined Nakama room browsing with automatic LiveKit voice chat

# UI References
@onready var current_room_panel = $VBox/CurrentRoomPanel
@onready var room_name_label = $VBox/CurrentRoomPanel/HBox/RoomNameLabel
@onready var player_count_label = $VBox/CurrentRoomPanel/HBox/PlayerCountLabel
@onready var leave_button = $VBox/CurrentRoomPanel/HBox/LeaveButton
@onready var status_label = $VBox/StatusLabel
@onready var refresh_button = $VBox/AvailableRoomsHeader/RefreshButton
@onready var create_room_button = $VBox/AvailableRoomsHeader/CreateRoomButton
@onready var room_list_container = $VBox/RoomListScroll/RoomListContainer

# Manager references
var nakama_manager: Node = null
var network_manager: Node = null
var livekit_manager: Node = null

# State
var current_match_id: String = ""
var current_room_name: String = ""
var available_rooms: Array = []
var is_connecting: bool = false


func _ready() -> void:
	print("=== Unified Room UI ===")
	
	# Get manager references
	nakama_manager = get_node_or_null("/root/NakamaManager")
	network_manager = get_node_or_null("/root/NetworkManager")
	
	# Get LiveKit manager - it might be created by livekit_ui.gd
	livekit_manager = _find_livekit_manager()
	
	if not nakama_manager:
		status_label.text = "❌ Error: NakamaManager not found"
		push_error("UnifiedRoomUI: NakamaManager not found")
		return
	
	if not network_manager:
		status_label.text = "❌ Error: NetworkManager not found"
		push_error("UnifiedRoomUI: NetworkManager not found")
		return
	
	# Connect signals
	_connect_signals()
	
	# Connect UI signals
	leave_button.pressed.connect(_on_leave_button_pressed)
	refresh_button.pressed.connect(_on_refresh_button_pressed)
	create_room_button.pressed.connect(_on_create_room_button_pressed)
	
	# Initial state
	current_room_panel.visible = false
	status_label.text = "⏳ Connecting to Nakama..."
	
	# Auto-authenticate with Nakama
	if not nakama_manager.is_authenticated:
		nakama_manager.authenticate_device()
	else:
		status_label.text = "✅ Connected - Click Refresh to see rooms"
		_refresh_room_list()
	
	# Auto-refresh room list
	_refresh_room_list()
	
	print("✅ Unified Room UI Ready!")


func _find_livekit_manager() -> Node:
	"""Find LiveKit manager in the scene tree"""
	# Check if it exists as an autoload
	var lk = get_node_or_null("/root/LiveKitManager")
	if lk:
		return lk
	
	# Search for LiveKitManager class instances
	var root = get_tree().root
	return _search_for_livekit(root)


func _search_for_livekit(node: Node) -> Node:
	"""Recursively search for LiveKitManager instance"""
	if node.get_class() == "LiveKitManager" or node.name == "LiveKitManager":
		return node
	
	for child in node.get_children():
		var found = _search_for_livekit(child)
		if found:
			return found
	
	return null


func _connect_signals() -> void:
	"""Connect to Nakama manager signals"""
	if nakama_manager.authenticated.is_connected(_on_nakama_authenticated):
		nakama_manager.authenticated.disconnect(_on_nakama_authenticated)
	nakama_manager.authenticated.connect(_on_nakama_authenticated)
	
	if nakama_manager.match_joined.is_connected(_on_match_joined):
		nakama_manager.match_joined.disconnect(_on_match_joined)
	nakama_manager.match_joined.connect(_on_match_joined)
	
	if nakama_manager.match_left.is_connected(_on_match_left):
		nakama_manager.match_left.disconnect(_on_match_left)
	nakama_manager.match_left.connect(_on_match_left)
	
	if nakama_manager.match_list_received.is_connected(_on_match_list_received):
		nakama_manager.match_list_received.disconnect(_on_match_list_received)
	nakama_manager.match_list_received.connect(_on_match_list_received)
	
	if nakama_manager.match_presence.is_connected(_on_match_presence):
		nakama_manager.match_presence.disconnect(_on_match_presence)
	nakama_manager.match_presence.connect(_on_match_presence)


func _on_nakama_authenticated(_session: Dictionary) -> void:
	"""Handle Nakama authentication"""
	print("UnifiedRoomUI: Nakama authenticated")
	status_label.text = "✅ Connected to Nakama"
	_refresh_room_list()


func _on_refresh_button_pressed() -> void:
	"""Refresh the room list"""
	_refresh_room_list()


func _on_create_room_button_pressed() -> void:
	"""Create a new room"""
	if is_connecting:
		return
	
	status_label.text = "⏳ Creating room..."
	is_connecting = true
	
	# Create match via Nakama
	nakama_manager.create_match()


func _refresh_room_list() -> void:
	"""Fetch available rooms from Nakama"""
	if not nakama_manager or not nakama_manager.is_authenticated:
		status_label.text = "⚠️ Not connected to Nakama"
		return
	
	status_label.text = "⏳ Refreshing room list..."
	nakama_manager.list_matches()


func _on_match_list_received(matches: Array) -> void:
	"""Handle received match list from Nakama"""
	available_rooms = matches
	_update_room_list_ui()
	
	if matches.size() == 0:
		status_label.text = "No rooms available - Create one!"
	else:
		status_label.text = "Found %d room(s)" % matches.size()


func _update_room_list_ui() -> void:
	"""Update the UI with available rooms"""
	# Clear existing room items
	for child in room_list_container.get_children():
		child.queue_free()
	
	# Add room items
	for match_data in available_rooms:
		var match_id = match_data.get("match_id", "")
		var label = match_data.get("label", match_id)
		var size = match_data.get("size", 0)
		
		# Skip if this is our current room
		if match_id == current_match_id:
			continue
		
		_create_room_list_item(match_id, label, size)


func _create_room_list_item(match_id: String, room_name: String, player_count: int) -> void:
	"""Create a room list item UI element"""
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.17, 0.22)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	panel.add_child(hbox)
	
	# Room name
	var name_label = Label.new()
	name_label.text = room_name if room_name else match_id.substr(0, 8)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 28)
	hbox.add_child(name_label)
	
	# Player count
	var count_label = Label.new()
	count_label.text = "👥 %d" % player_count
	count_label.add_theme_font_size_override("font_size", 24)
	count_label.modulate = Color(0.7, 0.7, 0.7)
	hbox.add_child(count_label)
	
	# Join button
	var join_btn = Button.new()
	join_btn.text = "Join"
	join_btn.custom_minimum_size = Vector2(120, 50)
	join_btn.add_theme_font_size_override("font_size", 22)
	join_btn.pressed.connect(_on_join_room.bind(match_id, room_name))
	hbox.add_child(join_btn)
	
	room_list_container.add_child(panel)


func _on_join_room(match_id: String, room_name: String) -> void:
	"""Join a Nakama room and auto-connect to LiveKit"""
	if is_connecting:
		return
	
	print("UnifiedRoomUI: Joining room: ", match_id, " (", room_name, ")")
	status_label.text = "⏳ Joining room..."
	is_connecting = true
	
	# Store room info
	current_match_id = match_id
	current_room_name = room_name if room_name else match_id
	
	# Join Nakama match
	nakama_manager.join_match(match_id)


func _on_match_joined(match_id: String) -> void:
	"""Handle successful match join"""
	print("UnifiedRoomUI: Joined match: ", match_id)
	is_connecting = false
	current_match_id = match_id
	
	# Update UI
	current_room_panel.visible = true
	room_name_label.text = "Room: " + current_room_name
	player_count_label.text = "👥 1"  # Will be updated by presence events
	status_label.text = "✅ Joined room"
	
	# Auto-connect to LiveKit
	_auto_connect_livekit(current_room_name)
	
	# Refresh room list to remove current room
	_refresh_room_list()


func _on_match_presence(joins: Array, leaves: Array) -> void:
	"""Handle player join/leave events"""
	# Update player count
	var total_players = nakama_manager.match_peers.size() + 1  # +1 for self
	player_count_label.text = "👥 %d" % total_players
	
	# Log events
	for join in joins:
		var user_id = join.get("user_id", "")
		if user_id != nakama_manager.local_user_id:
			print("UnifiedRoomUI: Player joined: ", user_id)
	
	for leave in leaves:
		var user_id = leave.get("user_id", "")
		if user_id != nakama_manager.local_user_id:
			print("UnifiedRoomUI: Player left: ", user_id)


func _auto_connect_livekit(room_name: String) -> void:
	"""Automatically connect to LiveKit for this room"""
	# Get or create LiveKit manager
	if not livekit_manager:
		livekit_manager = _find_livekit_manager()
	
	if not livekit_manager:
		push_warning("UnifiedRoomUI: LiveKit manager not found - voice chat unavailable")
		status_label.text += " (No voice)"
		return
	
	# Get Nakama user ID for LiveKit participant identity
	var nakama_id = nakama_manager.local_user_id
	if nakama_id.is_empty():
		push_warning("UnifiedRoomUI: No Nakama user ID - cannot connect to LiveKit")
		return
	
	# Generate LiveKit token
	var token = _generate_livekit_token(nakama_id, room_name)
	
	# Connect to LiveKit
	var server_url = "ws://localhost:7880"  # Default local LiveKit server
	
	print("UnifiedRoomUI: Auto-connecting to LiveKit room: ", room_name)
	livekit_manager.connect_to_room(server_url, token)
	
	status_label.text = "✅ Joined room with voice chat"


func _on_leave_button_pressed() -> void:
	"""Leave current room (both Nakama and LiveKit)"""
	_leave_room()


func _leave_room() -> void:
	"""Leave current room and disconnect from LiveKit"""
	print("UnifiedRoomUI: Leaving room")
	
	# Disconnect from LiveKit first
	_disconnect_livekit()
	
	# Leave Nakama match
	if nakama_manager:
		nakama_manager.leave_match()
	
	# Clear state
	current_match_id = ""
	current_room_name = ""
	
	# Update UI
	current_room_panel.visible = false
	status_label.text = "Left room"
	
	# Refresh room list
	_refresh_room_list()


func _on_match_left() -> void:
	"""Handle match left event from Nakama"""
	print("UnifiedRoomUI: Match left event")
	current_room_panel.visible = false
	_refresh_room_list()


func _disconnect_livekit() -> void:
	"""Disconnect from LiveKit"""
	if livekit_manager and livekit_manager.has_method("disconnect_from_room"):
		print("UnifiedRoomUI: Disconnecting from LiveKit")
		livekit_manager.disconnect_from_room()


func _generate_livekit_token(participant_id: String, room_name: String) -> String:
	"""Generate a LiveKit JWT access token using HS256"""
	# LiveKit credentials (must match server config)
	const API_KEY = "devkey"
	const API_SECRET = "secret"
	const TOKEN_VALIDITY_HOURS = 24
	
	# Current time
	var now = Time.get_unix_time_from_system()
	var exp = now + (TOKEN_VALIDITY_HOURS * 3600)
	
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
