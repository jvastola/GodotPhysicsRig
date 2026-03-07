@tool
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
@export var key_character: String = "A":
	set(value):
		key_character = value
		if is_inside_tree():
			call_deferred("_update_label")
@export var width: float = 0.06:
	set(value):
		width = value
		_update_visuals()
@export var height: float = 0.06:
	set(value):
		height = value
		_update_visuals()
@export var press_threshold: float = 0.8  # 0 to 1, percentage of max_travel
@export var max_travel: float = 0.02      # Maximum distance the button can move (meters)
@export var surface_offset: float = 0.02  # Local Z where interaction starts
@export var return_speed: float = 10.0    # Speed at which the button returns to start position
@export var click_haptic_intensity: float = 0.6
@export var click_haptic_duration: float = 0.05

@export_group("Audio")
@export var press_sound: AudioStream
@export var release_sound: AudioStream
@export var pitch_randomness: float = 0.1  # Random pitch variation (0.0 = none, 1.0 = max)

# Internal state
var _button_visual: Node3D
var _initial_local_pos: Vector3
var _current_displacement: float = 0.0
var _is_pressed: bool = false
var _audio_player: AudioStreamPlayer3D
var _active_poke_pos: Vector3 = Vector3.ZERO
var _is_being_poked: bool = false
var _child_interactable: BaseInteractable = null

func get_collider() -> CollisionObject3D:
	return self


func _update_label() -> void:
	if not is_inside_tree():
		return
	
	# Wait one frame to ensure all nodes are ready
	await get_tree().process_frame
	
	var label: Label3D = null
	
	# Try to get button visual first
	if not _button_visual and not button_visual_path.is_empty():
		_button_visual = get_node_or_null(button_visual_path)
	
	# Look for label in button visual
	if _button_visual:
		label = _button_visual.get_node_or_null("KeyLabel") as Label3D
	
	# Fallback: search common locations
	if not label:
		label = get_node_or_null("ButtonVisual/KeyLabel") as Label3D
	
	# Last resort: recursive search
	if not label:
		label = _find_label3d_recursive(self)
		
	if label:
		label.text = key_character
	else:
		push_warning("PokeableButton: Could not find KeyLabel for key_character: " + key_character)


func _find_label3d_recursive(node: Node) -> Label3D:
	"""Recursively find the first Label3D in the node tree"""
	for child in node.get_children():
		if child is Label3D:
			return child as Label3D
		var found = _find_label3d_recursive(child)
		if found:
			return found
	return null

func _ready() -> void:
	if not button_visual_path.is_empty():
		_button_visual = get_node(button_visual_path)
		if _button_visual:
			_initial_local_pos = _button_visual.position
	
	_update_visuals()
	# Defer label update to ensure all nodes are ready
	call_deferred("_update_label")

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
	if _child_interactable and "selecting_interactors" in _child_interactable:
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
		# Add pitch randomness
		if pitch_randomness > 0.0:
			_audio_player.pitch_scale = 1.0 + randf_range(-pitch_randomness, pitch_randomness)
		else:
			_audio_player.pitch_scale = 1.0
		_audio_player.play()
func _update_visuals() -> void:
	if not is_inside_tree(): return
	
	# Update Collision Shape
	var collision_shape = get_node_or_null("CollisionShape3D")
	if collision_shape and collision_shape.shape:
		if not Engine.is_editor_hint():
			collision_shape.shape = collision_shape.shape.duplicate()
		var shape = collision_shape.shape as BoxShape3D
		if shape:
			shape.size = Vector3(width, height, 0.04)
	
	# Update Frame Mesh
	var frame = get_node_or_null("Frame")
	if frame and frame.mesh:
		if not Engine.is_editor_hint():
			frame.mesh = frame.mesh.duplicate()
		var mesh = frame.mesh as BoxMesh
		if mesh:
			mesh.size = Vector3(width, height, 0.02)
			
	# Update Button Visual Mesh
	if not _button_visual:
		_button_visual = get_node_or_null(button_visual_path)
	
	if _button_visual and _button_visual is MeshInstance3D:
		if not Engine.is_editor_hint():
			_button_visual.mesh = _button_visual.mesh.duplicate()
		var b_mesh = _button_visual.mesh as BoxMesh
		if b_mesh:
			b_mesh.size = Vector3(width - 0.01, height - 0.01, 0.03)


func _trigger_haptic_on_interactor(interactor: Node) -> void:
	# Try to trigger haptics on the node or its parents
	var node = interactor
	while node:
		if node.has_method("trigger_haptic_pulse"):
			node.trigger_haptic_pulse("haptic", 0.0, click_haptic_intensity, click_haptic_duration, 0.0)
			break
		node = node.get_parent()
