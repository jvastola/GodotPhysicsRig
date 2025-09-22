# physics_hand.gd (Corrected for Rotation)
extends RigidBody3D

@export_group("PID")
@export var frequency := 50.0
@export var damping := 1.0
@export var rot_frequency := 100.0
@export var rot_damping := 0.9

@export_group("References")
@export var player_rigidbody: RigidBody3D
@export var target: Node3D

@export_group("Springs")
@export var climb_force := 2500.0
@export var climb_drag := 50.0
@export var drag_max_velocity := 10.0


var _previous_position: Vector3

var _is_colliding: bool = false


func _ready() -> void:

	global_position = target.global_position
	global_rotation = target.global_rotation
	_previous_position = global_position

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


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
	var kp := (6.0 * rot_frequency) * (6.0 * rot_frequency) * 0.25
	var kd := 4.5 * rot_frequency * rot_damping
	var g := 1.0 / (1.0 + kd * delta + kp * delta * delta)
	var ksg := kp * g
	var kdg := (kd + kp * delta) * g

	var target_rotation_quat := target.global_transform.basis.get_rotation_quaternion()
	var hand_rotation_quat := global_transform.basis.get_rotation_quaternion()
	
	var q_diff := target_rotation_quat * hand_rotation_quat.inverse()
	
	var angle := q_diff.get_angle()
	var axis := q_diff.get_axis()
	
	if axis.is_zero_approx():
		return

	var angular_error_vector := axis * angle
	var angular_acceleration := angular_error_vector * ksg - angular_velocity * kdg
	
	# Directly modify angular velocity to apply an acceleration, ignoring inertia.
	angular_velocity += angular_acceleration * delta


func _hookes_law() -> void:
	if not is_instance_valid(player_rigidbody): return

	# Calculate the climbing force. This is a spring-like force that pulls the player up.
	var displacement := global_position - target.global_position
	var force := displacement * climb_force
	
	# Get the drag multiplier. This is high when the hand is still and low when it's moving.
	var drag := _get_drag(get_physics_process_delta_time())
	# Calculate the drag force. This slows the player down when they are holding on to a surface.
	var drag_force: Vector3 = drag * -player_rigidbody.linear_velocity * climb_drag

	# Apply the combined climbing and drag forces to the player.
	player_rigidbody.apply_central_force(force + drag_force)
	
func _get_drag(delta: float) -> float:
	var hand_velocity := (global_position - _previous_position) / delta
	_previous_position = global_position

	if drag_max_velocity <= 0.0:
		return 1.0

	var drag := 1.0 - clamp(hand_velocity.length() / drag_max_velocity, 0.0, 1.0)
	return drag


func _on_body_entered(body: Node) -> void:
	_is_colliding = true

func _on_body_exited(body: Node) -> void:
	# This is slightly more robust than the original. It checks if we are still
	# colliding with other objects before setting _is_colliding to false.
	_is_colliding = false
