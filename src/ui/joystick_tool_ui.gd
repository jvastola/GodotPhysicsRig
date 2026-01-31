extends PanelContainer

# Joystick Tool UI - Selection Logic
# Handles directional selection of tools using joystick input

@onready var icon_up: Label = %IconUp
@onready var icon_down: Label = %IconDown
@onready var icon_left: Label = %IconLeft
@onready var icon_right: Label = %IconRight
@onready var stick_handle: Panel = %StickHandle
@onready var stick_base: Panel = %StickBase

@export var activation_threshold: float = 0.6
@export var highlight_color: Color = Color(1.0, 1.0, 0.2, 1.0) # Yellow for selection
@export var default_color: Color = Color(1, 1, 1, 1)

var current_selection: String = ""
var active_controller: XRController3D = null

func _process(_delta: float) -> void:
	if not active_controller:
		# Reset visuals if no controller
		_update_visuals(Vector2.ZERO)
		return
		
	var input = active_controller.get_vector2("primary")
	_update_visuals(input)
	_process_selection(input)

func _update_visuals(input: Vector2) -> void:
	# Update stick handle position
	var max_dist = 20.0
	var center = stick_base.size / 2.0
	# Invert Y for UI
	var offset = Vector2(input.x, -input.y) * max_dist
	stick_handle.position = center + offset - (stick_handle.size / 2.0)
	
	# Reset highlights
	icon_up.modulate = default_color
	icon_down.modulate = default_color
	icon_left.modulate = default_color
	icon_right.modulate = default_color
	
	# Highlight selected
	if input.length() > activation_threshold:
		if abs(input.x) > abs(input.y):
			if input.x > 0:
				icon_right.modulate = highlight_color
			else:
				icon_left.modulate = highlight_color
		else:
			if input.y > 0:
				icon_up.modulate = highlight_color
			else:
				icon_down.modulate = highlight_color

func _process_selection(input: Vector2) -> void:
	var new_selection = ""
	if input.length() > activation_threshold:
		if abs(input.x) > abs(input.y):
			new_selection = "right" if input.x > 0 else "left"
		else:
			new_selection = "up" if input.y > 0 else "down"
	
	if new_selection != current_selection:
		current_selection = new_selection
		if current_selection != "":
			print("JoystickTool: Selected ", current_selection)

func set_controller(controller: XRController3D) -> void:
	active_controller = controller
	if not active_controller:
		current_selection = ""
