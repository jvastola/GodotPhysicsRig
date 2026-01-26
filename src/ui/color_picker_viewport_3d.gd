extends "res://src/ui/ui_viewport_3d.gd"

# Specialized viewport that allows poke interactions to pick colors from the UI

func handle_pointer_event(event: Dictionary) -> void:
	# 1. Allow normal UI interaction (clicking buttons, moving sliders)
	super.handle_pointer_event(event)

	# 2. Check if we should transfer color to the pointer (Poker)
	# We want to do this on "press" or "hold" so updating the color feels responsive
	var type = event.get("type", "")
	if type == "press" or type == "hold":
		var pointer = event.get("pointer")
		if pointer and "poke_color" in pointer:
			_update_pointer_color(pointer)


func _update_pointer_color(pointer: Node) -> void:
	# Get the current color from the UI
	var color_picker_ui = _find_color_picker_ui()
	if not color_picker_ui:
		return
		
	var current_color = color_picker_ui.get_current_color()
	print("ColorPickerViewport3D: Sampling color ", current_color, " for pointer ", pointer.name)
	
	# Update the pointer's color
	# PokeInteractor has a setter that updates visuals automatically
	pointer.poke_color = current_color


func _find_color_picker_ui() -> ColorPickerUI:
	if not viewport:
		return null
		
	# Try to find the typed node
	# Since viewport children are dynamic, search for group or type
	for child in viewport.get_children():
		if child is ColorPickerUI:
			return child as ColorPickerUI
			
	# Fallback: search recursive
	var result = viewport.find_child("ColorPickerUI", true, false) as ColorPickerUI
	if not result:
		print("ColorPickerViewport3D: WARNING - Could not find ColorPickerUI in viewport!")
	return result
