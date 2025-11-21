# Base Interactor
# Base class for all interaction sources (ray pointer, poke, mouse, etc.)
extends Node3D
class_name BaseInteractor

## Emitted when this interactor begins hovering over an interactable
signal hover_entered(interactable: BaseInteractable)
## Emitted when this interactor stops hovering over an interactable
signal hover_exited(interactable: BaseInteractable)
## Emitted when this interactor selects an interactable
signal select_started(interactable: BaseInteractable)
## Emitted when this interactor deselects an interactable
signal select_ended(interactable: BaseInteractable)
## Emitted when this interactor activates an interactable
signal activated(interactable: BaseInteractable)

@export_flags_3d_physics var interaction_layer_mask: int = 1 << 5  # Layer 6 for interactables
@export var can_hover: bool = true
@export var can_select: bool = true
@export var hover_timeout: float = 0.0  # 0 = no timeout

# Current interaction state
var hover_target: BaseInteractable = null
var select_target: BaseInteractable = null
var is_selecting: bool = false

# Internal
var _hover_timer: float = 0.0


func _ready() -> void:
	# Register with interaction manager
	if InteractionManager:
		InteractionManager.register_interactor(self)


func _exit_tree() -> void:
	# Unregister from interaction manager
	if InteractionManager:
		InteractionManager.unregister_interactor(self)
	
	# Clean up active interactions
	_clear_hover()
	_end_select()


func _physics_process(delta: float) -> void:
	# Update hover timeout
	if hover_target and hover_timeout > 0.0:
		_hover_timer += delta
		if _hover_timer >= hover_timeout:
			_clear_hover()


## Override this in subclasses to implement detection logic
## Should return the interactable currently targeted, or null
func _detect_interactable() -> BaseInteractable:
	return null


## Override this in subclasses to check if select action is pressed
func _is_select_pressed() -> bool:
	return false


## Override this in subclasses to check if activate action is pressed
func _is_activate_pressed() -> bool:
	return false


## Process interactions - call this from subclass _physics_process
func process_interaction() -> void:
	var detected: BaseInteractable = _detect_interactable()
	
	# Update hover state
	if can_hover:
		if detected != hover_target:
			_clear_hover()
			if detected:
				_set_hover(detected)
	
	# Update select state
	if can_select:
		var select_pressed = _is_select_pressed()
		
		if select_pressed and not is_selecting:
			# Start selecting
			if detected:
				_start_select(detected)
		elif not select_pressed and is_selecting:
			# End selecting
			_end_select()
	
	# Check activate
	if _is_activate_pressed() and detected:
		_activate(detected)


func _set_hover(interactable: BaseInteractable) -> void:
	if not interactable or not can_hover:
		return
	
	# Check if interactable accepts this interactor
	if not interactable._can_interact_with(self):
		return
	
	hover_target = interactable
	_hover_timer = 0.0
	hover_target._on_hover_entered(self)
	hover_entered.emit(hover_target)


func _clear_hover() -> void:
	if hover_target:
		var prev_target = hover_target
		hover_target = null
		_hover_timer = 0.0
		prev_target._on_hover_exited(self)
		hover_exited.emit(prev_target)


func _start_select(interactable: BaseInteractable) -> void:
	if not interactable or not can_select:
		return
	
	# Check if interactable accepts this interactor
	if not interactable._can_interact_with(self):
		return
	
	# Check if interactable can be selected
	if not interactable._can_select(self):
		return
	
	select_target = interactable
	is_selecting = true
	select_target._on_select_started(self)
	select_started.emit(select_target)


func _end_select() -> void:
	if select_target:
		var prev_target = select_target
		select_target = null
		is_selecting = false
		prev_target._on_select_ended(self)
		select_ended.emit(prev_target)


func _activate(interactable: BaseInteractable) -> void:
	if not interactable:
		return
	
	if not interactable._can_interact_with(self):
		return
	
	interactable._on_activated(self)
	activated.emit(interactable)


## Get the interaction point in world space (override in subclasses)
func get_interaction_point() -> Vector3:
	return global_position


## Get the interaction normal in world space (override in subclasses)
func get_interaction_normal() -> Vector3:
	return -global_transform.basis.z
