extends PanelContainer
class_name MovementSettingsPanel
## Movement Settings Panel - Locomotion, turning, and hand swap controls

signal settings_changed()

# Visual palette
const COLOR_TITLE := Color(0.88, 0.93, 1.0)
const COLOR_SUBTITLE := Color(0.7, 0.78, 0.9)
const COLOR_ACCENT := Color(0.42, 0.75, 1.0)
const COLOR_CARD_BG := Color(0.16, 0.17, 0.21)
const COLOR_CARD_BORDER := Color(0.24, 0.29, 0.36)

# Defaults snapshot (updated once a player component is found)
const DEFAULTS := {
	"locomotion_mode": PlayerMovementComponent.LocomotionMode.DISABLED,
	"locomotion_speed": 3.0,
	"locomotion_deadzone": 0.2,
	"turn_mode": PlayerMovementComponent.TurnMode.SNAP,
	"snap_turn_angle": 45.0,
	"smooth_turn_speed": 90.0,
	"turn_deadzone": 0.5,
	"snap_turn_cooldown": 0.3,
	"hand_assignment": PlayerMovementComponent.HandAssignment.DEFAULT,
	"enable_two_hand_world_scale": false,
	"enable_two_hand_world_rotation": false,
	"world_scale_min": 0.1,
	"world_scale_max": 15.0,
	"world_scale_sensitivity": 0.35,
	"world_rotation_sensitivity": 0.6,
	"enable_one_hand_world_grab": false,
	"one_hand_world_move_sensitivity": 0.35,
	"jump_enabled": false,
	"jump_impulse": 12.0,
	"jump_cooldown": 0.4,
	"player_gravity_enabled": true,
}

# UI References - set up dynamically
var locomotion_mode_btn: OptionButton
var locomotion_speed_slider: HSlider
var locomotion_speed_label: Label
var locomotion_deadzone_slider: HSlider
var locomotion_deadzone_label: Label
var turn_mode_btn: OptionButton
var snap_angle_slider: HSlider
var snap_angle_label: Label
var smooth_speed_slider: HSlider
var smooth_speed_label: Label
var deadzone_slider: HSlider
var deadzone_label: Label
var snap_cooldown_slider: HSlider
var snap_cooldown_label: Label
var hand_swap_check: CheckBox
var world_scale_check: CheckBox
var world_rotation_check: CheckBox
var gravity_check: CheckBox
var world_scale_min_slider: HSlider
var world_scale_min_label: Label
var world_scale_max_slider: HSlider
var world_scale_max_label: Label
var status_label: Label
var world_scale_sensitivity_slider: HSlider
var world_scale_sensitivity_label: Label
var world_rotation_sensitivity_slider: HSlider
var world_rotation_sensitivity_label: Label
var one_hand_world_grab_check: CheckBox
var one_hand_world_move_sense_slider: HSlider
var one_hand_world_move_sense_label: Label
var jump_enabled_check: CheckBox
var jump_impulse_slider: HSlider
var jump_impulse_label: Label
var jump_cooldown_slider: HSlider
var jump_cooldown_label: Label

var snap_container: VBoxContainer
var smooth_container: VBoxContainer

# Reference to movement component
var movement_component: PlayerMovementComponent
var defaults_snapshot := DEFAULTS.duplicate(true)


func _ready():
	_find_movement_component()
	_build_ui()


func _find_movement_component():
	"""Find the player's movement component"""
	var player = get_tree().get_first_node_in_group("xr_player")
	if player:
		movement_component = player.get_node_or_null("PlayerMovementComponent")
		if movement_component:
			print("MovementSettingsPanel: Found movement component")
			_snapshot_defaults()
			# Ensure UI reflects live values once found
			call_deferred("refresh")
		else:
			push_warning("MovementSettingsPanel: PlayerMovementComponent not found")
	else:
		# Retry after a frame
		call_deferred("_find_movement_component")


func _build_ui():
	"""Build the settings UI dynamically"""
	# Root with padding + scroll so all controls remain reachable
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	# Main container
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(main_vbox)
	
	# Title + status
	var header_card = _create_card(main_vbox, "Movement Settings", "Tune locomotion, turning, and interaction comfort", "🧭")
	var header_row = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	header_card.add_child(header_row)
	
	status_label = _make_hint("Waiting for player...")
	_update_status_label()
	header_row.add_child(status_label)
	
	var reset_btn = Button.new()
	reset_btn.text = "Reset to Defaults"
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.pressed.connect(_on_reset_pressed)
	header_row.add_child(reset_btn)
	
	# === Locomotion Section ===
	var locomotion_card = _create_card(main_vbox, "Locomotion", "Speed and direction source for thumbstick movement", "🏃")
	
	# Locomotion Mode
	var loco_row = _create_row(locomotion_card, "Mode")
	locomotion_mode_btn = OptionButton.new()
	locomotion_mode_btn.add_item("Disabled")
	locomotion_mode_btn.add_item("Head Direction")
	locomotion_mode_btn.add_item("Hand Direction")
	locomotion_mode_btn.add_item("Head Direction (3D)")
	locomotion_mode_btn.add_item("Hand Direction (3D)")
	locomotion_mode_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	locomotion_mode_btn.tooltip_text = "Choose where movement direction is derived from."
	if movement_component:
		locomotion_mode_btn.selected = movement_component.locomotion_mode
	else:
		locomotion_mode_btn.selected = defaults_snapshot["locomotion_mode"]
	locomotion_mode_btn.item_selected.connect(func(index: int):
		_on_locomotion_mode_changed(index)
		_update_locomotion_controls_enabled()
	)
	loco_row.add_child(locomotion_mode_btn)
	
	# Locomotion Speed
	var initial_speed = movement_component.locomotion_speed if movement_component else defaults_snapshot["locomotion_speed"]
	var speed_block = _add_slider_block(
		locomotion_card,
		"Speed",
		"Movement velocity in meters per second.",
		1.0,
		8.0,
		0.25,
		initial_speed,
		func(value): return " %.1f m/s" % value
	)
	locomotion_speed_label = speed_block.label
	locomotion_speed_slider = speed_block.slider
	locomotion_speed_slider.value_changed.connect(func(value: float): _on_locomotion_speed_changed(value))
	
	# Locomotion Deadzone
	var initial_loco_deadzone = movement_component.locomotion_deadzone if movement_component else defaults_snapshot["locomotion_deadzone"]
	var loco_deadzone_block = _add_slider_block(
		locomotion_card,
		"Locomotion Deadzone",
		"Ignore thumbstick wobble below this value.",
		0.05,
		0.6,
		0.02,
		initial_loco_deadzone,
		func(value): return " %.2f"
	)
	locomotion_deadzone_label = loco_deadzone_block.label
	locomotion_deadzone_slider = loco_deadzone_block.slider
	locomotion_deadzone_slider.value_changed.connect(func(value: float): _on_locomotion_deadzone_changed(value))
	
	# === Turning Section ===
	var turning_card = _create_card(main_vbox, "Turning", "Snap or smooth turning with sensitivity controls", "🌀")
	
	# Turn Mode
	var turn_row = _create_row(turning_card, "Turn Mode")
	turn_mode_btn = OptionButton.new()
	turn_mode_btn.add_item("Snap")
	turn_mode_btn.add_item("Smooth")
	turn_mode_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if movement_component:
		turn_mode_btn.selected = movement_component.turn_mode
	else:
		turn_mode_btn.selected = defaults_snapshot["turn_mode"]
	turn_mode_btn.item_selected.connect(func(index: int):
		_on_turn_mode_changed(index)
		_update_turn_mode_ui()
	)
	turn_row.add_child(turn_mode_btn)
	
	# Snap Angle
	snap_container = VBoxContainer.new()
	var initial_snap = movement_component.snap_turn_angle if movement_component else defaults_snapshot["snap_turn_angle"]
	var snap_block = _add_slider_block(
		snap_container,
		"Snap Angle",
		"Degrees rotated per snap turn.",
		15.0,
		90.0,
		5.0,
		initial_snap,
		func(value): return " %.0f°" % value
	)
	snap_angle_label = snap_block.label
	snap_angle_slider = snap_block.slider
	snap_angle_slider.value_changed.connect(func(value: float): _on_snap_angle_changed(value))
	turning_card.add_child(snap_container)
	
	# Snap Cooldown
	var initial_cooldown = movement_component.snap_turn_cooldown if movement_component else defaults_snapshot["snap_turn_cooldown"]
	var cooldown_block = _add_slider_block(
		turning_card,
		"Snap Cooldown",
		"Delay between snap turns (seconds).",
		0.1,
		0.7,
		0.05,
		initial_cooldown,
		func(value): return " %.2fs" % value
	)
	snap_cooldown_label = cooldown_block.label
	snap_cooldown_slider = cooldown_block.slider
	snap_cooldown_slider.value_changed.connect(func(value: float): _on_snap_cooldown_changed(value))
	
	# Smooth Speed
	smooth_container = VBoxContainer.new()
	var initial_smooth = movement_component.smooth_turn_speed if movement_component else defaults_snapshot["smooth_turn_speed"]
	var smooth_block = _add_slider_block(
		smooth_container,
		"Smooth Speed",
		"Rotation speed for continuous turning.",
		30.0,
		240.0,
		10.0,
		initial_smooth,
		func(value): return " %.0f°/s" % value
	)
	smooth_speed_label = smooth_block.label
	smooth_speed_slider = smooth_block.slider
	smooth_speed_slider.value_changed.connect(func(value: float): _on_smooth_speed_changed(value))
	turning_card.add_child(smooth_container)
	
	# Deadzone
	var initial_deadzone = movement_component.turn_deadzone if movement_component else defaults_snapshot["turn_deadzone"]
	var deadzone_block = _add_slider_block(
		turning_card,
		"Turn Deadzone",
		"Ignore turn input until the stick passes this threshold.",
		0.05,
		0.9,
		0.02,
		initial_deadzone,
		func(value): return " %.2f"
	)
	deadzone_label = deadzone_block.label
	deadzone_slider = deadzone_block.slider
	deadzone_slider.value_changed.connect(func(value: float): _on_deadzone_changed(value))
	
	# === Hand Assignment Section ===
	var controls_card = _create_card(main_vbox, "Controls", "Choose which hand drives movement and turning", "👐")
	
	# Hand Swap Checkbox
	hand_swap_check = CheckBox.new()
	hand_swap_check.text = "Swap Hands (Move Right / Turn Left)"
	hand_swap_check.add_theme_font_size_override("font_size", 12)
	hand_swap_check.tooltip_text = "Swap controller roles for movement vs turning."
	if movement_component:
		hand_swap_check.button_pressed = movement_component.hand_assignment == PlayerMovementComponent.HandAssignment.SWAPPED
	else:
		hand_swap_check.button_pressed = defaults_snapshot["hand_assignment"] == PlayerMovementComponent.HandAssignment.SWAPPED
	hand_swap_check.toggled.connect(func(pressed: bool): _on_hand_swap_toggled(pressed))
	controls_card.add_child(hand_swap_check)

	# === World Manipulation ===
	var world_card = _create_card(main_vbox, "World Manipulation", "Two-hand gestures for scaling and rotating the world", "🌍")

	world_scale_check = CheckBox.new()
	world_scale_check.text = "Two-Hand Grab: Scale"
	world_scale_check.add_theme_font_size_override("font_size", 12)
	if movement_component:
		world_scale_check.button_pressed = movement_component.enable_two_hand_world_scale
	else:
		world_scale_check.button_pressed = defaults_snapshot["enable_two_hand_world_scale"]
	world_scale_check.toggled.connect(func(pressed: bool): _on_world_scale_toggled(pressed))
	world_scale_check.tooltip_text = "Pinch/pull with both grips to resize the world."
	world_card.add_child(world_scale_check)

	world_rotation_check = CheckBox.new()
	world_rotation_check.text = "Two-Hand Grab: Rotation"
	world_rotation_check.add_theme_font_size_override("font_size", 12)
	if movement_component:
		world_rotation_check.button_pressed = movement_component.enable_two_hand_world_rotation
	else:
		world_rotation_check.button_pressed = defaults_snapshot["enable_two_hand_world_rotation"]
	world_rotation_check.toggled.connect(func(pressed: bool): _on_world_rotation_toggled(pressed))
	world_rotation_check.tooltip_text = "Twist both grips to rotate the environment."
	world_card.add_child(world_rotation_check)
	
	one_hand_world_grab_check = CheckBox.new()
	one_hand_world_grab_check.text = "One-Hand World Grab"
	one_hand_world_grab_check.add_theme_font_size_override("font_size", 12)
	if movement_component:
		one_hand_world_grab_check.button_pressed = movement_component.enable_one_hand_world_grab
	else:
		one_hand_world_grab_check.button_pressed = defaults_snapshot["enable_one_hand_world_grab"]
	one_hand_world_grab_check.tooltip_text = "Allow moving the world with a single grip."
	one_hand_world_grab_check.toggled.connect(func(pressed: bool): _on_one_hand_world_grab_toggled(pressed))
	world_card.add_child(one_hand_world_grab_check)
	
	var initial_world_min = movement_component.world_scale_min if movement_component else defaults_snapshot["world_scale_min"]
	var world_min_block = _add_slider_block(
		world_card,
		"World Scale Min",
		"Lower bound for two-hand world scaling.",
		0.05,
		10.0,
		0.05,
		initial_world_min,
		func(value): return " %.2fx" % value
	)
	world_scale_min_label = world_min_block.label
	world_scale_min_slider = world_min_block.slider
	world_scale_min_slider.value_changed.connect(func(value: float): _on_world_scale_min_changed(value))
	
	var initial_world_max = movement_component.world_scale_max if movement_component else defaults_snapshot["world_scale_max"]
	var world_max_block = _add_slider_block(
		world_card,
		"World Scale Max",
		"Upper bound for two-hand world scaling.",
		0.5,
		50.0,
		0.25,
		initial_world_max,
		func(value): return " %.2fx" % value
	)
	world_scale_max_label = world_max_block.label
	world_scale_max_slider = world_max_block.slider
	world_scale_max_slider.value_changed.connect(func(value: float): _on_world_scale_max_changed(value))

	var initial_scale_sense = movement_component.world_scale_sensitivity if movement_component else defaults_snapshot["world_scale_sensitivity"]
	var scale_sense_block = _add_slider_block(
		world_card,
		"Scale Sensitivity",
		"Multiplier for how strongly distance changes scale.",
		0.05,
		1.5,
		0.05,
		initial_scale_sense,
		func(value): return " x%.2f" % value
	)
	world_scale_sensitivity_label = scale_sense_block.label
	world_scale_sensitivity_slider = scale_sense_block.slider
	world_scale_sensitivity_slider.value_changed.connect(func(value: float): _on_world_scale_sensitivity_changed(value))

	var initial_rot_sense = movement_component.world_rotation_sensitivity if movement_component else defaults_snapshot["world_rotation_sensitivity"]
	var rot_sense_block = _add_slider_block(
		world_card,
		"Rotation Sensitivity",
		"Dampen or amplify twist responsiveness.",
		0.05,
		2.0,
		0.05,
		initial_rot_sense,
		func(value): return " x%.2f" % value
	)
	world_rotation_sensitivity_label = rot_sense_block.label
	world_rotation_sensitivity_slider = rot_sense_block.slider
	world_rotation_sensitivity_slider.value_changed.connect(func(value: float): _on_world_rotation_sensitivity_changed(value))

	var initial_one_hand_sense = movement_component.one_hand_world_move_sensitivity if movement_component else defaults_snapshot["one_hand_world_move_sensitivity"]
	var one_hand_sense_block = _add_slider_block(
		world_card,
		"One-Hand Move Sensitivity",
		"How much the world moves per meter of hand motion.",
		0.05,
		5.0,
		0.05,
		initial_one_hand_sense,
		func(value): return " x%.2f" % value
	)
	one_hand_world_move_sense_label = one_hand_sense_block.label
	one_hand_world_move_sense_slider = one_hand_sense_block.slider
	one_hand_world_move_sense_slider.value_changed.connect(func(value: float): _on_one_hand_world_move_sensitivity_changed(value))

	# === Player ===
	var player_card = _create_card(main_vbox, "Player", "Gravity and safety preferences", "🧍")

	gravity_check = CheckBox.new()
	gravity_check.text = "Player Gravity Enabled"
	gravity_check.add_theme_font_size_override("font_size", 12)
	if movement_component:
		gravity_check.button_pressed = movement_component.player_gravity_enabled
	else:
		gravity_check.button_pressed = defaults_snapshot["player_gravity_enabled"]
	gravity_check.toggled.connect(func(pressed: bool): _on_gravity_toggled(pressed))
	player_card.add_child(gravity_check)
	
	jump_enabled_check = CheckBox.new()
	jump_enabled_check.text = "Enable Jump (action: jump)"
	jump_enabled_check.add_theme_font_size_override("font_size", 12)
	if movement_component:
		jump_enabled_check.button_pressed = movement_component.jump_enabled
	else:
		jump_enabled_check.button_pressed = defaults_snapshot["jump_enabled"]
	jump_enabled_check.toggled.connect(func(pressed: bool): _on_jump_enabled_toggled(pressed))
	player_card.add_child(jump_enabled_check)
	
	var initial_jump_impulse = movement_component.jump_impulse if movement_component else defaults_snapshot["jump_impulse"]
	var jump_impulse_block = _add_slider_block(
		player_card,
		"Jump Impulse",
		"Upward impulse when pressing the jump action.",
		4.0,
		30.0,
		0.5,
		initial_jump_impulse,
		func(value): return " %.1f"
	)
	jump_impulse_label = jump_impulse_block.label
	jump_impulse_slider = jump_impulse_block.slider
	jump_impulse_slider.value_changed.connect(func(value: float): _on_jump_impulse_changed(value))
	
	var initial_jump_cd = movement_component.jump_cooldown if movement_component else defaults_snapshot["jump_cooldown"]
	var jump_cd_block = _add_slider_block(
		player_card,
		"Jump Cooldown",
		"Delay before another jump can trigger.",
		0.0,
		2.0,
		0.05,
		initial_jump_cd,
		func(value): return " %.2fs" % value
	)
	jump_cooldown_label = jump_cd_block.label
	jump_cooldown_slider = jump_cd_block.slider
	jump_cooldown_slider.value_changed.connect(func(value: float): _on_jump_cooldown_changed(value))
	
	_update_turn_mode_ui()
	_update_locomotion_controls_enabled()
	_update_status_label()


func _add_section_label(parent: VBoxContainer, text: String):
	var label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	label.add_theme_font_size_override("font_size", 13)
	parent.add_child(label)


func _add_separator(parent: VBoxContainer):
	var sep = HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 4)
	parent.add_child(sep)


func _create_row(parent: VBoxContainer, label_text: String) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(110, 0)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", COLOR_SUBTITLE)
	row.add_child(label)
	
	parent.add_child(row)
	return row


# === Event Handlers ===

func _on_locomotion_mode_changed(index: int):
	if movement_component:
		movement_component.locomotion_mode = index as PlayerMovementComponent.LocomotionMode
		print("MovementSettings: Locomotion mode -> ", ["Disabled", "Head Direction", "Hand Direction"][index])
	settings_changed.emit()


func _on_locomotion_speed_changed(value: float):
	if movement_component:
		movement_component.locomotion_speed = value
	locomotion_speed_label.text = "Speed: %.1f m/s" % value
	settings_changed.emit()


func _on_locomotion_deadzone_changed(value: float):
	if movement_component:
		movement_component.locomotion_deadzone = value
	locomotion_deadzone_label.text = "Locomotion Deadzone: %.2f" % value
	settings_changed.emit()


func _on_turn_mode_changed(index: int):
	if movement_component:
		movement_component.turn_mode = index as PlayerMovementComponent.TurnMode
	settings_changed.emit()


func _on_snap_angle_changed(value: float):
	if movement_component:
		movement_component.snap_turn_angle = value
	snap_angle_label.text = "Snap Angle: %.0f°" % value
	settings_changed.emit()


func _on_snap_cooldown_changed(value: float):
	if movement_component:
		movement_component.snap_turn_cooldown = value
	snap_cooldown_label.text = "Snap Cooldown: %.2fs" % value
	settings_changed.emit()


func _on_smooth_speed_changed(value: float):
	if movement_component:
		movement_component.smooth_turn_speed = value
	smooth_speed_label.text = "Smooth Speed: %.0f°/s" % value
	settings_changed.emit()


func _on_deadzone_changed(value: float):
	if movement_component:
		movement_component.turn_deadzone = value
	deadzone_label.text = "Deadzone: %.2f" % value
	settings_changed.emit()


func _on_hand_swap_toggled(pressed: bool):
	if movement_component:
		if pressed:
			movement_component.hand_assignment = PlayerMovementComponent.HandAssignment.SWAPPED
		else:
			movement_component.hand_assignment = PlayerMovementComponent.HandAssignment.DEFAULT
		print("MovementSettings: Hand swap -> ", "Swapped" if pressed else "Default")
	settings_changed.emit()


func _on_world_scale_toggled(pressed: bool):
	if movement_component:
		movement_component.enable_two_hand_world_scale = pressed
	settings_changed.emit()


func _on_world_rotation_toggled(pressed: bool):
	if movement_component:
		movement_component.enable_two_hand_world_rotation = pressed
	settings_changed.emit()


func _on_world_scale_min_changed(value: float):
	if world_scale_max_slider and value > world_scale_max_slider.value:
		world_scale_max_slider.value = value
	if movement_component:
		movement_component.world_scale_min = value
	world_scale_min_label.text = "World Scale Min: %.2fx" % value
	settings_changed.emit()


func _on_world_scale_max_changed(value: float):
	if world_scale_min_slider and value < world_scale_min_slider.value:
		world_scale_min_slider.value = value
	if movement_component:
		movement_component.world_scale_max = value
	world_scale_max_label.text = "World Scale Max: %.2fx" % value
	settings_changed.emit()


func _on_world_scale_sensitivity_changed(value: float):
	if movement_component:
		movement_component.world_scale_sensitivity = value
	world_scale_sensitivity_label.text = "Scale Sensitivity: x%.2f" % value
	settings_changed.emit()


func _on_world_rotation_sensitivity_changed(value: float):
	if movement_component:
		movement_component.world_rotation_sensitivity = value
	world_rotation_sensitivity_label.text = "Rotation Sensitivity: x%.2f" % value
	settings_changed.emit()


func _on_one_hand_world_grab_toggled(pressed: bool):
	if movement_component:
		movement_component.enable_one_hand_world_grab = pressed
	settings_changed.emit()


func _on_one_hand_world_move_sensitivity_changed(value: float):
	if movement_component:
		movement_component.one_hand_world_move_sensitivity = value
	one_hand_world_move_sense_label.text = "One-Hand Move Sensitivity: x%.2f" % value
	settings_changed.emit()


func _on_jump_enabled_toggled(pressed: bool):
	if movement_component:
		movement_component.jump_enabled = pressed
	settings_changed.emit()


func _on_jump_impulse_changed(value: float):
	if movement_component:
		movement_component.jump_impulse = value
	jump_impulse_label.text = "Jump Impulse: %.1f" % value
	settings_changed.emit()


func _on_jump_cooldown_changed(value: float):
	if movement_component:
		movement_component.jump_cooldown = value
	jump_cooldown_label.text = "Jump Cooldown: %.2fs" % value
	settings_changed.emit()


func _on_gravity_toggled(pressed: bool):
	if movement_component:
		movement_component.set_player_gravity_enabled(pressed)
	settings_changed.emit()


func _on_reset_pressed():
	# Prefer live snapshot when available, otherwise defaults
	var source = defaults_snapshot if defaults_snapshot.size() > 0 else DEFAULTS
	_apply_defaults(source)
	refresh()
	settings_changed.emit()


# === Public API ===

func refresh():
	"""Refresh UI from current component values"""
	if not movement_component:
		_find_movement_component()
	
	if movement_component:
		_snapshot_defaults()
		if locomotion_mode_btn:
			locomotion_mode_btn.selected = movement_component.locomotion_mode
		if locomotion_speed_slider:
			locomotion_speed_slider.value = movement_component.locomotion_speed
		if locomotion_deadzone_slider:
			locomotion_deadzone_slider.value = movement_component.locomotion_deadzone
		if turn_mode_btn:
			turn_mode_btn.selected = movement_component.turn_mode
		if snap_angle_slider:
			snap_angle_slider.value = movement_component.snap_turn_angle
		if snap_cooldown_slider:
			snap_cooldown_slider.value = movement_component.snap_turn_cooldown
		if smooth_speed_slider:
			smooth_speed_slider.value = movement_component.smooth_turn_speed
		if deadzone_slider:
			deadzone_slider.value = movement_component.turn_deadzone
		if hand_swap_check:
			hand_swap_check.button_pressed = movement_component.hand_assignment == PlayerMovementComponent.HandAssignment.SWAPPED
		if world_scale_check:
			world_scale_check.button_pressed = movement_component.enable_two_hand_world_scale
		if world_rotation_check:
			world_rotation_check.button_pressed = movement_component.enable_two_hand_world_rotation
		if gravity_check:
			gravity_check.button_pressed = movement_component.player_gravity_enabled
		if world_scale_min_slider:
			world_scale_min_slider.value = movement_component.world_scale_min
		if world_scale_max_slider:
			world_scale_max_slider.value = movement_component.world_scale_max
		if world_scale_sensitivity_slider:
			world_scale_sensitivity_slider.value = movement_component.world_scale_sensitivity
		if world_rotation_sensitivity_slider:
			world_rotation_sensitivity_slider.value = movement_component.world_rotation_sensitivity
		if one_hand_world_grab_check:
			one_hand_world_grab_check.button_pressed = movement_component.enable_one_hand_world_grab
		if one_hand_world_move_sense_slider:
			one_hand_world_move_sense_slider.value = movement_component.one_hand_world_move_sensitivity
		if jump_enabled_check:
			jump_enabled_check.button_pressed = movement_component.jump_enabled
		if jump_impulse_slider:
			jump_impulse_slider.value = movement_component.jump_impulse
		if jump_cooldown_slider:
			jump_cooldown_slider.value = movement_component.jump_cooldown
	
	_update_turn_mode_ui()
	_update_locomotion_controls_enabled()
	_update_status_label()


# === Helpers ===

func _snapshot_defaults():
	if not movement_component:
		return
	defaults_snapshot = {
		"locomotion_mode": movement_component.locomotion_mode,
		"locomotion_speed": movement_component.locomotion_speed,
		"locomotion_deadzone": movement_component.locomotion_deadzone,
		"turn_mode": movement_component.turn_mode,
		"snap_turn_angle": movement_component.snap_turn_angle,
		"smooth_turn_speed": movement_component.smooth_turn_speed,
		"turn_deadzone": movement_component.turn_deadzone,
		"snap_turn_cooldown": movement_component.snap_turn_cooldown,
		"hand_assignment": movement_component.hand_assignment,
		"enable_two_hand_world_scale": movement_component.enable_two_hand_world_scale,
		"enable_two_hand_world_rotation": movement_component.enable_two_hand_world_rotation,
		"world_scale_min": movement_component.world_scale_min,
		"world_scale_max": movement_component.world_scale_max,
		"player_gravity_enabled": movement_component.player_gravity_enabled,
	}


func _apply_defaults(source: Dictionary):
	if locomotion_mode_btn:
		locomotion_mode_btn.selected = source.get("locomotion_mode", DEFAULTS["locomotion_mode"])
	if locomotion_speed_slider:
		locomotion_speed_slider.value = source.get("locomotion_speed", DEFAULTS["locomotion_speed"])
	if locomotion_deadzone_slider:
		locomotion_deadzone_slider.value = source.get("locomotion_deadzone", DEFAULTS["locomotion_deadzone"])
	if turn_mode_btn:
		turn_mode_btn.selected = source.get("turn_mode", DEFAULTS["turn_mode"])
	if snap_angle_slider:
		snap_angle_slider.value = source.get("snap_turn_angle", DEFAULTS["snap_turn_angle"])
	if snap_cooldown_slider:
		snap_cooldown_slider.value = source.get("snap_turn_cooldown", DEFAULTS["snap_turn_cooldown"])
	if smooth_speed_slider:
		smooth_speed_slider.value = source.get("smooth_turn_speed", DEFAULTS["smooth_turn_speed"])
	if deadzone_slider:
		deadzone_slider.value = source.get("turn_deadzone", DEFAULTS["turn_deadzone"])
	if hand_swap_check:
		hand_swap_check.button_pressed = source.get("hand_assignment", DEFAULTS["hand_assignment"]) == PlayerMovementComponent.HandAssignment.SWAPPED
	if world_scale_check:
		world_scale_check.button_pressed = source.get("enable_two_hand_world_scale", DEFAULTS["enable_two_hand_world_scale"])
	if world_rotation_check:
		world_rotation_check.button_pressed = source.get("enable_two_hand_world_rotation", DEFAULTS["enable_two_hand_world_rotation"])
	if world_scale_min_slider:
		world_scale_min_slider.value = source.get("world_scale_min", DEFAULTS["world_scale_min"])
	if world_scale_max_slider:
		world_scale_max_slider.value = source.get("world_scale_max", DEFAULTS["world_scale_max"])
	if world_scale_sensitivity_slider:
		world_scale_sensitivity_slider.value = source.get("world_scale_sensitivity", DEFAULTS["world_scale_sensitivity"])
	if world_rotation_sensitivity_slider:
		world_rotation_sensitivity_slider.value = source.get("world_rotation_sensitivity", DEFAULTS["world_rotation_sensitivity"])
	if one_hand_world_grab_check:
		one_hand_world_grab_check.button_pressed = source.get("enable_one_hand_world_grab", DEFAULTS["enable_one_hand_world_grab"])
	if one_hand_world_move_sense_slider:
		one_hand_world_move_sense_slider.value = source.get("one_hand_world_move_sensitivity", DEFAULTS["one_hand_world_move_sensitivity"])
	if jump_enabled_check:
		jump_enabled_check.button_pressed = source.get("jump_enabled", DEFAULTS["jump_enabled"])
	if jump_impulse_slider:
		jump_impulse_slider.value = source.get("jump_impulse", DEFAULTS["jump_impulse"])
	if jump_cooldown_slider:
		jump_cooldown_slider.value = source.get("jump_cooldown", DEFAULTS["jump_cooldown"])
	if gravity_check:
		gravity_check.button_pressed = source.get("player_gravity_enabled", DEFAULTS["player_gravity_enabled"])


func _update_turn_mode_ui():
	if not turn_mode_btn:
		return
	var turn_mode = turn_mode_btn.selected
	if snap_container:
		snap_container.visible = turn_mode == PlayerMovementComponent.TurnMode.SNAP
	if smooth_container:
		smooth_container.visible = turn_mode == PlayerMovementComponent.TurnMode.SMOOTH


func _update_locomotion_controls_enabled():
	if not locomotion_mode_btn:
		return
	var enabled = locomotion_mode_btn.selected != PlayerMovementComponent.LocomotionMode.DISABLED
	if locomotion_speed_slider:
		locomotion_speed_slider.editable = enabled
	if locomotion_deadzone_slider:
		locomotion_deadzone_slider.editable = enabled
	if locomotion_speed_label:
		locomotion_speed_label.modulate = Color.WHITE if enabled else Color(0.6, 0.6, 0.6)
	if locomotion_deadzone_label:
		locomotion_deadzone_label.modulate = Color.WHITE if enabled else Color(0.6, 0.6, 0.6)


func _update_status_label():
	if not status_label:
		return
	if movement_component:
		status_label.text = "Player linked — live updates"
		status_label.add_theme_color_override("font_color", COLOR_ACCENT)
	else:
		status_label.text = "Waiting for player..."
		status_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.4))


func _create_card(parent: VBoxContainer, title: String, subtitle: String = "", icon: String = "") -> VBoxContainer:
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_CARD_BG
	style.border_color = COLOR_CARD_BORDER
	style.border_width_bottom = 1
	style.border_width_top = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	
	var header = Label.new()
	header.text = ("%s " % icon if icon != "" else "") + title
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", COLOR_TITLE)
	vbox.add_child(header)
	
	if subtitle != "":
		var sub = _make_hint(subtitle)
		vbox.add_child(sub)
	
	parent.add_child(panel)
	return vbox


class SliderBlock:
	var label: Label
	var slider: HSlider


func _add_slider_block(parent: VBoxContainer, title: String, tooltip: String, min_value: float, max_value: float, step: float, initial_value: float, formatter: Callable) -> SliderBlock:
	var block = SliderBlock.new()
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	parent.add_child(container)
	
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var label = Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", COLOR_SUBTITLE)
	header.add_child(label)
	
	var value_label = Label.new()
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.custom_minimum_size = Vector2(90, 0)
	value_label.add_theme_font_size_override("font_size", 12)
	header.add_child(value_label)
	container.add_child(header)
	
	var slider = HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.tick_count = int((max_value - min_value) / step)
	slider.ticks_on_borders = true
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = tooltip
	slider.value = initial_value
	container.add_child(slider)
	
	var format_value = func(value):
		return formatter.call(value)
	value_label.text = title + ":" + format_value.call(initial_value)
	slider.value_changed.connect(func(value: float):
		value_label.text = title + ":" + format_value.call(value)
	)
	
	block.label = value_label
	block.slider = slider
	return block


func _make_hint(text: String) -> Label:
	var hint = Label.new()
	hint.text = text
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", COLOR_SUBTITLE)
	return hint