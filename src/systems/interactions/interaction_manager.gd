# Interaction Manager (Autoload)
# Central manager for the interaction system
# Manages registration and coordination of interactors and interactables
extends Node

var _interactors: Array[BaseInteractor] = []
var _interactables: Array[BaseInteractable] = []

@export var debug_visualization: bool = false


func _ready() -> void:
	print("InteractionManager: Initialized")


func register_interactor(interactor: BaseInteractor) -> void:
	if not _interactors.has(interactor):
		_interactors.append(interactor)
		print("InteractionManager: Registered interactor - ", interactor.name)


func unregister_interactor(interactor: BaseInteractor) -> void:
	_interactors.erase(interactor)
	print("InteractionManager: Unregistered interactor - ", interactor.name)


func register_interactable(interactable: BaseInteractable) -> void:
	if not _interactables.has(interactable):
		_interactables.append(interactable)
		print("InteractionManager: Registered interactable - ", interactable.name)


func unregister_interactable(interactable: BaseInteractable) -> void:
	_interactables.erase(interactable)
	print("InteractionManager: Unregistered interactable - ", interactable.name)


func get_valid_targets(interactor: BaseInteractor) -> Array[BaseInteractable]:
	"""Get all interactables that the given interactor can interact with"""
	var valid_targets: Array[BaseInteractable] = []
	
	for interactable in _interactables:
		if not is_instance_valid(interactable):
			continue
		
		if interactable._can_interact_with(interactor):
			valid_targets.append(interactable)
	
	return valid_targets


func get_interactor_count() -> int:
	return _interactors.size()


func get_interactable_count() -> int:
	return _interactables.size()


func _physics_process(_delta: float) -> void:
	# Clean up invalid references
	_interactors = _interactors.filter(func(x): return is_instance_valid(x))
	_interactables = _interactables.filter(func(x): return is_instance_valid(x))
