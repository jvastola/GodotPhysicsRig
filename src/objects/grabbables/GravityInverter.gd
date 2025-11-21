extends Grabbable
class_name GravityInverter

# Fun grabbable that unlocks the player's angular axis locks when held
# This allows the player to tumble and rotate freely!

var player_body: RigidBody3D = null
var original_lock_x: bool = false
var original_lock_y: bool = false
var original_lock_z: bool = false


func _ready() -> void:
	super._ready()
	
	# Connect to grab signals
	grabbed.connect(_on_grabbed)
	released.connect(_on_released)


func _on_grabbed(hand: RigidBody3D) -> void:
	"""When grabbed, unlock the player's angular axis"""
	# Find the player body through the hand
	if hand and hand.has_method("get"):
		player_body = hand.get("player_rigidbody")
		
		if player_body and player_body is RigidBody3D:
			# Store original lock states
			original_lock_x = player_body.axis_lock_angular_x
			original_lock_y = player_body.axis_lock_angular_y
			original_lock_z = player_body.axis_lock_angular_z
			
			# Unlock all angular axes - player can now tumble!
			player_body.axis_lock_angular_x = false
			player_body.axis_lock_angular_y = false
			player_body.axis_lock_angular_z = false
			
			print("GravityInverter: Angular locks disabled - prepare to tumble!")


func _on_released() -> void:
	"""When released, restore the player's angular axis locks"""
	if is_instance_valid(player_body):
		# Restore original lock states
		player_body.axis_lock_angular_x = original_lock_x
		player_body.axis_lock_angular_y = original_lock_y
		player_body.axis_lock_angular_z = original_lock_z
		
		# Stop any residual angular velocity for safety
		player_body.angular_velocity = Vector3.ZERO
		
		print("GravityInverter: Angular locks restored")
	
	player_body = null
