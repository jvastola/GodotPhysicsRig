extends MovementSettingsPanel
class_name MovementSettingsPanelV2

## Movement Settings Panel V3 - streamlined base tab layout

var _locomotion_details: VBoxContainer


func _ready() -> void:
	_apply_fullrect_layout()
	_find_movement_component()
	_build_ui()
	_refresh_profiles()
	_auto_load_saved_settings()
	if not settings_changed.is_connected(_queue_auto_save):
		settings_changed.connect(_queue_auto_save)


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)

	var title := Label.new()
	title.text = "Movement Settings V3"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	header.add_child(title)

	status_label = _make_hint("Waiting for player...")
	_update_status_label()
	header.add_child(status_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.pressed.connect(_on_reset_pressed)
	header.add_child(reset_btn)

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)

	_build_base_tab(tabs)

	_update_turn_mode_ui()
	_update_locomotion_controls_enabled()


func _create_tab_scroll(tabs: TabContainer, name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)
	return vbox


func _build_base_tab(tabs: TabContainer) -> void:
	var vbox := _create_tab_scroll(tabs, "Base")

	var controls_card := _create_card(vbox, "Handedness", "Controller layout for move/turn", "👐")
	hand_swap_check = CheckBox.new()
	hand_swap_check.text = "Left-Handed Layout (Move Right / Turn Left)"
	hand_swap_check.button_pressed = movement_component.hand_assignment == PlayerMovementComponent.HandAssignment.SWAPPED if movement_component else defaults_snapshot["hand_assignment"] == PlayerMovementComponent.HandAssignment.SWAPPED
	hand_swap_check.toggled.connect(_on_hand_swap_toggled)
	controls_card.add_child(hand_swap_check)

	var locomotion_card := _create_card(vbox, "Locomotion", "Stick movement and direction source", "🏃")
	var mode_row := _create_row(locomotion_card, "Mode")
	locomotion_mode_btn = OptionButton.new()
	locomotion_mode_btn.add_item("Disabled")
	locomotion_mode_btn.add_item("Head Direction")
	locomotion_mode_btn.add_item("Hand Direction")
	locomotion_mode_btn.add_item("Head Direction (3D)")
	locomotion_mode_btn.add_item("Hand Direction (3D)")
	locomotion_mode_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	locomotion_mode_btn.selected = movement_component.locomotion_mode if movement_component else defaults_snapshot["locomotion_mode"]
	locomotion_mode_btn.item_selected.connect(func(index: int):
		_on_locomotion_mode_changed(index)
		_update_locomotion_controls_enabled()
	)
	mode_row.add_child(locomotion_mode_btn)

	_locomotion_details = VBoxContainer.new()
	_locomotion_details.add_theme_constant_override("separation", 8)
	locomotion_card.add_child(_locomotion_details)

	var speed_block = _add_slider_block(
		_locomotion_details,
		"Speed",
		"Movement speed in meters per second.",
		1.0,
		8.0,
		0.25,
		movement_component.locomotion_speed if movement_component else defaults_snapshot["locomotion_speed"],
		func(v): return " %.1f m/s" % v
	)
	locomotion_speed_label = speed_block.label
	locomotion_speed_slider = speed_block.slider
	locomotion_speed_slider.value_changed.connect(_on_locomotion_speed_changed)

	var deadzone_block = _add_slider_block(
		_locomotion_details,
		"Deadzone",
		"Ignore tiny stick drift.",
		0.05,
		0.6,
		0.02,
		movement_component.locomotion_deadzone if movement_component else defaults_snapshot["locomotion_deadzone"],
		func(v): return " %.2f" % v
	)
	locomotion_deadzone_label = deadzone_block.label
	locomotion_deadzone_slider = deadzone_block.slider
	locomotion_deadzone_slider.value_changed.connect(_on_locomotion_deadzone_changed)

	var invert_row := _create_row(_locomotion_details, "Invert")
	locomotion_invert_x_check = CheckBox.new()
	locomotion_invert_x_check.text = "Horizontal"
	locomotion_invert_x_check.button_pressed = movement_component.invert_locomotion_x if movement_component else defaults_snapshot["invert_locomotion_x"]
	locomotion_invert_x_check.toggled.connect(_on_locomotion_invert_x_toggled)
	invert_row.add_child(locomotion_invert_x_check)

	locomotion_invert_y_check = CheckBox.new()
	locomotion_invert_y_check.text = "Vertical"
	locomotion_invert_y_check.button_pressed = movement_component.invert_locomotion_y if movement_component else defaults_snapshot["invert_locomotion_y"]
	locomotion_invert_y_check.toggled.connect(_on_locomotion_invert_y_toggled)
	invert_row.add_child(locomotion_invert_y_check)

	var turning_card := _create_card(vbox, "Turning", "Snap or smooth turning", "🌀")
	var turn_row := _create_row(turning_card, "Turn Mode")
	turn_mode_btn = OptionButton.new()
	turn_mode_btn.add_item("Snap")
	turn_mode_btn.add_item("Smooth")
	turn_mode_btn.add_item("Disabled")
	turn_mode_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	turn_mode_btn.selected = movement_component.turn_mode if movement_component else defaults_snapshot["turn_mode"]
	turn_mode_btn.item_selected.connect(func(index: int):
		_on_turn_mode_changed(index)
		_update_turn_mode_ui()
	)
	turn_row.add_child(turn_mode_btn)

	snap_container = VBoxContainer.new()
	snap_container.add_theme_constant_override("separation", 8)
	turning_card.add_child(snap_container)

	var snap_block = _add_slider_block(
		snap_container,
		"Snap Angle",
		"Angle per snap turn.",
		15.0,
		90.0,
		5.0,
		movement_component.snap_turn_angle if movement_component else defaults_snapshot["snap_turn_angle"],
		func(v): return " %.0f°" % v
	)
	snap_angle_label = snap_block.label
	snap_angle_slider = snap_block.slider
	snap_angle_slider.value_changed.connect(_on_snap_angle_changed)

	var cooldown_block = _add_slider_block(
		snap_container,
		"Snap Cooldown",
		"Delay between snap turns.",
		0.1,
		0.7,
		0.05,
		movement_component.snap_turn_cooldown if movement_component else defaults_snapshot["snap_turn_cooldown"],
		func(v): return " %.2fs" % v
	)
	snap_cooldown_label = cooldown_block.label
	snap_cooldown_slider = cooldown_block.slider
	snap_cooldown_slider.value_changed.connect(_on_snap_cooldown_changed)

	smooth_container = VBoxContainer.new()
	smooth_container.add_theme_constant_override("separation", 8)
	turning_card.add_child(smooth_container)

	var smooth_block = _add_slider_block(
		smooth_container,
		"Smooth Speed",
		"Rotation speed for smooth mode.",
		30.0,
		240.0,
		10.0,
		movement_component.smooth_turn_speed if movement_component else defaults_snapshot["smooth_turn_speed"],
		func(v): return " %.0f°/s" % v
	)
	smooth_speed_label = smooth_block.label
	smooth_speed_slider = smooth_block.slider
	smooth_speed_slider.value_changed.connect(_on_smooth_speed_changed)

	var turn_deadzone_block = _add_slider_block(
		smooth_container,
		"Turn Deadzone",
		"Stick threshold for turning.",
		0.05,
		0.9,
		0.02,
		movement_component.turn_deadzone if movement_component else defaults_snapshot["turn_deadzone"],
		func(v): return " %.2f" % v
	)
	deadzone_label = turn_deadzone_block.label
	deadzone_slider = turn_deadzone_block.slider
	deadzone_slider.value_changed.connect(_on_deadzone_changed)

	var turn_invert_row := _create_row(turning_card, "Invert")
	turn_invert_check = CheckBox.new()
	turn_invert_check.text = "Horizontal"
	turn_invert_check.button_pressed = movement_component.invert_turn_x if movement_component else defaults_snapshot["invert_turn_x"]
	turn_invert_check.toggled.connect(_on_turn_invert_toggled)
	turn_invert_row.add_child(turn_invert_check)

	var simple_card := _create_card(vbox, "Simple World Grab", "Grip anywhere to drag and scale the world", "🌐")
	simple_world_grab_check = CheckBox.new()
	simple_world_grab_check.text = "Enable Simple World Grab"
	simple_world_grab_check.button_pressed = _get_simple_world_grab_enabled()
	simple_world_grab_check.toggled.connect(_on_simple_world_grab_toggled)
	simple_card.add_child(simple_world_grab_check)

	var physics_card := _create_card(vbox, "Movement Physics", "Runtime physics toggles", "⚙️")
	physics_hands_check = CheckBox.new()
	physics_hands_check.text = "Enable Physics Hands"
	physics_hands_check.button_pressed = movement_component.enable_physics_hands if movement_component else defaults_snapshot["enable_physics_hands"]
	physics_hands_check.toggled.connect(_on_physics_hands_toggled)
	physics_card.add_child(physics_hands_check)

	gravity_check = CheckBox.new()
	gravity_check.text = "Enable Player Gravity"
	gravity_check.button_pressed = movement_component.player_gravity_enabled if movement_component else defaults_snapshot["player_gravity_enabled"]
	gravity_check.toggled.connect(_on_gravity_toggled)
	physics_card.add_child(gravity_check)

	var drag_block = _add_slider_block(
		physics_card,
		"Player Drag",
		"Linear damp applied to player body.",
		0.0,
		5.0,
		0.05,
		movement_component.player_drag_force if movement_component else defaults_snapshot["player_drag_force"],
		func(v): return " x%.2f" % v
	)
	player_drag_label = drag_block.label
	player_drag_slider = drag_block.slider
	player_drag_slider.value_changed.connect(_on_player_drag_changed)

	var safety_card := _create_card(vbox, "Safety", "Respawn and recovery behavior", "🛟")
	auto_respawn_check = CheckBox.new()
	auto_respawn_check.text = "Enable Auto Respawn"
	auto_respawn_check.button_pressed = movement_component.auto_respawn_enabled if movement_component else defaults_snapshot["auto_respawn_enabled"]
	auto_respawn_check.toggled.connect(_on_auto_respawn_toggled)
	safety_card.add_child(auto_respawn_check)

	var respawn_dist_block = _add_slider_block(
		safety_card,
		"Respawn Distance",
		"Distance from spawn before auto-respawn.",
		1.0,
		1000.0,
		1.0,
		movement_component.auto_respawn_distance if movement_component else defaults_snapshot["auto_respawn_distance"],
		func(v): return " %.0f m" % v
	)
	auto_respawn_distance_label = respawn_dist_block.label
	auto_respawn_distance_slider = respawn_dist_block.slider
	auto_respawn_distance_slider.value_changed.connect(_on_auto_respawn_distance_changed)

	hard_respawn_check = CheckBox.new()
	hard_respawn_check.text = "Hard Respawn Resets Settings"
	hard_respawn_check.button_pressed = movement_component.hard_respawn_resets_settings if movement_component else defaults_snapshot["hard_respawn_resets_settings"]
	hard_respawn_check.toggled.connect(_on_hard_respawn_toggled)
	safety_card.add_child(hard_respawn_check)

	var respawn_btn := Button.new()
	respawn_btn.text = "Respawn Now"
	respawn_btn.focus_mode = Control.FOCUS_NONE
	respawn_btn.pressed.connect(_on_respawn_now_pressed)
	safety_card.add_child(respawn_btn)


func _update_locomotion_controls_enabled() -> void:
	super._update_locomotion_controls_enabled()
	if _locomotion_details and locomotion_mode_btn:
		_locomotion_details.visible = locomotion_mode_btn.selected != PlayerMovementComponent.LocomotionMode.DISABLED


func _update_turn_mode_ui() -> void:
	super._update_turn_mode_ui()
	if turn_invert_check and turn_mode_btn:
		turn_invert_check.disabled = turn_mode_btn.selected == PlayerMovementComponent.TurnMode.DISABLED


func _collect_settings_data() -> Dictionary:
	var data := super._collect_settings_data()
	if not movement_component:
		return data

	# Preserve hidden legacy fields so this panel does not force-reset them.
	data["ui_scroll_steals_stick"] = movement_component.ui_scroll_steals_stick
	data["ui_scroll_wheel_factor"] = movement_component.ui_scroll_wheel_factor
	data["disable_joystick_on_grip"] = movement_component.disable_joystick_on_grip
	data["enable_two_hand_world_scale"] = movement_component.enable_two_hand_world_scale
	data["enable_two_hand_world_rotation"] = movement_component.enable_two_hand_world_rotation
	data["invert_two_hand_scale_direction"] = movement_component.invert_two_hand_scale_direction
	data["show_two_hand_rotation_visual"] = movement_component.show_two_hand_rotation_visual
	data["two_hand_left_action"] = movement_component.two_hand_left_action
	data["two_hand_right_action"] = movement_component.two_hand_right_action
	data["world_scale_min"] = movement_component.world_scale_min
	data["world_scale_max"] = movement_component.world_scale_max
	data["world_scale_sensitivity"] = movement_component.world_scale_sensitivity
	data["world_rotation_sensitivity"] = movement_component.world_rotation_sensitivity
	data["world_grab_move_factor"] = movement_component.world_grab_move_factor
	data["world_grab_smooth_factor"] = movement_component.world_grab_smooth_factor
	data["enable_one_hand_world_grab"] = movement_component.enable_one_hand_world_grab
	data["one_hand_world_move_sensitivity"] = movement_component.one_hand_world_move_sensitivity
	data["one_hand_grab_mode"] = movement_component.one_hand_grab_mode
	data["enable_one_hand_rotation"] = movement_component.enable_one_hand_rotation
	data["enable_one_hand_world_rotate"] = movement_component.enable_one_hand_world_rotate
	data["invert_one_hand_rotation"] = movement_component.invert_one_hand_rotation
	data["one_hand_rotation_smooth_factor"] = movement_component.one_hand_rotation_smooth_factor
	data["apply_one_hand_release_velocity"] = movement_component.apply_one_hand_release_velocity
	data["invert_one_hand_grab_direction"] = movement_component.invert_one_hand_grab_direction
	data["show_one_hand_grab_visual"] = movement_component.show_one_hand_grab_visual
	data["jump_enabled"] = movement_component.jump_enabled
	data["jump_impulse"] = movement_component.jump_impulse
	data["jump_cooldown"] = movement_component.jump_cooldown
	data["enable_two_hand_grab_v2"] = movement_component.enable_two_hand_grab_v2
	data["v2_scale_enabled"] = movement_component.v2_scale_enabled
	data["v2_rotation_enabled"] = movement_component.v2_rotation_enabled
	data["v2_world_scale_min"] = movement_component.v2_world_scale_min
	data["v2_world_scale_max"] = movement_component.v2_world_scale_max
	data["v2_left_action"] = movement_component.v2_left_action
	data["v2_right_action"] = movement_component.v2_right_action
	data["v2_show_visual"] = movement_component.v2_show_visual
	data["v2_debug_logs"] = movement_component.v2_debug_logs
	data["v3_scale_sensitivity"] = movement_component.v3_scale_sensitivity
	data["v3_invert_scale"] = movement_component.v3_invert_scale
	data["v3_rotation_sensitivity"] = movement_component.v3_rotation_sensitivity
	data["v3_translation_sensitivity"] = movement_component.v3_translation_sensitivity
	data["v3_smoothing"] = movement_component.v3_smoothing
	return data
