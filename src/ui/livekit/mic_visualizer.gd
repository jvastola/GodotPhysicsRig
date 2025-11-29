extends Control

# This script visualizes microphone input as a waveform.
# It does not depend on any other project code.

var audio_bus_index: int = -1
var effect_capture: AudioEffectCapture = null
var audio_buffer = []
var frequency_bands = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
const BUFFER_SIZE = 512
var mic_threshold = 0.05 # Activation threshold for mic (now adjustable)
var is_mic_active = false
var is_muted = false
var hear_own_audio = false
var peak_level = 0.0
var audio_player: AudioStreamPlayer = null

# UI Controls
var mute_button: Button
var threshold_slider: HSlider
var threshold_label: Label
var hear_audio_check: CheckBox
var mic_level_bar: ProgressBar


func _ready():
	# Create a dedicated bus for microphone capture
	# This ensures visualization works even when the user doesn't want to hear their own audio
	var mic_bus_index = AudioServer.bus_count
	AudioServer.add_bus(mic_bus_index)
	AudioServer.set_bus_name(mic_bus_index, "Mic Capture")
	
	# Add capture effect to the mic capture bus
	effect_capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(mic_bus_index, effect_capture)
	
	# By default, don't send the mic bus to master (no self-monitoring)
	AudioServer.set_bus_send(mic_bus_index, "Master")
	AudioServer.set_bus_mute(mic_bus_index, true)
	
	audio_bus_index = mic_bus_index
	
	# Create microphone stream and player
	var mic_stream = AudioStreamMicrophone.new()
	audio_player = AudioStreamPlayer.new()
	audio_player.stream = mic_stream
	audio_player.bus = "Mic Capture"
	add_child(audio_player)
	audio_player.play()
	
	# Create UI controls
	_create_ui_controls()
	
	set_process(true)


func _create_ui_controls():
	# Create a VBoxContainer for the controls
	var controls_container = VBoxContainer.new()
	controls_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	controls_container.position = Vector2(10, 50)
	controls_container.add_theme_constant_override("separation", 10)
	add_child(controls_container)
	
	# Mute button
	mute_button = Button.new()
	mute_button.text = "Mute: OFF"
	mute_button.custom_minimum_size = Vector2(150, 30)
	mute_button.pressed.connect(_on_mute_toggled)
	controls_container.add_child(mute_button)
	
	# Threshold control
	var threshold_container = HBoxContainer.new()
	threshold_container.add_theme_constant_override("separation", 10)
	controls_container.add_child(threshold_container)
	
	var threshold_title = Label.new()
	threshold_title.text = "Threshold:"
	threshold_title.custom_minimum_size = Vector2(80, 0)
	threshold_container.add_child(threshold_title)
	
	threshold_slider = HSlider.new()
	threshold_slider.min_value = 0.01
	threshold_slider.max_value = 0.5
	threshold_slider.step = 0.01
	threshold_slider.value = mic_threshold
	threshold_slider.custom_minimum_size = Vector2(150, 20)
	threshold_slider.value_changed.connect(_on_threshold_changed)
	threshold_container.add_child(threshold_slider)
	
	threshold_label = Label.new()
	threshold_label.text = "%.2f" % mic_threshold
	threshold_label.custom_minimum_size = Vector2(40, 0)
	threshold_container.add_child(threshold_label)
	
	# Mic level bar
	var mic_level_container = VBoxContainer.new()
	mic_level_container.add_theme_constant_override("separation", 5)
	controls_container.add_child(mic_level_container)
	
	var mic_level_title = Label.new()
	mic_level_title.text = "Mic Level:"
	mic_level_container.add_child(mic_level_title)
	
	mic_level_bar = ProgressBar.new()
	mic_level_bar.custom_minimum_size = Vector2(250, 25)
	mic_level_bar.max_value = 100
	mic_level_bar.show_percentage = false
	mic_level_container.add_child(mic_level_bar)
	
	# Hear own audio checkbox
	hear_audio_check = CheckBox.new()
	hear_audio_check.text = "Hear Own Audio"
	hear_audio_check.button_pressed = hear_own_audio
	hear_audio_check.toggled.connect(_on_hear_audio_toggled)
	controls_container.add_child(hear_audio_check)


func _process(_delta):
	# Get captured audio data
	if effect_capture and effect_capture.can_get_buffer(BUFFER_SIZE):
		var buffer = effect_capture.get_buffer(BUFFER_SIZE)
		if buffer.size() > 0:
			peak_level = 0.0
			for i in range(buffer.size()):
				audio_buffer.append(buffer[i])
				if audio_buffer.size() > BUFFER_SIZE:
					audio_buffer.pop_front()
				# Calculate peak level
				var amplitude = buffer[i]
				if amplitude is Vector2:
					amplitude = amplitude.x
				var abs_amp = abs(float(amplitude))
				peak_level = max(peak_level, abs_amp)
			
			# Update frequency bands for bar visualization
			_update_frequency_bands()
			is_mic_active = peak_level > mic_threshold
			
			# Update mic level bar (0-100%)
			if mic_level_bar:
				mic_level_bar.value = peak_level * 100
	
	queue_redraw()


func _on_mute_toggled():
	is_muted = !is_muted
	mute_button.text = "Mute: ON" if is_muted else "Mute: OFF"
	
	# When muted, stop the audio player playback
	if audio_player:
		if is_muted:
			audio_player.stop()
		else:
			audio_player.play()


func _on_threshold_changed(value: float):
	mic_threshold = value
	threshold_label.text = "%.2f" % mic_threshold


func _on_hear_audio_toggled(button_pressed: bool):
	hear_own_audio = button_pressed
	# Mute the mic capture bus when not wanting to hear own audio
	# This keeps visualization working but prevents audio output
	AudioServer.set_bus_mute(audio_bus_index, not hear_own_audio)


func _update_frequency_bands():
	# Divide buffer into frequency bands and calculate average amplitude
	var band_size = audio_buffer.size() / frequency_bands.size()
	if band_size == 0:
		return
	
	for band_idx in range(frequency_bands.size()):
		var sum = 0.0
		var count = 0
		var start = band_idx * band_size
		var end = min(start + band_size, audio_buffer.size())
		
		for i in range(start, end):
			var amplitude = audio_buffer[i]
			if amplitude is Vector2:
				amplitude = amplitude.x
			sum += abs(float(amplitude))
			count += 1
		
		if count > 0:
			frequency_bands[band_idx] = sum / count


func _draw():
	var w = size.x
	var h = size.y
	
	# Draw background
	draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.05, 0.1, 1))
	
	# Draw center line
	draw_line(Vector2(0, h / 2), Vector2(w, h / 2), Color(0.3, 0.3, 0.3, 0.5), 1.0)
	
	# Draw mute status indicator (top right)
	if is_muted:
		draw_rect(Rect2(w - 120, 10, 20, 20), Color(1, 0, 0, 1))
		_draw_text_with_outline(Vector2(w - 95, 15), "MUTED", Color(1, 0, 0))
	
	# Draw mic activation indicator
	if is_mic_active and not is_muted:
		draw_rect(Rect2(10, 10, 20, 20), Color(0, 1, 0, 1))
		_draw_text_with_outline(Vector2(35, 15), "MIC ACTIVE", Color(0, 1, 0))
	else:
		draw_rect(Rect2(10, 10, 20, 20), Color(0.5, 0.5, 0.5, 0.5))
		_draw_text_with_outline(Vector2(35, 15), "MIC IDLE", Color(0.5, 0.5, 0.5))
	
	# Draw waveform (dimmed when muted)
	_draw_waveform(w, h)
	
	# Draw frequency bars
	_draw_frequency_bars(w, h)
	
	# Draw peak level indicator
	_draw_peak_level(w, h)


func _draw_waveform(w: float, h: float):
	if audio_buffer.size() < 2:
		return
	
	var mid = h / 2.5 # Adjust midpoint
	var step = w / float(audio_buffer.size())
	var points = PackedVector2Array()
	
	for i in range(audio_buffer.size()):
		var x = i * step
		var amplitude = audio_buffer[i]
		if amplitude is Vector2:
			amplitude = amplitude.x
		var y = mid - float(amplitude) * mid * 8.0
		y = clamp(y, 0, h)
		points.append(Vector2(x, y))
	
	draw_polyline(points, Color(0, 1, 0, 0.8), 1.5)


func _draw_frequency_bars(w: float, h: float):
	var bar_width = w / frequency_bands.size()
	var bar_spacing = 2.0
	var bar_start_y = h * 0.7
	
	for i in range(frequency_bands.size()):
		var bar_height = frequency_bands[i] * (h * 0.25) * 10.0 # Scale up for visibility
		var x = i * bar_width + bar_spacing
		var y = bar_start_y
		
		# Color gradient based on frequency
		var color = Color(0, 1, 0).lerp(Color(1, 0, 0), float(i) / frequency_bands.size())
		color.a = 0.7
		
		draw_rect(Rect2(x, y - bar_height, bar_width - bar_spacing * 2, bar_height), color)
		draw_rect(Rect2(x, y, bar_width - bar_spacing * 2, 1), Color(0.3, 0.3, 0.3, 1))


func _draw_peak_level(w: float, h: float):
	var peak_bar_width = w * peak_level
	draw_rect(Rect2(0, h - 10, peak_bar_width, 10), Color(1, 1, 0, 0.7))
	draw_rect(Rect2(peak_bar_width, h - 10, w - peak_bar_width, 10), Color(0.1, 0.1, 0.1, 0.7))


func _draw_text_with_outline(pos: Vector2, text: String, color: Color):
	var font = get_theme_default_font()
	var font_size = get_theme_default_font_size()
	
	# Draw outline
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx != 0 or dy != 0:
				draw_string(font, pos + Vector2(dx, dy), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
	
	# Draw main text
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
