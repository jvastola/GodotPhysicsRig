extends PanelContainer
class_name MovementSettingsPanel
## Movement Settings Panel - Locomotion, turning, and hand swap controls

signal settings_changed()

# UI References - will be set up dynamically
var locomotion_mode_btn: OptionButton
var locomotion_speed_slider: HSlider
var locomotion_speed_label: Label
var turn_mode_btn: OptionButton
var snap_angle_slider: HSlider
var snap_angle_label: Label
var smooth_speed_slider: HSlider
var smooth_speed_label: Label
var deadzone_slider: HSlider
var deadzone_label: Label
var hand_swap_check: CheckBox
var world_scale_check: CheckBox
var world_rotation_check: CheckBox
var gravity_check: CheckBox

# Reference to movement component
var movement_component: PlayerMovementComponent


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
		else:
			push_warning("MovementSettingsPanel: PlayerMovementComponent not found")
	else:
		# Retry after a frame
		call_deferred("_find_movement_component")


func _build_ui():
	"""Build the settings UI dynamically"""
	# Main container
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	add_child(main_vbox)
	
	# Title
	var title = Label.new()
	title.text = "MOVEMENT SETTINGS"
	title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	title.add_theme_font_size_override("font_size", 14)
	main_vbox.add_child(title)
	
	# === Locomotion Section ===
	_add_section_label(main_vbox, "Locomotion")
	
	# Locomotion Mode
	var loco_row = _create_row(main_vbox, "Mode:")
	locomotion_mode_btn = OptionButton.new()
	locomotion_mode_btn.add_item("Disabled")
	locomotion_mode_btn.add_item("Head Direction")
	locomotion_mode_btn.add_item("Hand Direction")
	locomotion_mode_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if movement_component:
		locomotion_mode_btn.selected = movement_component.locomotion_mode
	locomotion_mode_btn.item_selected.connect(_on_locomotion_mode_changed)
	loco_row.add_child(locomotion_mode_btn)
	
	# Locomotion Speed
	var speed_container = VBoxContainer.new()
	locomotion_speed_label = Label.new()
	var initial_speed = movement_component.locomotion_speed if movement_component else 3.0
	locomotion_speed_label.text = "Speed: %.1f m/s" % initial_speed
	locomotion_speed_label.add_theme_font_size_override("font_size", 12)
	speed_container.add_child(locomotion_speed_label)
	
	locomotion_speed_slider = HSlider.new()
	locomotion_speed_slider.min_value = 1.0
	locomotion_speed_slider.max_value = 8.0
	locomotion_speed_slider.step = 0.5
	locomotion_speed_slider.value = initial_speed
	locomotion_speed_slider.value_changed.connect(_on_locomotion_speed_changed)
	speed_container.add_child(locomotion_speed_slider)
	main_vbox.add_child(speed_container)
	
	_add_separator(main_vbox)
	
	# === Turning Section ===
	_add_section_label(main_vbox, "Turning")
	
	# Turn Mode
	var turn_row = _create_row(main_vbox, "Turn Mode:")
	turn_mode_btn = OptionButton.new()
	turn_mode_btn.add_item("Snap")
	turn_mode_btn.add_item("Smooth")
	turn_mode_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if movement_component:
		turn_mode_btn.selected = movement_component.turn_mode
	turn_mode_btn.item_selected.connect(_on_turn_mode_changed)
	turn_row.add_child(turn_mode_btn)
	
	# Snap Angle
	var snap_container = VBoxContainer.new()
	var initial_snap = movement_component.snap_turn_angle if movement_component else 45.0
	snap_angle_label = Label.new()
	snap_angle_label.text = "Snap Angle: %.0f°" % initial_snap
	snap_angle_label.add_theme_font_size_override("font_size", 12)
	snap_container.add_child(snap_angle_label)
	
	snap_angle_slider = HSlider.new()
	snap_angle_slider.min_value = 15
	snap_angle_slider.max_value = 90
	snap_angle_slider.step = 15
	snap_angle_slider.value = initial_snap
	snap_angle_slider.value_changed.connect(_on_snap_angle_changed)
	snap_container.add_child(snap_angle_slider)
	main_vbox.add_child(snap_container)
	
	# Smooth Speed
	var smooth_container = VBoxContainer.new()
	var initial_smooth = movement_component.smooth_turn_speed if movement_component else 90.0
	smooth_speed_label = Label.new()
	smooth_speed_label.text = "Smooth Speed: %.0f°/s" % initial_smooth
	smooth_speed_label.add_theme_font_size_override("font_size", 12)
	smooth_container.add_child(smooth_speed_label)
	
	smooth_speed_slider = HSlider.new()
	smooth_speed_slider.min_value = 30
	smooth_speed_slider.max_value = 180
	smooth_speed_slider.step = 15
	smooth_speed_slider.value = initial_smooth
	smooth_speed_slider.value_changed.connect(_on_smooth_speed_changed)
	smooth_container.add_child(smooth_speed_slider)
	main_vbox.add_child(smooth_container)
	
	# Deadzone
	var deadzone_container = VBoxContainer.new()
	var initial_deadzone = movement_component.turn_deadzone if movement_component else 0.5
	deadzone_label = Label.new()
	deadzone_label.text = "Deadzone: %.2f" % initial_deadzone
	deadzone_label.add_theme_font_size_override("font_size", 12)
	deadzone_container.add_child(deadzone_label)
	
	deadzone_slider = HSlider.new()
	deadzone_slider.min_value = 0.1
	deadzone_slider.max_value = 0.8
	deadzone_slider.step = 0.05
	deadzone_slider.value = initial_deadzone
	deadzone_slider.value_changed.connect(_on_deadzone_changed)
	deadzone_container.add_child(deadzone_slider)
	main_vbox.add_child(deadzone_container)
	
	_add_separator(main_vbox)
	
	# === Hand Assignment Section ===
	_add_section_label(main_vbox, "Controls")
	
	# Hand Swap Checkbox
	hand_swap_check = CheckBox.new()
	hand_swap_check.text = "Swap Hands (Move:Right, Turn:Left)"
	hand_swap_check.add_theme_font_size_override("font_size", 12)
	if movement_component:
		hand_swap_check.button_pressed = movement_component.hand_assignment == PlayerMovementComponent.HandAssignment.SWAPPED
	hand_swap_check.toggled.connect(_on_hand_swap_toggled)
	main_vbox.add_child(hand_swap_check)

	# === World Manipulation ===
	_add_section_label(main_vbox, "World Manipulation")

	world_scale_check = CheckBox.new()
	world_scale_check.text = "Two-Hand Grab World Scale"
	world_scale_check.add_theme_font_size_override("font_size", 12)
	if movement_component:
		world_scale_check.button_pressed = movement_component.enable_two_hand_world_scale
	world_scale_check.toggled.connect(_on_world_scale_toggled)
	main_vbox.add_child(world_scale_check)

	world_rotation_check = CheckBox.new()
	world_rotation_check.text = "Two-Hand Grab World Rotation"
	world_rotation_check.add_theme_font_size_override("font_size", 12)
	if movement_component:
		world_rotation_check.button_pressed = movement_component.enable_two_hand_world_rotation
	world_rotation_check.toggled.connect(_on_world_rotation_toggled)
	main_vbox.add_child(world_rotation_check)

	# === Player ===
	_add_section_label(main_vbox, "Player")

	gravity_check = CheckBox.new()
	gravity_check.text = "Player Gravity Enabled"
	gravity_check.add_theme_font_size_override("font_size", 12)
	if movement_component:
		gravity_check.button_pressed = movement_component.player_gravity_enabled
	gravity_check.toggled.connect(_on_gravity_toggled)
	main_vbox.add_child(gravity_check)


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
	label.custom_minimum_size = Vector2(100, 0)
	label.add_theme_font_size_override("font_size", 12)
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


func _on_turn_mode_changed(index: int):
	if movement_component:
		movement_component.turn_mode = index as PlayerMovementComponent.TurnMode
	settings_changed.emit()


func _on_snap_angle_changed(value: float):
	if movement_component:
		movement_component.snap_turn_angle = value
	snap_angle_label.text = "Snap Angle: %.0f°" % value
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


func _on_gravity_toggled(pressed: bool):
	if movement_component:
		movement_component.set_player_gravity_enabled(pressed)
	settings_changed.emit()


# === Public API ===

func refresh():
	"""Refresh UI from current component values"""
	if not movement_component:
		_find_movement_component()
	
	if movement_component:
		if locomotion_mode_btn:
			locomotion_mode_btn.selected = movement_component.locomotion_mode
		if locomotion_speed_slider:
			locomotion_speed_slider.value = movement_component.locomotion_speed
		if turn_mode_btn:
			turn_mode_btn.selected = movement_component.turn_mode
		if snap_angle_slider:
			snap_angle_slider.value = movement_component.snap_turn_angle
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
