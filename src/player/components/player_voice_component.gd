class_name PlayerVoiceComponent
extends Node

var network_manager: Node = null
var microphone: AudioStreamMicrophone = null
var microphone_player: AudioStreamPlayer = null
var voice_effect: AudioEffectCapture = null
var voice_enabled: bool = false

# Audio Processing Settings
# Audio Processing Settings
const TARGET_SAMPLE_RATE = 22050 # Downsample to this rate
var vad_threshold: float = 0.005 # RMS threshold for voice activity (adjustable)
const VAD_HANGOVER_TIME = 0.2 # Keep sending for 0.2s after silence
const BATCH_DURATION = 0.05 # Send packets every 50ms

# State
var _sample_buffer: PackedVector2Array = PackedVector2Array()
var _batch_timer: float = 0.0
var _vad_active: bool = false
var _vad_hangover_timer: float = 0.0
var _system_mix_rate: float = 44100.0 # Will be updated from AudioServer
var _current_rms: float = 0.0 # For UI visualization

func setup(p_network_manager: Node) -> void:
	network_manager = p_network_manager
	_setup_voice_chat()

func _process(delta: float) -> void:
	_process_voice_chat(delta)

func _setup_voice_chat() -> void:
	"""Initialize microphone capture for voice chat"""
	# Create microphone stream
	microphone = AudioStreamMicrophone.new()
	
	# Create audio player for microphone (we just use it for capture)
	microphone_player = AudioStreamPlayer.new()
	microphone_player.name = "MicrophonePlayer"
	microphone_player.stream = microphone
	microphone_player.bus = "VoiceInput" # Use Input bus (muted locally)
	microphone_player.volume_db = 0.0  # Full volume for capture
	add_child(microphone_player)
	
	# Add AudioEffectCapture to VoiceInput bus
	var input_bus_index = AudioServer.get_bus_index("VoiceInput")
	if input_bus_index != -1:
		# Check if capture effect already exists
		var has_capture = false
		for i in range(AudioServer.get_bus_effect_count(input_bus_index)):
			if AudioServer.get_bus_effect(input_bus_index, i) is AudioEffectCapture:
				voice_effect = AudioServer.get_bus_effect(input_bus_index, i)
				has_capture = true
				break
		
		# Add Professional Audio Chain (HighPass -> Compressor -> Limiter -> Capture)
		
		# 1. High Pass Filter (Remove rumble/wind)
		var high_pass = AudioEffectHighPassFilter.new()
		high_pass.cutoff_hz = 80.0
		AudioServer.add_bus_effect(input_bus_index, high_pass)
		
		# 2. Compressor (Level out volume)
		var compressor = AudioEffectCompressor.new()
		compressor.threshold = -20.0
		compressor.ratio = 4.0
		compressor.gain = 10.0
		compressor.attack_us = 20.0
		compressor.release_ms = 250.0
		AudioServer.add_bus_effect(input_bus_index, compressor)
		
		# 3. Limiter (Prevent clipping)
		var limiter = AudioEffectLimiter.new()
		limiter.ceiling_db = -1.0
		limiter.threshold_db = -1.0
		AudioServer.add_bus_effect(input_bus_index, limiter)
		
		if not has_capture:
			voice_effect = AudioEffectCapture.new()
			AudioServer.add_bus_effect(input_bus_index, voice_effect)
		
		_system_mix_rate = AudioServer.get_mix_rate()
		print("PlayerVoiceComponent: Voice chat initialized on VoiceInput bus. System Rate: ", _system_mix_rate)

func toggle_voice_chat(enabled: bool) -> void:
	"""Enable or disable voice chat"""
	voice_enabled = enabled
	
	if network_manager:
		network_manager.enable_voice_chat(enabled)
	
	# Ensure VoiceOutput bus is unmuted so we can hear remote players
	var output_bus_index = AudioServer.get_bus_index("VoiceOutput")
	if output_bus_index != -1:
		AudioServer.set_bus_mute(output_bus_index, false)
		#print("PlayerVoiceComponent: VoiceOutput bus unmuted")
	
	if enabled and microphone_player:
		microphone_player.play()
	elif microphone_player:
		microphone_player.stop()
	
	print("PlayerVoiceComponent: Voice chat ", "enabled" if enabled else "disabled")

func _process_voice_chat(delta: float) -> void:
	"""Capture, process, and send voice data"""
	if not voice_enabled or not voice_effect or not network_manager:
		return
	
	# Update batch timer
	_batch_timer += delta
	
	# Get available audio frames from capture
	var available = voice_effect.get_frames_available()
	if available > 0:
		var audio_data = voice_effect.get_buffer(available)
		
		if audio_data.size() > 0:
			# 1. Resample if needed (simple decimation for speed)
			# Note: Proper resampling requires a filter, but for voice chat decimation is often "good enough"
			# if we capture at 44.1/48 and want 22.05.
			var resampled_data = _resample_audio(audio_data)
			
			# 2. Voice Activity Detection (VAD)
			if _check_vad(resampled_data):
				_vad_active = true
				_vad_hangover_timer = VAD_HANGOVER_TIME
			elif _vad_active:
				_vad_hangover_timer -= delta * (float(audio_data.size()) / _system_mix_rate) # Approx time passed in audio
				if _vad_hangover_timer <= 0:
					_vad_active = false
			
			# 3. Buffer data if VAD is active
			if _vad_active:
				_sample_buffer.append_array(resampled_data)
	
	# 4. Send batch if timer expired and we have data
	if _batch_timer >= BATCH_DURATION:
		_batch_timer = 0.0
		if _sample_buffer.size() > 0:
			network_manager.send_voice_data(_sample_buffer)
			#print("PlayerVoiceComponent: Sent batch of ", _sample_buffer.size(), " samples")
			_sample_buffer.clear()


func _resample_audio(input_samples: PackedVector2Array) -> PackedVector2Array:
	"""Downsample audio to TARGET_SAMPLE_RATE"""
	if _system_mix_rate <= TARGET_SAMPLE_RATE:
		return input_samples
		
	var ratio = _system_mix_rate / float(TARGET_SAMPLE_RATE)
	var new_size = int(input_samples.size() / ratio)
	var output = PackedVector2Array()
	output.resize(new_size)
	
	# Simple nearest-neighbor/decimation for performance
	# For better quality, we'd use linear interpolation or a filter
	for i in range(new_size):
		var src_idx = int(i * ratio)
		if src_idx < input_samples.size():
			output[i] = input_samples[src_idx]
			
	return output


func _check_vad(samples: PackedVector2Array) -> bool:
	"""Check if audio samples contain voice (RMS threshold)"""
	var sum_squares = 0.0
	for sample in samples:
		# Average of left/right channels
		var val = (sample.x + sample.y) * 0.5
		sum_squares += val * val
		
	var rms = sqrt(sum_squares / samples.size())
	_current_rms = rms # Store for UI
	return rms > vad_threshold

# UI Helpers
func get_current_rms() -> float:
	return _current_rms

func set_vad_threshold(value: float) -> void:
	vad_threshold = value

