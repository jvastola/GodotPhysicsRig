extends CharacterBody3D

# Simple Player Body - basic physics body that follows the camera
# In zero-G world grab mode, this just tracks position without physics

@onready var origin_node: XROrigin3D = get_parent()
@onready var camera_node: XRCamera3D = origin_node.get_node("XRCamera3D")

var player_radius = 0.3
var player_height = 1.8

func _ready():
	# Create collision shape
	var capsule = CapsuleShape3D.new()
	capsule.radius = player_radius
	capsule.height = player_height
	
	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = capsule
	collision_shape.transform.origin = Vector3(0, player_height/2, 0)
	add_child(collision_shape)
	
	# Set as top level so it's positioned in global space
	set_as_top_level(true)

func _physics_process(_delta):
	# Simply follow the camera position - no gravity in world grab mode
	if camera_node:
		var camera_pos = camera_node.global_transform.origin
		global_transform.origin = Vector3(camera_pos.x, camera_pos.y - player_height/2, camera_pos.z)
	
	# Zero velocity - world grab handles all movement
	velocity = Vector3.ZERO