extends Area3D
class_name OreChunk

## Ore Chunk - Auto-pickup loot that adds to inventory on player touch

@export var ore_type: String = "iron"
@export var amount: int = 1
@export var lifetime: float = 30.0  # Despawn after this time if not collected
@export var magnet_range: float = 1.5  # Range to attract to player

var _lifetime_timer: float = 0.0
var _player_body: Node3D = null
var _collected: bool = false
var _mesh_instance: MeshInstance3D = null


func _ready() -> void:
	# Set up collision for player detection
	collision_layer = 0
	collision_mask = 1  # Layer 1 for player
	
	# Connect signals
	body_entered.connect(_on_body_entered)
	
	# Add to group
	add_to_group("ore_chunk")
	add_to_group("loot")
	
	# Find mesh instance for visual effects
	for child in get_children():
		if child is MeshInstance3D:
			_mesh_instance = child
			break
	
	print("OreChunk: Created - ", ore_type, " x", amount)


func _physics_process(delta: float) -> void:
	# Lifetime countdown
	_lifetime_timer += delta
	if _lifetime_timer >= lifetime:
		print("OreChunk: Despawning due to lifetime")
		_despawn()
		return
	
	# Fade out near end of lifetime
	if _lifetime_timer > lifetime - 2.0:
		var fade = 1.0 - (_lifetime_timer - (lifetime - 2.0)) / 2.0
		_apply_fade(fade)
	
	# Magnet effect - move toward player if nearby
	if _player_body and is_instance_valid(_player_body) and not _collected:
		var target_pos = _player_body.global_position
		var current_pos = global_position
		var distance = current_pos.distance_to(target_pos)
		
		if distance < magnet_range:
			var direction = (target_pos - current_pos).normalized()
			var speed = 5.0 * (1.0 - distance / magnet_range)  # Faster when closer
			
			# If parent is RigidBody3D, apply force instead of direct position change
			var parent_body = get_parent()
			if parent_body is RigidBody3D:
				parent_body.apply_central_force(direction * speed * 50.0)
			else:
				global_position += direction * speed * delta


func _on_body_entered(body: Node3D) -> void:
	"""Called when player touches the chunk"""
	if _collected:
		return
	
	# Check if it's the player
	if body.is_in_group("player_body") or body.name.contains("PlayerBody"):
		_collect()
		return
	
	# Store player reference for magnet effect
	if body.is_in_group("player_body"):
		_player_body = body


func _collect() -> void:
	"""Collect the chunk and add to inventory"""
	if _collected:
		return
	
	_collected = true
	
	# Add to inventory
	if InventoryManager.instance:
		InventoryManager.instance.add_item(ore_type, amount)
	else:
		print("OreChunk: Warning - No InventoryManager found!")
	
	# Play collection effect
	_play_collection_effect()
	
	# Remove the chunk (and parent if it's a RigidBody3D)
	_despawn()


func _despawn() -> void:
	"""Remove the chunk and its parent if needed"""
	var parent_body = get_parent()
	if parent_body is RigidBody3D:
		parent_body.queue_free()
	else:
		queue_free()


func _play_collection_effect() -> void:
	"""Visual/audio feedback for collection"""
	# Spawn a quick particle burst
	var particles = []
	for i in range(8):
		var particle = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 0.02
		particle.mesh = sphere
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = _get_ore_color()
		mat.emission_enabled = true
		mat.emission = _get_ore_color()
		mat.emission_energy_multiplier = 2.0
		particle.material_override = mat
		
		get_parent().add_child(particle)
		particle.global_position = global_position
		
		# Random direction
		var direction = Vector3(
			randf_range(-1, 1),
			randf_range(0.5, 1.5),
			randf_range(-1, 1)
		).normalized()
		
		# Animate
		var tween = create_tween()
		tween.tween_property(particle, "global_position", 
			particle.global_position + direction * 0.5, 0.4)
		tween.parallel().tween_property(particle, "scale", Vector3.ZERO, 0.4)
		tween.tween_callback(particle.queue_free)
	
	print("OreChunk: Collected ", ore_type, " x", amount)


func _get_ore_color() -> Color:
	"""Get color based on ore type"""
	match ore_type:
		"iron":
			return Color(0.7, 0.7, 0.7)
		"gold":
			return Color(1.0, 0.84, 0.0)
		"copper":
			return Color(0.72, 0.45, 0.2)
		_:
			return Color(0.5, 0.5, 0.5)


func set_player_reference(player: Node3D) -> void:
	"""Set the player reference for magnet effect"""
	_player_body = player


func _apply_fade(fade: float) -> void:
	"""Apply transparency to the mesh instance"""
	if not _mesh_instance:
		return
		
	var mat = _mesh_instance.material_override as StandardMaterial3D
	if mat:
		# Ensure transparency is enabled
		if mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		
		var current_color = mat.albedo_color
		current_color.a = fade
		mat.albedo_color = current_color
		
		if mat.emission_enabled:
			mat.emission_energy_multiplier = 0.3 * fade
