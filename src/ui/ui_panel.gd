extends Control

@onready var tab = $TabContainer
@onready var vbox_turn = $TabContainer/TurnVBox
@onready var vbox_player = $TabContainer/PlayerVBox

var movement_component: PlayerMovementComponent
var player_body: RigidBody3D
var xr_player: Node = null

func _ready() -> void:
	print("UIPanel: _ready() called")
	# Find the player and movement component
	# We defer this slightly to ensure the player is ready and in the group
	call_deferred("_find_player_and_setup")

func _find_player_and_setup() -> void:
	print("UIPanel: _find_player_and_setup() called")
	var player = get_tree().get_first_node_in_group("xr_player")
	print("UIPanel: Found player: ", player)
	
	if player:
		movement_component = player.get_node_or_null("PlayerMovementComponent")
		print("UIPanel: Found movement_component: ", movement_component)
		xr_player = player
		player_body = player.get_node_or_null("PlayerBody") as RigidBody3D
		print("UIPanel: Found player_body: ", player_body)
	
	if movement_component:
		print("UIPanel: Calling _setup_ui()")
		_setup_ui()
	else:
		print("UIPanel: ERROR - Could not find PlayerMovementComponent")
		print("UIPanel: Available children of player: ")
		if player:
			for child in player.get_children():
				print("  - ", child.name, " (", child.get_class(), ")")

func _setup_ui() -> void:
	print("UIPanel: _setup_ui() starting")
	
	# Only clear if we have a movement component to populate with
	if not movement_component:
		print("UIPanel: No movement component, keeping default UI")
		return
	
	print("UIPanel: Movement component found, populating UI with settings")
	
	# Clear default test children
	for c in vbox_turn.get_children():
		c.queue_free()
	for c in vbox_player.get_children():
		c.queue_free()
	# Make a bit denser
	if vbox_turn:
		vbox_turn.add_theme_constant_override("separation", 8)
	if vbox_player:
		vbox_player.add_theme_constant_override("separation", 8)
	
	# === Turn Settings Tab ===
	
	# Add Turn Mode (Snap/Smooth)
	var mode_h = HBoxContainer.new()
	var mode_label = Label.new()
	mode_label.text = "Turn Mode:"
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mode_label.custom_minimum_size = Vector2(120, 0)
	mode_h.add_child(mode_label)

	var mode_button = OptionButton.new()
	mode_button.add_item("Snap")
	mode_button.add_item("Smooth")
	mode_button.selected = movement_component.turn_mode
	mode_button.item_selected.connect(_on_mode_selected)
	mode_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_h.add_child(mode_button)
	vbox_turn.add_child(mode_h)
	
	# Separator
	_add_separator(vbox_turn)
	
	# Section Label: Snap Turn Settings
	var snap_section = Label.new()
	snap_section.text = "  Snap Turn Settings"
	snap_section.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	vbox_turn.add_child(snap_section)
	
	# Add Snap Angle
	var snap_container = VBoxContainer.new()
	var snap_label = Label.new()
	snap_label.text = "   Snap Angle: %.0f°" % movement_component.snap_turn_angle
	snap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	snap_container.add_child(snap_label)

	var snap_slider = HSlider.new()
	snap_slider.min_value = 15
	snap_slider.max_value = 90
	snap_slider.step = 15
	snap_slider.value = movement_component.snap_turn_angle
	snap_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	snap_slider.value_changed.connect(func(val): 
		_on_snap_angle_changed(val, snap_label)
	)
	snap_container.add_child(snap_slider)
	vbox_turn.add_child(snap_container)
	
	# Add Snap Cooldown
	var cooldown_container = VBoxContainer.new()
	var cooldown_label = Label.new()
	cooldown_label.text = "   Cooldown: %.2fs" % movement_component.snap_turn_cooldown
	cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	cooldown_container.add_child(cooldown_label)

	var cooldown_slider = HSlider.new()
	cooldown_slider.min_value = 0.1
	cooldown_slider.max_value = 1.0
	cooldown_slider.step = 0.1
	cooldown_slider.value = movement_component.snap_turn_cooldown
	cooldown_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cooldown_slider.value_changed.connect(func(val):
		_on_cooldown_changed(val, cooldown_label)
	)
	cooldown_container.add_child(cooldown_slider)
	vbox_turn.add_child(cooldown_container)
	
	# Separator
	_add_separator(vbox_turn)
	
	# Section Label: Smooth Turn Settings
	var smooth_section = Label.new()
	smooth_section.text = "  Smooth Turn Settings"
	smooth_section.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	vbox_turn.add_child(smooth_section)
	
	# Add Smooth Speed
	var smooth_container = VBoxContainer.new()
	var smooth_label = Label.new()
	smooth_label.text = "   Speed: %.0f°/sec" % movement_component.smooth_turn_speed
	smooth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	smooth_container.add_child(smooth_label)

	var smooth_slider = HSlider.new()
	smooth_slider.min_value = 10
	smooth_slider.max_value = 360
	smooth_slider.step = 10
	smooth_slider.value = movement_component.smooth_turn_speed
	smooth_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	smooth_slider.value_changed.connect(func(val):
		_on_smooth_speed_changed(val, smooth_label)
	)
	smooth_container.add_child(smooth_slider)
	vbox_turn.add_child(smooth_container)
	
	# Separator
	_add_separator(vbox_turn)
	
	# Section Label: Input Settings
	var input_section = Label.new()
	input_section.text = "  Input Settings"
	input_section.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	vbox_turn.add_child(input_section)
	
	# Add Deadzone
	var deadzone_container = VBoxContainer.new()
	var deadzone_label = Label.new()
	deadzone_label.text = "   Deadzone: %.2f" % movement_component.turn_deadzone
	deadzone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	deadzone_container.add_child(deadzone_label)

	var deadzone_slider = HSlider.new()
	deadzone_slider.min_value = 0.0
	deadzone_slider.max_value = 1.0
	deadzone_slider.step = 0.05
	deadzone_slider.value = movement_component.turn_deadzone
	deadzone_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deadzone_slider.value_changed.connect(func(val):
		_on_deadzone_changed(val, deadzone_label)
	)
	deadzone_container.add_child(deadzone_slider)
	vbox_turn.add_child(deadzone_container)

	# === Player Settings Tab ===
	
	# Add Player Scale
	var scale_container = VBoxContainer.new()
	var scale_label = Label.new()
	var initial_scale = 1.0
	if player_body:
		initial_scale = player_body.scale.x
	scale_label.text = "Player Scale: %.2fx" % initial_scale
	scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	scale_container.add_child(scale_label)

	# Scale Action Buttons [-] [+]
	var action_hbox = HBoxContainer.new()
	action_hbox.add_theme_constant_override("separation", 10)
	
	var decrease_btn = Button.new()
	decrease_btn.text = " - "
	decrease_btn.custom_minimum_size = Vector2(40, 0)
	decrease_btn.pressed.connect(func(): _on_apply_scale_change(-1, scale_label))
	action_hbox.add_child(decrease_btn)
	
	var increase_btn = Button.new()
	increase_btn.text = " + "
	increase_btn.custom_minimum_size = Vector2(40, 0)
	increase_btn.pressed.connect(func(): _on_apply_scale_change(1, scale_label))
	action_hbox.add_child(increase_btn)
	
	scale_container.add_child(action_hbox)
	
	# Step Control: Step: 5% [-] [+]
	var step_hbox = HBoxContainer.new()
	step_hbox.add_theme_constant_override("separation", 10)
	
	var step_label = Label.new()
	step_label.text = "Step: %d%%" % scale_step_percent
	step_hbox.add_child(step_label)
	
	var step_dec_btn = Button.new()
	step_dec_btn.text = "-"
	step_dec_btn.custom_minimum_size = Vector2(30, 0)
	step_dec_btn.pressed.connect(func(): _on_scale_step_changed(-1, step_label))
	step_hbox.add_child(step_dec_btn)
	
	var step_inc_btn = Button.new()
	step_inc_btn.text = "+"
	step_inc_btn.custom_minimum_size = Vector2(30, 0)
	step_inc_btn.pressed.connect(func(): _on_scale_step_changed(1, step_label))
	step_hbox.add_child(step_inc_btn)
	
	scale_container.add_child(step_hbox)
	vbox_player.add_child(scale_container)

	# Set tab titles if we have a TabContainer (Turn and Player)
	if tab and tab.get_child_count() >= 2:
		tab.set_tab_title(0, "Turn")
		tab.set_tab_title(1, "Player")

func _add_separator(parent: VBoxContainer) -> void:
	"""Add a visual separator line"""
	var separator = HSeparator.new()
	separator.custom_minimum_size = Vector2(0, 4)
	parent.add_child(separator)

func _on_mode_selected(index: int) -> void:
	if movement_component:
		movement_component.turn_mode = index as PlayerMovementComponent.TurnMode

func _on_snap_angle_changed(value: float, label: Label) -> void:
	if movement_component:
		movement_component.snap_turn_angle = value
		label.text = "   Snap Angle: %.0f°" % value

func _on_smooth_speed_changed(value: float, label: Label) -> void:
	if movement_component:
		movement_component.smooth_turn_speed = value
		label.text = "   Speed: %.0f°/sec" % value

func _on_deadzone_changed(value: float, label: Label) -> void:
	if movement_component:
		movement_component.turn_deadzone = value
		label.text = "   Deadzone: %.2f" % value

func _on_cooldown_changed(value: float, label: Label) -> void:
	if movement_component:
		movement_component.snap_turn_cooldown = value
		label.text = "   Cooldown: %.2fs" % value

func _on_player_scale_changed(value: float, label: Label) -> void:
	# Apply uniform scale to the player's body
	if player_body:
		player_body.scale = Vector3(value, value, value)
		label.text = "Player Scale: %.2fx" % value
	else:
		print("UIPanel: Cannot change player scale, PlayerBody not found")

# === Player Scale Helpers ===

var scale_step_percent: int = 5

func _on_scale_step_changed(change: int, label: Label) -> void:
	scale_step_percent = clampi(scale_step_percent + change, 1, 25)
	label.text = "Step: %d%%" % scale_step_percent

func _on_apply_scale_change(sign: int, label: Label) -> void:
	if not player_body:
		return
		
	var current_scale = player_body.scale.x
	var change_amount = (scale_step_percent / 100.0) * sign
	var new_scale = clampf(current_scale + change_amount, 0.25, 3.0)
	
	player_body.scale = Vector3(new_scale, new_scale, new_scale)
	label.text = "Player Scale: %.2fx" % new_scale
