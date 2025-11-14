extends StaticBody3D

@export var rotation_speed: float = 1.0 # radians per second

func _ready() -> void:
	# Ensure this object is on the same physics layer the grapple raycast checks
	collision_layer = 1

func _physics_process(delta: float) -> void:
	# Rotate around the Y axis so it stays capturable by grapples and to show movement
	rotate_y(rotation_speed * delta)
