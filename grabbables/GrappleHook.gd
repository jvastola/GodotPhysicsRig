
extends "res://grabbable.gd"

@export var max_distance: float = 20.0
@export var impulse_speed: float = 12.0
@export var winch_speed: float = 4.0
@export var grapple_collision_mask: int = 1
@export var enable_debug_logs: bool = false
@export var hitmarker_radius: float = 0.06
@export var hitmarker_color: Color = Color8(255, 100, 50)

var _is_hooked: bool = false
var _hook_point: Vector3 = Vector3.ZERO
var _hook_object: Node = null
var _hand: RigidBody3D = null
var _controller: Node = null
var _player_body: RigidBody3D = null
var _hitmarker: MeshInstance3D = null
var _hook_local_offset: Vector3 = Vector3.ZERO
var _rope_cylinder: CylinderMesh = null
var _rope_visual: MeshInstance3D = null
@export var rope_thickness: float = 0.02
@export var rope_segments: int = 10
@export var rope_sag_factor: float = 0.5
@export var rope_sag_max: float = 2.0
var _rope_container: Node3D = null
var _rope_segments_arr: Array = []
@export var rope_start_stiffness: float = 0.05
@export var rope_end_stiffness: float = 0.05
@export var rope_mid_sag_bias: float = 1.0
@export var rope_start_min_length: float = 0.2
@export var rope_color: Color = Color8(255, 200, 80)

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 10
	add_to_group("grabbable")
	body_entered.connect(_on_collision_entered)

	grabbed.connect(_on_grabbed)
	released.connect(_on_released)

	# Create a simple world-space hitmarker (a small emissive sphere)
	var sphere = SphereMesh.new()
	sphere.radius = hitmarker_radius
	var mi = MeshInstance3D.new()
	mi.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = hitmarker_color
	mat.emission_enabled = true
	mat.emission = hitmarker_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.visible = false
	mi.name = "GrappleHitmarker"
	_hitmarker = mi
	# Add hitmarker to the current scene root so it's truly world-space
	var root = get_tree().get_current_scene()
	# Use call_deferred because the scene tree may be busy setting up children when _ready runs.
	if root:
		root.call_deferred("add_child", _hitmarker)
	else:
		call_deferred("add_child", _hitmarker)

	# Create a rope visual as a thin CylinderMesh and a MeshInstance3D
	_rope_cylinder = CylinderMesh.new()
	# Keep the mesh base radius as 1.0 and control final thickness with scale.x/z
	_rope_cylinder.top_radius = 1.0
	_rope_cylinder.bottom_radius = 1.0
	_rope_cylinder.height = 1.0
	_rope_cylinder.radial_segments = 12
	_rope_visual = MeshInstance3D.new()
	_rope_visual.mesh = _rope_cylinder
	var rope_mat = StandardMaterial3D.new()
	rope_mat.flags_unshaded = true
	rope_mat.emission_enabled = true
	rope_mat.emission = rope_color
	rope_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rope_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rope_visual.material_override = rope_mat
	_rope_visual.visible = false
	_rope_visual.name = "GrappleRope"
	# Create a container for rope segments
	_rope_container = Node3D.new()
	_rope_container.name = "GrappleRopeContainer"
	if root:
		root.call_deferred("add_child", _rope_container)
	else:
		call_deferred("add_child", _rope_container)

	# Initialize segment MeshInstances
	for i in rope_segments:
		var seg = MeshInstance3D.new()
		seg.mesh = _rope_cylinder
		seg.material_override = rope_mat
		seg.visible = false
		_rope_container.add_child(seg)
		_rope_segments_arr.append(seg)

	if enable_debug_logs:
		print("GrappleHook: ready at", global_transform.origin, "collision_layer=", collision_layer)

func _on_grabbed(hand: RigidBody3D) -> void:
	_hand = hand
	_controller = null
	_player_body = null
	if is_instance_valid(hand) and hand.has_method("get"):
		var maybe_target = hand.get("target")
		if maybe_target and maybe_target is Node3D:
			_controller = maybe_target

		var maybe_player = hand.get("player_rigidbody")
		if maybe_player and maybe_player is RigidBody3D:
			_player_body = maybe_player

	set_physics_process(true)
	# show prediction marker while grabbed
	if is_instance_valid(_hitmarker):
		_hitmarker.visible = true

func _on_released() -> void:
	_end_grapple()
	set_physics_process(false)
	if is_instance_valid(_hitmarker):
		_hitmarker.visible = false
	if is_instance_valid(_rope_visual):
		_rope_visual.visible = false
		if _rope_cylinder:
			# Reset scale and height
			_rope_visual.scale = Vector3.ONE
			_rope_visual.mesh = _rope_cylinder

func _end_grapple() -> void:
	_is_hooked = false
	_hook_object = null
	# Hide the hitmarker when grappling ends (cleanup)
	if is_instance_valid(_hitmarker):
		_hitmarker.visible = false
	if is_instance_valid(_rope_visual):
		_rope_visual.visible = false
		if _rope_cylinder:
			# Reset scale and mesh if we later toggle rope on
			_rope_visual.mesh = _rope_cylinder

	# Hide segments on release
	for seg in _rope_segments_arr:
		if is_instance_valid(seg):
			seg.visible = false

func _physics_process(delta: float) -> void:
	if not is_grabbed:
		return
	if not is_instance_valid(_hand):
		return

	# Determine controller transform (prefer controller target when present)
	var controller_transform: Transform3D
	if is_instance_valid(_controller) and _controller is Node3D:
		controller_transform = (_controller as Node3D).global_transform
	else:
		controller_transform = _hand.global_transform

	# Read trigger input
	var trigger_pressed: bool = false
	if is_instance_valid(_controller) and _controller.has_method("is_button_pressed"):
		trigger_pressed = _controller.is_button_pressed("trigger_click")
	elif InputMap.has_action("trigger_click"):
		trigger_pressed = Input.is_action_pressed("trigger_click")

	# Prediction: while grabbed and not hooked, update hitmarker to where the grapple would land
	if is_instance_valid(_hitmarker) and not _is_hooked:
		var _from = controller_transform.origin
		var _forward_vec: Vector3 = controller_transform.basis.z
		var _dir: Vector3 = _forward_vec.normalized() * -1.0
		var _to = _from + _dir * max_distance
		var _space = get_world_3d().direct_space_state
		var _exclude = [self]
		if is_instance_valid(_hand):
			_exclude.append(_hand)
		var _q = PhysicsRayQueryParameters3D.create(_from, _to)
		_q.exclude = _exclude
		_q.collision_mask = grapple_collision_mask
		var _pres = _space.intersect_ray(_q)
		if _pres:
			_hitmarker.global_transform = Transform3D(Basis(), _pres.position)
			_hitmarker.visible = true
		else:
			_hitmarker.visible = false
	# Launch grapple
	if trigger_pressed and not _is_hooked:
		var from = controller_transform.origin
		var forward_vec: Vector3 = controller_transform.basis.z
		var aim_dir: Vector3 = forward_vec.normalized() * -1.0
		var to = from + aim_dir * max_distance
		var space = get_world_3d().direct_space_state
		var exclude = [self]
		if is_instance_valid(_hand):
			exclude.append(_hand)
		var query = PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = exclude
		query.collision_mask = grapple_collision_mask
		var res = space.intersect_ray(query)
		if res:
			_is_hooked = true
			_hook_point = res.position
			_hook_object = res.collider
			if is_instance_valid(_hook_object) and _hook_object is Node3D:
				# store offset in object-local coordinates so it moves with rotation and scale
				_hook_local_offset = (_hook_object as Node3D).to_local(_hook_point)
			else:
				_hook_local_offset = Vector3.ZERO
			if enable_debug_logs:
				print("GrappleHook: hooked at", _hook_point, "collider=", _hook_object)
			# Use the object's local offset to calculate the actual world hook point to apply the initial
			# impulse toward the dynamic surface point if the object moves/rotates.
			var world_hook_point: Vector3 = _hook_point
			if is_instance_valid(_hook_object) and _hook_object is Node3D:
				world_hook_point = (_hook_object as Node3D).to_global(_hook_local_offset)
			# Apply initial impulse to the player body if available, towards live world hook point
			if is_instance_valid(_player_body):
				var impulse = (world_hook_point - _player_body.global_transform.origin).normalized() * impulse_speed
				_player_body.apply_central_impulse(impulse)
			# Ensure hitmarker stays at the actual hook location once hooked
			if is_instance_valid(_hitmarker):
				_hitmarker.visible = true
				if is_instance_valid(_hook_object) and _hook_object is Node3D:
					_hitmarker.global_transform = Transform3D(Basis(), (_hook_object as Node3D).to_global(_hook_local_offset))
				else:
					_hitmarker.global_transform = Transform3D(Basis(), _hook_point)


	# While hooked, apply winch force
	if _is_hooked:
		if not trigger_pressed:
			_end_grapple()
		else:
			# Compute a live world hook point that updates as the hooked object moves/rotates
			var live_hook_point: Vector3 = _hook_point
			if is_instance_valid(_hook_object) and _hook_object is Node3D:
				live_hook_point = (_hook_object as Node3D).to_global(_hook_local_offset)

			# Update hitmarker while hooked
			if is_instance_valid(_hitmarker):
				_hitmarker.visible = true
				_hitmarker.global_transform = Transform3D(Basis(), live_hook_point)

			# Position and orient a thin cylinder between controller and hook point
			# Draw curved rope using quadratic bezier segmentation
			var rope_start: Vector3 = controller_transform.origin
			var rope_end: Vector3 = live_hook_point
			var v: Vector3 = rope_end - rope_start
			var length: float = v.length()
			if length > 0.001:
				# Compute cubic Bezier control points to get a tensioned rope with straighter ends
				var sag_amount: float = clamp(length * rope_sag_factor, 0.0, rope_sag_max)
				# direction from start to end
				var curve_dir: Vector3 = v.normalized()
				# p0 = start, p3 = end
				var p0: Vector3 = rope_start
				var p3: Vector3 = rope_end
				# control points near both ends to enforce stiffness
				# For the start control, allow a minimum forward offset in the controller's forward direction
				var controller_forward: Vector3 = Vector3.ZERO
				if is_instance_valid(_controller) and _controller is Node3D:
					controller_forward = ((_controller as Node3D).global_transform.basis.z).normalized() * -1.0
				else:
					controller_forward = curve_dir
				# pick distance for p1 using stiffness or a minimum forward length
				var desired_p1_dist: float = max(length * rope_start_stiffness, rope_start_min_length)
				# clamp to a safe fraction of the rope length so p1 doesn't cross p2
				desired_p1_dist = clamp(desired_p1_dist, 0.001, length * 0.45)
				var p1: Vector3 = p0 + controller_forward * desired_p1_dist
				var p2: Vector3 = p3 - curve_dir * (length * rope_end_stiffness)
				# ensure p2 also doesn't cross p1
				var p2_dist = (p3 - p2).length()
				if p2_dist < desired_p1_dist:
					# push back p2 so it remains after p1
					p2 = p3 - curve_dir * (length * rope_end_stiffness + (desired_p1_dist - p2_dist))
				# apply sag bias - move both controls downward to create center sag; bias can push p1 a little less than p2
				p1 += Vector3.DOWN * (sag_amount * (rope_mid_sag_bias * 0.5))
				p2 += Vector3.DOWN * (sag_amount * (rope_mid_sag_bias * 1.0))
				# sample points along cubic bezier (S-like curvature)
				var points: Array = []
				for i in range(rope_segments + 1):
					var t: float = float(i) / rope_segments
					# cubic bezier formula
					var mt: float = 1.0 - t
					var p: Vector3 = mt * mt * mt * p0 + 3.0 * mt * mt * t * p1 + 3.0 * mt * t * t * p2 + t * t * t * p3
					points.append(p)
				# update segments
				for i in range(rope_segments):
					var a: Vector3 = points[i]
					var b: Vector3 = points[i + 1]
					var seg = _rope_segments_arr[i]
					if not is_instance_valid(seg):
						continue
					var seg_v: Vector3 = b - a
					var seg_length: float = seg_v.length()
					if seg_length <= 0.0001:
						seg.visible = false
						continue
					# compute orientation basis (Y aligns with seg_v)
					var seg_dir = seg_v / seg_length
					var up = Vector3.UP
					if abs(seg_dir.dot(up)) > 0.999:
						up = Vector3.FORWARD
					var right = up.cross(seg_dir).normalized()
					var forward = seg_dir.cross(right).normalized()
					var seg_basis = Basis(right, seg_dir, forward)
					var seg_mid = a + seg_v * 0.5
					seg.global_transform = Transform3D(seg_basis, seg_mid)
					seg.scale = Vector3(rope_thickness, seg_length, rope_thickness)
					seg.visible = true
			else:
				# hide segments
				for seg in _rope_segments_arr:
					if is_instance_valid(seg):
						seg.visible = false

			# Apply winch force toward the live hook point
			if is_instance_valid(_player_body):
				var to_hook = live_hook_point - _player_body.global_transform.origin
				var dist = to_hook.length()
				if dist > 0.1:
					var dir2 = to_hook.normalized()
					var vdot = _player_body.linear_velocity.dot(dir2)
					if vdot < winch_speed:
						var force = dir2 * (_player_body.mass * (winch_speed - vdot)) * delta * 8.0
						_player_body.apply_central_impulse(force)
			if enable_debug_logs:
				print("GrappleHook(frame): player=", _player_body.global_transform.origin, ", hook=", live_hook_point)

func _exit_tree() -> void:
	_end_grapple()
	if is_instance_valid(_hitmarker):
		_hitmarker.queue_free()
	if is_instance_valid(_rope_visual):
		_rope_visual.queue_free()
	if is_instance_valid(_rope_container):
		_rope_container.queue_free()
	for seg in _rope_segments_arr:
		if is_instance_valid(seg):
			seg.queue_free()
	if _rope_cylinder:
		_rope_cylinder = null
