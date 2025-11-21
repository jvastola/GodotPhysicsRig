extends Node

# Grapple visuals manager — create and keep visuals on scene root so they persist across scene changes.
# Add this script as an Autoload (Project Settings > Autoload) with a name like 'GrappleVisuals' to use it automatically.

@export var hitmarker_size: Vector3 = Vector3(0.12, 0.12, 0.12)
@export var hitmarker_color: Color = Color8(255, 100, 50)
@export var rope_thickness: float = 0.02
@export var rope_color: Color = Color8(255, 200, 80)

var hitmarker: MeshInstance3D = null
var rope_container: Node3D = null
var segments: Array = []
var shared_cylinder: CylinderMesh = null
var _persist_ttl: float = 0.0

func _process(delta: float) -> void:
	if _persist_ttl > 0.0:
		_persist_ttl -= delta
		if _persist_ttl <= 0.0:
			hide_segments()
			hide_hitmarker()

func _add_child_to_root_deferred(node: Node) -> void:
	var root = get_tree().root
	if root:
		root.call_deferred("add_child", node)
	else:
		# Try again a frame later
		call_deferred("_add_child_to_root_deferred", node)

func _ready():
	# Create hitmarker
	hitmarker = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = hitmarker_size
	hitmarker.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = hitmarker_color
	mat.emission_enabled = true
	mat.emission = hitmarker_color
	hitmarker.material_override = mat
	hitmarker.visible = false
	hitmarker.name = "GrappleHitmarker"
	# Attach to root, but guard in case project is running in a context
	# where `get_tree().root` is temporarily null (e.g., editor scripts).
	_add_child_to_root_deferred(hitmarker)

	# Create shared cylinder
	shared_cylinder = CylinderMesh.new()
	shared_cylinder.top_radius = 1.0
	shared_cylinder.bottom_radius = 1.0
	shared_cylinder.height = 1.0
	shared_cylinder.radial_segments = 12

	# Create container for segments
	rope_container = Node3D.new()
	rope_container.name = "GrappleRopeContainer"
	_add_child_to_root_deferred(rope_container)

func init_segments(count: int):
	clear_segments()
	for i in range(count):
		var seg = MeshInstance3D.new()
		seg.mesh = shared_cylinder
		var mat2 = StandardMaterial3D.new()
		mat2.flags_unshaded = true
		mat2.emission_enabled = true
		mat2.emission = rope_color
		seg.material_override = mat2
		seg.visible = false
		rope_container.add_child(seg)
		segments.append(seg)

func clear_segments():
	for s in segments:
		if is_instance_valid(s):
			s.queue_free()
	segments.clear()


func show_hitmarker(pos: Vector3, normal: Vector3 = Vector3.UP):
	if not is_instance_valid(hitmarker):
		return
	
	# Create a basis that aligns to the hit normal
	var y_axis = normal.normalized()
	var x_axis: Vector3
	
	# Choose a reference vector that's not parallel to the normal
	if abs(y_axis.dot(Vector3.UP)) < 0.999:
		x_axis = Vector3.UP.cross(y_axis).normalized()
	else:
		x_axis = Vector3.FORWARD.cross(y_axis).normalized()
	
	var z_axis = y_axis.cross(x_axis).normalized()
	var basis = Basis(x_axis, y_axis, z_axis)
	
	hitmarker.global_transform = Transform3D(basis, pos)
	hitmarker.visible = true

func hide_hitmarker():
	if is_instance_valid(hitmarker):
		hitmarker.visible = false

func update_segment(i: int, origin: Vector3, end: Vector3, thickness: float) -> void:
	if i < 0 or i >= segments.size():
		return
	var seg = segments[i]
	var v = end - origin
	var length = v.length()
	if length <= 0.0001:
		seg.visible = false
		return
	var dir = v / length
	var up = Vector3.UP
	if abs(dir.dot(up)) > 0.999:
		up = Vector3.FORWARD
	var right = up.cross(dir).normalized()
	var forward = dir.cross(right).normalized()
	var seg_basis = Basis(right, dir, forward)
	var mid = origin + v * 0.5
	seg.global_transform = Transform3D(seg_basis, mid)
	seg.scale = Vector3(thickness, length, thickness)
	seg.visible = true

func persist_rope(points: Array, thickness: float, ttl: float = 5.0) -> void:
	# Make sure there are enough segments
	init_segments(points.size() - 1)
	for i in range(points.size() - 1):
		update_segment(i, points[i], points[i+1], thickness)
	_persist_ttl = ttl

func hide_segments():
	for s in segments:
		if is_instance_valid(s):
			s.visible = false

func free_visuals():
	if is_instance_valid(hitmarker):
		hitmarker.queue_free()
	if is_instance_valid(rope_container):
		rope_container.queue_free()
	clear_segments()
