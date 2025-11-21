extends Node3D
## Test scene for demonstrating the grid-snapping mesh

@export var movement_speed: float = .20
@export var movement_range: float = 3.0

var time: float = 0.0

@onready var grid_snap_mesh: RigidBody3D = $GridSnapMesh

func _process(delta: float) -> void:
	time += delta
	
	# Move the mesh in a circular pattern to demonstrate grid snapping
	var x := sin(time * movement_speed) * movement_range
	var z := cos(time * movement_speed) * movement_range
	
	grid_snap_mesh.global_position = Vector3(x, 1.0, z)
