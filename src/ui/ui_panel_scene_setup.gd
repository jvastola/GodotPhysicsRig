class_name UIPanelSceneSetup
extends Node
## Removes pre-placed UI panels from the scene on startup
## and sets up the UIPanelManager for on-demand panel spawning.
##
## Add this node to any scene to enable the new UI panel management system.
## Pre-placed UI panels will be removed and can be spawned via the watch menu.

## List of UI panel node names to remove on startup
const UI_PANEL_NAMES := [
	"MovementSettingsViewport3D2",
	"KeyboardFullViewport3D",
	"FileSystemViewport3D",
	"SceneHierarchyViewport3D",
	"NodeInspectorViewport3D",
	"ScriptEditorViewport3D",
	"DebugConsoleViewport3D",
	"GitViewport3D",
	"UnifiedRoomViewport3D",
	"LiveKitViewport3D",
	"LegalViewport3D",
	"ColorPickerViewport3D",
	"PolyToolViewport3D",
	"ActionMapViewport3D",
	"TwoHandGrabSettingsViewport3D",
	# Keep PerformancePanelViewport3D as it's useful for managing panels
]

## Whether to remove pre-placed UI panels on startup
@export var remove_preplaced_panels: bool = true

## Whether to keep the Performance Panel (useful for managing other panels)
@export var keep_performance_panel: bool = true

## Whether to automatically create a UIPanelManager if one doesn't exist
@export var auto_create_manager: bool = true

var _manager: Node = null


func _ready() -> void:
	call_deferred("_setup")


func _setup() -> void:
	if remove_preplaced_panels:
		_remove_preplaced_panels()
	
	if auto_create_manager:
		_ensure_panel_manager()


func _remove_preplaced_panels() -> void:
	"""Remove pre-placed UI panels from the scene."""
	var parent := get_parent()
	if not parent:
		return
	
	var removed_count := 0
	for panel_name in UI_PANEL_NAMES:
		# Skip performance panel if configured to keep it
		if keep_performance_panel and panel_name == "PerformancePanelViewport3D":
			continue
		
		var panel := parent.get_node_or_null(panel_name)
		if panel:
			panel.queue_free()
			removed_count += 1
	
	if removed_count > 0:
		print("UIPanelSceneSetup: Removed %d pre-placed UI panels" % removed_count)


func _ensure_panel_manager() -> void:
	"""Create a UIPanelManager if one doesn't exist."""
	var parent := get_parent()
	if not parent:
		return
	
	# Check if manager already exists
	var existing := parent.get_node_or_null("UIPanelManager")
	if existing:
		_manager = existing
		return
	
	# Also check via the static finder
	var manager_script := preload("res://src/ui/ui_panel_manager.gd")
	var found := manager_script.find()
	if found:
		_manager = found
		return
	
	# Create new manager
	_manager = manager_script.new()
	_manager.name = "UIPanelManager"
	parent.add_child(_manager)
	print("UIPanelSceneSetup: Created UIPanelManager")
