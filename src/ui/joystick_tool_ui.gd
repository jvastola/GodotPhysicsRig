extends PanelContainer

# Joystick Tool UI - Selection Logic
# Handles directional selection of tools using joystick input

@onready var icon_up: Label = %IconUp
@onready var icon_down: Label = %IconDown
@onready var icon_left: Label = %IconLeft
@onready var icon_right: Label = %IconRight
@onready var section_up: Panel = %SectionUp
@onready var section_down: Panel = %SectionDown
@onready var section_left: Panel = %SectionLeft
@onready var section_right: Panel = %SectionRight
@onready var stick_handle: Panel = %StickHandle
@onready var stick_base: Panel = %StickBase

@export var activation_threshold: float = 0.6
@export var highlight_color: Color = Color(1.0, 1.0, 1.0, 1.0) # White for icon when highlighted
@export var default_color: Color = Color(0.8, 0.8, 0.8, 1)

var highlight_style: StyleBoxFlat
var empty_style: StyleBoxEmpty

var current_selection: String = ""
var active_controller: XRController3D = null

func _ready() -> void:
	# Create styles in code for consistency
	highlight_style = StyleBoxFlat.new()
	highlight_style.bg_color = Color(0.1, 0.4, 0.8, 0.8) # Nice Blue
	highlight_style.set_corner_radius_all(10)
	
	empty_style = StyleBoxEmpty.new()

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
	
	# Reset blocks to default
	for section in [section_up, section_down, section_left, section_right]:
		section.add_theme_stylebox_override("panel", empty_style)
	
	# Reset icons to default
	for icon in [icon_up, icon_down, icon_left, icon_right]:
		icon.modulate = default_color
	
	# 1. APPLY PERSISTENT HIGHLIGHT (Based on current_selection)
	var active_section: Panel = null
	var active_icon: Label = null
	match current_selection:
		"up":
			active_section = section_up
			active_icon = icon_up
		"down":
			active_section = section_down
			active_icon = icon_down
		"left":
			active_section = section_left
			active_icon = icon_left
		"right":
			active_section = section_right
			active_icon = icon_right
	
	if active_section:
		active_section.add_theme_stylebox_override("panel", highlight_style)
	if active_icon:
		active_icon.modulate = highlight_color

	# 2. APPLY LIVE SELECTION HIGHLIGHT (If hovering different from current)
	if input.length() > activation_threshold:
		var hover_section: Panel = null
		var hover_icon: Label = null
		var hover_mode = ""
		
		if abs(input.x) > abs(input.y):
			if input.x > 0:
				hover_section = section_right
				hover_icon = icon_right
				hover_mode = "right"
			else:
				hover_section = section_left
				hover_icon = icon_left
				hover_mode = "left"
		else:
			if input.y > 0:
				hover_section = section_up
				hover_icon = icon_up
				hover_mode = "up"
			else:
				hover_section = section_down
				hover_icon = icon_down
				hover_mode = "down"
		
		# If we are hovering over a NEW mode that isn't the current selection,
		# use a slightly different color (yellowish) or just the same blue.
		# The user asked to keep it blue, so we'll use same blue but maybe different icon color.
		if hover_mode != current_selection:
			if hover_section:
				hover_section.add_theme_stylebox_override("panel", highlight_style)
			if hover_icon:
				hover_icon.modulate = Color(1.0, 1.0, 0.5, 1.0) # Yellowish hint for hover

func _process_selection(input: Vector2) -> void:
	var new_selection = ""
	if input.length() > activation_threshold:
		if abs(input.x) > abs(input.y):
			new_selection = "right" if input.x > 0 else "left"
		else:
			new_selection = "up" if input.y > 0 else "down"
	
	# Only update if we have a NEW valid selection (not empty)
	if new_selection != "" and new_selection != current_selection:
		current_selection = new_selection
		print("JoystickTool: Selected ", current_selection)

func set_controller(controller: XRController3D) -> void:
	active_controller = controller
	if not active_controller:
		current_selection = ""
