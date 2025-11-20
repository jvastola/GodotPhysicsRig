class_name PlayerVoiceComponent
extends Node

var network_manager: Node = null
var microphone: AudioStreamMicrophone = null
var microphone_player: AudioStreamPlayer = null
var voice_effect: AudioEffectCapture = null
var voice_enabled: bool = false

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
	microphone_player.bus = "Voice"
	add_child(microphone_player)
	
	# Add AudioEffectCapture to Voice bus
	var voice_bus_index = AudioServer.get_bus_index("Voice")
	if voice_bus_index != -1:
		# Check if capture effect already exists
		var has_capture = false
		for i in range(AudioServer.get_bus_effect_count(voice_bus_index)):
			if AudioServer.get_bus_effect(voice_bus_index, i) is AudioEffectCapture:
				voice_effect = AudioServer.get_bus_effect(voice_bus_index, i)
				has_capture = true
				break
		
		if not has_capture:
			voice_effect = AudioEffectCapture.new()
			AudioServer.add_bus_effect(voice_bus_index, voice_effect)
		
		print("PlayerVoiceComponent: Voice chat initialized")

func toggle_voice_chat(enabled: bool) -> void:
	"""Enable or disable voice chat"""
	voice_enabled = enabled
	
	if network_manager:
		network_manager.enable_voice_chat(enabled)
	
	if enabled and microphone_player:
		microphone_player.play()
	elif microphone_player:
		microphone_player.stop()
	
	print("PlayerVoiceComponent: Voice chat ", "enabled" if enabled else "disabled")

func _process_voice_chat(_delta: float) -> void:
	"""Capture and send voice data"""
	if not voice_enabled or not voice_effect or not network_manager:
		return
	
	# Get available audio frames from capture
	var available = voice_effect.get_frames_available()
	if available > 0:
		# Get audio samples (limit to reasonable buffer size)
		var frames_to_get = min(available, 2048)
		var audio_data = voice_effect.get_buffer(frames_to_get)
		
		if audio_data.size() > 0:
			# Send to network
			network_manager.send_voice_data(audio_data)
