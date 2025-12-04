# GrappleHook - Extends Grabbable with grapple gun functionality
# Allows the player to fire a grapple and winch toward the hook point
extends Grabbable

# GrappleHook specific properties
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
var _use_global_visuals: bool = false
var _global_visuals = null
var _hook_local_offset: Vector3 = Vector3.ZERO
var _rope_cylinder: CylinderMesh = null
var _rope_visual: MeshInstance3D = null
var _rope_line_mesh: ImmediateMesh = null
var _rope_line_instance: MeshInstance3D = null
@export var rope_thickness: float = 0.02
@export var rope_segments: int = 10
@export var rope_sag_factor: float = 0.5
@export var rope_sag_max: float = 2.0
var _rope_container: Node3D = null
var _rope_segments_arr: Array = []
var _last_rope_points: Array = []
@export var rope_start_stiffness: float = 0.05
@export var rope_end_stiffness: float = 0.05
@export var rope_mid_sag_bias: float = 1.0
@export var rope_start_min_length: float = 0.2
@export var rope_color: Color = Color8(255, 200, 80)
@export var use_line_visual: bool = true
var _visuals_pending_parent: bool = false
@export var persist_visuals_across_scenes: bool = true


func _ready() -> void:
	# Call parent Grabbable._ready() for standard grabbable setup
	super._ready()
	
	# Connect to our own signals for grapple-specific behavior
	grabbed.connect(_on_grabbed)
	released.connect(_on_released)

	# Get the HitTargetMarker node from the scene
	var hit_target_marker = get_node_or_null("HitTargetMarker")
	if hit_target_marker:
		_hitmarker = hit_target_marker.get_node_or_null("MarkerMesh")
		if _hitmarker:
			_hitmarker.visible = false
			if enable_debug_logs:
				print("GrappleHook: Using scene hitmarker node")
	
	# Detect global visuals manager (autoload) and use it if available
	_global_visuals = get_node_or_null("/root/GrappleVisuals")
	if _global_visuals:
		_use_global_visuals = true
		_global_visuals.init_segments(rope_segments)
	elif persist_visuals_across_scenes:
		# If the user didn't set GrappleVisuals as an autoload, create it now
		var gv_script = preload("res://src/objects/grabbables/GrappleVisuals.gd")
		if gv_script and not get_node_or_null("/root/GrappleVisuals"):
			var gv = gv_script.new()
			gv.name = "GrappleVisuals"
			get_tree().root.call_deferred("add_child", gv)
			_global_visuals = gv
			_use_global_visuals = true
			_global_visuals.call_deferred("init_segments", rope_segments)
	
	# Ensure root is available before attempting to attach visuals
	var root = get_tree().root
	if not root:
		call_deferred("_attach_visuals_to_root")
		return
	_attach_visuals_to_root()

	# Create rope visuals
	var rope_mat: StandardMaterial3D = null
	if _use_global_visuals:
		pass
	else:
		_rope_cylinder = CylinderMesh.new()
		_rope_cylinder.top_radius = 1.0
		_rope_cylinder.bottom_radius = 1.0
		_rope_cylinder.height = 1.0
		_rope_cylinder.radial_segments = 12
		_rope_visual = MeshInstance3D.new()
		_rope_visual.mesh = _rope_cylinder
		rope_mat = StandardMaterial3D.new()
		rope_mat.flags_unshaded = true
		rope_mat.emission_enabled = true
		rope_mat.emission = rope_color
		rope_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rope_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_rope_visual.material_override = rope_mat
		_rope_visual.visible = false
		_rope_visual.name = "GrappleRope"
	_attach_visuals_to_root()

	# Create rope segment container
	if not _use_global_visuals:
		_rope_container = Node3D.new()
		_rope_container.name = "GrappleRopeContainer"
		var root2 = get_tree().root
		if not root2:
			call_deferred("_attach_visuals_to_root")
		else:
			_attach_visuals_to_root()

	# Initialize segment MeshInstances
	if not _use_global_visuals:
		for i in range(rope_segments):
			var seg = MeshInstance3D.new()
			seg.mesh = _rope_cylinder
			seg.material_override = rope_mat
			seg.visible = false
			_rope_container.add_child(seg)
			_rope_segments_arr.append(seg)
		# Create line visual
		if use_line_visual:
			_rope_line_mesh = ImmediateMesh.new()
			_rope_line_instance = MeshInstance3D.new()
			_rope_line_instance.mesh = _rope_line_mesh
			var line_mat = StandardMaterial3D.new()
			line_mat.flags_unshaded = true
			line_mat.emission_enabled = true
			line_mat.emission = rope_color
			line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_rope_line_instance.material_override = line_mat
			_rope_line_instance.visible = false
			_rope_line_instance.name = "GrappleRopeLine"
			_attach_visuals_to_root()

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
	if is_instance_valid(_hitmarker):
		if _use_global_visuals and _global_visuals:
			pass
		else:
			_hitmarker.visible = true


func _on_released() -> void:
	_end_grapple()
	set_physics_process(false)
	if is_instance_valid(_hitmarker):
		if _use_global_visuals and _global_visuals:
			_global_visuals.hide_hitmarker()
		else:
			_hitmarker.visible = false
			if use_line_visual and is_instance_valid(_rope_line_instance):
				_rope_line_instance.visible = false
	if is_instance_valid(_rope_visual):
		if _use_global_visuals and _global_visuals:
			_global_visuals.hide_segments()
		else:
			_rope_visual.visible = false
		if _rope_cylinder:
			_rope_visual.scale = Vector3.ONE
			_rope_visual.mesh = _rope_cylinder
		if use_line_visual and is_instance_valid(_rope_line_instance):
			_rope_line_instance.visible = false


func _end_grapple() -> void:
	_is_hooked = false
	_hook_object = null
	if is_instance_valid(_hitmarker):
		if _use_global_visuals and _global_visuals:
			_global_visuals.hide_hitmarker()
		else:
			_hitmarker.visible = false
	if is_instance_valid(_rope_visual):
		if _use_global_visuals and _global_visuals:
			_global_visuals.hide_segments()
		else:
			_rope_visual.visible = false
		if _rope_cylinder:
			_rope_visual.mesh = _rope_cylinder
		if use_line_visual and is_instance_valid(_rope_line_instance):
			_rope_line_instance.visible = false

	# Hide segments on release
	if _use_global_visuals and _global_visuals:
		_global_visuals.hide_segments()
	else:
		for seg in _rope_segments_arr:
			if is_instance_valid(seg):
				seg.visible = false


func _physics_process(delta: float) -> void:
	# Call parent physics process for grabbable functionality
	super._physics_process(delta)
	
	# Ensure visuals are parented to the SceneTree root
	_ensure_visuals_parent()
	
	if not is_grabbed:
		return
	if not is_instance_valid(_hand):
		return

	# Determine controller transform
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

	# Prediction: while grabbed and not hooked, update hitmarker
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
			if _use_global_visuals and _global_visuals:
				_global_visuals.show_hitmarker(_pres.position)
			else:
				_hitmarker.global_transform = Transform3D(Basis(), _pres.position)
				_hitmarker.visible = true
				if use_line_visual and is_instance_valid(_rope_line_mesh) and is_instance_valid(_rope_line_instance):
					_rope_line_mesh.clear_surfaces()
					_rope_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
					_rope_line_mesh.surface_add_vertex(_from)
					_rope_line_mesh.surface_add_vertex(_pres.position)
					_rope_line_mesh.surface_end()
					_rope_line_instance.visible = true
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
				_hook_local_offset = (_hook_object as Node3D).to_local(_hook_point)
			else:
				_hook_local_offset = Vector3.ZERO
			if enable_debug_logs:
				print("GrappleHook: hooked at", _hook_point, "collider=", _hook_object)
			var world_hook_point: Vector3 = _hook_point
			if is_instance_valid(_hook_object) and _hook_object is Node3D:
				world_hook_point = (_hook_object as Node3D).to_global(_hook_local_offset)
			if is_instance_valid(_player_body):
				var impulse = (world_hook_point - _player_body.global_transform.origin).normalized() * impulse_speed
				_player_body.apply_central_impulse(impulse)
		# Update hitmarker position
		if _use_global_visuals and _global_visuals:
			_global_visuals.show_hitmarker(((_hook_object as Node3D).to_global(_hook_local_offset)) if is_instance_valid(_hook_object) and _hook_object is Node3D else _hook_point)
		elif is_instance_valid(_hitmarker):
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
			var live_hook_point: Vector3 = _hook_point
			if is_instance_valid(_hook_object) and _hook_object is Node3D:
				live_hook_point = (_hook_object as Node3D).to_global(_hook_local_offset)

			# Update hitmarker while hooked
			if _use_global_visuals and _global_visuals:
				_global_visuals.show_hitmarker(live_hook_point)
			elif is_instance_valid(_hitmarker):
				_hitmarker.visible = true
				_hitmarker.global_transform = Transform3D(Basis(), live_hook_point)

			# Draw rope
			var rope_start: Vector3 = controller_transform.origin
			var rope_end: Vector3 = live_hook_point
			var v: Vector3 = rope_end - rope_start
			var length: float = v.length()
			if length > 0.001:
				_draw_rope(rope_start, rope_end, length, v)
			else:
				_hide_rope_segments()
				
			# Hide line visual when segments are hidden
			if use_line_visual and is_instance_valid(_rope_line_instance):
				_rope_line_instance.visible = false

			# Apply winch force
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

			# Ensure visuals persist
			if _use_global_visuals and _global_visuals and persist_visuals_across_scenes:
				pass
			else:
				_ensure_visuals_parent()


func _draw_rope(rope_start: Vector3, rope_end: Vector3, length: float, v: Vector3) -> void:
	"""Draw the rope using cubic bezier segments"""
	var sag_amount: float = clamp(length * rope_sag_factor, 0.0, rope_sag_max)
	var curve_dir: Vector3 = v.normalized()
	var p0: Vector3 = rope_start
	var p3: Vector3 = rope_end
	
	var controller_forward: Vector3 = Vector3.ZERO
	if is_instance_valid(_controller) and _controller is Node3D:
		controller_forward = ((_controller as Node3D).global_transform.basis.z).normalized() * -1.0
	else:
		controller_forward = curve_dir
	
	var desired_p1_dist: float = max(length * rope_start_stiffness, rope_start_min_length)
	desired_p1_dist = clamp(desired_p1_dist, 0.001, length * 0.45)
	var p1: Vector3 = p0 + controller_forward * desired_p1_dist
	var p2: Vector3 = p3 - curve_dir * (length * rope_end_stiffness)
	var p2_dist = (p3 - p2).length()
	if p2_dist < desired_p1_dist:
		p2 = p3 - curve_dir * (length * rope_end_stiffness + (desired_p1_dist - p2_dist))
	p1 += Vector3.DOWN * (sag_amount * (rope_mid_sag_bias * 0.5))
	p2 += Vector3.DOWN * (sag_amount * (rope_mid_sag_bias * 1.0))
	
	var points: Array = []
	for i in range(rope_segments + 1):
		var t: float = float(i) / rope_segments
		var mt: float = 1.0 - t
		var p: Vector3 = mt * mt * mt * p0 + 3.0 * mt * mt * t * p1 + 3.0 * mt * t * t * p2 + t * t * t * p3
		points.append(p)
		_last_rope_points = points
	
	if points.size() < 2:
		_hide_rope_segments()
	else:
		_update_rope_segments(points)
		if use_line_visual and is_instance_valid(_rope_line_mesh) and is_instance_valid(_rope_line_instance):
			_rope_line_mesh.clear_surfaces()
			_rope_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			_rope_line_mesh.surface_add_vertex(rope_start)
			_rope_line_mesh.surface_add_vertex(rope_end)
			_rope_line_mesh.surface_end()
			_rope_line_instance.visible = true


func _update_rope_segments(points: Array) -> void:
	"""Update rope segment visuals from bezier points"""
	if _use_global_visuals and _global_visuals:
		_global_visuals.hide_segments()
		var seg_count: int = min(max(rope_segments, 0), max(0, points.size() - 1))
		for i in range(seg_count):
			var a: Vector3 = points[i]
			var b: Vector3 = points[i + 1]
			_global_visuals.update_segment(i, a, b, rope_thickness)
	else:
		var seg_count: int = min(max(rope_segments, 0), max(0, points.size() - 1))
		seg_count = min(seg_count, _rope_segments_arr.size())
		for i in range(seg_count):
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
		for j in range(seg_count, _rope_segments_arr.size()):
			var extra = _rope_segments_arr[j]
			if is_instance_valid(extra):
				extra.visible = false


func _hide_rope_segments() -> void:
	"""Hide all rope segments"""
	if _use_global_visuals and _global_visuals:
		_global_visuals.hide_segments()
	else:
		for seg in _rope_segments_arr:
			if is_instance_valid(seg):
				seg.visible = false


func _exit_tree() -> void:
	_end_grapple()
	if is_instance_valid(_hitmarker):
		_hitmarker.visible = false
	if is_instance_valid(_rope_visual):
		if persist_visuals_across_scenes:
			if _use_global_visuals and _global_visuals:
				_global_visuals.hide_segments()
			else:
				_rope_visual.visible = false
		else:
			_rope_visual.queue_free()
	if use_line_visual and is_instance_valid(_rope_line_instance):
		if persist_visuals_across_scenes:
			_rope_line_instance.visible = false
		else:
			_rope_line_instance.queue_free()
	if is_instance_valid(_rope_container):
		if persist_visuals_across_scenes:
			if _use_global_visuals and _global_visuals:
				_global_visuals.hide_segments()
			else:
				for seg in _rope_segments_arr:
					if is_instance_valid(seg):
						seg.visible = false
			_rope_container.visible = false
		else:
			_rope_container.queue_free()
	for seg in _rope_segments_arr:
		if is_instance_valid(seg):
			seg.queue_free()
	if _rope_cylinder:
		_rope_cylinder = null
	if _is_hooked and persist_visuals_across_scenes and _use_global_visuals and _global_visuals and _last_rope_points.size() > 0:
		_global_visuals.persist_rope(_last_rope_points, rope_thickness, 10.0)


func _ensure_visuals_parent() -> void:
	"""Reparent visuals to root for scene persistence"""
	var root = get_tree().root
	var _scheduled: bool = false
	
	if is_instance_valid(_rope_visual) and _rope_visual.get_parent() != root:
		if _visuals_pending_parent:
			pass
		else:
			if _rope_visual.get_parent():
				_rope_visual.get_parent().remove_child(_rope_visual)
			root.call_deferred("add_child", _rope_visual)
			_visuals_pending_parent = true
	if is_instance_valid(_rope_container) and _rope_container.get_parent() != root:
		if _visuals_pending_parent:
			pass
		else:
			if _rope_container.get_parent():
				_rope_container.get_parent().remove_child(_rope_container)
			root.call_deferred("add_child", _rope_container)
			_visuals_pending_parent = true
	if is_instance_valid(_rope_visual) and _rope_visual.get_parent() == root and is_instance_valid(_rope_container) and _rope_container.get_parent() == root:
		_visuals_pending_parent = false
	if use_line_visual and is_instance_valid(_rope_line_instance) and _rope_line_instance.get_parent() == root:
		_visuals_pending_parent = false
	if use_line_visual and is_instance_valid(_rope_line_instance) and _rope_line_instance.get_parent() != root:
		root.call_deferred("add_child", _rope_line_instance)
		_visuals_pending_parent = true


func _attach_visuals_to_root() -> void:
	"""Helper to attach visuals to root once"""
	if _visuals_pending_parent:
		return
	_visuals_pending_parent = true
	var root = get_tree().root
	if not root:
		call_deferred("_attach_visuals_to_root")
		return
	var scheduled: bool = false
	if not root:
		return
	
	if is_instance_valid(_rope_visual) and _rope_visual.get_parent() == null:
		root.call_deferred("add_child", _rope_visual)
		scheduled = true
	if is_instance_valid(_rope_container) and _rope_container.get_parent() == null:
		root.call_deferred("add_child", _rope_container)
		scheduled = true
	if use_line_visual and is_instance_valid(_rope_line_instance) and _rope_line_instance.get_parent() == null:
		root.call_deferred("add_child", _rope_line_instance)
		scheduled = true
	if scheduled:
		_visuals_pending_parent = true
