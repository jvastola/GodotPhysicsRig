extends Control

signal threshold_changed(new_value: float)
signal test_mic_toggled(enabled: bool)
signal closed

@onready var volume_bar: ProgressBar = $Panel/VBoxContainer/VolumeSection/VolumeBar
@onready var threshold_slider: HSlider = $Panel/VBoxContainer/ThresholdSection/ThresholdSlider
@onready var threshold_value_label: Label = $Panel/VBoxContainer/ThresholdSection/HBoxContainer/ValueLabel
@onready var test_mic_button: CheckButton = $Panel/VBoxContainer/TestMicButton

var _voice_component: Node = null

func setup(voice_component: Node) -> void:
	_voice_component = voice_component
	
	# Initialize UI with current values
	if _voice_component:
		threshold_slider.value = _voice_component.vad_threshold
		threshold_value_label.text = str(_voice_component.vad_threshold)

func _process(_delta: float) -> void:
	if not _voice_component:
		# Try to find local player if not already connected
		var xr_player = get_tree().get_first_node_in_group("xr_player")
		if xr_player:
			var component = xr_player.get_node_or_null("PlayerVoiceComponent")
			if component:
				setup(component)
	
	if not visible or not _voice_component:
		return
		
	# Update volume meter
	# We need to expose current RMS from voice component
	if _voice_component.has_method("get_current_rms"):
		var rms = _voice_component.get_current_rms()
		# Logarithmic scaling for better visualization
		var db = linear_to_db(rms)
		# Map -60dB to 0dB -> 0.0 to 1.0
		var normalized = remap(db, -60.0, 0.0, 0.0, 1.0)
		volume_bar.value = clamp(normalized, 0.0, 1.0)
		
		# Color code: Green = Active, Gray = Below Threshold
		if rms > threshold_slider.value:
			volume_bar.modulate = Color.GREEN
		else:
			volume_bar.modulate = Color.GRAY

func _on_threshold_slider_value_changed(value: float) -> void:
	threshold_value_label.text = str(value).pad_decimals(3)
	threshold_changed.emit(value)
	
	if _voice_component:
		_voice_component.set_vad_threshold(value)

func _on_test_mic_button_toggled(toggled_on: bool) -> void:
	test_mic_toggled.emit(toggled_on)
	# Logic to enable loopback would go here or in parent

func _on_close_button_pressed() -> void:
	closed.emit()
	hide()
