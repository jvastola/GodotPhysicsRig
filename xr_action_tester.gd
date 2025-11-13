extends Control

# XR Action Tester UI
# Builds a list of actions and checkboxes for left/right controllers.
# Attempts several methods to detect button/axis presses from XRController3D.

@export var quest3_only: bool = true

var default_actions := [
	{"name":"trigger","label":"Trigger"},
	{"name":"trigger_click","label":"Trigger Click"},
	{"name":"trigger_touch","label":"Trigger Touch"},
	{"name":"grip","label":"Grip"},
	{"name":"grip_click","label":"Grip Click"},
	{"name":"primary","label":"Primary (thumbstick)"},
	{"name":"primary_click","label":"Primary Click"},
	{"name":"secondary","label":"Secondary (thumbstick)"},
	{"name":"primary_touch","label":"Primary Touch"},
	{"name":"secondary_click","label":"Secondary Click"},
	{"name":"ax_button","label":"A/X Button"},
	{"name":"by_button","label":"B/Y Button"},
	{"name":"menu_button","label":"Menu/System"},
	{"name":"select_button","label":"Select"},
	{"name":"thumbstick","label":"Thumbstick (axis)"},
	{"name":"thumbstick_click","label":"Thumbstick Click"}
]

var quest3_actions := [
	{"name":"trigger","label":"Trigger"},
	{"name":"trigger_click","label":"Trigger Click"},
	{"name":"grip","label":"Grip"},
	{"name":"grip_click","label":"Grip Click"},
	{"name":"primary","label":"Thumbstick (Primary)"},
	{"name":"primary_click","label":"Thumbstick Click"},
	{"name":"primary_touch","label":"Thumbstick Touch"},
	{"name":"ax_button","label":"A/X Button"},
	{"name":"by_button","label":"B/Y Button"},
	{"name":"menu_button","label":"Menu/System"},
	{"name":"thumbstick","label":"Thumbstick (axis)"},
	{"name":"thumbstick_click","label":"Thumbstick Click"},
]

@export var actions := []

var left_controller: XRController3D = null
var right_controller: XRController3D = null
var checkboxes := {} # action_name -> {"left":CheckBox, "right":CheckBox}

func _ready():
	# Create a simple panel layout
	self.anchor_right = 0
	self.anchor_bottom = 0
	self.position = Vector2(12, 12)
	self.custom_minimum_size = Vector2(420, 300)
	# choose action set based on quest3_only
	if quest3_only:
		actions = quest3_actions
	else:
		actions = default_actions

	var panel = Panel.new()
	panel.name = "XRTestPanel"
	panel.custom_minimum_size = Vector2(420, 300)
	add_child(panel)

	var vb = VBoxContainer.new()
	vb.name = "VBox"
	vb.anchor_right = 0
	vb.anchor_bottom = 0
	panel.add_child(vb)

	var title = Label.new()
	title.text = "Oculus Touch Controls Test"
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_font_size_override("font_size", 18)
	vb.add_child(title)

	var grid = GridContainer.new()
	grid.columns = 3
	grid.name = "Grid"
	vb.add_child(grid)

	# header
	grid.add_child(Label.new())
	var lh = Label.new(); lh.text = "Left"; grid.add_child(lh)
	var rh = Label.new(); rh.text = "Right"; grid.add_child(rh)

	for a in actions:
		var name = a.name
		var label = Label.new()
		label.text = a.label
		grid.add_child(label)

		var cb_left = CheckBox.new()
		cb_left.disabled = true
		grid.add_child(cb_left)

		var cb_right = CheckBox.new()
		cb_right.disabled = true
		grid.add_child(cb_right)

		checkboxes[name] = {"left":cb_left, "right":cb_right}

	# reset button
	var h = HBoxContainer.new()
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(h)
	var reset_btn = Button.new()
	reset_btn.text = "Reset"
	reset_btn.connect("pressed", Callable(self, "_on_reset_pressed"))
	h.add_child(reset_btn)

	# try to find controller nodes in tree
	_find_controllers()

func _on_reset_pressed():
	for k in checkboxes.keys():
		checkboxes[k]["left"].set_pressed(false)
		checkboxes[k]["right"].set_pressed(false)

func _find_controllers():
	left_controller = null
	right_controller = null
	var root = get_tree().get_root()
	_search_for_controllers(root)

func _search_for_controllers(node):
	# depth-first search for nodes named like LeftController/RightController or of class XRController3D
	if typeof(node) == TYPE_OBJECT:
		if node.get_class() == "XRController3D":
			if node.name.to_lower().find("left") != -1:
				left_controller = node
			elif node.name.to_lower().find("right") != -1:
				right_controller = node
		# else continue search
	for c in node.get_children():
		_search_for_controllers(c)

func _process(delta):
	# If controllers are not found, try again occasionally
	if left_controller == null or right_controller == null:
		_find_controllers()

	for a in actions:
		var name = a.name
		var left_pressed = _check_action_on_controller(left_controller, name)
		var right_pressed = _check_action_on_controller(right_controller, name)

		if left_pressed:
			checkboxes[name]["left"].set_pressed(true)
		if right_pressed:
			checkboxes[name]["right"].set_pressed(true)

func _check_action_on_controller(controller, action_name):
	if controller == null:
		return false
	# Try methods in order: get_vector2 (axis), get_bool/get_float, generic call
	# 1) vector2
	if controller.has_method("get_vector2"):
		var ok := true
		var v = Vector2.ZERO
		# safe call
		v = controller.get_vector2(action_name) if controller.has_method("get_vector2") else Vector2.ZERO
		if v.length() > 0.3:
			return true

	# 2) get_axis / get_joy_axis style
	if controller.has_method("get_axis"):
		var f = controller.get_axis(action_name)
		if abs(f) > 0.3:
			return true

	# 3) get_bool / get_button
	if controller.has_method("get_bool"):
		if controller.get_bool(action_name):
			return true
	if controller.has_method("get_pressed"):
		if controller.get_pressed(action_name):
			return true
	if controller.has_method("get_button"):
		if controller.get_button(action_name):
			return true

	# 4) Input fallbacks: try Input singleton action names
	# Try the raw action name, and common left/right suffixed variants used in projects
	var candidates = [action_name, action_name + "_left", action_name + "_right"]
	for act in candidates:
		# Only call Input.* for actions that exist in the project's InputMap
		if InputMap.has_action(act):
			if Input.is_action_just_pressed(act) or Input.is_action_pressed(act):
				return true

	# 5) joypad fallback (check any device)
	for device in Input.get_connected_joypads():
		# try mapping common button indices? Not reliable; skip
		pass

	return false
