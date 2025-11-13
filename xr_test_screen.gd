extends MeshInstance3D

# Assign the SubViewport's texture to this mesh's material at runtime
@export var viewport_node_name: String = "XRTestViewport"

func _ready():
	var scene = get_tree().get_current_scene()
	if scene == null:
		return
	var vp = scene.get_node_or_null(viewport_node_name)
	if vp == null:
		# try searching recursively
		for n in scene.get_children():
			vp = n.get_node_or_null(viewport_node_name)
			if vp != null:
				break
	if vp == null:
		print("xr_test_screen.gd: could not find viewport '" + viewport_node_name + "'")
		return
	var tex = vp.get_texture()
	if tex == null:
		print("xr_test_screen.gd: viewport has no texture yet")
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	self.material_override = mat
	print("xr_test_screen.gd: applied viewport texture to mesh")
