extends Control

signal close_requested

# Two Hand Grab Settings UI
# Controls settings for the TwoHandGrabCube

@onready var scale_slider: HSlider = $Panel/VBoxContainer/ScaleSensitivity/HSlider
@onready var scale_value: Label = $Panel/VBoxContainer/ScaleSensitivity/Value
@onready var rotation_slider: HSlider = $Panel/VBoxContainer/RotationSensitivity/HSlider
@onready var rotation_value: Label = $Panel/VBoxContainer/RotationSensitivity/Value
@onready var smoothing_slider: HSlider = $Panel/VBoxContainer/Smoothing/HSlider
@onready var smoothing_value: Label = $Panel/VBoxContainer/Smoothing/Value
@onready var lock_y_check: CheckBox = $Panel/VBoxContainer/Checks/LockYCheck
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel
@onready var close_button: Button = $Panel/VBoxContainer/TitleRow/CloseButton

var _target_cube: Node = null

func _ready() -> void:
	# Wait for scene to settle
	await get_tree().process_frame
	_find_cube()
	
	if close_button:
		close_button.pressed.connect(func(): close_requested.emit())
	
	if _target_cube:
		scale_slider.value = _target_cube.scale_sensitivity
		scale_value.text = "%.1f" % _target_cube.scale_sensitivity
		
		rotation_slider.value = _target_cube.rotation_sensitivity
		rotation_value.text = "%.1f" % _target_cube.rotation_sensitivity
		
		smoothing_slider.value = _target_cube.smoothing
		smoothing_value.text = "%.1f" % _target_cube.smoothing
		
		# Allow dynamic property access for new prop
		if "lock_y_axis" in _target_cube:
			lock_y_check.button_pressed = _target_cube.lock_y_axis

func _find_cube() -> void:
	var nodes = get_tree().get_nodes_in_group("grabbable")
	for n in nodes:
		if n.get_script() and "two_hand_grab_cube.gd" in n.get_script().resource_path:
			_target_cube = n
			print("SettingsUI: Found TwoHandGrabCube")
			break

func _on_scale_slider_value_changed(value: float) -> void:
	scale_value.text = "%.1f" % value
	if is_instance_valid(_target_cube):
		_target_cube.scale_sensitivity = value

func _on_rotation_slider_value_changed(value: float) -> void:
	rotation_value.text = "%.1f" % value
	if is_instance_valid(_target_cube):
		_target_cube.rotation_sensitivity = value

func _on_smoothing_slider_value_changed(value: float) -> void:
	smoothing_value.text = "%.1f" % value
	if is_instance_valid(_target_cube):
		_target_cube.smoothing = value

func _on_lock_y_toggled(toggled: bool) -> void:
	if is_instance_valid(_target_cube) and "lock_y_axis" in _target_cube:
		_target_cube.lock_y_axis = toggled

func _process(_delta: float) -> void:
	if not is_instance_valid(_target_cube):
		status_label.text = "Status: Cube Not Found"
		status_label.modulate = Color.RED
		if randf() < 0.01: # Try to find it occasionally
			_find_cube()
		return
		
	# Access private property via dynamic access or just check state if we exposed it
	# Since _is_two_hand_grabbing is private-ish (underscore), we can still access it in GDScript
	if _target_cube.get("_is_two_hand_grabbing"):
		status_label.text = "Status: GRABBING"
		status_label.modulate = Color.GREEN
	else:
		status_label.text = "Status: Idle"
		status_label.modulate = Color.WHITE
