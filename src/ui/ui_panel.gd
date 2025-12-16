extends Control

@onready var tab = $TabContainer
@onready var vbox_panels = $TabContainer/PanelsScroll/PanelsVBox
@onready var vbox_general = $TabContainer/GeneralScroll/GeneralVBox
@onready var vbox_movement = $TabContainer/MovementScroll/MovementVBox
@onready var vbox_multiplayer = $TabContainer/MultiplayerScroll/MultiplayerVBox

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

const MAIN_SCENE_PATH := "res://src/levels/MainScene.tscn"
const UIPanelManager = preload("res://src/ui/ui_panel_manager.gd")

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
	
	# Clear default test children from all tabs
	for c in vbox_panels.get_children():
		c.queue_free()
	for c in vbox_general.get_children():
		c.queue_free()
	for c in vbox_movement.get_children():
		c.queue_free()
	for c in vbox_multiplayer.get_children():
		c.queue_free()
	
	# Ensure all tabs are visible once populated
	var all_vboxes = [vbox_panels, vbox_general, vbox_movement, vbox_multiplayer]
	for vbox in all_vboxes:
		if vbox:
			vbox.visible = true
			var parent: Node = vbox.get_parent()
			if parent:
				parent.visible = true
			# Make a bit denser
			vbox.add_theme_constant_override("separation", 8)
	
	# === PANELS TAB ===
	_setup_panels_tab()
	
	# === GENERAL SETTINGS TAB ===
	_setup_general_tab()
	
	# === MOVEMENT TAB ===
	_setup_movement_tab()
	
	# === MULTIPLAYER TAB ===
	_setup_multiplayer_tab()

	# Set tab titles
	if tab and tab.get_child_count() >= 4:
		tab.set_tab_title(0, "Panels")
		tab.set_tab_title(1, "General")
		tab.set_tab_title(2, "Movement")
		tab.set_tab_title(3, "Multiplayer")

func _setup_panels_tab() -> void:
	"""Setup the Panels tab with quick access to all UI panels"""
	var title_label = Label.new()
	title_label.text = "Quick Panel Access"
	title_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox_panels.add_child(title_label)
	
	_add_separator(vbox_panels)

	var quick_panels := [
		{"label": "⚡ Performance Settings", "node": "PerformancePanelViewport3D"},
		{"label": "Movement Settings", "node": "MovementSettingsViewport3D2"},
		{"label": "Keyboard", "node": "KeyboardFullViewport3D"},
		{"label": "File System", "node": "FileSystemViewport3D"},
		{"label": "Scene Hierarchy", "node": "SceneHierarchyViewport3D"},
		{"label": "Node Inspector", "node": "NodeInspectorViewport3D"},
		{"label": "Script Editor", "node": "ScriptEditorViewport3D"},
		{"label": "Debug Console", "node": "DebugConsoleViewport3D"},
		{"label": "Git Tracker", "node": "GitViewport3D"},
		{"label": "Multiplayer Panel", "node": "UnifiedRoomViewport3D"},
		{"label": "LiveKit Settings", "node": "LiveKitViewport3D"},
		{"label": "Legal Panel", "node": "LegalViewport3D"},
		{"label": "Color Picker", "node": "ColorPickerViewport3D"},
		{"label": "Poly Tool Export", "node": "PolyToolViewport3D"},
	]
	
	for entry in quick_panels:
		var btn := Button.new()
		btn.text = "📋 " + entry.get("label", "")
		btn.custom_minimum_size = Vector2(0, 35)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var target_node: String = entry.get("node", "")
		btn.pressed.connect(func(node_name := target_node): _move_ui_node_in_front(node_name))
		vbox_panels.add_child(btn)

func _setup_general_tab() -> void:
	"""Setup the General Settings tab with player scale, respawn, passthrough, and scene management"""
	# Player Scale Section
	var scale_section = Label.new()
	scale_section.text = "Player Scale"
	scale_section.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	vbox_general.add_child(scale_section)
	
	var scale_container = VBoxContainer.new()
	var scale_label = Label.new()
	var initial_scale = 1.0
	if player_body:
		initial_scale = player_body.scale.x
	scale_label.text = "Scale: %.2fx" % initial_scale
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
	
	# Step Control
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
	vbox_general.add_child(scale_container)

	_add_separator(vbox_general)

	# Respawn Section
	var respawn_btn = Button.new()
	respawn_btn.text = "🔄 Respawn Player"
	respawn_btn.custom_minimum_size = Vector2(0, 40)
	respawn_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	respawn_btn.pressed.connect(_on_respawn_pressed)
	vbox_general.add_child(respawn_btn)
	
	_add_separator(vbox_general)
	
	# Environment / Passthrough Section
	var env_label = Label.new()
	env_label.text = "Environment"
	env_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	vbox_general.add_child(env_label)
	
	passthrough_check = CheckBox.new()
	passthrough_check.text = "Skybox Passthrough (Quest 3)"
	passthrough_check.tooltip_text = "Uses OpenXR alpha-blend to reveal passthrough video. Only supported on devices like Quest 3."
	passthrough_check.toggled.connect(func(pressed): _on_passthrough_toggled(pressed))
	vbox_general.add_child(passthrough_check)
	
	passthrough_status = Label.new()
	passthrough_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	passthrough_status.text = "Skybox status pending..."
	vbox_general.add_child(passthrough_status)
	_update_passthrough_ui_state()

	_add_separator(vbox_general)
	
	# Scene Management Section
	var scene_label = Label.new()
	scene_label.text = "Scene Management"
	scene_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	vbox_general.add_child(scene_label)

	var return_main_btn = Button.new()
	return_main_btn.text = "🏠 Return to Main Scene"
	return_main_btn.custom_minimum_size = Vector2(0, 40)
	return_main_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return_main_btn.pressed.connect(_on_return_to_main_scene_pressed)
	vbox_general.add_child(return_main_btn)

func _setup_movement_tab() -> void:
	"""Setup the Movement tab with turning settings and world grab toggle"""
	# Turn Mode Section
	var turn_section = Label.new()
	turn_section.text = "Turning"
	turn_section.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	vbox_movement.add_child(turn_section)
	
	# Turn Mode (Snap/Smooth)
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
	vbox_movement.add_child(mode_h)
	
	_add_separator(vbox_movement)
	
	# Snap Turn Settings
	var snap_section = Label.new()
	snap_section.text = "Snap Turn Settings"
	snap_section.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	vbox_movement.add_child(snap_section)
	
	# Snap Angle
	var snap_container = VBoxContainer.new()
	var snap_label = Label.new()
	snap_label.text = "Angle: %.0f°" % movement_component.snap_turn_angle
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
	vbox_movement.add_child(snap_container)
	
	# Snap Cooldown
	var cooldown_container = VBoxContainer.new()
	var cooldown_label = Label.new()
	cooldown_label.text = "Cooldown: %.2fs" % movement_component.snap_turn_cooldown
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
	vbox_movement.add_child(cooldown_container)
	
	_add_separator(vbox_movement)
	
	# Smooth Turn Settings
	var smooth_section = Label.new()
	smooth_section.text = "Smooth Turn Settings"
	smooth_section.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	vbox_movement.add_child(smooth_section)
	
	# Smooth Speed
	var smooth_container = VBoxContainer.new()
	var smooth_label = Label.new()
	smooth_label.text = "Speed: %.0f°/sec" % movement_component.smooth_turn_speed
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
	vbox_movement.add_child(smooth_container)
	
	_add_separator(vbox_movement)
	
	# Input Settings
	var input_section = Label.new()
	input_section.text = "Input Settings"
	input_section.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	vbox_movement.add_child(input_section)
	
	# Deadzone
	var deadzone_container = VBoxContainer.new()
	var deadzone_label = Label.new()
	deadzone_label.text = "Deadzone: %.2f" % movement_component.turn_deadzone
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
	vbox_movement.add_child(deadzone_container)

	_add_separator(vbox_movement)
	
	# World Grab Settings
	var grab_section = Label.new()
	grab_section.text = "World Interaction"
	grab_section.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	vbox_movement.add_child(grab_section)
	
	# Two-Hand World Grab Toggle
	var world_grab_check = CheckBox.new()
	world_grab_check.text = "Two-Hand World Grab (V3)"
	world_grab_check.button_pressed = movement_component.enable_two_hand_grab_v3
	world_grab_check.tooltip_text = "Enable two-hand world grab using XRTools algorithm. Hold both triggers to grab and manipulate the world."
	world_grab_check.toggled.connect(_on_world_grab_toggled)
	vbox_movement.add_child(world_grab_check)

func _setup_multiplayer_tab() -> void:
	"""Setup the Multiplayer tab for future multiplayer features"""
	var title_label = Label.new()
	title_label.text = "Multiplayer Features"
	title_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox_multiplayer.add_child(title_label)
	
	_add_separator(vbox_multiplayer)
	
	# Placeholder content
	var info_label = Label.new()
	info_label.text = "🚧 Multiplayer features are in development"
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6))
	vbox_multiplayer.add_child(info_label)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox_multiplayer.add_child(spacer)
	
	# Quick access to existing multiplayer panels
	var livekit_btn = Button.new()
	livekit_btn.text = "🎤 LiveKit Settings"
	livekit_btn.custom_minimum_size = Vector2(0, 40)
	livekit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	livekit_btn.pressed.connect(func(): _move_ui_node_in_front("LiveKitViewport3D"))
	vbox_multiplayer.add_child(livekit_btn)
	
	var room_btn = Button.new()
	room_btn.text = "🌐 Room Management"
	room_btn.custom_minimum_size = Vector2(0, 40)
	room_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_btn.pressed.connect(func(): _move_ui_node_in_front("UnifiedRoomViewport3D"))
	vbox_multiplayer.add_child(room_btn)
	
	# Future features (disabled for now)
	_add_separator(vbox_multiplayer)
	
	var future_label = Label.new()
	future_label.text = "Coming Soon:"
	future_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	vbox_multiplayer.add_child(future_label)
	
	var features = [
		"👥 Player List & Management",
		"🎮 Shared World Controls", 
		"💬 Voice Chat Settings",
		"🔒 Room Privacy Controls",
		"📊 Network Statistics"
	]
	
	for feature in features:
		var feature_btn = Button.new()
		feature_btn.text = feature
		feature_btn.disabled = true
		feature_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox_multiplayer.add_child(feature_btn)

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
		label.text = "Angle: %.0f°" % value

func _on_smooth_speed_changed(value: float, label: Label) -> void:
	if movement_component:
		movement_component.smooth_turn_speed = value
		label.text = "Speed: %.0f°/sec" % value

func _on_deadzone_changed(value: float, label: Label) -> void:
	if movement_component:
		movement_component.turn_deadzone = value
		label.text = "Deadzone: %.2f" % value

func _on_cooldown_changed(value: float, label: Label) -> void:
	if movement_component:
		movement_component.snap_turn_cooldown = value
		label.text = "Cooldown: %.2fs" % value

func _on_world_grab_toggled(enabled: bool) -> void:
	if movement_component:
		movement_component.enable_two_hand_grab_v3 = enabled

func _on_player_scale_changed(value: float, label: Label) -> void:
	# Apply uniform scale to the player's rig (body, hands, head)
	if xr_player and xr_player.has_method("set_player_scale"):
		xr_player.set_player_scale(value)
		label.text = "Player Scale: %.2fx" % value
	elif player_body:
		player_body.scale = Vector3(value, value, value)
		label.text = "Player Scale: %.2fx" % value
		if movement_component and movement_component.has_method("set_manual_player_scale"):
			movement_component.set_manual_player_scale(value)
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
	
	if xr_player and xr_player.has_method("set_player_scale"):
		xr_player.set_player_scale(new_scale)
	else:
		player_body.scale = Vector3(new_scale, new_scale, new_scale)
		if movement_component and movement_component.has_method("set_manual_player_scale"):
			movement_component.set_manual_player_scale(new_scale)
	label.text = "Scale: %.2fx" % new_scale


func _on_respawn_pressed() -> void:
	if movement_component:
		movement_component.respawn(movement_component.hard_respawn_resets_settings)


func _on_return_to_main_scene_pressed() -> void:
	var target_scene := MAIN_SCENE_PATH
	var player_state := {
		"use_spawn_point": true,
		"spawn_point": "SpawnPoint",
	}
	if GameManager and GameManager.has_method("change_scene_with_player"):
		GameManager.call_deferred("change_scene_with_player", target_scene, player_state)
	else:
		get_tree().call_deferred("change_scene_to_file", target_scene)


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
		_xr_interface.environment_blend_mode = mode as XRInterface.EnvironmentBlendMode


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


func _move_ui_node_in_front(node_name: String, _distance: float = 1.6, _height_offset: float = 0.0) -> void:
	"""Open a UI panel using the UIPanelManager (handles max panels, distance culling, etc.)"""
	var manager := UIPanelManager.find()
	if manager:
		manager.open_panel(node_name, true)
	else:
		# Fallback: create manager if it doesn't exist
		_create_panel_manager_and_open(node_name)


func _create_panel_manager_and_open(node_name: String) -> void:
	"""Create a UIPanelManager if one doesn't exist, then open the panel."""
	var scene_root: Node = get_tree().current_scene
	if not scene_root:
		var gm: Node = get_tree().root.get_node_or_null("GameManager")
		if gm and gm.has_method("get") and gm.get("current_world"):
			scene_root = gm.get("current_world")
	
	if not scene_root:
		print("UIPanel: Cannot create UIPanelManager - no scene root")
		return
	
	# Check if manager already exists
	var existing := scene_root.get_node_or_null("UIPanelManager")
	if existing and existing is UIPanelManager:
		(existing as UIPanelManager).open_panel(node_name, true)
		return
	
	# Create new manager
	var manager := UIPanelManager.new()
	manager.name = "UIPanelManager"
	scene_root.add_child(manager)
	print("UIPanel: Created UIPanelManager")
	
	# Open the panel
	manager.open_panel(node_name, true)
