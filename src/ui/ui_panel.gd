extends Control

@onready var tab = $TabContainer
@onready var vbox_turn = $TabContainer/TurnVBox
@onready var vbox_player = $TabContainer/PlayerVBox

var movement_component: PlayerMovementComponent
var player_body: RigidBody3D
var xr_player: Node = null
var passthrough_check: CheckBox
var passthrough_status: Label

var _xr_interface: XRInterface
var _world_environment: WorldEnvironment
var _world_env_snapshot: Dictionary = {}
var _root_viewport: Viewport
var _viewport_transparent_default: bool = false

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
	
	_xr_interface = XRServer.find_interface("OpenXR")
	_root_viewport = get_tree().root
	if _root_viewport:
		_viewport_transparent_default = _root_viewport.transparent_bg
	_find_world_environment()
	
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

	var respawn_btn = Button.new()
	respawn_btn.text = "Respawn (hard setting)"
	respawn_btn.custom_minimum_size = Vector2(0, 40)
	respawn_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	respawn_btn.pressed.connect(_on_respawn_pressed)
	vbox_player.add_child(respawn_btn)
	
	# Environment / Passthrough (Quest 3)
	_add_separator(vbox_player)
	var env_label = Label.new()
	env_label.text = "Environment"
	env_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	vbox_player.add_child(env_label)
	
	passthrough_check = CheckBox.new()
	passthrough_check.text = "Skybox Passthrough (Meta Quest 3)"
	passthrough_check.tooltip_text = "Uses OpenXR alpha-blend to reveal passthrough video. Only supported on devices like Quest 3."
	passthrough_check.toggled.connect(func(pressed): _on_passthrough_toggled(pressed))
	vbox_player.add_child(passthrough_check)
	
	passthrough_status = Label.new()
	passthrough_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	passthrough_status.text = "Skybox status pending..."
	vbox_player.add_child(passthrough_status)
	_update_passthrough_ui_state()

	# Quick panel buttons to bring UI in front of player
	_add_separator(vbox_player)
	var quick_label = Label.new()
	quick_label.text = "Quick Panels"
	quick_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	vbox_player.add_child(quick_label)

	var btn_move_movement = Button.new()
	btn_move_movement.text = "Move Movement Settings in Front"
	btn_move_movement.pressed.connect(func(): _move_ui_node_in_front("MovementSettingsViewport3D2"))
	vbox_player.add_child(btn_move_movement)

	var btn_move_keyboard = Button.new()
	btn_move_keyboard.text = "Move Keyboard in Front"
	btn_move_keyboard.pressed.connect(func(): _move_ui_node_in_front("KeyboardFullViewport3D"))
	vbox_player.add_child(btn_move_keyboard)

	var btn_move_filesystem = Button.new()
	btn_move_filesystem.text = "Move File System in Front"
	btn_move_filesystem.pressed.connect(func(): _move_ui_node_in_front("FileSystemViewport3D"))
	vbox_player.add_child(btn_move_filesystem)

	var btn_move_hierarchy = Button.new()
	btn_move_hierarchy.text = "Move Scene Hierarchy in Front"
	btn_move_hierarchy.pressed.connect(func(): _move_ui_node_in_front("SceneHierarchyViewport3D"))
	vbox_player.add_child(btn_move_hierarchy)

	var btn_move_debug = Button.new()
	btn_move_debug.text = "Move Debug Window in Front"
	btn_move_debug.pressed.connect(func(): _move_ui_node_in_front("DebugConsoleViewport3D"))
	vbox_player.add_child(btn_move_debug)

	var btn_move_git = Button.new()
	btn_move_git.text = "Move Git Tracker in Front"
	btn_move_git.pressed.connect(func(): _move_ui_node_in_front("GitViewport3D"))
	vbox_player.add_child(btn_move_git)

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

func _on_apply_scale_change(delta_sign: int, label: Label) -> void:
	if not player_body:
		return
		
	var current_scale = player_body.scale.x
	var change_amount = (scale_step_percent / 100.0) * delta_sign
	var new_scale = clampf(current_scale + change_amount, 0.25, 3.0)
	
	player_body.scale = Vector3(new_scale, new_scale, new_scale)
	label.text = "Player Scale: %.2fx" % new_scale


func _on_respawn_pressed() -> void:
	if movement_component:
		movement_component.respawn(movement_component.hard_respawn_resets_settings)


func _on_passthrough_toggled(enabled: bool) -> void:
	_apply_passthrough_enabled(enabled)
	_update_passthrough_ui_state()


func _find_world_environment() -> void:
	if _world_environment:
		return
	var root := get_tree().root
	if not root:
		return
	var env_node := root.find_child("WorldEnvironment", true, false)
	if env_node and env_node is WorldEnvironment:
		_world_environment = env_node
		if _world_environment.environment and _world_env_snapshot.is_empty():
			var env := _world_environment.environment
			_world_env_snapshot = {
				"background_mode": env.background_mode,
				"background_color": env.background_color,
				"sky": env.sky,
			}


func _supports_alpha_passthrough() -> bool:
	if not _xr_interface:
		return false
	if _xr_interface.has_method("get_supported_environment_blend_modes"):
		var supported: PackedInt32Array = _xr_interface.get_supported_environment_blend_modes()
		return XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in supported
	# Assume supported when the runtime does not expose the query
	return true


func _current_blend_mode() -> int:
	if not _xr_interface:
		return -1
	if _xr_interface.has_method("get_environment_blend_mode"):
		return _xr_interface.get_environment_blend_mode()
	return _xr_interface.environment_blend_mode


func _set_environment_blend_mode(mode: int) -> void:
	if not _xr_interface:
		return
	if _xr_interface.has_method("set_environment_blend_mode"):
		_xr_interface.set_environment_blend_mode(mode)
	else:
		_xr_interface.environment_blend_mode = mode


func _apply_passthrough_enabled(enabled: bool) -> void:
	if not _xr_interface:
		_update_passthrough_status("OpenXR not available")
		if passthrough_check:
			passthrough_check.button_pressed = false
		return
	if enabled and not _supports_alpha_passthrough():
		_update_passthrough_status("Alpha blend not supported by runtime")
		if passthrough_check:
			passthrough_check.button_pressed = false
		return
	
	var target_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND if enabled else XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	_set_environment_blend_mode(target_mode)
	
	if _root_viewport:
		_root_viewport.transparent_bg = true if enabled else _viewport_transparent_default
	
	if _world_environment and _world_environment.environment:
		var env := _world_environment.environment
		if _world_env_snapshot.is_empty():
			_world_env_snapshot = {
				"background_mode": env.background_mode,
				"background_color": env.background_color,
				"sky": env.sky,
			}
		if enabled:
			env.background_mode = Environment.BG_CLEAR_COLOR
			env.background_color = Color(0, 0, 0, 0)
		else:
			env.background_mode = _world_env_snapshot.get("background_mode", env.background_mode)
			env.background_color = _world_env_snapshot.get("background_color", env.background_color)
			env.sky = _world_env_snapshot.get("sky", env.sky)


func _update_passthrough_status(text: String) -> void:
	if passthrough_status:
		passthrough_status.text = text


func _update_passthrough_ui_state() -> void:
	var xr_ready := _xr_interface and _xr_interface.is_initialized()
	var supported := _supports_alpha_passthrough()
	if passthrough_check:
		passthrough_check.disabled = not xr_ready or not supported
		if not xr_ready:
			passthrough_check.tooltip_text = "Passthrough requires OpenXR to be running."
		elif not supported:
			passthrough_check.tooltip_text = "Runtime does not support alpha blend passthrough."
		else:
			passthrough_check.tooltip_text = "Uses OpenXR alpha-blend to reveal passthrough video. Only supported on devices like Quest 3."
		passthrough_check.button_pressed = xr_ready and supported and _current_blend_mode() == XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	
	if not xr_ready:
		_update_passthrough_status("VR session not active")
	elif not supported:
		_update_passthrough_status("Passthrough not supported by runtime")
	elif _current_blend_mode() == XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND:
		_update_passthrough_status("Passthrough ON (skybox hidden)")
	else:
		_update_passthrough_status("Passthrough OFF (skybox visible)")


func _move_ui_node_in_front(node_name: String, distance: float = 1.6, height_offset: float = 0.0) -> void:
	if not xr_player:
		print("UIPanel: xr_player not found, cannot move UI")
		return
	var camera: XRCamera3D = xr_player.get_node_or_null("PlayerBody/XROrigin3D/XRCamera3D") as XRCamera3D
	if not camera:
		print("UIPanel: camera not found, cannot move UI")
		return
	var ui_node := get_tree().get_current_scene().get_node_or_null(node_name)
	if not ui_node or not (ui_node is Node3D):
		print("UIPanel: node %s not found or not Node3D" % node_name)
		return
	var cam_tf := camera.global_transform
	var forward := -cam_tf.basis.z.normalized()
	var target_origin := cam_tf.origin + forward * distance + Vector3(0, height_offset, 0)
	var xf: Transform3D = ui_node.global_transform
	xf.origin = target_origin
	# Face the camera (only yaw)
	var look_at_target := cam_tf.origin
	var dir := (look_at_target - target_origin)
	dir.y = 0
	if dir.length_squared() > 0.0001:
		dir = dir.normalized()
		xf.basis = Basis().looking_at(dir, Vector3.UP)
	ui_node.global_transform = xf
