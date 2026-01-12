class_name HandMovementComponent
extends Node

## Hand Movement Component
## Uses middle finger pinch gesture to move the player like one-hand world grab.
## When pinching, the pinch position becomes an anchor point.
## Moving the hand while pinching moves the player based on the offset.

signal hand_movement_started(hand_idx: int)
signal hand_movement_ended(hand_idx: int)

## Grab mode determines how movement is calculated
enum GrabMode { RELATIVE, ANCHORED }

## Enable/disable the hand movement functionality
@export var enabled: bool = true

## Grab mode: RELATIVE moves anchor with player, ANCHORED keeps anchor fixed in world space
@export var grab_mode: GrabMode = GrabMode.RELATIVE

## Pinch threshold for detecting grab (0.0 - 1.0)
@export_range(0.5, 1.0, 0.05) var pinch_threshold: float = 0.8

## Movement sensitivity multiplier
@export_range(0.05, 2.0, 0.05) var movement_sensitivity: float = 0.25

## Invert movement direction (pull to move forward vs push to move forward)
@export var invert_direction: bool = true

## Apply velocity on release for momentum
@export var apply_release_velocity: bool = true

## Show visual line from anchor to hand
@export var show_visual: bool = true

## Visual line color
@export var visual_color: Color = Color(0.9, 0.5, 0.2, 0.9)

## Anchor sphere color
@export var anchor_color: Color = Color(0.9, 0.5, 0.2, 0.8)

## Debug logging
@export var debug_logs: bool = false

# References (set via setup())
var player_body: RigidBody3D
var xr_origin: XROrigin3D

# Hand tracking state
var _left_tracker: XRHandTracker
var _right_tracker: XRHandTracker

# Movement state per hand (0 = left, 1 = right)
var _hand_active: Array[bool] = [false, false]
var _hand_anchor_world: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _hand_initial_pinch_pos: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]  # For relative mode
var _hand_initial_body_pos: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _hand_prev_body_pos: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _hand_last_velocity: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]

# Visual helpers
var _visual_root: Node3D
var _anchor_meshes: Array[MeshInstance3D] = [null, null]
var _line_meshes: Array[MeshInstance3D] = [null, null]
var _anchor_mat: StandardMaterial3D
var _line_mat: StandardMaterial3D


func setup(p_player_body: RigidBody3D, p_xr_origin: XROrigin3D) -> void:
	player_body = p_player_body
	xr_origin = p_xr_origin
	if debug_logs:
		print("HandMovementComponent: Setup complete")


func _physics_process(delta: float) -> void:
	if not enabled or not player_body:
		_release_all()
		return
	
	# Get hand trackers
	_left_tracker = XRServer.get_tracker("/user/hand_tracker/left") as XRHandTracker
	_right_tracker = XRServer.get_tracker("/user/hand_tracker/right") as XRHandTracker
	
	# Process each hand
	_process_hand(0, _left_tracker, delta)  # Left hand
	_process_hand(1, _right_tracker, delta)  # Right hand


func _process_hand(hand_idx: int, tracker: XRHandTracker, delta: float) -> void:
	if not tracker or not tracker.has_tracking_data:
		if _hand_active[hand_idx]:
			_end_hand_movement(hand_idx)
		return
	
	# Get middle finger pinch strength
	var pinch_strength := _get_middle_pinch_strength(tracker)
	var is_pinching := pinch_strength > pinch_threshold
	
	# Get current pinch position (midpoint between thumb tip and middle finger tip)
	var pinch_pos := _get_pinch_position(tracker)
	
	if is_pinching:
		if not _hand_active[hand_idx]:
			_start_hand_movement(hand_idx, pinch_pos)
		_update_hand_movement(hand_idx, pinch_pos, delta)
	else:
		if _hand_active[hand_idx]:
			_end_hand_movement(hand_idx)


func _get_middle_pinch_strength(tracker: XRHandTracker) -> float:
	# Joint indices: Thumb Tip (5), Middle Tip (15)
	var thumb_tip_transform := tracker.get_hand_joint_transform(5 as XRHandTracker.HandJoint)
	var middle_tip_transform := tracker.get_hand_joint_transform(15 as XRHandTracker.HandJoint)
	
	if thumb_tip_transform == Transform3D() or middle_tip_transform == Transform3D():
		return 0.0
	
	var distance := thumb_tip_transform.origin.distance_to(middle_tip_transform.origin)
	
	# Map distance to pinch strength
	# 7cm or more = 0.0 (fully open)
	# 2cm or less = 1.0 (fully pinched)
	var max_dist := 0.07
	var min_dist := 0.02
	
	return clamp((max_dist - distance) / (max_dist - min_dist), 0.0, 1.0)


func _get_pinch_position(tracker: XRHandTracker) -> Vector3:
	# Get midpoint between thumb tip and middle finger tip
	var thumb_tip := tracker.get_hand_joint_transform(5 as XRHandTracker.HandJoint)
	var middle_tip := tracker.get_hand_joint_transform(15 as XRHandTracker.HandJoint)
	
	if thumb_tip == Transform3D() or middle_tip == Transform3D():
		return Vector3.ZERO
	
	# Convert to global space if we have xr_origin
	var thumb_pos := thumb_tip.origin
	var middle_pos := middle_tip.origin
	
	if xr_origin:
		thumb_pos = xr_origin.global_transform * thumb_pos
		middle_pos = xr_origin.global_transform * middle_pos
	
	return (thumb_pos + middle_pos) * 0.5


func _start_hand_movement(hand_idx: int, pinch_pos: Vector3) -> void:
	_ensure_visuals()
	_hand_active[hand_idx] = true
	_hand_anchor_world[hand_idx] = pinch_pos
	_hand_initial_pinch_pos[hand_idx] = pinch_pos  # Store initial pinch for relative mode
	_hand_initial_body_pos[hand_idx] = player_body.global_position
	_hand_prev_body_pos[hand_idx] = player_body.global_position
	_hand_last_velocity[hand_idx] = Vector3.ZERO
	
	if debug_logs:
		var hand_name := "Left" if hand_idx == 0 else "Right"
		var mode_name := "ANCHORED" if grab_mode == GrabMode.ANCHORED else "RELATIVE"
		print("HandMovementComponent: %s hand movement started at %s (mode: %s)" % [hand_name, pinch_pos, mode_name])
	
	hand_movement_started.emit(hand_idx)
	_update_visual(hand_idx, pinch_pos)


func _update_hand_movement(hand_idx: int, pinch_pos: Vector3, delta: float) -> void:
	if not _hand_active[hand_idx] or not player_body:
		return
	
	var offset: Vector3
	
	if grab_mode == GrabMode.ANCHORED:
		# ANCHORED mode: The anchor is a fixed point in world space.
		# The player moves so that the current pinch position stays at the anchor.
		# This is like grabbing a fixed point in space and pulling yourself to it.
		# offset = where anchor is - where pinch currently is
		# Moving player by this offset will bring the pinch back to the anchor
		offset = _hand_anchor_world[hand_idx] - pinch_pos
		# No sensitivity scaling in anchored mode - direct 1:1 movement
	else:
		# RELATIVE mode: calculate offset from initial pinch to current pinch
		offset = (pinch_pos - _hand_initial_pinch_pos[hand_idx]) * movement_sensitivity
		# Invert if needed (only for relative mode)
		if invert_direction:
			offset *= -1.0
	
	# Apply movement
	var prev_pos := player_body.global_position
	var xf := player_body.global_transform
	xf.origin += offset
	player_body.global_transform = xf
	
	# Update tracking based on mode
	if grab_mode == GrabMode.RELATIVE:
		# In relative mode, update initial pinch to current (so movement is incremental)
		_hand_initial_pinch_pos[hand_idx] = pinch_pos
		# Anchor follows player for visual
		_hand_anchor_world[hand_idx] += offset
	# In anchored mode, anchor stays fixed in world space
	
	# Calculate velocity for release momentum
	var dt: float = maxf(delta, 0.0001)
	var new_vel: Vector3 = (xf.origin - prev_pos) / dt
	player_body.linear_velocity = new_vel
	_hand_prev_body_pos[hand_idx] = xf.origin
	_hand_last_velocity[hand_idx] = new_vel
	
	_update_visual(hand_idx, pinch_pos)


func _end_hand_movement(hand_idx: int) -> void:
	_hand_active[hand_idx] = false
	
	if not apply_release_velocity and player_body:
		player_body.linear_velocity = Vector3.ZERO
	
	_hand_last_velocity[hand_idx] = Vector3.ZERO
	
	if debug_logs:
		var hand_name := "Left" if hand_idx == 0 else "Right"
		print("HandMovementComponent: %s hand movement ended" % hand_name)
	
	hand_movement_ended.emit(hand_idx)
	_clear_visual(hand_idx)


func _release_all() -> void:
	for i in range(2):
		if _hand_active[i]:
			_end_hand_movement(i)


# === Visual Helpers ===

func _ensure_visuals() -> void:
	if not player_body or not show_visual:
		return
	
	if not _visual_root:
		_visual_root = Node3D.new()
		_visual_root.name = "HandMovementVisuals"
		player_body.add_child(_visual_root)
	
	# Create shared materials
	if not _anchor_mat:
		_anchor_mat = StandardMaterial3D.new()
		_anchor_mat.albedo_color = anchor_color
		_anchor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_anchor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	if not _line_mat:
		_line_mat = StandardMaterial3D.new()
		_line_mat.albedo_color = visual_color
		_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	# Create visuals for each hand
	for i in range(2):
		if not _anchor_meshes[i]:
			var sphere := SphereMesh.new()
			sphere.radius = 0.03
			sphere.height = 0.06
			_anchor_meshes[i] = MeshInstance3D.new()
			_anchor_meshes[i].mesh = sphere
			_anchor_meshes[i].material_override = _anchor_mat
			_anchor_meshes[i].visible = false
			_visual_root.add_child(_anchor_meshes[i])
		
		if not _line_meshes[i]:
			var im := ImmediateMesh.new()
			_line_meshes[i] = MeshInstance3D.new()
			_line_meshes[i].mesh = im
			_line_meshes[i].material_override = _line_mat
			_line_meshes[i].visible = false
			_visual_root.add_child(_line_meshes[i])


func _update_visual(hand_idx: int, pinch_pos: Vector3) -> void:
	if not show_visual:
		_clear_visual(hand_idx)
		return
	
	_ensure_visuals()
	
	var anchor_mesh := _anchor_meshes[hand_idx]
	var line_mesh := _line_meshes[hand_idx]
	
	if not anchor_mesh or not line_mesh:
		return
	
	# Update anchor sphere position
	anchor_mesh.global_position = _hand_anchor_world[hand_idx]
	anchor_mesh.visible = true
	
	# Update line from anchor to current pinch position
	if line_mesh.mesh is ImmediateMesh:
		var im := line_mesh.mesh as ImmediateMesh
		var anchor_local := _visual_root.to_local(_hand_anchor_world[hand_idx]) if _visual_root else _hand_anchor_world[hand_idx]
		var pinch_local := _visual_root.to_local(pinch_pos) if _visual_root else pinch_pos
		
		im.clear_surfaces()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		im.surface_add_vertex(anchor_local)
		im.surface_add_vertex(pinch_local)
		im.surface_end()
		line_mesh.visible = true


func _clear_visual(hand_idx: int) -> void:
	var anchor_mesh := _anchor_meshes[hand_idx]
	var line_mesh := _line_meshes[hand_idx]
	
	if anchor_mesh:
		anchor_mesh.visible = false
	
	if line_mesh:
		line_mesh.visible = false
		if line_mesh.mesh is ImmediateMesh:
			var im := line_mesh.mesh as ImmediateMesh
			im.clear_surfaces()
