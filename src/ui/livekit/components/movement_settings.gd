extends PanelContainer
class_name MovementSettingsPanel
## Movement Settings Panel - Locomotion, turning, and hand swap controls

signal settings_changed()

const InputBindingManager = preload("res://src/systems/input_binding_manager.gd")

# Visual palette
const COLOR_TITLE := Color(0.88, 0.93, 1.0)
const COLOR_SUBTITLE := Color(0.7, 0.78, 0.9)
const COLOR_ACCENT := Color(0.42, 0.75, 1.0)
const COLOR_CARD_BG := Color(0.16, 0.17, 0.21)
const COLOR_CARD_BORDER := Color(0.24, 0.29, 0.36)

# Defaults snapshot (updated once a player component is found)
# Defaults snapshot (updated once a player component is found)
const DEFAULTS := {
	"locomotion_mode": PlayerMovementComponent.LocomotionMode.HEAD_DIRECTION_3D,
	"locomotion_speed": 5.0,
	"locomotion_deadzone": 0.2,
	"invert_locomotion_x": false,
	"invert_locomotion_y": false,
	"turn_mode": PlayerMovementComponent.TurnMode.SNAP,
	"snap_turn_angle": 45.0,
	"smooth_turn_speed": 90.0,
	"turn_deadzone": 0.5,
	"snap_turn_cooldown": 0.3,
	"invert_turn_x": false,
	"ui_scroll_wheel_factor": 20.0,
	"hand_assignment": PlayerMovementComponent.HandAssignment.DEFAULT,
	"world_scale_min": 0.1,
	"world_scale_max": 15.0,
	"world_scale_sensitivity": 0.35,
	"world_rotation_sensitivity": 0.6,
	"world_grab_move_factor": 1.0,
	"world_grab_smooth_factor": 0.15,
	"invert_one_hand_grab_direction": true,
	"one_hand_grab_mode": PlayerMovementComponent.OneHandGrabMode.RELATIVE,
	"enable_one_hand_rotation": true,
	"enable_one_hand_world_rotate": false,
	"invert_one_hand_rotation": false,
	"apply_one_hand_release_velocity": true,
	"one_hand_rotation_smooth_factor": 0.2,
	"auto_respawn_enabled": false,
	"auto_respawn_distance": 120.0,
	"hard_respawn_resets_settings": true,
	"show_one_hand_grab_visual": true,
	"enable_one_hand_world_grab": false,
	"one_hand_world_move_sensitivity": 0.25,
	"player_gravity_enabled": false,
	"player_drag_force": 0.85,
	"enable_physics_hands": true,
	"simple_world_grab_enabled": false,
}

const INPUT_ACTIONS := []

# UI References - set up dynamically
var locomotion_mode_btn: OptionButton
var locomotion_speed_slider: HSlider
var locomotion_speed_label: Label
var locomotion_deadzone_slider: HSlider
var locomotion_deadzone_label: Label
var locomotion_invert_x_check: CheckBox
var locomotion_invert_y_check: CheckBox
var turn_mode_btn: OptionButton
var snap_angle_slider: HSlider
var snap_angle_label: Label
var smooth_speed_slider: HSlider
var smooth_speed_label: Label
var deadzone_slider: HSlider
var deadzone_label: Label
var snap_cooldown_slider: HSlider
var snap_cooldown_label: Label
var turn_invert_check: CheckBox
var hand_swap_check: CheckBox
var ui_scroll_override_check: CheckBox
var disable_joystick_grip_check: CheckBox
var ui_scroll_speed_slider: HSlider
var ui_scroll_speed_label: Label
var world_scale_check: CheckBox
var world_rotation_check: CheckBox
var gravity_check: CheckBox
var player_drag_slider: HSlider
var player_drag_label: Label
var auto_respawn_check: CheckBox
var auto_respawn_distance_slider: HSlider
var auto_respawn_distance_label: Label
var hard_respawn_check: CheckBox
var physics_hands_check: CheckBox
var world_scale_min_slider: HSlider
var world_scale_min_label: Label
var world_scale_max_slider: HSlider
var world_scale_max_label: Label
var status_label: Label
var world_scale_sensitivity_slider: HSlider
var world_scale_sensitivity_label: Label
var world_rotation_sensitivity_slider: HSlider
var world_rotation_sensitivity_label: Label
var world_grab_move_factor_slider: HSlider
var world_grab_move_factor_label: Label
var world_grab_smooth_slider: HSlider
var world_grab_smooth_label: Label
var one_hand_world_grab_check: CheckBox
var one_hand_world_move_sense_slider: HSlider
var one_hand_world_move_sense_label: Label
var one_hand_grab_mode_btn: OptionButton
var one_hand_rotation_check: CheckBox
var one_hand_rotation_smooth_slider: HSlider
var one_hand_rotation_smooth_label: Label
var one_hand_rotate_check: CheckBox
var invert_one_hand_rotation_check: CheckBox
var apply_one_hand_release_vel_check: CheckBox
var invert_one_hand_grab_check: CheckBox
var show_one_hand_grab_visual_check: CheckBox
var simple_world_grab_check: CheckBox
var input_mapper_status: Label
var profile_name_field: LineEdit
var profile_selector: OptionButton
var profile_status_label: Label

var snap_container: VBoxContainer
var smooth_container: VBoxContainer

# Input mapping UI state
var input_rows := {}
var input_listen_action := ""
var input_listen_events: Array[InputEvent] = []

# Reference to movement component
var movement_component: PlayerMovementComponent
var defaults_snapshot := DEFAULTS.duplicate(true)

# === Recent Toggle Tracking ===
# Stores recent setting changes for the Watch Menu's "Recent" tab
signal setting_toggled(setting_name: String, old_value, new_value, revert_callable: Callable)

static var recent_toggles: Array[Dictionary] = []
const MAX_RECENT_TOGGLES := 15


static func record_toggle(setting_name: String, old_val, new_val, revert_callable: Callable) -> void:
	"""Record a setting change for the Recent tab"""
	var entry := {
		"setting_name": setting_name,
		"old_value": old_val,
		"new_value": new_val,
		"timestamp": Time.get_unix_time_from_system(),
		"revert_callable": revert_callable
	}
	recent_toggles.insert(0, entry)
	if recent_toggles.size() > MAX_RECENT_TOGGLES:
		recent_toggles.resize(MAX_RECENT_TOGGLES)


static func get_recent_toggles() -> Array[Dictionary]:
	"""Get all recent toggles for display"""
	return recent_toggles


static func revert_toggle(index: int) -> void:
	"""Revert a toggle at the given index"""
	if index < 0 or index >= recent_toggles.size():
		return
	var entry: Dictionary = recent_toggles[index]
	var revert_callable: Callable = entry.get("revert_callable", Callable())
	if revert_callable.is_valid():
		revert_callable.call()
	recent_toggles.remove_at(index)


static func clear_recent_toggles() -> void:
	"""Clear all recent toggles"""
	recent_toggles.clear()


func _ready():
	# Stretch to viewport to avoid clipping; rely on scroll for overflow
	_apply_fullrect_layout()
	_find_movement_component()
	_build_ui()
	_refresh_profiles()
	# Auto-load saved settings on startup (Meta VRCS requirement: preserve user data)
	_auto_load_saved_settings()
	# Connect to settings_changed to trigger auto-save
	settings_changed.connect(_queue_auto_save)


func _apply_fullrect_layout():
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


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
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(margin)

	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	# Main container
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
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

	# Profiles
	var profile_card = _create_card(main_vbox, "Profiles", "Save and load movement presets", "💾")
	var profile_row = HBoxContainer.new()
	profile_row.add_theme_constant_override("separation", 8)
	profile_card.add_child(profile_row)

	profile_name_field = LineEdit.new()
	profile_name_field.placeholder_text = "Profile name"
	profile_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_row.add_child(profile_name_field)

	var save_profile_btn = Button.new()
	save_profile_btn.text = "Save"
	save_profile_btn.focus_mode = Control.FOCUS_NONE
	save_profile_btn.pressed.connect(_on_save_profile_pressed)
	profile_row.add_child(save_profile_btn)

	var load_row = HBoxContainer.new()
	load_row.add_theme_constant_override("separation", 8)
	profile_card.add_child(load_row)

	profile_selector = OptionButton.new()
	profile_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_row.add_child(profile_selector)

	var load_profile_btn = Button.new()
	load_profile_btn.text = "Load"
	load_profile_btn.focus_mode = Control.FOCUS_NONE
	load_profile_btn.pressed.connect(_on_load_profile_pressed)
	load_row.add_child(load_profile_btn)

	var refresh_profile_btn = Button.new()
	refresh_profile_btn.text = "Refresh"
	refresh_profile_btn.focus_mode = Control.FOCUS_NONE
	refresh_profile_btn.pressed.connect(_refresh_profiles)
	load_row.add_child(refresh_profile_btn)

	profile_status_label = _make_hint("Profiles not loaded yet")
	profile_card.add_child(profile_status_label)
	
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
		func(value): return " %.2f" % value
	)
	locomotion_deadzone_label = loco_deadzone_block.label
	locomotion_deadzone_slider = loco_deadzone_block.slider
	locomotion_deadzone_slider.value_changed.connect(func(value: float): _on_locomotion_deadzone_changed(value))
	
	# Locomotion Axis Inversion
	var loco_invert_row = _create_row(locomotion_card, "Invert Axes")
	locomotion_invert_x_check = CheckBox.new()
	locomotion_invert_x_check.text = "Horizontal"
	locomotion_invert_x_check.tooltip_text = "Flip left/right on the movement stick."
	locomotion_invert_x_check.focus_mode = Control.FOCUS_NONE
	if movement_component:
		locomotion_invert_x_check.button_pressed = movement_component.invert_locomotion_x
	else:
		locomotion_invert_x_check.button_pressed = defaults_snapshot["invert_locomotion_x"]
	locomotion_invert_x_check.toggled.connect(func(pressed: bool): _on_locomotion_invert_x_toggled(pressed))
	loco_invert_row.add_child(locomotion_invert_x_check)
	
	locomotion_invert_y_check = CheckBox.new()
	locomotion_invert_y_check.text = "Vertical"
	locomotion_invert_y_check.tooltip_text = "Flip forward/back on the movement stick."
	locomotion_invert_y_check.focus_mode = Control.FOCUS_NONE
	if movement_component:
		locomotion_invert_y_check.button_pressed = movement_component.invert_locomotion_y
	else:
		locomotion_invert_y_check.button_pressed = defaults_snapshot["invert_locomotion_y"]
	locomotion_invert_y_check.toggled.connect(func(pressed: bool): _on_locomotion_invert_y_toggled(pressed))
	loco_invert_row.add_child(locomotion_invert_y_check)
	
	# === Turning Section ===
	var turning_card = _create_card(main_vbox, "Turning", "Snap or smooth turning with sensitivity controls", "🌀")
	
	# Turn Mode
	var turn_row = _create_row(turning_card, "Turn Mode")
	turn_mode_btn = OptionButton.new()
	turn_mode_btn.add_item("Snap")
	turn_mode_btn.add_item("Smooth")
	turn_mode_btn.add_item("Disabled")
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
		func(value): return " %.2f" % value
	)
	deadzone_label = deadzone_block.label
	deadzone_slider = deadzone_block.slider
	deadzone_slider.value_changed.connect(func(value: float): _on_deadzone_changed(value))
	
	# Turn Axis Inversion
	var turn_invert_row = _create_row(turning_card, "Invert Turn")
	turn_invert_check = CheckBox.new()
	turn_invert_check.text = "Horizontal"
	turn_invert_check.tooltip_text = "Flip left/right turn input."
	turn_invert_check.focus_mode = Control.FOCUS_NONE
	if movement_component:
		turn_invert_check.button_pressed = movement_component.invert_turn_x
	else:
		turn_invert_check.button_pressed = defaults_snapshot["invert_turn_x"]
	turn_invert_check.toggled.connect(func(pressed: bool): _on_turn_invert_toggled(pressed))
	turn_invert_row.add_child(turn_invert_check)
	
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

	var ui_scroll_row = _create_row(controls_card, "UI Scroll")
	ui_scroll_override_check = CheckBox.new()
	ui_scroll_override_check.text = "Use stick to scroll when pointing at UI"
	ui_scroll_override_check.add_theme_font_size_override("font_size", 12)
	ui_scroll_override_check.tooltip_text = "Temporarily repurpose the pointing hand's stick for UI scrolling and pause locomotion/turn."
	if movement_component:
		ui_scroll_override_check.button_pressed = movement_component.ui_scroll_steals_stick
	else:
		ui_scroll_override_check.button_pressed = defaults_snapshot["ui_scroll_steals_stick"]
	ui_scroll_override_check.toggled.connect(func(pressed: bool): _on_ui_scroll_override_toggled(pressed))
	ui_scroll_row.add_child(ui_scroll_override_check)

	var initial_scroll_speed = movement_component.ui_scroll_wheel_factor if movement_component else defaults_snapshot["ui_scroll_wheel_factor"]
	var scroll_speed_block = _add_slider_block(
		controls_card,
		"Scroll Speed",
		"Multiplier for scroll wheel emulation.",
		10.0,
		720.0,
		10.0,
		initial_scroll_speed,
		func(value): return " %.0f" % value
	)
	ui_scroll_speed_label = scroll_speed_block.label
	ui_scroll_speed_slider = scroll_speed_block.slider
	ui_scroll_speed_slider.value_changed.connect(func(value: float): _on_ui_scroll_speed_changed(value))

	var grip_joystick_row = _create_row(controls_card, "Grip Behavior")
	disable_joystick_grip_check = CheckBox.new()
	disable_joystick_grip_check.text = "Disable Joystick While Gripping"
	disable_joystick_grip_check.add_theme_font_size_override("font_size", 12)
	disable_joystick_grip_check.tooltip_text = "When enabled, joystick locomotion is disabled while either grip button is held. Useful when using grip for world manipulation."
	if movement_component:
		disable_joystick_grip_check.button_pressed = movement_component.disable_joystick_on_grip
	else:
		disable_joystick_grip_check.button_pressed = defaults_snapshot["disable_joystick_on_grip"]
	disable_joystick_grip_check.toggled.connect(func(pressed: bool): _on_disable_joystick_grip_toggled(pressed))
	grip_joystick_row.add_child(disable_joystick_grip_check)

	# === World Manipulation ===
	var world_card = _create_card(main_vbox, "World Manipulation", "Gestures for scaling and moving the world environment.", "🌍")

	var initial_grab_move = movement_component.world_grab_move_factor if movement_component else defaults_snapshot["world_grab_move_factor"]
	var grab_move_block = _add_slider_block(
		world_card,
		"World Grab Move Factor",
		"How much the world moves relative to your hand motion.",
		0.05,
		3.0,
		0.05,
		initial_grab_move,
		func(value): return " x%.2f" % value
	)
	world_grab_move_factor_label = grab_move_block.label
	world_grab_move_factor_slider = grab_move_block.slider
	world_grab_move_factor_slider.value_changed.connect(func(value: float): _on_world_grab_move_factor_changed(value))

	var initial_grab_smooth = movement_component.world_grab_smooth_factor if movement_component else defaults_snapshot["world_grab_smooth_factor"]
	var grab_smooth_block = _add_slider_block(
		world_card,
		"Grab Smooth Factor",
		"Damp grab move/scale/rotation jitter (0.05–1.0).",
		0.05,
		1.0,
		0.05,
		initial_grab_smooth,
		func(value): return " x%.2f" % value
	)
	world_grab_smooth_label = grab_smooth_block.label
	world_grab_smooth_slider = grab_smooth_block.slider
	world_grab_smooth_slider.value_changed.connect(func(value: float): _on_world_grab_smooth_factor_changed(value))
	
	simple_world_grab_check = CheckBox.new()
	simple_world_grab_check.text = "Simple World Grab (Grip anywhere to scale)"
	simple_world_grab_check.tooltip_text = "Enable legacy two-hand scaling and movement. Works anywhere, even without specific grab points."
	simple_world_grab_check.button_pressed = _get_simple_world_grab_enabled()
	simple_world_grab_check.toggled.connect(_on_simple_world_grab_toggled)
	world_card.add_child(simple_world_grab_check)
	
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

	invert_one_hand_grab_check = CheckBox.new()
	invert_one_hand_grab_check.text = "Invert One-Hand Grab Direction"
	invert_one_hand_grab_check.add_theme_font_size_override("font_size", 12)
	if movement_component:
		invert_one_hand_grab_check.button_pressed = movement_component.invert_one_hand_grab_direction
	else:
		invert_one_hand_grab_check.button_pressed = defaults_snapshot["invert_one_hand_grab_direction"]
	invert_one_hand_grab_check.tooltip_text = "Reverse the motion when dragging with one hand."
	invert_one_hand_grab_check.toggled.connect(func(pressed: bool): _on_invert_one_hand_grab_toggled(pressed))
	world_card.add_child(invert_one_hand_grab_check)

	show_one_hand_grab_visual_check = CheckBox.new()
	show_one_hand_grab_visual_check.text = "Show One-Hand Grab Anchor"
	show_one_hand_grab_visual_check.add_theme_font_size_override("font_size", 12)
	if movement_component:
		show_one_hand_grab_visual_check.button_pressed = movement_component.show_one_hand_grab_visual
	else:
		show_one_hand_grab_visual_check.button_pressed = defaults_snapshot["show_one_hand_grab_visual"]
	show_one_hand_grab_visual_check.tooltip_text = "Display an anchor marker where the grab started."
	show_one_hand_grab_visual_check.toggled.connect(func(pressed: bool): _on_show_one_hand_grab_visual_toggled(pressed))
	world_card.add_child(show_one_hand_grab_visual_check)
	
	var initial_world_min = movement_component.world_scale_min if movement_component else defaults_snapshot["world_scale_min"]
	var world_min_block = _add_slider_block(
		world_card,
		"World Scale Min",
		"Lower bound for world scaling.",
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
		"Upper bound for world scaling.",
		0.5,
		1000.0,
		0.5,
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
		0.0,
		2.0,
		0.05,
		initial_one_hand_sense,
		func(value): return " x%.2f" % value
	)
	one_hand_world_move_sense_label = one_hand_sense_block.label
	one_hand_world_move_sense_slider = one_hand_sense_block.slider
	one_hand_world_move_sense_slider.value_changed.connect(func(value: float): _on_one_hand_world_move_sensitivity_changed(value))

	var one_hand_mode_row = _create_row(world_card, "One-Hand Grab Mode")
	one_hand_grab_mode_btn = OptionButton.new()
	one_hand_grab_mode_btn.add_item("Relative")
	one_hand_grab_mode_btn.add_item("Anchored")
	one_hand_grab_mode_btn.selected = (movement_component.one_hand_grab_mode if movement_component else defaults_snapshot["one_hand_grab_mode"])
	one_hand_grab_mode_btn.item_selected.connect(func(idx: int): _on_one_hand_grab_mode_changed(idx))
	one_hand_mode_row.add_child(one_hand_grab_mode_btn)

	one_hand_rotate_check = CheckBox.new()
	one_hand_rotate_check.text = "One-Hand Rotate Enabled"
	one_hand_rotate_check.add_theme_font_size_override("font_size", 12)
	if movement_component:
		one_hand_rotate_check.button_pressed = movement_component.enable_one_hand_world_rotate
	else:
		one_hand_rotate_check.button_pressed = defaults_snapshot["enable_one_hand_world_rotate"]
	one_hand_rotate_check.toggled.connect(func(pressed: bool): _on_one_hand_world_rotate_toggled(pressed))
	world_card.add_child(one_hand_rotate_check)

	one_hand_rotation_check = CheckBox.new()
	one_hand_rotation_check.text = "Enable One-Hand Rotation"
	one_hand_rotation_check.add_theme_font_size_override("font_size", 12)
	if movement_component:
		one_hand_rotation_check.button_pressed = movement_component.enable_one_hand_rotation
	else:
		one_hand_rotation_check.button_pressed = defaults_snapshot["enable_one_hand_rotation"]
	one_hand_rotation_check.toggled.connect(func(pressed: bool): _on_one_hand_rotation_toggled(pressed))
	world_card.add_child(one_hand_rotation_check)

	apply_one_hand_release_vel_check = CheckBox.new()
	apply_one_hand_release_vel_check.text = "Keep Velocity On Release"
	apply_one_hand_release_vel_check.add_theme_font_size_override("font_size", 12)
	if movement_component:
		apply_one_hand_release_vel_check.button_pressed = movement_component.apply_one_hand_release_velocity
	else:
		apply_one_hand_release_vel_check.button_pressed = defaults_snapshot["apply_one_hand_release_velocity"]
	apply_one_hand_release_vel_check.toggled.connect(func(pressed: bool): _on_apply_one_hand_release_vel_toggled(pressed))
	world_card.add_child(apply_one_hand_release_vel_check)

	invert_one_hand_rotation_check = CheckBox.new()
	invert_one_hand_rotation_check.text = "Invert One-Hand Rotation"
	invert_one_hand_rotation_check.add_theme_font_size_override("font_size", 12)
	if movement_component:
		invert_one_hand_rotation_check.button_pressed = movement_component.invert_one_hand_rotation
	else:
		invert_one_hand_rotation_check.button_pressed = defaults_snapshot["invert_one_hand_rotation"]
	invert_one_hand_rotation_check.toggled.connect(func(pressed: bool): _on_invert_one_hand_rotation_toggled(pressed))
	world_card.add_child(invert_one_hand_rotation_check)

	var one_hand_rot_smooth_block = _add_slider_block(
		world_card,
		"One-Hand Rotation Smooth",
		"Damping for one-hand rotation toward target.",
		0.01,
		1.0,
		0.01,
		movement_component.one_hand_rotation_smooth_factor if movement_component else defaults_snapshot["one_hand_rotation_smooth_factor"],
		func(value): return " x%.2f" % value
	)
	one_hand_rotation_smooth_label = one_hand_rot_smooth_block.label
	one_hand_rotation_smooth_slider = one_hand_rot_smooth_block.slider
	one_hand_rotation_smooth_slider.value_changed.connect(func(value: float): _on_one_hand_rotation_smooth_changed(value))

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

	physics_hands_check = CheckBox.new()
	physics_hands_check.text = "Enable Physics Hands"
	physics_hands_check.add_theme_font_size_override("font_size", 12)
	physics_hands_check.tooltip_text = "Enable physical hand interactions with the world."
	if movement_component:
		physics_hands_check.button_pressed = movement_component.enable_physics_hands
	else:
		physics_hands_check.button_pressed = defaults_snapshot["enable_physics_hands"]
	physics_hands_check.toggled.connect(func(pressed: bool): _on_physics_hands_toggled(pressed))
	player_card.add_child(physics_hands_check)

	auto_respawn_check = CheckBox.new()
	auto_respawn_check.text = "Auto Respawn if Far"
	auto_respawn_check.add_theme_font_size_override("font_size", 12)
	if movement_component:
		auto_respawn_check.button_pressed = movement_component.auto_respawn_enabled
	else:
		auto_respawn_check.button_pressed = defaults_snapshot["auto_respawn_enabled"]
	auto_respawn_check.toggled.connect(func(pressed: bool): _on_auto_respawn_toggled(pressed))
	player_card.add_child(auto_respawn_check)

	var auto_respawn_block = _add_slider_block(
		player_card,
		"Respawn Distance",
		"Auto-respawn if farther than this distance from spawn.",
		5.0,
		400.0,
		1.0,
		movement_component.auto_respawn_distance if movement_component else defaults_snapshot["auto_respawn_distance"],
		func(value): return " %.0f m" % value
	)
	auto_respawn_distance_label = auto_respawn_block.label
	auto_respawn_distance_slider = auto_respawn_block.slider
	auto_respawn_distance_slider.value_changed.connect(func(value: float): _on_auto_respawn_distance_changed(value))

	hard_respawn_check = CheckBox.new()
	hard_respawn_check.text = "Hard Respawn (reset settings, zero velocity)"
	hard_respawn_check.add_theme_font_size_override("font_size", 12)
	if movement_component:
		hard_respawn_check.button_pressed = movement_component.hard_respawn_resets_settings
	else:
		hard_respawn_check.button_pressed = defaults_snapshot["hard_respawn_resets_settings"]
	hard_respawn_check.toggled.connect(func(pressed: bool): _on_hard_respawn_toggled(pressed))
	player_card.add_child(hard_respawn_check)

	var respawn_btn = Button.new()
	
	# === Input Mapper ===
	_build_input_mapper(main_vbox)
	
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
		var old_mode = movement_component.locomotion_mode
		movement_component.locomotion_mode = index as PlayerMovementComponent.LocomotionMode
		var names := [
			"Disabled",
			"Head Direction",
			"Hand Direction",
			"Head Direction (3D)",
			"Hand Direction (3D)",
		]
		print("MovementSettings: Locomotion mode -> ", names[index] if index < names.size() else index)
		MovementSettingsPanel.record_toggle(
			"Locomotion Mode",
			names[old_mode] if old_mode < names.size() else str(old_mode),
			names[index] if index < names.size() else str(index),
			func(): _on_locomotion_mode_changed(old_mode)
		)
	settings_changed.emit()


func _on_locomotion_speed_changed(value: float):
	if movement_component:
		var old_val = movement_component.locomotion_speed
		movement_component.locomotion_speed = value
		MovementSettingsPanel.record_toggle(
			"Locomotion Speed",
			"%.1f m/s" % old_val,
			"%.1f m/s" % value,
			func(): _on_locomotion_speed_changed(old_val)
		)
	locomotion_speed_label.text = "Speed: %.1f m/s" % value
	settings_changed.emit()


func _on_locomotion_deadzone_changed(value: float):
	if movement_component:
		var old_val = movement_component.locomotion_deadzone
		movement_component.locomotion_deadzone = value
		MovementSettingsPanel.record_toggle(
			"Locomotion Deadzone",
			"%.2f" % old_val,
			"%.2f" % value,
			func(): _on_locomotion_deadzone_changed(old_val)
		)
	locomotion_deadzone_label.text = "Locomotion Deadzone: %.2f" % value
	settings_changed.emit()


func _on_locomotion_invert_x_toggled(pressed: bool):
	if movement_component:
		var old_val = movement_component.invert_locomotion_x
		movement_component.invert_locomotion_x = pressed
		MovementSettingsPanel.record_toggle(
			"Invert Locomotion X",
			"ON" if old_val else "OFF",
			"ON" if pressed else "OFF",
			func(): _on_locomotion_invert_x_toggled(old_val)
		)
	settings_changed.emit()


func _on_locomotion_invert_y_toggled(pressed: bool):
	if movement_component:
		var old_val = movement_component.invert_locomotion_y
		movement_component.invert_locomotion_y = pressed
		MovementSettingsPanel.record_toggle(
			"Invert Locomotion Y",
			"ON" if old_val else "OFF",
			"ON" if pressed else "OFF",
			func(): _on_locomotion_invert_y_toggled(old_val)
		)
	settings_changed.emit()


func _on_turn_mode_changed(index: int):
	if movement_component:
		var old_mode = movement_component.turn_mode
		movement_component.turn_mode = index as PlayerMovementComponent.TurnMode
		var names := ["Snap", "Smooth", "Disabled"]
		MovementSettingsPanel.record_toggle(
			"Turn Mode",
			names[old_mode] if old_mode < names.size() else str(old_mode),
			names[index] if index < names.size() else str(index),
			func(): _on_turn_mode_changed(old_mode)
		)
	settings_changed.emit()


func _on_snap_angle_changed(value: float):
	if movement_component:
		var old_val = movement_component.snap_turn_angle
		movement_component.snap_turn_angle = value
		MovementSettingsPanel.record_toggle(
			"Snap Angle",
			"%.0f°" % old_val,
			"%.0f°" % value,
			func(): _on_snap_angle_changed(old_val)
		)
	snap_angle_label.text = "Snap Angle: %.0f°" % value
	settings_changed.emit()


func _on_snap_cooldown_changed(value: float):
	if movement_component:
		var old_val = movement_component.snap_turn_cooldown
		movement_component.snap_turn_cooldown = value
		MovementSettingsPanel.record_toggle(
			"Snap Cooldown",
			"%.2fs" % old_val,
			"%.2fs" % value,
			func(): _on_snap_cooldown_changed(old_val)
		)
	snap_cooldown_label.text = "Snap Cooldown: %.2fs" % value
	settings_changed.emit()


func _on_smooth_speed_changed(value: float):
	if movement_component:
		var old_val = movement_component.smooth_turn_speed
		movement_component.smooth_turn_speed = value
		MovementSettingsPanel.record_toggle(
			"Smooth Speed",
			"%.0f°/s" % old_val,
			"%.0f°/s" % value,
			func(): _on_smooth_speed_changed(old_val)
		)
	smooth_speed_label.text = "Smooth Speed: %.0f°/s" % value
	settings_changed.emit()


func _on_deadzone_changed(value: float):
	if movement_component:
		var old_val = movement_component.turn_deadzone
		movement_component.turn_deadzone = value
		MovementSettingsPanel.record_toggle(
			"Turn Deadzone",
			"%.2f" % old_val,
			"%.2f" % value,
			func(): _on_deadzone_changed(old_val)
		)
	deadzone_label.text = "Deadzone: %.2f" % value
	settings_changed.emit()


func _on_turn_invert_toggled(pressed: bool):
	if movement_component:
		var old_val = movement_component.invert_turn_x
		movement_component.invert_turn_x = pressed
		MovementSettingsPanel.record_toggle(
			"Invert Turn",
			"ON" if old_val else "OFF",
			"ON" if pressed else "OFF",
			func(): _on_turn_invert_toggled(old_val)
		)
	settings_changed.emit()


func _on_hand_swap_toggled(pressed: bool):
	if movement_component:
		var old_val = movement_component.hand_assignment == PlayerMovementComponent.HandAssignment.SWAPPED
		if pressed:
			movement_component.hand_assignment = PlayerMovementComponent.HandAssignment.SWAPPED
		else:
			movement_component.hand_assignment = PlayerMovementComponent.HandAssignment.DEFAULT
		print("MovementSettings: Hand swap -> ", "Swapped" if pressed else "Default")
		MovementSettingsPanel.record_toggle(
			"Swap Hands",
			"ON" if old_val else "OFF",
			"ON" if pressed else "OFF",
			func(): _on_hand_swap_toggled(old_val)
		)
	settings_changed.emit()


func _on_ui_scroll_override_toggled(pressed: bool):
	if movement_component:
		var old_val = movement_component.ui_scroll_steals_stick
		movement_component.ui_scroll_steals_stick = pressed
		MovementSettingsPanel.record_toggle(
			"UI Scroll Stick",
			"ON" if old_val else "OFF",
			"ON" if pressed else "OFF",
			func(): _on_ui_scroll_override_toggled(old_val)
		)
	settings_changed.emit()


func _on_disable_joystick_grip_toggled(pressed: bool):
	if movement_component:
		var old_val = movement_component.disable_joystick_on_grip
		movement_component.disable_joystick_on_grip = pressed
		MovementSettingsPanel.record_toggle(
			"Disable Joystick on Grip",
			"ON" if old_val else "OFF",
			"ON" if pressed else "OFF",
			func(): _on_disable_joystick_grip_toggled(old_val)
		)
	settings_changed.emit()


func _on_ui_scroll_speed_changed(value: float):
	if movement_component:
		var old_val = movement_component.ui_scroll_wheel_factor
		movement_component.ui_scroll_wheel_factor = value
		MovementSettingsPanel.record_toggle(
			"UI Scroll Speed",
			"%.0f" % old_val,
			"%.0f" % value,
			func(): _on_ui_scroll_speed_changed(old_val)
		)
	if ui_scroll_speed_label:
		ui_scroll_speed_label.text = " %.0f" % value
	settings_changed.emit()


func _on_world_grab_move_factor_changed(value: float):
	if movement_component:
		var old_val = movement_component.world_grab_move_factor
		movement_component.world_grab_move_factor = value
		MovementSettingsPanel.record_toggle(
			"World Grab Move Factor",
			"x%.2f" % old_val,
			"x%.2f" % value,
			func(): _on_world_grab_move_factor_changed(old_val)
		)
	world_grab_move_factor_label.text = "World Grab Move Factor: x%.2f" % value
	settings_changed.emit()


func _on_world_grab_smooth_factor_changed(value: float):
	if movement_component:
		var old_val = movement_component.world_grab_smooth_factor
		movement_component.world_grab_smooth_factor = value
		MovementSettingsPanel.record_toggle(
			"Grab Smooth Factor",
			"x%.2f" % old_val,
			"x%.2f" % value,
			func(): _on_world_grab_smooth_factor_changed(old_val)
		)
	world_grab_smooth_label.text = "Grab Smooth Factor: x%.2f" % value
	settings_changed.emit()


func _on_world_scale_min_changed(value: float):
	if world_scale_max_slider and value > world_scale_max_slider.value:
		world_scale_max_slider.value = value
	if movement_component:
		var old_val = movement_component.world_scale_min
		movement_component.world_scale_min = value
		MovementSettingsPanel.record_toggle(
			"World Scale Min",
			"%.2fx" % old_val,
			"%.2fx" % value,
			func(): _on_world_scale_min_changed(old_val)
		)
	world_scale_min_label.text = "World Scale Min: %.2fx" % value
	settings_changed.emit()


func _on_world_scale_max_changed(value: float):
	if world_scale_min_slider and value < world_scale_min_slider.value:
		world_scale_min_slider.value = value
	if movement_component:
		var old_val = movement_component.world_scale_max
		movement_component.world_scale_max = value
		MovementSettingsPanel.record_toggle(
			"World Scale Max",
			"%.2fx" % old_val,
			"%.2fx" % value,
			func(): _on_world_scale_max_changed(old_val)
		)
	world_scale_max_label.text = "World Scale Max: %.2fx" % value
	settings_changed.emit()


func _on_world_scale_sensitivity_changed(value: float):
	if movement_component:
		var old_val = movement_component.world_scale_sensitivity
		movement_component.world_scale_sensitivity = value
		MovementSettingsPanel.record_toggle(
			"Scale Sensitivity",
			"x%.2f" % old_val,
			"x%.2f" % value,
			func(): _on_world_scale_sensitivity_changed(old_val)
		)
	world_scale_sensitivity_label.text = "Scale Sensitivity: x%.2f" % value
	settings_changed.emit()


func _on_world_rotation_sensitivity_changed(value: float):
	if movement_component:
		var old_val = movement_component.world_rotation_sensitivity
		movement_component.world_rotation_sensitivity = value
		MovementSettingsPanel.record_toggle(
			"Rotation Sensitivity",
			"x%.2f" % old_val,
			"x%.2f" % value,
			func(): _on_world_rotation_sensitivity_changed(old_val)
		)
	world_rotation_sensitivity_label.text = "Rotation Sensitivity: x%.2f" % value
	settings_changed.emit()


func _on_one_hand_world_grab_toggled(pressed: bool):
	if movement_component:
		var old_val = movement_component.enable_one_hand_world_grab
		movement_component.enable_one_hand_world_grab = pressed
		MovementSettingsPanel.record_toggle(
			"One-Hand Grab",
			"ON" if old_val else "OFF",
			"ON" if pressed else "OFF",
			func(): _on_one_hand_world_grab_toggled(old_val)
		)
	settings_changed.emit()


func _on_invert_one_hand_grab_toggled(pressed: bool):
	if movement_component:
		var old_val = movement_component.invert_one_hand_grab_direction
		movement_component.invert_one_hand_grab_direction = pressed
		MovementSettingsPanel.record_toggle(
			"Invert One-Hand Grab",
			"ON" if old_val else "OFF",
			"ON" if pressed else "OFF",
			func(): _on_invert_one_hand_grab_toggled(old_val)
		)
	settings_changed.emit()


func _on_show_one_hand_grab_visual_toggled(pressed: bool):
	if movement_component:
		var old_val = movement_component.show_one_hand_grab_visual
		movement_component.show_one_hand_grab_visual = pressed
		movement_component._ensure_visuals()
		MovementSettingsPanel.record_toggle(
			"One-Hand Grab Visual",
			"ON" if old_val else "OFF",
			"ON" if pressed else "OFF",
			func(): _on_show_one_hand_grab_visual_toggled(old_val)
		)
	settings_changed.emit()


func _on_one_hand_world_move_sensitivity_changed(value: float):
	if movement_component:
		var old_val = movement_component.one_hand_world_move_sensitivity
		movement_component.one_hand_world_move_sensitivity = value
		MovementSettingsPanel.record_toggle(
			"One-Hand Move Sensitivity",
			"x%.2f" % old_val,
			"x%.2f" % value,
			func(): _on_one_hand_world_move_sensitivity_changed(old_val)
		)
	one_hand_world_move_sense_label.text = "One-Hand Move Sensitivity: x%.2f" % value
	settings_changed.emit()


func _on_one_hand_grab_mode_changed(idx: int):
	if movement_component:
		var old_val = movement_component.one_hand_grab_mode
		movement_component.one_hand_grab_mode = idx as PlayerMovementComponent.OneHandGrabMode
		var names := ["Relative", "Anchored"]
		MovementSettingsPanel.record_toggle(
			"One-Hand Grab Mode",
			names[old_val] if old_val < names.size() else str(old_val),
			names[idx] if idx < names.size() else str(idx),
			func(): _on_one_hand_grab_mode_changed(old_val)
		)
	settings_changed.emit()


func _on_one_hand_rotation_toggled(pressed: bool):
	if movement_component:
		var old_val = movement_component.enable_one_hand_rotation
		movement_component.enable_one_hand_rotation = pressed
		MovementSettingsPanel.record_toggle(
			"One-Hand Rotation",
			"ON" if old_val else "OFF",
			"ON" if pressed else "OFF",
			func(): _on_one_hand_rotation_toggled(old_val)
		)
	settings_changed.emit()


func _on_one_hand_rotation_smooth_changed(value: float):
	if movement_component:
		var old_val = movement_component.one_hand_rotation_smooth_factor
		movement_component.one_hand_rotation_smooth_factor = value
		MovementSettingsPanel.record_toggle(
			"One-Hand Rotation Smooth",
			"x%.2f" % old_val,
			"x%.2f" % value,
			func(): _on_one_hand_rotation_smooth_changed(old_val)
		)
	one_hand_rotation_smooth_label.text = "One-Hand Rotation Smooth: x%.2f" % value
	settings_changed.emit()


func _on_one_hand_world_rotate_toggled(pressed: bool):
	if movement_component:
		var old_val = movement_component.enable_one_hand_world_rotate
		movement_component.enable_one_hand_world_rotate = pressed
		MovementSettingsPanel.record_toggle(
			"One-Hand World Rotate",
			"ON" if old_val else "OFF",
			"ON" if pressed else "OFF",
			func(): _on_one_hand_world_rotate_toggled(old_val)
		)
	settings_changed.emit()


func _on_invert_one_hand_rotation_toggled(pressed: bool):
	if movement_component:
		var old_val = movement_component.invert_one_hand_rotation
		movement_component.invert_one_hand_rotation = pressed
		MovementSettingsPanel.record_toggle(
			"Invert One-Hand Rotation",
			"ON" if old_val else "OFF",
			"ON" if pressed else "OFF",
			func(): _on_invert_one_hand_rotation_toggled(old_val)
		)
	settings_changed.emit()


func _on_apply_one_hand_release_vel_toggled(pressed: bool):
	if movement_component:
		var old_val = movement_component.apply_one_hand_release_velocity
		movement_component.apply_one_hand_release_velocity = pressed
		MovementSettingsPanel.record_toggle(
			"Keep Velocity (one-hand)",
			"ON" if old_val else "OFF",
			"ON" if pressed else "OFF",
			func(): _on_apply_one_hand_release_vel_toggled(old_val)
		)
	settings_changed.emit()


func _on_physics_hands_toggled(pressed: bool):
	if movement_component:
		var old_val = movement_component.enable_physics_hands
		movement_component.enable_physics_hands = pressed
		movement_component._update_physics_hands()
		MovementSettingsPanel.record_toggle(
			"Physics Hands",
			"ON" if old_val else "OFF",
			"ON" if pressed else "OFF",
			func(): _on_physics_hands_toggled(old_val)
		)
	settings_changed.emit()


func _on_gravity_toggled(pressed: bool):
	if movement_component:
		var old_val = movement_component.player_gravity_enabled
		movement_component.set_player_gravity_enabled(pressed)
		MovementSettingsPanel.record_toggle(
			"Player Gravity",
			"ON" if old_val else "OFF",
			"ON" if pressed else "OFF",
			func(): _on_gravity_toggled(old_val)
		)
	settings_changed.emit()


# === Simple World Grab Functions ===

func _get_simple_world_grab_enabled() -> bool:
	var player = get_tree().get_first_node_in_group("xr_player")
	if player:
		var simple_grab = player.get_node_or_null("SimpleWorldGrabComponent")
		if simple_grab:
			return simple_grab.enabled
	return defaults_snapshot.get("simple_world_grab_enabled", DEFAULTS["simple_world_grab_enabled"])


func _set_simple_world_grab_enabled(pressed: bool, record_change: bool = true) -> void:
	var player = get_tree().get_first_node_in_group("xr_player")
	if player:
		var simple_grab = player.get_node_or_null("SimpleWorldGrabComponent")
		if simple_grab:
			var old_val = simple_grab.enabled
			simple_grab.enabled = pressed
			print("SimpleWorldGrab: ", "enabled" if pressed else "disabled")
			if record_change:
				MovementSettingsPanel.record_toggle(
					"Simple World Grab",
					"ON" if old_val else "OFF",
					"ON" if pressed else "OFF",
					func(): _set_simple_world_grab_enabled(old_val)
				)


func _on_simple_world_grab_toggled(pressed: bool):
	_set_simple_world_grab_enabled(pressed, true)
	settings_changed.emit()


# === Event Handlers ===


func _on_auto_respawn_toggled(pressed: bool):
	if movement_component:
		var old_val = movement_component.auto_respawn_enabled
		movement_component.auto_respawn_enabled = pressed
		MovementSettingsPanel.record_toggle(
			"Auto Respawn",
			"ON" if old_val else "OFF",
			"ON" if pressed else "OFF",
			func(): _on_auto_respawn_toggled(old_val)
		)
	settings_changed.emit()


func _on_auto_respawn_distance_changed(value: float):
	if movement_component:
		var old_val = movement_component.auto_respawn_distance
		movement_component.auto_respawn_distance = value
		MovementSettingsPanel.record_toggle(
			"Respawn Distance",
			"%.0f m" % old_val,
			"%.0f m" % value,
			func(): _on_auto_respawn_distance_changed(old_val)
		)
	auto_respawn_distance_label.text = "Respawn Distance: %.0f m" % value
	settings_changed.emit()


func _on_hard_respawn_toggled(pressed: bool):
	if movement_component:
		var old_val = movement_component.hard_respawn_resets_settings
		movement_component.hard_respawn_resets_settings = pressed
		MovementSettingsPanel.record_toggle(
			"Hard Respawn resets settings",
			"ON" if old_val else "OFF",
			"ON" if pressed else "OFF",
			func(): _on_hard_respawn_toggled(old_val)
		)
	settings_changed.emit()


func _on_respawn_now_pressed():
	if movement_component:
		movement_component.respawn(movement_component.hard_respawn_resets_settings)
		MovementSettingsPanel.record_toggle(
			"Respawn Now",
			"N/A",
			"Triggered",
			func(): pass # No undo for immediate action
		)
	settings_changed.emit()


func _on_player_drag_changed(value: float):
	if movement_component:
		var old_val = movement_component.player_drag_force
		movement_component.player_drag_force = value
		movement_component._apply_player_drag()
		MovementSettingsPanel.record_toggle(
			"Player Drag",
			"x%.2f" % old_val,
			"x%.2f" % value,
			func(): _on_player_drag_changed(old_val)
		)
	player_drag_label.text = "Player Drag: x%.2f" % value
	settings_changed.emit()


func _on_mode_changed(action: String):
	var row: InputRow = input_rows.get(action, null)
	if not row:
		return
	var manager := InputBindingManager.get_singleton()
	if not manager:
		return
	var binding: Dictionary = manager.get_binding(action)
	var old_mode: int = binding.get("mode", 0)
	var events: Array = binding.get("events", [])
	if events.is_empty():
		return
	var mode := _mode_from_selector(row.mode_btn)
	manager.set_binding(action, events, mode)
	
	var mode_names := {0: "Button", 1: "Axis (Positive)", 2: "Axis (Negative)", 3: "Axis (Absolute)"}
	MovementSettingsPanel.record_toggle(
		"Input Mode: " + action.capitalize(),
		mode_names.get(old_mode, str(old_mode)),
		mode_names.get(mode, str(mode)),
		func(): 
			row.mode_btn.selected = old_mode
			_on_mode_changed(action)
	)
	
	_refresh_input_row(action)


func _on_reset_pressed():
	# Prefer live snapshot when available, otherwise defaults
	var source = defaults_snapshot if defaults_snapshot.size() > 0 else DEFAULTS
	_apply_defaults(source)
	refresh()
	settings_changed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if input_listen_action == "":
		return
	if event.is_echo():
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_stop_listening(false)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_stop_listening(true)
			get_viewport().set_input_as_handled()
			return
	if not _is_bindable_event(event):
		return
	_capture_listen_event(event)
	get_viewport().set_input_as_handled()


func _is_bindable_event(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		return false
	if event is InputEventMagnifyGesture or event is InputEventPanGesture:
		return false
	if event is InputEventScreenDrag:
		return false
	return event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton or event is InputEventJoypadMotion


func _capture_listen_event(event: InputEvent):
	if input_listen_action == "":
		return
	if not _is_pressed_event(event):
		return
	var copy: InputEvent = event.duplicate()
	var text: String = copy.as_text()
	for ev in input_listen_events:
		if ev.as_text() == text:
			return
	input_listen_events.append(copy)
	var row: InputRow = input_rows.get(input_listen_action, null)
	if row and row.summary:
		row.summary.text = "Captured: %s" % _format_events(input_listen_events)


func _is_pressed_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed
	if event is InputEventMouseButton:
		return event.pressed
	if event is InputEventJoypadButton:
		return event.pressed
	if event is InputEventJoypadMotion:
		return abs(event.axis_value) > 0.5
	return false


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
		if locomotion_invert_x_check:
			locomotion_invert_x_check.button_pressed = movement_component.invert_locomotion_x
		if locomotion_invert_y_check:
			locomotion_invert_y_check.button_pressed = movement_component.invert_locomotion_y
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
		if turn_invert_check:
			turn_invert_check.button_pressed = movement_component.invert_turn_x
		if hand_swap_check:
			hand_swap_check.button_pressed = movement_component.hand_assignment == PlayerMovementComponent.HandAssignment.SWAPPED
		if ui_scroll_speed_slider:
			ui_scroll_speed_slider.value = movement_component.ui_scroll_wheel_factor
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
		if invert_one_hand_grab_check:
			invert_one_hand_grab_check.button_pressed = movement_component.invert_one_hand_grab_direction
		if show_one_hand_grab_visual_check:
			show_one_hand_grab_visual_check.button_pressed = movement_component.show_one_hand_grab_visual
		if one_hand_grab_mode_btn:
			one_hand_grab_mode_btn.selected = movement_component.one_hand_grab_mode
		if one_hand_rotate_check:
			one_hand_rotate_check.button_pressed = movement_component.enable_one_hand_world_rotate
		if one_hand_rotation_check:
			one_hand_rotation_check.button_pressed = movement_component.enable_one_hand_rotation
		if invert_one_hand_rotation_check:
			invert_one_hand_rotation_check.button_pressed = movement_component.invert_one_hand_rotation
		if apply_one_hand_release_vel_check:
			apply_one_hand_release_vel_check.button_pressed = movement_component.apply_one_hand_release_velocity
		if one_hand_rotation_smooth_slider:
			one_hand_rotation_smooth_slider.value = movement_component.one_hand_rotation_smooth_factor
		if world_grab_move_factor_slider:
			world_grab_move_factor_slider.value = movement_component.world_grab_move_factor
		if world_grab_smooth_slider:
			world_grab_smooth_slider.value = movement_component.world_grab_smooth_factor
		if gravity_check:
			gravity_check.button_pressed = movement_component.player_gravity_enabled
		if physics_hands_check:
			physics_hands_check.button_pressed = movement_component.enable_physics_hands
		if auto_respawn_check:
			auto_respawn_check.button_pressed = movement_component.auto_respawn_enabled
		if auto_respawn_distance_slider:
			auto_respawn_distance_slider.value = movement_component.auto_respawn_distance
		if hard_respawn_check:
			hard_respawn_check.button_pressed = movement_component.hard_respawn_resets_settings
		if player_drag_slider:
			player_drag_slider.value = movement_component.player_drag_force
		
		if simple_world_grab_check:
			simple_world_grab_check.button_pressed = _get_simple_world_grab_enabled()
	
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
		"invert_locomotion_x": movement_component.invert_locomotion_x,
		"invert_locomotion_y": movement_component.invert_locomotion_y,
		"turn_mode": movement_component.turn_mode,
		"snap_turn_angle": movement_component.snap_turn_angle,
		"smooth_turn_speed": movement_component.smooth_turn_speed,
		"turn_deadzone": movement_component.turn_deadzone,
		"snap_turn_cooldown": movement_component.snap_turn_cooldown,
		"invert_turn_x": movement_component.invert_turn_x,
		"ui_scroll_wheel_factor": movement_component.ui_scroll_wheel_factor,
		"hand_assignment": movement_component.hand_assignment,
		"world_scale_min": movement_component.world_scale_min,
		"world_scale_max": movement_component.world_scale_max,
		"player_gravity_enabled": movement_component.player_gravity_enabled,
		"world_grab_move_factor": movement_component.world_grab_move_factor,
		"world_grab_smooth_factor": movement_component.world_grab_smooth_factor,
		"invert_one_hand_grab_direction": movement_component.invert_one_hand_grab_direction,
		"show_one_hand_grab_visual": movement_component.show_one_hand_grab_visual,
		"player_drag_force": movement_component.player_drag_force,
		"auto_respawn_enabled": movement_component.auto_respawn_enabled,
		"auto_respawn_distance": movement_component.auto_respawn_distance,
		"hard_respawn_resets_settings": movement_component.hard_respawn_resets_settings,
		"enable_physics_hands": movement_component.enable_physics_hands,
	}


func _apply_defaults(source: Dictionary):
	if locomotion_mode_btn:
		locomotion_mode_btn.selected = source.get("locomotion_mode", DEFAULTS["locomotion_mode"])
	if locomotion_speed_slider:
		locomotion_speed_slider.value = source.get("locomotion_speed", DEFAULTS["locomotion_speed"])
	if locomotion_deadzone_slider:
		locomotion_deadzone_slider.value = source.get("locomotion_deadzone", DEFAULTS["locomotion_deadzone"])
	if locomotion_invert_x_check:
		locomotion_invert_x_check.button_pressed = source.get("invert_locomotion_x", DEFAULTS["invert_locomotion_x"])
	if locomotion_invert_y_check:
		locomotion_invert_y_check.button_pressed = source.get("invert_locomotion_y", DEFAULTS["invert_locomotion_y"])
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
	if turn_invert_check:
		turn_invert_check.button_pressed = source.get("invert_turn_x", DEFAULTS["invert_turn_x"])
	if hand_swap_check:
		hand_swap_check.button_pressed = source.get("hand_assignment", DEFAULTS["hand_assignment"]) == PlayerMovementComponent.HandAssignment.SWAPPED
	if ui_scroll_speed_slider:
		ui_scroll_speed_slider.value = source.get("ui_scroll_wheel_factor", DEFAULTS["ui_scroll_wheel_factor"])
	if world_scale_min_slider:
		world_scale_min_slider.value = source.get("world_scale_min", DEFAULTS["world_scale_min"])
	if world_scale_max_slider:
		world_scale_max_slider.value = source.get("world_scale_max", DEFAULTS["world_scale_max"])
	if world_scale_sensitivity_slider:
		world_scale_sensitivity_slider.value = source.get("world_scale_sensitivity", DEFAULTS["world_scale_sensitivity"])
	if world_rotation_sensitivity_slider:
		world_rotation_sensitivity_slider.value = source.get("world_rotation_sensitivity", DEFAULTS["world_rotation_sensitivity"])
	if world_grab_move_factor_slider:
		world_grab_move_factor_slider.value = source.get("world_grab_move_factor", DEFAULTS["world_grab_move_factor"])
	if world_grab_smooth_slider:
		world_grab_smooth_slider.value = source.get("world_grab_smooth_factor", DEFAULTS["world_grab_smooth_factor"])
	if one_hand_world_grab_check:
		one_hand_world_grab_check.button_pressed = source.get("enable_one_hand_world_grab", DEFAULTS["enable_one_hand_world_grab"])
	if one_hand_world_move_sense_slider:
		one_hand_world_move_sense_slider.value = source.get("one_hand_world_move_sensitivity", DEFAULTS["one_hand_world_move_sensitivity"])
	if invert_one_hand_grab_check:
		invert_one_hand_grab_check.button_pressed = source.get("invert_one_hand_grab_direction", DEFAULTS["invert_one_hand_grab_direction"])
	if one_hand_grab_mode_btn:
		one_hand_grab_mode_btn.selected = source.get("one_hand_grab_mode", DEFAULTS["one_hand_grab_mode"])
	if one_hand_rotate_check:
		one_hand_rotate_check.button_pressed = source.get("enable_one_hand_world_rotate", DEFAULTS["enable_one_hand_world_rotate"])
	if one_hand_rotation_check:
		one_hand_rotation_check.button_pressed = source.get("enable_one_hand_rotation", DEFAULTS["enable_one_hand_rotation"])
	if invert_one_hand_rotation_check:
		invert_one_hand_rotation_check.button_pressed = source.get("invert_one_hand_rotation", DEFAULTS["invert_one_hand_rotation"])
	if apply_one_hand_release_vel_check:
		apply_one_hand_release_vel_check.button_pressed = source.get("apply_one_hand_release_velocity", DEFAULTS["apply_one_hand_release_velocity"])
	if one_hand_rotation_smooth_slider:
		one_hand_rotation_smooth_slider.value = source.get("one_hand_rotation_smooth_factor", DEFAULTS["one_hand_rotation_smooth_factor"])
	if show_one_hand_grab_visual_check:
		show_one_hand_grab_visual_check.button_pressed = source.get("show_one_hand_grab_visual", DEFAULTS["show_one_hand_grab_visual"])
	if auto_respawn_check:
		auto_respawn_check.button_pressed = source.get("auto_respawn_enabled", DEFAULTS["auto_respawn_enabled"])
	if auto_respawn_distance_slider:
		auto_respawn_distance_slider.value = source.get("auto_respawn_distance", DEFAULTS["auto_respawn_distance"])
	if hard_respawn_check:
		hard_respawn_check.button_pressed = source.get("hard_respawn_resets_settings", DEFAULTS["hard_respawn_resets_settings"])
	if gravity_check:
		gravity_check.button_pressed = source.get("player_gravity_enabled", DEFAULTS["player_gravity_enabled"])
	if physics_hands_check:
		physics_hands_check.button_pressed = source.get("enable_physics_hands", DEFAULTS["enable_physics_hands"])
	if player_drag_slider:
		player_drag_slider.value = source.get("player_drag_force", DEFAULTS["player_drag_force"])


func _update_turn_mode_ui():
	if not turn_mode_btn:
		return
	var turn_mode = turn_mode_btn.selected
	var is_disabled = turn_mode == PlayerMovementComponent.TurnMode.DISABLED
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
	if locomotion_invert_x_check:
		locomotion_invert_x_check.disabled = not enabled
	if locomotion_invert_y_check:
		locomotion_invert_y_check.disabled = not enabled
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


# === Auto-Save/Load (Meta VRCS Compliance) ===
# Automatically persist settings across app restarts

var _auto_save_pending := false
var _auto_save_timer := 0.0
const AUTO_SAVE_DELAY := 1.0  # Debounce saves to avoid excessive writes


func _process(delta: float) -> void:
	# Debounced auto-save to reduce write frequency
	if _auto_save_pending:
		_auto_save_timer += delta
		if _auto_save_timer >= AUTO_SAVE_DELAY:
			_perform_auto_save()
			_auto_save_pending = false
			_auto_save_timer = 0.0


func _queue_auto_save() -> void:
	"""Queue an auto-save after a short delay (debounced)"""
	_auto_save_pending = true
	_auto_save_timer = 0.0


func _perform_auto_save() -> void:
	"""Actually save settings to SaveManager"""
	var save_manager = get_node_or_null("/root/SaveManager")
	if save_manager and save_manager.has_method("save_movement_settings"):
		var data := _collect_settings_data()
		save_manager.save_movement_settings(data)
		print("MovementSettingsPanel: Auto-saved settings")


func _auto_load_saved_settings() -> void:
	"""Load previously saved settings on startup"""
	var save_manager = get_node_or_null("/root/SaveManager")
	if not save_manager or not save_manager.has_method("get_movement_settings"):
		print("MovementSettingsPanel: SaveManager not available for auto-load")
		return
	
	if not save_manager.has_movement_settings():
		print("MovementSettingsPanel: No saved settings found, using defaults")
		return
	
	var saved_data: Dictionary = save_manager.get_movement_settings()
	if saved_data.is_empty():
		return
	
	print("MovementSettingsPanel: Loading saved settings")
	_apply_defaults(saved_data)
	settings_changed.emit()
	
	if profile_status_label:
		profile_status_label.text = "Restored saved settings"


# === Profiles ===

func _profile_path() -> String:
	return "user://movement_profiles.cfg"


func _collect_settings_data() -> Dictionary:
	return {
		"locomotion_mode": locomotion_mode_btn.selected if locomotion_mode_btn else DEFAULTS["locomotion_mode"],
		"locomotion_speed": locomotion_speed_slider.value if locomotion_speed_slider else DEFAULTS["locomotion_speed"],
		"locomotion_deadzone": locomotion_deadzone_slider.value if locomotion_deadzone_slider else DEFAULTS["locomotion_deadzone"],
		"invert_locomotion_x": locomotion_invert_x_check.button_pressed if locomotion_invert_x_check else DEFAULTS["invert_locomotion_x"],
		"invert_locomotion_y": locomotion_invert_y_check.button_pressed if locomotion_invert_y_check else DEFAULTS["invert_locomotion_y"],
		"turn_mode": turn_mode_btn.selected if turn_mode_btn else DEFAULTS["turn_mode"],
		"snap_turn_angle": snap_angle_slider.value if snap_angle_slider else DEFAULTS["snap_turn_angle"],
		"turn_deadzone": deadzone_slider.value if deadzone_slider else DEFAULTS["turn_deadzone"],
		"snap_turn_cooldown": snap_cooldown_slider.value if snap_cooldown_slider else DEFAULTS["snap_turn_cooldown"],
		"smooth_turn_speed": smooth_speed_slider.value if smooth_speed_slider else DEFAULTS["smooth_turn_speed"],
		"invert_turn_x": turn_invert_check.button_pressed if turn_invert_check else DEFAULTS["invert_turn_x"],
		"ui_scroll_wheel_factor": ui_scroll_speed_slider.value if ui_scroll_speed_slider else DEFAULTS["ui_scroll_wheel_factor"],
		"hand_assignment": PlayerMovementComponent.HandAssignment.SWAPPED if hand_swap_check and hand_swap_check.button_pressed else PlayerMovementComponent.HandAssignment.DEFAULT,
		"world_scale_min": world_scale_min_slider.value if world_scale_min_slider else DEFAULTS["world_scale_min"],
		"world_scale_max": world_scale_max_slider.value if world_scale_max_slider else DEFAULTS["world_scale_max"],
		"world_scale_sensitivity": world_scale_sensitivity_slider.value if world_scale_sensitivity_slider else DEFAULTS["world_scale_sensitivity"],
		"world_rotation_sensitivity": world_rotation_sensitivity_slider.value if world_rotation_sensitivity_slider else DEFAULTS["world_rotation_sensitivity"],
		"world_grab_move_factor": world_grab_move_factor_slider.value if world_grab_move_factor_slider else DEFAULTS["world_grab_move_factor"],
		"world_grab_smooth_factor": world_grab_smooth_slider.value if world_grab_smooth_slider else DEFAULTS["world_grab_smooth_factor"],
		"enable_one_hand_world_grab": one_hand_world_grab_check.button_pressed if one_hand_world_grab_check else DEFAULTS["enable_one_hand_world_grab"],
		"one_hand_world_move_sensitivity": one_hand_world_move_sense_slider.value if one_hand_world_move_sense_slider else DEFAULTS["one_hand_world_move_sensitivity"],
		"invert_one_hand_grab_direction": invert_one_hand_grab_check.button_pressed if invert_one_hand_grab_check else DEFAULTS["invert_one_hand_grab_direction"],
		"show_one_hand_grab_visual": show_one_hand_grab_visual_check.button_pressed if show_one_hand_grab_visual_check else DEFAULTS["show_one_hand_grab_visual"],
		"player_gravity_enabled": gravity_check.button_pressed if gravity_check else DEFAULTS["player_gravity_enabled"],
		"enable_physics_hands": physics_hands_check.button_pressed if physics_hands_check else DEFAULTS["enable_physics_hands"],
		"player_drag_force": player_drag_slider.value if player_drag_slider else DEFAULTS["player_drag_force"],
		"simple_world_grab_enabled": _get_simple_world_grab_enabled(),
	}


func _refresh_profiles():
	if not profile_selector:
		return
	profile_selector.clear()
	var cf := ConfigFile.new()
	var err = cf.load(_profile_path())
	if err != OK and err != ERR_DOES_NOT_EXIST:
		profile_status_label.text = "Profile load error: %s" % err
		return
	if err == ERR_DOES_NOT_EXIST:
		profile_status_label.text = "No profiles saved yet"
		return
	var keys := cf.get_section_keys("profiles")
	if keys.is_empty():
		profile_status_label.text = "No profiles saved yet"
		return
	keys.sort()
	for k in keys:
		profile_selector.add_item(k)
	profile_status_label.text = "Profiles loaded"


func _on_save_profile_pressed():
	if not profile_name_field:
		return
	var profile_name := profile_name_field.text.strip_edges()
	if profile_name == "":
		if profile_status_label:
			profile_status_label.text = "Enter a profile name to save"
		return
	var data := _collect_settings_data()
	var cf := ConfigFile.new()
	var err = cf.load(_profile_path())
	if err != OK and err != ERR_DOES_NOT_EXIST:
		if profile_status_label:
			profile_status_label.text = "Save failed: %s" % err
		return
	cf.set_value("profiles", profile_name, data)
	err = cf.save(_profile_path())
	if err != OK:
		if profile_status_label:
			profile_status_label.text = "Save failed: %s" % err
		return
	_refresh_profiles()
	if profile_status_label:
		profile_status_label.text = "Saved profile \"%s\"" % profile_name


func _on_load_profile_pressed():
	if not profile_selector or profile_selector.item_count == 0:
		if profile_status_label:
			profile_status_label.text = "No profiles to load"
		return
	var profile_name := profile_selector.get_item_text(profile_selector.selected)
	var cf := ConfigFile.new()
	var err = cf.load(_profile_path())
	if err != OK:
		if profile_status_label:
			profile_status_label.text = "Load failed: %s" % err
		return
	var data: Dictionary = cf.get_value("profiles", profile_name, {})
	if typeof(data) != TYPE_DICTIONARY:
		if profile_status_label:
			profile_status_label.text = "Profile \"%s\" missing data" % profile_name
		return
	_apply_defaults(data)
	if profile_status_label:
		profile_status_label.text = "Loaded profile \"%s\"" % profile_name
	settings_changed.emit()


func _build_input_mapper(parent: VBoxContainer):
	var card = _create_card(parent, "Input Mapper", "Map buttons/keys to actions. Press the inputs after clicking map.", "🎮")
	input_mapper_status = _make_hint("Click \"Map Input\" to start listening. Enter = save, Esc = cancel.")
	card.add_child(input_mapper_status)
	
	for action_data in INPUT_ACTIONS:
		var row := _create_input_row(card, action_data)
		input_rows[action_data.action] = row
		_refresh_input_row(action_data.action)


func _create_input_row(parent: VBoxContainer, action_data: Dictionary) -> InputRow:
	var row := InputRow.new()
	row.action = action_data.action
	
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	parent.add_child(container)
	
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	container.add_child(header)
	
	var label = Label.new()
	label.text = action_data.label
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", COLOR_SUBTITLE)
	label.custom_minimum_size = Vector2(110, 0)
	header.add_child(label)
	
	row.summary = _make_hint("Not mapped yet")
	row.summary.custom_minimum_size = Vector2(220, 0)
	header.add_child(row.summary)
	
	row.mode_btn = OptionButton.new()
	row.mode_btn.add_item("Any (OR)") # 0
	row.mode_btn.add_item("Chord (all together)") # 1
	row.mode_btn.add_item("Sequence (in order)") # 2
	row.mode_btn.tooltip_text = "Choose how multiple inputs should behave."
	row.mode_btn.custom_minimum_size = Vector2(180, 0)
	row.mode_btn.item_selected.connect(func(_i): _on_mode_changed(row.action))
	header.add_child(row.mode_btn)
	
	row.listen_btn = Button.new()
	row.listen_btn.text = "Map Input"
	row.listen_btn.focus_mode = Control.FOCUS_NONE
	row.listen_btn.tooltip_text = "Click, then press one or more inputs to bind."
	row.listen_btn.pressed.connect(func(): _toggle_listen_for(row.action))
	header.add_child(row.listen_btn)
	
	if action_data.has("description"):
		var hint = _make_hint(action_data.description)
		container.add_child(hint)
	
	return row


func _toggle_listen_for(action: String):
	if input_listen_action == action:
		_stop_listening(true)
		return
	_start_listening(action)


func _start_listening(action: String):
	input_listen_action = action
	input_listen_events = []
	for key in input_rows.keys():
		var r: InputRow = input_rows[key]
		r.listen_btn.disabled = key != action
		if key == action:
			r.listen_btn.text = "Listening..."
			if r.summary:
				r.summary.text = "Listening..."
	if input_mapper_status:
		input_mapper_status.text = "Listening for %s. Press inputs, Enter = save, Esc = cancel." % action


func _stop_listening(commit: bool):
	if input_listen_action == "":
		return
	var action := input_listen_action
	var events := input_listen_events.duplicate()
	input_listen_action = ""
	input_listen_events.clear()
	
	for key in input_rows.keys():
		var r: InputRow = input_rows[key]
		r.listen_btn.disabled = false
		r.listen_btn.text = "Map Input"
	
	if commit and not events.is_empty():
		var row: InputRow = input_rows.get(action, null)
		var mode := _mode_from_selector(row.mode_btn) if row else InputBindingManager.MODE_ANY
		InputBindingManager.get_singleton().set_binding(action, events, mode)
		_refresh_input_row(action)
	else:
		_refresh_input_row(action)
	if input_mapper_status:
		input_mapper_status.text = "Click \"Map Input\" to start listening. Enter = save, Esc = cancel."


func _mode_from_selector(selector: OptionButton) -> String:
	match selector.selected:
		1:
			return InputBindingManager.MODE_CHORD
		2:
			return InputBindingManager.MODE_SEQUENCE
		_:
			return InputBindingManager.MODE_ANY


func _refresh_input_row(action: String):
	var row: InputRow = input_rows.get(action, null)
	if not row:
		return
	var manager := InputBindingManager.get_singleton()
	var binding: Dictionary = manager.get_binding(action) if manager else {}
	if binding.is_empty():
		var existing := InputMap.action_get_events(action) if InputMap.has_action(action) else []
		if manager:
			manager.ensure_binding(action, existing, InputBindingManager.MODE_ANY)
		binding = manager.get_binding(action) if manager else {"events": existing, "mode": InputBindingManager.MODE_ANY}
	
	var events: Array = binding.get("events", [])
	var mode: String = binding.get("mode", InputBindingManager.MODE_ANY)
	row.mode_btn.selected = 0 if mode == InputBindingManager.MODE_ANY else 1 if mode == InputBindingManager.MODE_CHORD else 2
	if events.is_empty():
		row.summary.text = "No bindings set"
	else:
		row.summary.text = "%s (%s)" % [_format_events(events), _format_mode(mode)]


func _format_mode(mode: String) -> String:
	if mode == InputBindingManager.MODE_CHORD:
		return "all together"
	if mode == InputBindingManager.MODE_SEQUENCE:
		return "in order"
	return "any"


func _format_events(events: Array) -> String:
	var parts: Array[String] = []
	for ev in events:
		if ev is InputEvent:
			parts.append(ev.as_text())
	return ", ".join(parts)


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


class InputRow:
	var action: String
	var summary: Label
	var listen_btn: Button
	var mode_btn: OptionButton


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
