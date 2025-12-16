extends Node3D

# Simple Pickup - creates virtual grab handles in space (no Area3D needed)

signal grabbed()
signal released()

@onready var controller: XRController3D = get_parent()

var grip_pressed = false
var grip_threshold = 0.7
var grab_handle: Node3D = null

func _process(_delta):
	if not controller or not controller.get_is_active():
		return
	
	# Check grip value
	var grip_value = controller.get_float("grip")
	
	if not grip_pressed and grip_value > grip_threshold:
		grip_pressed = true
		_create_grab_handle()
	elif grip_pressed and grip_value < grip_threshold - 0.1:
		grip_pressed = false
		_release_grab_handle()

func _create_grab_handle():
	# Create a virtual grab point at current hand position
	grab_handle = Node3D.new()
	get_tree().root.add_child(grab_handle)
	grab_handle.global_transform = global_transform
	grabbed.emit()

func _release_grab_handle():
	if grab_handle and is_instance_valid(grab_handle):
		grab_handle.queue_free()
	grab_handle = null
	released.emit()

func get_grab_handle() -> Node3D:
	return grab_handle

func is_grabbing() -> bool:
	return grab_handle != null and is_instance_valid(grab_handle)
