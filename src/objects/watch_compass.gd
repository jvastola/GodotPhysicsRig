extends Node3D

# watch_compass.gd
# Places a needle on the watch that points to world "north" (default = world -Z).
# Usage notes:
# - The `Needle` node should point along its local +Y when the needle rotation is zero.
# - `rotation_axis_local` is the axis in local space that the needle rotates around (default Z).

@export var needle_node_path: NodePath = "Needle"
@export var watch_face_node_path: NodePath = "WatchFace"
@export var north_world: Vector3 = Vector3(0, 0, -1)
@export var rotation_axis_local: Vector3 = Vector3(0, 0, 1)
@export_range(0.0, 100.0, 0.1) var smoothing: float = 8.0
@export var raycast_node_path: NodePath = "RayCast"
@export var ray_visual_node_path: NodePath = "RayVisual"
@export var ray_hit_node_path: NodePath = "RayHit"
@export_range(0.0, 10.0, 0.1) var ray_length: float = 2.0
@export var show_line: bool = true
@export var show_hitpoint: bool = true
@export var ui_viewport_node_path: NodePath = "UIViewportWatch"

# When true, the needle is enabled only while the ray hits the player; when
# false the needle remains visible regardless of player hits.
@export var needle_only_on_player_hit: bool = true
@export var player_group: StringName = &"player"

@onready var _needle: MeshInstance3D = get_node_or_null(needle_node_path) as MeshInstance3D
@onready var _watch_face: MeshInstance3D = get_node_or_null(watch_face_node_path) as MeshInstance3D
@onready var _raycast: RayCast3D = get_node_or_null(raycast_node_path) as RayCast3D
@onready var _ray_visual: MeshInstance3D = get_node_or_null(ray_visual_node_path) as MeshInstance3D
@onready var _ray_hit_indicator: MeshInstance3D = get_node_or_null(ray_hit_node_path) as MeshInstance3D
@onready var _ui_viewport: Node = get_node_or_null(ui_viewport_node_path) as Node

var _ray_mesh: ImmediateMesh

func _ready() -> void:
	if _raycast:
		var axis_local := rotation_axis_local.normalized()
		if axis_local.length_squared() > 0.0:
			_raycast.target_position = axis_local * ray_length
		_raycast.enabled = true
	if _ray_visual:
		var existing_mesh := _ray_visual.mesh
		if existing_mesh is ImmediateMesh:
			_ray_mesh = existing_mesh
		else:
			_ray_mesh = ImmediateMesh.new()
			_ray_visual.mesh = _ray_mesh
		# Respect the show_line toggle
		_ray_visual.visible = show_line
	if _ray_hit_indicator:
		_ray_hit_indicator.visible = false
		# If hitpoint visuals are disabled, hide the node
		if not show_hitpoint:
			_ray_hit_indicator.visible = false

	# Initialize needle visibility according to the toggle. If needle_only_on_player_hit
	# is true, start hidden until the ray hits the player.
	if _needle:
		_needle.visible = not needle_only_on_player_hit
	if _ui_viewport and needle_only_on_player_hit:
		_ui_viewport.visible = false

func _process(delta: float) -> void:
	# Always show the watch face and needle; update needle orientation every frame
	if _watch_face:
		_watch_face.visible = true
	# NOTE: needle visibility is controlled in _update_ray_visual() when
	# `needle_only_on_player_hit` is enabled; do not force visibility here.

	if not _needle:
		return

	# Compute watch face normal (rotation axis) in world space
	var axis_world: Vector3 = (global_transform.basis * rotation_axis_local).normalized()

	# Project world "north" onto the plane perpendicular to the watch face normal
	var target: Vector3 = north_world.normalized()
	var proj: Vector3 = target - axis_world * target.dot(axis_world)
	if proj.length_squared() < 1e-8:
		# North is parallel to watch face normal; can't determine direction
		return
	proj = proj.normalized()

	# Build target basis for the needle:
	# - needle local +Y should align with projected north (proj)
	# - needle local +Z should align with watch face normal (axis_world)
	# This ensures needle points to north on the watch face plane
	var needle_forward: Vector3 = proj
	var needle_up: Vector3 = axis_world
	var needle_right: Vector3 = needle_up.cross(needle_forward).normalized()
	# Recompute forward to ensure orthogonality (in case of numerical error)
	needle_forward = needle_right.cross(needle_up).normalized()
	
	var target_basis: Basis = Basis(needle_right, needle_forward, needle_up)
	var target_quat: Quaternion = target_basis.get_rotation_quaternion()
	
	# Get current needle orientation
	var current_quat: Quaternion = _needle.global_transform.basis.get_rotation_quaternion()

	# Smoothly slerp toward target (apply a fraction of the rotation each frame)
	var t: float = clamp(smoothing * delta, 0.0, 1.0)
	var out_quat: Quaternion = current_quat.slerp(target_quat, t)

	# Apply new rotation keeping needle world position
	var gtf: Transform3D = _needle.global_transform
	gtf.basis = Basis(out_quat)
	_needle.global_transform = gtf

	# done

func _physics_process(_delta: float) -> void:
	# Perform raycast and visual updates in the physics step to access space state safely
	# Compute watch face normal in world space
	var axis_world: Vector3 = (global_transform.basis * rotation_axis_local).normalized()

	_update_ray_visual(axis_world)

func _update_ray_visual(axis_world: Vector3) -> void:
	var axis_local := rotation_axis_local.normalized()
	if axis_local.length_squared() < 1e-8:
		return

	var start_global: Vector3 = global_transform.origin
	var hit_point: Vector3 = start_global + axis_world * ray_length
	var hit_distance: float = ray_length
	var hit_player := false
	var has_hit := false

	if _raycast:
		_raycast.target_position = axis_local * ray_length
		_raycast.force_raycast_update()
		has_hit = _raycast.is_colliding()
		if has_hit:
			hit_point = _raycast.get_collision_point()
			hit_distance = start_global.distance_to(hit_point)
			var collider := _raycast.get_collider()
			if collider is Node:
				hit_player = (collider as Node).is_in_group(player_group)

	if _ray_hit_indicator:
		_ray_hit_indicator.visible = has_hit and show_hitpoint
		if has_hit and show_hitpoint:
			var hit_xform := _ray_hit_indicator.global_transform
			hit_xform.origin = hit_point
			# Keep the hit indicator flat to the world by default
			hit_xform.basis = Basis.IDENTITY
			_ray_hit_indicator.global_transform = hit_xform

	# Needle visibility: enable when the ray hits the player if the toggle is set,
	# otherwise keep the needle visible normally.
	if _needle:
		if needle_only_on_player_hit:
			_needle.visible = hit_player
			if _ui_viewport:
				_ui_viewport.visible = hit_player
		else:
			_needle.visible = true

	if _ray_visual:
		_ray_visual.global_transform = global_transform
		if _ray_mesh and show_line:
			var local_end := axis_local * hit_distance
			_ray_mesh.clear_surfaces()
			_ray_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			_ray_mesh.surface_add_vertex(Vector3.ZERO)
			_ray_mesh.surface_add_vertex(local_end)
			_ray_mesh.surface_end()
