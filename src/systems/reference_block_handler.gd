extends MeshInstance3D
class_name ReferenceBlockHandler

## Handler script for painting on the reference block
## Receives pointer events from the XR hand pointer system

@export var debug_paint: bool = true

var _reference_block: ReferenceBlock = null
var _color_picker_ui: ColorPickerUI = null


func _ready() -> void:
	add_to_group("pointer_interactable")
	call_deferred("_find_reference_block")
	call_deferred("_find_color_picker")


func _find_reference_block() -> void:
	# Parent should be the ReferenceBlock
	var parent := get_parent()
	if parent is ReferenceBlock:
		_reference_block = parent
		return
	
	if ReferenceBlock.instance:
		_reference_block = ReferenceBlock.instance
		return
	
	var blocks := get_tree().get_nodes_in_group("reference_block")
	if blocks.size() > 0:
		_reference_block = blocks[0] as ReferenceBlock


func _find_color_picker() -> void:
	if ColorPickerUI.instance:
		_color_picker_ui = ColorPickerUI.instance
		return
	var pickers := get_tree().get_nodes_in_group("color_picker_ui")
	if pickers.size() > 0:
		_color_picker_ui = pickers[0] as ColorPickerUI


func handle_pointer_event(event: Dictionary) -> void:
	"""Called by XR pointer when this mesh is hit"""
	var just_pressed: bool = event.get("action_just_pressed", false)
	var pressed: bool = event.get("action_pressed", false)
	
	if not just_pressed and not pressed:
		return
	
	if not _reference_block:
		_find_reference_block()
	if not _reference_block:
		if debug_paint:
			print("ReferenceBlockHandler: No reference block found")
		return
	
	# Get hit position and normal
	var hit_pos: Vector3
	var hit_normal: Vector3
	
	if event.has("global_position"):
		hit_pos = event["global_position"]
	else:
		if debug_paint:
			print("ReferenceBlockHandler: No position in event")
		return
	
	if event.has("global_normal"):
		hit_normal = event["global_normal"]
	else:
		hit_normal = Vector3.UP
	
	# Convert to this mesh's local space (the mesh is the collision target)
	# The mesh is a child of ReferenceBlock, so use the mesh's transform
	var local_pos := global_transform.affine_inverse() * hit_pos
	var local_normal := global_transform.basis.inverse() * hit_normal
	
	# Get paint color
	var color := Color.WHITE
	if event.has("pointer_color") and event["pointer_color"] is Color:
		color = event["pointer_color"]
	elif _color_picker_ui:
		color = _color_picker_ui.get_current_color()
	
	if debug_paint:
		print("ReferenceBlockHandler: hit_pos=", hit_pos, " local_pos=", local_pos, " normal=", local_normal)
	
	_reference_block.paint_at(local_pos, local_normal.normalized(), color)
