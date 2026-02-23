extends Node3D

const BOX_SCENE_PATH := "res://src/test/Phase2OwnedBlock3D.tscn"
const FIXED_Z := 0.0

@onready var status_label: Label = $CanvasLayer/UI/Panel/VBox/StatusLabel
@onready var match_label: Label = $CanvasLayer/UI/Panel/VBox/MatchLabel
@onready var peers_label: Label = $CanvasLayer/UI/Panel/VBox/PeersLabel
@onready var objects_label: Label = $CanvasLayer/UI/Panel/VBox/ObjectsLabel
@onready var match_id_input: LineEdit = $CanvasLayer/UI/Panel/VBox/JoinRow/MatchIDInput
@onready var log_output: TextEdit = $CanvasLayer/UI/Panel/VBox/LogOutput


func _ready() -> void:
	randomize()
	_connect_signals()
	_setup_buttons()
	_display_instance_title()
	_refresh_labels()
	if not NakamaManager.is_authenticated:
		NakamaManager.authenticate_device()
	else:
		_log("Already authenticated as " + _short_id(NakamaManager.local_user_id))


func _process(_delta: float) -> void:
	_refresh_labels()


func _connect_signals() -> void:
	if not NakamaManager.authenticated.is_connected(_on_authenticated):
		NakamaManager.authenticated.connect(_on_authenticated)
	if not NakamaManager.authentication_failed.is_connected(_on_auth_failed):
		NakamaManager.authentication_failed.connect(_on_auth_failed)
	if not NakamaManager.connection_restored.is_connected(_on_socket_connected):
		NakamaManager.connection_restored.connect(_on_socket_connected)
	if not NakamaManager.match_created.is_connected(_on_match_created):
		NakamaManager.match_created.connect(_on_match_created)
	if not NakamaManager.match_joined.is_connected(_on_match_joined):
		NakamaManager.match_joined.connect(_on_match_joined)
	if not NakamaManager.match_left.is_connected(_on_match_left):
		NakamaManager.match_left.connect(_on_match_left)
	if not NakamaManager.match_presence.is_connected(_on_match_presence):
		NakamaManager.match_presence.connect(_on_match_presence)
	if not NetworkManager.snapshot_reconstructed.is_connected(_on_snapshot_reconstructed):
		NetworkManager.snapshot_reconstructed.connect(_on_snapshot_reconstructed)
	if not NetworkManager.ownership_changed.is_connected(_on_ownership_changed):
		NetworkManager.ownership_changed.connect(_on_ownership_changed)


func _setup_buttons() -> void:
	$CanvasLayer/UI/Panel/VBox/ButtonsRow/HostButton.pressed.connect(_on_host_pressed)
	$CanvasLayer/UI/Panel/VBox/JoinRow/JoinButton.pressed.connect(_on_join_pressed)
	$CanvasLayer/UI/Panel/VBox/ButtonsRow/LeaveButton.pressed.connect(_on_leave_pressed)
	$CanvasLayer/UI/Panel/VBox/SpawnRow/SpawnPlacedButton.pressed.connect(func(): _spawn_box("placed_room"))
	$CanvasLayer/UI/Panel/VBox/SpawnRow/SpawnSavedButton.pressed.connect(func(): _spawn_box("placed_saved"))
	$CanvasLayer/UI/Panel/VBox/SpawnRow/SpawnTransientButton.pressed.connect(func(): _spawn_box("transient_held"))
	$CanvasLayer/UI/Panel/VBox/ButtonsRow/SnapshotButton.pressed.connect(_on_snapshot_pressed)


func _display_instance_title() -> void:
	var pid := str(OS.get_process_id())
	DisplayServer.window_set_title("Phase2 Ownership 3D Test - PID " + pid)
	_log("Window PID: " + pid)
	_log("Use two instances: one Host, one Join.")


func _on_authenticated(_session: Dictionary) -> void:
	_log("Authenticated: " + _short_id(NakamaManager.local_user_id))


func _on_auth_failed(err: String) -> void:
	_log("Auth failed: " + err)


func _on_socket_connected() -> void:
	_log("Socket connected")


func _on_match_created(match_id: String, _label: String) -> void:
	match_id_input.text = match_id
	_log("Match created: " + match_id)


func _on_match_joined(match_id: String) -> void:
	_log("Joined match: " + match_id)


func _on_match_left() -> void:
	_log("Left match")


func _on_match_presence(joins: Array, leaves: Array) -> void:
	for j in joins:
		_log("+ join " + _short_id(str(j.get("user_id", ""))))
	for l in leaves:
		_log("- leave " + _short_id(str(l.get("user_id", ""))))


func _on_snapshot_reconstructed(snapshot_id: String, object_count: int) -> void:
	_log("Snapshot reconstructed: " + snapshot_id + " objects=" + str(object_count))


func _on_ownership_changed(object_id: String, new_owner_id: String, previous_owner_id: String) -> void:
	_log("Ownership " + object_id + " " + _short_id(previous_owner_id) + " -> " + _short_id(new_owner_id))


func _on_host_pressed() -> void:
	if not NakamaManager.is_socket_connected:
		_log("Socket not connected yet")
		return
	NakamaManager.create_match()


func _on_join_pressed() -> void:
	var match_id := match_id_input.text.strip_edges()
	if match_id.is_empty():
		_log("Enter match id")
		return
	NakamaManager.join_match(match_id)


func _on_leave_pressed() -> void:
	NakamaManager.leave_match()


func _on_snapshot_pressed() -> void:
	if NakamaManager.current_match_id.is_empty():
		_log("Join a room first")
		return
	NetworkManager.request_room_snapshot()
	_log("Snapshot request sent")


func _spawn_box(persist_mode: String) -> void:
	if NakamaManager.current_match_id.is_empty():
		_log("Join a room first")
		return
	var spawn_pos := Vector3(randf_range(-4.0, 4.0), randf_range(0.6, 3.8), FIXED_Z)
	var object_id := NetworkManager.spawn_network_object_with_mode(BOX_SCENE_PATH, spawn_pos, persist_mode, "default")
	if object_id.is_empty():
		_log("Spawn failed")
		return
	var node := get_node_or_null(object_id)
	if node and node.has_method("set_release_persist_mode"):
		node.call("set_release_persist_mode", persist_mode)
	_log("Spawned " + object_id + " mode=" + persist_mode)


func _refresh_labels() -> void:
	var in_match := not NakamaManager.current_match_id.is_empty()
	var my_id := NetworkManager.get_stable_network_id()
	var host_text := "host=" + _short_id(NetworkManager.get_host_peer_id() if NetworkManager.has_method("get_host_peer_id") else "")
	status_label.text = "auth=" + str(NakamaManager.is_authenticated) + " socket=" + str(NakamaManager.is_socket_connected) + " in_match=" + str(in_match) + " " + host_text
	match_label.text = "match=" + NakamaManager.current_match_id
	peers_label.text = "players=" + str(NetworkManager.players.size()) + " me=" + _short_id(my_id)
	objects_label.text = "registry_objects=" + str(NetworkManager.room_object_registry.size())


func _log(line: String) -> void:
	print("[Phase2Test] " + line)
	if not log_output:
		return
	log_output.text += line + "\n"
	await get_tree().process_frame
	log_output.scroll_vertical = log_output.get_line_count()


func _short_id(value: String) -> String:
	if value.is_empty():
		return "-"
	return value.substr(0, min(8, value.length()))
