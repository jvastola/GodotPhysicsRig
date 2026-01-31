extends PanelContainer

# UI References
@onready var left_stick_base: Control = %LeftStickBase
@onready var left_stick_handle: Control = %LeftStickHandle
@onready var left_indicator_up: Control = %LeftIndicatorUp
@onready var left_indicator_down: Control = %LeftIndicatorDown
@onready var left_indicator_left: Control = %LeftIndicatorLeft
@onready var left_indicator_right: Control = %LeftIndicatorRight
@onready var left_coordinates_label: Label = %LeftCoordinatesLabel

@onready var right_stick_base: Control = %RightStickBase
@onready var right_stick_handle: Control = %RightStickHandle
@onready var right_indicator_up: Control = %RightIndicatorUp
@onready var right_indicator_down: Control = %RightIndicatorDown
@onready var right_indicator_left: Control = %RightIndicatorLeft
@onready var right_indicator_right: Control = %RightIndicatorRight
@onready var right_coordinates_label: Label = %RightCoordinatesLabel

# Visual Settings
@export var max_handle_distance: float = 25.0
@export var activation_threshold: float = 0.5
@export var active_color: Color = Color(0.2, 1.0, 0.2, 1.0)
@export var inactive_color: Color = Color(0.3, 0.3, 0.3, 1.0)

# Controller References
var left_controller: XRController3D
var right_controller: XRController3D

func _ready() -> void:
	_find_controllers()
	print("JoystickVis: _ready. Nodes check:")
	print("  LeftStickBase: ", left_stick_base)
	print("  LeftStickHandle: ", left_stick_handle)
	print("  RightStickBase: ", right_stick_base)
	print("  RightStickHandle: ", right_stick_handle)

func _process(_delta: float) -> void:
	if not left_controller or not right_controller:
		_find_controllers()
		
	if left_controller:
		_process_hand(left_controller, left_stick_base, left_stick_handle, left_indicator_up, left_indicator_down, left_indicator_left, left_indicator_right, left_coordinates_label)
		
	if right_controller:
		_process_hand(right_controller, right_stick_base, right_stick_handle, right_indicator_up, right_indicator_down, right_indicator_left, right_indicator_right, right_coordinates_label)

func _find_controllers() -> void:
	var player = get_tree().get_first_node_in_group("xr_player")
	if player:
		# Assuming standard Rig structure based on xr_player.gd
		var origin = player.get_node_or_null("PlayerBody/XROrigin3D")
		if origin:
			var new_left = origin.get_node_or_null("LeftController")
			var new_right = origin.get_node_or_null("RightController")
			if new_left != left_controller:
				left_controller = new_left
				print("JoystickVis: Found Left Controller: ", left_controller)
			if new_right != right_controller:
				right_controller = new_right
				print("JoystickVis: Found Right Controller: ", right_controller)

func _process_hand(controller: XRController3D, base: Control, handle: Control, up: Control, down: Control, left: Control, right: Control, label: Label) -> void:
	if not controller or not base or not handle:
		return
		
	var input := controller.get_vector2("primary")
	
	# Calculate offset for UI (invert Y axis because UI Y+ is Down, but Joystick Y+ is Up)
	var offset = Vector2(input.x, -input.y) * max_handle_distance
	
	# Update Handle Position (centered on base + offset)
	var center = base.size / 2.0
	handle.position = center + offset - (handle.size / 2.0)
	
	# Update Indicators
	if up: _update_indicator(up, input.y > activation_threshold)
	if down: _update_indicator(down, input.y < -activation_threshold)
	if left: _update_indicator(left, input.x < -activation_threshold)
	if right: _update_indicator(right, input.x > activation_threshold)
	
	# Update Label
	if label:
		label.text = "X: %.2f\nY: %.2f" % [input.x, input.y]

func _update_indicator(indicator: Control, active: bool) -> void:
	indicator.modulate = active_color if active else inactive_color
