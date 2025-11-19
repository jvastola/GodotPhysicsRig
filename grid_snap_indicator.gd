extends Node3D

class_name GridSnapIndicator

var _grid_size: float = 0.1
var _snap_interval: float = 0.1
var _orientation_space: String = "world"

@export_enum("on_hit", "always", "manual") var follow_mode: String = "on_hit"
@export_enum("world", "local") var orientation_space := "world":
	set(value):
		_orientation_space = value
		_apply_orientation_space()
	get:
		return _orientation_space
@export var align_with_surface_normal: bool = false
@export var maintain_visibility_without_hit: bool = false

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
var _initial_basis: Basis = Basis.IDENTITY

func _ready() -> void:
	_raycast = get_node_or_null(raycast_path) as RayCast3D
	_indicator_mesh = get_node_or_null(indicator_mesh_path) as MeshInstance3D
	_initial_basis = global_transform.basis
	_apply_indicator_scale()
	_apply_indicator_material()
	_apply_orientation_space()
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

func _apply_orientation_space() -> void:
	top_level = (_orientation_space == "world")

func _snap_from_sample(sample_point: Vector3, has_hit: bool, surface_normal: Vector3) -> void:
	var should_show: bool = has_hit or not hide_without_hit
	_apply_snapped_position(_snap_to_grid(sample_point), surface_normal)
	if not should_show and hide_without_hit and not maintain_visibility_without_hit:
		_set_indicator_visible(false)

func _derive_basis(surface_normal: Vector3) -> Basis:
	if align_with_surface_normal and surface_normal.length_squared() > 0.0:
		return _basis_from_normal(surface_normal)
	if _orientation_space == "world":
		return Basis.IDENTITY
	if _raycast:
		return _raycast.global_transform.basis
	return _initial_basis

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
