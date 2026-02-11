extends MeshInstance3D

## Handler for canvas painter - processes pointer/touch events and converts to UV coordinates

@export var painter: NodePath = NodePath("")
@export var paint_color: Color = Color.BLACK
@export var brush_size: int = 5
@export var debug_mode: bool = false

var _is_pressing: bool = false

func _ready() -> void:
	add_to_group("pointer_interactable")

func handle_pointer_event(event: Dictionary) -> void:
	if debug_mode:
		print("CanvasPainterHandler: Received pointer event on ", name)
		print("  - Event keys: ", event.keys())
	
	# Compute local position if not provided
	if not event.has("local_position"):
		if event.has("global_position"):
			var gp: Vector3 = event["global_position"]
			event["local_position"] = to_local(gp)
			if debug_mode:
				print("  - Computed local_position from global: ", event["local_position"])
		else:
			if debug_mode:
				print("  - No position data, aborting")
			return
	
	# Check press state
	var just_pressed: bool = event.has("action_just_pressed") and event["action_just_pressed"]
	var pressed: bool = event.has("action_pressed") and event["action_pressed"]
	var just_released: bool = event.has("action_just_released") and event["action_just_released"]
	
	if debug_mode:
		print("  - just_pressed: ", just_pressed, ", pressed: ", pressed, ", just_released: ", just_released)
	
	# Get painter node
	var pnode := get_node_or_null(painter) as Node
	if not pnode:
		if debug_mode:
			print("  - WARNING: Painter node not found at path: ", painter)
		return
	
	# Handle painting state
	if just_pressed:
		_is_pressing = true
		if pnode.has_method("start_painting"):
			pnode.call("start_painting")
	elif just_released:
		_is_pressing = false
		if pnode.has_method("stop_painting"):
			pnode.call("stop_painting")
		return
	
	if not _is_pressing and not pressed:
		return
	
	# Convert local position to UV
	var lp: Vector3 = event["local_position"]
	var uv := _compute_uv_from_local_pos(lp)
	
	if debug_mode:
		print("  - Local pos: ", lp, " -> UV: ", uv)
	
	if uv.x < 0.0 or uv.y < 0.0:
		if debug_mode:
			print("  - Invalid UV, aborting")
		return
	
	# Get color to paint
	var color_to_paint: Color = paint_color
	if event.has("pointer_color") and event["pointer_color"] is Color:
		color_to_paint = event["pointer_color"]
	
	if debug_mode:
		print("  - Painting at UV ", uv, " with color ", color_to_paint)
	
	# Paint on canvas
	if pnode.has_method("paint_at_uv"):
		pnode.call("paint_at_uv", uv, color_to_paint)
	elif debug_mode:
		print("  - WARNING: Painter node doesn't have paint_at_uv method")

func _compute_uv_from_local_pos(lp: Vector3) -> Vector2:
	if not mesh:
		return Vector2(-1, -1)
	
	var aabb: AABB = mesh.get_aabb()
	
	# For a plane mesh, we expect it to be in XY plane (Z=0)
	# Map X to U and Y to V
	var u: float = (lp.x - aabb.position.x) / aabb.size.x
	var v: float = (lp.y - aabb.position.y) / aabb.size.y
	
	# Flip V to match texture coordinates (top-left origin)
	v = 1.0 - v
	
	u = clamp(u, 0.0, 1.0)
	v = clamp(v, 0.0, 1.0)
	
	return Vector2(u, v)
