extends Grabbable
class_name PaintBrush

## Grabbable Paint Brush - Paint on the reference block with colors from the color picker
## Uses raycast to interact with both the color picker UI and the reference block

# === Ray Settings ===
@export_group("Ray Settings")
@export var ray_length: float = 3.0
@export var ray_length_min: float = 0.3
@export var ray_length_max: float = 10.0
@export var ray_length_adjust_speed: float = 3.0
@export var ray_deadzone: float = 0.2
@export var ray_axis_action: String = "primary"

# === Visibility ===
@export_group("Visibility")
@export var always_show_ray: bool = true
@export var ray_color: Color = Color(0.8, 0.2, 0.8, 0.6)
@export var ray_hit_color: Color = Color(1.0, 0.5, 1.0, 0.8)

# === Collision ===
@export_group("Collision")
@export_flags_3d_physics var pointer_collision_mask: int = (1 << 5) | 32  # Layer 6 (UI) + Layer 6 (reference block)
@export var pointer_handler_group: StringName = &"pointer_interactable"

# === Child Nodes (attached to self) ===
var raycast: RayCast3D
var ray_visual: MeshInstance3D
var ray_immediate_mesh: ImmediateMesh

# === Scene-level nodes (added to scene root for proper world positioning) ===
var hit_marker: MeshInstance3D

# === State ===
var _reference_block: ReferenceBlock
var _color_picker_ui: ColorPickerUI
var _was_trigger_pressed: bool = false
var _has_hit: bool = false
var _hit_point: Vector3 = Vector3.ZERO
var _hit_normal: Vector3 = Vector3.UP
var _current_color: Color = Color.WHITE
var _hover_target: Node = null
var _last_collider: Object = null
var _brush_tip_material: StandardMaterial3D


func _ready() -> void:
	super._ready()
	
	_create_raycast()
	_create_ray_visual()
	_create_hit_marker()
	_setup_brush_tip_material()
	
	_find_reference_block()
	_find_color_picker()
	
	print("PaintBrush: Ready")


func _find_reference_block() -> void:
	if ReferenceBlock.instance:
		_reference_block = ReferenceBlock.instance
		return
	
	var blocks = get_tree().get_nodes_in_group("reference_block")
	if blocks.size() > 0:
		_reference_block = blocks[0] as ReferenceBlock
		return
	
	_reference_block = get_tree().root.find_child("ReferenceBlock", true, false) as ReferenceBlock


func _find_color_picker() -> void:
	if ColorPickerUI.instance:
		_color_picker_ui = ColorPickerUI.instance
		return
	
	var pickers = get_tree().get_nodes_in_group("color_picker_ui")
	if pickers.size() > 0:
		_color_picker_ui = pickers[0] as ColorPickerUI
		return
	
	_color_picker_ui = get_tree().root.find_child("ColorPickerUI", true, false) as ColorPickerUI


func _create_raycast() -> void:
	raycast = RayCast3D.new()
	raycast.name = "PaintRaycast"
	raycast.target_position = Vector3(0, 0, -ray_length)
	raycast.enabled = true
	raycast.collision_mask = pointer_collision_mask
	raycast.collide_with_areas = true
	raycast.collide_with_bodies = true
	add_child(raycast)


func _create_ray_visual() -> void:
	ray_visual = MeshInstance3D.new()
	ray_visual.name = "RayVisual"
	ray_immediate_mesh = ImmediateMesh.new()
	ray_visual.mesh = ray_immediate_mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = ray_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	ray_visual.material_override = mat
	
	add_child(ray_visual)


func _create_hit_marker() -> void:
	# Create hit marker but don't add as child yet - will be added to scene root
	hit_marker = MeshInstance3D.new()
	hit_marker.name = "PaintBrushHitMarker"
	
	var sphere = SphereMesh.new()
	sphere.radius = 0.015
	sphere.height = 0.03
	hit_marker.mesh = sphere
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = ray_hit_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hit_marker.material_override = mat
	hit_marker.visible = false


func _setup_brush_tip_material() -> void:
	# Create a shared material for the brush tip that we can update
	_brush_tip_material = StandardMaterial3D.new()
	_brush_tip_material.albedo_color = _current_color
	
	# Find the Bristles mesh and apply the material
	var bristles = get_node_or_null("Bristles") as MeshInstance3D
	if bristles:
		bristles.material_override = _brush_tip_material


func _ensure_hit_marker_in_tree() -> void:
	"""Add hit marker to scene root if not already there"""
	if not is_inside_tree():
		return
	
	var scene_root = get_tree().current_scene
	if not scene_root:
		return
	
	if not is_instance_valid(hit_marker):
		_create_hit_marker()
	
	if hit_marker and not hit_marker.is_inside_tree():
		scene_root.add_child(hit_marker)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	_ensure_hit_marker_in_tree()
	
	if not is_instance_valid(_reference_block):
		_find_reference_block()
	if not is_instance_valid(_color_picker_ui):
		_find_color_picker()
	
	if not is_grabbed or not is_instance_valid(grabbing_hand):
		_set_visuals_visible(false)
		_clear_hover()
		return
	
	_process_input(delta)
	_process_raycast()
	_update_visuals()
	_update_brush_tip_color()


func _update_brush_tip_color() -> void:
	# Update the shared material
	if _brush_tip_material:
		_brush_tip_material.albedo_color = _current_color
	
	# Also update any grabbed mesh instances on the hand that represent the bristles
	if is_grabbed and is_instance_valid(grabbing_hand):
		for child in grabbing_hand.get_children():
			if child is MeshInstance3D and child.name.contains("Bristles"):
				if child.material_override != _brush_tip_material:
					child.material_override = _brush_tip_material


func _process_input(delta: float) -> void:
	var controller = _get_controller()
	if not controller:
		return
	
	var trigger_pressed = controller.is_button_pressed("trigger_click")
	var just_pressed = trigger_pressed and not _was_trigger_pressed
	var just_released = not trigger_pressed and _was_trigger_pressed
	
	# Build action state for pointer events
	var action_state = {
		"pressed": trigger_pressed,
		"just_pressed": just_pressed,
		"just_released": just_released
	}
	
	# Process pointer interaction
	if _has_hit and _last_collider:
		var handler = _find_pointer_handler(_last_collider)
		if handler:
			_process_pointer_events(handler, action_state)
	
	_was_trigger_pressed = trigger_pressed
	
	# Ray length adjustment
	var axis_input = controller.get_vector2(ray_axis_action)
	if abs(axis_input.y) > ray_deadzone:
		ray_length = clamp(
			ray_length - axis_input.y * ray_length_adjust_speed * delta,
			ray_length_min,
			ray_length_max
		)
		raycast.target_position = Vector3(0, 0, -ray_length)


func _get_controller() -> XRController3D:
	if not is_instance_valid(grabbing_hand):
		return null
	return grabbing_hand.target as XRController3D


func _process_raycast() -> void:
	if not raycast:
		return
	
	# Update raycast origin to follow the grabbed position
	if is_grabbed and grabbed_collision_shapes.size() > 0:
		var first_shape = grabbed_collision_shapes[0]
		if is_instance_valid(first_shape):
			raycast.global_transform = first_shape.global_transform
	
	raycast.force_raycast_update()
	_has_hit = raycast.is_colliding()
	
	if _has_hit:
		_hit_point = raycast.get_collision_point()
		_hit_normal = raycast.get_collision_normal()
		_last_collider = raycast.get_collider()
	else:
		_hit_point = raycast.to_global(Vector3(0, 0, -ray_length))
		_hit_normal = Vector3.UP
		_last_collider = null
		_clear_hover()


func _find_pointer_handler(collider: Object) -> Node:
	"""Find a node that can handle pointer events by walking up the tree"""
	if not collider or not is_instance_valid(collider):
		return null
	
	var node = collider as Node
	while node:
		if pointer_handler_group != StringName() and node.is_in_group(pointer_handler_group):
			return node
		if node.has_method("handle_pointer_event"):
			return node
		node = node.get_parent()
	return null


func _process_pointer_events(handler: Node, action_state: Dictionary) -> void:
	"""Send pointer events to the handler"""
	var event = _build_pointer_event(handler, action_state)
	
	# Handle hover enter/exit
	if handler != _hover_target:
		if _hover_target and is_instance_valid(_hover_target) and _hover_target.has_method("handle_pointer_event"):
			var exit_event = event.duplicate()
			exit_event["type"] = "exit"
			_hover_target.call_deferred("handle_pointer_event", exit_event)
		
		_hover_target = handler
		event["type"] = "enter"
		if handler.has_method("handle_pointer_event"):
			handler.call_deferred("handle_pointer_event", event)
	
	# Send appropriate event based on action state
	if action_state["just_pressed"]:
		event["type"] = "press"
		event["action_just_pressed"] = true
		if handler.has_method("handle_pointer_event"):
			handler.call_deferred("handle_pointer_event", event)
		
		# Check if we hit the reference block - paint it
		if _is_reference_block_handler(handler):
			_paint_at_hit()
		# Check if we hit a color picker - sample the color
		elif _is_color_picker_viewport(handler):
			_sample_color_from_picker()
	
	elif action_state["pressed"]:
		event["type"] = "hold"
		event["action_pressed"] = true
		if handler.has_method("handle_pointer_event"):
			handler.call_deferred("handle_pointer_event", event)
		
		# Continuous painting on reference block
		if _is_reference_block_handler(handler):
			_paint_at_hit()
	
	elif action_state["just_released"]:
		event["type"] = "release"
		event["action_just_released"] = true
		if handler.has_method("handle_pointer_event"):
			handler.call_deferred("handle_pointer_event", event)
	
	else:
		# Hover
		event["type"] = "hover"
		if handler.has_method("handle_pointer_event"):
			handler.call_deferred("handle_pointer_event", event)


func _build_pointer_event(handler: Node, action_state: Dictionary) -> Dictionary:
	"""Build a pointer event dictionary similar to hand_pointer"""
	var event = {
		"type": "hover",
		"global_position": _hit_point,
		"global_normal": _hit_normal,
		"pointer": self,
		"pointer_color": _current_color,
		"action_pressed": action_state.get("pressed", false),
		"action_just_pressed": action_state.get("just_pressed", false),
		"action_just_released": action_state.get("just_released", false)
	}
	
	# Add local position/normal if handler is a Node3D
	if handler is Node3D:
		var handler3d = handler as Node3D
		event["local_position"] = handler3d.to_local(_hit_point)
		event["local_normal"] = (handler3d.global_transform.basis.transposed() * _hit_normal).normalized()
	
	return event


func _is_reference_block_handler(handler: Node) -> bool:
	"""Check if the handler is the reference block or its handler"""
	if handler is ReferenceBlock:
		return true
	if handler is ReferenceBlockHandler:
		return true
	if handler.name == "BlockMesh" and handler.get_parent() is ReferenceBlock:
		return true
	return false


func _is_color_picker_viewport(handler: Node) -> bool:
	"""Check if the handler is a color picker viewport"""
	if handler.name.contains("ColorPicker"):
		return true
	var viewport = handler.get_node_or_null("SubViewport")
	if viewport:
		var picker = viewport.get_node_or_null("ColorPickerUI")
		if picker:
			return true
	return false


func _clear_hover() -> void:
	"""Clear hover state and send exit event"""
	if _hover_target and is_instance_valid(_hover_target) and _hover_target.has_method("handle_pointer_event"):
		var exit_event = {"type": "exit", "global_position": _hit_point}
		_hover_target.call_deferred("handle_pointer_event", exit_event)
	_hover_target = null


func _paint_at_hit() -> void:
	"""Paint on the reference block at the hit point"""
	if not _reference_block:
		_find_reference_block()
		if not _reference_block:
			return
	
	var handler = _reference_block.mesh_instance
	if not handler:
		return
	
	var local_pos = handler.global_transform.affine_inverse() * _hit_point
	var local_normal = handler.global_transform.basis.inverse() * _hit_normal
	
	_reference_block.paint_at(local_pos, local_normal.normalized(), _current_color)


func _sample_color_from_picker() -> void:
	"""Sample the current color from the color picker UI"""
	if _color_picker_ui:
		_current_color = _color_picker_ui.get_current_color()
		_update_brush_tip_color()
		print("PaintBrush: Sampled color ", _current_color)


func _update_visuals() -> void:
	var show_ray = always_show_ray or _has_hit
	
	# Update ray visual - need to position it at the grabbed location
	if ray_visual and ray_immediate_mesh:
		ray_visual.visible = show_ray
		if show_ray:
			_draw_ray()
	
	# Update hit marker at world position
	if hit_marker and is_instance_valid(hit_marker):
		hit_marker.visible = _has_hit
		if _has_hit:
			hit_marker.global_position = _hit_point
			var mat = hit_marker.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color = Color(_current_color.r, _current_color.g, _current_color.b, 0.8)


func _draw_ray() -> void:
	ray_immediate_mesh.clear_surfaces()
	ray_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	var end_point = Vector3(0, 0, -ray_length)
	if _has_hit:
		end_point = raycast.to_local(_hit_point)
	
	ray_immediate_mesh.surface_add_vertex(Vector3.ZERO)
	ray_immediate_mesh.surface_add_vertex(end_point)
	ray_immediate_mesh.surface_end()
	
	var mat = ray_visual.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = ray_hit_color if _has_hit else ray_color


func _set_visuals_visible(visible_state: bool) -> void:
	if ray_visual:
		ray_visual.visible = visible_state
	if hit_marker and is_instance_valid(hit_marker):
		hit_marker.visible = visible_state


# === Public API ===

func get_current_color() -> Color:
	return _current_color


func set_color(color: Color) -> void:
	_current_color = color
	_update_brush_tip_color()
