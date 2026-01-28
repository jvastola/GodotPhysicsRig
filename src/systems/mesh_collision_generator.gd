@tool
class_name MeshCollisionGenerator
extends Node
## Automatically generates trimesh collision shapes for all MeshInstance3D children.

## If true, collisions will be generated when the scene is loaded at runtime.
@export var generate_on_ready: bool = true

## If true, existing StaticBody3D nodes named "GeneratedStaticBody" will be removed before generating new ones.
@export var clean_existing: bool = true

## The collision layer to assign to the generated StaticBody3D nodes.
@export_flags_3d_physics var collision_layer: int = 1

## The collision mask to assign to the generated StaticBody3D nodes.
@export_flags_3d_physics var collision_mask: int = 1


func _ready() -> void:
	if not Engine.is_editor_hint() and generate_on_ready:
		generate_collisions()


## Recursively finds MeshInstance3D nodes and creates trimesh collisions for them.
func generate_collisions() -> void:
	var parent = get_parent()
	if not parent:
		push_error("MeshCollisionGenerator: No parent node found.")
		return
	
	if clean_existing:
		_remove_generated_collisions(parent)
	
	var mesh_instances: Array[MeshInstance3D] = []
	_find_mesh_instances(parent, mesh_instances)
	
	var count = 0
	for mesh_instance in mesh_instances:
		if mesh_instance.mesh:
			_create_collision_for_mesh(mesh_instance)
			count += 1
	
	print("MeshCollisionGenerator: Generated collisions for ", count, " mesh instances under ", parent.name)


func _find_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node)
	
	for child in node.get_children():
		_find_mesh_instances(child, result)


func _create_collision_for_mesh(mesh_instance: MeshInstance3D) -> void:
	# Create a StaticBody3D
	var static_body = StaticBody3D.new()
	static_body.name = "GeneratedStaticBody"
	static_body.collision_layer = collision_layer
	static_body.collision_mask = collision_mask
	
	# Add it as a child of the mesh instance
	mesh_instance.add_child(static_body)
	
	# Trigger trimesh collision generation
	# mesh_instance.create_trimesh_collision() creates a child StaticBody3D/CollisionShape3D 
	# but we want more control, so we'll do it manually if possible or use the helper.
	# Actually, create_trimesh_collision() is perfect for complex terrain.
	
	# Alternative: use the built-in helper but it adds children to the mesh_instance.
	# We'll use the mesh data to create a CollisionShape3D.
	var collision_shape = CollisionShape3D.new()
	collision_shape.name = "GeneratedCollisionShape"
	collision_shape.shape = mesh_instance.mesh.create_trimesh_shape()
	
	static_body.add_child(collision_shape)


func _remove_generated_collisions(node: Node) -> void:
	for child in node.get_children():
		if child.name == "GeneratedStaticBody" and child is StaticBody3D:
			child.queue_free()
		else:
			_remove_generated_collisions(child)
