extends StaticBody3D

@export var mesh_node_path: NodePath = NodePath("MeshInstance3D")
@export var collision_shape_path: NodePath = NodePath("CollisionShape3D")

var _mesh_instance: MeshInstance3D

func _ready() -> void:
	_mesh_instance = get_node_or_null(mesh_node_path) as MeshInstance3D

func set_build_color(color: Color) -> void:
	if not _mesh_instance:
		_mesh_instance = get_node_or_null(mesh_node_path) as MeshInstance3D
	if not _mesh_instance:
		return
	var material: StandardMaterial3D = _mesh_instance.material_override as StandardMaterial3D
	if not material:
		material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	_mesh_instance.material_override = material
