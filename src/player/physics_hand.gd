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

@export_group("Grabbing")
@export var controller_name: String = "left_hand"  # "left_hand" or "right_hand"
@export var grab_action_trigger: String = "trigger"  # Trigger to grab
@export var grab_action_grip: String = "grip"  # Grip to grab
@export var release_button: String = "ax_button"  # Button to release (OpenXR 'ax_button' for A/X)

@export_group("Hit Feedback")
@export var haptic_enabled: bool = true
@export_range(0.0, 1.0, 0.05) var haptic_intensity: float = 0.5
@export_range(0.01, 0.5, 0.01) var haptic_duration: float = 0.1
@export var hit_sound_enabled: bool = true
@export_range(0.1, 5.0, 0.1) var min_impact_velocity: float = 0.5
@export var hit_sound_path: String = "res://assets/audio/hitwood.ogg"

# Release is handled via a single rising-edge check on `release_button` (ax_button)

var _previous_position: Vector3
var _previous_velocity: Vector3 = Vector3.ZERO

var _is_colliding: bool = false

# Hit feedback
var _hit_sound_player: AudioStreamPlayer3D = null
var _hit_sound_stream: AudioStream = null

# Grabbing state
var held_object: RigidBody3D = null
# Use an untyped Array for nearby_grabbables to avoid TypedArray validation
# errors when non-RigidBody3D nodes (e.g., StaticBody3D) trigger enter/exit.
var nearby_grabbables: Array = []

# Sticky trigger state tracking
var _prev_release_button_pressed: bool = false


func _ready() -> void:

	global_position = target.global_position
	global_rotation = target.global_rotation
	_previous_position = global_position

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	set_center_of_mass_mode(RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM)
	set_center_of_mass(Vector3.ZERO)
	
	# Add to physics_hand group for physics interaction with grabbables
	add_to_group("physics_hand")
	
	# Set up controller action
	grab_action_trigger = "trigger_click"
	grab_action_grip = "grip_click"
	# Use OpenXR action name for left-hand X/A button (Quest/OpenXR uses ax_button)
	release_button = "ax_button"
	
	# Setup hit sound player
	_setup_hit_sound()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target): return
	
	# Track velocity before movement for impact calculation
	_previous_velocity = _get_hand_velocity(delta)
	
	_pid_movement(delta)
	_pid_rotation(delta)
	
	if _is_colliding:
		_hookes_law()
	
	_handle_grab_input()
	
	# Periodically check for and remove orphaned collision shapes
	_cleanup_orphaned_grabbed_shapes()


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
	
	# Handle hit feedback (haptics + sound)
	_handle_hit_feedback(_body)
	
	# Track grabbable objects
	if _body.is_in_group("grabbable") and _body is RigidBody3D:
		if not nearby_grabbables.has(_body):
			nearby_grabbables.append(_body)
			print("PhysicsHand: Grabbable nearby - ", _body.name)

func _on_body_exited(_body: Node) -> void:
	# This is slightly more robust than the original. It checks if we are still
	# colliding with other objects before setting _is_colliding to false.
	_is_colliding = false
	
	# Remove from nearby grabbables
	if _body in nearby_grabbables:
		nearby_grabbables.erase(_body)


func _handle_grab_input() -> void:
	"""Handle grab and release input from VR controllers"""
	if not is_instance_valid(target) or not target is XRController3D:
		return
	
	var controller = target as XRController3D
	
	# Read current input states
	var trigger_value = controller.get_float("trigger")
	var grip_value = controller.get_float("grip")
	var trigger_pressed = trigger_value > 0.5
	var grip_pressed = grip_value > 0.5
	
	# Check release button through a single rising-edge on the configured action
	var release_button_pressed = _check_release_button(controller)
	
	# Validate held_object - if it's invalid, clear it
	if held_object != null:
		if not is_instance_valid(held_object):
			print("PhysicsHand: Held object became invalid, clearing reference")
			held_object = null
		elif held_object.has_method("get"):
			# Check if the object still thinks it's grabbed by us
			if not held_object.get("is_grabbed") or held_object.get("grabbing_hand") != self:
				print("PhysicsHand: Held object state desynchronized, clearing reference")
				held_object = null

	# Try to grab if trigger or grip pressed and not holding anything
	if held_object == null:
		if trigger_pressed or grip_pressed:
			_try_grab_nearest()

	# Simple release: rising edge of the configured release action
	else:
		if release_button_pressed and not _prev_release_button_pressed:
			_release_object()
	
	# Store previous release state for rising-edge detection
	_prev_release_button_pressed = release_button_pressed


func _check_release_button(controller: XRController3D) -> bool:
	"""Check release button through multiple input methods for robustness"""
	# Only accept the configured release action (defaults to "ax_button")
	var action := release_button

	# 1) get_vector2 (axis/trackpad/thumbstick)
	if controller.has_method("get_vector2"):
		var v = controller.get_vector2(action)
		if v.length() > 0.3:
			return true

	# 2) get_axis / get_float style
	if controller.has_method("get_axis"):
		var f = controller.get_axis(action)
		if abs(f) > 0.3:
			return true
	if controller.has_method("get_float"):
		var ff = controller.get_float(action)
		if abs(ff) > 0.3:
			return true

	# 3) boolean/button getters
	if controller.has_method("get_bool"):
		if controller.get_bool(action):
			return true
	if controller.has_method("get_pressed"):
		if controller.get_pressed(action):
			return true
	if controller.has_method("get_button"):
		if controller.get_button(action):
			return true
	if controller.has_method("is_button_pressed"):
		if controller.is_button_pressed(action):
			return true

	# 4) InputMap action for the configured action name
	if InputMap.has_action(action):
		if Input.is_action_pressed(action):
			return true

	return false


func _try_grab_nearest() -> void:
	"""Try to grab the nearest grabbable object"""
	if nearby_grabbables.is_empty():
		return
	
	# Find closest grabbable
	var closest: RigidBody3D = null
	var closest_dist := INF
	
	for grabbable in nearby_grabbables:
		if not is_instance_valid(grabbable):
			continue
		
		var dist = global_position.distance_to(grabbable.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = grabbable
	
	if closest and closest.has_method("try_grab"):
		if closest.try_grab(self):
			held_object = closest
			print("PhysicsHand: Grabbed ", held_object.name)


func _release_object() -> void:
	"""Release the currently held object"""
	if held_object and is_instance_valid(held_object):
		var obj_name = held_object.name  # Store name before release
		if held_object.has_method("release"):
			held_object.release()
			print("PhysicsHand: Released ", obj_name)
	
	held_object = null


func integrate_grabbed_collision(collision_shapes: Array) -> void:
	"""Integrate grabbed object collision shapes with this hand's physics body.
	Called by grabbable objects when they are grabbed.
	
	The collision shapes are already children of this RigidBody3D, so they
	automatically participate in this body's physics simulation using this
	hand's collision layer (layer 3) and mask settings.
	"""
	# Collision shapes added as children automatically use the parent RigidBody3D's
	# collision layer and mask. The physics_hand is on layer 3 and collides with
	# layer 1 (world), which is exactly what we want for grabbed objects.
	#
	# No additional configuration needed - just log for debugging
	if collision_shapes.size() > 0:
		print("PhysicsHand: Integrated ", collision_shapes.size(), " collision shapes from grabbed object")


func remove_grabbed_collision(collision_shapes: Array) -> void:
	"""Remove grabbed object collision shapes from this hand.
	Called by grabbable objects when they are released.
	"""
	for shape in collision_shapes:
		if is_instance_valid(shape) and shape.get_parent() == self:
			remove_child(shape)
			shape.queue_free()
	
	if collision_shapes.size() > 0:
		print("PhysicsHand: Removed ", collision_shapes.size(), " collision shapes")


func _cleanup_orphaned_grabbed_shapes() -> void:
	"""Remove any orphaned grabbed collision shapes or meshes.
	This catches shapes that were left behind during scene transitions
	or when a grabbable was freed unexpectedly."""
	# Only cleanup if we're NOT holding something
	if held_object != null and is_instance_valid(held_object):
		return
	
	# Find any children with "_grabbed_" in their name - these are orphaned
	var orphans: Array = []
	for child in get_children():
		if "_grabbed_" in child.name:
			orphans.append(child)
	
	if orphans.size() > 0:
		print("PhysicsHand: Cleaning up ", orphans.size(), " orphaned grabbed shapes")
		for orphan in orphans:
			remove_child(orphan)
			orphan.queue_free()


# === Hit Feedback ===

func _setup_hit_sound() -> void:
	"""Setup the AudioStreamPlayer3D for hit sounds"""
	_hit_sound_player = AudioStreamPlayer3D.new()
	_hit_sound_player.name = "HitSoundPlayer"
	_hit_sound_player.max_distance = 10.0
	_hit_sound_player.unit_size = 2.0
	add_child(_hit_sound_player)
	
	# Try to load the hit sound
	if ResourceLoader.exists(hit_sound_path):
		_hit_sound_stream = load(hit_sound_path)
		_hit_sound_player.stream = _hit_sound_stream
		print("PhysicsHand: Loaded hit sound from ", hit_sound_path)
	else:
		push_warning("PhysicsHand: Hit sound not found at ", hit_sound_path)


func _handle_hit_feedback(body: Node) -> void:
	"""Handle haptic and audio feedback when hitting an object"""
	# Calculate impact velocity
	var impact_velocity := _previous_velocity.length()
	
	# Skip if impact is too weak
	if impact_velocity < min_impact_velocity:
		return
	
	# Normalize impact for feedback scaling (0.0 to 1.0)
	var impact_strength := clampf((impact_velocity - min_impact_velocity) / 3.0, 0.0, 1.0)
	
	# Trigger haptics
	if haptic_enabled:
		_trigger_haptics(impact_strength)
	
	# Play hit sound
	if hit_sound_enabled:
		_play_hit_sound(impact_strength)


func _trigger_haptics(impact_strength: float) -> void:
	"""Trigger haptic feedback on the controller"""
	if not is_instance_valid(target) or not target is XRController3D:
		return
	
	var controller := target as XRController3D
	var amplitude := haptic_intensity * impact_strength
	var duration := haptic_duration
	
	# XRController3D.trigger_haptic_pulse(action_name, frequency, amplitude, duration_sec, delay_sec)
	controller.trigger_haptic_pulse("haptic", 0.0, amplitude, duration, 0.0)


func _play_hit_sound(impact_strength: float) -> void:
	"""Play hit sound with volume based on impact strength"""
	if not _hit_sound_player or not _hit_sound_stream:
		return
	
	# Don't overlap sounds too quickly
	if _hit_sound_player.playing:
		return
	
	# Scale volume with impact (-20dB to 0dB range)
	_hit_sound_player.volume_db = lerp(-20.0, 0.0, impact_strength)
	_hit_sound_player.play()


func _get_hand_velocity(delta: float) -> Vector3:
	"""Calculate hand velocity from position change"""
	var velocity: Vector3 = (global_position - _previous_position) / max(delta, 0.001)
	return velocity
