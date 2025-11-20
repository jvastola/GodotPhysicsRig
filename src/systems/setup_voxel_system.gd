@tool
extends EditorScript

## Auto-setup script to add VoxelChunkManager to XRPlayer scene
## Run this from Editor -> Run Script

func _run() -> void:
	print("=== VoxelChunkManager Auto-Setup ===")
	
	# Load the XRPlayer scene
	var scene_path := "res://src/player/XRPlayer.tscn"
	var packed_scene := load(scene_path) as PackedScene
	if not packed_scene:
		print("ERROR: Could not load XRPlayer.tscn")
		return
	
	var root := packed_scene.instantiate()
	if not root:
		print("ERROR: Could not instantiate scene")
		return
	
	print("Loaded XRPlayer scene")
	
	# Check if VoxelChunkManager already exists
	var existing_manager := root.find_child("VoxelChunkManager", false, false)
	if existing_manager:
		print("VoxelChunkManager already exists in scene")
		root.queue_free()
		return
	
	# Create VoxelChunkManager node
	var manager := Node.new()
	manager.name = "VoxelChunkManager"
	manager.set_script(load("res://src/systems/voxel_chunk_manager.gd"))
	root.add_child(manager)
	manager.owner = root
	print("Created VoxelChunkManager node")
	
	# Find GridSnapIndicator
	var indicator := root.find_child("GridSnapIndicator", true, false)
	if indicator and indicator.get_script():
		# Set voxel chunk properties
		indicator.set("use_voxel_chunks", true)
		indicator.set("voxel_chunk_manager_path", indicator.get_path_to(manager))
		print("Configured GridSnapIndicator:")
		print("  - use_voxel_chunks: true")
		print("  - voxel_chunk_manager_path: ", indicator.get("voxel_chunk_manager_path"))
	else:
		print("WARNING: Could not find GridSnapIndicator")
	
	# Save the modified scene
	var new_packed := PackedScene.new()
	var result := new_packed.pack(root)
	if result == OK:
		result = ResourceSaver.save(new_packed, scene_path)
		if result == OK:
			print("Successfully saved modified scene!")
			print("=== Setup Complete ===")
		else:
			print("ERROR: Could not save scene: ", result)
	else:
		print("ERROR: Could not pack scene: ", result)
	
	root.queue_free()
