extends StaticBody3D

# Attach to the Floor StaticBody3D. Listens for pointer 'press' events
# and changes the floor MeshInstance3D's material color.

@onready var _mesh_inst: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D


func handle_pointer_event(event: Dictionary) -> void:
	if event.is_empty():
		return
	var etype: String = String(event.get("type", ""))
	if etype == "press" or event.get("action_just_pressed", false):
		if not _mesh_inst:
			# fallback: try to find a MeshInstance3D child at runtime
			_mesh_inst = get_node_or_null("MeshInstance3D") as MeshInstance3D
			if not _mesh_inst:
				return
		var mat: StandardMaterial3D = _mesh_inst.material_override as StandardMaterial3D
		if not mat:
			mat = StandardMaterial3D.new()
			_mesh_inst.material_override = mat
		# choose a color for the floor and the pointer
		var chosen_color: Color = Color(randf(), randf(), randf(), 1.0)
		mat.albedo_color = chosen_color
		# If the pointer is present in the event, set its carried color so
		# subsequent paint actions use this color.
		var pointer = event.get("pointer", null)
		if pointer:
			# Best-effort: set pointer fields used by the pointer system
			pointer.pointer_color = chosen_color
			pointer.include_pointer_color = true
