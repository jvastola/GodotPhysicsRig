# Pokeable Button
# Responds to PokeInteractor (BaseInteractable system) and XRPlayer (handle_pointer_event system)
extends StaticBody3D
class_name PokeableButton

## Emitted when the button is pressed past the threshold
signal pressed()
## Emitted when the button is released
signal released()

@export_group("Button Settings")
@export var button_visual_path: NodePath
@export var press_threshold: float = 0.8  # 0 to 1, percentage of max_travel
@export var max_travel: float = 0.02      # Maximum distance the button can move (meters)
@export var surface_offset: float = 0.02  # Local Z where interaction starts
@export var return_speed: float = 10.0    # Speed at which the button returns to start position
@export var click_haptic_intensity: float = 0.6
@export var click_haptic_duration: float = 0.05

@export_group("Audio")
@export var press_sound: AudioStream
@export var release_sound: AudioStream

# Internal state
var _button_visual: Node3D
var _initial_local_pos: Vector3
var _current_displacement: float = 0.0
var _is_pressed: bool = false
var _audio_player: AudioStreamPlayer3D
var _active_poke_pos: Vector3 = Vector3.ZERO
var _is_being_poked: bool = false
var _child_interactable: BaseInteractable = null

func _ready() -> void:
	if not button_visual_path.is_empty():
		_button_visual = get_node(button_visual_path)
		_initial_local_pos = _button_visual.position
	else:
		_button_visual = null
		push_warning("PokeableButton: button_visual_path is empty")

	_audio_player = AudioStreamPlayer3D.new()
	add_child(_audio_player)
	_audio_player.max_distance = 5.0
	_audio_player.unit_size = 2.0
	
	# Find a child BaseInteractable for the standard interaction system
	for child in get_children():
		if child is BaseInteractable:
			_child_interactable = child as BaseInteractable
			break


## Support for XRPlayer's built-in poke system
func handle_pointer_event(event: Dictionary) -> void:
	var type = event.get("type", "")
	var global_pos = event.get("global_position", Vector3.ZERO)
	
	if type == "press" or type == "hold":
		_active_poke_pos = global_pos
		_is_being_poked = true
	elif type == "release":
		_is_being_poked = false


func _process(delta: float) -> void:
	var target_displacement: float = 0.0
	var deepest_interactor: Node = null
	
	# 1. Check selecting interactors from child BaseInteractable (standard system)
	if _child_interactable:
		for interactor in _child_interactable.selecting_interactors:
			if interactor.has_method("get_interaction_point"):
				var interactor_pos = interactor.get_interaction_point()
				var local_pos = to_local(interactor_pos)
				
				var displacement = surface_offset - local_pos.z
				if displacement > target_displacement:
					target_displacement = displacement
					deepest_interactor = interactor
	
	# 2. Check active poke from handle_pointer_event (XRPlayer system)
	if _is_being_poked:
		var local_pos = to_local(_active_poke_pos)
		var displacement = surface_offset - local_pos.z
		if displacement > target_displacement:
			target_displacement = displacement
	
	# Update visual displacement
	if target_displacement <= 0.001:
		_current_displacement = lerp(_current_displacement, 0.0, return_speed * delta)
	else:
		_current_displacement = clamp(target_displacement, 0.0, max_travel)
	
	# Apply visual displacement
	if _button_visual:
		_button_visual.position = _initial_local_pos + Vector3(0, 0, -_current_displacement)
	
	# Check for press/release events
	var normalized_press = _current_displacement / max_travel
	if not _is_pressed and normalized_press >= press_threshold:
		_on_button_pressed(deepest_interactor)
	elif _is_pressed and normalized_press < (press_threshold * 0.8): # Hysteresis
		_on_button_released(deepest_interactor)


func _on_button_pressed(interactor: Node) -> void:
	_is_pressed = true
	pressed.emit()
	
	# Feedback
	_play_sound(press_sound)
	if interactor:
		_trigger_haptic_on_interactor(interactor)


func _on_button_released(_interactor: Node) -> void:
	_is_pressed = false
	released.emit()
	_play_sound(release_sound)


func _play_sound(stream: AudioStream) -> void:
	if stream and _audio_player:
		_audio_player.stream = stream
		_audio_player.play()


func _trigger_haptic_on_interactor(interactor: Node) -> void:
	# Try to trigger haptics on the node or its parents
	var node = interactor
	while node:
		if node.has_method("trigger_haptic_pulse"):
			node.trigger_haptic_pulse("haptic", 0.0, click_haptic_intensity, click_haptic_duration, 0.0)
			break
		node = node.get_parent()
