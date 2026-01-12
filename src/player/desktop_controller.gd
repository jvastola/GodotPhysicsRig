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

# Desktop interaction component
var desktop_interaction: DesktopInteractionComponent


func _ready() -> void:
	# Get references
	player_body = get_parent() as RigidBody3D
	if not player_body:
		push_error("DesktopController must be child of RigidBody3D")
		return
		
	physics_hand_left = get_node_or_null("../../PhysicsHandLeft")
	physics_hand_right = get_node_or_null("../../PhysicsHandRight")
	
	# Get desktop interaction component
	desktop_interaction = get_node_or_null("../../DesktopInteractionComponent")


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
		
		# Setup desktop interaction component
		if desktop_interaction:
			var center_pointer = camera.get_node_or_null("CenterPointer")
			desktop_interaction.setup(camera, center_pointer)
			
			# Get VR hand pointers to disable them
			var left_pointer = get_node_or_null("../XROrigin3D/LeftController/HandPointer")
			var right_pointer = get_node_or_null("../XROrigin3D/RightController/HandPointer")
			desktop_interaction.set_hand_pointers(left_pointer, right_pointer)
			desktop_interaction.activate()


func deactivate() -> void:
	"""Deactivate desktop controls"""
	is_active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Deactivate desktop interaction
	if desktop_interaction:
		desktop_interaction.deactivate()
	
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
	
	# Note: Pickup input is now handled by DesktopInteractionComponent


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
