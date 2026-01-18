class_name ShapeTool
extends Grabbable

# ShapeTool - A grabbable tool that creates box volumes
# Hold trigger while gripping to start a box, drag to size it, release to create.



# Configuration
@export var tip_offset: Vector3 = Vector3(0, 0, -0.15) # Offset from center to tool tip
@export var tool_color: Color = Color(0.2, 0.8, 0.4, 1.0)
@export var preview_color: Color = Color(0.2, 0.8, 0.4, 0.5)
@export var min_size: float = 0.05 # Minimum size to create a box

# State
var _is_dragging: bool = false
var _start_point: Vector3 = Vector3.ZERO
var _preview_mesh_instance: MeshInstance3D = null
var _preview_box_mesh: BoxMesh = null
var _controller: Node = null
var _hand: RigidBody3D = null
var _prev_trigger_pressed: bool = false

# Pooling
const POOL_TYPE := "shape_tool"

func _ready() -> void:
	super._ready()
	
	# Register with pool manager if available
	var pool := ToolPoolManager.find()
	if pool:
		pool.register_instance(POOL_TYPE, self)
		
	# Connect signals
	grabbed.connect(_on_tool_grabbed)
	released.connect(_on_tool_released)
	
	# Create reusable preview resources
	_preview_box_mesh = BoxMesh.new()
	
	print("ShapeTool: Ready - grabbed signal connected, physics_process=", is_physics_processing())

func _on_tool_grabbed(hand: RigidBody3D) -> void:
	_hand = hand
	_controller = null
	
	if is_instance_valid(hand) and hand.has_method("get"):
		var maybe_target = hand.get("target")
		if maybe_target and maybe_target is Node3D:
			_controller = maybe_target
			
	set_physics_process(true)
	print("ShapeTool: Grabbed by ", hand.name if hand else "desktop")

func _on_tool_released() -> void:
	if _is_dragging:
		_finish_shape()
	
	_destroy_preview()
	_hand = null
	_controller = null
	set_physics_process(false)
	print("ShapeTool: Released")

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# Check for either VR grab (is_grabbed) OR desktop grab (is_desktop_grabbed)
	if not is_grabbed and not is_desktop_grabbed:
		return
	
	# Read trigger input
	var trigger_pressed: bool = false
	# Try to get input from controller
	if is_instance_valid(_controller):
		if _controller.has_method("get_float"):
			trigger_pressed = _controller.get_float("trigger") > 0.5
		elif _controller.has_method("is_button_pressed"):
			trigger_pressed = _controller.is_button_pressed("trigger_click")
	# Fallback to InputMap (left mouse button) for desktop
	if not trigger_pressed:
		if InputMap.has_action("trigger_click") and Input.is_action_pressed("trigger_click"):
			trigger_pressed = true
	
	# Handle input state
	if trigger_pressed and not _prev_trigger_pressed:
		_start_shape()
	elif not trigger_pressed and _prev_trigger_pressed:
		_finish_shape()
	elif _is_dragging:
		_update_preview()
		
	_prev_trigger_pressed = trigger_pressed

func _get_tip_world_position() -> Vector3:
	# Calculate tip position based on grab state
	# Since the tool itself might be visually hidden/replaced by the hand attachment during grab,
	# we rely on the grabbed collision shapes or the hand itself.
	if grabbed_collision_shapes.size() > 0 and is_instance_valid(grabbed_collision_shapes[0]):
		var grabbed_transform = grabbed_collision_shapes[0].global_transform
		return grabbed_transform * tip_offset
	elif is_instance_valid(_hand):
		return _hand.global_transform * tip_offset
	return global_transform * tip_offset

func _start_shape() -> void:
	if _is_dragging:
		return
		
	_is_dragging = true
	_start_point = _get_tip_world_position()
	_create_preview()
	print("ShapeTool: Start dragging shape at ", _start_point)

func _finish_shape() -> void:
	if not _is_dragging:
		return
		
	_is_dragging = false
	var end_point = _get_tip_world_position()
	var bounds = _calculate_bounds(_start_point, end_point)
	var size = bounds.size
	
	# Only create if large enough
	if size.length() >= min_size:
		_create_solid_box(bounds.position + size * 0.5, size)
	else:
		print("ShapeTool: Shape too small, discarding")
		
	_destroy_preview()

func _update_preview() -> void:
	if not is_instance_valid(_preview_mesh_instance):
		return
		
	var end_point = _get_tip_world_position()
	var bounds = _calculate_bounds(_start_point, end_point)
	
	# Update mesh size
	_preview_box_mesh.size = bounds.size
	
	# Update position (center of the box)
	_preview_mesh_instance.global_position = bounds.position + bounds.size * 0.5

func _calculate_bounds(p1: Vector3, p2: Vector3) -> AABB:
	var min_p = Vector3(min(p1.x, p2.x), min(p1.y, p2.y), min(p1.z, p2.z))
	var max_p = Vector3(max(p1.x, p2.x), max(p1.y, p2.y), max(p1.z, p2.z))
	return AABB(min_p, max_p - min_p)

func _create_preview() -> void:
	_destroy_preview() # Safety clear
	
	_preview_mesh_instance = MeshInstance3D.new()
	_preview_mesh_instance.mesh = _preview_box_mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = preview_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_preview_mesh_instance.material_override = mat
	
	# Add to root to be independent of hand transform
	get_tree().root.add_child(_preview_mesh_instance)

func _destroy_preview() -> void:
	if is_instance_valid(_preview_mesh_instance):
		_preview_mesh_instance.queue_free()
	_preview_mesh_instance = null

func _create_solid_box(center: Vector3, size: Vector3) -> void:
	var body = RigidBody3D.new()
	body.name = "GenBox_" + str(randi() % 10000)
	var volume = size.x * size.y * size.z
	body.mass = volume * 10.0 # Approximate density
	body.position = center
	
	# Collision
	var shape = BoxShape3D.new()
	shape.size = size
	var coll = CollisionShape3D.new()
	coll.shape = shape
	body.add_child(coll)
	
	# Visual
	var mesh = BoxMesh.new()
	mesh.size = size
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(randf(), randf(), randf())
	mesh_inst.material_override = mat
	
	body.add_child(mesh_inst)
	body.add_to_group("grabbable")
	
	# Add Grabbable script/logic if needed, or just let `Grabbable` pick it up if it handles generic RigidBodies?
	# The `Grabbable` system in this project seems to require the object to have the `Grabbable` script attached
	# to be picked up properly by `PhysicsHand` (which calls `try_grab` on the object).
	# So we MUST attach `Grabbable` script to the new object.
	# Or we can attach a simpler script. Let's attach generic `Grabbable`.
	body.set_script(load("res://src/objects/grabbable.gd"))
	
	# Add to scene
	var current_scene = get_tree().current_scene
	if current_scene:
		current_scene.add_child(body)
		
		# Register with pool manager to prevent infinite garbage
		var pool := ToolPoolManager.find()
		if pool:
			pool.register_hull(body) # Re-using register_hull as it likely just tracks generic nodes
			
	print("ShapeTool: Created box at ", center, " size ", size)
