extends Control

signal close_requested

# Use explicit node paths (no unique-name flags set on the scene nodes).
@onready var action_list: VBoxContainer = $Panel/VBox/ScrollContainer/ActionList
@onready var summary_label: Label = $Panel/VBox/Header/SummaryLabel
@onready var refresh_button: Button = $Panel/VBox/Header/RefreshButton
@onready var close_button: Button = $Panel/VBox/Header/CloseButton

# Map of actions to the places we use them in code.
# This is hand-authored so the UI can show "where used" information without
# scanning the whole project at runtime.
const ACTION_USAGE := {
	"move_forward": [
		"Desktop movement: _physics_process in desktop_controller.gd"
	],
	"move_backward": [
		"Desktop movement: _physics_process in desktop_controller.gd"
	],
	"move_left": [
		"Desktop movement: _physics_process in desktop_controller.gd"
	],
	"move_right": [
		"Desktop movement: _physics_process in desktop_controller.gd"
	],
	"jump": [
		"Desktop movement jump: desktop_controller.gd",
		"XR player jump impulse: player_movement_component.gd"
	],
	"sprint": [
		"Desktop sprint speed multiplier: desktop_controller.gd"
	],
	"build_mode_toggle": [
		"Toggle build mode: grid_snap_indicator.gd"
	],
	"pickup_left": [
		"Desktop left-hand pickup/drop: desktop_controller.gd"
	],
	"pickup_right": [
		"Desktop right-hand pickup/drop: desktop_controller.gd"
	],
	"ui_select": [
		"Desktop: recapture mouse when clicked: desktop_controller.gd"
	],
	"ui_cancel": [
		"Desktop: toggle mouse capture on ESC: desktop_controller.gd"
	],
	"trigger_click": [
		"XR grabbables: ConvexHullPen, VolumeHullPen, TrianglePointTool, PolyTool, GrappleHook",
		"Grid build trigger when using XR controller: grid_snap_indicator.gd",
		"Legal intro continue prompt: legal_intro.gd"
	],
	"grip_click": [
		"XR grabbables secondary/erase input: PolyTool, TrianglePointTool",
		"Build/remove toggle while building voxels: grid_snap_indicator.gd"
	]
}


func _ready() -> void:
	if refresh_button:
		refresh_button.pressed.connect(_populate_action_list)
	if close_button:
		close_button.pressed.connect(func(): close_requested.emit())
	_populate_action_list()


func _populate_action_list() -> void:
	_clear_action_list()
	var actions: Array = InputMap.get_actions()
	actions.sort()

	# Include any usage-only actions that are not currently in InputMap.
	for action in ACTION_USAGE.keys():
		if not actions.has(action):
			actions.append(action)
	actions.sort()

	for action_name in actions:
		var events := []
		var is_defined: bool = InputMap.has_action(action_name)
		if is_defined:
			for ev in InputMap.action_get_events(action_name):
				events.append(_event_to_text(ev))
		var usages: Array = ACTION_USAGE.get(action_name, [])
		_add_action_card(action_name, events, usages, is_defined)

	if summary_label:
		var defined_count := 0
		for action_name in actions:
			if InputMap.has_action(action_name):
				defined_count += 1
		var extra_count := actions.size() - defined_count
		summary_label.text = "Actions: %d (InputMap %d, extra usage-only %d)" % [actions.size(), defined_count, extra_count]


func _clear_action_list() -> void:
	if not action_list:
		return
	for child in action_list.get_children():
		child.queue_free()


func _add_action_card(action_name: String, events: Array, usages: Array, is_defined: bool) -> void:
	if not action_list:
		return

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.custom_minimum_size = Vector2(0, 60)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = action_name
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	if not is_defined:
		var warn := Label.new()
		warn.text = "Not in InputMap"
		warn.modulate = Color(1, 0.75, 0.3)
		header.add_child(warn)

	vb.add_child(header)

	var events_label := RichTextLabel.new()
	events_label.fit_content = true
	events_label.scroll_active = false
	events_label.bbcode_enabled = true
	events_label.text = _format_events_text(events, is_defined)
	events_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(events_label)

	var usage_label := RichTextLabel.new()
	usage_label.fit_content = true
	usage_label.scroll_active = false
	usage_label.bbcode_enabled = true
	usage_label.text = _format_usage_text(usages)
	usage_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(usage_label)

	panel.add_child(vb)
	action_list.add_child(panel)


func _format_events_text(events: Array, is_defined: bool) -> String:
	if not is_defined:
		return "[i]Action is referenced in code but not registered in the Input Map.[/i]"
	if events.is_empty():
		return "[i]No bindings assigned.[/i]"
	var clean: Array = []
	for ev in events:
		clean.append(str(ev))
	return "[b]Bindings:[/b] " + ", ".join(clean)


func _format_usage_text(usages: Array) -> String:
	if usages.is_empty():
		return "[b]Used in:[/b] (not documented yet)"
	var bullets: Array = []
	for usage in usages:
		bullets.append("• " + usage)
	return "[b]Used in:[/b]\n" + "\n".join(bullets)


func _event_to_text(event: InputEvent) -> String:
	if event is InputEventKey:
		var ev_key := event as InputEventKey
		var keycode := ev_key.physical_keycode if ev_key.physical_keycode != 0 else ev_key.keycode
		var key_name := OS.get_keycode_string(keycode)
		var mods: Array = []
		if ev_key.ctrl_pressed:
			mods.append("Ctrl")
		if ev_key.alt_pressed:
			mods.append("Alt")
		if ev_key.shift_pressed:
			mods.append("Shift")
		if ev_key.meta_pressed:
			mods.append("Meta")
		var prefix := ""
		if not mods.is_empty():
			prefix = "+".join(mods) + "+"
		return prefix + key_name
	elif event is InputEventMouseButton:
		var ev_mouse := event as InputEventMouseButton
		match ev_mouse.button_index:
			MOUSE_BUTTON_LEFT:
				return "Mouse Left"
			MOUSE_BUTTON_RIGHT:
				return "Mouse Right"
			MOUSE_BUTTON_MIDDLE:
				return "Mouse Middle"
			MOUSE_BUTTON_WHEEL_UP:
				return "Mouse Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "Mouse Wheel Down"
			_:
				return "Mouse Button %d" % ev_mouse.button_index
	elif event is InputEventJoypadButton:
		var ev_btn := event as InputEventJoypadButton
		return "Joy Button %d" % ev_btn.button_index
	elif event is InputEventJoypadMotion:
		var ev_axis := event as InputEventJoypadMotion
		return "Joy Axis %d (%.2f)" % [ev_axis.axis, ev_axis.axis_value]

	# Fallback to the built-in text for any other InputEvent types
	return event.as_text()
