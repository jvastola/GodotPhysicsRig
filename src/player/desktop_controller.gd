# Desktop Controller
# Provides mouse look and keyboard movement for desktop mode
extends Node

@export var mouse_sensitivity := 0.003
@export var move_speed := 5.0
@export var sprint_multiplier := 2.0
@export var jump_velocity := 6.0

var player_body: RigidBody3D
var camera: Camera3D
var is_active := false

# Camera rotation
var camera_rotation := Vector3.ZERO

# Hand references
var physics_hand_left: RigidBody3D
var physics_hand_right: RigidBody3D
var original_left_target: Node3D
var original_right_target: Node3D
var desktop_left_target: Node3D
var desktop_right_target: Node3D


func _ready() -> void:
	# Get references
	player_body = get_parent() as RigidBody3D
	if not player_body:
		push_error("DesktopController must be child of RigidBody3D")
		return
		
	physics_hand_left = get_node_or_null("../../PhysicsHandLeft")
	physics_hand_right = get_node_or_null("../../PhysicsHandRight")


func activate(cam: Camera3D) -> void:
	"""Activate desktop controls with the specified camera"""
	is_active = true
	camera = cam
	
	# Capture mouse
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Set up camera
	if camera:
		camera.current = true
		camera_rotation = camera.rotation
		
		# Setup desktop hand targets
		if not desktop_left_target:
			desktop_left_target = Node3D.new()
			desktop_left_target.name = "DesktopLeftTarget"
			camera.add_child(desktop_left_target)
			desktop_left_target.position = Vector3(-0.3, -0.2, -0.5)

		if not desktop_right_target:
			desktop_right_target = Node3D.new()
			desktop_right_target.name = "DesktopRightTarget"
			camera.add_child(desktop_right_target)
			desktop_right_target.position = Vector3(0.3, -0.2, -0.5)

		# Switch targets
		if physics_hand_left:
			original_left_target = physics_hand_left.target
			physics_hand_left.target = desktop_left_target

		if physics_hand_right:
			original_right_target = physics_hand_right.target
			physics_hand_right.target = desktop_right_target


func deactivate() -> void:
	"""Deactivate desktop controls"""
	is_active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Restore targets
	if physics_hand_left and original_left_target:
		physics_hand_left.target = original_left_target
	if physics_hand_right and original_right_target:
		physics_hand_right.target = original_right_target


func _input(event: InputEvent) -> void:
	if not is_active or not camera:
		return
	
	# Mouse look
	if event is InputEventMouseMotion:
		camera_rotation.y -= event.relative.x * mouse_sensitivity
		camera_rotation.x -= event.relative.y * mouse_sensitivity
		camera_rotation.x = clamp(camera_rotation.x, -PI/2, PI/2)
		
		# Apply rotation to camera
		camera.rotation = camera_rotation
	
	# Release mouse on ESC
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			
	# Pickup input
	if event.is_action_pressed("pickup_left"):
		_handle_pickup(physics_hand_left)
	if event.is_action_pressed("pickup_right"):
		_handle_pickup(physics_hand_right)


func _physics_process(_delta: float) -> void:
	if not is_active or not player_body or not camera:
		return
	
	# Re-capture mouse if clicked
	if Input.is_action_just_pressed("ui_select") and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Get input direction
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	
	# Calculate movement direction relative to camera
	var forward := camera.global_transform.basis.z
	var right := camera.global_transform.basis.x
	
	# Keep movement on horizontal plane
	forward.y = 0
	right.y = 0
	forward = forward.normalized()
	right = right.normalized()
	
	var move_direction := (forward * input_dir.y + right * input_dir.x).normalized()
	
	# Apply movement speed
	var speed := move_speed
	if Input.is_action_pressed("sprint"):
		speed *= sprint_multiplier
	
	# Apply force for movement (arcade-style)
	if move_direction.length() > 0:
		var target_velocity := move_direction * speed
		var velocity_change := target_velocity - Vector3(player_body.linear_velocity.x, 0, player_body.linear_velocity.z)
		player_body.apply_central_force(velocity_change * player_body.mass * 10.0)
	
	# Apply damping when not moving
	else:
		var horizontal_velocity := Vector3(player_body.linear_velocity.x, 0, player_body.linear_velocity.z)
		player_body.apply_central_force(-horizontal_velocity * player_body.mass * 5.0)
	
	# Jump
	if Input.is_action_just_pressed("jump") and _is_on_ground():
		player_body.linear_velocity.y = jump_velocity


func _is_on_ground() -> bool:
	"""Simple ground check using a raycast"""
	var space_state := player_body.get_world_3d().direct_space_state
	if not space_state:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		player_body.global_position,
		player_body.global_position + Vector3(0, -1.2, 0)
	)
	query.collision_mask = 1  # World layer
	
	var result := space_state.intersect_ray(query)
	return not result.is_empty()


func _handle_pickup(hand: RigidBody3D) -> void:
	"""Handle pickup/drop action for a specific hand"""
	if not hand:
		return
		
	# If holding something, drop it
	if hand.get("held_object"):
		var obj = hand.get("held_object")
		if is_instance_valid(obj) and obj.has_method("release"):
			obj.release()
		return
	
	# Otherwise try to pick up
	var space_state := camera.get_world_3d().direct_space_state
	if not space_state:
		return
	# Raycast from center of screen
	var query := PhysicsRayQueryParameters3D.create(
		camera.global_position,
		camera.global_position - camera.global_transform.basis.z * 3.0 # 3 meters reach
	)
	# Collide with World (1) and Interactable (6) and maybe others?
	# Let's just use default mask or a broad one.
	# Grabbables are usually RigidBodies.
	query.collision_mask = 0xFFFFFFFF # Collide with everything
	query.exclude = [player_body, hand] # Exclude player and hand
	
	var result := space_state.intersect_ray(query)
	if not result.is_empty():
		var collider = result.collider
		if collider is RigidBody3D and collider.is_in_group("grabbable"):
			if collider.has_method("try_grab"):
				collider.try_grab(hand)
