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

@onready var _needle: MeshInstance3D = get_node_or_null(needle_node_path) as MeshInstance3D
@onready var _watch_face: MeshInstance3D = get_node_or_null(watch_face_node_path) as MeshInstance3D

func _process(delta: float) -> void:
	# Always show the watch face and needle; update needle orientation every frame
	if _watch_face:
		_watch_face.visible = true
	if _needle:
		_needle.visible = true

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
