# XRPlayer Scene
# Manages the XR player including camera, controllers, and physics hands
# Supports both VR and desktop modes
extends Node3D

@onready var player_body: RigidBody3D = $PlayerBody
@onready var xr_origin: XROrigin3D = $PlayerBody/XROrigin3D
@onready var xr_camera: XRCamera3D = $PlayerBody/XROrigin3D/XRCamera3D
@onready var left_controller: XRController3D = $PlayerBody/XROrigin3D/LeftController
@onready var right_controller: XRController3D = $PlayerBody/XROrigin3D/RightController
@onready var desktop_camera: Camera3D = $PlayerBody/DesktopCamera
@onready var desktop_controller: Node = $PlayerBody/DesktopController
@onready var physics_hand_left: RigidBody3D = $PhysicsHandLeft
@onready var physics_hand_right: RigidBody3D = $PhysicsHandRight
@onready var head_area: Area3D = $PlayerBody/XROrigin3D/XRCamera3D/HeadArea
@onready var head_collision_shape: CollisionShape3D = $PlayerBody/XROrigin3D/XRCamera3D/HeadArea/HeadCollisionShape
@onready var head_mesh: MeshInstance3D = $PlayerBody/XROrigin3D/XRCamera3D/HeadMesh

# Player settings
var player_height := 0.0  # Using headset tracking; keep 0 to avoid artificial offset
var is_vr_mode := false
@export var head_radius: float = 0.18
@export var show_head_mesh: bool = true

# Turning settings
enum TurnMode { SNAP, SMOOTH }
@export var turn_mode: TurnMode = TurnMode.SNAP
@export var snap_turn_angle: float = 45.0  # Degrees per snap turn
@export var smooth_turn_speed: float = 90.0  # Degrees per second
@export var turn_deadzone: float = 0.5  # Thumbstick deadzone for turning
@export var snap_turn_cooldown: float = 0.3  # Seconds between snap turns

# Turning state
var can_snap_turn := true
var snap_turn_timer := 0.0
var _pending_snap_angle := 0.0
var _smooth_input := 0.0


func _ready() -> void:
	# Wait for XR origin to initialize
	if xr_origin:
		xr_origin.vr_mode_active.connect(_on_vr_mode_changed)
		# Check initial state
		call_deferred("_check_initial_mode")

	if head_collision_shape and head_collision_shape.shape and head_collision_shape.shape is SphereShape3D:
		head_collision_shape.shape.radius = head_radius
	
	if head_mesh:
		head_mesh.visible = show_head_mesh
	
	# Restore saved headmesh texture
	call_deferred("_restore_head_texture")
	
	# Ensure physics hands are properly connected
	call_deferred("_setup_physics_hands")


func _setup_physics_hands() -> void:
	"""Ensure physics hands have valid references after scene transitions"""
	if not physics_hand_left or not physics_hand_right:
		# Try to find them if references are lost
		physics_hand_left = get_node_or_null("PhysicsHandLeft")
		physics_hand_right = get_node_or_null("PhysicsHandRight")
	
	if physics_hand_left:
		physics_hand_left.player_rigidbody = player_body
		physics_hand_left.target = left_controller
		print("XRPlayer: Physics hand left connected")
	
	if physics_hand_right:
		physics_hand_right.player_rigidbody = player_body
		physics_hand_right.target = right_controller
		print("XRPlayer: Physics hand right connected")


func _process(delta: float) -> void:
	if is_vr_mode:
		_handle_turning(delta)


func _physics_process(delta: float) -> void:
	# Apply any pending rotation to the physics body during the physics step
	if player_body:
		# Apply snap rotation if pending
		if abs(_pending_snap_angle) > 0.001:
			var lv = player_body.linear_velocity
			var av = player_body.angular_velocity
			player_body.rotate_y(deg_to_rad(_pending_snap_angle))
			# restore linear velocity so rotation doesn't alter falling
			player_body.linear_velocity = lv
			# clear pending
			_pending_snap_angle = 0.0

		# Apply smooth rotation based on input
		if abs(_smooth_input) > 0.001:
			var turn_amount = -_smooth_input * smooth_turn_speed * delta
			var lv2 = player_body.linear_velocity
			player_body.rotate_y(deg_to_rad(turn_amount))
			player_body.linear_velocity = lv2

		# Head collision is now an Area3D parented to the XRCamera3D; it follows the headset automatically


func _check_initial_mode() -> void:
	"""Check initial VR mode after a frame"""
	if xr_origin and xr_origin.has_method("is_vr_mode"):
		_on_vr_mode_changed(xr_origin.is_vr_mode)
	else:
		# Default to checking if XR interface exists
		var xr_interface = XRServer.find_interface("OpenXR")
		_on_vr_mode_changed(xr_interface != null and xr_interface.is_initialized())


func _on_vr_mode_changed(vr_active: bool) -> void:
	"""Switch between VR and desktop mode"""
	is_vr_mode = vr_active
	
	if vr_active:
		print("XRPlayer: VR mode active")
		_activate_vr_mode()
	else:
		print("XRPlayer: Desktop mode active")
		_activate_desktop_mode()


func _activate_vr_mode() -> void:
	"""Enable VR camera and physics hands"""
	# Enable VR camera
	if xr_camera:
		xr_camera.current = true
	
	# Enable physics hands
	if physics_hand_left:
		physics_hand_left.show()
		physics_hand_left.set_physics_process(true)
	if physics_hand_right:
		physics_hand_right.show()
		physics_hand_right.set_physics_process(true)
	
	# Disable desktop controls
	if desktop_camera:
		desktop_camera.current = false
	if desktop_controller and desktop_controller.has_method("deactivate"):
		desktop_controller.deactivate()


func _activate_desktop_mode() -> void:
	"""Enable desktop camera and controls, disable VR hands"""
	# Enable desktop camera
	if desktop_camera:
		desktop_camera.current = true
	
	# Enable desktop controller
	if desktop_controller and desktop_controller.has_method("activate"):
		desktop_controller.activate(desktop_camera)
	
	# Disable physics hands
	if physics_hand_left:
		physics_hand_left.hide()
		physics_hand_left.set_physics_process(false)
	if physics_hand_right:
		physics_hand_right.hide()
		physics_hand_right.set_physics_process(false)


func teleport_to(target_position: Vector3) -> void:
	"""Teleport player to a new position"""
	if not player_body:
		return

	# To avoid physics impulse on placement (which can push the body back),
	# temporarily disable collisions for the PlayerBody, move it, wait a couple
	# physics frames for the new world to settle, then restore collisions and
	# clear velocities. This prevents collision response from the old velocity
	# or penetration resolving from throwing the player.
	var prev_layer: int = player_body.collision_layer
	var prev_mask: int = player_body.collision_mask

	player_body.collision_layer = 0
	player_body.collision_mask = 0
	player_body.global_position = target_position
	player_body.linear_velocity = Vector3.ZERO
	player_body.angular_velocity = Vector3.ZERO

	# Wait for physics to process the new placement so collisions settle
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Restore previous collision layers/masks and ensure velocities are zero
	player_body.collision_layer = prev_layer
	player_body.collision_mask = prev_mask
	player_body.linear_velocity = Vector3.ZERO
	player_body.angular_velocity = Vector3.ZERO


func get_camera_position() -> Vector3:
	"""Get the actual camera world position"""
	if is_vr_mode and xr_camera:
		return xr_camera.global_position
	elif desktop_camera:
		return desktop_camera.global_position
	elif player_body:
		return player_body.global_position
	return global_position


func get_camera_forward() -> Vector3:
	"""Get the camera's forward direction"""
	if is_vr_mode and xr_camera:
		return -xr_camera.global_transform.basis.z
	elif desktop_camera:
		return -desktop_camera.global_transform.basis.z
	return -global_transform.basis.z


func _handle_turning(delta: float) -> void:
	"""Handle VR turning input from right controller thumbstick"""
	if not right_controller:
		return
	
	# Update snap turn cooldown
	if snap_turn_timer > 0:
		snap_turn_timer -= delta
		if snap_turn_timer <= 0:
			can_snap_turn = true
	
	# Get thumbstick input for turning (horizontal axis)
	var turn_input = right_controller.get_vector2("primary")
	
	if abs(turn_input.x) > turn_deadzone:
		if turn_mode == TurnMode.SNAP:
			_handle_snap_turn(turn_input.x)
		else:  # SMOOTH
			_handle_smooth_turn(turn_input.x, delta)
	else:
		# Reset snap turn when thumbstick returns to center
		if turn_mode == TurnMode.SNAP and snap_turn_timer <= 0:
			can_snap_turn = true
		# Clear smooth input when centered
		_smooth_input = 0.0


func _handle_snap_turn(input: float) -> void:
	"""Handle snap turning"""
	if not can_snap_turn:
		return
	
	# Determine turn direction
	# Invert sign so pushing the thumbstick right (positive x) turns right
	var turn_angle = -snap_turn_angle if input > 0 else snap_turn_angle

	# Queue the snap rotation to be applied in physics step
	_pending_snap_angle = turn_angle

	# Start cooldown
	can_snap_turn = false
	snap_turn_timer = snap_turn_cooldown

	print("XRPlayer: Queued snap turn ", turn_angle, " degrees")


func _handle_smooth_turn(input: float, delta: float) -> void:
	"""Handle smooth turning"""
	# Store smooth input for physics step to apply
	_smooth_input = input


func apply_texture_to_head(texture: ImageTexture) -> void:
	"""Apply a texture to the head mesh"""
	if not head_mesh:
		print("XRPlayer: head_mesh is null, cannot apply texture")
		return
	
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_BACK  # Show front faces (outside)
	head_mesh.material_override = mat
	print("XRPlayer: Applied texture to head mesh, visible: ", head_mesh.visible, ", mesh: ", head_mesh.mesh)


func _restore_head_texture() -> void:
	"""Restore saved head texture from paint data on scene load"""
	if not SaveManager:
		return
	
	var paint_data := SaveManager.load_head_paint()
	if paint_data.is_empty():
		print("XRPlayer: No saved paint data to restore")
		return
	
	# Try to find the subdivided cube in the scene to trigger update
	var cube = get_tree().get_first_node_in_group("pointer_interactable")
	if cube and cube.has_method("_update_player_head_texture"):
		# Cube exists, let it handle the texture update
		cube._update_player_head_texture()
		print("XRPlayer: Head texture restored via painted cube")
	else:
		# No cube in scene, generate texture directly from saved data
		print("XRPlayer: No painted cube in scene, generating texture from saved data")
		_apply_saved_texture_directly(paint_data)


func _apply_saved_texture_directly(paint_data: Dictionary) -> void:
	"""Apply saved paint texture directly when no painted cube exists in scene"""
	if not head_mesh:
		return
	
	var subdivisions_meta: Variant = paint_data.get("subdivisions", 1)
	var cell_colors: Array = paint_data.get("cell_colors", [])

	if cell_colors.is_empty() or cell_colors.size() != 6:
		print("XRPlayer: Invalid cell colors data")
		return

	var face_dims: Array = []
	for face in cell_colors:
		if not (face is Array):
			print("XRPlayer: Malformed face data in saved colors")
			return
		var rows: Array = face
		var height: int = rows.size()
		if height == 0:
			print("XRPlayer: Saved face data missing rows")
			return
		var width: int = 0
		for row in rows:
			if not (row is Array):
				print("XRPlayer: Malformed row data in saved colors")
				return
			width = max(width, row.size())
		if width == 0:
			print("XRPlayer: Saved face data missing columns")
			return
		face_dims.append(Vector2i(width, height))

	if face_dims.size() != 6:
		print("XRPlayer: Unexpected face dimension count")
		return

	var column_faces := [
		[3, 1],
		[4, 0],
		[2, 5]
	]
	var row_faces := [
		[3, 4, 2],
		[1, 0, 5]
	]

	var col_widths: Array[int] = []
	for faces in column_faces:
		var width: int = 1
		for fi in faces:
			width = max(width, face_dims[fi].x)
		col_widths.append(width)

	var row_heights: Array[int] = []
	for faces in row_faces:
		var height: int = 1
		for fi in faces:
			height = max(height, face_dims[fi].y)
		row_heights.append(height)

	var tex_width: int = 0
	for width in col_widths:
		tex_width += width
	var tex_height: int = 0
	for height in row_heights:
		tex_height += height

	if tex_width <= 0 or tex_height <= 0:
		print("XRPlayer: Invalid texture dimensions computed from saved paint")
		return

	var img: Image = Image.create(tex_width, tex_height, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var col_offsets: Array[int] = []
	var acc: int = 0
	for width in col_widths:
		col_offsets.append(acc)
		acc += width
	var row_offsets: Array[int] = []
	acc = 0
	for height in row_heights:
		row_offsets.append(acc)
		acc += height

	var face_to_row := [1, 1, 0, 0, 0, 1]
	var face_to_col := [1, 0, 2, 0, 1, 2]

	for fi in range(6):
		var dims: Vector2i = face_dims[fi]
		var offset: Vector2i = Vector2i(col_offsets[face_to_col[fi]], row_offsets[face_to_row[fi]])
		var alloc_w: int = col_widths[face_to_col[fi]]
		var alloc_h: int = row_heights[face_to_row[fi]]
		var face_rows: Array = cell_colors[fi] as Array
		for iy in range(alloc_h):
			var sample_y: int = clamp(iy, 0, dims.y - 1)
			var row: Array = (face_rows[sample_y] as Array) if sample_y < face_rows.size() else []
			for ix in range(alloc_w):
				var sample_x: int = clamp(ix, 0, dims.x - 1)
				if sample_x < row.size():
					var color: Color = row[sample_x] as Color
					img.set_pixel(offset.x + ix, offset.y + iy, color)

	var texture: ImageTexture = ImageTexture.create_from_image(img)
	apply_texture_to_head(texture)
	print("XRPlayer: Applied saved texture directly (subdivisions=", subdivisions_meta, ", texture=", tex_width, "x", tex_height, ")")
