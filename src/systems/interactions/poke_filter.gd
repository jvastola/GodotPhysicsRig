# Poke Filter
# Component that defines poke-specific interaction constraints
# Attach to BaseInteractable to make it respond to poke interactions
extends Node
class_name PokeFilter

@export var required_poke_direction: Vector3 = Vector3(0, 0, 1)  # Local space direction
@export var direction_tolerance: float = 0.5  # Dot product threshold (0-1)
@export var min_poke_depth: float = 0.01
@export var max_poke_depth: float = 0.05

var parent_interactable: BaseInteractable = null


func _ready() -> void:
	# Find parent interactable
	var parent = get_parent()
	if parent is BaseInteractable:
		parent_interactable = parent as BaseInteractable


## Check if a poke from the given direction and depth is valid
func is_valid_poke(poke_direction: Vector3, depth: float) -> bool:
	# Check depth
	if depth < min_poke_depth or depth > max_poke_depth:
		return false
	
	# Check direction
	if required_poke_direction.length_squared() > 0:
		var parent_node = parent_interactable.get_parent() if parent_interactable else get_parent()
		if parent_node is Node3D:
			var local_required = (parent_node as Node3D).global_transform.basis * required_poke_direction
			var dot = poke_direction.normalized().dot(local_required.normalized())
			if dot < direction_tolerance:
				return false
	
	return true
