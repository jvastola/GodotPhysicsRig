extends Grabbable
class_name MiningTool

## Mining Tool - Hit ore deposits to mine them based on collision impact

@export var damage_multiplier: float = 5.0  # Damage = velocity * this multiplier
@export var min_damage_velocity: float = 0.5  # Minimum velocity to cause damage
@export var hit_cooldown: float = 0.2

var _last_hit_time: float = 0.0
var _audio_player: AudioStreamPlayer3D
var _last_collision_velocity: Vector3 = Vector3.ZERO
var _hand_connected: bool = false

signal ore_mined(ore_type: String, amount: int)


func _ready() -> void:
	super._ready()
	add_to_group("mining_tool")
	_create_audio_player()
	
	# Connect to collision signals for when not grabbed
	body_entered.connect(_on_body_collision)
	
	print("MiningTool: Ready - collision-based mining enabled")


func _create_audio_player() -> void:
	"""Create audio player for hit sounds"""
	_audio_player = AudioStreamPlayer3D.new()
	_audio_player.name = "HitSound"
	add_child(_audio_player)
	_audio_player.max_distance = 20.0
	_audio_player.unit_size = 1.0


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# Store velocity for collision calculations
	if is_grabbed and is_instance_valid(grabbing_hand):
		_last_collision_velocity = grabbing_hand.linear_velocity
		
		# Connect to hand's collision signal if not already connected
		if not _hand_connected:
			if grabbing_hand.body_entered.is_connected(_on_hand_body_collision):
				_hand_connected = true
			else:
				if grabbing_hand.body_entered.connect(_on_hand_body_collision) == OK:
					_hand_connected = true
					print("MiningTool: Connected to hand collision signal")
	else:
		_last_collision_velocity = linear_velocity
		_hand_connected = false


func _on_body_collision(body: Node) -> void:
	"""Called when the tool collides with something (when not grabbed)"""
	_process_collision(body, linear_velocity)


func _on_hand_body_collision(body: Node) -> void:
	"""Called when the hand (with grabbed tool) collides with something"""
	if not is_grabbed:
		return
	
	# Only process if this is our grabbed collision shape hitting something
	# Check if the body is an ore deposit
	if not body.has_method("take_mining_damage"):
		return
	
	_process_collision(body, _last_collision_velocity)


func _process_collision(body: Node, velocity: Vector3) -> void:
	"""Process a collision with a potential ore deposit"""
	# Check cooldown
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - _last_hit_time < hit_cooldown:
		return
	
	# Check if it's an ore deposit
	if not body.has_method("take_mining_damage"):
		return
	
	# Calculate impact velocity
	var impact_velocity = velocity.length()
	
	# Check if velocity is high enough
	if impact_velocity < min_damage_velocity:
		print("MiningTool: Hit but velocity too low: ", impact_velocity)
		return
	
	# Calculate damage based on impact velocity
	var damage = impact_velocity * damage_multiplier
	
	# Get collision point (approximate as body center)
	var hit_position = body.global_position
	
	# Apply damage
	body.take_mining_damage(damage, hit_position)
	_last_hit_time = current_time
	
	# Play feedback
	_play_hit_feedback(impact_velocity)
	
	print("MiningTool: Hit ore with velocity ", impact_velocity, " dealing ", damage, " damage")


func _play_hit_feedback(impact_velocity: float) -> void:
	"""Audio feedback for hitting an ore"""
	if not _audio_player:
		return
	
	# Play sound with pitch based on impact
	_audio_player.pitch_scale = clamp(0.8 + impact_velocity * 0.1, 0.8, 1.5)
	
	# Create a simple impact sound
	var stream = AudioStreamGenerator.new()
	stream.mix_rate = 22050
	stream.buffer_length = 0.1
	
	_audio_player.stream = stream
	_audio_player.play()
