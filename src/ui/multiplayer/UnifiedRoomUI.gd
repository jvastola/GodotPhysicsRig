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
var _is_refreshing_list: bool = false  # Debounce flag for match list refresh

# Connection info labels
var nakama_info_label: Label = null
var livekit_info_label: Label = null


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
	
	# Create connection info labels
	_create_connection_info_labels()
	
	# Auto-authenticate with Nakama
	if not nakama_manager.is_authenticated:
		nakama_manager.authenticate_device()
	else:
		status_label.text = "✅ Connected - Click Refresh to see rooms"
		_refresh_room_list()
	
	# Auto-refresh room list
	_refresh_room_list()
	
	# Update connection info
	_update_connection_info()
	
	print("✅ Unified Room UI Ready!")


func _find_livekit_manager() -> Node:
	"""Find LiveKit manager in the scene tree"""
	# Check for LiveKitWrapper first (Android/unified wrapper)
	var lk = get_node_or_null("/root/LiveKitWrapper")
	if lk:
		print("UnifiedRoomUI: Found LiveKitWrapper autoload")
		return lk
	
	# Check for LiveKitManager (Desktop Rust GDExtension)
	lk = get_node_or_null("/root/LiveKitManager")
	if lk:
		print("UnifiedRoomUI: Found LiveKitManager autoload")
		return lk
	
	# Search for LiveKitManager class instances
	print("UnifiedRoomUI: No autoload found, searching scene tree...")
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
	
	if nakama_manager.match_created.is_connected(_on_match_created):
		nakama_manager.match_created.disconnect(_on_match_created)
	nakama_manager.match_created.connect(_on_match_created)
	
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
	
	# Connect to LiveKit signals if manager exists
	if livekit_manager:
		if livekit_manager.has_signal("room_connected"):
			if livekit_manager.room_connected.is_connected(_on_livekit_connected):
				livekit_manager.room_connected.disconnect(_on_livekit_connected)
			livekit_manager.room_connected.connect(_on_livekit_connected)
			
		if livekit_manager.has_signal("room_disconnected"):
			if livekit_manager.room_disconnected.is_connected(_on_livekit_disconnected):
				livekit_manager.room_disconnected.disconnect(_on_livekit_disconnected)
			livekit_manager.room_disconnected.connect(_on_livekit_disconnected)


func _on_nakama_authenticated(_session: Dictionary) -> void:
	"""Handle Nakama authentication"""
	print("UnifiedRoomUI: Nakama authenticated")
	status_label.text = "✅ Connected to Nakama"
	_update_connection_info()
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
	# Debounce: Skip if already refreshing to prevent concurrent requests
	# This prevents crashes on Android when leaving a match triggers multiple refreshes
	if _is_refreshing_list:
		print("UnifiedRoomUI: Skipping refresh - already in progress")
		return
	
	if not nakama_manager or not nakama_manager.is_authenticated:
		status_label.text = "⚠️ Not connected to Nakama"
		return
	
	_is_refreshing_list = true
	status_label.text = "⏳ Refreshing room list..."
	nakama_manager.list_matches()


func _on_match_list_received(matches: Array) -> void:
	"""Handle received match list from Nakama"""
	_is_refreshing_list = false  # Reset debounce flag
	
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
		var player_count = match_data.get("size", 0)
		
		# Skip if this is our current room
		if match_id == current_match_id:
			continue
		
		_create_room_list_item(match_id, label, player_count)


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


func _on_match_created(match_id: String, match_label: String) -> void:
	"""Handle successful match creation"""
	print("UnifiedRoomUI: Created match: ", match_id, " (", match_label, ")")
	is_connecting = false
	current_match_id = match_id
	current_room_name = match_label if match_label else match_id
	
	# Update UI
	current_room_panel.visible = true
	room_name_label.text = "Room: " + current_room_name
	player_count_label.text = "👥 1"  # Will be updated by presence events
	status_label.text = "✅ Created room"
	
	# Auto-connect to LiveKit
	_auto_connect_livekit(current_room_name)
	
	# Update connection info
	_update_connection_info()
	
	# Refresh room list to remove current room
	_refresh_room_list()
	# Update player count
	var total_players = nakama_manager.match_peers.size() + 1  # +1 for self
	player_count_label.text = "👥 %d" % total_players
	



func _on_match_joined(match_id: String) -> void:
	"""Handle successful match join"""
	print("UnifiedRoomUI: Joined match: ", match_id)
	
	# If we just created this match, we already handled connection in _on_match_created
	if match_id == current_match_id and not is_connecting:
		print("UnifiedRoomUI: Already connected to this match (via creation)")
		return
		
	is_connecting = false
	current_match_id = match_id
	
	# Update UI
	current_room_panel.visible = true
	room_name_label.text = "Room: " + current_room_name
	player_count_label.text = "👥 1"  # Will be updated by presence events
	status_label.text = "✅ Joined room"
	
	# Auto-connect to LiveKit
	_auto_connect_livekit(current_room_name)
	
	# Update connection info
	_update_connection_info()
	
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
	print("UnifiedRoomUI: _auto_connect_livekit called with room: ", room_name)
	
	# Get or create LiveKit manager
	if not livekit_manager:
		print("UnifiedRoomUI: LiveKit manager not found, searching...")
		livekit_manager = _find_livekit_manager()
		# If found now, connect signals
		if livekit_manager:
			_connect_signals()
	
	if not livekit_manager:
		push_warning("UnifiedRoomUI: LiveKit manager not found - voice chat unavailable")
		status_label.text += " (No voice)"
		print("❌ UnifiedRoomUI: Could not find LiveKit manager!")
		return
	
	print("UnifiedRoomUI: Found LiveKit manager: ", livekit_manager)
	
	# Get Nakama user ID for LiveKit participant identity
	var nakama_id = nakama_manager.local_user_id
	print("UnifiedRoomUI: Nakama user ID: ", nakama_id)
	
	if nakama_id.is_empty():
		push_warning("UnifiedRoomUI: No Nakama user ID - cannot connect to LiveKit")
		print("❌ UnifiedRoomUI: Nakama user ID is empty!")
		return
	
	# Sanitize room name (remove trailing dot if present)
	var clean_room_name = room_name
	if clean_room_name.ends_with("."):
		clean_room_name = clean_room_name.substr(0, clean_room_name.length() - 1)
		print("UnifiedRoomUI: Sanitized room name from '", room_name, "' to '", clean_room_name, "'")
	
	# Generate LiveKit token
	print("UnifiedRoomUI: Generating LiveKit token...")
	var token = _generate_livekit_token(nakama_id, clean_room_name)
	print("UnifiedRoomUI: Token generated (length: ", token.length(), ")")
	
	# Connect to LiveKit
	var server_url = "wss://godotkit-mjbmdjse.livekit.cloud"
	
	print("UnifiedRoomUI: Auto-connecting to LiveKit room: ", room_name)
	print("UnifiedRoomUI: Server URL: ", server_url)
	livekit_manager.connect_to_room(server_url, token)
	print("✅ UnifiedRoomUI: Called connect_to_room on LiveKit manager")
	
	# Update LiveKit UI with room name
	_update_livekit_ui_room_name(clean_room_name)
	
	status_label.text = "✅ Joined room with voice chat"


func _on_livekit_connected() -> void:
	"""Handle LiveKit connection success"""
	print("UnifiedRoomUI: ✅ Successfully connected to LiveKit!")
	_update_connection_info()


func _on_livekit_disconnected() -> void:
	"""Handle LiveKit disconnection"""
	print("UnifiedRoomUI: ❌ Disconnected from LiveKit")
	_update_connection_info()


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
	
	# Update connection info
	_update_connection_info()
	
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
		"exp": expire_time,
		"iss": API_KEY,
		"nbf": now - 60,  # Allow for 1 minute clock skew
		"sub": participant_id,  # CRITICAL: This must match Nakama user_id
		"video": {
			"room": room_name,
			"roomJoin": true,
			"canPublish": true,
			"canSubscribe": true,
			"canUpdateOwnMetadata": true
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


func _update_livekit_ui_room_name(room_name: String) -> void:
	"""Update the LiveKit UI to show the current room name"""
	# Find LiveKit UI in the scene tree
	var livekit_ui = _find_livekit_ui()
	if livekit_ui and livekit_ui.has_method("set"):
		# Set the room name property
		livekit_ui.current_room_name = room_name
		# Trigger update if method exists
		if livekit_ui.has_method("_update_room_name_label"):
			livekit_ui._update_room_name_label()
		print("UnifiedRoomUI: Updated LiveKit UI with room name: ", room_name)


func _find_livekit_ui() -> Node:
	"""Find the LiveKit UI node in the scene tree"""
	var root = get_tree().root
	return _search_for_livekit_ui(root)


func _search_for_livekit_ui(node: Node) -> Node:
	"""Recursively search for LiveKit UI instance"""
	if node.get_script():
		var script_path = node.get_script().resource_path
		if "livekit_ui" in script_path.to_lower():
			return node
	
	for child in node.get_children():
		var found = _search_for_livekit_ui(child)
		if found:
			return found
	
	return null


func _create_connection_info_labels() -> void:
	"""Create labels to display connection information"""
	var vbox = $VBox
	
	# Create a container for connection info (below status label, before separator)
	var info_container = VBoxContainer.new()
	info_container.name = "ConnectionInfoContainer"
	info_container.add_theme_constant_override("separation", 5)
	
	# Nakama connection info
	nakama_info_label = Label.new()
	nakama_info_label.name = "NakamaInfoLabel"
	nakama_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nakama_info_label.add_theme_font_size_override("font_size", 16)
	nakama_info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	nakama_info_label.text = "Nakama: Connecting..."
	info_container.add_child(nakama_info_label)
	
	# LiveKit connection info
	livekit_info_label = Label.new()
	livekit_info_label.name = "LiveKitInfoLabel"
	livekit_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	livekit_info_label.add_theme_font_size_override("font_size", 16)
	livekit_info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	livekit_info_label.text = "LiveKit: Not connected"
	info_container.add_child(livekit_info_label)
	
	# Add container to VBox (after StatusLabel, before first HSeparator)
	vbox.add_child(info_container)
	vbox.move_child(info_container, 2)  # After Title and StatusLabel
	
	print("✅ Created connection info labels")


func _update_connection_info() -> void:
	"""Update the connection info labels with current status"""
	if not nakama_info_label or not livekit_info_label:
		return
	
	# Update Nakama info
	if nakama_manager:
		if nakama_manager.is_authenticated:
			var nakama_host = nakama_manager.nakama_host
			var nakama_port = nakama_manager.nakama_port
			nakama_info_label.text = "🟢 Nakama: %s:%d" % [nakama_host, nakama_port]
			nakama_info_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))  # Green
		else:
			nakama_info_label.text = "🔴 Nakama: Not connected"
			nakama_info_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))  # Red
	
	# Update LiveKit info
	if livekit_manager:
		if livekit_manager.has_method("is_room_connected") and livekit_manager.is_room_connected():
			var room_display = current_room_name if not current_room_name.is_empty() else "Unknown"
			livekit_info_label.text = "🟢 LiveKit: Cloud Connected (Room: %s)" % room_display
			livekit_info_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))  # Green
		else:
			livekit_info_label.text = "🔴 LiveKit: Not connected"
			livekit_info_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))  # Red
	else:
		livekit_info_label.text = "⚠️ LiveKit: Manager not found"
		livekit_info_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))  # Yellow
