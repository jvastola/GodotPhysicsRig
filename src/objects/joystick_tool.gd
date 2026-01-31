extends Grabbable

# Joystick Tool - 3D Object Logic
# Integrates the selection UI with the grabbable physics object

@onready var ui_viewport: SubViewport = $SubViewport
@onready var tool_ui = $SubViewport/JoystickToolUI

func _ready() -> void:
	super._ready()
	# Connect to grab signals to track which hand is using the tool
	grabbed.connect(_on_grabbed)
	released.connect(_on_released)

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
