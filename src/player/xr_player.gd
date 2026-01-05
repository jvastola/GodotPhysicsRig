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

# Hand Tracking
const CAPSULE_MATERIAL = preload("res://capsule_material.tres")

@onready var left_hand_ray_cast: RayCast3D = $PlayerBody/XROrigin3D/LeftController/RayCast3D
@onready var left_hand_tracker_node: XRNode3D = $PlayerBody/XROrigin3D/LeftHandTracker
@onready var left_hand_skeleton: OpenXRFbHandTrackingMesh = $PlayerBody/XROrigin3D/LeftHandTracker/OpenXRFbHandTrackingMesh
@onready var right_hand_ray_cast: RayCast3D = $PlayerBody/XROrigin3D/RightController/RayCast3D
@onready var right_hand_tracker_node: XRNode3D = $PlayerBody/XROrigin3D/RightHandTracker
@onready var right_hand_skeleton: OpenXRFbHandTrackingMesh = $PlayerBody/XROrigin3D/RightHandTracker/OpenXRFbHandTrackingMesh

var fb_capsule_ext
var left_capsules_loaded := false
var right_capsules_loaded := false
var _left_skeleton_logged := false  # Debug: only log bone count once
var _right_skeleton_logged := false  # Debug: only log bone count once
var xr_interface: XRInterface
@onready var hand_tracking_ui = get_tree().root.find_child("HandTracking2DUI", true, false)

var _left_index_pinch_active := false
var _right_index_pinch_active := false


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
@export var show_body_mesh: bool = true
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
	
	if head_mesh:
		head_mesh.visible = show_head_mesh
	
	if body_mesh:
		body_mesh.visible = show_body_mesh
	
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
	print("XRPlayer: _add_mesh_group called for '", p_group, "', parent: ", p_parent.name if p_parent else "NULL")
	var mesh_count := 0
	for child in p_parent.get_children():
		if child is MeshInstance3D:
			child.add_to_group(p_group)
			# Ensure skinning is active for the generated mesh
			if p_parent is OpenXRFbHandTrackingMesh:
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
		var bone_transform: Transform3D = hand_tracker.get_hand_joint_transform(joint_idx)
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
	var thumb_tip_transform = tracker.get_hand_joint_transform(5)
	var finger_tip_transform = tracker.get_hand_joint_transform(joint_idx)
	
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


func _on_left_controller_input_float_changed(name: String, value: float) -> void:
	# Handled via polling in _process for diagnostic UI
	# print("L Float: ", name, " ", value)
	pass


func _on_right_controller_input_float_changed(name: String, value: float) -> void:
	# Handled via polling in _process for diagnostic UI
	# print("R Float: ", name, " ", value)
	pass


func _on_left_controller_button_pressed(name: String) -> void:
	print("XRPlayer Left Button: ", name)
	# Keep controller events for non-hand-tracking or system-level signals
	# but diagnostic UI lights are handled by polling in _process for accuracy
	
	if name == "index_pinch":
		_left_index_pinch_active = true


func _on_left_controller_button_released(name: String) -> void:
	if name == "index_pinch":
		left_hand_ray_cast.enabled = false

func _on_right_controller_button_pressed(name: String) -> void:
	print("XRPlayer Right Button: ", name)
	if name == "index_pinch":
		_right_index_pinch_active = true


func _on_right_controller_button_released(name: String) -> void:
	if name == "index_pinch":
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
