@tool
class_name XRToolsGroundPhysics
extends Node

## Ground physics settings resource
@export var physics : XRToolsGroundPhysicsSettings

## Get the physics settings from a node, falling back to default if needed
static func get_physics(
		physics_node: XRToolsGroundPhysics, 
		default_physics: XRToolsGroundPhysicsSettings) -> XRToolsGroundPhysicsSettings:
	
	# Return the physics from the node if it exists and has physics
	if physics_node and physics_node.physics:
		return physics_node.physics
	
	# Fall back to default physics
	return default_physics