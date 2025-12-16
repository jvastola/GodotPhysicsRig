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
@onready var left_hand_mesh: Node3D = $PlayerBody/XROrigin3D/LeftController/LeftHandMesh
@onready var left_hand_pointer: Node3D = $PlayerBody/XROrigin3D/LeftController/HandPointer
@onready var left_watch: Node3D = $PlayerBody/XROrigin3D/LeftController/Watch
@onready var left_watch_face: Node3D = $PlayerBody/XROrigin3D/LeftController/Watch/WatchFace
@onready var left_watch_needle: Node3D = $PlayerBody/XROrigin3D/LeftController/Watch/Needle
@onready var left_watch_ray_visual: Node3D = $PlayerBody/XROrigin3D/LeftController/Watch/RayVisual
@onready var left_watch_ray_hit: Node3D = $PlayerBody/XROrigin3D/LeftController/Watch/RayHit
@onready var right_hand_mesh: Node3D = $PlayerBody/XROrigin3D/RightController/RightHandMesh
@onready var right_hand_pointer: Node3D = $PlayerBody/XROrigin3D/RightController/HandPointer
@onready var center_pointer: Node3D = $PlayerBody/DesktopCamera/CenterPointer
@onready var head_area: Area3D = $PlayerBody/XROrigin3D/XRCamera3D/HeadArea
@onready var head_collision_shape: CollisionShape3D = $PlayerBody/XROrigin3D/XRCamera3D/HeadArea/HeadCollisionShape
@onready var head_mesh: MeshInstance3D = $PlayerBody/XROrigin3D/XRCamera3D/HeadArea/HeadMesh

# Components
var network_component: PlayerNetworkComponent
var voice_component: PlayerVoiceComponent
var movement_component: PlayerMovementComponent
var simple_world_grab: SimpleWorldGrabComponent

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
@export var auto_scale_physics_hands: bool = true
@export var auto_scale_head: bool = true
@export var auto_scale_hand_visuals: bool = true

# Player scale tracking
var _manual_player_scale: float = 1.0
var _last_world_scale: float = 1.0
var _base_player_body_scale: Vector3 = Vector3.ONE
var _base_left_hand_scale: Vector3 = Vector3.ONE
var _base_right_hand_scale: Vector3 = Vector3.ONE
var _base_head_area_scale: Vector3 = Vector3.ONE
var _hand_visual_nodes: Array[Node3D] = []
var _base_hand_visual_scales: Dictionary = {}
var _base_hand_visual_transforms: Dictionary = {}

# Audio Listeners
var vr_listener: AudioListener3D = null
var desktop_listener: AudioListener3D = null


func _ready() -> void:
	_cache_base_scales()
	_last_world_scale = XRServer.world_scale
	_apply_rig_scale()

	# Initialize components
	_setup_components()

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
	
	# Setup audio listeners
	_setup_audio_listeners()


func _setup_components() -> void:
	# Get components from scene (they're now part of the XRPlayer.tscn)
	network_component = get_node_or_null("PlayerNetworkComponent")
	if network_component:
		network_component.setup(player_body, xr_camera, desktop_camera, left_controller, right_controller)
	else:
		push_warning("XRPlayer: PlayerNetworkComponent not found in scene")
	
	# Voice Component - now uses LiveKit instead of Nakama
	voice_component = get_node_or_null("PlayerVoiceComponent")
	if voice_component:
		# Find LiveKit manager in the scene
		var livekit_manager = _find_livekit_manager()
		if livekit_manager:
			voice_component.setup(livekit_manager)
			# Set scene root so voice component can find NetworkPlayers
			voice_component.set_player_scene_root(get_tree().root)
		else:
			push_warning("XRPlayer: LiveKit manager not found in scene")
	elif not voice_component:
		push_warning("XRPlayer: PlayerVoiceComponent not found in scene")
	
	# Movement Component - check if it already exists in scene first
	movement_component = get_node_or_null("PlayerMovementComponent")
	if movement_component:
		movement_component.setup(player_body, left_controller, right_controller, xr_camera, physics_hand_left, physics_hand_right)
	
	# Simple World Grab Component
	simple_world_grab = get_node_or_null("SimpleWorldGrabComponent")
	if simple_world_grab:
		simple_world_grab.setup(xr_origin, xr_camera, left_controller, right_controller)
		simple_world_grab.enabled = false  # Disabled by default, enable via UI


func _find_livekit_manager() -> Node:
	"""Find the LiveKit manager in the scene"""
	# Option 1: Look for LiveKitViewport3D and get its manager
	var root = get_tree().root
	var livekit_ui = _find_node_by_script(root, "livekit_ui.gd")
	if livekit_ui and livekit_ui.has_method("get") and "livekit_manager" in livekit_ui:
		return livekit_ui.livekit_manager
	
	# Option 2: Look for LiveKitManager directly
	var livekit_manager = _find_node_by_class(root, "LiveKitManager")
	if livekit_manager:
		return livekit_manager
	
	return null


func _find_node_by_script(node: Node, script_name: String) -> Node:
	"""Recursively find a node by its script filename"""
	if node.get_script():
		var script_path = node.get_script().resource_path
		if script_name in script_path:
			return node
	
	for child in node.get_children():
		var result = _find_node_by_script(child, script_name)
		if result:
			return result
	
	return null


func _find_node_by_class(node: Node, target_class_name: String) -> Node:
	"""Recursively find a node by its class name"""
	if node.get_class() == target_class_name:
		return node
	
	for child in node.get_children():
		var result = _find_node_by_class(child, target_class_name)
		if result:
			return result
	
	return null



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
	var current_world_scale := XRServer.world_scale
	if not is_equal_approx(current_world_scale, _last_world_scale):
		_last_world_scale = current_world_scale
		_apply_rig_scale()

	if movement_component:
		movement_component.process_turning(delta)
		movement_component.process_locomotion(delta)
	
	# Retry setting up voice component if needed (handles race condition with UI loading)
	if voice_component and not voice_component.livekit_manager:
		var livekit_manager = _find_livekit_manager()
		if livekit_manager:
			print("XRPlayer: Found LiveKit manager (late init), setting up voice component")
			voice_component.setup(livekit_manager)
			voice_component.set_player_scene_root(get_tree().root)


func _physics_process(delta: float) -> void:
	if movement_component:
		movement_component.physics_process_turning(delta)
		movement_component.physics_process_locomotion(delta)
		
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
	
	# Update components
	if network_component:
		network_component.set_vr_mode(vr_active)
	if movement_component:
		movement_component.set_vr_mode(vr_active)
	
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
	
	# Physics hands are handled by PlayerMovementComponent if present
	if not movement_component:
		# Fallback if no movement component
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

	# Switch audio listener
	if vr_listener:
		vr_listener.make_current()
	elif desktop_listener:
		desktop_listener.clear_current()

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
	
	# Switch audio listener
	if desktop_listener:
		desktop_listener.make_current()
	elif vr_listener:
		vr_listener.clear_current()
	
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
	print("XRPlayer: teleport_to called! Target: ", target_position)
	print_stack()
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


func set_player_scale(new_scale: float) -> void:
	"""Apply a uniform scale to the whole player rig (body, physics hands, head)."""
	_manual_player_scale = max(new_scale, 0.01)
	if movement_component and movement_component.has_method("set_manual_player_scale"):
		# Keep the movement component's cached value in sync for persistence/UI
		movement_component.set_manual_player_scale(_manual_player_scale)
	elif player_body:
		player_body.scale = _base_player_body_scale * _manual_player_scale
	_apply_rig_scale()


func _cache_base_scales() -> void:
	if player_body:
		_base_player_body_scale = player_body.scale
	if physics_hand_left:
		_base_left_hand_scale = physics_hand_left.scale
	if physics_hand_right:
		_base_right_hand_scale = physics_hand_right.scale
	if head_area:
		_base_head_area_scale = head_area.scale
	_cache_hand_visual_data()


func _cache_hand_visual_data() -> void:
	_hand_visual_nodes.clear()
	_base_hand_visual_scales.clear()
	_base_hand_visual_transforms.clear()

	var hand_visual_candidates: Array = [
		left_hand_mesh,
		left_hand_pointer,
		left_watch,
		right_hand_mesh,
		right_hand_pointer,
		center_pointer,
	]

	for node in hand_visual_candidates:
		if node and node is Node3D:
			var node3d := node as Node3D
			_hand_visual_nodes.append(node3d)
			_base_hand_visual_scales[node3d] = node3d.scale
			_base_hand_visual_transforms[node3d] = node3d.transform


func _apply_rig_scale() -> void:
	var combined_scale := _manual_player_scale * XRServer.world_scale
	var visual_scale_vec := Vector3.ONE * combined_scale
	if player_body:
		player_body.scale = _base_player_body_scale * combined_scale
	
	if auto_scale_physics_hands:
		if physics_hand_left:
			physics_hand_left.scale = _base_left_hand_scale * combined_scale
		if physics_hand_right:
			physics_hand_right.scale = _base_right_hand_scale * combined_scale
	
	if auto_scale_head and head_area:
		# XR tracking can ignore parent scale; compensate so the head area follows player scale.
		var parent_scale: Vector3 = head_area.get_parent().global_transform.basis.get_scale()
		var inherited_scale: float = (abs(parent_scale.x) + abs(parent_scale.y) + abs(parent_scale.z)) / 3.0
		if inherited_scale < 0.0001:
			inherited_scale = 1.0
		var desired_local: float = combined_scale / inherited_scale
		head_area.scale = _base_head_area_scale * desired_local

	if auto_scale_hand_visuals and not _hand_visual_nodes.is_empty():
		for node in _hand_visual_nodes:
			if node and is_instance_valid(node):
				var base_xf: Transform3D = _base_hand_visual_transforms.get(node, node.transform)
				var scaled_basis := base_xf.basis.scaled(Vector3.ONE * combined_scale)
				var scaled_origin := base_xf.origin * combined_scale
				node.transform = Transform3D(scaled_basis, scaled_origin)


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


func toggle_voice_chat(enabled: bool) -> void:
	if voice_component:
		voice_component.toggle_voice_chat(enabled)


func set_muted(muted: bool) -> void:
	"""Set mute status for voice chat"""
	print("XRPlayer.set_muted called with: ", muted)
	if voice_component:
		voice_component.set_muted(muted)
		print("  ✓ Forwarded to voice_component")
	else:
		print("  ❌ voice_component is NULL! Cannot forward mute.")


func _setup_audio_listeners() -> void:
	"""Create and attach audio listeners to cameras"""
	# VR Listener
	if xr_camera:
		vr_listener = AudioListener3D.new()
		vr_listener.name = "VRListener"
		xr_camera.add_child(vr_listener)
	
	# Desktop Listener
	if desktop_camera:
		desktop_listener = AudioListener3D.new()
		desktop_listener.name = "DesktopListener"
		desktop_camera.add_child(desktop_listener)
	
	print("XRPlayer: Audio listeners setup")
