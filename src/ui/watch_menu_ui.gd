extends Control

@onready var tab = $TabContainer
@onready var vbox_panels = $TabContainer/PanelsScroll/PanelsVBox
@onready var vbox_general = $TabContainer/GeneralScroll/GeneralVBox
@onready var vbox_history = $TabContainer/HistoryScroll/HistoryVBox
@onready var vbox_shapes = $TabContainer/ShapesScroll/ShapesVBox

var movement_component: PlayerMovementComponent
var player_body: RigidBody3D
var xr_player: Node = null
var passthrough_check: CheckBox
var passthrough_status: Label

var _xr_interface: XRInterface
var _world_environment: WorldEnvironment
var _world_env_snapshot: Dictionary = {}
var _root_viewport: Viewport
var _viewport_transparent_default: bool = false

const MAIN_SCENE_PATH := "res://src/levels/MainScene.tscn"


func _ready() -> void:
	print("WatchMenuUI: _ready() called")
	call_deferred("_find_player_and_setup")

func _find_player_and_setup() -> void:
	print("WatchMenuUI: _find_player_and_setup() called")
	var player = get_tree().get_first_node_in_group("xr_player")
	print("WatchMenuUI: Found player: ", player)
	
	if player:
		movement_component = player.get_node_or_null("PlayerMovementComponent")
		print("WatchMenuUI: Found movement_component: ", movement_component)
		xr_player = player
		player_body = player.get_node_or_null("PlayerBody") as RigidBody3D
		print("WatchMenuUI: Found player_body: ", player_body)
	
	_xr_interface = XRServer.find_interface("OpenXR")
	_root_viewport = get_tree().root
	if _root_viewport:
		_viewport_transparent_default = _root_viewport.transparent_bg
	_find_world_environment()
	
	if movement_component:
		print("WatchMenuUI: Calling _setup_ui()")
		_setup_ui()
	else:
		print("WatchMenuUI: ERROR - Could not find PlayerMovementComponent")
		print("WatchMenuUI: Available children of player: ")
		if player:
			for child in player.get_children():
				print("  - ", child.name, " (", child.get_class(), ")")

func _setup_ui() -> void:
	print("WatchMenuUI: _setup_ui() starting")
	
	if not movement_component:
		print("WatchMenuUI: No movement component, keeping default UI")
		return
	
	print("WatchMenuUI: Movement component found, populating UI with settings")
	
	for c in vbox_panels.get_children():
		c.queue_free()
	for c in vbox_general.get_children():
		c.queue_free()
	for c in vbox_history.get_children():
		c.queue_free()
	for c in vbox_shapes.get_children():
		c.queue_free()
	
	var all_vboxes = [vbox_panels, vbox_general, vbox_history, vbox_shapes]
	for vbox in all_vboxes:
		if vbox:
			vbox.visible = true
			var parent: Node = vbox.get_parent()
			if parent:
				parent.visible = true
			vbox.add_theme_constant_override("separation", 10)
	
	_setup_panels_tab()
	_setup_general_tab()
	_setup_history_tab()
	_setup_shapes_tab()

	if tab and tab.get_child_count() >= 4:
		tab.set_tab_title(0, "Panels")
		tab.set_tab_title(1, "General")
		tab.set_tab_title(2, "History")
		tab.set_tab_title(3, "Shapes")

func _setup_panels_tab() -> void:
	var title_label = Label.new()
	title_label.text = "Quick Panel Access"
	title_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 20)
	vbox_panels.add_child(title_label)
	
	_add_separator(vbox_panels)

	var quick_panels := [
		{"label": "⚡ Performance", "node": "PerformancePanelViewport3D"},
		{"label": "🎮 Movement", "node": "MovementSettingsViewport3D2"},
		{"label": "⌨️ Keyboard", "node": "KeyboardFullViewport3D"},
		{"label": "📁 File System", "node": "FileSystemViewport3D"},
		{"label": "🌳 Scene Hierarchy", "node": "SceneHierarchyViewport3D"},
		{"label": "🔍 Node Inspector", "node": "NodeInspectorViewport3D"},
		{"label": "📝 Script Editor", "node": "ScriptEditorViewport3D"},
		{"label": "🐛 Debug Console", "node": "DebugConsoleViewport3D"},
		{"label": "🔀 Git Tracker", "node": "GitViewport3D"},
		{"label": "🌐 Multiplayer", "node": "UnifiedRoomViewport3D"},
		{"label": "🎤 LiveKit", "node": "LiveKitViewport3D"},
		{"label": "🎨 Color Picker", "node": "ColorPickerViewport3D"},
		{"label": "🧱 Block Library", "node": "BlockLibraryViewport3D"},
		{"label": "🌍 Web Browser", "node": "WebviewViewport3D"},
		{"label": "📦 Asset Library", "node": "AssetLibraryViewport3D"},
	]
	
	for entry in quick_panels:
		var btn := Button.new()
		btn.text = entry.get("label", "")
		btn.custom_minimum_size = Vector2(0, 45)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 18)
		var target_node: String = entry.get("node", "")
		btn.pressed.connect(func(node_name := target_node): _move_ui_node_in_front(node_name))
		vbox_panels.add_child(btn)

func _move_ui_node_in_front(node_name: String) -> void:
	var manager := UIPanelManager.find()
	if manager:
		manager.open_panel(node_name, true)
	else:
		_create_panel_manager_and_open(node_name)

func _create_panel_manager_and_open(node_name: String) -> void:
	var scene_root: Node = get_tree().current_scene
	if not scene_root:
		var gm: Node = get_tree().root.get_node_or_null("GameManager")
		if gm and gm.has_method("get") and gm.get("current_world"):
			scene_root = gm.get("current_world")
	
	if not scene_root:
		print("WatchMenuUI: Cannot create UIPanelManager - no scene root")
		return
	
	var existing := scene_root.get_node_or_null("UIPanelManager")
	if existing and existing is UIPanelManager:
		(existing as UIPanelManager).open_panel(node_name, true)
		return
	
	var manager := UIPanelManager.new()
	manager.name = "UIPanelManager"
	scene_root.add_child(manager)
	print("WatchMenuUI: Created UIPanelManager")
	manager.open_panel(node_name, true)

func _setup_general_tab() -> void:
	# Player Scale Section
	var scale_section = Label.new()
	scale_section.text = "Player Scale"
	scale_section.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	scale_section.add_theme_font_size_override("font_size", 18)
	vbox_general.add_child(scale_section)
	
	var scale_hbox = HBoxContainer.new()
	scale_hbox.add_theme_constant_override("separation", 10)
	
	var scale_label = Label.new()
	var initial_scale = 1.0
	if player_body:
		initial_scale = player_body.scale.x
	scale_label.text = "%.2fx" % initial_scale
	scale_label.custom_minimum_size = Vector2(70, 0)
	scale_label.add_theme_font_size_override("font_size", 18)
	scale_hbox.add_child(scale_label)
	
	var decrease_btn = Button.new()
	decrease_btn.text = "-"
	decrease_btn.custom_minimum_size = Vector2(50, 40)
	decrease_btn.add_theme_font_size_override("font_size", 20)
	decrease_btn.pressed.connect(func(): _on_apply_scale_change(-1, scale_label))
	scale_hbox.add_child(decrease_btn)
	
	var increase_btn = Button.new()
	increase_btn.text = "+"
	increase_btn.custom_minimum_size = Vector2(50, 40)
	increase_btn.add_theme_font_size_override("font_size", 20)
	increase_btn.pressed.connect(func(): _on_apply_scale_change(1, scale_label))
	scale_hbox.add_child(increase_btn)
	
	var step_label = Label.new()
	step_label.text = "Step: %d%%" % scale_step_percent
	step_label.custom_minimum_size = Vector2(90, 0)
	step_label.add_theme_font_size_override("font_size", 16)
	scale_hbox.add_child(step_label)
	
	var step_dec_btn = Button.new()
	step_dec_btn.text = "◀"
	step_dec_btn.custom_minimum_size = Vector2(40, 40)
	step_dec_btn.add_theme_font_size_override("font_size", 16)
	step_dec_btn.pressed.connect(func(): _on_scale_step_changed(-1, step_label))
	scale_hbox.add_child(step_dec_btn)
	
	var step_inc_btn = Button.new()
	step_inc_btn.text = "▶"
	step_inc_btn.custom_minimum_size = Vector2(40, 40)
	step_inc_btn.add_theme_font_size_override("font_size", 16)
	step_inc_btn.pressed.connect(func(): _on_scale_step_changed(1, step_label))
	scale_hbox.add_child(step_inc_btn)
	
	vbox_general.add_child(scale_hbox)
	_add_separator(vbox_general)

	# Actions Row
	var actions_hbox = HBoxContainer.new()
	actions_hbox.add_theme_constant_override("separation", 8)
	
	var respawn_btn = Button.new()
	respawn_btn.text = "🔄 Respawn"
	respawn_btn.custom_minimum_size = Vector2(0, 45)
	respawn_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	respawn_btn.add_theme_font_size_override("font_size", 18)
	respawn_btn.pressed.connect(_on_respawn_pressed)
	actions_hbox.add_child(respawn_btn)
	
	var return_main_btn = Button.new()
	return_main_btn.text = "🏠 Main Scene"
	return_main_btn.custom_minimum_size = Vector2(0, 45)
	return_main_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return_main_btn.add_theme_font_size_override("font_size", 18)
	return_main_btn.pressed.connect(_on_return_to_main_scene_pressed)
	actions_hbox.add_child(return_main_btn)
	
	vbox_general.add_child(actions_hbox)
	_add_separator(vbox_general)
	
	# Environment Section
	var env_label = Label.new()
	env_label.text = "Environment"
	env_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	env_label.add_theme_font_size_override("font_size", 18)
	vbox_general.add_child(env_label)
	
	passthrough_check = CheckBox.new()
	passthrough_check.text = "Passthrough (Quest 3)"
	passthrough_check.add_theme_font_size_override("font_size", 16)
	passthrough_check.tooltip_text = "Uses OpenXR alpha-blend to reveal passthrough video."
	passthrough_check.toggled.connect(func(pressed): _on_passthrough_toggled(pressed))
	vbox_general.add_child(passthrough_check)
	
	passthrough_status = Label.new()
	passthrough_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	passthrough_status.text = "Status pending..."
	passthrough_status.add_theme_font_size_override("font_size", 14)
	passthrough_status.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox_general.add_child(passthrough_status)
	_update_passthrough_ui_state()

	_add_separator(vbox_general)
	
	# Render Mode Section
	var render_label = Label.new()
	render_label.text = "Render Mode"
	render_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	render_label.add_theme_font_size_override("font_size", 18)
	vbox_general.add_child(render_label)
	
	# Render modes in 2 rows
	var render_row1 = HBoxContainer.new()
	render_row1.add_theme_constant_override("separation", 6)
	
	var modes_row1 = [
		{"label": "Normal", "mode": Viewport.DEBUG_DRAW_DISABLED},
		{"label": "Wireframe", "mode": Viewport.DEBUG_DRAW_WIREFRAME},
		{"label": "Overdraw", "mode": Viewport.DEBUG_DRAW_OVERDRAW},
	]
	
	for entry in modes_row1:
		var btn = Button.new()
		btn.text = entry["label"]
		btn.custom_minimum_size = Vector2(0, 42)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(func(): _set_render_mode(entry["mode"]))
		render_row1.add_child(btn)
	
	vbox_general.add_child(render_row1)
	
	var render_row2 = HBoxContainer.new()
	render_row2.add_theme_constant_override("separation", 6)
	
	var modes_row2 = [
		{"label": "Unshaded", "mode": Viewport.DEBUG_DRAW_UNSHADED},
		{"label": "Collision", "mode": -1}
	]
	
	for entry in modes_row2:
		var btn = Button.new()
		btn.text = entry["label"]
		btn.custom_minimum_size = Vector2(0, 42)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(func(): _set_render_mode(entry["mode"]))
		render_row2.add_child(btn)
	
	vbox_general.add_child(render_row2)

func _setup_history_tab() -> void:
	_refresh_history_list()

func _setup_shapes_tab() -> void:
	var title_label = Label.new()
	title_label.text = "Spawn Shapes"
	title_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 20)
	vbox_shapes.add_child(title_label)
	
	_add_separator(vbox_shapes)
	
	# Row 1: Cube, Sphere, Cylinder
	var row1 = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	
	var shapes_row1 = [
		{"label": "� Cube", "shape": "cube"},
		{"label": "⚪ Sphere", "shape": "sphere"},
		{"label": "🔺 Cylinder", "shape": "cylinder"},
	]
	
	for entry in shapes_row1:
		var btn = Button.new()
		btn.text = entry["label"]
		btn.custom_minimum_size = Vector2(0, 50)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 18)
		var shape_type: String = entry["shape"]
		btn.pressed.connect(func(): _spawn_shape(shape_type))
		row1.add_child(btn)
	
	vbox_shapes.add_child(row1)
	
	# Row 2: Cone, Capsule, Prism
	var row2 = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	
	var shapes_row2 = [
		{"label": "🔻 Cone", "shape": "cone"},
		{"label": "💊 Capsule", "shape": "capsule"},
		{"label": "📐 Prism", "shape": "prism"},
	]
	
	for entry in shapes_row2:
		var btn = Button.new()
		btn.text = entry["label"]
		btn.custom_minimum_size = Vector2(0, 50)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 18)
		var shape_type: String = entry["shape"]
		btn.pressed.connect(func(): _spawn_shape(shape_type))
		row2.add_child(btn)
	
	vbox_shapes.add_child(row2)
	
	_add_separator(vbox_shapes)
	
	var info_label = Label.new()
	info_label.text = "Shapes spawn 0.8m in front of camera"
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	info_label.add_theme_font_size_override("font_size", 14)
	vbox_shapes.add_child(info_label)

func _spawn_shape(shape_type: String) -> void:
	# Try to get camera - works for both VR and desktop
	var camera: Camera3D = null
	
	# First, try to find camera from player
	if xr_player:
		# Try XRCamera3D (VR mode)
		camera = xr_player.get_node_or_null("XRCamera3D")
		
		# If not found, try regular Camera3D (desktop mode)
		if not camera:
			camera = xr_player.get_node_or_null("Camera3D")
		
		# Try to find any Camera3D in the player hierarchy
		if not camera:
			for child in xr_player.get_children():
				if child is Camera3D:
					camera = child
					break
				# Check nested children
				for nested_child in child.get_children():
					if nested_child is Camera3D:
						camera = nested_child
						break
				if camera:
					break
	
	# Last resort: use the current viewport camera
	if not camera:
		camera = get_viewport().get_camera_3d()
	
	if not camera:
		print("WatchMenuUI: Cannot spawn shape - no camera found")
		return
	
	# Wait for camera to be ready if needed
	if not camera.is_inside_tree():
		print("WatchMenuUI: Camera not in tree yet, deferring spawn...")
		call_deferred("_spawn_shape_deferred", shape_type, camera)
		return
	
	_spawn_shape_deferred(shape_type, camera)

func _spawn_shape_deferred(shape_type: String, camera: Camera3D) -> void:
	# Ensure camera is in tree
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		print("WatchMenuUI: Camera invalid or not in tree, cannot spawn")
		return
	
	# Default spawn position
	var spawn_pos = camera.global_position + camera.global_transform.basis.z * -0.8
	
	# Try to find the hand that's NOT holding the watch menu (the free hand)
	if xr_player:
		var left_controller = xr_player.get_node_or_null("PlayerBody/XROrigin3D/LeftController")
		var right_controller = xr_player.get_node_or_null("PlayerBody/XROrigin3D/RightController")
		
		# Check which controller is pressing the button (that's the one interacting with the watch)
		var left_trigger = left_controller.get_float("trigger") if left_controller else 0.0
		var right_trigger = right_controller.get_float("trigger") if right_controller else 0.0
		
		# The hand NOT pressing trigger is the free hand - spawn there
		if left_trigger > 0.5 and right_controller:
			# Left hand is using watch, spawn at right hand
			spawn_pos = right_controller.global_position
			print("WatchMenuUI: Spawning at right hand (free hand)")
		elif right_trigger > 0.5 and left_controller:
			# Right hand is using watch, spawn at left hand
			spawn_pos = left_controller.global_position
			print("WatchMenuUI: Spawning at left hand (free hand)")
		elif left_controller:
			# Default to left hand if we can't determine
			spawn_pos = left_controller.global_position
			print("WatchMenuUI: Spawning at left hand (default)")
	
	print("WatchMenuUI: Spawn position: ", spawn_pos)
	
	var rigid_body = RigidBody3D.new()
	rigid_body.global_position = spawn_pos
	
	var mesh_instance = MeshInstance3D.new()
	var mesh: Mesh
	
	match shape_type:
		"cube":
			mesh = BoxMesh.new()
			mesh.size = Vector3(0.5, 0.5, 0.5)
		"sphere":
			mesh = SphereMesh.new()
			mesh.radius = 0.25
			mesh.height = 0.5
		"cylinder":
			mesh = CylinderMesh.new()
			mesh.top_radius = 0.25
			mesh.bottom_radius = 0.25
			mesh.height = 0.5
		"cone":
			mesh = CylinderMesh.new()
			mesh.top_radius = 0.0
			mesh.bottom_radius = 0.25
			mesh.height = 0.5
		"capsule":
			mesh = CapsuleMesh.new()
			mesh.radius = 0.2
			mesh.height = 0.6
		"prism":
			mesh = PrismMesh.new()
			mesh.size = Vector3(0.5, 0.5, 0.5)
		_:
			mesh = BoxMesh.new()
	
	mesh_instance.mesh = mesh
	
	# Disable shadows on the mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	rigid_body.add_child(mesh_instance)
	
	var collision_shape = CollisionShape3D.new()
	var shape: Shape3D
	
	match shape_type:
		"cube":
			shape = BoxShape3D.new()
			shape.size = Vector3(0.5, 0.5, 0.5)
		"prism":
			# Use ConvexPolygonShape3D for accurate prism collision
			# Create it from the mesh directly
			var prism_mesh = mesh as PrismMesh
			var arrays = prism_mesh.get_mesh_arrays()
			if arrays and arrays.size() > 0:
				var vertices = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
				if vertices and vertices.size() > 0:
					var convex_shape = ConvexPolygonShape3D.new()
					convex_shape.points = vertices
					shape = convex_shape
				else:
					# Fallback to box if mesh data not available
					shape = BoxShape3D.new()
					shape.size = Vector3(0.5, 0.5, 0.5)
			else:
				# Fallback to box if mesh data not available
				shape = BoxShape3D.new()
				shape.size = Vector3(0.5, 0.5, 0.5)
		"sphere":
			shape = SphereShape3D.new()
			shape.radius = 0.25
		"cylinder", "cone":
			shape = CylinderShape3D.new()
			shape.radius = 0.25
			shape.height = 0.5
		"capsule":
			shape = CapsuleShape3D.new()
			shape.radius = 0.2
			shape.height = 0.6
		_:
			shape = BoxShape3D.new()
	
	collision_shape.shape = shape
	rigid_body.add_child(collision_shape)
	
	# Set collision layers for selection system
	# Layer 8 (bit 7) = Spawned shapes that can be selected
	rigid_body.collision_layer = 128  # Layer 8
	rigid_body.collision_mask = 1     # Collide with world (layer 1)
	
	# Disable gravity - shapes should float
	rigid_body.gravity_scale = 0.0
	
	# Add to a group for easy identification
	rigid_body.add_to_group("selectable_shapes")
	
	# Give it a name for debugging
	rigid_body.name = "Spawned_" + shape_type.capitalize() + "_" + str(Time.get_ticks_msec())
	
	get_tree().current_scene.add_child(rigid_body)
	
	print("WatchMenuUI: Spawned ", shape_type, " at ", spawn_pos, " with name ", rigid_body.name, " on layer ", rigid_body.collision_layer)

func _set_render_mode(mode: int) -> void:
	if _root_viewport:
		if mode == -1:
			_root_viewport.debug_draw = Viewport.DEBUG_DRAW_DISABLED
			get_tree().debug_collisions_hint = true
		else:
			_root_viewport.debug_draw = mode as Viewport.DebugDraw
			get_tree().debug_collisions_hint = false

func _add_separator(parent: VBoxContainer) -> void:
	var separator = HSeparator.new()
	separator.custom_minimum_size = Vector2(0, 4)
	parent.add_child(separator)

var scale_step_percent: int = 5

func _on_scale_step_changed(change: int, label: Label) -> void:
	scale_step_percent = clampi(scale_step_percent + change, 1, 25)
	label.text = "Step: %d%%" % scale_step_percent

func _on_apply_scale_change(delta_sign: int, label: Label) -> void:
	if not player_body:
		return
		
	var current_scale = player_body.scale.x
	var change_amount = (scale_step_percent / 100.0) * delta_sign
	var new_scale = clampf(current_scale + change_amount, 0.25, 3.0)
	
	if xr_player and xr_player.has_method("set_player_scale"):
		xr_player.set_player_scale(new_scale)
	else:
		player_body.scale = Vector3(new_scale, new_scale, new_scale)
		if movement_component and movement_component.has_method("set_manual_player_scale"):
			movement_component.set_manual_player_scale(new_scale)
	
	label.text = "Scale: %.2fx" % new_scale
	
	MovementSettingsPanel.record_toggle(
		"Player Scale",
		"%.2fx" % current_scale,
		"%.2fx" % new_scale,
		func(): _on_apply_scale_change(-delta_sign, label)
	)

func _on_respawn_pressed() -> void:
	if movement_component:
		movement_component.respawn(movement_component.hard_respawn_resets_settings)

func _on_return_to_main_scene_pressed() -> void:
	var target_scene := MAIN_SCENE_PATH
	var player_state := {
		"use_spawn_point": true,
		"spawn_point": "SpawnPoint",
	}
	if GameManager and GameManager.has_method("change_scene_with_player"):
		GameManager.call_deferred("change_scene_with_player", target_scene, player_state)
	else:
		get_tree().call_deferred("change_scene_to_file", target_scene)

func _on_passthrough_toggled(enabled: bool) -> void:
	var old_val = _current_blend_mode() == XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	_apply_passthrough_enabled(enabled)
	_update_passthrough_ui_state()
	MovementSettingsPanel.record_toggle(
		"Skybox Passthrough",
		old_val,
		enabled,
		func(): _on_passthrough_toggled(old_val)
	)

func _find_world_environment() -> void:
	if _world_environment:
		return
	var root := get_tree().root
	if not root:
		return
	var env_node := root.find_child("WorldEnvironment", true, false)
	if env_node and env_node is WorldEnvironment:
		_world_environment = env_node
		if _world_environment.environment and _world_env_snapshot.is_empty():
			var env := _world_environment.environment
			_world_env_snapshot = {
				"background_mode": env.background_mode,
				"background_color": env.background_color,
				"sky": env.sky,
			}

func _supports_alpha_passthrough() -> bool:
	if not _xr_interface:
		return false
	if _xr_interface.has_method("get_supported_environment_blend_modes"):
		var supported: PackedInt32Array = _xr_interface.get_supported_environment_blend_modes()
		return XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in supported
	return true

func _current_blend_mode() -> int:
	if not _xr_interface:
		return -1
	if _xr_interface.has_method("get_environment_blend_mode"):
		return _xr_interface.get_environment_blend_mode()
	return _xr_interface.environment_blend_mode

func _set_environment_blend_mode(mode: int) -> void:
	if not _xr_interface:
		return
	if _xr_interface.has_method("set_environment_blend_mode"):
		_xr_interface.set_environment_blend_mode(mode)
	else:
		_xr_interface.environment_blend_mode = mode as XRInterface.EnvironmentBlendMode

func _apply_passthrough_enabled(enabled: bool) -> void:
	if not _xr_interface:
		_update_passthrough_status("OpenXR not available")
		if passthrough_check:
			passthrough_check.button_pressed = false
		return
	if enabled and not _supports_alpha_passthrough():
		_update_passthrough_status("Alpha blend not supported by runtime")
		if passthrough_check:
			passthrough_check.button_pressed = false
		return
	
	var target_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND if enabled else XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	_set_environment_blend_mode(target_mode)
	
	if _root_viewport:
		_root_viewport.transparent_bg = true if enabled else _viewport_transparent_default
	
	if _world_environment and _world_environment.environment:
		var env := _world_environment.environment
		if _world_env_snapshot.is_empty():
			_world_env_snapshot = {
				"background_mode": env.background_mode,
				"background_color": env.background_color,
				"sky": env.sky,
			}
		if enabled:
			env.background_mode = Environment.BG_CLEAR_COLOR
			env.background_color = Color(0, 0, 0, 0)
		else:
			env.background_mode = _world_env_snapshot.get("background_mode", env.background_mode)
			env.background_color = _world_env_snapshot.get("background_color", env.background_color)
			env.sky = _world_env_snapshot.get("sky", env.sky)

func _update_passthrough_status(text: String) -> void:
	if passthrough_status:
		passthrough_status.text = text

func _update_passthrough_ui_state() -> void:
	var xr_ready := _xr_interface and _xr_interface.is_initialized()
	var supported := _supports_alpha_passthrough()
	if passthrough_check:
		passthrough_check.disabled = not xr_ready or not supported
		if not xr_ready:
			passthrough_check.tooltip_text = "Passthrough requires OpenXR to be running."
		elif not supported:
			passthrough_check.tooltip_text = "Runtime does not support alpha blend passthrough."
		else:
			passthrough_check.tooltip_text = "Uses OpenXR alpha-blend to reveal passthrough video. Only supported on devices like Quest 3."
		passthrough_check.button_pressed = xr_ready and supported and _current_blend_mode() == XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	
	if not xr_ready:
		_update_passthrough_status("VR session not active")
	elif not supported:
		_update_passthrough_status("Passthrough not supported by runtime")
	elif _current_blend_mode() == XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND:
		_update_passthrough_status("Passthrough ON (skybox hidden)")
	else:
		_update_passthrough_status("Passthrough OFF (skybox visible)")

func _refresh_history_list() -> void:
	if not vbox_history:
		return
	
	for c in vbox_history.get_children():
		c.queue_free()
	
	var title_label = Label.new()
	title_label.text = "Recently Changed Settings"
	title_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox_history.add_child(title_label)
	
	_add_separator(vbox_history)
	
	var toggles := MovementSettingsPanel.get_recent_toggles()
	
	if toggles.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No recent changes"
		empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox_history.add_child(empty_label)
		return
	
	for i in toggles.size():
		var entry: Dictionary = toggles[i]
		_create_history_entry_ui(i, entry)

func _create_history_entry_ui(index: int, entry: Dictionary) -> void:
	var container = HBoxContainer.new()
	container.add_theme_constant_override("separation", 8)
	
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var name_label = Label.new()
	name_label.text = entry.get("setting_name", "Unknown")
	name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	info_vbox.add_child(name_label)
	
	var value_label = Label.new()
	var old_val = entry.get("old_value", "?")
	var new_val = entry.get("new_value", "?")
	value_label.text = "%s → %s" % [_format_value(old_val), _format_value(new_val)]
	value_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	value_label.add_theme_font_size_override("font_size", 12)
	info_vbox.add_child(value_label)
	
	container.add_child(info_vbox)
	
	var revert_btn = Button.new()
	revert_btn.text = "↩ Revert"
	revert_btn.custom_minimum_size = Vector2(80, 35)
	revert_btn.pressed.connect(func(): _on_revert_pressed(index))
	container.add_child(revert_btn)
	
	vbox_history.add_child(container)

func _format_value(val) -> String:
	if val is bool:
		return "ON" if val else "OFF"
	elif val is int:
		if val == 0:
			return "Snap"
		elif val == 1:
			return "Smooth"
		return str(val)
	elif val is float:
		return "%.2f" % val
	else:
		return str(val)

func _on_revert_pressed(index: int) -> void:
	MovementSettingsPanel.revert_toggle(index)
	_refresh_history_list()
