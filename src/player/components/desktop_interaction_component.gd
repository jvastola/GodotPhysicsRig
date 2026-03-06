class_name DesktopInteractionComponent
extends Node

## Desktop Interaction Component
## Handles keyboard-based object pickup and interaction for desktop players.
## Uses the head crosshair (CenterPointer) for targeting instead of VR hand rays.

signal item_picked_up(slot: int, item: Node3D)
signal item_dropped(slot: int, item: Node3D)
signal look_target_changed(target: Node)

enum Slot { LEFT = 0, RIGHT = 1 }

## Enable/disable desktop interaction
@export var enabled: bool = true

## Held item offsets relative to camera
@export var left_slot_offset: Vector3 = Vector3(-0.4, -0.2, -0.6)
@export var right_slot_offset: Vector3 = Vector3(0.4, -0.2, -0.6)

## Distance adjustment range
@export var min_hold_distance: float = 0.3
@export var max_hold_distance: float = 2.0
@export var distance_adjust_speed: float = 0.2

## Rotation speed (degrees per key press frame)
@export var rotation_speed: float = 90.0

## Debug logging
@export var debug_logs: bool = false

# References
var camera: Camera3D
var center_pointer: Node  # hand_pointer.gd instance
var left_hand_pointer: Node
var right_hand_pointer: Node

# State
var _left_held_item: Node3D = null
var _right_held_item: Node3D = null
var _left_hold_distance: float = 0.6
var _right_hold_distance: float = 0.6
var _look_target: Node = null

# Original parents for restoration on drop
var _left_original_parent: Node = null
var _right_original_parent: Node = null

# Active pointer interaction targets
var _left_interact_target: Node = null
var _right_interact_target: Node = null


func setup(p_camera: Camera3D, p_center_pointer: Node) -> void:
	camera = p_camera
	center_pointer = p_center_pointer
	if debug_logs:
		print("DesktopInteractionComponent: Setup complete")


func set_hand_pointers(left: Node, right: Node) -> void:
	"""Store references to VR hand pointers so we can disable them in desktop mode"""
	left_hand_pointer = left
	right_hand_pointer = right


func activate() -> void:
	"""Called when desktop mode is activated"""
	enabled = true
	# Disable VR hand pointer processing
	_set_hand_pointers_enabled(false)
	if debug_logs:
		print("DesktopInteractionComponent: Activated")


func deactivate() -> void:
	"""Called when desktop mode is deactivated"""
	enabled = false
	# Drop any held items
	drop_item(Slot.LEFT)
	drop_item(Slot.RIGHT)
	# Re-enable VR hand pointers
	_set_hand_pointers_enabled(true)
	if debug_logs:
		print("DesktopInteractionComponent: Deactivated")


func _set_hand_pointers_enabled(value: bool) -> void:
	if left_hand_pointer and left_hand_pointer.has_method("set_physics_process"):
		left_hand_pointer.set_physics_process(value)
		left_hand_pointer.visible = value
	if right_hand_pointer and right_hand_pointer.has_method("set_physics_process"):
		right_hand_pointer.set_physics_process(value)
		right_hand_pointer.visible = value


func _input(event: InputEvent) -> void:
	if not enabled or not camera:
		return
	
	# E/F keys handle interaction (press and release)
	if event.is_action_pressed("pickup_left"):
		_handle_interaction(Slot.LEFT, true)
	elif event.is_action_released("pickup_left"):
		_handle_interaction(Slot.LEFT, false)
	elif event.is_action_pressed("pickup_right"):
		_handle_interaction(Slot.RIGHT, true)
	elif event.is_action_released("pickup_right"):
		_handle_interaction(Slot.RIGHT, false)
	
	# Distance adjustment with mouse wheel
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_adjust_distance(-distance_adjust_speed)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_adjust_distance(distance_adjust_speed)


func _physics_process(delta: float) -> void:
	if not enabled or not camera:
		return
	
	# Update look target from center pointer
	_update_look_target()
	
	# Update held item positions
	_update_held_items(delta)
	
	# Handle rotation input (continuous while held)
	if Input.is_action_pressed("rotate_left") and _left_held_item:
		_rotate_item(_left_held_item, delta)
	if Input.is_action_pressed("rotate_right") and _right_held_item:
		_rotate_item(_right_held_item, delta)


func _update_look_target() -> void:
	var new_target: Node = null
	
	if center_pointer and center_pointer.has_method("get_hit_collider"):
		var collider = center_pointer.get_hit_collider()
		if collider and collider is Node:
			# Check if it's grabbable or pointer-interactable.
			if collider.is_in_group("grabbable") or collider.is_in_group("interactable") or collider.is_in_group("pointer_interactable") or collider.has_method("handle_pointer_event"):
				new_target = collider
	
	if new_target != _look_target:
		_look_target = new_target
		look_target_changed.emit(_look_target)
		if debug_logs and _look_target:
			print("DesktopInteractionComponent: Looking at ", _look_target.name)


func _handle_interaction(slot: int, is_press: bool) -> void:
	if is_press:
		var held = _get_held_item(slot)
		if held:
			drop_item(slot)
		else:
			# Try to interact with pointer-based objects first
			var target = _try_interact_look_target(true)
			if target:
				if slot == Slot.LEFT: _left_interact_target = target
				else: _right_interact_target = target
				return
			
			# Fallback to pickup
			pickup_item(slot)
	else:
		# Handle release
		var target = _left_interact_target if slot == Slot.LEFT else _right_interact_target
		if target:
			_send_pointer_event(target, "release")
			if slot == Slot.LEFT: _left_interact_target = null
			else: _right_interact_target = null


func _try_interact_look_target(is_press: bool) -> Node:
	"""If the looked-at target is pointer-interactable, trigger an event and return the target."""
	if not _look_target:
		return null
	if _look_target.is_in_group("grabbable") and is_press:
		return null
	
	var is_pointer_friendly = _look_target.is_in_group("pointer_interactable") or \
							  _look_target.has_method("handle_pointer_event")
	
	if not is_pointer_friendly:
		return null

	if is_press:
		_send_pointer_event(_look_target, "press")
		if debug_logs:
			print("DesktopInteractionComponent: Triggered pointer press on ", _look_target.name)
		return _look_target
	
	return null


func _send_pointer_event(target: Node, type: String) -> void:
	if not target or not target.has_method("handle_pointer_event"):
		return
		
	var event := {
		"type": type,
		"pointer": center_pointer,
		"controller": null,
		"collider": target,
		"handler": target,
		"global_position": (target as Node3D).global_position if target is Node3D else Vector3.ZERO,
		"global_normal": Vector3.UP,
		"pointer_origin": camera.global_position if camera else Vector3.ZERO,
		"pointer_direction": -camera.global_transform.basis.z if camera else Vector3.FORWARD,
		"distance": 0.0,
		"action": "trigger_click",
		"action_pressed": (type == "press" or type == "hold"),
		"action_just_pressed": (type == "press"),
		"action_just_released": (type == "release"),
		"action_strength": 1.0 if (type == "press" or type == "hold") else 0.0,
	}
	
	# Use call_deferred to avoid physics state issues
	target.call_deferred("handle_pointer_event", event)


func pickup_item(slot: int) -> void:
	"""Pick up the item we're looking at into the specified slot"""
	if not _look_target:
		if debug_logs:
			print("DesktopInteractionComponent: Nothing to pick up")
		return
	
	# Check if already holding something in this slot
	if _get_held_item(slot):
		if debug_logs:
			print("DesktopInteractionComponent: Slot ", slot, " already occupied")
		return
	
	var target := _look_target as Node3D
	if not target:
		return
	
	# Check if it's a grabbable
	if not target.is_in_group("grabbable"):
		if debug_logs:
			print("DesktopInteractionComponent: Target not grabbable")
		return
	
	# Store original parent
	var original_parent := target.get_parent()
	
	# For Grabbable objects, use their grab interface if available
	if target.has_method("desktop_grab"):
		target.desktop_grab(self, slot)
	elif target is RigidBody3D:
		# Disable physics while held
		(target as RigidBody3D).freeze = true
	
	# Reparent to camera for easy positioning (using reparent avoids multiple tree signals)
	target.reparent(camera, false)
	
	# Set initial position
	var offset := left_slot_offset if slot == Slot.LEFT else right_slot_offset
	var distance := _left_hold_distance if slot == Slot.LEFT else _right_hold_distance
	offset.z = -distance
	target.position = offset
	
	# Store references
	if slot == Slot.LEFT:
		_left_held_item = target
		_left_original_parent = original_parent
	else:
		_right_held_item = target
		_right_original_parent = original_parent
	
	item_picked_up.emit(slot, target)
	if debug_logs:
		print("DesktopInteractionComponent: Picked up ", target.name, " to slot ", slot)


func drop_item(slot: int) -> void:
	"""Drop the item from the specified slot"""
	var item := _get_held_item(slot)
	if not item:
		return
	
	var original_parent := _left_original_parent if slot == Slot.LEFT else _right_original_parent
	
	# Get world transform before reparenting
	var world_transform := item.global_transform
	
	# Restore to original parent or scene root using reparent()
	var restore_parent := original_parent if is_instance_valid(original_parent) else get_tree().current_scene
	if restore_parent:
		item.reparent(restore_parent, true)
	
	# Re-enable physics if it's a RigidBody
	if item is RigidBody3D:
		(item as RigidBody3D).freeze = false
	
	# Call release method if available
	if item.has_method("desktop_release"):
		item.desktop_release()
	
	# Clear references
	if slot == Slot.LEFT:
		_left_held_item = null
		_left_original_parent = null
	else:
		_right_held_item = null
		_right_original_parent = null
	
	item_dropped.emit(slot, item)
	if debug_logs:
		print("DesktopInteractionComponent: Dropped ", item.name, " from slot ", slot)


func _get_held_item(slot: int) -> Node3D:
	return _left_held_item if slot == Slot.LEFT else _right_held_item


func _update_held_items(_delta: float) -> void:
	"""Update positions of held items relative to camera"""
	if _left_held_item and is_instance_valid(_left_held_item):
		var offset := left_slot_offset
		offset.z = -_left_hold_distance
		_left_held_item.position = offset
	
	if _right_held_item and is_instance_valid(_right_held_item):
		var offset := right_slot_offset
		offset.z = -_right_hold_distance
		_right_held_item.position = offset


func _adjust_distance(amount: float) -> void:
	"""Adjust hold distance for both slots"""
	_left_hold_distance = clampf(_left_hold_distance + amount, min_hold_distance, max_hold_distance)
	_right_hold_distance = clampf(_right_hold_distance + amount, min_hold_distance, max_hold_distance)


func _rotate_item(item: Node3D, delta: float) -> void:
	"""Rotate held item around Y axis"""
	item.rotate_y(deg_to_rad(rotation_speed * delta))


# Public getters
func get_left_held_item() -> Node3D:
	return _left_held_item

func get_right_held_item() -> Node3D:
	return _right_held_item

func get_look_target() -> Node:
	return _look_target

func is_holding_anything() -> bool:
	return _left_held_item != null or _right_held_item != null
