extends Area3D

@export var release_persist_mode: String = "placed_room"
@export var fixed_z: float = 0.0

@onready var mesh: MeshInstance3D = $Mesh
@onready var label_3d: Label3D = $Label3D

var _is_locally_held: bool = false
var _owner_id: String = ""
var _drag_offset: Vector3 = Vector3.ZERO
var _send_timer: float = 0.0
var _drag_camera: Camera3D = null
var _last_mouse_down: bool = false


func _ready() -> void:
	input_ray_pickable = true
	_last_mouse_down = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if NetworkManager and NetworkManager.has_signal("ownership_changed") and not NetworkManager.ownership_changed.is_connected(_on_ownership_changed):
		NetworkManager.ownership_changed.connect(_on_ownership_changed)
	if NetworkManager and NetworkManager.has_signal("grabbable_sync_update") and not NetworkManager.grabbable_sync_update.is_connected(_on_grabbable_sync_update):
		NetworkManager.grabbable_sync_update.connect(_on_grabbable_sync_update)
	if NetworkManager and NetworkManager.has_signal("grabbable_released") and not NetworkManager.grabbable_released.is_connected(_on_grabbable_released):
		NetworkManager.grabbable_released.connect(_on_grabbable_released)
	if NetworkManager and NetworkManager.has_signal("network_object_despawn_requested") and not NetworkManager.network_object_despawn_requested.is_connected(_on_network_object_despawn_requested):
		NetworkManager.network_object_despawn_requested.connect(_on_network_object_despawn_requested)
	_refresh_visuals()


func set_release_persist_mode(mode: String) -> void:
	release_persist_mode = mode
	_refresh_visuals()


func _input_event(_camera: Camera3D, event: InputEvent, event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		print("[Phase2Block] click on ", name, " requester=", NetworkManager.get_stable_network_id())
		_drag_camera = _camera
		_drag_offset = global_position - Vector3(event_position.x, event_position.y, fixed_z)
		NetworkManager.request_object_ownership(name, "mouse")


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _is_locally_held:
		_release_hold()


func _process(delta: float) -> void:
	var mouse_down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if _is_locally_held and _last_mouse_down and not mouse_down:
		_release_hold()
	_last_mouse_down = mouse_down

	if not _is_locally_held:
		return
	var camera := _drag_camera if _drag_camera else get_viewport().get_camera_3d()
	if not camera:
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	var plane := Plane(Vector3(0, 0, 1), fixed_z)
	var hit = plane.intersects_ray(ray_origin, ray_dir)
	if hit == null:
		return
	var target: Vector3 = hit + _drag_offset
	target.z = fixed_z
	global_position = target
	_send_timer += delta
	if _send_timer >= 0.05:
		_send_timer = 0.0
		NetworkManager.update_grabbed_object(name, global_position, Quaternion.IDENTITY)


func _release_hold() -> void:
	var final_pos := global_position
	final_pos.z = fixed_z
	print("[Phase2Block] release ", name, " mode=", release_persist_mode)
	NetworkManager.release_object(name, final_pos, Quaternion.IDENTITY, Vector3.ZERO, Vector3.ZERO, release_persist_mode)
	_is_locally_held = false
	_drag_camera = null
	_refresh_visuals()


func _on_ownership_changed(object_id: String, new_owner_id: String, _previous_owner_id: String) -> void:
	if object_id != name:
		return
	print("[Phase2Block] ownership ", name, " -> ", _short(new_owner_id))
	_owner_id = new_owner_id
	_is_locally_held = (new_owner_id == NetworkManager.get_stable_network_id())
	if not _is_locally_held:
		_drag_camera = null
	_refresh_visuals()


func _on_grabbable_sync_update(object_id: String, data: Dictionary) -> void:
	if object_id != name or _is_locally_held:
		return
	var pos: Vector3 = data.get("position", global_position)
	global_position = Vector3(pos.x, pos.y, fixed_z)


func _on_grabbable_released(object_id: String, _peer_id: String) -> void:
	if object_id != name:
		return
	if _is_locally_held:
		return
	_refresh_visuals()


func _on_network_object_despawn_requested(object_id: String) -> void:
	if object_id == name:
		queue_free()


func _refresh_visuals() -> void:
	if not mesh:
		return
	var mat := mesh.get_active_material(0)
	if mat == null:
		mat = StandardMaterial3D.new()
		mesh.set_surface_override_material(0, mat)
	if mat is StandardMaterial3D:
		var std := mat as StandardMaterial3D
		if _is_locally_held:
			std.albedo_color = Color(0.2, 0.9, 0.35)
		elif release_persist_mode == "placed_saved":
			std.albedo_color = Color(0.2, 0.6, 1.0)
		elif release_persist_mode == "transient_held":
			std.albedo_color = Color(1.0, 0.55, 0.2)
		else:
			std.albedo_color = Color(0.85, 0.85, 0.85)
	if label_3d:
		label_3d.text = name + "\nowner=" + _short(_owner_id) + "\nmode=" + release_persist_mode


func _short(value: String) -> String:
	if value.is_empty():
		return "-"
	return value.substr(0, min(8, value.length()))
