extends PanelContainer

# Debug Console UI - Displays print output and errors in 3D worldspace
# Captures messages via a custom logger

signal console_cleared

@export var max_lines: int = 100
@export var auto_scroll: bool = true
@export var show_timestamps: bool = true
@export var font_size: int = 12

@onready var output_label: RichTextLabel = $MarginContainer/VBoxContainer/ScrollContainer/OutputLabel
@onready var clear_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/ClearButton
@onready var scroll_container: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer
@onready var filter_option: OptionButton = $MarginContainer/VBoxContainer/HBoxContainer/FilterOption
@onready var physics_toggle_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/PhysicsToggleButton
@onready var save_physics_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/SavePhysicsButton
@onready var reset_physics_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/ResetPhysicsButton
@onready var player_exclude_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/PlayerExcludeButton

var _messages: Array[Dictionary] = []
var _filter: int = 0  # 0=All, 1=Info, 2=Warning, 3=Error
var _physics_active: bool = true
var _exclude_player: bool = false
var _kept_nodes_original_modes: Dictionary = {}
var _frozen_body_states: Dictionary = {}
var _saved_body_states: Dictionary = {}

# Message types
enum MessageType { INFO, WARNING, ERROR, SYSTEM }

# Colors for different message types
const TYPE_COLORS = {
	MessageType.INFO: Color(0.9, 0.9, 0.95),
	MessageType.WARNING: Color(1.0, 0.85, 0.3),
	MessageType.ERROR: Color(1.0, 0.4, 0.4),
	MessageType.SYSTEM: Color(0.5, 0.8, 1.0),
}

# Static reference for global access
static var instance: PanelContainer = null


func _ready() -> void:
	instance = self
	
	if clear_button:
		clear_button.pressed.connect(_on_clear_pressed)
	
	if filter_option:
		filter_option.add_item("All", 0)
		filter_option.add_item("Info", 1)
		filter_option.add_item("Warning", 2)
		filter_option.add_item("Error", 3)
		filter_option.item_selected.connect(_on_filter_changed)
	
	if physics_toggle_button:
		# PhysicsServer3D does not expose a getter for active state; assume enabled
		_physics_active = true
		physics_toggle_button.button_pressed = _physics_active
		_update_physics_button_text()
		physics_toggle_button.toggled.connect(_on_physics_toggled)

	if save_physics_button:
		save_physics_button.pressed.connect(_on_save_physics_pressed)
	if reset_physics_button:
		reset_physics_button.pressed.connect(_on_reset_physics_pressed)

	if player_exclude_button:
		player_exclude_button.toggled.connect(_on_player_exclude_toggled)
		_update_player_button_text()
	
	if output_label:
		output_label.bbcode_enabled = true
		output_label.scroll_following = auto_scroll
		output_label.add_theme_font_size_override("normal_font_size", font_size)
	
	# Add startup message
	log_system("Debug Console initialized")
	log_system("Use DebugConsoleUI.log(), log_warning(), log_error() to output messages")


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if instance == self:
			instance = null


## Log an info message
static func log(message: String) -> void:
	if instance:
		instance._add_message(message, MessageType.INFO)
	else:
		print(message)


## Log a warning message
static func log_warning(message: String) -> void:
	if instance:
		instance._add_message(message, MessageType.WARNING)
	else:
		push_warning(message)


## Log an error message
static func log_error(message: String) -> void:
	if instance:
		instance._add_message(message, MessageType.ERROR)
	else:
		push_error(message)


## Log a system message
func log_system(message: String) -> void:
	_add_message(message, MessageType.SYSTEM)


## Add a message to the console
func _add_message(message: String, type: MessageType) -> void:
	var timestamp = Time.get_time_string_from_system()
	
	var msg_data = {
		"text": message,
		"type": type,
		"timestamp": timestamp,
	}
	
	_messages.append(msg_data)
	
	# Trim old messages
	while _messages.size() > max_lines:
		_messages.pop_front()
	
	_refresh_display()


## Refresh the display based on current filter
func _refresh_display() -> void:
	if not output_label:
		return
	
	var bbcode_text = ""
	
	for msg in _messages:
		var type: MessageType = msg["type"]
		
		# Apply filter
		if _filter > 0:
			match _filter:
				1:  # Info only
					if type != MessageType.INFO:
						continue
				2:  # Warning only
					if type != MessageType.WARNING:
						continue
				3:  # Error only
					if type != MessageType.ERROR:
						continue
		
		var color: Color = TYPE_COLORS[type]
		var color_hex = color.to_html(false)
		
		var line = ""
		if show_timestamps:
			line += "[color=#888888][%s][/color] " % msg["timestamp"]
		
		# Add type prefix
		match type:
			MessageType.WARNING:
				line += "[color=#%s]⚠ %s[/color]" % [color_hex, msg["text"]]
			MessageType.ERROR:
				line += "[color=#%s]❌ %s[/color]" % [color_hex, msg["text"]]
			MessageType.SYSTEM:
				line += "[color=#%s]🔧 %s[/color]" % [color_hex, msg["text"]]
			_:
				line += "[color=#%s]%s[/color]" % [color_hex, msg["text"]]
		
		bbcode_text += line + "\n"
	
	output_label.text = bbcode_text
	
	# Auto-scroll to bottom
	if auto_scroll and scroll_container:
		await get_tree().process_frame
		scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value


func _on_clear_pressed() -> void:
	_messages.clear()
	_refresh_display()
	log_system("Console cleared")
	console_cleared.emit()


func _on_filter_changed(index: int) -> void:
	_filter = index
	_refresh_display()


func _on_physics_toggled(pressed: bool) -> void:
	_set_physics_state(pressed)


func _set_physics_active(active: bool) -> void:
	# Keep servers active; manually freeze/unfreeze rigid bodies so simulation truly stops.
	PhysicsServer3D.set_active(true)
	PhysicsServer2D.set_active(true)
	_apply_exclusion_process_modes()
	if active:
		_thaw_bodies()
	else:
		_freeze_bodies()


func _set_physics_state(active: bool) -> void:
	_physics_active = active
	_set_physics_active(active)
	_update_physics_button_text()
	log_system("Physics simulation %s" % ("resumed" if _physics_active else "paused"))


func _update_physics_button_text() -> void:
	if not physics_toggle_button:
		return
	physics_toggle_button.text = "⏸️ Pause Physics" if _physics_active else "▶️ Play Physics"


func _on_player_exclude_toggled(pressed: bool) -> void:
	_exclude_player = pressed
	_update_player_button_text()
	_apply_exclusion_process_modes()
	log_system("Player exclusion %s" % ("enabled" if _exclude_player else "disabled"))


func _apply_exclusion_process_modes() -> void:
	var nodes_always_active: Array = _get_always_active_nodes()
	var nodes_excluded_active: Array = _get_excluded_active_nodes()
	var should_force: bool = not _physics_active
	
	for node in nodes_always_active:
		_set_node_process_mode(node, should_force)
	
	for node in nodes_excluded_active:
		_set_node_process_mode(node, should_force and _exclude_player)

	# If paused, refresh frozen set using latest exclusion rules.
	if not _physics_active:
		_thaw_bodies()
		_freeze_bodies()


func _set_node_process_mode(node: Node, make_always: bool) -> void:
	if node == null:
		return
	if make_always:
		if not _kept_nodes_original_modes.has(node):
			_kept_nodes_original_modes[node] = node.process_mode
		node.process_mode = Node.PROCESS_MODE_ALWAYS
	else:
		if _kept_nodes_original_modes.has(node):
			node.process_mode = _kept_nodes_original_modes[node]
			_kept_nodes_original_modes.erase(node)


func _get_always_active_nodes() -> Array:
	# Keep hands and player roots ticking so hand rays can always click unpause.
	var nodes: Array = []
	nodes.append_array(get_tree().get_nodes_in_group("physics_hand"))
	nodes.append_array(get_tree().get_nodes_in_group("xr_player"))
	nodes.append_array(get_tree().get_nodes_in_group("player"))
	nodes.append_array(_find_hand_pointer_nodes())
	return nodes


func _find_hand_pointer_nodes() -> Array:
	var pointers: Array = []
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return pointers
	var stack: Array = [scene_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node == null:
			continue
		var script = node.get_script()
		if script and str(script.resource_path).ends_with("hand_pointer.gd"):
			pointers.append(node)
		elif "Pointer" in node.name:
			# Fallback name match
			pointers.append(node)
		for child in node.get_children():
			if child:
				stack.append(child)
	return pointers


func _get_rigid_bodies() -> Array:
	var bodies: Array = []
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return bodies
	var stack: Array = [scene_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is RigidBody3D:
			bodies.append(node)
		for child in node.get_children():
			if child:
				stack.append(child)
	return bodies


func _should_skip_freeze(body: RigidBody3D) -> bool:
	if body.is_in_group("physics_hand"):
		return true
	if _exclude_player and (body.is_in_group("player") or body.is_in_group("xr_player")):
		return true
	if _exclude_player and body is TransformTool:
		return true
	return false


func _freeze_bodies() -> void:
	_frozen_body_states.clear()
	for body in _get_rigid_bodies():
		if body == null or _should_skip_freeze(body):
			continue
		_frozen_body_states[body] = {
			"lin": body.linear_velocity,
			"ang": body.angular_velocity,
			"sleep": body.sleeping,
			"freeze": body.freeze,
		}
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.sleeping = true
		body.freeze = true


func _thaw_bodies() -> void:
	for body in _frozen_body_states.keys():
		if not is_instance_valid(body):
			continue
		var state: Dictionary = _frozen_body_states[body]
		# Force wake and unfreeze; then restore recorded velocities.
		body.freeze = false
		body.sleeping = false
		body.linear_velocity = state.get("lin", Vector3.ZERO)
		body.angular_velocity = state.get("ang", Vector3.ZERO)
	_frozen_body_states.clear()


func _on_save_physics_pressed() -> void:
	_saved_body_states.clear()
	for body in _get_rigid_bodies():
		if body == null:
			continue
		_saved_body_states[body] = {
			"transform": body.global_transform,
			"lin": body.linear_velocity,
			"ang": body.angular_velocity,
			"sleep": body.sleeping,
			"freeze": body.freeze,
		}
	log_system("Physics state saved (%s bodies)" % str(_saved_body_states.size()))


func _on_reset_physics_pressed() -> void:
	if _saved_body_states.is_empty():
		log_warning("No saved physics state to restore")
		return
	for body in _saved_body_states.keys():
		if not is_instance_valid(body):
			continue
		var state: Dictionary = _saved_body_states[body]
		body.freeze = false
		body.sleeping = false
		body.global_transform = state.get("transform", body.global_transform)
		body.linear_velocity = state.get("lin", Vector3.ZERO)
		body.angular_velocity = state.get("ang", Vector3.ZERO)
		body.freeze = state.get("freeze", false)
		body.sleeping = state.get("sleep", false)
	log_system("Physics state restored")


func _get_excluded_active_nodes() -> Array:
	# XR player root is in "xr_player" group; child colliders are in "player" group.
	# TransformTool is a Grabbable; keep it active so the player can still use it.
	var nodes: Array = []
	nodes.append_array(get_tree().get_nodes_in_group("xr_player"))
	nodes.append_array(get_tree().get_nodes_in_group("player"))
	for node in get_tree().get_nodes_in_group("grabbable"):
		if node is TransformTool:
			nodes.append(node)
	return nodes


func _update_player_button_text() -> void:
	if not player_exclude_button:
		return
	player_exclude_button.text = "🙋 Exclude Player" if _exclude_player else "🙋 Include Player"


func _unhandled_input(event: InputEvent) -> void:
	# Fallback: allow toggling via common actions even if pointer click is blocked.
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		if not physics_toggle_button:
			return
		physics_toggle_button.button_pressed = not _physics_active
		_on_physics_toggled(physics_toggle_button.button_pressed)


## Clear all messages
func clear() -> void:
	_messages.clear()
	_refresh_display()


## Get message count
func get_message_count() -> int:
	return _messages.size()
