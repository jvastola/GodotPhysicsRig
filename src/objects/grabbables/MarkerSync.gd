# MarkerSync - Handles synchronization for the marker
# Based on VRCMarker implementation
extends Node

# State
var state: int = 0


func sync_marker() -> void:
	"""Sync the marker state"""
	# In VRC, this would call RequestSerialization()
	# In Godot, we'd handle this through the network manager
	pass