class_name TwoHandGrabV3
extends Node
## Two-Hand Grab V3 - Exact XRToolsMovementWorldGrab algorithm
##
## The KEY insight from XRTools:
## - "Grab handles" are FIXED world positions (set at grab start)
## - "Pickup positions" are current controller positions
## - Each frame: calculate angle between grab_l2r and pickup_l2r
## - Apply rotation so pickup aligns with grab
## - After rotation, controllers (pickup) have moved, so angle converges to zero
##
## The math:
## - angle = grab_l2r.signed_angle_to(pickup_l2r, up)
## - rotate_player(angle) - this is the raw angle, applied directly
## - Because player rotates, controllers rotate with it
## - Next frame, pickup_l2r has rotated too, so angle is smaller


signal player_world_grab_start
signal player_world_grab_end
signal scale_changed(new_scale: float)
signal rotation_changed(angle_rad: float)


# === Settings ===

## Smallest world scale
@export var world_scale_min := 0.1

## Largest world scale
@export var world_scale_max := 500.0

## Left hand trigger/grip action
var left_action: String = "trigger"

## Right hand trigger/grip action
var right_action: String = "trigger"

## Show visual indicators during grab
var show_visual: bool = true

## Print debug logs
var debug_logs: bool = false

## Sensitivity & Smoothing
@export var scale_sensitivity: float = 1.0
@export var rotation_sensitivity: float = 1.0
@export var translation_sensitivity: float = 1.0
@export var smoothing: float = 0.5
@export var invert_scale: bool = false


# === References (set via setup()) ===
var player_body: RigidBody3D
var left_controller: XRController3D
var right_controller: XRController3D
var xr_camera: XRCamera3D
var xr_origin: XROrigin3D


# === Grab state ===
var _active: bool = false

# Grab handles - FIXED positions in WORLD space (set at grab start, never updated)
var _left_handle: Vector3
var _right_handle: Vector3

# Initial pickup distance for scale calculation
var _pickup_distance: float = 0.0
var _initial_world_scale: float = 1.0


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
	
	# Find XROrigin3D - needed for proper VR rotation
	if left_controller:
		var parent = left_controller.get_parent()
		if parent is XROrigin3D:
			xr_origin = parent
	
	_ensure_visuals()
	if debug_logs:
		print("TwoHandGrabV3: Setup complete, xr_origin=", xr_origin)


func is_active() -> bool:
	return _active


func process_grab(_delta: float) -> bool:
	"""Call this from the movement component's physics process.
	Returns true if exclusive motion was performed (to bypass gravity)."""
	if not player_body or not left_controller or not right_controller:
		return false
	
	var left_pressed := _is_action_pressed(left_controller, left_action)
	var right_pressed := _is_action_pressed(right_controller, right_action)
	
	if left_pressed and right_pressed:
		if not _active:
			_start_grab()
		return _update_grab()
	else:
		if _active:
			_end_grab()
		return false


func _is_action_pressed(controller: XRController3D, action: String) -> bool:
	if not controller:
		return false
	var val: float = controller.get_float(action)
	# Fallback for common naming variants
	if val < 0.01 and action == "grip":
		val = controller.get_float("grip_click")
	if val < 0.01 and action == "trigger":
		val = controller.get_float("trigger_click")
	return val > 0.75


func _start_grab() -> void:
	_active = true
	
	# Store the GRAB HANDLES - these are FIXED world positions
	# They represent "where the player grabbed the world"
	_left_handle = left_controller.global_position
	_right_handle = right_controller.global_position
	
	# Store initial pickup distance and world scale for scale calculation
	_pickup_distance = _left_handle.distance_to(_right_handle)
	_initial_world_scale = XRServer.world_scale
	
	if debug_logs:
		print("TwoHandGrabV3: Grab started")
		print("  Left handle: ", _left_handle)
		print("  Right handle: ", _right_handle)
		print("  Pickup distance: ", _pickup_distance)
	
	_update_visuals()
	emit_signal("player_world_grab_start")


func _update_grab() -> bool:
	"""Update grab - exact XRTools algorithm."""
	if not _active:
		return false
	
	var up_player := Vector3.UP
	
	# === Get grab handle positions (FIXED in world space) ===
	var left_grab_pos := _left_handle
	var right_grab_pos := _right_handle
	var grab_l2r := (right_grab_pos - left_grab_pos).slide(up_player)
	var grab_mid := (left_grab_pos + right_grab_pos) * 0.5
	var _grab_distance := grab_l2r.length()
	
	# === Get pickup positions (current controller positions) ===
	var left_pickup_pos := left_controller.global_position
	var right_pickup_pos := right_controller.global_position
	var pickup_l2r := (right_pickup_pos - left_pickup_pos).slide(up_player)
	var pickup_mid := (left_pickup_pos + right_pickup_pos) * 0.5
	var pickup_distance := pickup_l2r.length()
	
	# === ROTATION ===
	# Apply rotation based on angle from grab to pickup
	# CRITICAL: Negate angle because we want to rotate player in OPPOSITE direction
	# to bring controllers (pickup) back towards the grab handles
	if grab_l2r.length_squared() > 0.0001 and pickup_l2r.length_squared() > 0.0001:
		var angle := grab_l2r.signed_angle_to(pickup_l2r, up_player)
		if abs(angle) > 0.001:
			# Apply sensitivity and smoothing
			var target_angle := -angle * rotation_sensitivity
			var step_angle := target_angle * (1.0 - smoothing)
			
			_rotate_player(step_angle, pickup_mid)
			rotation_changed.emit(step_angle)
			if debug_logs:
				print("TwoHandGrabV3: Rotation ", rad_to_deg(step_angle), "°")
	
	# === SCALE ===
	# Use "Real World" distance (normalized by world_scale) to avoid feedback loop
	# Formula: new_scale = initial_scale * (current_real_dist / initial_real_dist)
	if _pickup_distance > 0.01 and pickup_distance > 0.01:
		# Calculate "Real" distances by removing the world scale factor
		# _pickup_distance was the GAME distance at start
		# pickup_distance is the GAME distance now
		# We want how much the HANDS moved physically
		
		# Note: We must compare apples to apples.
		# _pickup_distance was recorded at _initial_world_scale
		var initial_real_dist := _pickup_distance / _initial_world_scale
		
		var current_real_dist := pickup_distance / XRServer.world_scale
		
		# Clamp minimum distance to prevent division by zero or explosive scaling
		initial_real_dist = max(initial_real_dist, 0.01)
		current_real_dist = max(current_real_dist, 0.01)
		
		var raw_ratio := 1.0
		
		if invert_scale:
			# Inverted: Pulling hands apart (current > initial) -> Scale Down (ratio < 1.0)
			raw_ratio = initial_real_dist / current_real_dist
		else:
			# Standard: Pulling hands apart (current > initial) -> Scale Up (ratio > 1.0)
			# "Stretch the world"
			raw_ratio = current_real_dist / initial_real_dist
		
		# Apply sensitivity: ratio = 1.0 + (raw_ratio - 1.0) * scale_sensitivity
		var scale_ratio := 1.0 + (raw_ratio - 1.0) * scale_sensitivity
		
		# Calculate target scale based on inputs
		var target_world_scale := _initial_world_scale * scale_ratio
		
		# Clamp target scale
		target_world_scale = clampf(target_world_scale, world_scale_min, world_scale_max)

		# Apply smoothing to the SCALE VALUE itself (Temporal Smoothing)
		# Interpolate current world scale towards the target
		var new_world_scale: float = lerp(XRServer.world_scale, target_world_scale, 1.0 - smoothing)
		
		# Safety: Encapsulate in finite check
		if not is_finite(new_world_scale) or new_world_scale < 0.001:
			if debug_logs:
				print("TwoHandGrabV3: Invalid scale detected: ", new_world_scale, " defaulting to min")
			new_world_scale = world_scale_min
			
		new_world_scale = clampf(new_world_scale, world_scale_min, world_scale_max)
		
		if not is_equal_approx(XRServer.world_scale, new_world_scale):
			# Calculate prediction before applying scale
			var old_scale: float = XRServer.world_scale
			XRServer.world_scale = new_world_scale
			scale_changed.emit(new_world_scale)
			
			# PREDICTION: Adjust pickup_mid to where it WILL be after scale application
			# This prevents "teleporting" due to the 1-frame lag in controller position updates
			if xr_origin:
				var origin_pos: Vector3 = xr_origin.global_position
				var rel_vec: Vector3 = pickup_mid - origin_pos
				# Scaling keeps Real World Position constant. P_real = P_game * Scale.
				# P_game_new = P_real / Scale_new = (P_game_old * Scale_old) / Scale_new
				var scale_factor: float = old_scale / new_world_scale
				var predicted_rel_vec: Vector3 = rel_vec * scale_factor
				pickup_mid = origin_pos + predicted_rel_vec
			
			if debug_logs:
				print("TwoHandGrabV3: Scale -> ", new_world_scale)
	
	# === OFFSET / MOVEMENT ===
	# Move the player so the world midpoint aligns with the pickup midpoint
	# This effectively keeps the world "attached" to the hands
	var offset := grab_mid - pickup_mid
	
	# Clamp offset to prevent massive jumps (e.g. if tracking glitches)
	if offset.length() > 5.0: # 5 meters per frame is huge
		offset = offset.limit_length(0.5)
	
	if offset.length_squared() > 0.000001:
		# Apply sensitivity and smoothing
		var target_offset := offset * translation_sensitivity
		var step_offset := target_offset * (1.0 - smoothing)
		
		# Limit step size for safety
		step_offset = step_offset.limit_length(0.5)
		
		_move_player(step_offset)

	_update_visuals()
	return true


func _rotate_player(angle_rad: float, pivot: Vector3) -> void:
	"""Rotate the player around the given pivot point (usually hands midpoint)."""
	if not player_body:
		return
	
	# Preserve velocities
	var lv := player_body.linear_velocity
	var av := player_body.angular_velocity
	
	# Create rotation around Y axis
	var rot_basis := Basis(Vector3.UP, angle_rad)
	
	# Transform the player body
	var xf := player_body.global_transform
	xf.origin = pivot + rot_basis * (xf.origin - pivot)
	xf.basis = rot_basis * xf.basis
	player_body.global_transform = xf
	
	player_body.linear_velocity = lv
	player_body.angular_velocity = av


func _move_player(offset: Vector3) -> void:
	"""Move the player by the given offset."""
	if not player_body:
		return
	
	# Preserve velocities
	var lv := player_body.linear_velocity
	var av := player_body.angular_velocity
	
	var xf := player_body.global_transform
	xf.origin += offset
	player_body.global_transform = xf
	
	player_body.linear_velocity = lv
	player_body.angular_velocity = av


func _end_grab() -> void:
	_active = false
	_clear_visuals()
	
	if debug_logs:
		print("TwoHandGrabV3: Grab ended, final scale=", XRServer.world_scale)
	
	emit_signal("player_world_grab_end")


# === VISUAL HELPERS ===


func _ensure_visuals() -> void:
	if not player_body or not show_visual:
		return
	
	if not _visual_root:
		_visual_root = Node3D.new()
		_visual_root.name = "TwoHandGrabV3Visuals"
		player_body.get_tree().root.add_child.call_deferred(_visual_root)
	
	if not _left_anchor_mesh:
		_left_anchor_mesh = _create_anchor_mesh(Color(0.4, 1.0, 0.4, 0.8))
		_visual_root.add_child(_left_anchor_mesh)
	
	if not _right_anchor_mesh:
		_right_anchor_mesh = _create_anchor_mesh(Color(0.4, 1.0, 0.4, 0.8))
		_visual_root.add_child(_right_anchor_mesh)
	
	if not _midpoint_mesh:
		var box := BoxMesh.new()
		box.size = Vector3(0.06, 0.06, 0.06)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.4, 1.0, 0.4, 0.9)
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
		mat.albedo_color = Color(0.4, 1.0, 0.4, 0.85)
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
	
	# Show grab handles (fixed world positions)
	if _left_anchor_mesh:
		_left_anchor_mesh.visible = true
		_left_anchor_mesh.global_position = _left_handle
	
	if _right_anchor_mesh:
		_right_anchor_mesh.visible = true
		_right_anchor_mesh.global_position = _right_handle
	
	var midpoint := (_left_handle + _right_handle) * 0.5
	if _midpoint_mesh:
		_midpoint_mesh.visible = true
		_midpoint_mesh.global_position = midpoint
	
	if _connecting_line_mesh and _connecting_line_mesh.mesh is ImmediateMesh:
		var im := _connecting_line_mesh.mesh as ImmediateMesh
		im.clear_surfaces()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		im.surface_add_vertex(_left_handle)
		im.surface_add_vertex(_right_handle)
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
