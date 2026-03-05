# Flashlight
# Grabbable flashlight with on/off toggle. Works in both VR and desktop modes.
extends Grabbable
class_name FlashlightGrabbable

## Toggle state
@export var starts_on: bool = false

## Light references (auto-discovered if not set)
var _spot_light: SpotLight3D
var _fill_light: OmniLight3D
var _lens_mesh: MeshInstance3D

## Cloned lights for VR grab (attached to hand)
var _cloned_spot_light: SpotLight3D
var _cloned_fill_light: OmniLight3D

## State
var is_light_on: bool = true

## Lens materials for on/off visual feedback
var _lens_material_on: StandardMaterial3D
var _lens_material_off: StandardMaterial3D


func _ready() -> void:
	super._ready()
	
	# Discover light nodes
	_spot_light = _find_child_of_type("SpotLight3D") as SpotLight3D
	_fill_light = _find_child_of_type("OmniLight3D") as OmniLight3D
	_lens_mesh = get_node_or_null("Lens") as MeshInstance3D
	
	# Create on/off lens materials
	if _lens_mesh and _lens_mesh.material_override:
		_lens_material_on = _lens_mesh.material_override.duplicate() as StandardMaterial3D
		_lens_material_off = _lens_mesh.material_override.duplicate() as StandardMaterial3D
		_lens_material_off.emission_energy_multiplier = 0.0
		_lens_material_off.albedo_color = Color(0.3, 0.3, 0.28, 0.4)
	
	# Apply initial state
	is_light_on = starts_on
	_apply_light_state()


func _input(event: InputEvent) -> void:
	# Toggle with left click / trigger while held (desktop or VR)
	if (is_grabbed or is_desktop_grabbed) and event.is_action_pressed("trigger_click"):
		toggle_light()
		get_viewport().set_input_as_handled()


func toggle_light() -> void:
	is_light_on = not is_light_on
	_apply_light_state()
	print("Flashlight: toggled ", "ON" if is_light_on else "OFF")


func _apply_light_state() -> void:
	# Update original lights
	if _spot_light:
		_spot_light.visible = is_light_on
	if _fill_light:
		_fill_light.visible = is_light_on
	
	# Update cloned lights (VR grab)
	if _cloned_spot_light and is_instance_valid(_cloned_spot_light):
		_cloned_spot_light.visible = is_light_on
	if _cloned_fill_light and is_instance_valid(_cloned_fill_light):
		_cloned_fill_light.visible = is_light_on
	
	# Update lens visual
	if _lens_mesh:
		if is_light_on and _lens_material_on:
			_lens_mesh.material_override = _lens_material_on
		elif not is_light_on and _lens_material_off:
			_lens_mesh.material_override = _lens_material_off


func try_grab(hand: RigidBody3D) -> bool:
	var result := super.try_grab(hand)
	if result:
		# Clone lights to the hand so they follow the grabbed object
		_clone_lights_to_hand(hand)
	return result


func release() -> void:
	# Clean up cloned lights before releasing
	_cleanup_cloned_lights()
	super.release()


func _clone_lights_to_hand(hand: RigidBody3D) -> void:
	"""Clone SpotLight3D and OmniLight3D to the hand for VR grab."""
	var hand_space_object_transform := Transform3D(
		Basis(grab_rotation_offset).scaled(grab_scale_offset),
		grab_offset
	)
	var object_inv := global_transform.affine_inverse()
	
	if _spot_light:
		_cloned_spot_light = SpotLight3D.new()
		_cloned_spot_light.light_color = _spot_light.light_color
		_cloned_spot_light.light_energy = _spot_light.light_energy
		_cloned_spot_light.spot_range = _spot_light.spot_range
		_cloned_spot_light.spot_angle = _spot_light.spot_angle
		_cloned_spot_light.spot_angle_attenuation = _spot_light.spot_angle_attenuation
		_cloned_spot_light.shadow_enabled = _spot_light.shadow_enabled
		_cloned_spot_light.visible = is_light_on
		
		var relative_transform: Transform3D = object_inv * _spot_light.global_transform
		_cloned_spot_light.transform = hand_space_object_transform * relative_transform
		_cloned_spot_light.name = name + "_grabbed_spotlight"
		hand.add_child(_cloned_spot_light)
	
	if _fill_light:
		_cloned_fill_light = OmniLight3D.new()
		_cloned_fill_light.light_color = _fill_light.light_color
		_cloned_fill_light.light_energy = _fill_light.light_energy
		_cloned_fill_light.omni_range = _fill_light.omni_range
		_cloned_fill_light.visible = is_light_on
		
		var relative_transform: Transform3D = object_inv * _fill_light.global_transform
		_cloned_fill_light.transform = hand_space_object_transform * relative_transform
		_cloned_fill_light.name = name + "_grabbed_filllight"
		hand.add_child(_cloned_fill_light)


func _cleanup_cloned_lights() -> void:
	"""Remove cloned lights from hand."""
	if is_instance_valid(_cloned_spot_light):
		var parent = _cloned_spot_light.get_parent()
		if parent:
			parent.remove_child(_cloned_spot_light)
		_cloned_spot_light.queue_free()
		_cloned_spot_light = null
	
	if is_instance_valid(_cloned_fill_light):
		var parent = _cloned_fill_light.get_parent()
		if parent:
			parent.remove_child(_cloned_fill_light)
		_cloned_fill_light.queue_free()
		_cloned_fill_light = null


func _set_original_visuals_visible(p_visible: bool) -> void:
	"""Override to keep lights visible/hidden based on light state, not grab state.
	When grabbed in VR, lights are cloned to the hand so originals should be hidden.
	When grabbed on desktop (reparented), lights should stay based on is_light_on."""
	for child in get_children():
		if child is Light3D:
			# Lights handled separately — hide originals during VR grab,
			# keep visible during desktop grab
			if is_desktop_grabbed:
				child.visible = is_light_on
			else:
				child.visible = false if not p_visible else is_light_on
		elif child is VisualInstance3D:
			child.visible = p_visible


func _force_cleanup_grab_state() -> void:
	_cleanup_cloned_lights()
	super._force_cleanup_grab_state()


func _find_child_of_type(type_name: String) -> Node:
	"""Find the first child matching a type name."""
	for child in get_children():
		if child.get_class() == type_name:
			return child
	return null


## Called by DesktopInteractionComponent when picked up on desktop
func desktop_grab(grabber: Node, slot: int = -1) -> void:
	super.desktop_grab(grabber, slot)
	# Lights stay attached since the whole node is reparented
	_apply_light_state()
	print("Flashlight: Desktop grab")


## Called by DesktopInteractionComponent when dropped on desktop
func desktop_release() -> void:
	_apply_light_state()
	super.desktop_release()
	print("Flashlight: Desktop release")
