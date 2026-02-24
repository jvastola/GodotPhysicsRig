extends Node
class_name JoystickSelectionManager

# Manages multi-object selection for the joystick tool

signal selection_changed(selected_objects: Array)

var selected_objects: Array[RigidBody3D] = []
var bounding_box: MeshInstance3D = null
var bounding_box_mesh: ImmediateMesh = null
var bounding_box_collision: StaticBody3D = null
var is_selecting: bool = false
var _selection_handles: Array[Area3D] = []
var _last_center: Vector3 = Vector3.ZERO
var _last_half_size: Vector3 = Vector3.ZERO
var _last_rotation: Basis = Basis.IDENTITY  # Store rotation for oriented bounding box
var _active_handle: Area3D = null
var _active_handle_mode: String = ""  # "translate", "scale", or "rotate"
var _drag_start_pos: Vector3 = Vector3.ZERO
var _drag_axis: Vector3 = Vector3.ZERO
var _drag_initial_scale: Vector3 = Vector3.ONE
var _drag_initial_positions: Array[Vector3] = []  # Store initial positions for bounds-based scaling
var _drag_initial_rotations: Array[Basis] = []  # Store initial rotations for all objects
var _drag_scale_anchor: Vector3 = Vector3.ZERO  # The point that stays fixed during scaling
var _drag_initial_rotation: Basis = Basis.IDENTITY  # Kept for compatibility
var _drag_perpendicular_start: Vector3 = Vector3.ZERO
var _is_grabbing_box: bool = false
var _grab_offsets: Array[Vector3] = []
var _grab_hand: RigidBody3D = null
var _grab_hand_basis: Basis = Basis.IDENTITY
var _object_local_transforms: Array[Transform3D] = []

# Two-hand grab state
var _is_two_hand_grab: bool = false
var _second_grab_hand: RigidBody3D = null
var _initial_hand_distance: float = 0.0
var _initial_hand_direction: Vector3 = Vector3.ZERO
var _initial_selection_center: Vector3 = Vector3.ZERO
var _initial_selection_scale: float = 1.0
var _object_initial_transforms: Array[Transform3D] = []
var _network_manager: Node = null
var _owned_selected_object_ids: Dictionary = {} # object_id -> true while this manager holds ownership
var _ownership_request_msec: Dictionary = {} # object_id -> last ownership request tick
var _last_scale_sync_msec: Dictionary = {} # object_id -> msec
var _last_synced_scale: Dictionary = {} # object_id -> Vector3

const SCALE_SYNC_INTERVAL_MS: int = 50
const SCALE_SYNC_EPSILON: float = 0.0005
const OWNERSHIP_REQUEST_RETRY_MS: int = 250

# Handle settings (from transform tool)
var handle_length: float = 0.15
var handle_thickness: float = 0.015
var handle_offset: float = 0.05
var handle_color_x: Color = Color(1.0, 0.3, 0.3, 0.85)
var handle_color_y: Color = Color(0.3, 1.0, 0.3, 0.85)
var handle_color_z: Color = Color(0.3, 0.5, 1.0, 0.85)

func _ready() -> void:
	_create_bounding_box()
	_setup_selection_handles()
	_network_manager = _get_network_manager()


func _exit_tree() -> void:
	_release_all_owned_selection_objects()


func _get_network_manager() -> Node:
	if _network_manager and is_instance_valid(_network_manager):
		return _network_manager
	_network_manager = get_node_or_null("/root/NetworkManager")
	return _network_manager

func _create_bounding_box() -> void:
	# Create edge-only wireframe bounding box using ImmediateMesh
	bounding_box_mesh = ImmediateMesh.new()
	bounding_box = MeshInstance3D.new()
	bounding_box.name = "SelectionBounds"
	bounding_box.mesh = bounding_box_mesh
	
	# Create wireframe material (edge-only, no fill) with depth test
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.2, 0.8, 1.0, 1.0)
	material.no_depth_test = false  # Enable depth test so it doesn't show through objects
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	bounding_box.material_override = material
	
	bounding_box.visible = false
	add_child(bounding_box)
	
	# Create collision for grabbing the selection
	bounding_box_collision = StaticBody3D.new()
	bounding_box_collision.collision_layer = 256  # Layer 9 for selection bounding box
	bounding_box_collision.collision_mask = 0
	
	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = BoxShape3D.new()
	bounding_box_collision.add_child(collision_shape)
	bounding_box_collision.visible = false
	
	add_child(bounding_box_collision)

func start_selection() -> void:
	is_selecting = true
	clear_selection()

func add_to_selection(body: RigidBody3D) -> void:
	if body and body.is_in_group("selectable_shapes") and body not in selected_objects:
		selected_objects.append(body)
		_claim_network_ownership_for_object(body)
		print("JoystickSelection: Added ", body.name, " to selection (", selected_objects.size(), " total)")
		_update_bounding_box()
		selection_changed.emit(selected_objects)

func remove_from_selection(body: RigidBody3D) -> void:
	if body in selected_objects:
		selected_objects.erase(body)
		_release_network_ownership_for_object(body)
		print("JoystickSelection: Removed ", body.name, " from selection (", selected_objects.size(), " total)")
		_update_bounding_box()
		selection_changed.emit(selected_objects)

func end_selection() -> void:
	is_selecting = false
	if selected_objects.size() > 0:
		print("JoystickSelection: Selection complete with ", selected_objects.size(), " objects")
		_update_bounding_box()
	else:
		clear_selection()

func clear_selection() -> void:
	var objects_to_release: Array[RigidBody3D] = selected_objects.duplicate()
	if not objects_to_release.is_empty():
		_broadcast_selected_transform_updates(true)
	selected_objects.clear()
	for obj in objects_to_release:
		_release_network_ownership_for_object(obj)
	if bounding_box:
		bounding_box.visible = false
	if bounding_box_collision:
		bounding_box_collision.visible = false
	_hide_handles()
	selection_changed.emit(selected_objects)
	print("JoystickSelection: Cleared selection, hiding handles")

func _update_bounding_box() -> void:
	if selected_objects.is_empty():
		if bounding_box:
			bounding_box.visible = false
		if bounding_box_collision:
			bounding_box_collision.visible = false
		_hide_handles()
		return
	
	# Calculate center and average rotation from selected objects
	var center = Vector3.ZERO
	var avg_basis = Basis.IDENTITY
	var valid_count = 0
	
	for obj in selected_objects:
		if is_instance_valid(obj):
			center += obj.global_position
			# Average the rotation (simplified - just use first object's rotation for now)
			if valid_count == 0:
				avg_basis = obj.global_transform.basis.orthonormalized()
			valid_count += 1
	
	if valid_count == 0:
		if bounding_box:
			bounding_box.visible = false
		if bounding_box_collision:
			bounding_box_collision.visible = false
		_hide_handles()
		return
	
	center /= valid_count
	
	# Calculate local AABB in the rotated space
	var local_min = Vector3(INF, INF, INF)
	var local_max = Vector3(-INF, -INF, -INF)
	
	for obj in selected_objects:
		if not is_instance_valid(obj):
			continue
		
		# Get the actual AABB from mesh instances
		for child in obj.get_children():
			if child is MeshInstance3D:
				var mesh_inst = child as MeshInstance3D
				if mesh_inst.mesh:
					# Get mesh AABB and transform it to world space
					var mesh_aabb = mesh_inst.mesh.get_aabb()
					var global_transform = mesh_inst.global_transform
					
					# Transform AABB corners to world space, then to local rotated space
					var corners = [
						global_transform * Vector3(mesh_aabb.position.x, mesh_aabb.position.y, mesh_aabb.position.z),
						global_transform * Vector3(mesh_aabb.position.x + mesh_aabb.size.x, mesh_aabb.position.y, mesh_aabb.position.z),
						global_transform * Vector3(mesh_aabb.position.x, mesh_aabb.position.y + mesh_aabb.size.y, mesh_aabb.position.z),
						global_transform * Vector3(mesh_aabb.position.x, mesh_aabb.position.y, mesh_aabb.position.z + mesh_aabb.size.z),
						global_transform * Vector3(mesh_aabb.position.x + mesh_aabb.size.x, mesh_aabb.position.y + mesh_aabb.size.y, mesh_aabb.position.z),
						global_transform * Vector3(mesh_aabb.position.x + mesh_aabb.size.x, mesh_aabb.position.y, mesh_aabb.position.z + mesh_aabb.size.z),
						global_transform * Vector3(mesh_aabb.position.x, mesh_aabb.position.y + mesh_aabb.size.y, mesh_aabb.position.z + mesh_aabb.size.z),
						global_transform * Vector3(mesh_aabb.position.x + mesh_aabb.size.x, mesh_aabb.position.y + mesh_aabb.size.y, mesh_aabb.position.z + mesh_aabb.size.z),
					]
					
					# Transform corners to local rotated space
					for corner in corners:
						var local_corner = avg_basis.inverse() * (corner - center)
						local_min.x = min(local_min.x, local_corner.x)
						local_min.y = min(local_min.y, local_corner.y)
						local_min.z = min(local_min.z, local_corner.z)
						local_max.x = max(local_max.x, local_corner.x)
						local_max.y = max(local_max.y, local_corner.y)
						local_max.z = max(local_max.z, local_corner.z)
	
	if local_min.x == INF:  # No valid AABBs found
		if bounding_box:
			bounding_box.visible = false
		if bounding_box_collision:
			bounding_box_collision.visible = false
		_hide_handles()
		return
	
	# Calculate size and center in local space
	var local_size = local_max - local_min
	var local_center = (local_min + local_max) * 0.5
	
	# Transform local center back to world space
	var world_center = center + avg_basis * local_center
	
	# Store for handle positioning
	_last_center = world_center
	_last_half_size = local_size * 0.5
	_last_rotation = avg_basis
	
	# Draw oriented bounding box
	_draw_oriented_selection_bounds(world_center, local_size, avg_basis)
	
	# Update collision
	if bounding_box_collision:
		bounding_box_collision.global_position = world_center
		bounding_box_collision.global_transform.basis = avg_basis
		var collision_shape = bounding_box_collision.get_child(0) as CollisionShape3D
		if collision_shape:
			var box_shape = collision_shape.shape as BoxShape3D
			if box_shape:
				box_shape.size = local_size
		bounding_box_collision.visible = true
	
	# Position handles
	_position_handles(_last_center, _last_half_size)

func _draw_selection_bounds(aabb: AABB) -> void:
	if not bounding_box_mesh:
		return
	
	bounding_box_mesh.clear_surfaces()
	bounding_box_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	var min_v := aabb.position
	var max_v := aabb.position + aabb.size
	
	# 8 corners of the box
	var p0 := Vector3(min_v.x, min_v.y, min_v.z)
	var p1 := Vector3(max_v.x, min_v.y, min_v.z)
	var p2 := Vector3(max_v.x, min_v.y, max_v.z)
	var p3 := Vector3(min_v.x, min_v.y, max_v.z)
	var p4 := Vector3(min_v.x, max_v.y, min_v.z)
	var p5 := Vector3(max_v.x, max_v.y, min_v.z)
	var p6 := Vector3(max_v.x, max_v.y, max_v.z)
	var p7 := Vector3(min_v.x, max_v.y, max_v.z)
	
	# Bottom square
	bounding_box_mesh.surface_add_vertex(p0); bounding_box_mesh.surface_add_vertex(p1)
	bounding_box_mesh.surface_add_vertex(p1); bounding_box_mesh.surface_add_vertex(p2)
	bounding_box_mesh.surface_add_vertex(p2); bounding_box_mesh.surface_add_vertex(p3)
	bounding_box_mesh.surface_add_vertex(p3); bounding_box_mesh.surface_add_vertex(p0)
	
	# Top square
	bounding_box_mesh.surface_add_vertex(p4); bounding_box_mesh.surface_add_vertex(p5)
	bounding_box_mesh.surface_add_vertex(p5); bounding_box_mesh.surface_add_vertex(p6)
	bounding_box_mesh.surface_add_vertex(p6); bounding_box_mesh.surface_add_vertex(p7)
	bounding_box_mesh.surface_add_vertex(p7); bounding_box_mesh.surface_add_vertex(p4)
	
	# Vertical edges
	bounding_box_mesh.surface_add_vertex(p0); bounding_box_mesh.surface_add_vertex(p4)
	bounding_box_mesh.surface_add_vertex(p1); bounding_box_mesh.surface_add_vertex(p5)
	bounding_box_mesh.surface_add_vertex(p2); bounding_box_mesh.surface_add_vertex(p6)
	bounding_box_mesh.surface_add_vertex(p3); bounding_box_mesh.surface_add_vertex(p7)
	
	bounding_box_mesh.surface_end()
	
	bounding_box.visible = true

func _draw_oriented_selection_bounds(center: Vector3, size: Vector3, rotation: Basis) -> void:
	"""Draw an oriented bounding box that rotates with the selection"""
	if not bounding_box_mesh:
		return
	
	bounding_box_mesh.clear_surfaces()
	bounding_box_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	var half_size = size * 0.5
	
	# 8 corners in local space
	var local_corners = [
		Vector3(-half_size.x, -half_size.y, -half_size.z),  # p0
		Vector3(half_size.x, -half_size.y, -half_size.z),   # p1
		Vector3(half_size.x, -half_size.y, half_size.z),    # p2
		Vector3(-half_size.x, -half_size.y, half_size.z),   # p3
		Vector3(-half_size.x, half_size.y, -half_size.z),   # p4
		Vector3(half_size.x, half_size.y, -half_size.z),    # p5
		Vector3(half_size.x, half_size.y, half_size.z),     # p6
		Vector3(-half_size.x, half_size.y, half_size.z),    # p7
	]
	
	# Transform corners to world space
	var world_corners: Array[Vector3] = []
	for local_corner in local_corners:
		world_corners.append(center + rotation * local_corner)
	
	# Bottom square
	bounding_box_mesh.surface_add_vertex(world_corners[0]); bounding_box_mesh.surface_add_vertex(world_corners[1])
	bounding_box_mesh.surface_add_vertex(world_corners[1]); bounding_box_mesh.surface_add_vertex(world_corners[2])
	bounding_box_mesh.surface_add_vertex(world_corners[2]); bounding_box_mesh.surface_add_vertex(world_corners[3])
	bounding_box_mesh.surface_add_vertex(world_corners[3]); bounding_box_mesh.surface_add_vertex(world_corners[0])
	
	# Top square
	bounding_box_mesh.surface_add_vertex(world_corners[4]); bounding_box_mesh.surface_add_vertex(world_corners[5])
	bounding_box_mesh.surface_add_vertex(world_corners[5]); bounding_box_mesh.surface_add_vertex(world_corners[6])
	bounding_box_mesh.surface_add_vertex(world_corners[6]); bounding_box_mesh.surface_add_vertex(world_corners[7])
	bounding_box_mesh.surface_add_vertex(world_corners[7]); bounding_box_mesh.surface_add_vertex(world_corners[4])
	
	# Vertical edges
	bounding_box_mesh.surface_add_vertex(world_corners[0]); bounding_box_mesh.surface_add_vertex(world_corners[4])
	bounding_box_mesh.surface_add_vertex(world_corners[1]); bounding_box_mesh.surface_add_vertex(world_corners[5])
	bounding_box_mesh.surface_add_vertex(world_corners[2]); bounding_box_mesh.surface_add_vertex(world_corners[6])
	bounding_box_mesh.surface_add_vertex(world_corners[3]); bounding_box_mesh.surface_add_vertex(world_corners[7])
	
	bounding_box_mesh.surface_end()
	
	bounding_box.visible = true

func get_selection_center() -> Vector3:
	if selected_objects.is_empty():
		return Vector3.ZERO
	
	var sum = Vector3.ZERO
	for obj in selected_objects:
		if is_instance_valid(obj):
			sum += obj.global_position
	
	return sum / selected_objects.size()

func is_point_in_bounding_box(point: Vector3) -> bool:
	if selected_objects.is_empty():
		return false
	
	# Check if point is inside the oriented bounding box
	if _last_half_size == Vector3.ZERO:
		return false
	
	# Convert point to local space relative to bounding box center and rotation
	var local_point = _last_rotation.inverse() * (point - _last_center)
	
	# Check if within bounds in local space
	return abs(local_point.x) <= _last_half_size.x and \
	       abs(local_point.y) <= _last_half_size.y and \
	       abs(local_point.z) <= _last_half_size.z

func grab_selection(hand: RigidBody3D, grab_point: Vector3) -> void:
	if selected_objects.is_empty():
		return
	_claim_network_ownership_for_selection()
	
	# Check if this is a second hand grabbing (two-hand mode)
	if _is_grabbing_box and hand != _grab_hand:
		_start_two_hand_grab(hand, grab_point)
		return
	
	print("JoystickSelection: Grabbing selection box of ", selected_objects.size(), " objects at ", grab_point)
	
	_grab_hand = hand
	_drag_start_pos = grab_point
	_is_grabbing_box = true
	
	# Store the hand's current basis (rotation)
	if hand:
		_grab_hand_basis = hand.global_transform.basis
	else:
		_grab_hand_basis = Basis.IDENTITY
	
	# Store each object's transform relative to the grab point
	_object_local_transforms.clear()
	_grab_offsets.clear()
	
	for obj in selected_objects:
		if is_instance_valid(obj):
			# Store offset from grab point
			var offset = obj.global_position - grab_point
			_grab_offsets.append(offset)
			
			# Store the object's transform relative to the hand's basis
			var local_offset = _grab_hand_basis.inverse() * offset
			var local_rotation = _grab_hand_basis.inverse() * obj.global_transform.basis
			_object_local_transforms.append(Transform3D(local_rotation, local_offset))

func _start_two_hand_grab(second_hand: RigidBody3D, grab_point: Vector3) -> void:
	"""Start two-hand manipulation mode - keeps both grab points fixed"""
	if not _grab_hand or not is_instance_valid(_grab_hand):
		return
	
	print("JoystickSelection: Starting two-hand grab mode")
	
	_is_two_hand_grab = true
	_second_grab_hand = second_hand
	
	# Get the current hand positions
	var hand1_pos = _grab_hand.global_position
	var hand2_pos = second_hand.global_position
	
	# Store initial hand configuration
	_initial_hand_distance = hand1_pos.distance_to(hand2_pos)
	_initial_hand_direction = (hand2_pos - hand1_pos).normalized()
	
	# The center should be at the midpoint between the two hands
	# This is where we'll calculate transforms from
	_initial_selection_center = (hand1_pos + hand2_pos) * 0.5
	
	# Store each object's transform relative to this initial center
	_object_initial_transforms.clear()
	for obj in selected_objects:
		if is_instance_valid(obj):
			# Store current position relative to the center between hands
			var offset = obj.global_position - _initial_selection_center
			# Store current basis (rotation and scale)
			var current_basis = obj.global_transform.basis
			_object_initial_transforms.append(Transform3D(current_basis, offset))
	
	print("JoystickSelection: Two-hand grab initialized - center at ", _initial_selection_center)

func update_box_grab(current_pos: Vector3) -> void:
	"""Update box grab - move and rotate all objects with the hand"""
	if not _is_grabbing_box or selected_objects.is_empty():
		return
	
	# Two-hand mode: scale and rotate based on both hands
	if _is_two_hand_grab and _second_grab_hand and is_instance_valid(_second_grab_hand):
		_update_two_hand_grab()
		_broadcast_selected_transform_updates()
		return
	
	# Single-hand mode: follow hand rotation
	# Get current hand basis (rotation)
	var current_basis: Basis = Basis.IDENTITY
	if _grab_hand and is_instance_valid(_grab_hand):
		current_basis = _grab_hand.global_transform.basis
	
	# Calculate rotation delta from initial grab
	var rotation_delta = current_basis * _grab_hand_basis.inverse()
	
	# Update all objects based on their stored local transforms
	for i in range(selected_objects.size()):
		if i < _object_local_transforms.size() and is_instance_valid(selected_objects[i]):
			var obj = selected_objects[i]
			var local_transform = _object_local_transforms[i]
			
			# Apply rotation to the local offset and rotation
			var world_offset = current_basis * local_transform.origin
			var world_rotation = current_basis * local_transform.basis
			
			# Set new position and rotation
			obj.global_position = current_pos + world_offset
			obj.global_transform.basis = world_rotation
			
			# Zero out velocities
			obj.linear_velocity = Vector3.ZERO
			obj.angular_velocity = Vector3.ZERO
	
	# Update bounding box
	_update_bounding_box()
	_broadcast_selected_transform_updates()

func _update_two_hand_grab() -> void:
	"""Update two-hand manipulation - scale and rotate selection"""
	if not _grab_hand or not _second_grab_hand:
		return
	if not is_instance_valid(_grab_hand) or not is_instance_valid(_second_grab_hand):
		return
	
	# Get current hand positions
	var hand1_pos = _grab_hand.global_position
	var hand2_pos = _second_grab_hand.global_position
	
	# Calculate current distance and direction
	var current_distance = hand1_pos.distance_to(hand2_pos)
	var current_direction = (hand2_pos - hand1_pos).normalized()
	
	# Calculate scale factor from distance change
	var scale_factor = current_distance / _initial_hand_distance if _initial_hand_distance > 0.001 else 1.0
	scale_factor = clamp(scale_factor, 0.1, 10.0)
	
	# Calculate rotation from direction change
	var rotation_axis = _initial_hand_direction.cross(current_direction)
	var rotation_angle = _initial_hand_direction.angle_to(current_direction)
	var rotation = Basis(rotation_axis.normalized(), rotation_angle) if rotation_axis.length() > 0.001 else Basis.IDENTITY
	
	# Calculate new center - this should stay at the midpoint between the two hands
	# to keep both grab points fixed
	var current_center = (hand1_pos + hand2_pos) * 0.5
	
	# Apply transformations to all objects
	for i in range(selected_objects.size()):
		if i < _object_initial_transforms.size() and is_instance_valid(selected_objects[i]):
			var obj = selected_objects[i]
			var initial_transform = _object_initial_transforms[i]
			
			# Apply scale and rotation to offset from initial center
			var scaled_offset = initial_transform.origin * scale_factor
			var rotated_offset = rotation * scaled_offset
			
			# Apply rotation to object's basis (which already includes its current scale)
			var rotated_basis = rotation * initial_transform.basis
			
			# Apply additional scale to the basis
			var final_basis = rotated_basis.scaled(Vector3.ONE * scale_factor)
			
			# Position relative to current center (which moves to keep hands fixed)
			obj.global_position = current_center + rotated_offset
			obj.global_transform.basis = final_basis
			
			# Zero out velocities
			obj.linear_velocity = Vector3.ZERO
			obj.angular_velocity = Vector3.ZERO
	
	# Update bounding box
	_update_bounding_box()
	_broadcast_selected_transform_updates()

func release_box_grab() -> void:
	"""Release the selection box grab"""
	if _is_grabbing_box:
		_broadcast_selected_transform_updates(true)
		print("JoystickSelection: Released selection box")
		_is_grabbing_box = false
		_is_two_hand_grab = false
		_grab_offsets.clear()
		_object_local_transforms.clear()
		_object_initial_transforms.clear()
		_grab_hand = null
		_second_grab_hand = null
		_grab_hand_basis = Basis.IDENTITY

func release_second_hand() -> void:
	"""Release the second hand from two-hand grab, return to single-hand mode"""
	if _is_two_hand_grab:
		_broadcast_selected_transform_updates(true)
		print("JoystickSelection: Released second hand, returning to single-hand mode")
		_is_two_hand_grab = false
		_second_grab_hand = null
		_object_initial_transforms.clear()
		
		# Reinitialize single-hand grab state
		if _grab_hand and is_instance_valid(_grab_hand):
			var grab_point = _grab_hand.global_position
			_grab_hand_basis = _grab_hand.global_transform.basis
			
			_object_local_transforms.clear()
			for obj in selected_objects:
				if is_instance_valid(obj):
					var offset = obj.global_position - grab_point
					var local_offset = _grab_hand_basis.inverse() * offset
					var local_rotation = _grab_hand_basis.inverse() * obj.global_transform.basis
					_object_local_transforms.append(Transform3D(local_rotation, local_offset))

func is_grabbing_box() -> bool:
	"""Check if currently grabbing the selection box"""
	return _is_grabbing_box


func _setup_selection_handles() -> void:
	"""Create transform handles with translation, scale, and rotation controls"""
	_selection_handles.clear()
	var defs = [
		# Translate handles (6 directions) - these are in LOCAL space relative to OBB
		{"axis": Vector3.RIGHT, "color": handle_color_x, "name": "HandleXPos"},
		{"axis": Vector3.LEFT, "color": handle_color_x, "name": "HandleXNeg"},
		{"axis": Vector3.UP, "color": handle_color_y, "name": "HandleYPos"},
		{"axis": Vector3.DOWN, "color": handle_color_y, "name": "HandleYNeg"},
		{"axis": Vector3.BACK, "color": handle_color_z, "name": "HandleZPos"},
		{"axis": Vector3.FORWARD, "color": handle_color_z, "name": "HandleZNeg"},
	]
	
	for def in defs:
		var axis_vec: Vector3 = (def["axis"] as Vector3).normalized()
		var handle := Area3D.new()
		handle.name = def["name"]
		handle.collision_layer = 1  # Layer 1 so joystick can detect it
		handle.collision_mask = 0
		handle.monitoring = false
		handle.monitorable = true
		handle.set_meta("selection_axis_local", axis_vec)
		handle.set_meta("handle_color", def["color"])
		
		# Create the base arrow (for translation when expanded)
		var arrow_mesh := MeshInstance3D.new()
		arrow_mesh.name = "Arrow"
		arrow_mesh.mesh = _build_handle_mesh()
		arrow_mesh.material_override = _build_handle_material(def["color"])
		handle.add_child(arrow_mesh)
		
		# Add axis label on the arrow base
		var label := Label3D.new()
		label.name = "AxisLabel"
		label.text = _get_axis_label(def["name"])
		label.font_size = 32
		label.pixel_size = 0.001
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = def["color"]
		label.outline_size = 8
		label.outline_modulate = Color.BLACK
		# Position at the middle of the shaft (shaft is 60% of handle_length)
		var shaft_len = handle_length * 0.6
		label.position = Vector3(0, 0, shaft_len * 0.5)
		arrow_mesh.add_child(label)
		
		# Create scale cube (hidden by default)
		var scale_cube := MeshInstance3D.new()
		scale_cube.name = "ScaleCube"
		var cube_mesh := BoxMesh.new()
		cube_mesh.size = Vector3(0.04, 0.04, 0.04)
		scale_cube.mesh = cube_mesh
		scale_cube.material_override = _build_handle_material(def["color"])
		scale_cube.visible = false
		handle.add_child(scale_cube)
		
		# Create scale cube collision
		var scale_area := Area3D.new()
		scale_area.name = "ScaleArea"
		scale_area.collision_layer = 1
		scale_area.collision_mask = 0
		scale_area.monitorable = true
		scale_area.monitoring = false
		var scale_collision := CollisionShape3D.new()
		var scale_box := BoxShape3D.new()
		scale_box.size = Vector3(0.06, 0.06, 0.06)
		scale_collision.shape = scale_box
		scale_area.add_child(scale_collision)
		scale_area.visible = false
		scale_area.set_meta("handle_mode", "scale")
		scale_area.set_meta("parent_handle", handle)
		handle.add_child(scale_area)
		
		# Create rotation line and anchor (hidden by default)
		var rotation_line := MeshInstance3D.new()
		rotation_line.name = "RotationLine"
		rotation_line.mesh = _build_line_mesh(0.1)  # 0.1m line
		rotation_line.material_override = _build_handle_material(def["color"])
		rotation_line.visible = false
		handle.add_child(rotation_line)
		
		var rotation_anchor := MeshInstance3D.new()
		rotation_anchor.name = "RotationAnchor"
		var sphere_mesh := SphereMesh.new()
		sphere_mesh.radius = 0.02
		sphere_mesh.height = 0.04
		rotation_anchor.mesh = sphere_mesh
		rotation_anchor.material_override = _build_handle_material(def["color"])
		rotation_anchor.visible = false
		handle.add_child(rotation_anchor)
		
		# Create rotation anchor collision
		var rotate_area := Area3D.new()
		rotate_area.name = "RotateArea"
		rotate_area.collision_layer = 1
		rotate_area.collision_mask = 0
		rotate_area.monitorable = true
		rotate_area.monitoring = false
		var rotate_collision := CollisionShape3D.new()
		var rotate_sphere := SphereShape3D.new()
		rotate_sphere.radius = 0.03
		rotate_collision.shape = rotate_sphere
		rotate_area.add_child(rotate_collision)
		rotate_area.visible = false
		rotate_area.set_meta("handle_mode", "rotate")
		rotate_area.set_meta("parent_handle", handle)
		handle.add_child(rotate_area)
		
		# Base arrow collision (for translation)
		var collider := CollisionShape3D.new()
		collider.name = "Collision"
		collider.shape = _build_handle_collision_shape()
		collider.position = Vector3(0, 0, handle_length * 0.5)
		handle.add_child(collider)
		
		handle.visible = false
		handle.set_meta("handle_mode", "translate")  # Default mode
		_selection_handles.append(handle)
		
		# Add to scene root
		var scene_root = get_tree().current_scene
		if scene_root:
			scene_root.add_child(handle)
			print("JoystickSelection: Created multi-mode handle ", handle.name)

func _build_handle_mesh() -> Mesh:
	"""Build arrow-shaped handle mesh with proper caps"""
	var mesh: ArrayMesh = ArrayMesh.new()
	var st: SurfaceTool = SurfaceTool.new()
	var sides: int = 12
	var radius: float = max(handle_thickness, 0.005)
	var shaft_len: float = max(handle_length * 0.6, 0.02)
	var head_len: float = max(handle_length * 0.4, 0.015)
	var tip_z: float = shaft_len + head_len
	var head_radius: float = radius * 1.6
	
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Bottom cap (flat circle at z=0) - facing down
	var center_bottom := Vector3(0, 0, 0)
	for i in range(sides):
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float((i + 1) % sides) / float(sides)
		var p0 := Vector3(cos(a0) * radius, sin(a0) * radius, 0.0)
		var p1 := Vector3(cos(a1) * radius, sin(a1) * radius, 0.0)
		# Reverse winding for bottom face
		st.add_vertex(center_bottom); st.add_vertex(p1); st.add_vertex(p0)
	
	# Shaft cylinder
	for i in range(sides):
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float((i + 1) % sides) / float(sides)
		var p0 := Vector3(cos(a0) * radius, sin(a0) * radius, 0.0)
		var p1 := Vector3(cos(a1) * radius, sin(a1) * radius, 0.0)
		var p0_top := Vector3(p0.x, p0.y, shaft_len)
		var p1_top := Vector3(p1.x, p1.y, shaft_len)
		# Two triangles per quad
		st.add_vertex(p0); st.add_vertex(p1_top); st.add_vertex(p0_top)
		st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(p1_top)
	
	# Cone head
	var tip := Vector3(0, 0, tip_z)
	for i in range(sides):
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float((i + 1) % sides) / float(sides)
		var b0 := Vector3(cos(a0) * head_radius, sin(a0) * head_radius, shaft_len)
		var b1 := Vector3(cos(a1) * head_radius, sin(a1) * head_radius, shaft_len)
		st.add_vertex(tip); st.add_vertex(b1); st.add_vertex(b0)
	
	# Cone base cap (flat circle at shaft_len) - facing down
	var center_cone := Vector3(0, 0, shaft_len)
	for i in range(sides):
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float((i + 1) % sides) / float(sides)
		var b0 := Vector3(cos(a0) * head_radius, sin(a0) * head_radius, shaft_len)
		var b1 := Vector3(cos(a1) * head_radius, sin(a1) * head_radius, shaft_len)
		# Reverse winding for bottom face
		st.add_vertex(center_cone); st.add_vertex(b1); st.add_vertex(b0)
	
	st.generate_normals()
	st.commit(mesh)
	
	return mesh

func _build_handle_collision_shape() -> BoxShape3D:
	var box := BoxShape3D.new()
	# Make collision larger for easier grabbing
	var half: float = max(handle_thickness * 3.0, 0.02)  # Increased from 1.5 to 3.0
	box.size = Vector3(half * 2, half * 2, max(handle_length * 1.2, 0.06))  # Increased length too
	return box

func _build_line_mesh(length: float) -> Mesh:
	"""Build a simple line mesh for rotation handle - extends from 0 to +Z"""
	var st: SurfaceTool = SurfaceTool.new()
	var mesh: ArrayMesh = ArrayMesh.new()
	var radius: float = 0.003  # Thin line
	var sides: int = 6
	
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(sides):
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float((i + 1) % sides) / float(sides)
		var p0 := Vector3(cos(a0) * radius, sin(a0) * radius, 0.0)
		var p1 := Vector3(cos(a1) * radius, sin(a1) * radius, 0.0)
		var p0_top := Vector3(p0.x, p0.y, length)
		var p1_top := Vector3(p1.x, p1.y, length)
		# Build cylinder from 0 to length along Z axis
		st.add_vertex(p0); st.add_vertex(p1_top); st.add_vertex(p0_top)
		st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(p1_top)
	st.generate_normals()
	st.commit(mesh)
	
	return mesh

func _get_axis_label(handle_name: String) -> String:
	"""Get the axis label text for a handle"""
	match handle_name:
		"HandleXPos":
			return "+X"
		"HandleXNeg":
			return "-X"
		"HandleYPos":
			return "+Y"
		"HandleYNeg":
			return "-Y"
		"HandleZPos":
			return "+Z"
		"HandleZNeg":
			return "-Z"
		_:
			return "?"

func _build_handle_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.render_priority = 2
	return mat

func _position_handles(center: Vector3, half_size: Vector3) -> void:
	"""Position handles at the edges of the oriented bounding box"""
	if _selection_handles.is_empty():
		return
	
	var has_selection := half_size != Vector3.ZERO
	var abs_half := Vector3(abs(half_size.x), abs(half_size.y), abs(half_size.z))
	
	for handle in _selection_handles:
		if not is_instance_valid(handle):
			continue
		
		handle.visible = has_selection
		handle.monitorable = has_selection
		
		if not has_selection:
			continue
		
		# Get the LOCAL axis (relative to OBB)
		var local_axis: Vector3 = handle.get_meta("selection_axis_local", Vector3.ZERO)
		
		# Calculate position in local space
		var local_axis_len: float = abs(local_axis.x) * abs_half.x + abs(local_axis.y) * abs_half.y + abs(local_axis.z) * abs_half.z
		var extra: float = handle_offset + handle_length * 0.6
		var local_pos := local_axis.normalized() * (local_axis_len + extra)
		
		# Transform to world space using the bounding box rotation
		var world_pos := center + _last_rotation * local_pos
		var world_axis := (_last_rotation * local_axis).normalized()
		
		# Store the world axis for dragging
		handle.set_meta("selection_axis", world_axis)
		
		# Orient handle to point along the world axis
		var up := Vector3.UP if abs(world_axis.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
		var h_basis := Basis.looking_at(-world_axis, up)
		handle.global_transform = Transform3D(h_basis, world_pos)
		
		# Position child elements (scale cube, rotation line/anchor)
		_position_handle_children(handle, world_axis)

func _position_handle_children(handle: Area3D, world_axis: Vector3) -> void:
	"""Position the scale cube, rotation line, and rotation anchor for a handle"""
	# Scale cube is at the base (where arrow starts)
	var scale_cube = handle.get_node_or_null("ScaleCube")
	var scale_area = handle.get_node_or_null("ScaleArea")
	if scale_cube and scale_area:
		scale_cube.position = Vector3.ZERO
		scale_area.position = Vector3.ZERO
	
	# Arrow moves further out when expanded
	var arrow = handle.get_node_or_null("Arrow")
	if arrow:
		arrow.position = Vector3.ZERO  # Default position
	
	# Rotation line and anchor are positioned ORTHOGONAL to the arrow
	var rotation_line = handle.get_node_or_null("RotationLine")
	var rotation_anchor = handle.get_node_or_null("RotationAnchor")
	var rotate_area = handle.get_node_or_null("RotateArea")
	if rotation_line and rotation_anchor and rotate_area:
		# Position sphere orthogonal to arrow (along local X axis)
		var line_length = 0.1
		var orthogonal_offset = Vector3(line_length, 0, 0)  # Perpendicular in local space
		
		rotation_anchor.position = orthogonal_offset
		rotate_area.position = orthogonal_offset
		
		# Position and orient the line to connect from origin to sphere
		# The line mesh extends from 0 to +Z (length 0.1)
		# We need to rotate it to point at the sphere position
		var line_direction = orthogonal_offset.normalized()
		var line_distance = orthogonal_offset.length()
		
		# Create basis that points Z axis toward the sphere
		var z_axis = line_direction
		var x_axis = Vector3.UP.cross(z_axis)
		if x_axis.length() < 0.001:
			x_axis = Vector3.FORWARD.cross(z_axis)
		x_axis = x_axis.normalized()
		var y_axis = z_axis.cross(x_axis).normalized()
		var line_basis = Basis(x_axis, y_axis, z_axis)
		
		# Apply the transform
		rotation_line.transform = Transform3D(line_basis, Vector3.ZERO)
		# Scale along Z to reach the sphere
		rotation_line.scale = Vector3(1, 1, line_distance / 0.1)

func _hide_handles() -> void:
	"""Hide all transform handles"""
	for handle in _selection_handles:
		if is_instance_valid(handle):
			handle.visible = false
			handle.monitorable = false  # Disable collision when hidden
			_collapse_handle(handle)  # Ensure collapsed state


func start_handle_drag(handle: Area3D, start_pos: Vector3) -> void:
	"""Start dragging a transform handle - mode depends on which part was grabbed"""
	_claim_network_ownership_for_selection()
	_active_handle = handle
	_drag_start_pos = start_pos
	_drag_axis = handle.get_meta("selection_axis", Vector3.ZERO).normalized()
	_active_handle_mode = handle.get_meta("active_mode", "translate")
	
	# Store initial scale and positions for scale mode
	if _active_handle_mode == "scale" and not selected_objects.is_empty():
		var first_obj = selected_objects[0]
		if is_instance_valid(first_obj):
			_drag_initial_scale = first_obj.scale
		
		# Store initial positions for all objects
		_drag_initial_positions.clear()
		for obj in selected_objects:
			if is_instance_valid(obj):
				_drag_initial_positions.append(obj.global_position)
		
		# Calculate the anchor point - the opposite edge of the bounding box
		# This edge should stay fixed during scaling
		var local_axis = handle.get_meta("selection_axis_local", Vector3.ZERO)
		# Transform to world space
		var world_axis_dir = _last_rotation * local_axis
		# The anchor is on the opposite side of the bounding box
		_drag_scale_anchor = _last_center - (world_axis_dir.normalized() * _last_half_size.length())
		
		print("JoystickSelection: Scale anchor at ", _drag_scale_anchor, " (opposite from handle)")
	
	# Store initial rotation and perpendicular vector for rotate mode
	if _active_handle_mode == "rotate" and not selected_objects.is_empty():
		var center = get_selection_center()
		
		# Store initial positions and rotations for ALL objects
		_drag_initial_positions.clear()
		_drag_initial_rotations.clear()
		for obj in selected_objects:
			if is_instance_valid(obj):
				_drag_initial_positions.append(obj.global_position)
				_drag_initial_rotations.append(obj.global_transform.basis)
		
		# Calculate the perpendicular vector from center to grab point
		var to_grab = start_pos - center
		_drag_perpendicular_start = (to_grab - to_grab.dot(_drag_axis) * _drag_axis).normalized()
	
	print("JoystickSelection: Started ", _active_handle_mode, " on handle along axis ", _drag_axis)

func update_handle_drag(current_pos: Vector3) -> void:
	"""Update handle drag - behavior depends on mode"""
	if not _active_handle or selected_objects.is_empty():
		return
	
	match _active_handle_mode:
		"translate":
			_update_translate_drag(current_pos)
		"scale":
			_update_scale_drag(current_pos)
		"rotate":
			_update_rotate_drag(current_pos)
	_broadcast_selected_transform_updates()


func _broadcast_selected_transform_updates(force_scale_sync: bool = false) -> void:
	var network_manager := _get_network_manager()
	if network_manager == null:
		return
	if not network_manager.has_method("update_grabbed_object"):
		return
	_claim_network_ownership_for_selection()
	for obj in selected_objects:
		if not is_instance_valid(obj) or not (obj is RigidBody3D):
			continue
		var object_id := _resolve_network_object_id(obj)
		if object_id.is_empty():
			continue
		var rot: Quaternion = obj.global_transform.basis.get_rotation_quaternion()
		network_manager.update_grabbed_object(object_id, obj.global_position, rot)
		_maybe_broadcast_object_scale(network_manager, object_id, obj.scale, force_scale_sync)


func _claim_network_ownership_for_selection() -> void:
	for obj in selected_objects:
		if is_instance_valid(obj):
			_claim_network_ownership_for_object(obj)


func _claim_network_ownership_for_object(obj: RigidBody3D) -> void:
	var network_manager := _get_network_manager()
	if network_manager == null:
		return
	var object_id := _resolve_network_object_id(obj)
	if object_id.is_empty():
		return
	if _is_locally_authoritative_for_object(network_manager, object_id):
		_owned_selected_object_ids[object_id] = true
		return
	var now_msec := Time.get_ticks_msec()
	var last_request_msec := int(_ownership_request_msec.get(object_id, 0))
	if _owned_selected_object_ids.has(object_id) and (now_msec - last_request_msec) < OWNERSHIP_REQUEST_RETRY_MS:
		return
	if network_manager.has_method("grab_object"):
		network_manager.grab_object(object_id, "joystick_selection")
	elif network_manager.has_method("request_object_ownership"):
		network_manager.request_object_ownership(object_id, "joystick_selection")
	else:
		return
	_owned_selected_object_ids[object_id] = true
	_ownership_request_msec[object_id] = now_msec


func _release_network_ownership_for_object(obj: RigidBody3D) -> void:
	var object_id := _resolve_network_object_id(obj)
	if object_id.is_empty():
		return
	_owned_selected_object_ids.erase(object_id)
	_ownership_request_msec.erase(object_id)
	_last_scale_sync_msec.erase(object_id)
	_last_synced_scale.erase(object_id)

	var network_manager := _get_network_manager()
	if network_manager == null:
		return
	if not network_manager.has_method("release_object"):
		return
	if not is_instance_valid(obj):
		return
	if not _is_locally_authoritative_for_object(network_manager, object_id):
		return

	var persist_mode := _resolve_object_persist_mode(network_manager, object_id)
	var rot: Quaternion = obj.global_transform.basis.get_rotation_quaternion()
	network_manager.release_object(
		object_id,
		obj.global_position,
		rot,
		Vector3.ZERO,
		Vector3.ZERO,
		persist_mode,
		"RELEASED_STATIC"
	)


func _release_all_owned_selection_objects() -> void:
	if _owned_selected_object_ids.is_empty():
		return
	var network_manager := _get_network_manager()
	var owned_ids: Array = _owned_selected_object_ids.keys()
	for object_id_variant in owned_ids:
		var object_id := String(object_id_variant)
		if object_id.is_empty():
			continue
		var obj := _find_selected_object_by_id(object_id)
		if not is_instance_valid(obj):
			continue
		if network_manager and network_manager.has_method("release_object"):
			if not _is_locally_authoritative_for_object(network_manager, object_id):
				continue
			var persist_mode := _resolve_object_persist_mode(network_manager, object_id)
			var rot: Quaternion = obj.global_transform.basis.get_rotation_quaternion()
			network_manager.release_object(
				object_id,
				obj.global_position,
				rot,
				Vector3.ZERO,
				Vector3.ZERO,
				persist_mode,
				"RELEASED_STATIC"
			)
	_owned_selected_object_ids.clear()
	_ownership_request_msec.clear()
	_last_scale_sync_msec.clear()
	_last_synced_scale.clear()


func _find_selected_object_by_id(object_id: String) -> RigidBody3D:
	for obj in selected_objects:
		if not is_instance_valid(obj):
			continue
		if _resolve_network_object_id(obj) == object_id:
			return obj
	return null


func _resolve_object_persist_mode(network_manager: Node, object_id: String) -> String:
	var persist_mode := "placed_room"
	if network_manager == null:
		return persist_mode
	var registry_variant: Variant = network_manager.get("room_object_registry")
	if registry_variant is Dictionary:
		var registry := registry_variant as Dictionary
		var object_state_variant: Variant = registry.get(object_id, null)
		if object_state_variant is Dictionary:
			var object_state := object_state_variant as Dictionary
			var state_mode := String(object_state.get("persist_mode", ""))
			if not state_mode.is_empty():
				persist_mode = state_mode
	return persist_mode


func _is_locally_authoritative_for_object(network_manager: Node, object_id: String) -> bool:
	if network_manager == null or object_id.is_empty():
		return false
	if not network_manager.has_method("get_nakama_user_id"):
		return false

	var my_id := String(network_manager.get_nakama_user_id())
	if my_id.is_empty():
		return false

	if network_manager.has_method("get_object_owner"):
		var owner_id := String(network_manager.get_object_owner(object_id))
		if not owner_id.is_empty() and owner_id == my_id:
			return true

	var registry_variant: Variant = network_manager.get("room_object_registry")
	if registry_variant is Dictionary:
		var registry := registry_variant as Dictionary
		var state_variant: Variant = registry.get(object_id, null)
		if state_variant is Dictionary:
			var state := state_variant as Dictionary
			var held_by := String(state.get("held_by", ""))
			if held_by == my_id:
				return true
	return false


func _maybe_broadcast_object_scale(network_manager: Node, object_id: String, object_scale: Vector3, force_sync: bool = false) -> void:
	if network_manager == null:
		return
	if not network_manager.has_method("replicate_object_property"):
		return

	var should_send: bool = force_sync or not _last_synced_scale.has(object_id)
	if not should_send:
		var previous_scale: Vector3 = _last_synced_scale[object_id]
		should_send = previous_scale.distance_to(object_scale) > SCALE_SYNC_EPSILON
	if not should_send:
		return

	var now_msec := Time.get_ticks_msec()
	var last_sent_msec := int(_last_scale_sync_msec.get(object_id, 0))
	if not force_sync and now_msec - last_sent_msec < SCALE_SYNC_INTERVAL_MS:
		return

	network_manager.replicate_object_property(object_id, "scale", object_scale, false)
	_last_scale_sync_msec[object_id] = now_msec
	_last_synced_scale[object_id] = object_scale


func _resolve_network_object_id(obj: RigidBody3D) -> String:
	if obj.has_method("get"):
		var raw_save_id: Variant = obj.get("save_id")
		var save_id: String = String(raw_save_id) if raw_save_id != null else ""
		if not save_id.is_empty():
			return save_id
	if obj.name.begins_with("obj_"):
		return obj.name
	return ""

func _update_translate_drag(current_pos: Vector3) -> void:
	"""Move selected objects along the drag axis"""
	var delta = current_pos - _drag_start_pos
	var movement = delta.dot(_drag_axis) * _drag_axis
	
	for obj in selected_objects:
		if is_instance_valid(obj) and obj is RigidBody3D:
			obj.global_position += movement
			obj.linear_velocity = Vector3.ZERO
			obj.angular_velocity = Vector3.ZERO
	
	_drag_start_pos = current_pos
	_update_bounding_box()

func _update_scale_drag(current_pos: Vector3) -> void:
	"""Scale selection as a group from the bounding box edge - opposite edge stays fixed"""
	var delta = current_pos - _drag_start_pos
	var scale_delta = delta.dot(_drag_axis)
	
	# Calculate scale factor (0.01 units = 10% scale change)
	var scale_factor = 1.0 + (scale_delta * 10.0)
	scale_factor = clamp(scale_factor, 0.1, 10.0)
	
	# Scale all objects as a group relative to the anchor point
	for i in range(selected_objects.size()):
		if i >= _drag_initial_positions.size():
			break
		
		var obj = selected_objects[i]
		if not is_instance_valid(obj) or not (obj is RigidBody3D):
			continue
		
		# Get the local axis direction for this object
		var local_axis = obj.global_transform.basis.inverse() * _drag_axis
		
		# Determine which local axis is most aligned
		var abs_x = abs(local_axis.x)
		var abs_y = abs(local_axis.y)
		var abs_z = abs(local_axis.z)
		
		var axis_scale = Vector3.ONE
		
		if abs_x > abs_y and abs_x > abs_z:
			axis_scale.x = scale_factor
		elif abs_y > abs_x and abs_y > abs_z:
			axis_scale.y = scale_factor
		else:
			axis_scale.z = scale_factor
		
		# Apply scale
		obj.scale = _drag_initial_scale * axis_scale
		
		# Position the object relative to the anchor point
		# Objects move away from the anchor as they scale
		var initial_pos = _drag_initial_positions[i]
		var offset_from_anchor = initial_pos - _drag_scale_anchor
		
		# Only scale the offset along the drag axis
		var offset_along_axis = offset_from_anchor.dot(_drag_axis)
		var scaled_offset_along_axis = offset_along_axis * scale_factor
		var movement_along_axis = (scaled_offset_along_axis - offset_along_axis) * _drag_axis
		
		obj.global_position = initial_pos + movement_along_axis
		
		obj.linear_velocity = Vector3.ZERO
		obj.angular_velocity = Vector3.ZERO
	
	_update_bounding_box()

func _update_rotate_drag(current_pos: Vector3) -> void:
	"""Rotate all selected objects as one rigid unit around the drag axis"""
	var center = get_selection_center()
	
	# Calculate the current perpendicular vector from center to current position
	var to_current = current_pos - center
	var drag_perpendicular_current = (to_current - to_current.dot(_drag_axis) * _drag_axis).normalized()
	
	# Calculate rotation angle between start and current perpendicular vectors
	var rotation_angle = _drag_perpendicular_start.angle_to(drag_perpendicular_current)
	
	# Determine rotation direction using cross product
	var cross = _drag_perpendicular_start.cross(drag_perpendicular_current)
	if cross.dot(_drag_axis) < 0:
		rotation_angle = -rotation_angle
	
	# Create rotation basis around the drag axis
	var rotation = Basis(_drag_axis, rotation_angle)
	
	# Rotate all objects as a rigid unit
	for i in range(selected_objects.size()):
		if i >= _drag_initial_positions.size() or i >= _drag_initial_rotations.size():
			break
			
		var obj = selected_objects[i]
		if not is_instance_valid(obj) or not (obj is RigidBody3D):
			continue
		
		# Rotate position around center from initial position
		var initial_offset = _drag_initial_positions[i] - center
		var rotated_offset = rotation * initial_offset
		obj.global_position = center + rotated_offset
		
		# Rotate the object's orientation as well (all objects rotate together)
		obj.global_transform.basis = rotation * _drag_initial_rotations[i]
		
		obj.linear_velocity = Vector3.ZERO
		obj.angular_velocity = Vector3.ZERO
	
	# Update bounding box first
	_update_bounding_box()
	
	# Then update the rotation handle visual to follow the rotation
	# This must be called AFTER bounding box update to avoid being overwritten
	if _active_handle and is_instance_valid(_active_handle):
		call_deferred("_update_rotation_handle_visual", _active_handle, rotation_angle)

func _update_rotation_handle_visual(handle: Area3D, rotation_angle: float) -> void:
	"""Update the rotation line and sphere to show the current rotation"""
	var rotation_line = handle.get_node_or_null("RotationLine")
	var rotation_anchor = handle.get_node_or_null("RotationAnchor")
	var rotate_area = handle.get_node_or_null("RotateArea")
	
	if not rotation_line or not rotation_anchor or not rotate_area:
		return
	
	# Calculate the perpendicular offset rotated by the current angle
	var line_length = 0.1
	
	# Start with the initial perpendicular direction (local X axis)
	var initial_perp = Vector3(1, 0, 0)
	
	# Rotate it around the local Z axis (which points along the arrow)
	var rotation_basis = Basis(Vector3(0, 0, 1), rotation_angle)
	var rotated_perp = rotation_basis * initial_perp
	
	# Position the anchor at the rotated perpendicular offset
	var anchor_pos = rotated_perp * line_length
	rotation_anchor.position = anchor_pos
	rotate_area.position = anchor_pos
	
	# Make the line point from origin to the anchor
	var line_direction = anchor_pos.normalized()
	var line_distance = anchor_pos.length()
	
	# Create basis that points Z axis toward the sphere
	var z_axis = line_direction
	var x_axis = Vector3.UP.cross(z_axis)
	if x_axis.length() < 0.001:
		x_axis = Vector3.FORWARD.cross(z_axis)
	x_axis = x_axis.normalized()
	var y_axis = z_axis.cross(x_axis).normalized()
	var line_basis = Basis(x_axis, y_axis, z_axis)
	
	# Apply transform and scale
	rotation_line.transform = Transform3D(line_basis, Vector3.ZERO)
	rotation_line.scale = Vector3(1, 1, line_distance / 0.1)  # Scale to reach the sphere

func end_handle_drag() -> void:
	"""End handle dragging"""
	_broadcast_selected_transform_updates(true)
	print("JoystickSelection: Ended ", _active_handle_mode, " drag")
	_active_handle = null
	_active_handle_mode = ""
	_drag_axis = Vector3.ZERO

func is_dragging_handle() -> bool:
	"""Check if currently dragging a handle"""
	return _active_handle != null


func set_handle_highlight(handle: Area3D, highlighted: bool) -> void:
	"""Highlight or unhighlight a handle - expands to show all controls when highlighted"""
	if not is_instance_valid(handle):
		return
	
	if highlighted:
		_expand_handle(handle)
	else:
		_collapse_handle(handle)

func _expand_handle(handle: Area3D) -> void:
	"""Expand handle to show scale cube, moved arrow, and rotation anchor"""
	# Show scale cube
	var scale_cube = handle.get_node_or_null("ScaleCube")
	var scale_area = handle.get_node_or_null("ScaleArea")
	if scale_cube and scale_area:
		scale_cube.visible = true
		scale_area.visible = true
		scale_area.monitorable = true
	
	# Move arrow further out (0.15m beyond cube)
	var arrow = handle.get_node_or_null("Arrow")
	if arrow:
		arrow.position = Vector3(0, 0, 0.15)
	
	# Show rotation line and anchor
	var rotation_line = handle.get_node_or_null("RotationLine")
	var rotation_anchor = handle.get_node_or_null("RotationAnchor")
	var rotate_area = handle.get_node_or_null("RotateArea")
	if rotation_line and rotation_anchor and rotate_area:
		rotation_line.visible = true
		rotation_anchor.visible = true
		rotate_area.visible = true
		rotate_area.monitorable = true
	
	# Brighten all materials
	var color = handle.get_meta("handle_color", Color.WHITE)
	for child in handle.get_children():
		if child is MeshInstance3D:
			var mat = child.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color.a = 1.0
				mat.emission_enabled = true
				mat.emission = color * 1.5
				mat.emission_energy_multiplier = 2.0

func _collapse_handle(handle: Area3D) -> void:
	"""Collapse handle to show only the base arrow"""
	# Hide scale cube
	var scale_cube = handle.get_node_or_null("ScaleCube")
	var scale_area = handle.get_node_or_null("ScaleArea")
	if scale_cube and scale_area:
		scale_cube.visible = false
		scale_area.visible = false
		scale_area.monitorable = false
	
	# Reset arrow position
	var arrow = handle.get_node_or_null("Arrow")
	if arrow:
		arrow.position = Vector3.ZERO
	
	# Hide rotation line and anchor
	var rotation_line = handle.get_node_or_null("RotationLine")
	var rotation_anchor = handle.get_node_or_null("RotationAnchor")
	var rotate_area = handle.get_node_or_null("RotateArea")
	if rotation_line and rotation_anchor and rotate_area:
		rotation_line.visible = false
		rotation_anchor.visible = false
		rotate_area.visible = false
		rotate_area.monitorable = false
	
	# Reset materials
	for child in handle.get_children():
		if child is MeshInstance3D:
			var mat = child.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color.a = 0.85
				mat.emission_enabled = false
				mat.emission_energy_multiplier = 1.0
