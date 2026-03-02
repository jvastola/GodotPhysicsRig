class_name CosmeticVisuals
extends RefCounted


static func create_head_cosmetic(item_id: String) -> Node3D:
	match item_id:
		"hat_basic_red":
			return _create_baseball_cap(Color(0.9, 0.15, 0.15), Color(0.95, 0.95, 0.95))
		"hat_basic_black":
			return _create_baseball_cap(Color(0.12, 0.12, 0.12), Color(0.9, 0.9, 0.9))
		_:
			return null


static func _create_baseball_cap(primary_color: Color, accent_color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "BaseballCap"

	var brim := MeshInstance3D.new()
	brim.name = "Brim"
	var brim_mesh := CylinderMesh.new()
	brim_mesh.top_radius = 0.14
	brim_mesh.bottom_radius = 0.11
	brim_mesh.height = 0.02
	brim_mesh.radial_segments = 24
	brim.mesh = brim_mesh
	brim.position = Vector3(0.0, 0.0, 0.06)
	var brim_mat := StandardMaterial3D.new()
	brim_mat.albedo_color = accent_color
	brim_mat.roughness = 0.9
	brim_mat.metallic = 0.0
	brim.material_override = brim_mat
	root.add_child(brim)

	var crown := MeshInstance3D.new()
	crown.name = "Crown"
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.07
	crown_mesh.bottom_radius = 0.095
	crown_mesh.height = 0.12
	crown_mesh.radial_segments = 24
	crown.mesh = crown_mesh
	crown.position = Vector3(0.0, 0.07, 0.0)
	var crown_mat := StandardMaterial3D.new()
	crown_mat.albedo_color = primary_color
	crown_mat.roughness = 0.85
	crown_mat.metallic = 0.0
	crown.material_override = crown_mat
	root.add_child(crown)

	return root
