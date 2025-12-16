extends Node3D

# Simple Pickup - handles grabbing world grab areas using Area3D detection

signal grabbed(what)
signal released

@onready var controller: XRController3D = get_parent()

var grabbed_object = null
var grip_pressed = false
var grip_threshold = 0.7
var objects_in_range = []

# Grab detection area
var grab_area: Area3D

func _ready():
	# Create grab detection area
	grab_area = Area3D.new()
	grab_area.collision_layer = 0
	grab_area.collision_mask = 262144  # Layer 18 - world grab area
	grab_area.monitorable = false
	grab_area.monitoring = true
	
	var collision_shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 0.3
	collision_shape.shape = sphere
	grab_area.add_child(collision_shape)
	
	grab_area.area_entered.connect(_on_area_entered)
	grab_area.area_exited.connect(_on_area_exited)
	grab_area.body_entered.connect(_on_body_entered)
	grab_area.body_exited.connect(_on_body_exited)
	
	add_child(grab_area)
	
	print("SimplePickup ready on: ", get_parent().name)

func _process(_delta):
	if not controller or not controller.get_is_active():
		return
	
	# Check grip value (works with analog grip)
	var grip_value = controller.get_float("grip")
	
	if not grip_pressed and grip_value > grip_threshold:
		grip_pressed = true
		_try_grab()
	elif grip_pressed and grip_value < grip_threshold - 0.1:
		grip_pressed = false
		_release_grab()

func _on_area_entered(area):
	print("Area entered: ", area.name)
	if area.has_method("can_pick_up"):
		if area not in objects_in_range:
			objects_in_range.append(area)
			print("Added to grab range: ", area.name)

func _on_area_exited(area):
	objects_in_range.erase(area)

func _on_body_entered(body):
	if body.has_method("can_pick_up"):
		if body not in objects_in_range:
			objects_in_range.append(body)

func _on_body_exited(body):
	objects_in_range.erase(body)

func _try_grab():
	print("Trying to grab, objects in range: ", objects_in_range.size())
	# Find closest grabbable object
	for obj in objects_in_range:
		if is_instance_valid(obj) and obj.has_method("can_pick_up"):
			if obj.can_pick_up(self):
				grabbed_object = obj
				obj.pick_up(self)
				grabbed.emit(obj)
				print("Grabbed: ", obj.name)
				return

func _release_grab():
	if grabbed_object and is_instance_valid(grabbed_object):
		if grabbed_object.has_method("let_go"):
			grabbed_object.let_go(self, Vector3.ZERO, Vector3.ZERO)
	grabbed_object = null
	released.emit()

func get_grab_handle():
	if grabbed_object and is_instance_valid(grabbed_object):
		if grabbed_object.has_method("get_grab_handle"):
			return grabbed_object.get_grab_handle(self)
	return null
