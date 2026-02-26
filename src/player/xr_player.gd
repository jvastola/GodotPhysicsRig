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
@onready var body_mesh: MeshInstance3D = $PlayerBody/XROrigin3D/XRCamera3D/HeadArea/BodyMesh
@onready var head_follow_rigidbody_shape: CollisionShape3D = $"PlayerBody/not moving correctly with head"

# Hand Tracking
const CAPSULE_MATERIAL = preload("res://assets/materials/capsule_material.tres")

@onready var left_hand_ray_cast: RayCast3D = $PlayerBody/XROrigin3D/LeftController/RayCast3D
@onready var left_hand_tracker_node: XRNode3D = $PlayerBody/XROrigin3D/LeftHandTracker
@onready var left_hand_skeleton = $PlayerBody/XROrigin3D/LeftHandTracker/OpenXRFbHandTrackingMesh  # Type varies by platform
@onready var right_hand_ray_cast: RayCast3D = $PlayerBody/XROrigin3D/RightController/RayCast3D
@onready var right_hand_tracker_node: XRNode3D = $PlayerBody/XROrigin3D/RightHandTracker
@onready var right_hand_skeleton = $PlayerBody/XROrigin3D/RightHandTracker/OpenXRFbHandTrackingMesh  # Type varies by platform

var fb_capsule_ext
var left_capsules_loaded := false
var right_capsules_loaded := false

var xr_interface: XRInterface
@onready var hand_tracking_ui = get_tree().root.find_child("HandTracking2DUI", true, false)

var _left_index_pinch_active := false
var _right_index_pinch_active := false


# Components
var network_component: PlayerNetworkComponent
var voice_component: PlayerVoiceComponent
var movement_component: PlayerMovementComponent
var simple_world_grab: SimpleWorldGrabComponent
var hand_movement_component: HandMovementComponent

# Player settings
var player_height := 0.0  # Using headset tracking; keep 0 to avoid artificial offset
var is_vr_mode := false
@export var head_radius: float = 0.18
var _desktop_trigger_event: InputEventMouseButton = null
@export var show_head_mesh: bool = true
@export var show_body_mesh: bool = true
@export var desktop_extra_collider_enabled: bool = true
@export var desktop_extra_collider_height: float = 1.2
@export var desktop_extra_collider_radius: float = 0.2
@export var desktop_extra_collider_offset: Vector3 = Vector3(0, 1.15, 0)
@export var auto_scale_physics_hands: bool = true
@export var auto_scale_head: bool = true
@export var auto_scale_hand_visuals: bool = true
@export var match_cube_and_physics_to_tracked_hand_mesh: bool = true
@export var debug_physics_hand_scale_logs: bool = false
@export var scale_rig_with_world_scale: bool = true
# When running in VR the camera is positioned at the
# head mesh origin.  By default the interior faces are culled so
# you end up "inside" the cube and can't see it.  Historically we
# hid the head mesh entirely for the local VR helmet to avoid
#(renderer) artifacts, but you can override this behaviour if you
# want both the head *and* body visible in VR (e.g. for spectators
# or when spawning XRPlayer instances for remote users).
#
# Set to `false` if you want the head mesh to remain visible in VR.
@export var hide_head_mesh_in_vr: bool = false
@export var auto_scale_camera_clip: bool = true
@export_range(0.001, 5.0, 0.001) var camera_near_min: float = 0.005
@export_range(0.01, 500.0, 0.01) var camera_near_max: float = 100.0
@export_range(10.0, 10000000.0, 10.0) var camera_far_max: float = 5000000.0
@export_range(0.1, 10.0, 0.1) var camera_far_scale_boost: float = 1.0
@export var follow_head_with_rigidbody_shape: bool = true
@export var head_follow_shape_local_offset: Vector3 = Vector3.ZERO
@export var head_follow_shape_lerp_speed: float = 0.0

# Player scale tracking
var _manual_player_scale: float = 1.0
var _last_world_scale: float = 1.0
var _base_player_body_scale: Vector3 = Vector3.ONE
var _base_left_hand_scale: Vector3 = Vector3.ONE
var _base_right_hand_scale: Vector3 = Vector3.ONE
var _base_head_area_scale: Vector3 = Vector3.ONE
var _hand_visual_nodes: Array[Node3D] = []
var _base_hand_visual_scales: Dictionary = {}
var _base_xr_camera_near: float = 0.05
var _base_xr_camera_far: float = 4000.0
var _base_desktop_camera_near: float = 0.05
var _base_desktop_camera_far: float = 4000.0
var _last_logged_physics_hand_scale: float = -1.0
var _base_left_tracked_hand_global_scale: float = -1.0
var _base_right_tracked_hand_global_scale: float = -1.0

# Poke Interaction
var left_poke_area: Area3D
var right_poke_area: Area3D
var left_poke_visual: MeshInstance3D
var right_poke_visual: MeshInstance3D
var left_poke_shape: SphereShape3D
var right_poke_shape: SphereShape3D
var left_poke_mesh: SphereMesh
var right_poke_mesh: SphereMesh
var left_ui_last_collider: Node = null
var right_ui_last_collider: Node = null
var _poke_radius: float = 0.005
var _current_rig_scale: float = 1.0
var _poke_visual_color := Color(0.0, 0.8, 1.0, 0.8)
var _poke_active_color := Color(0.2, 1.0, 0.2, 1.0)
var _pinch_threshold: float = 0.8  # Strength to trigger grab

# Audio Listeners
var vr_listener: AudioListener3D = null
var desktop_listener: AudioListener3D = null


func _ready() -> void:
	_cache_base_scales()
	_last_world_scale = XRServer.world_scale
	_apply_rig_scale()

	# Initialize Hand Tracking
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		fb_capsule_ext = Engine.get_singleton("OpenXRFbHandTrackingCapsulesExtensionWrapper")
		print("XRPlayer: OpenXR initialized, capsule extension: ", fb_capsule_ext != null)
	else:
		print("XRPlayer: OpenXR not initialized yet, deferring capsule extension lookup")

	# Hand tracking mesh signals
	if left_hand_skeleton:
		left_hand_skeleton.openxr_fb_hand_tracking_mesh_ready.connect(_add_mesh_group.bind(left_hand_skeleton, "hand_mesh_left"))
		print("XRPlayer: Left hand skeleton connected, visible: ", left_hand_skeleton.visible)
		left_hand_skeleton.visible = true  # Ensure visibility
	else:
		push_warning("XRPlayer: Left hand skeleton not found!")
	
	if right_hand_skeleton:
		right_hand_skeleton.openxr_fb_hand_tracking_mesh_ready.connect(_add_mesh_group.bind(right_hand_skeleton, "hand_mesh_right"))
		print("XRPlayer: Right hand skeleton connected, visible: ", right_hand_skeleton.visible)
		right_hand_skeleton.visible = true  # Ensure visibility
	else:
		push_warning("XRPlayer: Right hand skeleton not found!")
	
	# Ensure tracker nodes are visible
	if hand_tracking_ui:
		hand_tracking_ui.visibility_toggle_requested.connect(_on_hand_ui_visibility_toggle_requested)
	
	if left_hand_tracker_node:
		left_hand_tracker_node.visible = true
	if right_hand_tracker_node:
		right_hand_tracker_node.visible = true

	# Connect Controller Signals
	left_controller.button_pressed.connect(_on_left_controller_button_pressed)
	left_controller.button_released.connect(_on_left_controller_button_released)
	left_controller.input_float_changed.connect(_on_left_controller_input_float_changed)

	right_controller.button_pressed.connect(_on_right_controller_button_pressed)
	right_controller.button_released.connect(_on_right_controller_button_released)
	right_controller.input_float_changed.connect(_on_right_controller_input_float_changed)

	# Initialize components
	_setup_components()

	# Wait for XR origin to initialize
	if xr_origin:
		xr_origin.vr_mode_active.connect(_on_vr_mode_changed)
		# Check initial state
		call_deferred("_check_initial_mode")

	if head_collision_shape and head_collision_shape.shape and head_collision_shape.shape is SphereShape3D:
		head_collision_shape.shape.radius = head_radius
	
	_update_local_mesh_visibility()
	
	# Ensure physics hands are properly connected
	call_deferred("_setup_physics_hands")
	
	# Add to group for easy finding
	add_to_group("xr_player")
	
	# Setup audio listeners
	_setup_audio_listeners()
	
	# Setup poke interaction
	_setup_poke_interaction()


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
		simple_world_grab.enabled = _load_saved_simple_world_grab_enabled()
	
	# Hand Movement Component (middle finger pinch world grab)
	hand_movement_component = get_node_or_null("HandMovementComponent")
	if hand_movement_component:
		hand_movement_component.setup(player_body, xr_origin)
		hand_movement_component.enabled = false  # Disabled by default, enable via settings


func _find_livekit_manager() -> Node:
	"""Find the LiveKit manager in the scene or as an autoload"""
	# Option 1: Look for LiveKitWrapper autoload
	var livekit_wrapper = get_node_or_null("/root/LiveKitWrapper")
	if livekit_wrapper:
		return livekit_wrapper
		
	# Option 2: Look for LiveKitViewport3D and get its manager
	var root = get_tree().root
	var livekit_ui = _find_node_by_script(root, "livekit_ui.gd")
	if livekit_ui and livekit_ui.has_method("get") and "livekit_manager" in livekit_ui:
		return livekit_ui.livekit_manager
	
	# Option 3: Look for LiveKitManager directly
	var livekit_manager = _find_node_by_class(root, "LiveKitManager")
	if livekit_manager:
		return livekit_manager
	
	return null


func _load_saved_simple_world_grab_enabled() -> bool:
	"""Read persisted movement settings for SimpleWorldGrab state."""
	var save_manager = get_node_or_null("/root/SaveManager")
	if not save_manager:
		return false
	if not save_manager.has_method("get_movement_settings"):
		return false
	var settings_variant = save_manager.call("get_movement_settings")
	if not (settings_variant is Dictionary):
		return false
	var settings: Dictionary = settings_variant
	return bool(settings.get("simple_world_grab_enabled", false))


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
	# Retry getting capsule extension if not available yet
	if fb_capsule_ext == null:
		xr_interface = XRServer.find_interface("OpenXR")
		if xr_interface and xr_interface.is_initialized():
			fb_capsule_ext = Engine.get_singleton("OpenXRFbHandTrackingCapsulesExtensionWrapper")
			if fb_capsule_ext:
				print("XRPlayer: Late-bound capsule extension successfully")
	
	if not left_capsules_loaded:
		var tracker: XRHandTracker = XRServer.get_tracker("/user/hand_tracker/left")
		if tracker and tracker.has_tracking_data:
			if left_hand_skeleton and left_hand_skeleton.get_bone_count() > 0:
				print("XRPlayer: Left hand tracker and skeleton ready (", left_hand_skeleton.get_bone_count(), " bones), setting up capsules...")
				hand_capsule_setup(0, tracker)
	
	if not right_capsules_loaded:
		var tracker: XRHandTracker = XRServer.get_tracker("/user/hand_tracker/right")
		if tracker and tracker.has_tracking_data:
			if right_hand_skeleton and right_hand_skeleton.get_bone_count() > 0:
				print("XRPlayer: Right hand tracker and skeleton ready (", right_hand_skeleton.get_bone_count(), " bones), setting up capsules...")
				hand_capsule_setup(1, tracker)

	_update_hand_tracking_ui_pinches()
	_sync_rig_scale_with_world_scale()

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
	_sync_rig_scale_with_world_scale()
	_process_poke_and_pinch(delta)

	# Handle raycasts in physics process to avoid Jolt "Space state inaccessible" errors
	if _left_index_pinch_active:
		if left_hand_ray_cast:
			left_hand_ray_cast.enabled = true
			left_hand_ray_cast.force_raycast_update()
			if left_hand_ray_cast.is_colliding():
				var collider = left_hand_ray_cast.get_collider()
				if collider:
					update_collider(collider)
		_left_index_pinch_active = false
	
	if _right_index_pinch_active:
		if right_hand_ray_cast:
			right_hand_ray_cast.enabled = true
			right_hand_ray_cast.force_raycast_update()
			if right_hand_ray_cast.is_colliding():
				var collider = right_hand_ray_cast.get_collider()
				if collider:
					update_collider(collider)
		_right_index_pinch_active = false

	if movement_component:
		movement_component.physics_process_turning(delta)
		movement_component.physics_process_locomotion(delta)

	_sync_head_follow_rigidbody_shape(delta)


func _sync_rig_scale_with_world_scale() -> void:
	var current_world_scale := XRServer.world_scale
	if is_equal_approx(current_world_scale, _last_world_scale):
		return
	_last_world_scale = current_world_scale
	_apply_rig_scale()


func force_world_scale_sync() -> void:
	_sync_rig_scale_with_world_scale()


func _check_initial_mode() -> void:
	"""Check initial VR mode after a frame"""
	if xr_origin and xr_origin.has_method("is_vr_mode"):
		_on_vr_mode_changed(xr_origin.is_vr_mode)
	else:
		# Default to checking if XR interface exists
		var interface = XRServer.find_interface("OpenXR")
		_on_vr_mode_changed(interface != null and interface.is_initialized())


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
	_update_local_mesh_visibility()


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
	if head_follow_rigidbody_shape:
		head_follow_rigidbody_shape.disabled = not follow_head_with_rigidbody_shape
	
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
	if head_follow_rigidbody_shape:
		head_follow_rigidbody_shape.disabled = true

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


func _sync_head_follow_rigidbody_shape(delta: float) -> void:
	if not follow_head_with_rigidbody_shape:
		return
	if not is_vr_mode:
		return
	if not player_body or not xr_camera or not head_follow_rigidbody_shape:
		return

	var target_local_pos: Vector3 = player_body.to_local(xr_camera.global_position) + head_follow_shape_local_offset
	var shape_xform := head_follow_rigidbody_shape.transform
	if head_follow_shape_lerp_speed <= 0.0:
		shape_xform.origin = target_local_pos
	else:
		var t := clampf(delta * head_follow_shape_lerp_speed, 0.0, 1.0)
		shape_xform.origin = shape_xform.origin.lerp(target_local_pos, t)
	head_follow_rigidbody_shape.transform = shape_xform


func set_player_scale(new_scale: float) -> void:
	"""Apply a uniform scale to the whole player rig (body, physics hands, head)."""
	_manual_player_scale = max(new_scale, 0.01)
	if movement_component and movement_component.has_method("set_manual_player_scale"):
		# Keep the movement component's cached value in sync for persistence/UI
		movement_component.set_manual_player_scale(_manual_player_scale)
	elif player_body:
		player_body.scale = _base_player_body_scale * _manual_player_scale
	_apply_rig_scale()


func set_scale_rig_with_world_scale(enabled: bool) -> void:
	scale_rig_with_world_scale = enabled
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
	if xr_camera:
		_base_xr_camera_near = maxf(xr_camera.near, 0.0001)
		_base_xr_camera_far = maxf(xr_camera.far, _base_xr_camera_near + 1.0)
	if desktop_camera:
		_base_desktop_camera_near = maxf(desktop_camera.near, 0.0001)
		_base_desktop_camera_far = maxf(desktop_camera.far, _base_desktop_camera_near + 1.0)
	_cache_hand_visual_data()
	_cache_tracked_hand_scale_bases()


func _cache_hand_visual_data() -> void:
	_hand_visual_nodes.clear()
	_base_hand_visual_scales.clear()

	var hand_visual_candidates: Array = [
		left_hand_mesh,
		left_hand_pointer,
		left_watch,
		left_hand_skeleton,
		right_hand_mesh,
		right_hand_pointer,
		right_hand_skeleton,
		center_pointer,
	]

	for node in hand_visual_candidates:
		if node and node is Node3D:
			var node3d := node as Node3D
			_hand_visual_nodes.append(node3d)
			_base_hand_visual_scales[node3d] = node3d.scale


func _apply_rig_scale() -> void:
	var world_factor := XRServer.world_scale if scale_rig_with_world_scale else 1.0
	var combined_scale := _manual_player_scale * world_factor
	_current_rig_scale = combined_scale
	var left_target_scale := combined_scale
	var right_target_scale := combined_scale

	if player_body:
		player_body.scale = _base_player_body_scale * combined_scale
	
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
					if node == left_watch and left_watch and left_watch.has_method("set_rig_scale_multiplier"):
						left_watch.call("set_rig_scale_multiplier", combined_scale)
						continue
					if _should_defer_cube_hand_scale(node):
						continue
					var base_scale: Vector3 = _base_hand_visual_scales.get(node, node.scale)
					if _use_direct_visual_scale(node):
						node.scale = base_scale * combined_scale
					else:
						_scale_visual_node(node, base_scale, combined_scale)

	if match_cube_and_physics_to_tracked_hand_mesh:
		left_target_scale = _get_tracked_hand_scale_factor(left_hand_skeleton, true, combined_scale)
		right_target_scale = _get_tracked_hand_scale_factor(right_hand_skeleton, false, combined_scale)
		_apply_cube_hand_mesh_scale(left_hand_mesh, left_target_scale)
		_apply_cube_hand_mesh_scale(right_hand_mesh, right_target_scale)

	if auto_scale_physics_hands:
		_apply_physics_hand_scale(physics_hand_left, _base_left_hand_scale, left_target_scale)
		_apply_physics_hand_scale(physics_hand_right, _base_right_hand_scale, right_target_scale)

	if left_watch and is_instance_valid(left_watch) and left_watch.has_method("set_rig_scale_multiplier"):
		left_watch.call("set_rig_scale_multiplier", combined_scale)
	_apply_poke_scale(combined_scale)
	_apply_camera_clip_scaling(combined_scale)
	_maybe_log_physics_hand_scale(combined_scale, left_target_scale, right_target_scale)


func _apply_physics_hand_scale(hand: RigidBody3D, base_scale: Vector3, combined_scale: float) -> void:
	if not hand:
		return
	if hand.has_method("set_hand_scale_multiplier"):
		hand.call("set_hand_scale_multiplier", combined_scale)
		return
	hand.scale = base_scale * combined_scale


func _maybe_log_physics_hand_scale(combined_scale: float, left_target_scale: float, right_target_scale: float) -> void:
	if not debug_physics_hand_scale_logs:
		return
	if is_equal_approx(combined_scale, _last_logged_physics_hand_scale):
		return
	_last_logged_physics_hand_scale = combined_scale

	var left_mesh_scale := _node_scale_to_string(left_hand_mesh)
	var right_mesh_scale := _node_scale_to_string(right_hand_mesh)
	print("XRPlayer ScaleDebug: world=", snapped(XRServer.world_scale, 0.001), " manual=", snapped(_manual_player_scale, 0.001), " combined=", snapped(combined_scale, 0.001))
	print("  left_hand_mesh(global)=", left_mesh_scale, " right_hand_mesh(global)=", right_mesh_scale)
	print("  left_target_scale=", snapped(left_target_scale, 0.001), " right_target_scale=", snapped(right_target_scale, 0.001))
	if left_hand_skeleton:
		print("  left_tracked_hand(global)=", _node_scale_to_string(left_hand_skeleton))
	if right_hand_skeleton:
		print("  right_tracked_hand(global)=", _node_scale_to_string(right_hand_skeleton))
	if left_hand_mesh:
		var left_g := left_hand_mesh.global_transform.basis.get_scale()
		var left_ratio := left_g.x / maxf(combined_scale, 0.0001)
		print("  left_hand_mesh/global_to_combined_ratio=", snapped(left_ratio, 0.001))
	if physics_hand_left:
		if physics_hand_left.has_method("get_scale_debug_state"):
			print("  left_physics=", str(physics_hand_left.call("get_scale_debug_state")))
		else:
			print("  left_physics(global)=", _node_scale_to_string(physics_hand_left))
	if physics_hand_right:
		if physics_hand_right.has_method("get_scale_debug_state"):
			print("  right_physics=", str(physics_hand_right.call("get_scale_debug_state")))
		else:
			print("  right_physics(global)=", _node_scale_to_string(physics_hand_right))


func _node_scale_to_string(node: Node3D) -> String:
	if not node:
		return "n/a"
	var s: Vector3 = node.global_transform.basis.get_scale()
	return "(%.4f, %.4f, %.4f)" % [s.x, s.y, s.z]


func _cache_tracked_hand_scale_bases() -> void:
	_base_left_tracked_hand_global_scale = _get_uniform_global_scale(left_hand_skeleton)
	_base_right_tracked_hand_global_scale = _get_uniform_global_scale(right_hand_skeleton)


func _get_uniform_global_scale(node: Node3D) -> float:
	if not node:
		return -1.0
	var s: Vector3 = node.global_transform.basis.get_scale()
	return (absf(s.x) + absf(s.y) + absf(s.z)) / 3.0


func _get_tracked_hand_scale_factor(tracked_node: Node3D, is_left: bool, fallback_scale: float) -> float:
	if not tracked_node:
		return fallback_scale
	var tracked_scale := _get_uniform_global_scale(tracked_node)
	if tracked_scale <= 0.0001:
		return fallback_scale

	var base_scale := _base_left_tracked_hand_global_scale if is_left else _base_right_tracked_hand_global_scale
	if base_scale <= 0.0001:
		base_scale = tracked_scale
		if is_left:
			_base_left_tracked_hand_global_scale = base_scale
		else:
			_base_right_tracked_hand_global_scale = base_scale
	if base_scale <= 0.0001:
		return fallback_scale
	return tracked_scale / base_scale


func _apply_cube_hand_mesh_scale(hand_mesh_node: Node3D, target_scale: float) -> void:
	if not hand_mesh_node:
		return
	var base_scale: Vector3 = _base_hand_visual_scales.get(hand_mesh_node, hand_mesh_node.scale)
	_scale_visual_node(hand_mesh_node, base_scale, target_scale)


func _should_defer_cube_hand_scale(node: Node3D) -> bool:
	return match_cube_and_physics_to_tracked_hand_mesh and (node == left_hand_mesh or node == right_hand_mesh)


func _use_direct_visual_scale(node: Node3D) -> bool:
	# Controller mesh nodes inherit player/body scale, so they must use parent compensation.
	# Hand-tracking skeleton meshes can bypass that inheritance, so keep direct scaling there.
	return node == left_hand_skeleton or node == right_hand_skeleton


func _scale_visual_node(node: Node3D, base_scale: Vector3, target_uniform_scale: float) -> void:
	var parent_node: Node3D = node.get_parent_node_3d()
	if not parent_node:
		node.scale = base_scale * target_uniform_scale
		return

	var parent_scale: Vector3 = parent_node.global_transform.basis.get_scale()
	var safe_parent_scale := Vector3(
		maxf(absf(parent_scale.x), 0.0001),
		maxf(absf(parent_scale.y), 0.0001),
		maxf(absf(parent_scale.z), 0.0001)
	)
	node.scale = Vector3(
		base_scale.x * target_uniform_scale / safe_parent_scale.x,
		base_scale.y * target_uniform_scale / safe_parent_scale.y,
		base_scale.z * target_uniform_scale / safe_parent_scale.z
	)


func _apply_camera_clip_scaling(scale_factor: float) -> void:
	if not auto_scale_camera_clip:
		return
	var clip_scale := maxf(scale_factor, 0.01)
	if xr_camera:
		var xr_near := clampf(_base_xr_camera_near * clip_scale, camera_near_min, camera_near_max)
		var xr_far_target := _base_xr_camera_far * clip_scale * camera_far_scale_boost
		var xr_far := clampf(xr_far_target, maxf(xr_near + 10.0, xr_near * 2.0), camera_far_max)
		xr_camera.near = xr_near
		xr_camera.far = xr_far
	if desktop_camera:
		var desktop_near := clampf(_base_desktop_camera_near * clip_scale, camera_near_min, camera_near_max)
		var desktop_far_target := _base_desktop_camera_far * clip_scale * camera_far_scale_boost
		var desktop_far := clampf(desktop_far_target, maxf(desktop_near + 10.0, desktop_near * 2.0), camera_far_max)
		desktop_camera.near = desktop_near
		desktop_camera.far = desktop_far


func _update_local_mesh_visibility() -> void:
	# head/body meshes are part of the local XRPlayer scene.  The
	# body is always shown when `show_body_mesh` is true.  the head
	# mesh used to be forcibly hidden in VR (see `hide_head_mesh_in_vr`)
	# because the camera lives inside it.  You can now toggle that
	# behaviour independently via the export flag above.
	if head_mesh:
		# head_mesh.visible = show_head_mesh *and* (not hidden for VR)
		head_mesh.visible = show_head_mesh and not (is_vr_mode and hide_head_mesh_in_vr)
	if body_mesh:
		body_mesh.visible = show_body_mesh


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


func apply_texture_to_body(texture: ImageTexture) -> void:
	"""Apply a texture to the body mesh"""
	if not body_mesh:
		print("XRPlayer: body_mesh is null, cannot apply texture")
		return
	
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	body_mesh.material_override = mat
	print("XRPlayer: Applied texture to body mesh, visible: ", body_mesh.visible, ", mesh: ", body_mesh.mesh)


func get_grid_painter() -> Node:
	"""Get the GridPainter component"""
	return get_node_or_null("GridPainter")


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


func _add_mesh_group(p_parent: Node3D, p_group: String) -> void:
	print("XRPlayer: _add_mesh_group called for '", p_group, "', parent: ", str(p_parent.name) if p_parent else "NULL")
	var mesh_count := 0
	for child in p_parent.get_children():
		if child is MeshInstance3D:
			child.add_to_group(p_group)
			# Ensure skinning is active for the generated mesh
			if p_parent.has_method("get_path"):
				child.skeleton = p_parent.get_path()
			child.visible = true  # Ensure the mesh is visible
			mesh_count += 1
			print("  - Added mesh child: ", child.name, " to group ", p_group)
	print("XRPlayer: Hand tracking mesh ready - ", p_group, " with ", mesh_count, " meshes, parent visible: ", p_parent.visible)
	# Ensure the parent skeleton is visible
	if p_parent:
		p_parent.visible = true


func hand_capsule_setup(hand_idx: int, hand_tracker: XRHandTracker) -> void:
	if not fb_capsule_ext:
		print("XRPlayer: hand_capsule_setup - fb_capsule_ext is null, cannot create capsules")
		return

	var skeletons := [left_hand_skeleton, right_hand_skeleton]
	var skeleton_parent = skeletons[hand_idx]
	var hand_name = "left" if hand_idx == 0 else "right"
	
	if not skeleton_parent:
		print("XRPlayer: hand_capsule_setup - ", hand_name, " skeleton_parent is null")
		return

	# Try to find actual Skeleton3D if skeleton_parent is just a mesh
	var actual_skeleton: Skeleton3D = null
	if skeleton_parent is Skeleton3D:
		actual_skeleton = skeleton_parent
	else:
		# Search children for a Skeleton3D
		for child in skeleton_parent.get_children():
			if child is Skeleton3D:
				actual_skeleton = child
				break
	
	if not actual_skeleton:
		print("XRPlayer: hand_capsule_setup - WARNING: Could not find Skeleton3D under ", skeleton_parent.name)
		# Fallback to the node itself if it has bone methods, though it might not work for BoneAttachment3D
		if skeleton_parent.has_method("get_bone_count"):
			print("XRPlayer: hand_capsule_setup - Parent has bone methods, using it as fallback.")
			# But BoneAttachment3D strictly requires a Skeleton3D parent in Godot 4
	
	var bone_count = -1
	if actual_skeleton:
		bone_count = actual_skeleton.get_bone_count()
	elif skeleton_parent.has_method("get_bone_count"):
		bone_count = skeleton_parent.get_bone_count()
		
	print("XRPlayer: hand_capsule_setup - ", hand_name, " hand, bone count: ", bone_count)
	
	var capsule_count = fb_capsule_ext.get_hand_capsule_count()
	print("XRPlayer: hand_capsule_setup - Extension reports ", capsule_count, " capsules for ", hand_name, " hand")

	if capsule_count == 0:
		print("XRPlayer: hand_capsule_setup - WARNING: capsule_count is 0.")
		return

	for capsule_idx in capsule_count:
		var capsule_mesh := CapsuleMesh.new()
		var height = fb_capsule_ext.get_hand_capsule_height(hand_idx, capsule_idx)
		var radius = fb_capsule_ext.get_hand_capsule_radius(hand_idx, capsule_idx)
		capsule_mesh.height = height
		capsule_mesh.radius = radius

		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = capsule_mesh
		mesh_instance.set_surface_override_material(0, CAPSULE_MATERIAL)
		mesh_instance.visible = true
		match hand_idx:
			0:
				mesh_instance.add_to_group("hand_capsule_left")
			1:
				mesh_instance.add_to_group("hand_capsule_right")

		var joint_idx = fb_capsule_ext.get_hand_capsule_joint(hand_idx, capsule_idx)
		var bone_name = ""
		if actual_skeleton:
			bone_name = actual_skeleton.get_bone_name(joint_idx)
		elif skeleton_parent.has_method("get_bone_name"):
			bone_name = skeleton_parent.get_bone_name(joint_idx)
		
		var bone_attachment := BoneAttachment3D.new()
		if bone_name != "":
			bone_attachment.bone_name = bone_name
		else:
			bone_attachment.bone_idx = joint_idx
		
		bone_attachment.name = "CapsuleBone_" + str(capsule_idx)
		bone_attachment.add_child(mesh_instance)
		
		if actual_skeleton:
			actual_skeleton.add_child(bone_attachment)
		else:
			skeleton_parent.add_child(bone_attachment)

		# Important: In Godot 4, BoneAttachment3D might need to be notified of its skeleton
		# especially if it's not a direct child of a Skeleton3D node.
		# But we are adding it as a child.
		
		var capsule_transform: Transform3D = fb_capsule_ext.get_hand_capsule_transform(hand_idx, capsule_idx)
		var bone_transform: Transform3D = hand_tracker.get_hand_joint_transform(joint_idx as XRHandTracker.HandJoint)
		mesh_instance.transform = bone_transform.inverse() * capsule_transform
		
		if capsule_idx < 3:
			print("XRPlayer: Added Capsule ", capsule_idx, " to ", bone_name if bone_name != "" else "joint " + str(joint_idx), " under ", (actual_skeleton.name if actual_skeleton else skeleton_parent.name), " (h: ", snapped(height, 0.001), ", r: ", snapped(radius, 0.001), ")")

	match hand_idx:
		0:
			left_capsules_loaded = true
			print("XRPlayer: Left hand capsules loaded (", capsule_count, " capsules)")
		1:
			right_capsules_loaded = true
			print("XRPlayer: Right hand capsules loaded (", capsule_count, " capsules)")


func _get_manual_pinch_strength(tracker: XRHandTracker, joint_idx: int) -> float:
	# Fallback for missing get_hand_joint_pinch_strength
	# Standard OpenXR Hand Joint Indices: Thumb Tip (5), Index Tip (10), Middle Tip (15), Ring Tip (20), Little Tip (25)
	var thumb_tip_transform = tracker.get_hand_joint_transform(5 as XRHandTracker.HandJoint)
	var finger_tip_transform = tracker.get_hand_joint_transform(joint_idx as XRHandTracker.HandJoint)
	
	# If either joint is untracked, return 0
	if thumb_tip_transform == Transform3D() or finger_tip_transform == Transform3D():
		return 0.0
		
	var distance = thumb_tip_transform.origin.distance_to(finger_tip_transform.origin)
	
	# Mapping distance to pinch strength:
	# 7cm or more = 0.0 (fully open)
	# 2cm or less = 1.0 (fully pinched)
	var max_dist = 0.07
	var min_dist = 0.02
	
	return clamp((max_dist - distance) / (max_dist - min_dist), 0.0, 1.0)


func _update_hand_tracking_ui_pinches() -> void:
	if not hand_tracking_ui:
		return
	
	# Polling pinch strengths directly for better accuracy/independence
	var left_tracker := XRServer.get_tracker("/user/hand_tracker/left") as XRHandTracker
	if left_tracker and left_tracker.has_tracking_data:
		var p_index = _get_manual_pinch_strength(left_tracker, 10)
		var p_middle = _get_manual_pinch_strength(left_tracker, 15)
		var p_ring = _get_manual_pinch_strength(left_tracker, 20)
		var p_little = _get_manual_pinch_strength(left_tracker, 25)
		
		hand_tracking_ui.set_pinch_strength(0, "index_pinch", p_index)
		hand_tracking_ui.set_pinch_strength(0, "middle_pinch", p_middle)
		hand_tracking_ui.set_pinch_strength(0, "ring_pinch", p_ring)
		hand_tracking_ui.set_pinch_strength(0, "little_pinch", p_little)
		
		# Sync discrete indicators with strength (> 0.8 is green)
		hand_tracking_ui.set_discrete_signal(0, "index_pinch", p_index > 0.8)
		hand_tracking_ui.set_discrete_signal(0, "middle_pinch", p_middle > 0.8)
		hand_tracking_ui.set_discrete_signal(0, "ring_pinch", p_ring > 0.8)
		hand_tracking_ui.set_discrete_signal(0, "little_pinch", p_little > 0.8)
		
	var right_tracker := XRServer.get_tracker("/user/hand_tracker/right") as XRHandTracker
	if right_tracker and right_tracker.has_tracking_data:
		var p_index = _get_manual_pinch_strength(right_tracker, 10)
		var p_middle = _get_manual_pinch_strength(right_tracker, 15)
		var p_ring = _get_manual_pinch_strength(right_tracker, 20)
		var p_little = _get_manual_pinch_strength(right_tracker, 25)
		
		hand_tracking_ui.set_pinch_strength(1, "index_pinch", p_index)
		hand_tracking_ui.set_pinch_strength(1, "middle_pinch", p_middle)
		hand_tracking_ui.set_pinch_strength(1, "ring_pinch", p_ring)
		hand_tracking_ui.set_pinch_strength(1, "little_pinch", p_little)
		
		# Sync discrete indicators with strength (> 0.8 is green)
		hand_tracking_ui.set_discrete_signal(1, "index_pinch", p_index > 0.8)
		hand_tracking_ui.set_discrete_signal(1, "middle_pinch", p_middle > 0.8)
		hand_tracking_ui.set_discrete_signal(1, "ring_pinch", p_ring > 0.8)
		hand_tracking_ui.set_discrete_signal(1, "little_pinch", p_little > 0.8)


func _on_left_controller_input_float_changed(_name: String, _value: float) -> void:
	# Handled via polling in _process for diagnostic UI
	# print("L Float: ", name, " ", value)
	pass


func _on_right_controller_input_float_changed(_name: String, _value: float) -> void:
	# Handled via polling in _process for diagnostic UI
	# print("R Float: ", name, " ", value)
	pass


func _on_left_controller_button_pressed(btn_name: String) -> void:
	print("XRPlayer Left Button: ", btn_name)
	# Keep controller events for non-hand-tracking or system-level signals
	# but diagnostic UI lights are handled by polling in _process for accuracy
	
	if btn_name == "index_pinch":
		_left_index_pinch_active = true


func _on_left_controller_button_released(btn_name: String) -> void:
	if btn_name == "index_pinch":
		left_hand_ray_cast.enabled = false

func _on_right_controller_button_pressed(btn_name: String) -> void:
	print("XRPlayer Right Button: ", btn_name)
	if btn_name == "index_pinch":
		_right_index_pinch_active = true


func _on_right_controller_button_released(btn_name: String) -> void:
	if btn_name == "index_pinch":
		right_hand_ray_cast.enabled = false


func _on_hand_ui_visibility_toggle_requested(collider_name: String) -> void:
	# Handler for the 2D UI signals
	_handle_hand_interaction(collider_name)


func update_collider(collider: Node) -> void:
	# For raycast interactions directly with 3D nodes (toggles)
	_handle_hand_interaction(collider.name)


func _handle_hand_interaction(collider_name: String) -> void:
	# Shared logic for both 2D UI signals and 3D node raycasts
	print("XRPlayer: Hand Interaction with '", collider_name, "'")
	
	match collider_name:
		"LeftHandMesh":
			var nodes = get_tree().get_nodes_in_group("hand_mesh_left")
			print("XRPlayer: Toggling ", nodes.size(), " left hand meshes")
			for hand_mesh in nodes:
				hand_mesh.visible = not hand_mesh.visible
		"LeftHandCapsules":
			var nodes = get_tree().get_nodes_in_group("hand_capsule_left")
			print("XRPlayer: Toggling ", nodes.size(), " left hand capsules")
			for hand_capsule in nodes:
				hand_capsule.visible = not hand_capsule.visible
		"RightHandMesh":
			var nodes = get_tree().get_nodes_in_group("hand_mesh_right")
			print("XRPlayer: Toggling ", nodes.size(), " right hand meshes")
			for hand_mesh in nodes:
				hand_mesh.visible = not hand_mesh.visible
		"RightHandCapsules":
			var nodes = get_tree().get_nodes_in_group("hand_capsule_right")
			print("XRPlayer: Toggling ", nodes.size(), " right hand capsules")
			for hand_capsule in nodes:
				hand_capsule.visible = not hand_capsule.visible


func _setup_poke_interaction() -> void:
	"""Setup areas and visuals for poke interaction"""
	if not left_hand_tracker_node or not right_hand_tracker_node:
		return

	# Left Hand Poke
	left_poke_area = _create_poke_area("LeftPokeArea")
	left_poke_visual = _create_poke_visual("LeftPokeVisual")
	if left_poke_area and left_poke_visual:
		left_poke_area.add_child(left_poke_visual)
	left_poke_shape = _get_poke_sphere_shape(left_poke_area)
	left_poke_mesh = left_poke_visual.mesh as SphereMesh
	if left_poke_area:
		add_child(left_poke_area)

	# Right Hand Poke
	right_poke_area = _create_poke_area("RightPokeArea")
	right_poke_visual = _create_poke_visual("RightPokeVisual")
	if right_poke_area and right_poke_visual:
		right_poke_area.add_child(right_poke_visual)
	right_poke_shape = _get_poke_sphere_shape(right_poke_area)
	right_poke_mesh = right_poke_visual.mesh as SphereMesh
	if right_poke_area:
		add_child(right_poke_area)
	_apply_poke_scale(_current_rig_scale)


func _get_poke_sphere_shape(area: Area3D) -> SphereShape3D:
	if not area:
		return null
	var collision := area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not collision:
		for child in area.get_children():
			if child is CollisionShape3D:
				collision = child as CollisionShape3D
				break
	if collision and collision.shape is SphereShape3D:
		return collision.shape as SphereShape3D
	return null


func _apply_poke_scale(scale_factor: float) -> void:
	var scaled_radius := maxf(_poke_radius * maxf(scale_factor, 0.001), 0.0005)
	if left_poke_shape:
		left_poke_shape.radius = scaled_radius
	if right_poke_shape:
		right_poke_shape.radius = scaled_radius
	if left_poke_mesh:
		left_poke_mesh.radius = scaled_radius
		left_poke_mesh.height = scaled_radius * 2.0
	if right_poke_mesh:
		right_poke_mesh.radius = scaled_radius
		right_poke_mesh.height = scaled_radius * 2.0


func _create_poke_area(p_name: String) -> Area3D:
	var area := Area3D.new()
	area.name = p_name
	area.collision_layer = 0  # Don't get hit by others
	area.collision_mask = 1 << 5 # Layer 6 (UI) usually
	area.monitorable = false
	area.monitoring = true
	
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = _poke_radius
	col.shape = shape
	area.add_child(col)
	return area


func _create_poke_visual(p_name: String) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = p_name
	var mesh := SphereMesh.new()
	mesh.radius = _poke_radius
	mesh.height = _poke_radius * 2.0
	mesh.radial_segments = 16
	mesh_inst.mesh = mesh
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _poke_visual_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true # Visualize through objects
	mesh_inst.material_override = mat
	
	return mesh_inst


func _process_poke_and_pinch(_delta: float) -> void:
	var left_tracker := XRServer.get_tracker("/user/hand_tracker/left") as XRHandTracker
	var right_tracker := XRServer.get_tracker("/user/hand_tracker/right") as XRHandTracker

	# World scale is needed for the tracker-space fallback path.
	# Preferred path uses the rendered hand skeleton tip transform directly.
	var ws := maxf(XRServer.world_scale, 0.0001)

	# --- Left Hand ---
	if left_tracker and left_tracker.has_tracking_data:
		# Update Poke Position (Index Tip = 10)
		var left_tip_world := _get_index_tip_world_transform(left_tracker, left_hand_skeleton, ws)
		if left_poke_area and left_tip_world != Transform3D():
			left_poke_area.global_transform = left_tip_world
			_handle_poke_physics(left_poke_area, left_poke_visual, true)
		
		# Update Pinch Grab
		var pinch_strength = _get_manual_pinch_strength(left_tracker, 10)
		if physics_hand_left and physics_hand_left.has_method("set_pinch_grab"):
			physics_hand_left.set_pinch_grab(pinch_strength > _pinch_threshold)
	else:
		if left_poke_area: left_poke_area.visible = false

	# --- Right Hand ---
	if right_tracker and right_tracker.has_tracking_data:
		# Update Poke Position
		var right_tip_world := _get_index_tip_world_transform(right_tracker, right_hand_skeleton, ws)
		if right_poke_area and right_tip_world != Transform3D():
			right_poke_area.global_transform = right_tip_world
			_handle_poke_physics(right_poke_area, right_poke_visual, false)

		# Update Pinch Grab
		var pinch_strength = _get_manual_pinch_strength(right_tracker, 10)
		if physics_hand_right and physics_hand_right.has_method("set_pinch_grab"):
			physics_hand_right.set_pinch_grab(pinch_strength > _pinch_threshold)
	else:
		if right_poke_area: right_poke_area.visible = false


func _get_index_tip_world_transform(tracker: XRHandTracker, hand_skeleton_node: Node, ws: float) -> Transform3D:
	# Prefer skeleton tip pose so poke sits exactly on the rendered fingertip.
	var skeleton := hand_skeleton_node as Skeleton3D
	if skeleton and skeleton.get_bone_count() > 10:
		var tip_local: Transform3D = skeleton.get_bone_global_pose(10)
		return (skeleton.global_transform * tip_local).orthonormalized()

	if not xr_origin:
		return Transform3D()

	# Fallback to raw tracker-space joint transform.
	var index_tip: Transform3D = tracker.get_hand_joint_transform(10 as XRHandTracker.HandJoint)
	var adjusted := index_tip
	adjusted.origin /= ws
	return (xr_origin.global_transform * adjusted).orthonormalized()


func _handle_poke_physics(area: Area3D, visual: MeshInstance3D, is_left: bool) -> void:
	if not area: return
	area.visible = true
	
	var overlapping_bodies = area.get_overlapping_bodies()
	var overlapping_areas = area.get_overlapping_areas()
	var all_overlapping = overlapping_bodies + overlapping_areas
	var touching_ui: Node = null
	
	for body in all_overlapping:
		# Traverse up to find a node that handles pointer events
		var candidate = body
		for i in range(5): # Check up to 5 levels up
			if not is_instance_valid(candidate):
				break
			if candidate.has_method("handle_pointer_event"):
				touching_ui = candidate
				break
			candidate = candidate.get_parent()
		
		if touching_ui:
			break
	
	# Handle Interaction
	var last_collider = left_ui_last_collider if is_left else right_ui_last_collider
	
	if touching_ui:
		# Visual feedback
		if visual:
			var mat = visual.material_override as StandardMaterial3D
			if mat: mat.albedo_color = _poke_active_color
			
		# Interaction
		# Calculate detailed event properties
		var just_pressed = (touching_ui != last_collider)
		var event_type = "press" if just_pressed else "hold"
		
		var event = {
			"type": event_type,
			"global_position": area.global_position,
			"action_just_pressed": just_pressed,
			"action_pressed": true
		}
		touching_ui.handle_pointer_event(event)
	else:
		# Visual feedback
		if visual:
			var mat = visual.material_override as StandardMaterial3D
			if mat: mat.albedo_color = _poke_visual_color
			
		# Release previous
		if last_collider and is_instance_valid(last_collider):
			var event = {
				"type": "release",
				"global_position": area.global_position,
				"action_just_released": true,
				"action_pressed": false
			}
			last_collider.handle_pointer_event(event)

	# Update state
	if is_left:
		left_ui_last_collider = touching_ui
	else:
		right_ui_last_collider = touching_ui
