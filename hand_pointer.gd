extends Node3D

# hand_pointer.gd
# Provides a simple pointing aid for VR hands. A ray is cast forward and a
# lightweight line visual plus hit indicator are maintained to mirror the
# watch compass behaviour without sharing its assets.

@export var pointer_face_path: NodePath = "PointerFace"
@export var raycast_node_path: NodePath = "PointerRayCast"
@export var ray_visual_node_path: NodePath = "PointerRayVisual"
@export var ray_hit_node_path: NodePath = "PointerRayHit"
@export var pointer_axis_local: Vector3 = Vector3(0, 0, -1)
@export_range(0.1, 10.0, 0.1) var ray_length: float = 3.0
@export var hide_face_on_player_hit: bool = true
@export var player_group: StringName = &"player"

@onready var _pointer_face: MeshInstance3D = get_node_or_null(pointer_face_path) as MeshInstance3D
@onready var _raycast: RayCast3D = get_node_or_null(raycast_node_path) as RayCast3D
@onready var _ray_visual: MeshInstance3D = get_node_or_null(ray_visual_node_path) as MeshInstance3D
@onready var _ray_hit: MeshInstance3D = get_node_or_null(ray_hit_node_path) as MeshInstance3D

var _line_mesh: ImmediateMesh

func _ready() -> void:
	if _pointer_face:
		_pointer_face.visible = true

	if _raycast:
		var axis := pointer_axis_local.normalized()
		if axis.length_squared() > 0.0:
			_raycast.target_position = axis * ray_length
		_raycast.enabled = true

	if _ray_visual:
		var mesh := _ray_visual.mesh
		if mesh is ImmediateMesh:
			_line_mesh = mesh
		else:
			_line_mesh = ImmediateMesh.new()
			_ray_visual.mesh = _line_mesh
		_ray_visual.visible = true

	if _ray_hit:
		_ray_hit.visible = false

func _physics_process(_delta: float) -> void:
	if not _raycast:
		return

	var axis_local := pointer_axis_local.normalized()
	if axis_local.length_squared() <= 0.0:
		return

	_raycast.target_position = axis_local * ray_length
	_raycast.force_raycast_update()

	var axis_world := (global_transform.basis * axis_local).normalized()
	var start := global_transform.origin
	var end := start + axis_world * ray_length
	var distance := ray_length
	var hit_player := false
	var has_hit := _raycast.is_colliding()

	if has_hit:
		end = _raycast.get_collision_point()
		distance = start.distance_to(end)
		var collider := _raycast.get_collider()
		if hide_face_on_player_hit and collider is Node:
			hit_player = (collider as Node).is_in_group(player_group)

	if _ray_hit:
		_ray_hit.visible = has_hit
		if has_hit:
			var hit_xform := _ray_hit.global_transform
			hit_xform.origin = end
			# Align the hit indicator so its local +Y (cylinder axis) points along the surface normal
			var normal: Vector3 = _raycast.get_collision_normal().normalized()
			if normal.length_squared() > 0.0:
				# Build an orthonormal basis with Y = normal
				var y := normal
				var up := Vector3.UP
				if abs(y.dot(up)) > 0.999: # nearly parallel, choose another up
					up = Vector3.FORWARD
				var x := up.cross(y).normalized()
				var z := y.cross(x).normalized()
				hit_xform.basis = Basis(x, y, z)
			else:
				hit_xform.basis = Basis.IDENTITY
			_ray_hit.global_transform = hit_xform

	if _line_mesh:
		var local_end := axis_local * distance
		_line_mesh.clear_surfaces()
		_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		_line_mesh.surface_add_vertex(Vector3.ZERO)
		_line_mesh.surface_add_vertex(local_end)
		_line_mesh.surface_end()

	if _pointer_face and hide_face_on_player_hit:
		_pointer_face.visible = not hit_player
