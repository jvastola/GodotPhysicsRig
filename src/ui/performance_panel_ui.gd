class_name PerformancePanelUI
extends PanelContainer

signal close_requested


# Node references for tool pool controls
@onready var _status_label: Label = $MarginContainer/ScrollContainer/VBoxContainer/StatusLabel
@onready var _grid: GridContainer = $MarginContainer/ScrollContainer/VBoxContainer/LimitGrid
@onready var _close_button: Button = $MarginContainer/ScrollContainer/VBoxContainer/TitleRow/CloseButton

# Node references for world stats (will be created dynamically if not in scene)
var _stats_container: VBoxContainer
var _voxel_label: Label
var _hull_label: Label
var _poly_label: Label
var _scene_spawn_label: Label
var _scene_spawn_spin: SpinBox
var _clear_scenes_button: Button

# UI Panel Manager controls
var _ui_panel_label: Label
var _ui_max_panels_spin: SpinBox
var _ui_max_distance_spin: SpinBox
var _ui_distance_culling_check: CheckBox
var _ui_close_all_button: Button

var _rows: Dictionary = {}
var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.5  # Update stats every 0.5 seconds


func _ready() -> void:
	_init_rows()
	_init_stats_section()
	_refresh_from_manager()
	set_process(true)
	
	if _close_button:
		_close_button.pressed.connect(func(): close_requested.emit())


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_update_world_stats()


func _init_rows() -> void:
	_rows = {
		"poly_tool": {
			"spin": _grid.get_node_or_null("PolyRow/Spin"),
			"counts": _grid.get_node_or_null("PolyRow/Counts"),
			"label": "Poly Tool",
		},
		"convex_hull": {
			"spin": _grid.get_node_or_null("ConvexRow/Spin"),
			"counts": _grid.get_node_or_null("ConvexRow/Counts"),
			"label": "Convex Hull Pen",
		},
		"volume_hull": {
			"spin": _grid.get_node_or_null("VolumeRow/Spin"),
			"counts": _grid.get_node_or_null("VolumeRow/Counts"),
			"label": "Volume Hull Pen",
		},
		"voxel_tool": {
			"spin": _grid.get_node_or_null("VoxelRow/Spin"),
			"counts": _grid.get_node_or_null("VoxelRow/Counts"),
			"label": "Voxel Tool",
		},
	}
	for tool_type in _rows.keys():
		var spin: SpinBox = _rows[tool_type]["spin"]
		if spin and not spin.value_changed.is_connected(_on_spin_changed):
			spin.value_changed.connect(func(value: float, t: String = tool_type): _on_spin_changed(value, t))


func _init_stats_section() -> void:
	"""Initialize the world statistics section of the UI."""
	var vbox = $MarginContainer/ScrollContainer/VBoxContainer
	if not vbox:
		return
	
	# Check if stats section already exists in scene
	_stats_container = vbox.get_node_or_null("StatsSection")
	if _stats_container:
		_voxel_label = _stats_container.get_node_or_null("VoxelLabel")
		_hull_label = _stats_container.get_node_or_null("HullLabel")
		_poly_label = _stats_container.get_node_or_null("PolyLabel")
		_scene_spawn_label = _stats_container.get_node_or_null("SceneSpawnLabel")
		_scene_spawn_spin = _stats_container.get_node_or_null("SceneSpawnRow/Spin")
		_clear_scenes_button = _stats_container.get_node_or_null("ClearScenesBtn")
	else:
		# Create stats section dynamically
		_create_stats_section(vbox)
	
	# Connect signals
	if _scene_spawn_spin and not _scene_spawn_spin.value_changed.is_connected(_on_scene_spawn_limit_changed):
		_scene_spawn_spin.value_changed.connect(_on_scene_spawn_limit_changed)
	if _clear_scenes_button and not _clear_scenes_button.pressed.is_connected(_on_clear_scenes_pressed):
		_clear_scenes_button.pressed.connect(_on_clear_scenes_pressed)


func _create_stats_section(parent: VBoxContainer) -> void:
	"""Create the world statistics section programmatically."""
	# Separator
	var sep := HSeparator.new()
	sep.name = "StatsSeparator"
	parent.add_child(sep)
	parent.move_child(sep, 2)  # After subtitle
	
	# Stats container
	_stats_container = VBoxContainer.new()
	_stats_container.name = "StatsSection"
	parent.add_child(_stats_container)
	parent.move_child(_stats_container, 3)
	
	# === UI Panel Management Section ===
	_create_ui_panel_section(_stats_container)
	
	# Stats title
	var stats_title := Label.new()
	stats_title.text = "World Statistics"
	stats_title.add_theme_color_override("font_color", Color(0.8, 0.95, 1, 1))
	stats_title.add_theme_font_size_override("font_size", 16)
	_stats_container.add_child(stats_title)
	
	# Voxel count
	_voxel_label = Label.new()
	_voxel_label.name = "VoxelLabel"
	_voxel_label.text = "Voxels: 0 (0 chunks)"
	_voxel_label.add_theme_font_size_override("font_size", 13)
	_stats_container.add_child(_voxel_label)
	
	# Hull count
	_hull_label = Label.new()
	_hull_label.name = "HullLabel"
	_hull_label.text = "Hulls: 0"
	_hull_label.add_theme_font_size_override("font_size", 13)
	_stats_container.add_child(_hull_label)
	
	# Poly count
	_poly_label = Label.new()
	_poly_label.name = "PolyLabel"
	_poly_label.text = "Poly Triangles: 0 (0 points)"
	_poly_label.add_theme_font_size_override("font_size", 13)
	_stats_container.add_child(_poly_label)
	
	# Scene spawn section
	var spawn_sep := HSeparator.new()
	_stats_container.add_child(spawn_sep)
	
	var spawn_title := Label.new()
	spawn_title.text = "Scene Spawning"
	spawn_title.add_theme_color_override("font_color", Color(0.8, 0.95, 1, 1))
	spawn_title.add_theme_font_size_override("font_size", 16)
	_stats_container.add_child(spawn_title)
	
	_scene_spawn_label = Label.new()
	_scene_spawn_label.name = "SceneSpawnLabel"
	_scene_spawn_label.text = "Spawned: 0 / 2"
	_scene_spawn_label.add_theme_font_size_override("font_size", 13)
	_stats_container.add_child(_scene_spawn_label)
	
	# Spawn limit row
	var spawn_row := HBoxContainer.new()
	spawn_row.name = "SceneSpawnRow"
	_stats_container.add_child(spawn_row)
	
	var spawn_limit_label := Label.new()
	spawn_limit_label.text = "Max Spawns:"
	spawn_limit_label.custom_minimum_size = Vector2(100, 0)
	spawn_row.add_child(spawn_limit_label)
	
	_scene_spawn_spin = SpinBox.new()
	_scene_spawn_spin.name = "Spin"
	_scene_spawn_spin.min_value = 0
	_scene_spawn_spin.max_value = 20
	_scene_spawn_spin.step = 1
	_scene_spawn_spin.value = 1  # Default 1 for VR performance
	_scene_spawn_spin.custom_minimum_size = Vector2(80, 0)
	spawn_row.add_child(_scene_spawn_spin)
	
	# Clear button
	_clear_scenes_button = Button.new()
	_clear_scenes_button.name = "ClearScenesBtn"
	_clear_scenes_button.text = "Clear All Spawned"
	_clear_scenes_button.add_theme_color_override("font_color", Color(1, 0.8, 0.8))
	_stats_container.add_child(_clear_scenes_button)


func _create_ui_panel_section(parent: VBoxContainer) -> void:
	"""Create the UI Panel Management section."""
	var ui_sep := HSeparator.new()
	parent.add_child(ui_sep)
	
	var ui_title := Label.new()
	ui_title.text = "UI Panel Management"
	ui_title.add_theme_color_override("font_color", Color(0.8, 0.95, 1, 1))
	ui_title.add_theme_font_size_override("font_size", 16)
	parent.add_child(ui_title)
	
	# Active panels label
	_ui_panel_label = Label.new()
	_ui_panel_label.name = "UIPanelLabel"
	_ui_panel_label.text = "Active Panels: 0 / 3"
	_ui_panel_label.add_theme_font_size_override("font_size", 13)
	parent.add_child(_ui_panel_label)
	
	# Max panels row
	var max_row := HBoxContainer.new()
	max_row.name = "MaxPanelsRow"
	parent.add_child(max_row)
	
	var max_label := Label.new()
	max_label.text = "Max Panels:"
	max_label.custom_minimum_size = Vector2(100, 0)
	max_row.add_child(max_label)
	
	_ui_max_panels_spin = SpinBox.new()
	_ui_max_panels_spin.name = "MaxPanelsSpin"
	_ui_max_panels_spin.min_value = 0
	_ui_max_panels_spin.max_value = 10
	_ui_max_panels_spin.step = 1
	_ui_max_panels_spin.value = 3
	_ui_max_panels_spin.tooltip_text = "Maximum UI panels allowed (0 = unlimited)"
	_ui_max_panels_spin.custom_minimum_size = Vector2(80, 0)
	_ui_max_panels_spin.value_changed.connect(_on_max_panels_changed)
	max_row.add_child(_ui_max_panels_spin)
	
	# Distance culling checkbox
	_ui_distance_culling_check = CheckBox.new()
	_ui_distance_culling_check.name = "DistanceCullingCheck"
	_ui_distance_culling_check.text = "Distance Culling"
	_ui_distance_culling_check.button_pressed = true
	_ui_distance_culling_check.tooltip_text = "Hide panels that are too far from player"
	_ui_distance_culling_check.toggled.connect(_on_distance_culling_toggled)
	parent.add_child(_ui_distance_culling_check)
	
	# Max distance row
	var dist_row := HBoxContainer.new()
	dist_row.name = "MaxDistanceRow"
	parent.add_child(dist_row)
	
	var dist_label := Label.new()
	dist_label.text = "Max Distance:"
	dist_label.custom_minimum_size = Vector2(100, 0)
	dist_row.add_child(dist_label)
	
	_ui_max_distance_spin = SpinBox.new()
	_ui_max_distance_spin.name = "MaxDistanceSpin"
	_ui_max_distance_spin.min_value = 1.0
	_ui_max_distance_spin.max_value = 20.0
	_ui_max_distance_spin.step = 0.5
	_ui_max_distance_spin.value = 5.0
	_ui_max_distance_spin.suffix = "m"
	_ui_max_distance_spin.tooltip_text = "Panels beyond this distance are hidden"
	_ui_max_distance_spin.custom_minimum_size = Vector2(80, 0)
	_ui_max_distance_spin.value_changed.connect(_on_max_distance_changed)
	dist_row.add_child(_ui_max_distance_spin)
	
	# Close all button
	_ui_close_all_button = Button.new()
	_ui_close_all_button.name = "CloseAllPanelsBtn"
	_ui_close_all_button.text = "Close All UI Panels"
	_ui_close_all_button.add_theme_color_override("font_color", Color(1, 0.8, 0.8))
	_ui_close_all_button.pressed.connect(_on_close_all_panels_pressed)
	parent.add_child(_ui_close_all_button)


func _on_max_panels_changed(value: float) -> void:
	var manager := UIPanelManager.find()
	if manager:
		manager.set_max_panels(int(value))
		_update_ui_panel_stats()
		_set_status("Max UI panels set to %d" % int(value), false)
	else:
		_set_status("UIPanelManager not found", true)


func _on_distance_culling_toggled(enabled: bool) -> void:
	var manager := UIPanelManager.find()
	if manager:
		manager.set_distance_culling(enabled)
		_ui_max_distance_spin.editable = enabled
		_update_ui_panel_stats()
		_set_status("Distance culling %s" % ("enabled" if enabled else "disabled"), false)
	else:
		_set_status("UIPanelManager not found", true)


func _on_max_distance_changed(value: float) -> void:
	var manager := UIPanelManager.find()
	if manager:
		manager.set_max_distance(value)
		_update_ui_panel_stats()
		_set_status("Max panel distance set to %.1fm" % value, false)
	else:
		_set_status("UIPanelManager not found", true)


func _on_close_all_panels_pressed() -> void:
	var manager := UIPanelManager.find()
	if manager:
		manager.close_all_panels()
		_update_ui_panel_stats()
		_set_status("Closed all UI panels", false)
	else:
		_set_status("UIPanelManager not found", true)


func _update_ui_panel_stats() -> void:
	"""Update the UI panel statistics display."""
	var manager := UIPanelManager.find()
	if not manager:
		if _ui_panel_label:
			_ui_panel_label.text = "Active Panels: N/A (no manager)"
		return
	
	var stats := manager.get_stats()
	
	if _ui_panel_label:
		var active: int = stats.get("active_panels", 0)
		var max_p: int = stats.get("max_panels", 0)
		var hidden_count: int = stats.get("hidden_by_distance", 0)
		
		var max_str := str(max_p) if max_p > 0 else "∞"
		_ui_panel_label.text = "Active: %d / %s (hidden: %d)" % [active, max_str, hidden_count]
		
		# Color warning if at limit
		if max_p > 0 and active >= max_p:
			_ui_panel_label.add_theme_color_override("font_color", Color(1, 0.65, 0.65))
		else:
			_ui_panel_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	
	# Sync UI controls with manager state
	if _ui_max_panels_spin:
		_ui_max_panels_spin.set_value_no_signal(stats.get("max_panels", 3))
	if _ui_max_distance_spin:
		_ui_max_distance_spin.set_value_no_signal(stats.get("max_distance", 5.0))
	if _ui_distance_culling_check:
		_ui_distance_culling_check.set_pressed_no_signal(stats.get("distance_culling", true))
		_ui_max_distance_spin.editable = stats.get("distance_culling", true)


func _refresh_from_manager() -> void:
	var pool := ToolPoolManager.find()
	var missing := pool == null
	for tool_type in _rows.keys():
		var row: Dictionary = _rows[tool_type]
		var spin: SpinBox = row["spin"]
		var counts: Label = row["counts"]
		if not spin or not counts:
			continue
		if pool:
			spin.editable = true
			spin.value = pool.get_limit(tool_type)
			_update_counts(tool_type)
		else:
			spin.editable = false
			counts.text = "No manager"
	
	# Update scene spawn limit from manager
	if pool and _scene_spawn_spin:
		_scene_spawn_spin.value = pool.get_max_spawned_scenes()
	
	if missing:
		_set_status("ToolPoolManager not found in scene", true)
	else:
		_update_world_stats()


func _on_spin_changed(value: float, tool_type: String) -> void:
	var pool := ToolPoolManager.find()
	if not pool:
		_set_status("Cannot change limit: ToolPoolManager missing", true)
		return
	var new_limit := int(round(value))
	pool.set_limit(tool_type, new_limit)
	_update_counts(tool_type)
	_set_status("%s limit set to %d" % [_rows[tool_type]["label"], new_limit], false)


func _on_scene_spawn_limit_changed(value: float) -> void:
	var pool := ToolPoolManager.find()
	if not pool:
		_set_status("Cannot change limit: ToolPoolManager missing", true)
		return
	var new_limit := int(round(value))
	pool.set_max_spawned_scenes(new_limit)
	_update_world_stats()
	_set_status("Scene spawn limit set to %d" % new_limit, false)


func _on_clear_scenes_pressed() -> void:
	var pool := ToolPoolManager.find()
	if not pool:
		_set_status("Cannot clear: ToolPoolManager missing", true)
		return
	pool.clear_all_spawned_scenes()
	_update_world_stats()
	_set_status("Cleared all spawned scenes", false)


func _update_counts(tool_type: String) -> void:
	var pool := ToolPoolManager.find()
	if not pool:
		return
	var counts := pool.get_counts(tool_type)
	var label: Label = _rows[tool_type]["counts"]
	if not label:
		return
	label.text = "Active %d / Pooled %d (Limit %d)" % [
		counts.get("active", 0),
		counts.get("pooled", 0),
		counts.get("limit", 0),
	]


func _update_world_stats() -> void:
	"""Update the world statistics display."""
	# Update UI panel stats
	_update_ui_panel_stats()
	
	var pool := ToolPoolManager.find()
	if not pool:
		return
	
	var stats := pool.get_world_stats()
	
	if _voxel_label:
		var voxels: int = stats.get("voxels", 0)
		var max_voxels: int = stats.get("max_voxels", 500)
		var chunks: int = stats.get("chunks", 0)
		_voxel_label.text = "Voxels: %d / %d (%d chunks)" % [voxels, max_voxels, chunks]
		_voxel_label.add_theme_color_override("font_color", Color(1, 0.65, 0.65) if voxels >= max_voxels else Color(0.85, 0.85, 0.85))
	
	if _hull_label:
		var hulls: int = stats.get("hulls", 0)
		var max_hulls: int = stats.get("max_hulls", 10)
		_hull_label.text = "Hulls: %d / %d" % [hulls, max_hulls]
		_hull_label.add_theme_color_override("font_color", Color(1, 0.65, 0.65) if hulls >= max_hulls else Color(0.85, 0.85, 0.85))
	
	if _poly_label:
		var polys: int = stats.get("polys", 0)
		var max_polys: int = stats.get("max_polys", 50)
		var points: int = stats.get("poly_points", 0)
		_poly_label.text = "Poly Triangles: %d / %d (%d points)" % [polys, max_polys, points]
		_poly_label.add_theme_color_override("font_color", Color(1, 0.65, 0.65) if polys >= max_polys else Color(0.85, 0.85, 0.85))
	
	if _scene_spawn_label:
		var spawned: int = stats.get("spawned_scenes", 0)
		var max_spawned: int = stats.get("max_spawned_scenes", 1)
		_scene_spawn_label.text = "Spawned: %d / %d" % [spawned, max_spawned]
		_scene_spawn_label.add_theme_color_override("font_color", Color(1, 0.65, 0.65) if spawned >= max_spawned else Color(0.85, 0.85, 0.85))


func _set_status(text: String, is_error: bool) -> void:
	if not _status_label:
		return
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", Color(1, 0.65, 0.65) if is_error else Color(0.75, 1, 0.75))
