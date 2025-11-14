
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
var _rope_mesh: ImmediateMesh = null
var _rope_visual: MeshInstance3D = null
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

	# Create a rope visual with ImmediateMesh to show line from controller to hook
	_rope_mesh = ImmediateMesh.new()
	_rope_visual = MeshInstance3D.new()
	_rope_visual.mesh = _rope_mesh
	var rope_mat = StandardMaterial3D.new()
	rope_mat.flags_unshaded = true
	rope_mat.emission_enabled = true
	rope_mat.emission = rope_color
	rope_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rope_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rope_visual.material_override = rope_mat
	_rope_visual.visible = false
	_rope_visual.name = "GrappleRope"
	if root:
		root.call_deferred("add_child", _rope_visual)
	else:
		call_deferred("add_child", _rope_visual)

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

func _end_grapple() -> void:
	_is_hooked = false
	_hook_object = null
	# Hide the hitmarker when grappling ends (cleanup)
	if is_instance_valid(_hitmarker):
		_hitmarker.visible = false
	if is_instance_valid(_rope_visual):
		_rope_visual.visible = false
		if _rope_mesh:
			_rope_mesh.clear_surfaces()

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
		var dir: Vector3 = forward_vec.normalized() * -1.0
		var to = from + dir * max_distance
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

			# Draw rope from controller origin to live_hook_point using ImmediateMesh
			if is_instance_valid(_rope_mesh) and is_instance_valid(_rope_visual):
				var rope_start: Vector3 = controller_transform.origin
				var rope_end: Vector3 = live_hook_point
				_rope_visual.global_transform = Transform3D(Basis(), rope_start)
				_rope_mesh.clear_surfaces()
				_rope_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
				_rope_mesh.surface_add_vertex(Vector3.ZERO)
				_rope_mesh.surface_add_vertex(rope_end - rope_start)
				_rope_mesh.surface_end()
				_rope_visual.visible = true

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
	if _rope_mesh:
		_rope_mesh.clear_surfaces()
