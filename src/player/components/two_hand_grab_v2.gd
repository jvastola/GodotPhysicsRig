class_name TwoHandGrabV2
extends Node
## Two-Hand Grab V2 - Horizon Worlds style world manipulation
## 
## Implements locked world point grabbing where:
## - Hands lock to world positions when grab starts
## - Scaling keeps hands at their world positions (move closer in real space = scale up)
## - Rotation uses the angle between locked world vector and current hand vector

signal grab_started()
signal grab_ended()
signal scale_changed(new_scale: float)
signal rotation_changed(angle_rad: float)

# === Settings (set by parent movement component) ===
var scale_enabled: bool = true
var rotation_enabled: bool = true
var world_scale_min: float = 0.1
var world_scale_max: float = 15.0
var left_action: String = "trigger"
var right_action: String = "trigger"
var show_visual: bool = true
var debug_logs: bool = false

# === References (set via setup()) ===
var player_body: RigidBody3D
var left_controller: XRController3D
var right_controller: XRController3D
var xr_camera: XRCamera3D

# === Grab state ===
var _active: bool = false
var _world_point_left: Vector3   # Locked world position (left hand grab point)
var _world_point_right: Vector3  # Locked world position (right hand grab point)
var _initial_world_scale: float = 1.0
var _initial_player_transform: Transform3D
var _initial_world_distance: float = 0.0
var _initial_world_midpoint: Vector3
var _initial_world_vector_2d: Vector2  # XZ plane vector for rotation reference
var _accumulated_rotation: float = 0.0

# === Visuals ===
var _visual_root: Node3D
var _left_anchor_mesh: MeshInstance3D
var _right_anchor_mesh: MeshInstance3D
var _connecting_line_mesh: MeshInstance3D
var _midpoint_mesh: MeshInstance3D


func setup(p_player_body: RigidBody3D, p_left_controller: XRController3D, p_right_controller: XRController3D, p_xr_camera: XRCamera3D = null) -> void:
	player_body = p_player_body
	left_controller = p_left_controller
	right_controller = p_right_controller
	xr_camera = p_xr_camera
	_ensure_visuals()
	if debug_logs:
		print("TwoHandGrabV2: Setup complete")


func is_active() -> bool:
	return _active


func process_grab(delta: float) -> void:
	"""Call this from the movement component's physics process."""
	if not player_body or not left_controller or not right_controller:
		return
	
	var left_pressed := _is_action_pressed(left_controller, left_action)
	var right_pressed := _is_action_pressed(right_controller, right_action)
	
	if left_pressed and right_pressed:
		if not _active:
			_start_grab()
		_update_grab(delta)
	else:
		if _active:
			_end_grab()


func _is_action_pressed(controller: XRController3D, action: String) -> bool:
	if not controller:
		return false
	if controller.has_method("get_float"):
		var val: float = controller.get_float(action)
		# Fallback for common naming variants
		if val == 0.0 and action == "grip":
			val = controller.get_float("grip_click")
		if val == 0.0 and action == "trigger":
			val = controller.get_float("trigger_click")
		return val > 0.75
	if controller.has_method("get_bool"):
		return controller.get_bool(action)
	return false


func _start_grab() -> void:
	_active = true
	
	# Lock the world positions where hands currently are
	_world_point_left = left_controller.global_position
	_world_point_right = right_controller.global_position
	
	# Store initial state
	_initial_world_scale = XRServer.world_scale
	_initial_player_transform = player_body.global_transform
	_initial_world_distance = _world_point_left.distance_to(_world_point_right)
	_initial_world_midpoint = (_world_point_left + _world_point_right) * 0.5
	
	# Initial vector for rotation reference (XZ plane)
	var world_vec := _world_point_right - _world_point_left
	_initial_world_vector_2d = Vector2(world_vec.x, world_vec.z)
	_accumulated_rotation = 0.0
	
	if debug_logs:
		print("TwoHandGrabV2: Grab started")
		print("  World points: L=", _world_point_left, " R=", _world_point_right)
		print("  Initial distance: ", _initial_world_distance)
		print("  Initial scale: ", _initial_world_scale)
	
	_update_visuals()
	grab_started.emit()


func _update_grab(_delta: float) -> void:
	if not _active:
		return
	
	var left_pos := left_controller.global_position
	var right_pos := right_controller.global_position
	
	# Current hand tracking distance and midpoint
	var current_hand_distance: float = left_pos.distance_to(right_pos)
	var current_hand_midpoint: Vector3 = (left_pos + right_pos) * 0.5
	
	# === SCALE CALCULATION ===
	# The locked world points are fixed. We need to find a scale where:
	# - The distance between world points, when viewed at the new scale, 
	#   matches the current hand distance.
	#
	# In VR: world_scale > 1 means world appears bigger (you're smaller)
	#        world_scale < 1 means world appears smaller (you're bigger)
	#
	# Tracking-to-world: larger world_scale = same tracking movement covers less world distance
	#
	# We want: current_hand_distance (world space) = _initial_world_distance (unchanged)
	# But hands moved, so we scale the world to make it match.
	#
	# If hands moved apart: we shrunk, world grew relative to us
	# If hands moved closer: we grew, world shrank relative to us
	#
	# The new scale should be: initial_scale * (initial_hand_distance / current_hand_distance)
	
	if scale_enabled and _initial_world_distance > 0.01 and current_hand_distance > 0.01:
		var scale_ratio: float = _initial_world_distance / current_hand_distance
		var target_scale: float = _initial_world_scale * scale_ratio
		target_scale = clampf(target_scale, world_scale_min, world_scale_max)
		
		if not is_equal_approx(XRServer.world_scale, target_scale):
			XRServer.world_scale = target_scale
			scale_changed.emit(target_scale)
			if debug_logs:
				print("TwoHandGrabV2: Scale -> ", target_scale, " (ratio=", scale_ratio, ")")
	
	# === ROTATION CALCULATION ===
	# Calculate how much the hand vector has rotated from the initial grab vector
	if rotation_enabled and _initial_world_vector_2d.length_squared() > 0.0001:
		var tracking_vec := right_pos - left_pos
		var tracking_vec_2d := Vector2(tracking_vec.x, tracking_vec.z)
		
		if tracking_vec_2d.length_squared() > 0.0001:
			var target_angle: float = _signed_angle_2d(_initial_world_vector_2d, tracking_vec_2d)
			var delta_rotation: float = target_angle - _accumulated_rotation
			
			# Apply rotation around the LOCKED world midpoint (not hand midpoint)
			if abs(delta_rotation) > 0.001:
				_rotate_player_around_point(-delta_rotation, _initial_world_midpoint)
				_accumulated_rotation = target_angle
				rotation_changed.emit(target_angle)
				if debug_logs:
					print("TwoHandGrabV2: Rotation delta=", rad_to_deg(delta_rotation), "° total=", rad_to_deg(target_angle), "°")
	
	# === POSITION CORRECTION ===
	# After scale and rotation, move the player so the locked world midpoint
	# appears at the current hand midpoint position.
	# 
	# The locked world midpoint is fixed in world space.
	# We need to move the player so that when looking at that point,
	# it appears at where our hand midpoint is now.
	_align_world_to_hands(current_hand_midpoint)
	
	_update_visuals()


func _align_world_to_hands(hand_midpoint: Vector3) -> void:
	"""Move player so the locked world midpoint aligns with hand midpoint."""
	if not player_body:
		return
	
	# The world midpoint is fixed in world space
	# But we need to move the player so this point appears at hand_midpoint
	#
	# Since controllers report world-space positions (affected by player position),
	# and the world midpoint is a fixed point, we need to offset the player
	# so that the controller at the midpoint would be at hand_midpoint.
	#
	# The offset is simply: where hands are - where locked midpoint is
	var offset := hand_midpoint - _initial_world_midpoint
	
	if offset.length_squared() < 0.000001:
		return
	
	# Preserve velocities
	var lv := player_body.linear_velocity
	var av := player_body.angular_velocity
	
	var xf := player_body.global_transform
	xf.origin += offset
	player_body.global_transform = xf
	
	player_body.linear_velocity = lv
	player_body.angular_velocity = av
	
	# IMPORTANT: Update the locked world midpoint to track with the hands
	# This is because we want the "lock point" to follow the player's movement
	# but remain locked relative to the hands
	_initial_world_midpoint += offset
	_world_point_left += offset
	_world_point_right += offset


func _end_grab() -> void:
	_active = false
	_clear_visuals()
	
	if debug_logs:
		print("TwoHandGrabV2: Grab ended, final scale=", XRServer.world_scale)
	
	grab_ended.emit()


func _signed_angle_2d(from: Vector2, to: Vector2) -> float:
	"""Calculate signed angle between two 2D vectors (radians)."""
	var from_n := from.normalized()
	var to_n := to.normalized()
	var dot := from_n.dot(to_n)
	var cross := from_n.x * to_n.y - from_n.y * to_n.x
	return atan2(cross, dot)


func _rotate_player_around_point(angle_rad: float, pivot: Vector3) -> void:
	"""Rotate the player body around a world-space pivot point."""
	if not player_body:
		return
	
	# Preserve velocities
	var lv := player_body.linear_velocity
	var av := player_body.angular_velocity
	
	var xf := player_body.global_transform
	var rot_basis := Basis(Vector3.UP, angle_rad)
	
	# Rotate origin around pivot
	xf.origin = pivot + rot_basis * (xf.origin - pivot)
	# Rotate the basis
	xf.basis = rot_basis * xf.basis
	
	player_body.global_transform = xf
	player_body.linear_velocity = lv
	player_body.angular_velocity = av


# === VISUAL HELPERS ===


func _ensure_visuals() -> void:
	if not player_body or not show_visual:
		return
	
	if not _visual_root:
		_visual_root = Node3D.new()
		_visual_root.name = "TwoHandGrabV2Visuals"
		# Add to scene root so visuals don't scale with player
		player_body.get_tree().root.add_child.call_deferred(_visual_root)
	
	if not _left_anchor_mesh:
		_left_anchor_mesh = _create_anchor_mesh(Color(0.2, 0.8, 1.0, 0.8))
		_visual_root.add_child(_left_anchor_mesh)
	
	if not _right_anchor_mesh:
		_right_anchor_mesh = _create_anchor_mesh(Color(1.0, 0.5, 0.2, 0.8))
		_visual_root.add_child(_right_anchor_mesh)
	
	if not _midpoint_mesh:
		var box := BoxMesh.new()
		box.size = Vector3(0.06, 0.06, 0.06)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.9, 0.2, 0.9)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_midpoint_mesh = MeshInstance3D.new()
		_midpoint_mesh.mesh = box
		_midpoint_mesh.material_override = mat
		_midpoint_mesh.visible = false
		_visual_root.add_child(_midpoint_mesh)
	
	if not _connecting_line_mesh:
		var im := ImmediateMesh.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.9, 0.3, 0.85)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_connecting_line_mesh = MeshInstance3D.new()
		_connecting_line_mesh.mesh = im
		_connecting_line_mesh.material_override = mat
		_connecting_line_mesh.visible = false
		_visual_root.add_child(_connecting_line_mesh)


func _create_anchor_mesh(color: Color) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = 0.04
	sphere.height = 0.08
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = sphere
	mesh_inst.material_override = mat
	mesh_inst.visible = false
	return mesh_inst


func _update_visuals() -> void:
	if not show_visual or not _active:
		_clear_visuals()
		return
	
	if _left_anchor_mesh:
		_left_anchor_mesh.visible = true
		_left_anchor_mesh.global_position = _world_point_left
	
	if _right_anchor_mesh:
		_right_anchor_mesh.visible = true
		_right_anchor_mesh.global_position = _world_point_right
	
	var midpoint := (_world_point_left + _world_point_right) * 0.5
	if _midpoint_mesh:
		_midpoint_mesh.visible = true
		_midpoint_mesh.global_position = midpoint
	
	if _connecting_line_mesh and _connecting_line_mesh.mesh is ImmediateMesh:
		var im := _connecting_line_mesh.mesh as ImmediateMesh
		im.clear_surfaces()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		im.surface_add_vertex(_world_point_left)
		im.surface_add_vertex(_world_point_right)
		# Add line to midpoint
		im.surface_add_vertex(_world_point_left)
		im.surface_add_vertex(midpoint)
		im.surface_add_vertex(_world_point_right)
		im.surface_add_vertex(midpoint)
		im.surface_end()
		_connecting_line_mesh.visible = true


func _clear_visuals() -> void:
	if _left_anchor_mesh:
		_left_anchor_mesh.visible = false
	if _right_anchor_mesh:
		_right_anchor_mesh.visible = false
	if _midpoint_mesh:
		_midpoint_mesh.visible = false
	if _connecting_line_mesh:
		_connecting_line_mesh.visible = false
		if _connecting_line_mesh.mesh is ImmediateMesh:
			(_connecting_line_mesh.mesh as ImmediateMesh).clear_surfaces()


func _exit_tree() -> void:
	if _visual_root and is_instance_valid(_visual_root):
		_visual_root.queue_free()
