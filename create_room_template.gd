extends EditorScript

# Quick Scene Creator
# Run this from Godot Editor: File → Run Script
# Creates a new room template with all essentials

func _run():
	var room_name = "NewRoom"
	var scene_path = "res://%s.tscn" % room_name
	
	# Check if file already exists
	if FileAccess.file_exists(scene_path):
		print("⚠️  Scene already exists: ", scene_path)
		return
	
	# Create new scene
	var root = Node3D.new()
	root.name = room_name
	
	# Add WorldEnvironment
	var env_node = WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var environment = Environment.new()
	env_node.environment = environment
	root.add_child(env_node)
	env_node.owner = root
	
	# Add DirectionalLight3D
	var light = DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.transform.origin = Vector3(0, 5, 0)
	light.rotation_degrees = Vector3(-45, 45, 0)
	light.shadow_enabled = true
	root.add_child(light)
	light.owner = root
	
	# Add Floor
	var floor = StaticBody3D.new()
	floor.name = "Floor"
	floor.position = Vector3(0, -0.5, 0)
	floor.collision_layer = 1
	floor.collision_mask = 0
	
	var floor_collision = CollisionShape3D.new()
	var floor_shape = BoxShape3D.new()
	floor_shape.size = Vector3(20, 1, 20)
	floor_collision.shape = floor_shape
	floor.add_child(floor_collision)
	floor_collision.owner = root
	
	var floor_mesh_inst = MeshInstance3D.new()
	var floor_mesh = BoxMesh.new()
	floor_mesh.size = Vector3(20, 1, 20)
	floor_mesh_inst.mesh = floor_mesh
	floor_collision.add_child(floor_mesh_inst)
	floor_mesh_inst.owner = root
	
	root.add_child(floor)
	floor.owner = root
	
	# Add SpawnPoint
	var spawn = Marker3D.new()
	spawn.name = "SpawnPoint"
	spawn.position = Vector3(0, 2, 0)
	root.add_child(spawn)
	spawn.owner = root
	
	# Pack and save scene
	var packed_scene = PackedScene.new()
	packed_scene.pack(root)
	
	var err = ResourceSaver.save(packed_scene, scene_path)
	
	if err == OK:
		print("✅ Created new room: ", scene_path)
		print("📝 Next steps:")
		print("   1. Open ", room_name, ".tscn")
		print("   2. Add Portal.tscn instance")
		print("   3. Configure portal target scene")
	else:
		print("❌ Failed to create scene: ", err)
