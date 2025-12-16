extends Node

# Simple test script to verify the world grab demo dependencies are working

func _ready():
	print("Testing world grab demo dependencies...")
	
	# Test XRToolsUserSettings
	var user_settings = XRToolsUserSettings.new()
	print("✓ XRToolsUserSettings created successfully")
	
	# Test XRToolsGroundPhysicsSettings
	var ground_physics_settings = XRToolsGroundPhysicsSettings.new()
	print("✓ XRToolsGroundPhysicsSettings created successfully")
	
	# Test XRToolsGroundPhysics
	var ground_physics = XRToolsGroundPhysics.new()
	print("✓ XRToolsGroundPhysics created successfully")
	
	# Test XRTools static methods
	var grip_threshold = XRTools.get_grip_threshold()
	print("✓ XRTools.get_grip_threshold() returned: ", grip_threshold)
	
	# Test XRToolsRumbleManager
	var haptics_scale = XRToolsRumbleManager.get_default_haptics_scale()
	print("✓ XRToolsRumbleManager.get_default_haptics_scale() returned: ", haptics_scale)
	
	print("All dependencies are working correctly!")
	print("You can now run the world grab demo scene: world_grab_demo/world_grab_demo_v2.tscn")