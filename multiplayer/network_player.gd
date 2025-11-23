extends Node3D
## NetworkPlayer - Represents a remote player in the network
## Handles interpolation and visualization of networked player transforms

@export var peer_id: Variant = -1
@export var interpolation_speed: float = 15.0
@export var use_interpolation_buffer: bool = true
@export var buffer_size: int = 3

# Visual representations
@onready var head_visual: MeshInstance3D = $Head
@onready var left_hand_visual: MeshInstance3D = $LeftHand
@onready var right_hand_visual: MeshInstance3D = $RightHand
@onready var body_visual: MeshInstance3D = $Body

# Target transforms for interpolation
var target_head_position: Vector3 = Vector3.ZERO
var target_head_rotation: Vector3 = Vector3.ZERO
var target_left_hand_position: Vector3 = Vector3.ZERO
var target_left_hand_rotation: Vector3 = Vector3.ZERO
var target_right_hand_position: Vector3 = Vector3.ZERO
var target_right_hand_rotation: Vector3 = Vector3.ZERO
var target_scale: Vector3 = Vector3.ONE

# Interpolation buffer for smoother movement
var position_buffer: Array = []
var rotation_buffer: Array = []
var buffer_index: int = 0

# Label to show player name/ID
var label_3d: Label3D = null

# Voice chat
var voice_player: AudioStreamPlayer3D = null
var voice_playback: AudioStreamGeneratorPlayback = null

# Avatar texture
var has_custom_avatar: bool = false


func _ready() -> void:
	_create_visuals()
	_create_name_label()
	_create_voice_player()


func _process(delta: float) -> void:
	_interpolate_transforms(delta)
	_update_label_position()
	_process_voice_playback(delta)


## Update target transforms from network data
func update_from_network_data(player_data: Dictionary) -> void:
	var new_head_pos = player_data.get("head_position", Vector3.ZERO)
	var new_head_rot = player_data.get("head_rotation", Vector3.ZERO)
	
	# Use interpolation buffer for smoother movement
	if use_interpolation_buffer:
		# Add to buffer
		position_buffer.append(new_head_pos)
		rotation_buffer.append(new_head_rot)
		
		# Keep buffer size limited
		if position_buffer.size() > buffer_size:
			position_buffer.pop_front()
			rotation_buffer.pop_front()
		
		# Average the buffer for smoother result
		var avg_pos = Vector3.ZERO
		var avg_rot = Vector3.ZERO
		for pos in position_buffer:
			avg_pos += pos
		for rot in rotation_buffer:
			avg_rot += rot
		target_head_position = avg_pos / position_buffer.size()
		target_head_rotation = avg_rot / rotation_buffer.size()
	else:
		target_head_position = new_head_pos
		target_head_rotation = new_head_rot
	
	target_left_hand_position = player_data.get("left_hand_position", Vector3.ZERO)
	target_left_hand_rotation = player_data.get("left_hand_rotation", Vector3.ZERO)
	target_right_hand_position = player_data.get("right_hand_position", Vector3.ZERO)
	target_right_hand_rotation = player_data.get("right_hand_rotation", Vector3.ZERO)
	target_scale = player_data.get("player_scale", Vector3.ONE)
	
	# Handle voice samples
	if player_data.has("voice_samples"):
		_play_voice_samples(player_data["voice_samples"])


## Smoothly interpolate to target transforms
func _interpolate_transforms(delta: float) -> void:
	var lerp_factor = interpolation_speed * delta
	
	# Interpolate head
	head_visual.global_position = head_visual.global_position.lerp(target_head_position, lerp_factor)
	head_visual.rotation_degrees = head_visual.rotation_degrees.lerp(target_head_rotation, lerp_factor)
	
	# Interpolate left hand
	left_hand_visual.global_position = left_hand_visual.global_position.lerp(target_left_hand_position, lerp_factor)
	left_hand_visual.rotation_degrees = left_hand_visual.rotation_degrees.lerp(target_left_hand_rotation, lerp_factor)
	
	# Interpolate right hand
	right_hand_visual.global_position = right_hand_visual.global_position.lerp(target_right_hand_position, lerp_factor)
	right_hand_visual.rotation_degrees = right_hand_visual.rotation_degrees.lerp(target_right_hand_rotation, lerp_factor)
	
	# Interpolate scale
	scale = scale.lerp(target_scale, lerp_factor)
	
	# Update body position (midpoint between hands at chest height)
	var body_pos = (target_left_hand_position + target_right_hand_position) / 2.0
	body_pos.y = target_head_position.y - 0.3 # Slightly below head
	body_visual.global_position = body_visual.global_position.lerp(body_pos, lerp_factor)


## Create simple visual meshes for the player (rectangles like XRPlayer)
func _create_visuals() -> void:
	# Head - box/rectangle
	if not head_visual:
		head_visual = MeshInstance3D.new()
		head_visual.name = "Head"
		add_child(head_visual)
	
	var head_mesh = BoxMesh.new()
	head_mesh.size = Vector3(0.22, 0.22, 0.22)
	head_visual.mesh = head_mesh
	
	var head_material = StandardMaterial3D.new()
	head_material.albedo_color = Color(0.8, 0.6, 0.4) # Skin tone
	head_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	head_visual.material_override = head_material
	
	# Left hand - box/rectangle
	if not left_hand_visual:
		left_hand_visual = MeshInstance3D.new()
		left_hand_visual.name = "LeftHand"
		add_child(left_hand_visual)
	
	var left_hand_mesh = BoxMesh.new()
	left_hand_mesh.size = Vector3(0.1, 0.1, 0.15)
	left_hand_visual.mesh = left_hand_mesh
	
	var left_material = StandardMaterial3D.new()
	left_material.albedo_color = Color(0.3, 0.6, 1.0) # Blue for left
	left_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	left_hand_visual.material_override = left_material
	
	# Right hand - box/rectangle
	if not right_hand_visual:
		right_hand_visual = MeshInstance3D.new()
		right_hand_visual.name = "RightHand"
		add_child(right_hand_visual)
	
	var right_hand_mesh = BoxMesh.new()
	right_hand_mesh.size = Vector3(0.1, 0.1, 0.15)
	right_hand_visual.mesh = right_hand_mesh
	
	var right_material = StandardMaterial3D.new()
	right_material.albedo_color = Color(1.0, 0.3, 0.3) # Red for right
	right_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	right_hand_visual.material_override = right_material
	
	# Body - box/rectangle
	if not body_visual:
		body_visual = MeshInstance3D.new()
		body_visual.name = "Body"
		add_child(body_visual)
	
	var body_mesh = BoxMesh.new()
	body_mesh.size = Vector3(0.4, 0.6, 0.2)
	body_visual.mesh = body_mesh
	
	var body_material = StandardMaterial3D.new()
	body_material.albedo_color = Color(0.4, 0.4, 0.4) # Gray
	body_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_material.albedo_color.a = 0.5
	body_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	body_visual.material_override = body_material


## Create floating name label above head
func _create_name_label() -> void:
	label_3d = Label3D.new()
	label_3d.name = "NameLabel"
	label_3d.text = "Player " + str(peer_id)
	label_3d.pixel_size = 0.002
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.no_depth_test = true
	label_3d.modulate = Color(1, 1, 1, 0.8)
	label_3d.outline_size = 8
	label_3d.outline_modulate = Color(0, 0, 0, 0.5)
	add_child(label_3d)


## Update the name label position above head
func _update_label_position() -> void:
	if label_3d and head_visual:
		label_3d.global_position = head_visual.global_position + Vector3(0, 0.3, 0)



## Apply avatar textures to player meshes
func apply_avatar_textures(textures_data: Dictionary) -> void:
	"""Apply avatar textures to head, body, and hands meshes"""
	if textures_data.is_empty():
		return
	
	# Apply head texture
	if textures_data.has("head"):
		var texture = _create_texture_from_data(textures_data["head"])
		if texture and head_visual:
			var mat = StandardMaterial3D.new()
			mat.albedo_texture = texture
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode = BaseMaterial3D.CULL_BACK
			head_visual.material_override = mat
			has_custom_avatar = true
	
	# Apply body texture
	if textures_data.has("body"):
		var texture = _create_texture_from_data(textures_data["body"])
		if texture and body_visual:
			var mat = StandardMaterial3D.new()
			mat.albedo_texture = texture
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode = BaseMaterial3D.CULL_BACK
			body_visual.material_override = mat
	
	# Apply hands texture (same for both hands)
	if textures_data.has("hands"):
		var texture = _create_texture_from_data(textures_data["hands"])
		if texture:
			var mat = StandardMaterial3D.new()
			mat.albedo_texture = texture
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode = BaseMaterial3D.CULL_BACK
			
			if left_hand_visual:
				left_hand_visual.material_override = mat.duplicate()
			if right_hand_visual:
				right_hand_visual.material_override = mat.duplicate()
	
	print("NetworkPlayer: Applied ", textures_data.size(), " avatar textures to player ", peer_id)


func _create_texture_from_data(texture_data: PackedByteArray) -> ImageTexture:
	"""Create an ImageTexture from PNG byte data"""
	var image = Image.new()
	var error = image.load_png_from_buffer(texture_data)
	if error != OK:
		push_error("NetworkPlayer: Failed to load texture from data")
		return null
	return ImageTexture.create_from_image(image)


## Apply avatar texture to head mesh (legacy function for compatibility)
func apply_avatar_texture(texture: ImageTexture) -> void:
	if not head_visual or not texture:
		return
	
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	head_visual.material_override = mat
	has_custom_avatar = true
	print("NetworkPlayer: Applied avatar texture to player ", peer_id)


## Create voice audio player
# Voice Chat Settings
const VOICE_SAMPLE_RATE = 22050 # Must match PlayerVoiceComponent
const JITTER_BUFFER_MS = 0.1 # 100ms buffer target
const MAX_JITTER_BUFFER_MS = 0.5 # 500ms max buffer

var _jitter_buffer: Array[float] = [] # Buffer for individual samples (float)
var _playback_ring_buffer: PackedVector2Array # Ring buffer for upsampling
var _ring_buffer_pos: int = 0
var _system_mix_rate: float = 44100.0

## Create voice audio player
func _create_voice_player() -> void:
	voice_player = AudioStreamPlayer3D.new()
	voice_player.name = "VoicePlayer"
	
	# Create audio stream generator for voice playback
	var stream = AudioStreamGenerator.new()
	_system_mix_rate = AudioServer.get_mix_rate()
	stream.mix_rate = _system_mix_rate
	stream.buffer_length = 0.5 # Large buffer for generator
	voice_player.stream = stream
	voice_player.bus = "VoiceOutput"
	voice_player.autoplay = true
	voice_player.max_distance = 20.0
	voice_player.unit_size = 5.0
	
	add_child(voice_player)
	
	voice_player.play()
	voice_playback = voice_player.get_stream_playback()
	
	print("NetworkPlayer [", peer_id, "]: Voice player created. System Rate: ", _system_mix_rate)


## Process voice playback from jitter buffer
func _process_voice_playback(_delta: float) -> void:
	if not voice_playback:
		return
		
	# 1. Check how many frames the generator needs
	var frames_available = voice_playback.get_frames_available()
	if frames_available <= 0:
		return
		
	# 2. Pull from Jitter Buffer
	# We need to fill 'frames_available' at SYSTEM mix rate
	# But our buffer has samples at VOICE_SAMPLE_RATE (22050)
	
	var samples_needed = frames_available
	var samples_to_push = PackedVector2Array()
	samples_to_push.resize(samples_needed)
	
	# Calculate ratio for upsampling
	var ratio = _system_mix_rate / float(VOICE_SAMPLE_RATE)
	
	# If buffer is empty or too low, we might need to wait (buffering)
	# But for simplicity, if we have data, we play it. If not, silence.
	# A more advanced jitter buffer would time-stretch.
	
	var buffer_size_samples = _jitter_buffer.size()
	
	# Simple Jitter Buffer Logic:
	# If we have enough samples, play.
	# If we run dry, we output silence.
	
	if buffer_size_samples > 0:
		for i in range(samples_needed):
			# Upsampling: Map output index to input index
			# We consume 1 input sample for every 'ratio' output samples
			# This is a bit tricky with a simple array buffer.
			# Better approach: Step through output, calculate float index in input.
			
			# Current implementation: Linear Interpolation Upsampling
			# We need to maintain a "read head" position in the jitter buffer
			# Since we pop samples, index 0 is always the next sample.
			# But we need fractional progress.
			
			# Simplified: Just repeat samples (Nearest Neighbor) or Linear Interp
			# Let's do Linear Interpolation for quality.
			
			# We need 'ratio' output samples to consume 1 input sample.
			# So we consume (1 / ratio) input samples per output sample.
			
			# Actually, let's just drain the buffer into the stream
			# We need to generate 'samples_needed' output frames.
			# That corresponds to 'samples_needed / ratio' input frames.
			
			var input_idx_float = float(i) / ratio
			var input_idx_int = int(input_idx_float)
			var input_frac = input_idx_float - input_idx_int
			
			# We need to peek into the buffer
			var val_left = 0.0
			var val_right = 0.0
			
			if input_idx_int < _jitter_buffer.size() / 2: # Buffer stores interleaved L, R
				# Each frame is 2 floats (L, R)
				var idx_base = input_idx_int * 2
				
				var l1 = _jitter_buffer[idx_base]
				var r1 = _jitter_buffer[idx_base + 1]
				
				var l2 = l1
				var r2 = r1
				
				if idx_base + 2 < _jitter_buffer.size():
					l2 = _jitter_buffer[idx_base + 2]
					r2 = _jitter_buffer[idx_base + 3]
				
				# Lerp
				val_left = lerp(l1, l2, input_frac)
				val_right = lerp(r1, r2, input_frac)
				
				samples_to_push[i] = Vector2(val_left, val_right)
			else:
				# Run out of data during this batch
				samples_to_push[i] = Vector2.ZERO
		
		# Remove consumed samples from buffer
		var input_samples_consumed = int(float(samples_needed) / ratio)
		var floats_consumed = input_samples_consumed * 2
		
		if floats_consumed > 0:
			if floats_consumed >= _jitter_buffer.size():
				_jitter_buffer.clear()
			else:
				# This is slow for large arrays, but voice buffers are small
				# Optimization: Use a ring buffer or index
				for k in range(floats_consumed):
					_jitter_buffer.pop_front()
					
		voice_playback.push_buffer(samples_to_push)
	else:
		# Silence
		voice_playback.push_buffer(PackedVector2Array([Vector2.ZERO])) # Push a little silence


## Receive voice samples (called from NetworkManager)
func _play_voice_samples(samples: PackedVector2Array) -> void:
	# Add to Jitter Buffer
	# Samples are interleaved Vector2 (L, R)
	# We convert to flat float array for easier processing
	for sample in samples:
		_jitter_buffer.append(sample.x)
		_jitter_buffer.append(sample.y)
	
	# Limit buffer size (prevent infinite delay)
	var max_samples = int(MAX_JITTER_BUFFER_MS * VOICE_SAMPLE_RATE * 2) # *2 for stereo
	if _jitter_buffer.size() > max_samples:
		# Drop oldest samples to catch up
		var drop_count = _jitter_buffer.size() - max_samples
		for i in range(drop_count):
			_jitter_buffer.pop_front()
		#print("NetworkPlayer: Jitter buffer overflow, dropped ", drop_count, " samples")
