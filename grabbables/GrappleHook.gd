
extends "res://grabbable.gd"

@export var max_distance: float = 20.0
@export var impulse_speed: float = 12.0
@export var winch_speed: float = 4.0
@export var grapple_collision_mask: int = 1
@export var enable_debug_logs: bool = false

var _is_hooked: bool = false
var _hook_point: Vector3 = Vector3.ZERO
var _hook_object: Node = null
var _hand: RigidBody3D = null
var _controller: Node = null
var _player_body: RigidBody3D = null

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 10
	add_to_group("grabbable")
	body_entered.connect(_on_collision_entered)

	grabbed.connect(_on_grabbed)
	released.connect(_on_released)

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

func _on_released() -> void:
	_end_grapple()
	set_physics_process(false)

func _end_grapple() -> void:
	_is_hooked = false
	_hook_object = null

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
			if enable_debug_logs:
				print("GrappleHook: hooked at", _hook_point, "collider=", _hook_object)
			# Apply initial impulse to the player body if available
			if is_instance_valid(_player_body):
				var impulse = (_hook_point - _player_body.global_transform.origin).normalized() * impulse_speed
				_player_body.apply_central_impulse(impulse)

	# While hooked, apply winch force
	if _is_hooked:
		if not trigger_pressed:
			_end_grapple()
		else:
			if is_instance_valid(_player_body):
				var to_hook = _hook_point - _player_body.global_transform.origin
				var dist = to_hook.length()
				if dist > 0.1:
					var dir2 = to_hook.normalized()
					var vdot = _player_body.linear_velocity.dot(dir2)
					if vdot < winch_speed:
						var force = dir2 * (_player_body.mass * (winch_speed - vdot)) * delta * 8.0
						_player_body.apply_central_impulse(force)
			if enable_debug_logs:
				print("GrappleHook(frame): player=", _player_body.global_transform.origin, ", hook=", _hook_point)

func _exit_tree() -> void:
	_end_grapple()
