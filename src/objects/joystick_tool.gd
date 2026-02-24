extends Grabbable

# Joystick Tool - 3D Object Logic
# Integrates the selection UI with the grabbable physics object

@onready var ui_viewport: SubViewport = $SubViewport
@onready var tool_ui = $SubViewport/JoystickToolUI
@onready var tip_sphere: MeshInstance3D = %TipSphere
@onready var selection_area: Area3D = null

var anchor_y: float = 0.0
var selection_manager: JoystickSelectionManager = null
var is_trigger_held: bool = false
var can_grab_selection: bool = false
var _hovered_handle: Area3D = null
var _hovered_handle_distance: float = 0.0  # Distance to hovered handle
var _hover_sticky_threshold: float = 0.2  # Stay highlighted within 20cm

# Shared selection manager across all joystick tools
static var _shared_selection_manager: JoystickSelectionManager = null
const TIP_BASE_RADIUS_DEFAULT := 0.03
const SELECTION_BASE_RADIUS := 0.05
var _tip_base_radius: float = TIP_BASE_RADIUS_DEFAULT
var _tip_clone_meshes: Array[MeshInstance3D] = []
var _tip_clone_base_hand_multiplier: float = 1.0

func _ready() -> void:
	super._ready()
	
	# Use shared selection manager so both joystick tools can interact with same selection
	if not _shared_selection_manager:
		_shared_selection_manager = JoystickSelectionManager.new()
		# Add to scene root so it persists
		var scene_root = get_tree().current_scene
		if scene_root:
			scene_root.add_child(_shared_selection_manager)
			print("JoystickTool: Created shared selection manager")
	
	selection_manager = _shared_selection_manager
	
	# Create selection area
	call_deferred("_create_selection_area")
	
	# Connect to grab signals to track which hand is using the tool
	grabbed.connect(_on_grabbed)
	released.connect(_on_released)
	
	if tool_ui:
		tool_ui.tip_scale_changed.connect(_on_tip_scale_changed)
	
	if tip_sphere and tip_sphere.mesh is SphereMesh:
		_tip_base_radius = (tip_sphere.mesh as SphereMesh).radius
	
	# Calculate anchor (cone tip) based on initial editor placement
	if tip_sphere:
		anchor_y = tip_sphere.position.y - _tip_base_radius * tip_sphere.scale.y

func _physics_process(_delta: float) -> void:
	# Update selection area to match tip sphere
	_update_selection_area()
	# Check for overlaps when trigger is held
	if is_trigger_held:
		_check_selection_overlaps()
	# Always check for handle hover (even when trigger not held)
	_update_handle_hover()

func _create_selection_area() -> void:
	"""Create an Area3D for detecting selectable shapes and handles"""
	selection_area = Area3D.new()
	selection_area.name = "SelectionArea"
	selection_area.collision_layer = 0
	selection_area.collision_mask = 128 | 1  # Layer 8 (shapes) + Layer 1 (handles)
	selection_area.monitoring = true
	selection_area.monitorable = false
	
	var collision_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = SELECTION_BASE_RADIUS
	collision_shape.shape = sphere_shape
	
	selection_area.add_child(collision_shape)
	add_child(selection_area)
	
	# Add visual debug sphere to see where the selection area is
	var debug_mesh = MeshInstance3D.new()
	debug_mesh.name = "DebugVisual"
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = _tip_base_radius
	sphere_mesh.height = _tip_base_radius * 2.0
	debug_mesh.mesh = sphere_mesh
	
	var debug_mat = StandardMaterial3D.new()
	debug_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debug_mat.albedo_color = Color(1.0, 0.0, 1.0, 0.3)  # Magenta semi-transparent
	debug_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debug_mat.no_depth_test = true
	debug_mesh.material_override = debug_mat
	
	selection_area.add_child(debug_mesh)
	
	print("JoystickTool: Selection area created with collision radius ", snapped(SELECTION_BASE_RADIUS, 0.001), "m")

func _on_tip_scale_changed(_new_scale: float) -> void:
	_update_tip_sphere()

func _process(_delta: float) -> void:
	_update_tip_sphere()
	_check_controller_input()


func _get_grabbing_hand_scale_multiplier() -> float:
	if not (is_grabbed and is_instance_valid(grabbing_hand)):
		return 1.0
	
	if grabbing_hand.has_method("get_scale_debug_state"):
		var state_variant = grabbing_hand.call("get_scale_debug_state")
		if state_variant is Dictionary:
			var state := state_variant as Dictionary
			if state.has("multiplier"):
				return maxf(float(state["multiplier"]), 0.0001)
	
	if grabbing_hand.has_method("get"):
		var raw_multiplier = grabbing_hand.get("_current_scale_multiplier")
		if typeof(raw_multiplier) == TYPE_FLOAT:
			return maxf(float(raw_multiplier), 0.0001)
	
	return 1.0


func _get_tip_clone_hand_scale_factor() -> float:
	var current_multiplier: float = maxf(_get_grabbing_hand_scale_multiplier(), 0.0001)
	var base_multiplier: float = maxf(_tip_clone_base_hand_multiplier, 0.0001)
	return current_multiplier / base_multiplier


func _build_tip_clone_transform() -> Transform3D:
	# Build the hand-local tip transform at grab baseline, then apply the
	# same relative hand-scale rule used by PhysicsHand for grabbed nodes.
	var hand_space_base_tf: Transform3D = Transform3D(Basis(grab_rotation_offset).scaled(grab_scale_offset), grab_offset) * tip_sphere.transform
	var hand_scale_factor: float = _get_tip_clone_hand_scale_factor()
	var scaled_tf: Transform3D = hand_space_base_tf
	scaled_tf.origin = hand_space_base_tf.origin * hand_scale_factor
	scaled_tf.basis = hand_space_base_tf.basis.scaled(Vector3.ONE * hand_scale_factor)
	return scaled_tf


func _get_tip_world_radius() -> float:
	for tip_clone in _tip_clone_meshes:
		if is_instance_valid(tip_clone):
			return _tip_base_radius * absf(tip_clone.global_transform.basis.get_scale().x)
	
	if tip_sphere:
		return _tip_base_radius * absf(tip_sphere.global_transform.basis.get_scale().x)
	
	return _tip_base_radius


func _update_selection_area() -> void:
	"""Update the selection area to match tip sphere position and scale"""
	if not selection_area:
		return
	
	var tip_pos: Vector3
	
	# When grabbed, look for the visible cloned tip sphere
	if is_grabbed and is_instance_valid(grabbing_hand):
		var found_tip = false
		
		# Check tracked cloned tip meshes first.
		for tip_clone in _tip_clone_meshes:
			if is_instance_valid(tip_clone) and tip_clone.visible:
				tip_pos = tip_clone.global_position
				found_tip = true
				break
		
		if not found_tip:
			var tip_hand_tf: Transform3D = _build_tip_clone_transform()
			tip_pos = (grabbing_hand.global_transform * tip_hand_tf).origin
	elif tip_sphere:
		# Not grabbed, use tip sphere position directly
		tip_pos = tip_sphere.global_position
	else:
		# Fallback to tool position
		tip_pos = global_position
	
	selection_area.global_position = tip_pos
	
	# Keep selection volume in lock-step with the visible tip radius in world space.
	var tip_world_radius = _get_tip_world_radius()
	var desired_world_scale = tip_world_radius / maxf(_tip_base_radius, 0.0001)
	var parent_world_scale := 1.0
	var parent_node := selection_area.get_parent()
	if parent_node is Node3D:
		parent_world_scale = maxf(absf((parent_node as Node3D).global_transform.basis.get_scale().x), 0.0001)
	var local_scale = desired_world_scale / parent_world_scale
	selection_area.scale = Vector3.ONE * local_scale

func _check_selection_overlaps() -> void:
	"""Check for overlapping bodies when trigger is held"""
	if not is_trigger_held or not selection_area or not selection_manager:
		return
	
	# Get all overlapping bodies
	var overlapping = selection_area.get_overlapping_bodies()
	
	# Add overlapping bodies to selection
	for body in overlapping:
		if body is RigidBody3D and body.is_in_group("selectable_shapes"):
			if body not in selection_manager.selected_objects:
				print("JoystickTool: Adding ", body.name, " to selection")
				selection_manager.add_to_selection(body as RigidBody3D)

func _check_controller_input() -> void:
	if not is_grabbed or not is_instance_valid(grabbing_hand):
		return
	
	var controller = _find_controller_from_hand(grabbing_hand)
	if not controller:
		return
	
	# Check trigger state
	var trigger_value = controller.get_float("trigger")
	var was_held = is_trigger_held
	is_trigger_held = trigger_value > 0.5
	
	# Trigger just pressed - start selection or grab handle
	if is_trigger_held and not was_held:
		if selection_manager:
			# Get tip position - use selection_area position for consistency
			var tip_pos = selection_area.global_position if selection_area else global_position
			
			# Check if we're pointing at a transform handle (use hovered handle)
			if _hovered_handle:
				# Start dragging the handle
				print("JoystickTool: Grabbed handle ", _hovered_handle.name)
				selection_manager.start_handle_drag(_hovered_handle, tip_pos)
				can_grab_selection = false
				return
			
			# Check if clicking inside bounding box
			if selection_manager.selected_objects.size() > 0:
				if selection_manager.is_point_in_bounding_box(tip_pos):
					# Check if this is a second hand grabbing (for two-hand mode)
					if selection_manager.is_grabbing_box() and grabbing_hand != selection_manager._grab_hand:
						# Second hand grabbing - this will trigger two-hand mode
						print("JoystickTool: Second hand grabbing selection - entering two-hand mode")
						selection_manager.grab_selection(grabbing_hand, tip_pos)
					else:
						# First hand grabbing
						print("JoystickTool: Grabbing selection box at ", tip_pos)
						selection_manager.grab_selection(grabbing_hand, tip_pos)
					can_grab_selection = false
					return
			
			# Check if clicking on a shape - add to selection
			var overlapping = selection_area.get_overlapping_bodies() if selection_area else []
			var clicked_shape = false
			for body in overlapping:
				if body is RigidBody3D and body.is_in_group("selectable_shapes"):
					print("JoystickTool: Clicked on shape ", body.name)
					clicked_shape = true
					break
			
			if clicked_shape:
				# Start new selection
				selection_manager.start_selection()
				can_grab_selection = false
			else:
				# Clicked empty space - clear selection
				print("JoystickTool: Clicked empty space - clearing selection")
				selection_manager.clear_selection()
				can_grab_selection = false
	
	# Trigger held - update handle drag or box grab
	elif is_trigger_held and was_held:
		if selection_manager:
			# Use selection_area position for consistency
			var tip_pos = selection_area.global_position if selection_area else global_position
			
			if selection_manager.is_dragging_handle():
				selection_manager.update_handle_drag(tip_pos)
			elif selection_manager.is_grabbing_box():
				# In two-hand mode, the update happens automatically based on both hand positions
				# We just need to call update_box_grab with the current hand's position
				selection_manager.update_box_grab(tip_pos)
	
	# Trigger just released - end selection, handle drag, or box grab
	elif not is_trigger_held and was_held:
		if selection_manager:
			if selection_manager.is_dragging_handle():
				selection_manager.end_handle_drag()
			elif selection_manager.is_grabbing_box():
				# Check if this is the second hand releasing (in two-hand mode)
				if selection_manager._is_two_hand_grab and grabbing_hand == selection_manager._second_grab_hand:
					print("JoystickTool: Second hand released - returning to single-hand mode")
					selection_manager.release_second_hand()
				else:
					# First hand releasing - release entire grab
					selection_manager.release_box_grab()
			else:
				selection_manager.end_selection()
			can_grab_selection = true

func _update_handle_hover() -> void:
	"""Update handle hover highlighting with sticky behavior"""
	if not selection_manager or not selection_area:
		return
	
	# Check if we're hovering over a handle
	var handle = _check_handle_at_position(Vector3.ZERO)  # Position not used anymore
	
	# If we have a previously hovered handle and no new handle detected
	if not handle and _hovered_handle and is_instance_valid(_hovered_handle):
		# Check distance to the hovered handle - keep it highlighted if we're still close
		var tip_pos = selection_area.global_position if selection_area else global_position
		var handle_pos = _hovered_handle.global_position
		var distance = tip_pos.distance_to(handle_pos)
		
		# If we're still within the sticky threshold, keep the handle highlighted
		if distance < _hover_sticky_threshold:
			_hovered_handle_distance = distance
			return  # Keep current hover state
		else:
			# Too far away, unhighlight
			selection_manager.set_handle_highlight(_hovered_handle, false)
			_hovered_handle = null
			_hovered_handle_distance = 0.0
			return
	
	# If hover changed, update highlighting
	if handle != _hovered_handle:
		# Unhighlight old handle
		if _hovered_handle and is_instance_valid(_hovered_handle):
			selection_manager.set_handle_highlight(_hovered_handle, false)
		
		# Highlight new handle
		if handle:
			selection_manager.set_handle_highlight(handle, true)
			var tip_pos = selection_area.global_position if selection_area else global_position
			_hovered_handle_distance = tip_pos.distance_to(handle.global_position)
		else:
			_hovered_handle_distance = 0.0
		
		_hovered_handle = handle
	elif handle:
		# Same handle, update distance
		var tip_pos = selection_area.global_position if selection_area else global_position
		_hovered_handle_distance = tip_pos.distance_to(handle.global_position)

func _check_handle_at_position(_pos: Vector3) -> Area3D:
	"""Check if tip sphere is overlapping any transform handle or its sub-components"""
	if not selection_manager or not selection_area:
		return null
	
	var overlapping_areas = selection_area.get_overlapping_areas()
	
	# First check for sub-components (scale/rotate areas)
	for area in overlapping_areas:
		if area.has_meta("handle_mode") and area.has_meta("parent_handle"):
			var mode = area.get_meta("handle_mode")
			var parent_handle = area.get_meta("parent_handle")
			if is_instance_valid(parent_handle) and parent_handle.visible:
				# Store the mode on the parent handle for later use
				parent_handle.set_meta("active_mode", mode)
				return parent_handle
	
	# Then check for main handles
	for area in overlapping_areas:
		for handle in selection_manager._selection_handles:
			if is_instance_valid(handle) and handle.visible and area == handle:
				# Default to translate mode
				handle.set_meta("active_mode", "translate")
				return handle
	
	return null

func _update_tip_sphere() -> void:
	if not tip_sphere or not tool_ui:
		return
	
	# Visibility: ALWAYS visible as requested
	# ONLY show the original sphere if we are NOT currently grabbed
	tip_sphere.visible = not is_grabbed
	
	# APPLY SCALE
	var current_scale = tool_ui.tip_scale
	tip_sphere.scale = Vector3.ONE * current_scale
	
	# POSITIONING: Attach bottom of sphere to calculated anchor
	var radius = _tip_base_radius * current_scale
	tip_sphere.position = Vector3(0, anchor_y + radius, 0)
	
	# Also update the cloned visuals on the hand if grabbed
	if is_grabbed and is_instance_valid(grabbing_hand):
		var sphere_hand_tf: Transform3D = _build_tip_clone_transform()
		
		for tip_clone in _tip_clone_meshes:
			if is_instance_valid(tip_clone):
				tip_clone.visible = true
				tip_clone.transform = sphere_hand_tf

func _on_grabbed(hand: RigidBody3D) -> void:
	if not hand:
		# Could be a desktop grab
		return

	_tip_clone_meshes.clear()
	_tip_clone_base_hand_multiplier = _get_grabbing_hand_scale_multiplier()
	for mesh in grabbed_mesh_instances:
		if mesh is MeshInstance3D and mesh.mesh is SphereMesh:
			_tip_clone_meshes.append(mesh)
	
	# Tip clones are updated manually each frame (tip scale + hand scale), so keep them
	# out of generic hand-scale rebasing.
	if not _tip_clone_meshes.is_empty() and hand.has_method("unregister_grabbed_nodes"):
		hand.unregister_grabbed_nodes(_tip_clone_meshes)
		
	# Find the XRController3D associated with this hand
	var controller = _find_controller_from_hand(hand)
	if tool_ui and controller:
		tool_ui.set_controller(controller)
	_update_tip_sphere()

func _on_released() -> void:
	if tool_ui:
		tool_ui.set_controller(null)
	_tip_clone_meshes.clear()
	_tip_clone_base_hand_multiplier = 1.0

func _find_controller_from_hand(hand: RigidBody3D) -> XRController3D:
	# In this project's structure, the controller is often the parent or grandparent of the hand
	# or they share a parent in the XROrigin3D.
	# xr_player.gd suggests Controllers are in PlayerBody/XROrigin3D/
	
	var node = hand as Node
	while node:
		if node is XRController3D:
			return node
		node = node.get_parent()
		
	# Fallback: find it via the tree if the hand is reparented
	var player = get_tree().get_first_node_in_group("xr_player")
	if player:
		var origin = player.get_node_or_null("PlayerBody/XROrigin3D")
		if origin:
			# Check if hand name contains "left" or "right"
			if "left" in hand.name.to_lower():
				return origin.get_node_or_null("LeftController")
			elif "right" in hand.name.to_lower():
				return origin.get_node_or_null("RightController")
				
	return null
