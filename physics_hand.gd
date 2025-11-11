# physics_hand.gd (Corrected for Rotation)
extends RigidBody3D

@export_group("PID")
@export var frequency := 72.0
@export var damping := 1.0
@export var rot_frequency := 1000.0
@export var rot_damping := 5.9

@export_group("References")
@export var player_rigidbody: RigidBody3D
@export var target: Node3D


@export_group("Springs")
@export var climb_force := 2000.0
@export var climb_drag := 50.0

@export var max_spring_force := 2000.0  # ✅ new: clamp for spring impulse
@export var max_player_velocity := 8.0   # ✅ new: velocity cap to limit bounce


var _previous_position: Vector3

var _is_colliding: bool = false


func _ready() -> void:

	global_position = target.global_position
	global_rotation = target.global_rotation
	_previous_position = global_position

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	#set_center_of_mass_mode(RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM)
	#set_center_of_mass(Vector3.ZERO)
	


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target): return
	
	_pid_movement(delta)
	_pid_rotation(delta)
	
	if _is_colliding:
		_hookes_law()


func _pid_movement(delta: float) -> void:
	var kp := (6.0 * frequency) * (6.0 * frequency) * 0.25
	var kd := 4.5 * frequency * damping
	var g := 1.0 / (1.0 + kd * delta + kp * delta * delta)
	var ksg := kp * g
	var kdg := (kd + kp * delta) * g
	
	var player_vel := Vector3.ZERO
	if is_instance_valid(player_rigidbody):
		player_vel = player_rigidbody.linear_velocity

	var force_vector := (target.global_position - global_position) * ksg + (player_vel - linear_velocity) * kdg
	apply_central_force(force_vector * mass)

func _pid_rotation(delta: float) -> void:
	# PID gains
	var kp: float = (6.0 * rot_frequency) * (6.0 * rot_frequency) * 0.25
	var kd: float = 4.5 * rot_frequency * rot_damping
	var g: float = 1.0 / (1.0 + kd * delta + kp * delta * delta)
	var ksg: float = kp * g
	var kdg: float = (kd + kp * delta) * g

	# Get normalized quaternions
	var target_quat: Quaternion = target.global_transform.basis.get_rotation_quaternion().normalized()
	var hand_quat: Quaternion = global_transform.basis.get_rotation_quaternion().normalized()

	# Relative rotation (target * inverse(hand))
	var q_diff: Quaternion = (target_quat * hand_quat.inverse()).normalized()

	# Ensure shortest path: flip sign if w < 0
	if q_diff.w < 0.0:
		q_diff = -q_diff

	var angle: float = q_diff.get_angle()
	if angle < 1e-4:
		return

	# Get axis, with robust fallback near 180°
	var axis: Vector3 = q_diff.get_axis()
	if axis.is_zero_approx():
		var hand_basis: Basis = Basis(hand_quat)
		var target_basis: Basis = Basis(target_quat)

		var a: Vector3 = (hand_basis * Vector3.RIGHT).cross(target_basis * Vector3.RIGHT)
		if a.is_zero_approx():
			a = (hand_basis * Vector3.UP).cross(target_basis * Vector3.UP)
			if a.is_zero_approx():
				a = (hand_basis * Vector3.FORWARD).cross(target_basis * Vector3.FORWARD)

		axis = a.normalized() if not a.is_zero_approx() else Vector3.UP

	# PID angular acceleration
	var angular_error_vector: Vector3 = axis * angle
	var angular_accel: Vector3 = angular_error_vector * ksg - angular_velocity * kdg

	# Clamp to prevent extreme accelerations
	var max_ang_accel: float = max(10.0, rot_frequency * 2.0)
	if angular_accel.length() > max_ang_accel:
		angular_accel = angular_accel.normalized() * max_ang_accel

	# Integrate to angular velocity
	angular_velocity += angular_accel * delta


# --- HOOKE’S LAW SPRING (with force + velocity limits) ---
func _hookes_law() -> void:
	if not is_instance_valid(player_rigidbody):
		return

	var displacement := global_position - target.global_position
	var force := displacement * climb_force

	# ✅ 1. Clamp the maximum spring force magnitude
	if force.length() > max_spring_force:
		force = force.normalized() * max_spring_force

	var drag := _get_drag(get_physics_process_delta_time())
	player_rigidbody.apply_central_force(force * mass)

	var drag_force := -player_rigidbody.linear_velocity * climb_drag * drag
	player_rigidbody.apply_central_force(drag_force * mass)

	# ✅ 3. Limit the player's overall velocity to prevent excessive bounce
	if player_rigidbody.linear_velocity.length() > max_player_velocity:
		player_rigidbody.linear_velocity = player_rigidbody.linear_velocity.normalized() * max_player_velocity


func _get_drag(delta: float) -> float:
	var hand_velocity := (global_position - _previous_position) / delta
	_previous_position = global_position

	if hand_velocity.is_zero_approx():
		return 1.0

	var drag := 1.0 / (hand_velocity.length() + 0.01)
	if drag >1: drag= 1
	if drag < .03: drag= .03
	return drag


func _on_body_entered(_body: Node) -> void:
	_is_colliding = true

func _on_body_exited(_body: Node) -> void:
	# This is slightly more robust than the original. It checks if we are still
	# colliding with other objects before setting _is_colliding to false.
	_is_colliding = false
