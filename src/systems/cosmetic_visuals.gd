class_name CosmeticVisuals
extends RefCounted


static func create_head_cosmetic(item_id: String, for_local_player: bool = true) -> Node3D:
	match item_id:
		"hat_duck":
			return _create_model_cosmetic("res://assets/models/duckhat.fbx", for_local_player)
		"hat_cowboy":
			return _create_model_cosmetic("res://assets/models/cowboyhat.fbx", for_local_player)
		_:
			return null


static func _create_model_cosmetic(model_path: String, for_local_player: bool = true) -> Node3D:
	var scene := load(model_path) as PackedScene
	if not scene:
		push_warning("CosmeticVisuals: Failed to load model: " + model_path)
		return null
	var instance := scene.instantiate() as Node3D
	if not instance:
		push_warning("CosmeticVisuals: Failed to instantiate model: " + model_path)
		return null
	
	# Fix materials and lighting
	_fix_materials_recursive(instance)
	
	# Set layers: only local player cosmetics use mirror-only layers
	# Remote players and previews use default layers (visible normally)
	if for_local_player:
		_set_mirror_layers_recursive(instance)
	
	return instance


static func _fix_materials_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		
		# Fix materials to use proper lighting
		for i in range(mesh_instance.get_surface_override_material_count()):
			var mat := mesh_instance.get_surface_override_material(i)
			if mat is StandardMaterial3D:
				var std_mat := mat as StandardMaterial3D
				# Ensure proper shading
				std_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				# Disable any weird flags
				std_mat.flags_unshaded = false
				std_mat.flags_transparent = false
		
		# Also check material_override
		if mesh_instance.material_override is StandardMaterial3D:
			var mat := mesh_instance.material_override as StandardMaterial3D
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			mat.flags_unshaded = false
			mat.flags_transparent = false
	
	for child in node.get_children():
		_fix_materials_recursive(child)


static func _set_mirror_layers_recursive(node: Node) -> void:
	const MIRROR_ONLY_LAYER = 10
	const MIRROR_ONLY_MASK = 1 << (MIRROR_ONLY_LAYER - 1)
	
	if node is MeshInstance3D:
		node.layers = MIRROR_ONLY_MASK
	
	for child in node.get_children():
		_set_mirror_layers_recursive(child)
