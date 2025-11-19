extends Node3D

class_name GridSnapIndicator

var _grid_size: float = 0.1
var _snap_interval: float = 0.1
var _build_parent_path: NodePath = NodePath()

@export_enum("on_hit", "always", "manual") var follow_mode: String = "on_hit"
@export var align_with_surface_normal: bool = false
@export var maintain_visibility_without_hit: bool = false
@export var pointer_node_path: NodePath
@export var sync_grid_size_from_pointer: bool = false
@export_range(0.01, 10.0, 0.01) var pointer_scale_grid_multiplier: float = 1.0
@export_range(0.005, 2.0, 0.005) var pointer_scale_min_grid_size: float = 0.01
@export_range(0.0, 0.25, 0.001) var surface_normal_offset: float = 0.01
@export var build_mode_enabled: bool = false
@export var build_mode_toggle_action: String = "build_mode_toggle"
@export var build_cube_scene: PackedScene
@export var default_build_color: Color = Color(0.6, 0.6, 0.6, 1.0)
@export_range(0.1, 5.0, 0.1) var build_scale_multiplier: float = 1.0
@export var build_parent_path: NodePath:
	set(value):
		_build_parent_path = value
		_refresh_build_parent()
	get:
		return _build_parent_path

@export_range(0.01, 5.0, 0.01) var grid_size: float = 0.1:
	set(value):
		_grid_size = max(value, 0.01)
		_apply_indicator_scale()
	get:
		return _grid_size

@export_range(0.05, 1.0, 0.01) var snap_interval: float = 0.1:
	set(value):
		_snap_interval = max(value, 0.01)
	get:
		return _snap_interval

@export var raycast_path: NodePath
@export var indicator_mesh_path: NodePath = NodePath("IndicatorMesh")
@export var auto_sample_from_raycast: bool = true
@export var hide_without_hit: bool = true
var _raycast: RayCast3D
var _indicator_mesh: MeshInstance3D
var _accumulated_time: float = 0.0
var _last_snapped_position: Vector3 = Vector3.ZERO
var _has_valid_position: bool = false
var _pointer_node: Node = null
var _build_parent: Node = null

func _ready() -> void:
	_raycast = get_node_or_null(raycast_path) as RayCast3D
	_indicator_mesh = get_node_or_null(indicator_mesh_path) as MeshInstance3D
	top_level = true
	_apply_indicator_scale()
	_apply_indicator_material()
	_connect_pointer_signal()
	_refresh_build_parent()
	_set_indicator_visible(false)

func _physics_process(delta: float) -> void:
	if not auto_sample_from_raycast or not _raycast:
		return
	if follow_mode == "manual":
		return
	_accumulated_time += delta
	if _accumulated_time < _snap_interval:
		return
	_accumulated_time = 0.0
	_update_from_raycast()

func _process(_delta: float) -> void:
	_handle_build_mode_toggle()

func _update_from_raycast() -> void:
	if not _raycast:
		return
	var has_hit: bool = _raycast.is_colliding()
	if follow_mode == "on_hit":
		if not has_hit:
			if hide_without_hit:
				clear_indicator()
			return
		_snap_from_sample(_raycast.get_collision_point(), has_hit, _raycast.get_collision_normal())
		return
	if follow_mode == "always":
		var target_point: Vector3
		var normal: Vector3 = Vector3.UP
		if has_hit:
			target_point = _raycast.get_collision_point()
			normal = _raycast.get_collision_normal()
		else:
			target_point = _raycast.to_global(_raycast.target_position)
		_snap_from_sample(target_point, has_hit, normal)
		return
	# manual mode falls through for external control

func snap_world_position(world_position: Vector3, show: bool = true, surface_normal: Vector3 = Vector3.UP) -> void:
	_apply_snapped_position(_snap_to_grid(world_position), surface_normal)
	if show:
		_set_indicator_visible(true)
	else:
		_set_indicator_visible(false)

func clear_indicator() -> void:
	_has_valid_position = false
	_set_indicator_visible(false)

func get_last_snapped_position() -> Vector3:
	return _last_snapped_position

func has_snapped_position() -> bool:
	return _has_valid_position

func _snap_to_grid(position: Vector3) -> Vector3:
	var cell_size: float = max(_grid_size, 0.01)
	return Vector3(
		_snap_axis(position.x, cell_size),
		_snap_axis(position.y, cell_size),
		_snap_axis(position.z, cell_size)
	)

func _snap_axis(value: float, cell_size: float) -> float:
	return round(value / cell_size) * cell_size

func _apply_indicator_scale() -> void:
	if not _indicator_mesh:
		return
	var size: float = max(_grid_size, 0.01)
	_indicator_mesh.scale = Vector3.ONE * size

func _apply_snapped_position(snapped: Vector3, surface_normal: Vector3) -> void:
	_last_snapped_position = snapped
	_has_valid_position = true
	var new_basis: Basis = _derive_basis(surface_normal)
	var new_transform := Transform3D(new_basis, snapped)
	global_transform = new_transform
	_set_indicator_visible(true)


func _apply_indicator_material() -> void:
	if not _indicator_mesh:
		return
	if _indicator_mesh.material_override:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.3, 0.8, 1.0, 0.2)
	mat.disable_fog = true
	_indicator_mesh.material_override = mat

func _set_indicator_visible(visible: bool) -> void:
	if _indicator_mesh:
		_indicator_mesh.visible = visible
	self.visible = visible

func _snap_from_sample(sample_point: Vector3, has_hit: bool, surface_normal: Vector3) -> void:
	var should_show: bool = has_hit or not hide_without_hit
	var adjusted_point: Vector3 = sample_point
	if has_hit and surface_normal.length_squared() > 0.0 and surface_normal_offset > 0.0:
		adjusted_point += surface_normal.normalized() * surface_normal_offset
	_apply_snapped_position(_snap_to_grid(adjusted_point), surface_normal)
	if not should_show and hide_without_hit and not maintain_visibility_without_hit:
		_set_indicator_visible(false)

func _derive_basis(surface_normal: Vector3) -> Basis:
	if align_with_surface_normal and surface_normal.length_squared() > 0.0:
		return _basis_from_normal(surface_normal)
	return Basis.IDENTITY

func _basis_from_normal(normal: Vector3) -> Basis:
	var y: Vector3 = normal.normalized()
	if y.length_squared() <= 0.0:
		return Basis.IDENTITY
	var reference: Vector3 = Vector3.UP
	if abs(y.dot(reference)) > 0.98:
		reference = Vector3.RIGHT
	var x: Vector3 = reference.cross(y).normalized()
	var z: Vector3 = y.cross(x).normalized()
	return Basis(x, y, z)

func _connect_pointer_signal() -> void:
	if pointer_node_path == NodePath():
		return
	var node := get_node_or_null(pointer_node_path)
	if not node:
		return
	_pointer_node = node
	if node.has_signal("hit_scale_changed"):
		if not node.is_connected("hit_scale_changed", Callable(self, "_on_pointer_hit_scale_changed")):
			node.connect("hit_scale_changed", Callable(self, "_on_pointer_hit_scale_changed"))
	if node.has_signal("pointer_event"):
		if not node.is_connected("pointer_event", Callable(self, "_on_pointer_event")):
			node.connect("pointer_event", Callable(self, "_on_pointer_event"))

func _on_pointer_hit_scale_changed(scale: float) -> void:
	if not sync_grid_size_from_pointer:
		return
	var new_size: float = max(scale * pointer_scale_grid_multiplier, pointer_scale_min_grid_size)
	grid_size = new_size

func _on_pointer_event(event: Dictionary) -> void:
	if not build_mode_enabled:
		return
	if event.get("type", "") != "press":
		return
	if not event.get("action_just_pressed", false):
		return
	_spawn_build_cube(event)

func _handle_build_mode_toggle() -> void:
	if build_mode_toggle_action == "":
		return
	if not InputMap.has_action(build_mode_toggle_action):
		return
	if Input.is_action_just_pressed(build_mode_toggle_action):
		build_mode_enabled = not build_mode_enabled

func _refresh_build_parent() -> void:
	if not is_inside_tree():
		return
	if _build_parent_path == NodePath():
		_build_parent = get_tree().current_scene
	else:
		_build_parent = get_node_or_null(_build_parent_path)

func _get_build_parent() -> Node:
	if _build_parent and is_instance_valid(_build_parent):
		return _build_parent
	_refresh_build_parent()
	return _build_parent

func _spawn_build_cube(event: Dictionary) -> void:
	if not build_cube_scene:
		return
	var parent := _get_build_parent()
	if not parent:
		return
	var cube := build_cube_scene.instantiate()
	if not cube:
		return
	parent.add_child(cube)
	var target_position: Vector3 = _determine_build_position(event)
	var color: Color = _get_pointer_color(event)
	var transform := Transform3D(Basis.IDENTITY, target_position)
	cube.global_transform = transform
	var scale_factor: float = max(grid_size * build_scale_multiplier, 0.01)
	if cube is Node3D:
		var cube_node := cube as Node3D
		cube_node.scale = Vector3.ONE * scale_factor
	if cube.has_method("set_build_color"):
		cube.call("set_build_color", color)
	else:
		_apply_color_to_mesh(cube, color)

func _determine_build_position(event: Dictionary) -> Vector3:
	if _has_valid_position:
		return _last_snapped_position
	return event.get("global_position", global_transform.origin)

func _get_pointer_color(event: Dictionary) -> Color:
	if event.has("pointer_color"):
		return event["pointer_color"]
	return default_build_color

func _apply_color_to_mesh(node: Node, color: Color) -> void:
	var mesh: MeshInstance3D = node.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not mesh and node is Node3D:
		for child in (node as Node3D).get_children():
			if child is MeshInstance3D:
				mesh = child
				break
	if not mesh:
		return
	var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
	if not mat:
		mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mesh.material_override = mat
