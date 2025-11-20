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
@onready var head_mesh: MeshInstance3D = $PlayerBody/XROrigin3D/XRCamera3D/HeadArea/HeadMesh

# Networking
const NETWORK_PLAYER_SCENE = preload("res://multiplayer/NetworkPlayer.tscn")
var network_manager: Node = null
var remote_players: Dictionary = {} # peer_id -> NetworkPlayer instance
var update_rate: float = 0.05 # 20 Hz (50ms between updates)
var time_since_last_update: float = 0.0

# Voice chat
var microphone: AudioStreamMicrophone = null
var microphone_player: AudioStreamPlayer = null
var voice_effect: AudioEffectCapture = null
var voice_enabled: bool = false

# Player settings
var player_height := 0.0  # Using headset tracking; keep 0 to avoid artificial offset
var is_vr_mode := false
@export var head_radius: float = 0.18
var _desktop_trigger_event: InputEventMouseButton = null
@export var show_head_mesh: bool = true
@export var desktop_extra_collider_enabled: bool = true
@export var desktop_extra_collider_height: float = 1.2
@export var desktop_extra_collider_radius: float = 0.2
@export var desktop_extra_collider_offset: Vector3 = Vector3(0, 1.15, 0)

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
	
	# Ensure physics hands are properly connected
	call_deferred("_setup_physics_hands")
	
	# Add to group for easy finding
	add_to_group("xr_player")
	
	# Setup networking
	_setup_networking()


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
	
	# Update network with player transforms
	_update_networking(delta)
	
	# Process voice chat if enabled
	if voice_enabled:
		_process_voice_chat(delta)


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
			# restore angular velocity as well (avoid changing spin during rotation)
			player_body.angular_velocity = av
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

	# Remove desktop-only extra collider when in VR
	_remove_desktop_extra_collider()
	
	# Disable center pointer on VR
	var center_ptr = get_node_or_null("PlayerBody/DesktopCamera/CenterPointer")
	if center_ptr:
		center_ptr.set_physics_process(false)
		center_ptr.hide()

	# Remove desktop left-mouse mapping for trigger_click
	if _desktop_trigger_event:
		if InputMap.has_action("trigger_click"):
			InputMap.action_erase_event("trigger_click", _desktop_trigger_event)
			_desktop_trigger_event = null


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

	# Ensure extra collider is present on desktop
	_ensure_desktop_extra_collider()

	# Show center pointer on desktop
	var center_ptr = get_node_or_null("PlayerBody/DesktopCamera/CenterPointer")
	if center_ptr:
		center_ptr.show()
		center_ptr.set_physics_process(true)

	# Bind left mouse button to `trigger_click` when in desktop mode so left-click acts like trigger
	if not InputMap.has_action("trigger_click"):
		InputMap.add_action("trigger_click")
	# Add mouse button mapping if not already present
	if _desktop_trigger_event == null:
		var me := InputEventMouseButton.new()
		me.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("trigger_click", me)
		_desktop_trigger_event = me


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


func _ensure_desktop_extra_collider() -> void:
	"""Create or update the desktop-only extra collider for a taller player."""
	if not desktop_extra_collider_enabled or not player_body:
		return
	var cs_name := "DesktopExtraCollision"
	var existing := player_body.get_node_or_null(cs_name) as CollisionShape3D
	# Build a capsule shape for the extra collider
	if existing:
		if existing.shape and existing.shape is CapsuleShape3D:
			var s := existing.shape as CapsuleShape3D
			s.height = desktop_extra_collider_height
			s.radius = desktop_extra_collider_radius
		existing.transform = Transform3D(Basis(), desktop_extra_collider_offset)
		return
	# Create a new shape
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.name = cs_name
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.height = desktop_extra_collider_height
	cap.radius = desktop_extra_collider_radius
	cs.shape = cap
	cs.transform = Transform3D(Basis(), desktop_extra_collider_offset)
	player_body.add_child(cs)
	# Set owner so it persists in the scene if editing
	cs.owner = owner


func _remove_desktop_extra_collider() -> void:
	var cs_name := "DesktopExtraCollision"
	var existing := player_body.get_node_or_null(cs_name)
	if existing:
		existing.queue_free()


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


func _handle_smooth_turn(input: float, _delta: float) -> void:
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


# ============================================================================
# Networking Functions
# ============================================================================

func _setup_networking() -> void:
	"""Initialize networking connections"""
	network_manager = get_node_or_null("/root/NetworkManager")
	
	if not network_manager:
		print("XRPlayer: NetworkManager not found, multiplayer disabled")
		return
	
	# Connect to network events
	network_manager.player_connected.connect(_on_player_connected)
	network_manager.player_disconnected.connect(_on_player_disconnected)
	network_manager.avatar_texture_received.connect(_on_avatar_texture_received)
	
	# Setup voice chat
	_setup_voice_chat()
	
	print("XRPlayer: Networking initialized")


func _update_networking(delta: float) -> void:
	"""Send player transform updates to network and update remote players"""
	if not network_manager or not network_manager.multiplayer.multiplayer_peer:
		return
	
	# Throttle updates to update_rate
	time_since_last_update += delta
	if time_since_last_update < update_rate:
		return
	
	time_since_last_update = 0.0
	
	# Get local player transforms
	var head_pos = Vector3.ZERO
	var head_rot = Vector3.ZERO
	var left_pos = Vector3.ZERO
	var left_rot = Vector3.ZERO
	var right_pos = Vector3.ZERO
	var right_rot = Vector3.ZERO
	
	if is_vr_mode and xr_camera:
		head_pos = xr_camera.global_position
		head_rot = xr_camera.global_rotation_degrees
	elif desktop_camera:
		head_pos = desktop_camera.global_position
		head_rot = desktop_camera.global_rotation_degrees
	
	if is_vr_mode:
		if left_controller:
			left_pos = left_controller.global_position
			left_rot = left_controller.global_rotation_degrees
		if right_controller:
			right_pos = right_controller.global_position
			right_rot = right_controller.global_rotation_degrees
	else:
		# Desktop mode - use camera position for hands (or hide them)
		left_pos = head_pos + Vector3(-0.3, -0.3, 0.0)
		right_pos = head_pos + Vector3(0.3, -0.3, 0.0)
	
	# Get player scale
	var player_scale = player_body.scale if player_body else Vector3.ONE
	
	# Send to NetworkManager
	network_manager.update_local_player_transform(
		head_pos, head_rot,
		left_pos, left_rot,
		right_pos, right_rot,
		player_scale
	)
	
	# Update remote player visuals
	_update_remote_players()


func _update_remote_players() -> void:
	"""Update all remote player visual representations"""
	if not network_manager:
		return
	
	for peer_id in network_manager.players.keys():
		# Skip our own ID
		if peer_id == network_manager.get_multiplayer_id():
			continue
		
		var player_data = network_manager.players[peer_id]
		
		# Create remote player if doesn't exist
		if not remote_players.has(peer_id):
			_spawn_remote_player(peer_id)
		
		# Update remote player transforms
		if remote_players.has(peer_id):
			remote_players[peer_id].update_from_network_data(player_data)


func _despawn_remote_player(peer_id: int) -> void:
	"""Remove a remote player's visual representation"""
	if remote_players.has(peer_id):
		remote_players[peer_id].queue_free()
		remote_players.erase(peer_id)
		print("XRPlayer: Despawned remote player ", peer_id)


func _on_player_connected(peer_id: int) -> void:
	"""Handle new player connection"""
	print("XRPlayer: Player connected: ", peer_id)
	_spawn_remote_player(peer_id)
	
	# Send our avatar to the new player
	call_deferred("send_avatar_texture")


func _on_player_disconnected(peer_id: int) -> void:
	"""Handle player disconnection"""
	print("XRPlayer: Player disconnected: ", peer_id)
	_despawn_remote_player(peer_id)


## Send avatar texture to network
func send_avatar_texture() -> void:
	"""Send local player's avatar texture to all other players"""
	if not network_manager:
		return
	
	# Try multiple ways to find GridPainter
	var grid_painter = get_node_or_null("GridPainter")
	if not grid_painter:
		grid_painter = get_tree().root.get_node_or_null("MainScene/GridPainterTest")
	if not grid_painter:
		grid_painter = get_tree().root.get_node_or_null("MainScene/GridPainter")
	if not grid_painter:
		# Try finding by type or class name
		for node in get_tree().get_nodes_in_group("grid_painter"):
			grid_painter = node
			break
	if not grid_painter:
		# Last resort: search for GridPainter type
		var root = get_tree().root
		for child in root.get_children():
			if child is Node3D:
				var found = _find_grid_painter_recursive(child)
				if found:
					grid_painter = found
					break
	
	if not grid_painter:
		print("XRPlayer: GridPainter not found, cannot send avatar")
		return
	
	# Get head surface texture
	if not grid_painter.has_method("_get_surface"):
		print("XRPlayer: GridPainter doesn't have _get_surface method")
		return
	
	var head_surface = grid_painter._get_surface("head")
	if not head_surface or not head_surface.texture:
		print("XRPlayer: No head texture found, paint your head first!")
		return
	
	network_manager.set_local_avatar_texture(head_surface.texture)
	print("XRPlayer: Sent avatar texture to network")


func _find_grid_painter_recursive(node: Node) -> Node:
	"""Recursively search for GridPainter in the scene tree"""
	if node.get_script():
		var script = node.get_script()
		if script and script.has_method("_get_surface"):
			return node
	
	for child in node.get_children():
		var found = _find_grid_painter_recursive(child)
		if found:
			return found
	
	return null


## Update remote player avatars when they connect
func _spawn_remote_player(peer_id: int) -> void:
	"""Spawn a visual representation of a remote player"""
	var remote_player = NETWORK_PLAYER_SCENE.instantiate()
	remote_player.peer_id = peer_id
	remote_player.name = "RemotePlayer_" + str(peer_id)
	
	# Add to scene
	get_tree().root.add_child(remote_player)
	remote_players[peer_id] = remote_player
	
	print("XRPlayer: Spawned remote player ", peer_id)
	
	# Try to apply their avatar texture
	call_deferred("_apply_remote_avatar", peer_id)


func _apply_remote_avatar(peer_id: int) -> void:
	"""Apply avatar texture to a remote player"""
	if not network_manager or not remote_players.has(peer_id):
		return
	
	var texture = network_manager.get_player_avatar_texture(peer_id)
	if texture:
		remote_players[peer_id].apply_avatar_texture(texture)
		print("XRPlayer: Applied avatar to remote player ", peer_id)


func _on_avatar_texture_received(peer_id: int) -> void:
	"""Called when a remote player's avatar texture is received"""
	print("XRPlayer: Avatar texture received for peer ", peer_id)
	_apply_remote_avatar(peer_id)


# ============================================================================
# Voice Chat Functions
# ============================================================================

func _setup_voice_chat() -> void:
	"""Initialize microphone capture for voice chat"""
	# Create microphone stream
	microphone = AudioStreamMicrophone.new()
	
	# Create audio player for microphone (we just use it for capture)
	microphone_player = AudioStreamPlayer.new()
	microphone_player.name = "MicrophonePlayer"
	microphone_player.stream = microphone
	microphone_player.bus = "Voice"
	add_child(microphone_player)
	
	# Add AudioEffectCapture to Voice bus
	var voice_bus_index = AudioServer.get_bus_index("Voice")
	if voice_bus_index != -1:
		# Check if capture effect already exists
		var has_capture = false
		for i in range(AudioServer.get_bus_effect_count(voice_bus_index)):
			if AudioServer.get_bus_effect(voice_bus_index, i) is AudioEffectCapture:
				voice_effect = AudioServer.get_bus_effect(voice_bus_index, i)
				has_capture = true
				break
		
		if not has_capture:
			voice_effect = AudioEffectCapture.new()
			AudioServer.add_bus_effect(voice_bus_index, voice_effect)
		
		print("XRPlayer: Voice chat initialized")


func toggle_voice_chat(enabled: bool) -> void:
	"""Enable or disable voice chat"""
	voice_enabled = enabled
	
	if network_manager:
		network_manager.enable_voice_chat(enabled)
	
	if enabled and microphone_player:
		microphone_player.play()
	elif microphone_player:
		microphone_player.stop()
	
	print("XRPlayer: Voice chat ", "enabled" if enabled else "disabled")


func _process_voice_chat(delta: float) -> void:
	"""Capture and send voice data"""
	if not voice_enabled or not voice_effect or not network_manager:
		return
	
	# Get available audio frames from capture
	var available = voice_effect.get_frames_available()
	if available > 0:
		# Get audio samples (limit to reasonable buffer size)
		var frames_to_get = min(available, 2048)
		var audio_data = voice_effect.get_buffer(frames_to_get)
		
		if audio_data.size() > 0:
			# Send to network
			network_manager.send_voice_data(audio_data)
