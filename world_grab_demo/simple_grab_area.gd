extends Area3D

# Simple World Grab Area - defines areas that can be grabbed for world movement

var grab_handles = {}

func can_pick_up(by: Node3D) -> bool:
	return true

func pick_up(by: Node3D):
	# Create a grab handle at the pickup location
	var handle = Node3D.new()
	add_child(handle)
	handle.global_transform = by.global_transform
	
	# Store the handle
	var id = by.get_instance_id()
	grab_handles[id] = handle

func let_go(by: Node3D, linear_velocity: Vector3, angular_velocity: Vector3):
	# Clean up the grab handle
	var id = by.get_instance_id()
	if grab_handles.has(id):
		var handle = grab_handles[id]
		if is_instance_valid(handle):
			handle.queue_free()
		grab_handles.erase(id)

func get_grab_handle(pickup: Node3D) -> Node3D:
	var id = pickup.get_instance_id()
	if grab_handles.has(id):
		return grab_handles[id]
	return null