extends Grabbable
class_name SpeedBooster

# Fun grabbable that increases the player's movement speed when held
# Gotta go fast!

var movement_component: Node = null
var original_speed: float = 0.0
var speed_multiplier: float = 2.5


func _ready() -> void:
	super._ready()
	
	# Connect to grab signals
	grabbed.connect(_on_grabbed)
	released.connect(_on_released)


func _on_grabbed(_hand: RigidBody3D) -> void:
	"""When grabbed, boost the player's movement speed"""
	# Find the player movement component through the scene tree
	var xr_player = get_tree().get_first_node_in_group("xr_player")
	
	if xr_player:
		movement_component = xr_player.get_node_or_null("PlayerMovementComponent")
		
		if movement_component and movement_component.has_method("get"):
			# Check if the movement component has a speed property
			if "movement_speed" in movement_component:
				original_speed = movement_component.get("movement_speed")
				movement_component.set("movement_speed", original_speed * speed_multiplier)
				print("SpeedBooster: Movement speed boosted to ", original_speed * speed_multiplier)
			elif "speed" in movement_component:
				original_speed = movement_component.get("speed")
				movement_component.set("speed", original_speed * speed_multiplier)
				print("SpeedBooster: Movement speed boosted to ", original_speed * speed_multiplier)
			else:
				print("SpeedBooster: Could not find speed property on movement component")


func _on_released() -> void:
	"""When released, restore the player's movement speed"""
	if movement_component and is_instance_valid(movement_component):
		if "movement_speed" in movement_component:
			movement_component.set("movement_speed", original_speed)
			print("SpeedBooster: Movement speed restored to ", original_speed)
		elif "speed" in movement_component:
			movement_component.set("speed", original_speed)
			print("SpeedBooster: Movement speed restored to ", original_speed)
	
	movement_component = null
	original_speed = 0.0
