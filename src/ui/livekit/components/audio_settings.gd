extends PanelContainer
class_name AudioSettingsPanel
## Audio Settings Panel - Mic control, gain, threshold, device selection

signal mute_toggled(is_muted: bool)
signal gain_changed(db: float)
signal threshold_changed(value: float)
signal audio_buffer_ready(buffer: PackedVector2Array)

# UI References
@onready var mute_button: Button = $VBox/MuteButton
@onready var mic_level_bar: ProgressBar = $VBox/MicLevelBar
@onready var device_container: VBoxContainer = $VBox/DeviceContainer
@onready var gain_slider: HSlider = $VBox/GainSection/GainSlider
@onready var gain_value_label: Label = $VBox/GainSection/HBox/Value
@onready var threshold_slider: HSlider = $VBox/ThresholdSection/ThresholdSlider
@onready var threshold_label: Label = $VBox/ThresholdSection/HBox/Value
@onready var hear_self_check: CheckBox = $VBox/OptionsSection/HearSelfCheck
@onready var play_global_check: CheckBox = $VBox/OptionsSection/PlayGlobalCheck

# Audio state
var input_device_option: OptionButton
var mic_threshold: float = 0.1
var is_muted: bool = false
var hear_own_audio: bool = false
var audio_playback_enabled: bool = false

# Audio resources
const BUFFER_SIZE = 4096
var audio_bus_name = "LiveKit Mic"
var audio_bus_idx = -1
var capture_effect: AudioEffectCapture
var amplify_effect: AudioEffectAmplify
var mic_player: AudioStreamPlayer


func _ready():
	_setup_audio()
	_setup_ui()
	_setup_input_device_selector()
	# Auto-load saved audio settings (Meta VRCS compliance)
	_load_saved_settings()
	# Ensure mic starts after node is fully in tree
	call_deferred("_ensure_mic_playing")


func _setup_ui():
	mute_button.toggled.connect(_on_mute_toggle)
	gain_slider.value_changed.connect(_on_gain_changed)
	threshold_slider.value_changed.connect(_on_threshold_changed)
	hear_self_check.toggled.connect(_on_hear_audio_toggled)
	play_global_check.button_pressed = audio_playback_enabled
	play_global_check.toggled.connect(func(toggled): audio_playback_enabled = toggled)
	
	threshold_slider.value = mic_threshold
	_on_threshold_changed(mic_threshold)


func _setup_audio():
	# Check if our audio bus already exists (from a previous instance)
	audio_bus_idx = AudioServer.get_bus_index(audio_bus_name)
	
	if audio_bus_idx == -1:
		# Create dedicated audio bus only if it doesn't exist
		audio_bus_idx = AudioServer.bus_count
		AudioServer.add_bus(audio_bus_idx)
		AudioServer.set_bus_name(audio_bus_idx, audio_bus_name)
		
		# Add Amplify effect
		amplify_effect = AudioEffectAmplify.new()
		amplify_effect.volume_db = 0.0
		AudioServer.add_bus_effect(audio_bus_idx, amplify_effect)
		
		# Add Capture effect
		capture_effect = AudioEffectCapture.new()
		AudioServer.add_bus_effect(audio_bus_idx, capture_effect)
		
		# Route to Master
		AudioServer.set_bus_send(audio_bus_idx, "Master")
		
	
		print("🎤 AudioSettingsPanel: Created new audio bus '%s'" % audio_bus_name)
	else:
		# Bus exists, get references to existing effects
		print("🎤 AudioSettingsPanel: Reusing existing audio bus '%s' at index %d" % [audio_bus_name, audio_bus_idx])
		
		# Find existing effects on the bus
		for i in range(AudioServer.get_bus_effect_count(audio_bus_idx)):
			var effect = AudioServer.get_bus_effect(audio_bus_idx, i)
			if effect is AudioEffectAmplify:
				amplify_effect = effect
			elif effect is AudioEffectCapture:
				capture_effect = effect
		
		# If effects weren't found, add them
		if not amplify_effect:
			amplify_effect = AudioEffectAmplify.new()
			amplify_effect.volume_db = 0.0
			AudioServer.add_bus_effect(audio_bus_idx, amplify_effect)
		
		if not capture_effect:
			capture_effect = AudioEffectCapture.new()
			AudioServer.add_bus_effect(audio_bus_idx, capture_effect)
	
	# Start microphone input
	var mic_stream = AudioStreamMicrophone.new()
	mic_player = AudioStreamPlayer.new()
	mic_player.stream = mic_stream
	mic_player.bus = audio_bus_name
	add_child(mic_player)
	mic_player.play()
	
	print("🎤 AudioSettingsPanel: Audio initialized on bus '%s' (idx: %d)" % [audio_bus_name, audio_bus_idx])


func _setup_input_device_selector():
	var device_row = HBoxContainer.new()
	device_container.add_child(device_row)
	
	var device_label = Label.new()
	device_label.text = "Device:"
	device_label.custom_minimum_size = Vector2(70, 0)
	device_row.add_child(device_label)
	
	input_device_option = OptionButton.new()
	input_device_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_device_option.item_selected.connect(_on_input_device_selected)
	device_row.add_child(input_device_option)
	
	_update_input_device_list()


func _update_input_device_list():
	input_device_option.clear()
	var devices = AudioServer.get_input_device_list()
	var current_device = AudioServer.get_input_device()
	for i in range(devices.size()):
		var device_name = devices[i]
		input_device_option.add_item(device_name)
		if device_name == current_device:
			input_device_option.selected = i


func _process(_delta):
	_process_mic_audio()
	
	# Restart mic if stopped
	if mic_player and not mic_player.playing:
		mic_player.play()


func _ensure_mic_playing() -> void:
	"""Called deferred to ensure mic starts after node is fully in tree."""
	if mic_player and not mic_player.playing:
		print("🎤 AudioSettingsPanel: Starting mic player (deferred)")
		mic_player.play()
	
	# Verify capture effect is working
	if capture_effect:
		print("🎤 AudioSettingsPanel: Capture effect ready, frames available: ", capture_effect.get_frames_available())


func _process_mic_audio():
	if not capture_effect or not capture_effect.can_get_buffer(BUFFER_SIZE):
		return
	
	var buffer = capture_effect.get_buffer(BUFFER_SIZE)
	
	# Emit buffer for LiveKit transmission (if not muted)
	if not is_muted:
		audio_buffer_ready.emit(buffer)
	
	# Visualize level
	var max_amp = 0.0
	for frame in buffer:
		var amp = max(abs(frame.x), abs(frame.y))
		max_amp = max(max_amp, amp)
	
	mic_level_bar.value = max_amp * 100
	
	# Visual feedback for threshold
	if max_amp > mic_threshold and not is_muted:
		mic_level_bar.modulate = Color.GREEN
	else:
		mic_level_bar.modulate = Color.WHITE


func _on_mute_toggle(button_pressed: bool):
	is_muted = button_pressed
	mute_button.text = "🔇 Muted" if is_muted else "🎤 Active"
	mic_level_bar.modulate = Color.GRAY if is_muted else Color.WHITE
	mute_toggled.emit(is_muted)
	print("🎤 Mute toggled: ", is_muted)
	_save_settings()


func _on_gain_changed(value: float):
	if amplify_effect:
		amplify_effect.volume_db = value
		gain_value_label.text = "%.1f dB" % value
		gain_changed.emit(value)
		_save_settings()


func _on_threshold_changed(value: float):
	mic_threshold = value
	threshold_label.text = "%.2f" % mic_threshold
	threshold_changed.emit(value)
	_save_settings()


func _on_hear_audio_toggled(button_pressed: bool):
	hear_own_audio = button_pressed
	if audio_bus_idx != -1:
		var volume_db = 0.0 if hear_own_audio else -80.0
		AudioServer.set_bus_volume_db(audio_bus_idx, volume_db)
	_save_settings()


func _on_input_device_selected(index: int):
	var device_name = input_device_option.get_item_text(index)
	print("🎤 Switching to device: ", device_name)
	
	if mic_player:
		mic_player.stop()
	
	AudioServer.set_input_device(device_name)
	
	await get_tree().process_frame
	
	if mic_player:
		mic_player.stream = AudioStreamMicrophone.new()
		mic_player.play()


# Public API
func set_muted(muted: bool):
	is_muted = muted
	mute_button.button_pressed = muted
	_on_mute_toggle(muted)


func get_sample_rate() -> int:
	return int(AudioServer.get_mix_rate())


# === Persistence (Meta VRCS Compliance) ===

func _load_saved_settings() -> void:
	var save_manager = get_node_or_null("/root/SaveManager")
	if not save_manager or not save_manager.has_method("get_audio_settings"):
		return
	
	var settings: Dictionary = save_manager.get_audio_settings()
	if settings.is_empty():
		return
	
	print("AudioSettingsPanel: Loading saved settings")
	
	# Apply saved settings
	if settings.has("gain") and gain_slider:
		gain_slider.value = settings["gain"]
		_on_gain_changed(settings["gain"])
	
	if settings.has("threshold") and threshold_slider:
		threshold_slider.value = settings["threshold"]
		_on_threshold_changed(settings["threshold"])
	
	if settings.has("muted"):
		set_muted(settings["muted"])
	
	if settings.has("hear_self") and hear_self_check:
		hear_self_check.button_pressed = settings["hear_self"]
		_on_hear_audio_toggled(settings["hear_self"])


func _save_settings() -> void:
	var save_manager = get_node_or_null("/root/SaveManager")
	if not save_manager or not save_manager.has_method("save_audio_settings"):
		return
	
	var settings := {
		"gain": gain_slider.value if gain_slider else 0.0,
		"threshold": mic_threshold,
		"muted": is_muted,
		"hear_self": hear_own_audio,
	}
	save_manager.save_audio_settings(settings)
	print("AudioSettingsPanel: Settings saved")
