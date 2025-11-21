extends Control

@onready var tab = $TabContainer
@onready var vbox_turn = $TabContainer/TurnVBox
@onready var vbox_player = $TabContainer/PlayerVBox

var movement_component: PlayerMovementComponent
var player_body: RigidBody3D
var xr_player: Node = null

func _ready() -> void:
	# Find the player and movement component
	# We defer this slightly to ensure the player is ready and in the group
	call_deferred("_find_player_and_setup")

func _find_player_and_setup() -> void:
	var player = get_tree().get_first_node_in_group("xr_player")
	if player:
		movement_component = player.get_node_or_null("PlayerMovementComponent")
		xr_player = player
		player_body = player.get_node_or_null("PlayerBody") as RigidBody3D
	
	if movement_component:
		_setup_ui()
	else:
		print("UIPanel: Could not find PlayerMovementComponent")

func _setup_ui() -> void:
	# Clear all previously added children
	for c in vbox_turn.get_children():
		c.queue_free()
	for c in vbox_player.get_children():
		c.queue_free()
	# Make a bit denser
	if vbox_turn:
		vbox_turn.add_theme_constant_override("separation", 6)
	if vbox_player:
		vbox_player.add_theme_constant_override("separation", 6)
			
	# Add Turn Mode (Snap/Smooth)
	var mode_h = HBoxContainer.new()
	var mode_label = Label.new()
	mode_label.text = "Turn Mode"
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_h.add_child(mode_label)

	var mode_button = OptionButton.new()
	mode_button.add_item("Snap")
	mode_button.add_item("Smooth")
	mode_button.selected = movement_component.turn_mode
	mode_button.item_selected.connect(_on_mode_selected)
	mode_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mode_h.add_child(mode_button)
	vbox_turn.add_child(mode_h)
	
	# Add Snap Angle
	var snap_h = HBoxContainer.new()
	var snap_label = Label.new()
	snap_label.text = "Snap Angle: " + str(movement_component.snap_turn_angle)
	snap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	snap_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	snap_h.add_child(snap_label)

	var snap_slider = HSlider.new()
	snap_slider.min_value = 15
	snap_slider.max_value = 90
	snap_slider.step = 15
	snap_slider.value = movement_component.snap_turn_angle
	snap_slider.value_changed.connect(func(val): 
		_on_snap_angle_changed(val, snap_label)
	)
	snap_h.add_child(snap_slider)
	vbox_turn.add_child(snap_h)
	
	# Add Smooth Speed
	var smooth_h = HBoxContainer.new()
	var smooth_label = Label.new()
	smooth_label.text = "Smooth Speed: " + str(movement_component.smooth_turn_speed)
	smooth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	smooth_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	smooth_h.add_child(smooth_label)

	var smooth_slider = HSlider.new()
	smooth_slider.min_value = 10
	smooth_slider.max_value = 360
	smooth_slider.step = 10
	smooth_slider.value = movement_component.smooth_turn_speed
	smooth_slider.value_changed.connect(func(val):
		_on_smooth_speed_changed(val, smooth_label)
	)
	smooth_h.add_child(smooth_slider)
	vbox_turn.add_child(smooth_h)

	# Add Deadzone
	var deadzone_h = HBoxContainer.new()
	var deadzone_label = Label.new()
	deadzone_label.text = "Deadzone: " + str(movement_component.turn_deadzone)
	deadzone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	deadzone_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deadzone_h.add_child(deadzone_label)

	var deadzone_slider = HSlider.new()
	deadzone_slider.min_value = 0.0
	deadzone_slider.max_value = 1.0
	deadzone_slider.step = 0.05
	deadzone_slider.value = movement_component.turn_deadzone
	deadzone_slider.value_changed.connect(func(val):
		_on_deadzone_changed(val, deadzone_label)
	)
	deadzone_h.add_child(deadzone_slider)
	vbox_turn.add_child(deadzone_h)

	# Add Snap Cooldown
	var cooldown_h = HBoxContainer.new()
	var cooldown_label = Label.new()
	cooldown_label.text = "Snap Cooldown: " + str(movement_component.snap_turn_cooldown)
	cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	cooldown_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cooldown_h.add_child(cooldown_label)

	var cooldown_slider = HSlider.new()
	cooldown_slider.min_value = 0.1
	cooldown_slider.max_value = 1.0
	cooldown_slider.step = 0.1
	cooldown_slider.value = movement_component.snap_turn_cooldown
	cooldown_slider.value_changed.connect(func(val):
		_on_cooldown_changed(val, cooldown_label)
	)
	cooldown_h.add_child(cooldown_slider)
	vbox_turn.add_child(cooldown_h)

	# Add Player Scale
	var scale_h = HBoxContainer.new()
	var scale_label = Label.new()
	var initial_scale = 1.0
	if player_body:
		initial_scale = player_body.scale.x
	scale_label.text = "Player Scale: " + str(initial_scale)
	scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	scale_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_h.add_child(scale_label)

	var scale_slider = HSlider.new()
	scale_slider.min_value = 0.25
	scale_slider.max_value = 3.0
	scale_slider.step = 0.05
	scale_slider.value = initial_scale
	scale_slider.value_changed.connect(func(val):
		_on_player_scale_changed(val, scale_label)
	)
	scale_h.add_child(scale_slider)
	vbox_player.add_child(scale_h)

	# Set tab titles if we have a TabContainer (Turn and Player)
	if tab and tab.get_child_count() >= 2:
		tab.set_tab_title(0, "Turn")
		tab.set_tab_title(1, "Player")

func _on_mode_selected(index: int) -> void:
	if movement_component:
		movement_component.turn_mode = index as PlayerMovementComponent.TurnMode

func _on_snap_angle_changed(value: float, label: Label) -> void:
	if movement_component:
		movement_component.snap_turn_angle = value
		label.text = "Snap Angle: " + str(value)

func _on_smooth_speed_changed(value: float, label: Label) -> void:
	if movement_component:
		movement_component.smooth_turn_speed = value
		label.text = "Smooth Speed: " + str(value)

func _on_deadzone_changed(value: float, label: Label) -> void:
	if movement_component:
		movement_component.turn_deadzone = value
		label.text = "Deadzone: " + str(value)

func _on_cooldown_changed(value: float, label: Label) -> void:
	if movement_component:
		movement_component.snap_turn_cooldown = value
		label.text = "Snap Cooldown: " + str(value)

func _on_player_scale_changed(value: float, label: Label) -> void:
	# Apply uniform scale to the player's body
	if player_body:
		player_body.scale = Vector3(value, value, value)
		label.text = "Player Scale: " + str(value)
	else:
		print("UIPanel: Cannot change player scale, PlayerBody not found")
