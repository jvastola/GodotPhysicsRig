extends Control

const HAND_CHILD_PATHS := {
	"Left": NodePath("PhysicsHandLeft"),
	"Right": NodePath("PhysicsHandRight"),
}

const PROPERTY_CONFIGS := [
	{"id": "frequency", "label": "Move Frequency", "min": 1.0, "max": 200.0, "step": 0.5},
	{"id": "damping", "label": "Move Damping", "min": 0.0, "max": 5.0, "step": 0.01},
	{"id": "rot_frequency", "label": "Rotation Frequency", "min": 10.0, "max": 5000.0, "step": 10.0},
	{"id": "rot_damping", "label": "Rotation Damping", "min": 0.0, "max": 20.0, "step": 0.05},
	{"id": "climb_force", "label": "Climb Force", "min": 0.0, "max": 5000.0, "step": 10.0},
	{"id": "climb_drag", "label": "Climb Drag", "min": 0.0, "max": 200.0, "step": 1.0},
	{"id": "max_spring_force", "label": "Max Spring Force", "min": 100.0, "max": 8000.0, "step": 10.0},
	{"id": "max_player_velocity", "label": "Max Player Velocity", "min": 0.5, "max": 30.0, "step": 0.1},
]

var _hands: Dictionary = {}
var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _slider_steps: Dictionary = {}
var _status_label: Label
var _player_root: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	call_deferred("_refresh_hands_and_values")


func _process(_delta: float) -> void:
	if _player_root == null or _hands.size() != HAND_CHILD_PATHS.size() or not _has_all_hand_refs():
		_refresh_hands_and_values()


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.name = "PhysicsHandTunerPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 16.0
	panel.offset_top = 16.0
	panel.custom_minimum_size = Vector2(400.0, 640.0)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(root_vbox)

	var title := Label.new()
	title.text = "Physics Hand Tuner"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(title)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_vbox.add_child(_status_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(scroll)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)

	for hand_name in HAND_CHILD_PATHS.keys():
		_add_hand_section(content, hand_name)


func _add_hand_section(parent: VBoxContainer, hand_name: String) -> void:
	var hand_title := Label.new()
	hand_title.text = "%s Hand" % hand_name
	parent.add_child(hand_title)

	for config in PROPERTY_CONFIGS:
		var property_name: String = config["id"]
		var label_text: String = config["label"]
		var min_value: float = config["min"]
		var max_value: float = config["max"]
		var step: float = config["step"]
		var key := _get_key(hand_name, property_name)

		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		parent.add_child(row)

		var value_label := Label.new()
		value_label.text = "%s: --" % label_text
		row.add_child(value_label)
		_value_labels[key] = value_label
		_slider_steps[key] = step

		var slider := HSlider.new()
		slider.min_value = min_value
		slider.max_value = max_value
		slider.step = step
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_on_slider_value_changed.bind(hand_name, property_name, label_text))
		row.add_child(slider)
		_sliders[key] = slider


func _refresh_hands_and_values() -> void:
	_hands.clear()
	_player_root = get_tree().get_first_node_in_group("xr_player")
	if _player_root:
		for hand_name in HAND_CHILD_PATHS.keys():
			var hand_path: NodePath = HAND_CHILD_PATHS[hand_name]
			_hands[hand_name] = _player_root.get_node_or_null(hand_path)

	var missing: Array[String] = []
	for hand_name in HAND_CHILD_PATHS.keys():
		var hand: Node = _hands.get(hand_name)
		if hand == null:
			missing.append(hand_name)

	if _player_root == null:
		_status_label.text = "Waiting for XRPlayer..."
	elif missing.is_empty():
		_status_label.text = "Connected. Tune sliders live in world-space panel."
	else:
		_status_label.text = "Missing hand nodes: %s" % ", ".join(missing)

	for hand_name in HAND_CHILD_PATHS.keys():
		var hand: Node = _hands.get(hand_name)
		if hand == null:
			continue
		for config in PROPERTY_CONFIGS:
			var property_name: String = config["id"]
			var label_text: String = config["label"]
			var key := _get_key(hand_name, property_name)
			var slider: HSlider = _sliders.get(key)
			if slider == null:
				continue
			var value := float(hand.get(property_name))
			slider.set_value_no_signal(value)
			_update_row_label(hand_name, property_name, label_text, value)


func _on_slider_value_changed(value: float, hand_name: String, property_name: String, label_text: String) -> void:
	var hand: Node = _hands.get(hand_name)
	if hand == null or not is_instance_valid(hand):
		_refresh_hands_and_values()
		hand = _hands.get(hand_name)
	if hand != null and is_instance_valid(hand):
		hand.set(property_name, value)
		_update_row_label(hand_name, property_name, label_text, value)


func _update_row_label(hand_name: String, property_name: String, label_text: String, value: float) -> void:
	var key := _get_key(hand_name, property_name)
	var label: Label = _value_labels.get(key)
	if label == null:
		return
	var step := float(_slider_steps.get(key, 0.01))
	label.text = "%s: %s" % [label_text, _format_value(value, step)]


func _format_value(value: float, step: float) -> String:
	if step >= 1.0:
		return str(int(round(value)))
	if step >= 0.1:
		return "%0.1f" % value
	if step >= 0.01:
		return "%0.2f" % value
	return "%0.3f" % value


func _get_key(hand_name: String, property_name: String) -> String:
	return "%s/%s" % [hand_name, property_name]


func _has_all_hand_refs() -> bool:
	for hand_name in HAND_CHILD_PATHS.keys():
		var hand: Node = _hands.get(hand_name)
		if hand == null or not is_instance_valid(hand):
			return false
	return true
