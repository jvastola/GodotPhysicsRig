extends StaticBody3D
class_name OreDeposit

## Ore Deposit - Can be mined for resources

@export var ore_type: String = "iron"
@export var max_health: float = 100.0
@export var loot_amount_min: int = 1
@export var loot_amount_max: int = 3
@export var respawn_time: float = 30.0  # Time to respawn after being mined
@export var drop_loot: bool = true  # If false, adds directly to inventory

var current_health: float = 100.0
var _mesh_instance: MeshInstance3D
var _original_material: Material
var _audio_player: AudioStreamPlayer3D
var _health_label: Label3D
var _is_depleted: bool = false
var _respawn_timer: float = 0.0
var _collision_shape: CollisionShape3D

signal ore_depleted(ore_type: String, amount: int)
signal ore_damaged(health_remaining: float)
signal ore_respawned()


func _ready() -> void:
	current_health = max_health
	add_to_group("ore_deposit")
	
	# Set collision layer/mask for proper physics interaction
	# Layer 1 (default) so the stick can collide with it
	collision_layer = 1
	collision_mask = 0  # Doesn't need to detect anything
	
	# Find mesh instance for visual feedback
	_mesh_instance = _find_mesh_instance(self)
	if _mesh_instance and _mesh_instance.material_override:
		_original_material = _mesh_instance.material_override
	
	# Find collision shape
	_collision_shape = _find_collision_shape(self)
	
	# Create audio player
	_create_audio_player()
	
	# Create health label
	_create_health_label()
	
	print("OreDeposit: Ready - Type: ", ore_type, " Health: ", max_health, " Collision Layer: ", collision_layer)


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


func take_mining_damage(damage: float, hit_position: Vector3) -> void:
	"""Called by mining tools when they hit this ore"""
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
	_play_hit_sound()
	
	# Check if depleted
	if current_health <= 0:
		_on_depleted()


func _play_hit_sound() -> void:
	"""Play mining hit sound"""
	if not _audio_player:
		return
	
	# Create a rock hit sound (low frequency thud)
	var stream = AudioStreamGenerator.new()
	stream.mix_rate = 22050
	stream.buffer_length = 0.15
	
	_audio_player.stream = stream
	_audio_player.pitch_scale = randf_range(0.9, 1.1)  # Vary pitch slightly
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
		
		# Find player for magnet effect
		var player = get_tree().get_first_node_in_group("player_body")
		if player:
			loot.set_player_reference(player)


func _create_loot_item() -> Node3D:
	"""Create a loot item that can be picked up"""
	# Load the OreChunk script
	var OreChunkScript = load("res://src/objects/OreChunk.gd")
	
	var loot = Area3D.new()
	loot.name = ore_type + "_chunk"
	loot.script = OreChunkScript
	loot.set("ore_type", ore_type)
	loot.set("amount", 1)
	
	# Collision shape for pickup detection
	var collision = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.15
	collision.shape = shape
	loot.add_child(collision)
	
	# Mesh
	var mesh_inst = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(0.1, 0.1, 0.1)
	mesh_inst.mesh = box_mesh
	
	# Material based on ore type
	var mat = StandardMaterial3D.new()
	match ore_type:
		"iron":
			mat.albedo_color = Color(0.7, 0.7, 0.7)
			mat.metallic = 0.8
		"gold":
			mat.albedo_color = Color(1.0, 0.84, 0.0)
			mat.metallic = 1.0
		"copper":
			mat.albedo_color = Color(0.72, 0.45, 0.2)
			mat.metallic = 0.6
		_:
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
