extends Grabbable

# Joystick Tool - 3D Object Logic
# Integrates the selection UI with the grabbable physics object

@onready var ui_viewport: SubViewport = $SubViewport
@onready var tool_ui = $SubViewport/JoystickToolUI

var anchor_y: float = 0.0

func _ready() -> void:
	super._ready()
	# Connect to grab signals to track which hand is using the tool
	grabbed.connect(_on_grabbed)
	released.connect(_on_released)
	
	if tool_ui:
		tool_ui.tip_scale_changed.connect(_on_tip_scale_changed)
	
	# Calculate anchor (cone tip) based on initial editor placement
	var tip_sphere = %TipSphere
	if tip_sphere:
		# Assuming initial scale is 1.0 (or whatever is in editor) acting as "base"
		# Actually, user wants "bottom attached".
		# Anchor Y = Center Y - Radius
		# We assume the editor position represents the sphere sitting on the tip.
		anchor_y = tip_sphere.position.y - 0.03 # Radius is 0.03

func _on_tip_scale_changed(_new_scale: float) -> void:
	# Processed every frame in _process but we can force an update here if needed
	_update_tip_sphere()

func _process(_delta: float) -> void:
	_update_tip_sphere()

func _update_tip_sphere() -> void:
	var tip_sphere = %TipSphere
	if not tip_sphere or not tool_ui: return
	
	# Visibility: ALWAYS visible as requested
	# ONLY show the original sphere if we are NOT currently grabbed (Grabbable handles the visual clone)
	tip_sphere.visible = not is_grabbed
	
	# APPLY SCALE
	var current_scale = tool_ui.tip_scale
	tip_sphere.scale = Vector3.ONE * current_scale
	
	# POSITIONING: Attach bottom of sphere to calculated anchor
	var radius = 0.03 * current_scale
	tip_sphere.position = Vector3(0, anchor_y + radius, 0)
	
	# Also update the cloned visuals on the hand if grabbed
	if is_grabbed and is_instance_valid(grabbing_hand):
		# Create the transform representing the sphere in Hand space
		# Reusing the logic from Grabbable._create_hand_collision_shapes
		var grab_tf = Transform3D(Basis(grab_rotation_offset), grab_offset)
		var sphere_local_tf = tip_sphere.transform
		var sphere_hand_tf = grab_tf * sphere_local_tf
		
		for mesh in grabbed_mesh_instances:
			if mesh is MeshInstance3D and mesh.mesh is SphereMesh:
				# Always visible on hand
				mesh.visible = true
				# Apply the FULL transform (position, rotation, scale)
				mesh.transform = sphere_hand_tf
				# Scale is part of basis usually, but if basis is generic, safer to set scale explicitly if needed?
				# Transform mul includes scale if sphere_local_tf has it.
				# tip_sphere.transform already includes the scale we set above!

func _on_grabbed(hand: RigidBody3D) -> void:
	if not hand:
		# Could be a desktop grab
		return
		
	# Find the XRController3D associated with this hand
	var controller = _find_controller_from_hand(hand)
	if tool_ui and controller:
		tool_ui.set_controller(controller)

func _on_released() -> void:
	if tool_ui:
		tool_ui.set_controller(null)

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
