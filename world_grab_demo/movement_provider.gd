@tool
class_name XRToolsMovementProvider
extends Node

## Base class for movement providers
##
## This class provides the base functionality for movement providers that can
## modify player movement and behavior.

## Movement provider order
@export var order : int = 10

## Movement provider enabled
@export var enabled : bool = true

## Movement provider active state
var is_active : bool = false

## Player body reference
var player_body : XRToolsPlayerBody

## Called when the movement provider is added to the player
func _ready():
	# Add to movement providers group
	add_to_group("movement_providers")
	
	# Find the player body
	player_body = XRToolsPlayerBody.find_instance(self)
	if player_body:
		player_body._add_movement_provider(self)

## Physics pre-movement function called by the player body
func physics_pre_movement(_delta: float, _player_body: XRToolsPlayerBody):
	pass

## Physics movement function called by the player body
## Returns true if this provider should be exclusive (no other providers should run)
func physics_movement(_delta: float, _player_body: XRToolsPlayerBody, _disabled: bool) -> bool:
	return false

## Called when the movement provider is enabled/disabled
func set_enabled(new_enabled: bool):
	enabled = new_enabled

## Get the movement provider order for sorting
func get_order() -> int:
	return order

## Add support for is_xr_class on XRTools classes
func is_xr_class(xr_name: String) -> bool:
	return xr_name == "XRToolsMovementProvider"

## Get configuration warnings for this movement provider
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	return warnings