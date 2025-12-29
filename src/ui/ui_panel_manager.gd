class_name UIPanelManager
extends Node
## Manages UI panels in VR with performance optimizations
##
## Features:
## - Maximum panel limit with FIFO queue (oldest panels auto-close when limit reached)
## - Distance-based panel visibility (panels beyond threshold are hidden)
## - Centralized panel spawning and tracking

signal panel_opened(panel_name: String, panel_node: Node3D)
signal panel_closed(panel_name: String)
signal settings_changed()

# === Settings ===

## Maximum number of UI panels that can be displayed at once (0 = unlimited)
@export var max_panels: int = 3

## Distance from player camera beyond which panels are hidden (0 = disabled)
@export var max_panel_distance: float = 5.0

## Whether to auto-hide panels based on distance
@export var distance_culling_enabled: bool = true

## How often to check panel distances (seconds)
@export var distance_check_interval: float = 0.5

## Default distance to spawn panels in front of player
@export var default_spawn_distance: float = 1.6

# === Internal State ===

## Queue of active panel names (oldest first)
var _active_panels: Array[String] = []

## Map of panel name -> Node3D reference
var _panel_nodes: Dictionary = {}

## Map of panel name -> scene path
var _panel_scene_paths: Dictionary = {}

## Reference to XR camera for distance checks
var _xr_camera: XRCamera3D = null

## Timer for distance checks
var _distance_check_timer: float = 0.0

## Panels that are currently hidden due to distance
var _distance_hidden_panels: Array[String] = []

## Map of panel name -> placeholder mesh for distance-culled panels
var _placeholder_meshes: Dictionary = {}

## Placeholder material (semi-transparent)
var _placeholder_material: StandardMaterial3D = null


# === Scene Paths ===
const UI_SCENE_PATHS := {
	"MovementSettingsViewport3D2": "res://src/ui/MovementSettingsViewport2.tscn",
	"KeyboardFullViewport3D": "res://src/ui/KeyboardFullViewport3D.tscn",
	"FileSystemViewport3D": "res://src/ui/FileSystemViewport3D.tscn",
	"SceneHierarchyViewport3D": "res://src/ui/SceneHierarchyViewport3D.tscn",
	"DebugConsoleViewport3D": "res://src/ui/DebugConsoleViewport3D.tscn",
	"GitViewport3D": "res://src/ui/git/GitViewport3D.tscn",
	"UnifiedRoomViewport3D": "res://src/ui/multiplayer/UnifiedRoomViewport3D.tscn",
	"LiveKitViewport3D": "res://src/ui/livekit/LiveKitViewport3D.tscn",
	"NodeInspectorViewport3D": "res://src/ui/NodeInspectorViewport3D.tscn",
	"ScriptEditorViewport3D": "res://src/ui/ScriptEditorViewport3D.tscn",
	"LegalViewport3D": "res://src/ui/legal/LegalViewport3D.tscn",
	"ColorPickerViewport3D": "res://src/ui/ColorPickerViewport3D.tscn",
	"MaterialPickerViewport3D": "res://src/ui/MaterialPickerViewport3D.tscn",
	"PolyToolViewport3D": "res://src/ui/PolyToolViewport3D.tscn",
	"PerformancePanelViewport3D": "res://src/ui/PerformancePanelViewport3D.tscn",
	"ActionMapViewport3D": "res://src/ui/ActionMapViewport3D.tscn",
	"TwoHandGrabSettingsViewport3D": "res://src/ui/TwoHandGrabSettingsViewport3D.tscn",
	"AddNodeViewport3D": "res://src/ui/AddNodeViewport3D.tscn",
}


func _ready() -> void:
	_panel_scene_paths = UI_SCENE_PATHS.duplicate()
	_create_placeholder_material()
	call_deferred("_find_camera")


func _create_placeholder_material() -> void:
	"""Create the material used for placeholder panels."""
	_placeholder_material = StandardMaterial3D.new()
	_placeholder_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_placeholder_material.albedo_color = Color(0.3, 0.4, 0.5, 0.4)
	_placeholder_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_placeholder_material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _process(delta: float) -> void:
	if not distance_culling_enabled or max_panel_distance <= 0:
		return
	
	_distance_check_timer += delta
	if _distance_check_timer >= distance_check_interval:
		_distance_check_timer = 0.0
		_check_panel_distances()


func _find_camera() -> void:
	var player = get_tree().get_first_node_in_group("xr_player")
	if player:
		_xr_camera = player.get_node_or_null("PlayerBody/XROrigin3D/XRCamera3D") as XRCamera3D


# === Public API ===

func open_panel(panel_name: String, in_front_of_player: bool = true) -> Node3D:
	"""Open a UI panel. If max_panels is reached, closes the oldest panel first."""
	# Check if panel is already open
	if panel_name in _active_panels:
		# Move to front of queue (most recent)
		_active_panels.erase(panel_name)
		_active_panels.append(panel_name)
		# If hidden due to distance, show it
		if panel_name in _distance_hidden_panels:
			_show_panel(panel_name)
		# Move existing panel in front of player
		if in_front_of_player and _panel_nodes.has(panel_name):
			_position_panel_in_front(_panel_nodes[panel_name])
		return _panel_nodes.get(panel_name, null)
	
	# Enforce max panels limit
	if max_panels > 0 and _active_panels.size() >= max_panels:
		var oldest_panel: String = _active_panels[0]
		close_panel(oldest_panel)
	
	# Spawn the panel
	var panel_node := _spawn_panel(panel_name)
	if panel_node:
		_active_panels.append(panel_name)
		_panel_nodes[panel_name] = panel_node
		if in_front_of_player:
			_position_panel_in_front(panel_node)
		panel_opened.emit(panel_name, panel_node)
	
	return panel_node


func close_panel(panel_name: String) -> void:
	"""Close and remove a UI panel."""
	if panel_name not in _active_panels:
		return
	
	_active_panels.erase(panel_name)
	_distance_hidden_panels.erase(panel_name)
	
	# Clean up placeholder if exists
	_remove_placeholder(panel_name)
	
	if _panel_nodes.has(panel_name):
		var node: Node3D = _panel_nodes[panel_name]
		if is_instance_valid(node):
			node.queue_free()
		_panel_nodes.erase(panel_name)
	
	panel_closed.emit(panel_name)


func close_all_panels() -> void:
	"""Close all open UI panels."""
	var panels_to_close := _active_panels.duplicate()
	for panel_name in panels_to_close:
		close_panel(panel_name)


func is_panel_open(panel_name: String) -> bool:
	return panel_name in _active_panels


func get_active_panel_count() -> int:
	return _active_panels.size()


func get_active_panels() -> Array[String]:
	return _active_panels.duplicate()


func set_max_panels(value: int) -> void:
	max_panels = maxi(0, value)
	# Close excess panels if needed
	while max_panels > 0 and _active_panels.size() > max_panels:
		close_panel(_active_panels[0])
	settings_changed.emit()


func set_max_distance(value: float) -> void:
	max_panel_distance = maxf(0.0, value)
	settings_changed.emit()


func set_distance_culling(enabled: bool) -> void:
	distance_culling_enabled = enabled
	# Show all hidden panels if disabling
	if not enabled:
		for panel_name in _distance_hidden_panels.duplicate():
			_show_panel(panel_name)
		_distance_hidden_panels.clear()
	settings_changed.emit()


# === Internal Methods ===

func _spawn_panel(panel_name: String) -> Node3D:
	"""Spawn a new panel instance."""
	var scene_root: Node = get_tree().current_scene
	if not scene_root:
		var gm: Node = get_tree().root.get_node_or_null("GameManager")
		if gm and gm.has_method("get") and gm.get("current_world"):
			scene_root = gm.get("current_world")
	
	if not scene_root:
		push_warning("UIPanelManager: No scene root found")
		return null
	
	# Check if panel already exists in scene
	var existing := scene_root.get_node_or_null(panel_name)
	if existing and existing is Node3D:
		return existing as Node3D
	
	# Load and instantiate
	var scene_path: String = _panel_scene_paths.get(panel_name, "")
	if scene_path.is_empty():
		push_warning("UIPanelManager: Unknown panel: %s" % panel_name)
		return null
	
	var packed := load(scene_path)
	if not packed or not packed is PackedScene:
		push_warning("UIPanelManager: Failed to load scene: %s" % scene_path)
		return null
	
	var instance := (packed as PackedScene).instantiate()
	if not instance or not instance is Node3D:
		push_warning("UIPanelManager: Instantiated scene is not Node3D: %s" % panel_name)
		if instance:
			instance.queue_free()
		return null
	
	instance.name = panel_name
	scene_root.add_child(instance)
	print("UIPanelManager: Spawned panel: %s" % panel_name)
	return instance as Node3D


func _position_panel_in_front(panel: Node3D, distance: float = -1.0) -> void:
	"""Position a panel in front of the player camera."""
	if not _xr_camera:
		_find_camera()
	if not _xr_camera:
		return
	
	var spawn_dist := distance if distance > 0 else default_spawn_distance
	var cam_tf := _xr_camera.global_transform
	var forward := -cam_tf.basis.z.normalized()
	var target_origin := cam_tf.origin + forward * spawn_dist
	
	var xf: Transform3D = panel.global_transform
	var current_scale := xf.basis.get_scale()
	xf.origin = target_origin
	
	# Face the camera
	var dir_to_camera := cam_tf.origin - target_origin
	dir_to_camera.y = 0
	if dir_to_camera.length_squared() > 0.0001:
		dir_to_camera = dir_to_camera.normalized()
		var facing_basis := Basis.looking_at(-dir_to_camera, Vector3.UP)
		xf.basis = facing_basis.scaled(current_scale)
	else:
		xf.basis = Basis.IDENTITY.scaled(current_scale)
	
	panel.global_transform = xf


func _check_panel_distances() -> void:
	"""Check distances of all panels and hide/show based on threshold."""
	if not _xr_camera:
		_find_camera()
	if not _xr_camera:
		return
	
	var camera_pos := _xr_camera.global_position
	
	for panel_name in _active_panels:
		if not _panel_nodes.has(panel_name):
			continue
		
		var panel: Node3D = _panel_nodes[panel_name]
		if not is_instance_valid(panel):
			continue
		
		var distance := camera_pos.distance_to(panel.global_position)
		var is_hidden := panel_name in _distance_hidden_panels
		
		if distance > max_panel_distance and not is_hidden:
			_hide_panel(panel_name)
		elif distance <= max_panel_distance and is_hidden:
			_show_panel(panel_name)


func _hide_panel(panel_name: String) -> void:
	"""Hide a panel due to distance, showing a placeholder instead."""
	if panel_name in _distance_hidden_panels:
		return
	
	_distance_hidden_panels.append(panel_name)
	
	if _panel_nodes.has(panel_name):
		var panel: Node3D = _panel_nodes[panel_name]
		if is_instance_valid(panel):
			# Hide the actual panel content but keep the node
			_hide_panel_content(panel)
			# Create and show placeholder
			_create_placeholder(panel_name, panel)
			# Disable processing if possible
			if panel.has_method("set_interactive"):
				panel.call("set_interactive", false)


func _show_panel(panel_name: String) -> void:
	"""Show a panel that was hidden due to distance."""
	_distance_hidden_panels.erase(panel_name)
	
	if _panel_nodes.has(panel_name):
		var panel: Node3D = _panel_nodes[panel_name]
		if is_instance_valid(panel):
			# Show the actual panel content
			_show_panel_content(panel)
			# Remove placeholder
			_remove_placeholder(panel_name)
			if panel.has_method("set_interactive"):
				panel.call("set_interactive", true)


func _hide_panel_content(panel: Node3D) -> void:
	"""Hide the panel's visual content (SubViewport, MeshInstance3D with texture)."""
	# Find and hide the mesh that displays the viewport texture
	var mesh := panel.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh:
		mesh.visible = false
	# Also try to find SubViewport and disable it
	var viewport := panel.get_node_or_null("SubViewport") as SubViewport
	if viewport:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _show_panel_content(panel: Node3D) -> void:
	"""Show the panel's visual content."""
	var mesh := panel.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh:
		mesh.visible = true
	var viewport := panel.get_node_or_null("SubViewport") as SubViewport
	if viewport:
		viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE


func _create_placeholder(panel_name: String, panel: Node3D) -> void:
	"""Create a placeholder mesh at the panel's location."""
	if _placeholder_meshes.has(panel_name):
		return
	
	# Get the size from the existing mesh if possible
	var size := Vector2(2.0, 2.0)  # Default size
	var existing_mesh := panel.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if existing_mesh and existing_mesh.mesh:
		if existing_mesh.mesh is QuadMesh:
			size = (existing_mesh.mesh as QuadMesh).size
		elif existing_mesh.mesh is PlaneMesh:
			size = (existing_mesh.mesh as PlaneMesh).size
	
	# Create placeholder mesh
	var placeholder := MeshInstance3D.new()
	placeholder.name = "DistancePlaceholder"
	
	var quad := QuadMesh.new()
	quad.size = size
	placeholder.mesh = quad
	placeholder.material_override = _placeholder_material
	placeholder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# Add to panel (will inherit transform)
	panel.add_child(placeholder)
	_placeholder_meshes[panel_name] = placeholder


func _remove_placeholder(panel_name: String) -> void:
	"""Remove the placeholder mesh for a panel."""
	if _placeholder_meshes.has(panel_name):
		var placeholder: MeshInstance3D = _placeholder_meshes[panel_name]
		if is_instance_valid(placeholder):
			placeholder.queue_free()
		_placeholder_meshes.erase(panel_name)


# === Singleton Access ===

static var _instance: UIPanelManager = null

static func get_instance() -> UIPanelManager:
	return _instance

static func find() -> UIPanelManager:
	"""Find the UIPanelManager in the scene tree."""
	if _instance and is_instance_valid(_instance):
		return _instance
	
	# Search in autoloads first
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		var root := tree.root
		for child in root.get_children():
			if child is UIPanelManager:
				_instance = child
				return _instance
		
		# Search in current scene
		var scene := tree.current_scene
		if scene:
			var found := scene.find_child("UIPanelManager", true, false)
			if found and found is UIPanelManager:
				_instance = found
				return _instance
	
	return null


func _enter_tree() -> void:
	_instance = self


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


# === Stats for Performance UI ===

func get_stats() -> Dictionary:
	return {
		"active_panels": _active_panels.size(),
		"max_panels": max_panels,
		"hidden_by_distance": _distance_hidden_panels.size(),
		"distance_culling": distance_culling_enabled,
		"max_distance": max_panel_distance,
	}
