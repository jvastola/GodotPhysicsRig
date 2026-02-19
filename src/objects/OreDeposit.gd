extends StaticBody3D
class_name OreDeposit

## Ore Deposit - Can be mined for resources

@export var ore_type: String = "iron"
@export var max_health: float = 100.0
@export var loot_amount_min: int = 1
@export var loot_amount_max: int = 3
@export var respawn_time: float = 30.0  # Time to respawn after being mined
@export var drop_loot: bool = true  # If false, adds directly to inventory
@export var hand_damage_multiplier: float = 3.0  # Damage from hand hits
@export var min_hand_velocity: float = 0.8  # Minimum hand velocity to damage
@export var requires_tool: bool = true  # If true, can only be damaged by mining tools

var current_health: float = 100.0
var _mesh_instance: MeshInstance3D
var _original_material: Material
var _audio_player: AudioStreamPlayer3D
var _health_label: Label3D
var _is_depleted: bool = false
var _respawn_timer: float = 0.0
var _collision_shape: CollisionShape3D
var _hit_sound: AudioStream
var _failed_hit_sound: AudioStream
var _last_hand_hit_time: float = 0.0
const HAND_HIT_COOLDOWN: float = 0.2

signal ore_depleted(ore_type: String, amount: int)
signal ore_damaged(health_remaining: float)
signal ore_respawned()


func _ready() -> void:
	current_health = max_health
	add_to_group("ore_deposit")
	
	# Set requires_tool based on ore type
	if ore_type == "iron":
		requires_tool = true
	elif ore_type == "gold" or ore_type == "plasma":
		requires_tool = false
	
	# Set collision layer/mask for proper physics interaction
	# Layer 1 (default) so hands and tools can collide with it
	collision_layer = 1
	collision_mask = 0  # Doesn't need to detect anything
	
	# Find mesh instance for visual feedback
	_mesh_instance = _find_mesh_instance(self)
	if _mesh_instance and _mesh_instance.material_override:
		_original_material = _mesh_instance.material_override
	
	# Find collision shape
	_collision_shape = _find_collision_shape(self)
	
	# Create audio player and load sound
	_create_audio_player()
	_load_hit_sound()
	_load_failed_hit_sound()
	
	# Create health label
	_create_health_label()
	
	# Create detection area for hand collisions
	_create_hand_detection_area()
	
	print("OreDeposit: Ready - Type: ", ore_type, " Health: ", max_health, " Requires Tool: ", requires_tool)


func _create_hand_detection_area() -> void:
	"""Create an Area3D to detect hand collisions"""
	var detection_area = Area3D.new()
	detection_area.name = "HandDetectionArea"
	detection_area.collision_layer = 0
	detection_area.collision_mask = 4  # Layer 3 (physics_hand is on layer 3/bit 4)
	add_child(detection_area)
	
	# Copy the collision shape from the StaticBody3D
	if _collision_shape and _collision_shape.shape:
		var area_collision = CollisionShape3D.new()
		area_collision.shape = _collision_shape.shape
		area_collision.position = _collision_shape.position
		area_collision.rotation = _collision_shape.rotation
		area_collision.scale = _collision_shape.scale
		detection_area.add_child(area_collision)
		print("OreDeposit: Created hand detection area with shape")
	else:
		print("OreDeposit: WARNING - No collision shape found for hand detection!")
	
	# Connect to body entered signal
	detection_area.body_entered.connect(_on_body_entered)
	print("OreDeposit: Hand detection area ready, collision_mask: ", detection_area.collision_mask)


func _physics_process(delta: float) -> void:
	# Handle respawn timer
	if _is_depleted:
		_respawn_timer += delta
		if _respawn_timer >= respawn_time:
			_respawn()


func _find_collision_shape(node: Node) -> CollisionShape3D:
	"""Recursively find the first CollisionShape3D child"""
	if node is CollisionShape3D:
		return node as CollisionShape3D
	
	for child in node.get_children():
		var result = _find_collision_shape(child)
		if result:
			return result
	
	return null


func _create_audio_player() -> void:
	"""Create audio player for mining sounds"""
	_audio_player = AudioStreamPlayer3D.new()
	_audio_player.name = "MiningSound"
	add_child(_audio_player)
	_audio_player.max_distance = 25.0
	_audio_player.unit_size = 2.0


func _load_hit_sound() -> void:
	"""Load the appropriate hit sound based on ore type"""
	var sound_path = "res://assets/audio/ironhit.ogg"
	
	if ResourceLoader.exists(sound_path):
		_hit_sound = load(sound_path)
		print("OreDeposit: Loaded hit sound from ", sound_path)
	else:
		push_warning("OreDeposit: Hit sound not found at ", sound_path)


func _load_failed_hit_sound() -> void:
	"""Load the failed hit sound (hitwood)"""
	var sound_path = "res://assets/audio/hitwood.ogg"
	
	if ResourceLoader.exists(sound_path):
		_failed_hit_sound = load(sound_path)
		print("OreDeposit: Loaded failed hit sound from ", sound_path)
	else:
		push_warning("OreDeposit: Failed hit sound not found at ", sound_path)


func _create_health_label() -> void:
	"""Create a label showing health"""
	_health_label = Label3D.new()
	_health_label.name = "HealthLabel"
	_health_label.text = str(int(current_health))
	_health_label.font_size = 32
	_health_label.outline_size = 8
	_health_label.modulate = Color(1, 1, 1, 0.8)
	add_child(_health_label)
	_health_label.position = Vector3(0, 0.8, 0)


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	"""Recursively find the first MeshInstance3D child"""
	if node is MeshInstance3D:
		return node as MeshInstance3D
	
	for child in node.get_children():
		var result = _find_mesh_instance(child)
		if result:
			return result
	
	return null


func take_mining_damage(damage: float, hit_position: Vector3, impact_strength: float = 0.5, from_tool: bool = false) -> void:
	"""Called by mining tools or hands when they hit this ore"""
	if _is_depleted:
		return
	
	# Check if this ore requires a tool
	if requires_tool and not from_tool:
		print("OreDeposit: ", ore_type, " requires a tool to mine!")
		# Play a "clank" feedback sound to indicate it can't be broken
		_play_failed_hit_sound(impact_strength)
		return
	
	current_health -= damage
	ore_damaged.emit(current_health)
	
	print("OreDeposit: Took ", damage, " damage. Health: ", current_health, "/", max_health)
	
	# Update health label
	if _health_label:
		_health_label.text = str(max(0, int(current_health)))
		# Flash the label
		var tween = create_tween()
		_health_label.modulate = Color(1, 0.3, 0.3, 1)
		tween.tween_property(_health_label, "modulate", Color(1, 1, 1, 0.8), 0.3)
	
	# Visual feedback
	_show_damage_effect(hit_position)
	
	# Play hit sound
	_play_hit_sound(impact_strength)
	
	# Check if depleted
	if current_health <= 0:
		_on_depleted()


func _play_failed_hit_sound(impact_strength: float = 0.5) -> void:
	"""Play a sound when hitting ore that requires a tool"""
	if not _audio_player or not _failed_hit_sound:
		return
	
	_audio_player.stream = _failed_hit_sound
	_audio_player.pitch_scale = randf_range(0.9, 1.1)
	_audio_player.volume_db = lerpf(-12.0, 0.0, impact_strength)
	_audio_player.play()


func _on_body_entered(body: Node) -> void:
	"""Handle collisions with hands or other bodies"""
	print("OreDeposit: Body entered - ", body.name, " | Is physics_hand: ", body.is_in_group("physics_hand"))
	
	if _is_depleted:
		print("OreDeposit: Ore is depleted, ignoring hit")
		return
	
	# Check if it's a physics hand
	if body.is_in_group("physics_hand"):
		print("OreDeposit: Detected physics hand hit!")
		_handle_hand_hit(body)


func _handle_hand_hit(hand: RigidBody3D) -> void:
	"""Handle damage from hand punching the ore"""
	# Check cooldown
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - _last_hand_hit_time < HAND_HIT_COOLDOWN:
		return
	
	# Get hand velocity
	var hand_velocity = hand.linear_velocity.length()
	
	# Check if velocity is high enough
	if hand_velocity < min_hand_velocity:
		return
	
	_last_hand_hit_time = current_time
	
	# Calculate damage based on impact velocity
	var damage = hand_velocity * hand_damage_multiplier
	var impact_strength = clampf((hand_velocity - min_hand_velocity) / 3.0, 0.0, 1.0)
	
	# Apply damage (from_tool = false since this is a hand)
	take_mining_damage(damage, hand.global_position, impact_strength, false)
	
	print("OreDeposit: Hand hit with velocity ", hand_velocity, " dealing ", damage, " damage")


func _play_hit_sound(impact_strength: float = 0.5) -> void:
	"""Play mining hit sound"""
	if not _audio_player or not _hit_sound:
		return
	
	_audio_player.stream = _hit_sound
	_audio_player.pitch_scale = randf_range(0.9, 1.1)  # Vary pitch slightly
	_audio_player.volume_db = lerpf(-12.0, 0.0, impact_strength)
	_audio_player.play()


func _show_damage_effect(hit_position: Vector3) -> void:
	"""Show visual feedback when damaged"""
	# Flash the material
	if _mesh_instance:
		var tween = create_tween()
		var flash_material = StandardMaterial3D.new()
		flash_material.albedo_color = Color(1, 1, 1, 1)
		flash_material.emission_enabled = true
		flash_material.emission = Color(1, 0.8, 0.5)
		flash_material.emission_energy_multiplier = 2.0
		
		_mesh_instance.material_override = flash_material
		tween.tween_callback(func(): 
			if _mesh_instance and _original_material:
				_mesh_instance.material_override = _original_material
		).set_delay(0.1)
	
	# Shake the ore
	_shake_ore()
	
	# Spawn particle effects
	_spawn_hit_particles(hit_position)


func _shake_ore() -> void:
	"""Shake the ore when hit"""
	var original_pos = position
	var tween = create_tween()
	tween.tween_property(self, "position", original_pos + Vector3(randf_range(-0.05, 0.05), 0, randf_range(-0.05, 0.05)), 0.05)
	tween.tween_property(self, "position", original_pos + Vector3(randf_range(-0.03, 0.03), 0, randf_range(-0.03, 0.03)), 0.05)
	tween.tween_property(self, "position", original_pos, 0.05)


func _spawn_hit_particles(hit_position: Vector3) -> void:
	"""Spawn particle effect at hit location"""
	# Simple particle effect using multiple small cubes
	for i in range(5):
		var particle = MeshInstance3D.new()
		var cube = BoxMesh.new()
		cube.size = Vector3(0.05, 0.05, 0.05)
		particle.mesh = cube
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.5, 0.4)
		particle.material_override = mat
		
		get_parent().add_child(particle)
		particle.global_position = hit_position
		
		# Random velocity
		var velocity = Vector3(
			randf_range(-1, 1),
			randf_range(0.5, 2),
			randf_range(-1, 1)
		)
		
		# Animate particle with proper cleanup
		var tween = create_tween()
		tween.tween_property(particle, "global_position", 
			particle.global_position + velocity * 0.3, 0.5)
		tween.parallel().tween_property(particle, "scale", Vector3.ZERO, 0.5)
		tween.tween_callback(func():
			if is_instance_valid(particle):
				particle.queue_free()
		)


func _on_depleted() -> void:
	"""Called when ore is fully mined"""
	var loot_amount = randi_range(loot_amount_min, loot_amount_max)
	
	print("OreDeposit: Depleted! Dropping ", loot_amount, " ", ore_type)
	
	# Award currency based on ore type
	_award_currency()
	
	if drop_loot:
		_drop_loot(loot_amount)
	else:
		# Add directly to inventory
		if InventoryManager.instance:
			InventoryManager.instance.add_item(ore_type, loot_amount)
	
	ore_depleted.emit(ore_type, loot_amount)
	
	# Hide the ore deposit instead of destroying it
	_is_depleted = true
	_respawn_timer = 0.0
	_hide_ore()


func _award_currency() -> void:
	"""Award currency when ore is mined"""
	if not InventoryManager.instance:
		return
	
	# Award different currencies based on ore type
	match ore_type:
		"iron":
			# Iron gives tokens (yellow currency)
			var token_amount = randi_range(5, 15)
			InventoryManager.instance.add_item("tokens", token_amount)
			print("OreDeposit: Awarded ", token_amount, " tokens for iron ore")
		"gold":
			# Gold gives gold currency
			var gold_amount = randi_range(15, 30)
			InventoryManager.instance.add_item("gold", gold_amount)
			print("OreDeposit: Awarded ", gold_amount, " gold for gold ore")
		"plasma":
			# Plasma gives gems (blue currency)
			var gem_amount = randi_range(10, 20)
			InventoryManager.instance.add_item("gems", gem_amount)
			print("OreDeposit: Awarded ", gem_amount, " gems for plasma ore")
		"copper":
			# Copper gives fewer tokens
			var token_amount = randi_range(2, 8)
			InventoryManager.instance.add_item("tokens", token_amount)
			print("OreDeposit: Awarded ", token_amount, " tokens for copper ore")
		_:
			# Default: give tokens
			var token_amount = randi_range(3, 10)
			InventoryManager.instance.add_item("tokens", token_amount)
			print("OreDeposit: Awarded ", token_amount, " tokens for ", ore_type, " ore")


func _hide_ore() -> void:
	"""Hide the ore deposit visually and disable collision"""
	if _mesh_instance:
		_mesh_instance.visible = false
	if _health_label:
		_health_label.visible = false
	if _collision_shape:
		_collision_shape.disabled = true
	
	# Disable collision
	collision_layer = 0


func _respawn() -> void:
	"""Respawn the ore deposit"""
	print("OreDeposit: Respawning ", ore_type)
	
	_is_depleted = false
	current_health = max_health
	
	# Show the ore deposit
	if _mesh_instance:
		_mesh_instance.visible = true
	if _health_label:
		_health_label.visible = true
		_health_label.text = str(int(current_health))
	if _collision_shape:
		_collision_shape.disabled = false
	
	# Re-enable collision
	collision_layer = 1
	
	# Play respawn effect
	_play_respawn_effect()
	
	ore_respawned.emit()


func _play_respawn_effect() -> void:
	"""Visual effect for respawning"""
	if not _mesh_instance:
		return
	
	# Flash effect
	var tween = create_tween()
	var flash_material = StandardMaterial3D.new()
	flash_material.albedo_color = Color(1, 1, 1, 1)
	flash_material.emission_enabled = true
	flash_material.emission = Color(0.5, 1, 0.5)
	flash_material.emission_energy_multiplier = 3.0
	
	_mesh_instance.material_override = flash_material
	tween.tween_callback(func(): 
		if _mesh_instance and _original_material:
			_mesh_instance.material_override = _original_material
	).set_delay(0.3)
	
	# Spawn particles
	for i in range(10):
		var particle = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 0.05
		particle.mesh = sphere
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 1, 0.5, 0.8)
		mat.emission_enabled = true
		mat.emission = Color(0.5, 1, 0.5)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		particle.material_override = mat
		
		get_parent().add_child(particle)
		particle.global_position = global_position + Vector3(0, 0.5, 0)
		
		var direction = Vector3(
			randf_range(-1, 1),
			randf_range(0, 1),
			randf_range(-1, 1)
		).normalized()
		
		var particle_tween = create_tween()
		particle_tween.tween_property(particle, "global_position",
			particle.global_position + direction * 1.0, 0.8)
		particle_tween.parallel().tween_property(particle, "scale", Vector3.ZERO, 0.8)
		particle_tween.tween_callback(func():
			if is_instance_valid(particle):
				particle.queue_free()
		)


func _drop_loot(amount: int) -> void:
	"""Drop loot items in the world"""
	for i in range(amount):
		var loot = _create_loot_item()
		get_parent().add_child(loot)
		
		# Position with slight offset
		var offset = Vector3(
			randf_range(-0.3, 0.3),
			0.5 + i * 0.2,
			randf_range(-0.3, 0.3)
		)
		loot.global_position = global_position + offset
		
		# Apply random impulse for scatter effect
		if loot is RigidBody3D:
			var impulse = Vector3(
				randf_range(-1.5, 1.5),
				randf_range(2.0, 4.0),
				randf_range(-1.5, 1.5)
			)
			loot.apply_central_impulse(impulse)
		
		# Find player for magnet effect
		var player = get_tree().get_first_node_in_group("player_body")
		if player and loot.has_node("PickupArea"):
			var pickup_area = loot.get_node("PickupArea")
			if pickup_area.has_method("set_player_reference"):
				pickup_area.set_player_reference(player)


func _create_loot_item() -> Node3D:
	"""Create a loot item that can be picked up with physics"""
	# Load the OreChunk script
	var OreChunkScript = load("res://src/objects/OreChunk.gd")
	
	# Use RigidBody3D for gravity and physics
	var loot = RigidBody3D.new()
	loot.name = ore_type + "_chunk"
	loot.mass = 0.5
	loot.gravity_scale = 1.0
	loot.collision_layer = 2  # Layer 2 for loot
	loot.collision_mask = 1   # Collide with environment
	
	# Add Area3D as child for pickup detection
	var pickup_area = Area3D.new()
	pickup_area.name = "PickupArea"
	pickup_area.script = OreChunkScript
	pickup_area.set("ore_type", ore_type)
	pickup_area.set("amount", 1)
	pickup_area.collision_layer = 0
	pickup_area.collision_mask = 1  # Detect player
	loot.add_child(pickup_area)
	
	# Collision shape for physics
	var physics_collision = CollisionShape3D.new()
	var physics_shape = BoxShape3D.new()
	physics_shape.size = Vector3(0.12, 0.12, 0.12)
	physics_collision.shape = physics_shape
	loot.add_child(physics_collision)
	
	# Collision shape for pickup detection
	var pickup_collision = CollisionShape3D.new()
	var pickup_shape = SphereShape3D.new()
	pickup_shape.radius = 0.2
	pickup_collision.shape = pickup_shape
	pickup_area.add_child(pickup_collision)
	
	# Mesh
	var mesh_inst = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(0.1, 0.1, 0.1)
	mesh_inst.mesh = box_mesh
	
	# Material based on ore type
	match ore_type:
		"iron":
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.7, 0.7, 0.7)
			mat.metallic = 0.8
			mat.emission_enabled = true
			mat.emission = mat.albedo_color * 0.3
			mesh_inst.material_override = mat
		"gold":
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(1.0, 0.84, 0.0)
			mat.metallic = 1.0
			mat.emission_enabled = true
			mat.emission = mat.albedo_color * 0.3
			mesh_inst.material_override = mat
		"plasma":
			# Use the plasma shader material
			var plasma_mat = load("res://src/demos/tools/materials/plasma.tres")
			if plasma_mat:
				mesh_inst.material_override = plasma_mat
			else:
				# Fallback to cyan glow
				var mat = StandardMaterial3D.new()
				mat.albedo_color = Color(0, 1, 1)
				mat.metallic = 0.5
				mat.emission_enabled = true
				mat.emission = Color(0, 1, 1)
				mat.emission_energy_multiplier = 2.0
				mesh_inst.material_override = mat
		"copper":
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.72, 0.45, 0.2)
			mat.metallic = 0.6
			mat.emission_enabled = true
			mat.emission = mat.albedo_color * 0.3
			mesh_inst.material_override = mat
		_:
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.5, 0.5, 0.5)
			mat.emission_enabled = true
			mat.emission = mat.albedo_color * 0.3
			mesh_inst.material_override = mat
	
	loot.add_child(mesh_inst)
	
	# Add label
	var label = Label3D.new()
	label.text = ore_type
	label.font_size = 16
	label.outline_size = 4
	label.position = Vector3(0, 0.15, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	loot.add_child(label)
	
	# Add to groups
	loot.add_to_group("loot")
	loot.add_to_group("ore_chunk")
	
	return loot
