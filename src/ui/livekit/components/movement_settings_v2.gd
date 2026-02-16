extends MovementSettingsPanel
class_name MovementSettingsPanelV2

## Movement Settings Panel V2 - Redesigned with tabs and collapsible sections

func _build_ui():
	"""Build the redesigned settings UI with tabs and collapsible sections"""
	# Root with padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(main_vbox)
	
	# --- Header Row ---
	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 12)
	main_vbox.add_child(header_hbox)
	
	var title_lbl = Label.new()
	title_lbl.text = "Movement Settings V2"
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", COLOR_TITLE)
	header_hbox.add_child(title_lbl)
	
	status_label = _make_hint("Waiting for player...")
	_update_status_label()
	header_hbox.add_child(status_label)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)
	
	var reset_btn = Button.new()
	reset_btn.text = "Reset All"
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.pressed.connect(_on_reset_pressed)
	header_hbox.add_child(reset_btn)

	# --- Tab Container ---
	var tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.tab_alignment = TabBar.ALIGNMENT_LEFT
	main_vbox.add_child(tabs)

	# Build Tabs
	_build_movement_tab(tabs)
	_build_controls_tab(tabs)
	_build_world_tab(tabs)
	_build_physics_tab(tabs)
	_build_system_tab(tabs)


func _create_collapsible_card(parent: VBoxContainer, title: String, subtitle: String = "", icon: String = "", open_by_default: bool = true) -> VBoxContainer:
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
	parent.add_child(panel)

	var outer_vbox = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 4)
	panel.add_child(outer_vbox)

	var header_hbox = HBoxContainer.new()
	outer_vbox.add_child(header_hbox)

	var header_btn = Button.new()
	header_btn.text = ("%s " % icon if icon != "" else "") + title
	header_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header_btn.focus_mode = Control.FOCUS_NONE
	header_btn.flat = true
	header_btn.add_theme_font_size_override("font_size", 14)
	header_btn.add_theme_color_override("font_color", COLOR_TITLE)
	header_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(header_btn)
	
	var arrow_lbl = Label.new()
	arrow_lbl.text = "▼" if open_by_default else "▶"
	header_hbox.add_child(arrow_lbl)

	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 8)
	content_vbox.visible = open_by_default
	outer_vbox.add_child(content_vbox)

	if subtitle != "":
		var sub = _make_hint(subtitle)
		content_vbox.add_child(sub)

	header_btn.pressed.connect(func():
		content_vbox.visible = !content_vbox.visible
		arrow_lbl.text = "▼" if content_vbox.visible else "▶"
	)
	
	return content_vbox


func _create_tab_scroll(tabs: TabContainer, label: String) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.name = label
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)
	return vbox


func _build_movement_tab(tabs: TabContainer):
	var vbox = _create_tab_scroll(tabs, "Movement")
	
	# Locomotion Section
	var locomotion_card = _create_collapsible_card(vbox, "Locomotion", "Speed and direction source for thumbstick movement", "🏃")
	
	var loco_row = _create_row(locomotion_card, "Mode")
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
	loco_row.add_child(locomotion_mode_btn)
	
	var initial_speed = movement_component.locomotion_speed if movement_component else defaults_snapshot["locomotion_speed"]
	var speed_block = _add_slider_block(locomotion_card, "Speed", "Movement velocity in meters per second.", 1.0, 8.0, 0.25, initial_speed, func(v): return " %.1f m/s" % v)
	locomotion_speed_label = speed_block.label
	locomotion_speed_slider = speed_block.slider
	locomotion_speed_slider.value_changed.connect(_on_locomotion_speed_changed)
	
	var initial_loco_deadzone = movement_component.locomotion_deadzone if movement_component else defaults_snapshot["locomotion_deadzone"]
	var loco_deadzone_block = _add_slider_block(locomotion_card, "Locomotion Deadzone", "Ignore thumbstick wobble below this value.", 0.05, 0.6, 0.02, initial_loco_deadzone, func(v): return " %.2f" % v)
	locomotion_deadzone_label = loco_deadzone_block.label
	locomotion_deadzone_slider = loco_deadzone_block.slider
	locomotion_deadzone_slider.value_changed.connect(_on_locomotion_deadzone_changed)
	
	var loco_invert_row = _create_row(locomotion_card, "Invert Axes")
	locomotion_invert_x_check = CheckBox.new()
	locomotion_invert_x_check.text = "Horizontal"
	locomotion_invert_x_check.button_pressed = movement_component.invert_locomotion_x if movement_component else defaults_snapshot["invert_locomotion_x"]
	locomotion_invert_x_check.toggled.connect(_on_locomotion_invert_x_toggled)
	loco_invert_row.add_child(locomotion_invert_x_check)
	
	locomotion_invert_y_check = CheckBox.new()
	locomotion_invert_y_check.text = "Vertical"
	locomotion_invert_y_check.button_pressed = movement_component.invert_locomotion_y if movement_component else defaults_snapshot["invert_locomotion_y"]
	locomotion_invert_y_check.toggled.connect(_on_locomotion_invert_y_toggled)
	loco_invert_row.add_child(locomotion_invert_y_check)

	# Turning Section
	var turning_card = _create_collapsible_card(vbox, "Turning", "Snap or smooth turning with sensitivity controls", "🌀")
	
	var turn_row = _create_row(turning_card, "Turn Mode")
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
	var initial_snap = movement_component.snap_turn_angle if movement_component else defaults_snapshot["snap_turn_angle"]
	var snap_block = _add_slider_block(snap_container, "Snap Angle", "Degrees rotated per snap turn.", 15.0, 90.0, 5.0, initial_snap, func(v): return " %.0f°" % v)
	snap_angle_label = snap_block.label
	snap_angle_slider = snap_block.slider
	snap_angle_slider.value_changed.connect(_on_snap_angle_changed)
	turning_card.add_child(snap_container)
	
	var initial_cooldown = movement_component.snap_turn_cooldown if movement_component else defaults_snapshot["snap_turn_cooldown"]
	var cooldown_block = _add_slider_block(turning_card, "Snap Cooldown", "Delay between snap turns.", 0.1, 0.7, 0.05, initial_cooldown, func(v): return " %.2fs" % v)
	snap_cooldown_label = cooldown_block.label
	snap_cooldown_slider = cooldown_block.slider
	snap_cooldown_slider.value_changed.connect(_on_snap_cooldown_changed)
	
	smooth_container = VBoxContainer.new()
	var initial_smooth = movement_component.smooth_turn_speed if movement_component else defaults_snapshot["smooth_turn_speed"]
	var smooth_block = _add_slider_block(smooth_container, "Smooth Speed", "Rotation speed for continuous turning.", 30.0, 240.0, 10.0, initial_smooth, func(v): return " %.0f°/s" % v)
	smooth_speed_label = smooth_block.label
	smooth_speed_slider = smooth_block.slider
	smooth_speed_slider.value_changed.connect(_on_smooth_speed_changed)
	turning_card.add_child(smooth_container)
	
	var initial_deadzone = movement_component.turn_deadzone if movement_component else defaults_snapshot["turn_deadzone"]
	var deadzone_block = _add_slider_block(turning_card, "Turn Deadzone", "Input threshold.", 0.05, 0.9, 0.02, initial_deadzone, func(v): return " %.2f" % v)
	deadzone_label = deadzone_block.label
	deadzone_slider = deadzone_block.slider
	deadzone_slider.value_changed.connect(_on_deadzone_changed)
	
	var turn_invert_row = _create_row(turning_card, "Invert Turn")
	turn_invert_check = CheckBox.new()
	turn_invert_check.text = "Horizontal"
	turn_invert_check.button_pressed = movement_component.invert_turn_x if movement_component else defaults_snapshot["invert_turn_x"]
	turn_invert_check.toggled.connect(_on_turn_invert_toggled)
	turn_invert_row.add_child(turn_invert_check)


func _build_controls_tab(tabs: TabContainer):
	var vbox = _create_tab_scroll(tabs, "Controls")
	
	# Hand Assignment
	var assignment_card = _create_collapsible_card(vbox, "Hand Assignment", "Choose which hand drives movement", "👐")
	hand_swap_check = CheckBox.new()
	hand_swap_check.text = "Swap Hands (Move Right / Turn Left)"
	hand_swap_check.button_pressed = movement_component.hand_assignment == PlayerMovementComponent.HandAssignment.SWAPPED if movement_component else defaults_snapshot["hand_assignment"] == PlayerMovementComponent.HandAssignment.SWAPPED
	hand_swap_check.toggled.connect(_on_hand_swap_toggled)
	assignment_card.add_child(hand_swap_check)

	# UI Interaction
	var ui_card = _create_collapsible_card(vbox, "UI Interaction", "Stick behavior when pointing at UI", "🖱️")
	ui_scroll_override_check = CheckBox.new()
	ui_scroll_override_check.text = "Use stick to scroll when pointing at UI"
	ui_scroll_override_check.button_pressed = movement_component.ui_scroll_steals_stick if movement_component else defaults_snapshot["ui_scroll_steals_stick"]
	ui_scroll_override_check.toggled.connect(_on_ui_scroll_override_toggled)
	ui_card.add_child(ui_scroll_override_check)

	var initial_scroll_speed = movement_component.ui_scroll_wheel_factor if movement_component else defaults_snapshot["ui_scroll_wheel_factor"]
	var scroll_speed_block = _add_slider_block(ui_card, "Scroll Speed", "Multiplier for emulation.", 10.0, 720.0, 10.0, initial_scroll_speed, func(v): return " %.0f" % v)
	ui_scroll_speed_label = scroll_speed_block.label
	ui_scroll_speed_slider = scroll_speed_block.slider
	ui_scroll_speed_slider.value_changed.connect(_on_ui_scroll_speed_changed)

	disable_joystick_grip_check = CheckBox.new()
	disable_joystick_grip_check.text = "Disable Joystick While Gripping"
	disable_joystick_grip_check.button_pressed = movement_component.disable_joystick_on_grip if movement_component else defaults_snapshot["disable_joystick_on_grip"]
	disable_joystick_grip_check.toggled.connect(_on_disable_joystick_grip_toggled)
	ui_card.add_child(disable_joystick_grip_check)

	# Hand Movement (Pinch)
	var hand_move_card = _create_collapsible_card(vbox, "Hand Movement (Pinch)", "Move by pulling the world with finger pinch", "🤏", false)
	hand_movement_enable_check = CheckBox.new()
	hand_movement_enable_check.text = "Enable Middle Finger Pinch Movement"
	hand_movement_enable_check.button_pressed = _get_hand_movement_enabled()
	hand_movement_enable_check.toggled.connect(_on_hand_movement_toggled)
	hand_move_card.add_child(hand_movement_enable_check)
	
	var hm_mode_row = _create_row(hand_move_card, "Grab Mode")
	hand_movement_grab_mode_btn = OptionButton.new()
	hand_movement_grab_mode_btn.add_item("Relative")
	hand_movement_grab_mode_btn.add_item("Anchored")
	hand_movement_grab_mode_btn.selected = _get_hand_movement_grab_mode()
	hand_movement_grab_mode_btn.item_selected.connect(_on_hand_movement_grab_mode_changed)
	hm_mode_row.add_child(hand_movement_grab_mode_btn)
	
	var hm_sense_block = _add_slider_block(hand_move_card, "Sensitivity", "Multiplier.", 0.05, 1.0, 0.05, _get_hand_movement_sensitivity(), func(v): return " x%.2f" % v)
	hand_movement_sensitivity_label = hm_sense_block.label
	hand_movement_sensitivity_slider = hm_sense_block.slider
	hand_movement_sensitivity_slider.value_changed.connect(_on_hand_movement_sensitivity_changed)
	
	hand_movement_invert_check = CheckBox.new()
	hand_movement_invert_check.text = "Invert Direction"
	hand_movement_invert_check.button_pressed = _get_hand_movement_invert()
	hand_movement_invert_check.toggled.connect(_on_hand_movement_invert_toggled)
	hand_move_card.add_child(hand_movement_invert_check)
	
	hand_movement_release_vel_check = CheckBox.new()
	hand_movement_release_vel_check.text = "Apply Release Velocity"
	hand_movement_release_vel_check.button_pressed = _get_hand_movement_release_velocity()
	hand_movement_release_vel_check.toggled.connect(_on_hand_movement_release_vel_toggled)
	hand_move_card.add_child(hand_movement_release_vel_check)
	
	hand_movement_show_visual_check = CheckBox.new()
	hand_movement_show_visual_check.text = "Show Grab Visual"
	hand_movement_show_visual_check.button_pressed = _get_hand_movement_show_visual()
	hand_movement_show_visual_check.toggled.connect(_on_hand_movement_show_visual_toggled)
	hand_move_card.add_child(hand_movement_show_visual_check)


func _build_world_tab(tabs: TabContainer):
	var vbox = _create_tab_scroll(tabs, "World Grab")
	
	# Two-Hand Grab (V1)
	var v1_card = _create_collapsible_card(vbox, "Two-Hand Grab (Legacy/Classic)", "Traditional pull-to-scale/rotate", "👐")
	
	world_scale_check = CheckBox.new()
	world_scale_check.text = "Enable Scale"
	world_scale_check.button_pressed = movement_component.enable_two_hand_world_scale if movement_component else defaults_snapshot["enable_two_hand_world_scale"]
	world_scale_check.toggled.connect(_on_world_scale_toggled)
	v1_card.add_child(world_scale_check)

	world_rotation_check = CheckBox.new()
	world_rotation_check.text = "Enable Rotation"
	world_rotation_check.button_pressed = movement_component.enable_two_hand_world_rotation if movement_component else defaults_snapshot["enable_two_hand_world_rotation"]
	world_rotation_check.toggled.connect(_on_world_rotation_toggled)
	v1_card.add_child(world_rotation_check)

	var action_options := ["grip", "grip_click", "trigger", "trigger_click", "primary", "secondary", "ax", "by"]
	var actions_row = _create_row(v1_card, "Inputs (L/R)")
	two_hand_left_action_btn = OptionButton.new()
	for opt in action_options: two_hand_left_action_btn.add_item(opt)
	two_hand_left_action_btn.selected = action_options.find(movement_component.two_hand_left_action if movement_component else defaults_snapshot["two_hand_left_action"])
	two_hand_left_action_btn.item_selected.connect(func(idx: int): _on_two_hand_left_action_changed(action_options[idx]))
	actions_row.add_child(two_hand_left_action_btn)

	two_hand_right_action_btn = OptionButton.new()
	for opt in action_options: two_hand_right_action_btn.add_item(opt)
	two_hand_right_action_btn.selected = action_options.find(movement_component.two_hand_right_action if movement_component else defaults_snapshot["two_hand_right_action"])
	two_hand_right_action_btn.item_selected.connect(func(idx: int): _on_two_hand_right_action_changed(action_options[idx]))
	actions_row.add_child(two_hand_right_action_btn)

	var pivot_row = _create_row(v1_card, "Pivot")
	two_hand_pivot_btn = OptionButton.new()
	two_hand_pivot_btn.add_item("Midpoint")
	two_hand_pivot_btn.add_item("Player Origin")
	two_hand_pivot_btn.selected = movement_component.two_hand_rotation_pivot if movement_component else defaults_snapshot["two_hand_rotation_pivot"]
	two_hand_pivot_btn.item_selected.connect(_on_two_hand_pivot_changed)
	pivot_row.add_child(two_hand_pivot_btn)

	show_two_hand_visual_check = CheckBox.new()
	show_two_hand_visual_check.text = "Show Rotation Visual"
	show_two_hand_visual_check.button_pressed = movement_component.show_two_hand_rotation_visual if movement_component else defaults_snapshot["show_two_hand_rotation_visual"]
	show_two_hand_visual_check.toggled.connect(_on_show_two_hand_visual_toggled)
	v1_card.add_child(show_two_hand_visual_check)

	invert_two_hand_scale_check = CheckBox.new()
	invert_two_hand_scale_check.text = "Invert Scale"
	invert_two_hand_scale_check.button_pressed = movement_component.invert_two_hand_scale_direction if movement_component else defaults_snapshot["invert_two_hand_scale_direction"]
	invert_two_hand_scale_check.toggled.connect(_on_invert_two_hand_scale_toggled)
	v1_card.add_child(invert_two_hand_scale_check)

	var move_factor_block = _add_slider_block(v1_card, "Move Factor", "Translate multiplier.", 0.05, 3.0, 0.05, movement_component.world_grab_move_factor if movement_component else defaults_snapshot["world_grab_move_factor"], func(v): return " x%.2f" % v)
	world_grab_move_factor_label = move_factor_block.label
	world_grab_move_factor_slider = move_factor_block.slider
	world_grab_move_factor_slider.value_changed.connect(_on_world_grab_move_factor_changed)

	var smooth_block = _add_slider_block(v1_card, "Smooth Factor", "Dampening.", 0.05, 1.0, 0.05, movement_component.world_grab_smooth_factor if movement_component else defaults_snapshot["world_grab_smooth_factor"], func(v): return " x%.2f" % v)
	world_grab_smooth_label = smooth_block.label
	world_grab_smooth_slider = smooth_block.slider
	world_grab_smooth_slider.value_changed.connect(_on_world_grab_smooth_factor_changed)

	var v1_min_block = _add_slider_block(v1_card, "World Scale Min", "Lower bound.", 0.05, 10.0, 0.05, movement_component.world_scale_min if movement_component else defaults_snapshot["world_scale_min"], func(v): return " %.2fx" % v)
	world_scale_min_label = v1_min_block.label
	world_scale_min_slider = v1_min_block.slider
	world_scale_min_slider.value_changed.connect(_on_world_scale_min_changed)

	var v1_max_block = _add_slider_block(v1_card, "World Scale Max", "Upper bound.", 0.5, 1000.0, 0.5, movement_component.world_scale_max if movement_component else defaults_snapshot["world_scale_max"], func(v): return " %.2fx" % v)
	world_scale_max_label = v1_max_block.label
	world_scale_max_slider = v1_max_block.slider
	world_scale_max_slider.value_changed.connect(_on_world_scale_max_changed)

	var v1_ssense_block = _add_slider_block(v1_card, "Scale Sensitivity", "Multiplier.", 0.05, 1.5, 0.05, movement_component.world_scale_sensitivity if movement_component else defaults_snapshot["world_scale_sensitivity"], func(v): return " x%.2f" % v)
	world_scale_sensitivity_label = v1_ssense_block.label
	world_scale_sensitivity_slider = v1_ssense_block.slider
	world_scale_sensitivity_slider.value_changed.connect(_on_world_scale_sensitivity_changed)

	var v1_rsense_block = _add_slider_block(v1_card, "Rotation Sensitivity", "Multiplier.", 0.05, 2.0, 0.05, movement_component.world_rotation_sensitivity if movement_component else defaults_snapshot["world_rotation_sensitivity"], func(v): return " x%.2f" % v)
	world_rotation_sensitivity_label = v1_rsense_block.label
	world_rotation_sensitivity_slider = v1_rsense_block.slider
	world_rotation_sensitivity_slider.value_changed.connect(_on_world_rotation_sensitivity_changed)
	
	# One-Hand Grab
	var one_hand_card = _create_collapsible_card(vbox, "One-Hand World Grab", "Drag the world with a single hand", "✊")
	one_hand_world_grab_check = CheckBox.new()
	one_hand_world_grab_check.text = "Enable One-Hand Grab"
	one_hand_world_grab_check.button_pressed = movement_component.enable_one_hand_world_grab if movement_component else defaults_snapshot["enable_one_hand_world_grab"]
	one_hand_world_grab_check.toggled.connect(_on_one_hand_world_grab_toggled)
	one_hand_card.add_child(one_hand_world_grab_check)

	invert_one_hand_grab_check = CheckBox.new()
	invert_one_hand_grab_check.text = "Invert Direction"
	invert_one_hand_grab_check.button_pressed = movement_component.invert_one_hand_grab_direction if movement_component else defaults_snapshot["invert_one_hand_grab_direction"]
	invert_one_hand_grab_check.toggled.connect(_on_invert_one_hand_grab_toggled)
	one_hand_card.add_child(invert_one_hand_grab_check)

	show_one_hand_grab_visual_check = CheckBox.new()
	show_one_hand_grab_visual_check.text = "Show Grab Anchor"
	show_one_hand_grab_visual_check.button_pressed = movement_component.show_one_hand_grab_visual if movement_component else defaults_snapshot["show_one_hand_grab_visual"]
	show_one_hand_grab_visual_check.toggled.connect(_on_show_one_hand_grab_visual_toggled)
	one_hand_card.add_child(show_one_hand_grab_visual_check)

	var oh_sense_block = _add_slider_block(one_hand_card, "Sensitivity", "Multiplier.", 0.05, 3.0, 0.05, movement_component.one_hand_world_move_sensitivity if movement_component else defaults_snapshot["one_hand_world_move_sensitivity"], func(v): return " x%.2f" % v)
	one_hand_world_move_sense_label = oh_sense_block.label
	one_hand_world_move_sense_slider = oh_sense_block.slider
	one_hand_world_move_sense_slider.value_changed.connect(_on_one_hand_world_move_sensitivity_changed)

	var oh_mode_row = _create_row(one_hand_card, "Grab Mode")
	one_hand_grab_mode_btn = OptionButton.new()
	one_hand_grab_mode_btn.add_item("Relative")
	one_hand_grab_mode_btn.add_item("Anchored")
	one_hand_grab_mode_btn.selected = movement_component.one_hand_grab_mode if movement_component else defaults_snapshot["one_hand_grab_mode"]
	one_hand_grab_mode_btn.item_selected.connect(_on_one_hand_grab_mode_changed)
	oh_mode_row.add_child(one_hand_grab_mode_btn)

	one_hand_rotation_check = CheckBox.new()
	one_hand_rotation_check.text = "Enable Stick Rotation While Grabbing"
	one_hand_rotation_check.button_pressed = movement_component.enable_one_hand_rotation if movement_component else defaults_snapshot["enable_one_hand_rotation"]
	one_hand_rotation_check.toggled.connect(_on_one_hand_rotation_toggled)
	one_hand_card.add_child(one_hand_rotation_check)

	var oh_rot_smooth_block = _add_slider_block(one_hand_card, "Rotation Smooth", "Dampening.", 0.05, 1.0, 0.05, movement_component.one_hand_rotation_smooth_factor if movement_component else defaults_snapshot["one_hand_rotation_smooth_factor"], func(v): return " x%.2f" % v)
	one_hand_rotation_smooth_label = oh_rot_smooth_block.label
	one_hand_rotation_smooth_slider = oh_rot_smooth_block.slider
	one_hand_rotation_smooth_slider.value_changed.connect(_on_one_hand_rotation_smooth_changed)

	one_hand_rotate_check = CheckBox.new()
	one_hand_rotate_check.text = "Enable Yaw-Only Rotation (World Tilt)"
	one_hand_rotate_check.button_pressed = movement_component.enable_one_hand_world_rotate if movement_component else defaults_snapshot["enable_one_hand_world_rotate"]
	one_hand_rotate_check.toggled.connect(_on_one_hand_world_rotate_toggled)
	one_hand_card.add_child(one_hand_rotate_check)

	invert_one_hand_rotation_check = CheckBox.new()
	invert_one_hand_rotation_check.text = "Invert Stick Rotation"
	invert_one_hand_rotation_check.button_pressed = movement_component.invert_one_hand_rotation if movement_component else defaults_snapshot["invert_one_hand_rotation"]
	invert_one_hand_rotation_check.toggled.connect(_on_invert_one_hand_rotation_toggled)
	one_hand_card.add_child(invert_one_hand_rotation_check)

	apply_one_hand_release_vel_check = CheckBox.new()
	apply_one_hand_release_vel_check.text = "Apply Momentum on Release"
	apply_one_hand_release_vel_check.button_pressed = movement_component.apply_one_hand_release_velocity if movement_component else defaults_snapshot["apply_one_hand_release_velocity"]
	apply_one_hand_release_vel_check.toggled.connect(_on_apply_one_hand_release_vel_toggled)
	one_hand_card.add_child(apply_one_hand_release_vel_check)

	# Two-Hand Grab (V2)
	var v2_card = _create_collapsible_card(vbox, "Two-Hand Grab (V2)", "Improved multi-hand manipulation", "🌟", false)
	v2_enable_check = CheckBox.new()
	v2_enable_check.text = "Enable V2"
	v2_enable_check.button_pressed = movement_component.enable_two_hand_grab_v2 if movement_component else defaults_snapshot["enable_two_hand_grab_v2"]
	v2_enable_check.toggled.connect(_on_v2_enable_toggled)
	v2_card.add_child(v2_enable_check)

	v2_scale_check = CheckBox.new()
	v2_scale_check.text = "Enable Scale"
	v2_scale_check.button_pressed = movement_component.v2_scale_enabled if movement_component else defaults_snapshot["v2_scale_enabled"]
	v2_scale_check.toggled.connect(_on_v2_scale_toggled)
	v2_card.add_child(v2_scale_check)

	v2_rotation_check = CheckBox.new()
	v2_rotation_check.text = "Enable Rotation"
	v2_rotation_check.button_pressed = movement_component.v2_rotation_enabled if movement_component else defaults_snapshot["v2_rotation_enabled"]
	v2_rotation_check.toggled.connect(_on_v2_rotation_toggled)
	v2_card.add_child(v2_rotation_check)

	var v2_min_block = _add_slider_block(v2_card, "Scale Min", "Lower bound.", 0.05, 5.0, 0.05, movement_component.v2_world_scale_min if movement_component else defaults_snapshot["v2_world_scale_min"], func(v): return " %.2fx" % v)
	v2_scale_min_label = v2_min_block.label
	v2_scale_min_slider = v2_min_block.slider
	v2_scale_min_slider.value_changed.connect(_on_v2_scale_min_changed)

	var v2_max_block = _add_slider_block(v2_card, "Scale Max", "Upper bound.", 2.0, 100.0, 0.5, movement_component.v2_world_scale_max if movement_component else defaults_snapshot["v2_world_scale_max"], func(v): return " %.1fx" % v)
	v2_scale_max_label = v2_max_block.label
	v2_scale_max_slider = v2_max_block.slider
	v2_scale_max_slider.value_changed.connect(_on_v2_scale_max_changed)

	v2_show_visual_check = CheckBox.new()
	v2_show_visual_check.text = "Show V2 Visual"
	v2_show_visual_check.button_pressed = movement_component.v2_show_visual if movement_component else defaults_snapshot["v2_show_visual"]
	v2_show_visual_check.toggled.connect(_on_v2_show_visual_toggled)
	v2_card.add_child(v2_show_visual_check)

	v2_debug_check = CheckBox.new()
	v2_debug_check.text = "V2 Debug Logs"
	v2_debug_check.button_pressed = movement_component.v2_debug_logs if movement_component else defaults_snapshot["v2_debug_logs"]
	v2_debug_check.toggled.connect(_on_v2_debug_toggled)
	v2_card.add_child(v2_debug_check)

	# Two-Hand Grab (V3)
	var v3_card = _create_collapsible_card(vbox, "Two-Hand Grab (V3 / XRTools Style)", "Advanced physics-based manipulation", "⚡", false)
	v3_enable_check = CheckBox.new()
	v3_enable_check.text = "Enable V3"
	v3_enable_check.button_pressed = movement_component.enable_two_hand_grab_v3 if movement_component else defaults_snapshot["enable_two_hand_grab_v3"]
	v3_enable_check.toggled.connect(_on_v3_enable_toggled)
	v3_card.add_child(v3_enable_check)

	var v3_min_block = _add_slider_block(v3_card, "Scale Min", "Lower bound.", 0.05, 5.0, 0.05, movement_component.v3_world_scale_min if movement_component else defaults_snapshot["v3_world_scale_min"], func(v): return " %.2fx" % v)
	v3_scale_min_label = v3_min_block.label
	v3_scale_min_slider = v3_min_block.slider
	v3_scale_min_slider.value_changed.connect(_on_v3_scale_min_changed)

	var v3_max_block = _add_slider_block(v3_card, "Scale Max", "Upper bound.", 2.0, 100.0, 0.5, movement_component.v3_world_scale_max if movement_component else defaults_snapshot["v3_world_scale_max"], func(v): return " %.1fx" % v)
	v3_scale_max_label = v3_max_block.label
	v3_scale_max_slider = v3_max_block.slider
	v3_scale_max_slider.value_changed.connect(_on_v3_scale_max_changed)

	var v3_ssense_block = _add_slider_block(v3_card, "Scale Sensitivity", "Multiplier.", 0.05, 3.0, 0.05, movement_component.v3_scale_sensitivity if movement_component else defaults_snapshot["v3_scale_sensitivity"], func(v): return " x%.2f" % v)
	v3_scale_sensitivity_label = v3_ssense_block.label
	v3_scale_sensitivity_slider = v3_ssense_block.slider
	v3_scale_sensitivity_slider.value_changed.connect(_on_v3_scale_sensitivity_changed)

	v3_invert_scale_check = CheckBox.new()
	v3_invert_scale_check.text = "Invert Scale"
	v3_invert_scale_check.button_pressed = movement_component.v3_invert_scale if movement_component else defaults_snapshot["v3_invert_scale"]
	v3_invert_scale_check.toggled.connect(_on_v3_invert_scale_toggled)
	v3_card.add_child(v3_invert_scale_check)

	var v3_rsense_block = _add_slider_block(v3_card, "Rotation Sensitivity", "Multiplier.", 0.05, 3.0, 0.05, movement_component.v3_rotation_sensitivity if movement_component else defaults_snapshot["v3_rotation_sensitivity"], func(v): return " x%.2f" % v)
	v3_rotation_sensitivity_label = v3_rsense_block.label
	v3_rotation_sensitivity_slider = v3_rsense_block.slider
	v3_rotation_sensitivity_slider.value_changed.connect(_on_v3_rotation_sensitivity_changed)

	var v3_tsense_block = _add_slider_block(v3_card, "Translation Sensitivity", "Multiplier.", 0.05, 3.0, 0.05, movement_component.v3_translation_sensitivity if movement_component else defaults_snapshot["v3_translation_sensitivity"], func(v): return " x%.2f" % v)
	v3_translation_sensitivity_label = v3_tsense_block.label
	v3_translation_sensitivity_slider = v3_tsense_block.slider
	v3_translation_sensitivity_slider.value_changed.connect(_on_v3_translation_sensitivity_changed)

	var v3_smooth_block = _add_slider_block(v3_card, "Smoothing", "Interpolation factor.", 0.0, 1.0, 0.05, movement_component.v3_smoothing if movement_component else defaults_snapshot["v3_smoothing"], func(v): return " %.2f" % v)
	v3_smoothing_label = v3_smooth_block.label
	v3_smoothing_slider = v3_smooth_block.slider
	v3_smoothing_slider.value_changed.connect(_on_v3_smoothing_changed)

	v3_show_visual_check = CheckBox.new()
	v3_show_visual_check.text = "Show V3 Visual"
	v3_show_visual_check.button_pressed = movement_component.v3_show_visual if movement_component else defaults_snapshot["v3_show_visual"]
	v3_show_visual_check.toggled.connect(_on_v3_show_visual_toggled)
	v3_card.add_child(v3_show_visual_check)

	v3_debug_check = CheckBox.new()
	v3_debug_check.text = "V3 Debug Logs"
	v3_debug_check.button_pressed = movement_component.v3_debug_logs if movement_component else defaults_snapshot["v3_debug_logs"]
	v3_debug_check.toggled.connect(_on_v3_debug_toggled)
	v3_card.add_child(v3_debug_check)

	# Simple World Grab
	var simple_grab_card = _create_collapsible_card(vbox, "Simple World Grab", "Minimal world grab - grip anywhere", "✊", false)
	simple_world_grab_check = CheckBox.new()
	simple_world_grab_check.text = "Enable Simple World Grab"
	simple_world_grab_check.button_pressed = _get_simple_world_grab_enabled()
	simple_world_grab_check.toggled.connect(_on_simple_world_grab_toggled)
	simple_grab_card.add_child(simple_world_grab_check)


func _build_physics_tab(tabs: TabContainer):
	var vbox = _create_tab_scroll(tabs, "Physics & Survival")
	
	# Physics Hands
	var hand_phys_card = _create_collapsible_card(vbox, "Physics Hands", "Toggle hand collision and physics interaction", "🧤")
	physics_hands_check = CheckBox.new()
	physics_hands_check.text = "Enable Physics Hands"
	physics_hands_check.button_pressed = movement_component.enable_physics_hands if movement_component else defaults_snapshot["enable_physics_hands"]
	physics_hands_check.toggled.connect(_on_physics_hands_toggled)
	hand_phys_card.add_child(physics_hands_check)

	# Jump & Gravity
	var grav_card = _create_collapsible_card(vbox, "Jump & Gravity", "Control vertical movement and forces", "🚀")
	jump_enabled_check = CheckBox.new()
	jump_enabled_check.text = "Enable Jump"
	jump_enabled_check.button_pressed = movement_component.jump_enabled if movement_component else defaults_snapshot["jump_enabled"]
	jump_enabled_check.toggled.connect(_on_jump_enabled_toggled)
	grav_card.add_child(jump_enabled_check)

	var jump_imp_block = _add_slider_block(grav_card, "Jump Impulse", "Upward force.", 5.0, 25.0, 1.0, movement_component.jump_impulse if movement_component else defaults_snapshot["jump_impulse"], func(v): return " %.1f" % v)
	jump_impulse_label = jump_imp_block.label
	jump_impulse_slider = jump_imp_block.slider
	jump_impulse_slider.value_changed.connect(_on_jump_impulse_changed)

	var jump_cooldown_block = _add_slider_block(grav_card, "Jump Cooldown", "Delay between jumps.", 0.1, 2.0, 0.1, movement_component.jump_cooldown if movement_component else defaults_snapshot["jump_cooldown"], func(v): return " %.1fs" % v)
	jump_cooldown_label = jump_cooldown_block.label
	jump_cooldown_slider = jump_cooldown_block.slider
	jump_cooldown_slider.value_changed.connect(_on_jump_cooldown_changed)

	gravity_check = CheckBox.new()
	gravity_check.text = "Enable Gravity"
	gravity_check.button_pressed = movement_component.player_gravity_enabled if movement_component else defaults_snapshot["player_gravity_enabled"]
	gravity_check.toggled.connect(_on_gravity_toggled)
	grav_card.add_child(gravity_check)

	var drag_block = _add_slider_block(grav_card, "Air/Move Drag", "Dampening factor.", 0.0, 1.0, 0.05, movement_component.player_drag_force if movement_component else defaults_snapshot["player_drag_force"], func(v): return " x%.2f" % v)
	player_drag_label = drag_block.label
	player_drag_slider = drag_block.slider
	player_drag_slider.value_changed.connect(_on_player_drag_changed)

	# Auto-Respawn
	var respawn_card = _create_collapsible_card(vbox, "Auto-Respawn", "Automatic recovery when falling too far", "♻️")
	auto_respawn_check = CheckBox.new()
	auto_respawn_check.text = "Enable Auto-Respawn"
	auto_respawn_check.button_pressed = movement_component.auto_respawn_enabled if movement_component else defaults_snapshot["auto_respawn_enabled"]
	auto_respawn_check.toggled.connect(_on_auto_respawn_toggled)
	respawn_card.add_child(auto_respawn_check)

	var dist_block = _add_slider_block(respawn_card, "Respawn Distance", "Fall threshold.", 10.0, 500.0, 10.0, movement_component.auto_respawn_distance if movement_component else defaults_snapshot["auto_respawn_distance"], func(v): return " %.0fm" % v)
	auto_respawn_distance_label = dist_block.label
	auto_respawn_distance_slider = dist_block.slider
	auto_respawn_distance_slider.value_changed.connect(_on_auto_respawn_distance_changed)

	hard_respawn_check = CheckBox.new()
	hard_respawn_check.text = "Hard Respawn (Reset All Settings)"
	hard_respawn_check.button_pressed = movement_component.hard_respawn_resets_settings if movement_component else defaults_snapshot["hard_respawn_resets_settings"]
	hard_respawn_check.toggled.connect(_on_hard_respawn_toggled)
	respawn_card.add_child(hard_respawn_check)

	var respawn_now_btn = Button.new()
	respawn_now_btn.text = "Respawn Now"
	respawn_now_btn.pressed.connect(_on_respawn_now_pressed)
	respawn_card.add_child(respawn_now_btn)


func _build_system_tab(tabs: TabContainer):
	var vbox = _create_tab_scroll(tabs, "System")
	
	# Profiles
	var profile_card = _create_collapsible_card(vbox, "Profiles", "Save and load movement presets", "💾")
	var profile_row = HBoxContainer.new()
	profile_row.add_theme_constant_override("separation", 8)
	profile_card.add_child(profile_row)

	profile_name_field = LineEdit.new()
	profile_name_field.placeholder_text = "Profile name"
	profile_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_row.add_child(profile_name_field)

	var save_profile_btn = Button.new()
	save_profile_btn.text = "Save"
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
	load_profile_btn.pressed.connect(_on_load_profile_pressed)
	load_row.add_child(load_profile_btn)

	var refresh_profile_btn = Button.new()
	refresh_profile_btn.text = "Refresh Lists"
	refresh_profile_btn.pressed.connect(_refresh_profiles)
	load_row.add_child(refresh_profile_btn)

	profile_status_label = _make_hint("Ready")
	profile_card.add_child(profile_status_label)

	# Input Mapper
	var input_card = _create_collapsible_card(vbox, "Input Binding (Experimental)", "Rebind movement actions", "⌨️", false)
	input_mapper_status = _make_hint("Manual input binding")
	input_card.add_child(input_mapper_status)
	
	for action_data in INPUT_ACTIONS:
		var row := _create_input_row(input_card, action_data)
		input_rows[action_data.action] = row
		_refresh_input_row(action_data.action)
