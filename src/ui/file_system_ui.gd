extends PanelContainer
class_name FileSystemUI

## FileSystemUI - Displays project files in a tree structure
## Works like Godot's FileSystem dock for VR browsing

signal file_selected(path: String)
signal folder_selected(path: String)
signal file_double_clicked(path: String)
signal close_requested

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleRow/TitleLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/TitleRow/CloseButton
@onready var folder_toggle_row: HBoxContainer = $MarginContainer/VBoxContainer/FolderToggleRow
@onready var res_button: Button = $MarginContainer/VBoxContainer/FolderToggleRow/ResButton
@onready var user_button: Button = $MarginContainer/VBoxContainer/FolderToggleRow/UserButton
@onready var tree: Tree = $MarginContainer/VBoxContainer/Tree
@onready var load_button: Button = $MarginContainer/VBoxContainer/ButtonRow/LoadButton
@onready var spawn_button: Button = $MarginContainer/VBoxContainer/ButtonRow/SpawnButton

var _root_path: String = "res://"
var _tree_root: TreeItem = null
var _context_menu: PopupMenu = null
var _context_target_path: String = ""

# File type icons (emoji-based for simplicity)
const ICONS = {
	"folder": "📁",
	"folder_open": "📂",
	"gd": "📜",
	"tscn": "🎬",
	"tres": "📦",
	"png": "🖼️",
	"jpg": "🖼️",
	"wav": "🔊",
	"ogg": "🔊",
	"mp3": "🔊",
	"ttf": "🔤",
	"otf": "🔤",
	"md": "📝",
	"txt": "📝",
	"json": "📋",
	"cfg": "⚙️",
	"import": "📥",
	"default": "📄"
}

# Folders to hide
const HIDDEN_FOLDERS = [".git", ".godot", "android/build", ".import"]

# Static instance
static var instance: FileSystemUI = null

# Guard flag to prevent infinite recursion
var _processing_selection: bool = false

# Spawn placement tuning
@export var spawn_forward_distance: float = 2.5
@export var spawn_height_offset: float = 0.6


func _ready() -> void:
	instance = self
	_setup_folder_toggle()
	_setup_tree()
	_setup_buttons()
	_setup_context_menu()
	# Delay the scan to ensure the tree is ready
	call_deferred("_scan_filesystem")
	
	if close_button:
		close_button.pressed.connect(func(): close_requested.emit())


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if instance == self:
			instance = null


func _setup_folder_toggle() -> void:
	# Create toggle row if not in scene
	if not folder_toggle_row:
		folder_toggle_row = HBoxContainer.new()
		folder_toggle_row.name = "FolderToggleRow"
		var vbox = $MarginContainer/VBoxContainer
		if vbox:
			vbox.add_child(folder_toggle_row)
			vbox.move_child(folder_toggle_row, 1)  # After title
		
		res_button = Button.new()
		res_button.name = "ResButton"
		res_button.text = "📁 res://"
		res_button.toggle_mode = true
		res_button.button_pressed = true
		res_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		folder_toggle_row.add_child(res_button)
		
		user_button = Button.new()
		user_button.name = "UserButton"
		user_button.text = "📂 user://"
		user_button.toggle_mode = true
		user_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		folder_toggle_row.add_child(user_button)
	
	if res_button and not res_button.pressed.is_connected(_on_res_button_pressed):
		res_button.pressed.connect(_on_res_button_pressed)
	if user_button and not user_button.pressed.is_connected(_on_user_button_pressed):
		user_button.pressed.connect(_on_user_button_pressed)


func _on_res_button_pressed() -> void:
	if _root_path != "res://":
		_root_path = "res://"
		if res_button:
			res_button.button_pressed = true
		if user_button:
			user_button.button_pressed = false
		_scan_filesystem()


func _on_user_button_pressed() -> void:
	if _root_path != "user://":
		_root_path = "user://"
		if res_button:
			res_button.button_pressed = false
		if user_button:
			user_button.button_pressed = true
		_scan_filesystem()


func _setup_tree() -> void:
	if not tree:
		# Create tree if not in scene
		tree = Tree.new()
		tree.name = "Tree"
		tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var vbox = $MarginContainer/VBoxContainer
		if vbox:
			vbox.add_child(tree)
	
	tree.hide_root = false
	tree.allow_reselect = true
	tree.item_selected.connect(_on_item_selected)
	tree.item_activated.connect(_on_item_activated)
	if not tree.gui_input.is_connected(_on_tree_gui_input):
		tree.gui_input.connect(_on_tree_gui_input)


func _setup_context_menu() -> void:
	if _context_menu:
		return
	_context_menu = PopupMenu.new()
	_context_menu.name = "ContextMenu"
	add_child(_context_menu)
	_context_menu.add_item("Load Scene", 0)
	_context_menu.add_item("Spawn Scene In World", 1)
	_context_menu.id_pressed.connect(_on_context_menu_item_selected)


func _setup_buttons() -> void:
	if load_button and not load_button.pressed.is_connected(_on_load_button_pressed):
		load_button.pressed.connect(_on_load_button_pressed)
	if spawn_button and not spawn_button.pressed.is_connected(_on_spawn_button_pressed):
		spawn_button.pressed.connect(_on_spawn_button_pressed)


func _scan_filesystem() -> void:
	if not tree:
		return
	
	tree.clear()
	_tree_root = tree.create_item()
	_tree_root.set_text(0, "📂 " + _root_path)
	_tree_root.set_metadata(0, _root_path)
	
	_scan_directory(_root_path, _tree_root)
	
	# Collapse all by default, expand root
	_tree_root.set_collapsed(false)


func _scan_directory(path: String, parent_item: TreeItem) -> void:
	var dir = DirAccess.open(path)
	if not dir:
		push_warning("FileSystemUI: Cannot open directory: ", path)
		return
	
	var folders: Array[String] = []
	var files: Array[String] = []
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue
		
		var full_path = path.path_join(file_name)
		
		# Skip hidden folders
		var skip = false
		for hidden_folder in HIDDEN_FOLDERS:
			if full_path.contains(hidden_folder):
				skip = true
				break
		
		if not skip:
			if dir.current_is_dir():
				folders.append(file_name)
			else:
				# Skip .import files
				if not file_name.ends_with(".import"):
					files.append(file_name)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	
	# Sort alphabetically
	folders.sort()
	files.sort()
	
	# Add folders first
	for folder_name in folders:
		var folder_path = path.path_join(folder_name)
		var folder_item = tree.create_item(parent_item)
		folder_item.set_text(0, ICONS["folder"] + " " + folder_name)
		folder_item.set_metadata(0, folder_path)
		folder_item.set_collapsed(true)
		
		# Recursively scan subfolders
		_scan_directory(folder_path, folder_item)
	
	# Add files
	for fname in files:
		var file_path = path.path_join(fname)
		var file_item = tree.create_item(parent_item)
		var icon = _get_file_icon(fname)
		file_item.set_text(0, icon + " " + fname)
		file_item.set_metadata(0, file_path)


func _get_file_icon(file_name: String) -> String:
	var ext = file_name.get_extension().to_lower()
	return ICONS.get(ext, ICONS["default"])


func _on_item_selected() -> void:
	# Guard against infinite recursion when set_collapsed triggers item_selected
	if _processing_selection:
		return
	
	var selected = tree.get_selected()
	if not selected:
		return
	
	var path: String = selected.get_metadata(0)
	
	if DirAccess.dir_exists_absolute(path):
		folder_selected.emit(path)
		# Toggle folder collapsed state (with guard to prevent recursion)
		_processing_selection = true
		selected.set_collapsed(not selected.is_collapsed())
		# Update icon
		var folder_name = path.get_file()
		if folder_name.is_empty():
			folder_name = "res://"
		if selected.is_collapsed():
			selected.set_text(0, ICONS["folder"] + " " + folder_name)
		else:
			selected.set_text(0, ICONS["folder_open"] + " " + folder_name)
		_processing_selection = false
	else:
		file_selected.emit(path)


func _on_item_activated() -> void:
	var selected = tree.get_selected()
	if not selected:
		return
	
	var path: String = selected.get_metadata(0)
	
	if not DirAccess.dir_exists_absolute(path):
		file_double_clicked.emit(path)
		print("FileSystemUI: Double-clicked file: ", path)
		
		# If it's a script, open in ScriptEditor (fallback to viewer)
		if path.ends_with(".gd"):
			if ScriptEditorUI and ScriptEditorUI.instance:
				ScriptEditorUI.instance.open_script(path)
			elif ScriptViewerUI and ScriptViewerUI.instance:
				ScriptViewerUI.instance.open_script(path)
		
		# Load scenes on double-click (including .tscn.remap)
		_try_load_scene_from_path(path)


func _on_load_button_pressed() -> void:
	var path := _get_selected_path()
	_try_load_scene_from_path(path)


func _on_spawn_button_pressed() -> void:
	var path := _get_selected_path()
	_try_instance_scene_from_path(path)


func _on_tree_gui_input(event: InputEvent) -> void:
	if not tree:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			var item := tree.get_item_at_position(mouse_event.position)
			if item:
				tree.set_selected(item, 0)
				_context_target_path = item.get_metadata(0)
				_update_context_menu_state()
				if _context_menu:
					_context_menu.position = mouse_event.global_position
					_context_menu.popup()
				accept_event()


func _try_load_scene_from_path(path: String) -> void:
	var scene_path := _resolve_scene_path(path)
	if scene_path == "":
		return
	# Decide whether to change the world or just spawn the scene into the current world
	var res = ResourceLoader.load(scene_path)
	if not (res and res is PackedScene):
		print("FileSystemUI: Selected file is not a PackedScene: ", scene_path)
		return
	var temp_inst := (res as PackedScene).instantiate()
	var is_world_scene := _looks_like_world_scene(temp_inst, scene_path)
	if temp_inst:
		temp_inst.queue_free()
	if is_world_scene:
		if ResourceLoader.exists(scene_path):
			print("FileSystemUI: Loading scene from resource: ", scene_path)
		else:
			print("FileSystemUI: Attempting to load (may rely on remap): ", scene_path)
		print("FileSystemUI: Changing world to scene: ", scene_path)
		if GameManager and GameManager.has_method("change_scene_with_player"):
			GameManager.call_deferred("change_scene_with_player", scene_path, {})
		else:
			get_tree().call_deferred("change_scene_to_file", scene_path)
	else:
		print("FileSystemUI: Scene looks like a tool/object; spawning into current world instead of changing scene: ", scene_path)
		_try_instance_scene_from_path(path)


func _can_load_scene(path: String) -> bool:
	return _is_scene_path(path)


func _can_instance_scene(path: String) -> bool:
	if not _is_scene_path(path):
		return false
	var scene_path := _resolve_scene_path(path)
	if scene_path == "":
		return false
	var res = ResourceLoader.load(scene_path)
	return res is PackedScene


func _is_scene_path(path: String) -> bool:
	if path.is_empty():
		return false
	if DirAccess.dir_exists_absolute(path):
		return false
	return path.ends_with(".tscn") or path.ends_with(".tscn.remap")


func _update_context_menu_state() -> void:
	if not _context_menu:
		return
	var can_load := _can_load_scene(_context_target_path)
	var can_spawn := _can_instance_scene(_context_target_path)
	_context_menu.set_item_disabled(0, not can_load)
	_context_menu.set_item_disabled(1, not can_spawn)


func _on_context_menu_item_selected(id: int) -> void:
	match id:
		0:
			_try_load_scene_from_path(_context_target_path)
		1:
			_try_instance_scene_from_path(_context_target_path)


func _get_selected_path() -> String:
	if not tree:
		return ""
	var selected = tree.get_selected()
	if selected:
		return selected.get_metadata(0)
	return ""


func _resolve_scene_path(path: String) -> String:
	if path.is_empty():
		return ""
	if DirAccess.dir_exists_absolute(path):
		return ""
	var scene_path := path
	if path.ends_with(".tscn.remap"):
		var candidate := path.substr(0, path.length() - ".remap".length())
		scene_path = candidate
	if not (scene_path.ends_with(".tscn") or scene_path.ends_with(".tscn.remap")):
		return ""
	return scene_path


func _looks_like_world_scene(root: Node, scene_path: String) -> bool:
	if not root:
		return false
	# Level directory heuristic
	if scene_path.contains("/levels/"):
		return true
	# If it has a SpawnPoint, treat as world
	var spawn := root.find_child("SpawnPoint", true, false)
	if spawn and spawn is Node3D:
		return true
	# If root is RigidBody3D with no children, it's almost certainly a single tool/object
	if root is RigidBody3D and root.get_child_count() == 0:
		return false
	# Default: treat as non-world (safer) to avoid nuking the current scene for tools
	return false


func _try_instance_scene_from_path(path: String) -> void:
	var scene_path := _resolve_scene_path(path)
	if scene_path == "":
		return
	var res = ResourceLoader.load(scene_path)
	if not (res and res is PackedScene):
		print("FileSystemUI: Selected file is not a PackedScene: ", scene_path)
		return
	
	# Check spawn limits before instantiating
	var pool := ToolPoolManager.find()
	if pool and not pool.can_spawn_scene():
		var count := pool.get_spawned_scene_count()
		var max_count := pool.get_max_spawned_scenes()
		print("FileSystemUI: Spawn limit reached (%d/%d). Clear spawned scenes first." % [count, max_count])
		_show_spawn_limit_warning(count, max_count)
		return
	
	var parent := _get_world_root()
	if not parent:
		print("FileSystemUI: No active world to spawn into")
		return
	var spawn_transform := _get_spawn_transform()
	var inst: Node = null
	var pooled := false
	if pool:
		inst = pool.request_scene_instance(scene_path, parent, spawn_transform)
		pooled = inst != null
	if not inst:
		inst = res.instantiate()
		if not inst:
			print("FileSystemUI: Failed to instantiate scene: ", scene_path)
			return
		parent.add_child(inst)
	inst.name = _make_unique_name(parent, inst.name)
	_set_owner_recursive(inst, parent)
	if inst is Node3D:
		(inst as Node3D).global_transform = spawn_transform
	
	# Register the spawned scene for tracking
	if pool:
		pool.register_spawned_scene(inst, scene_path)
	
	var mode_label := "pooled" if pooled else "new"
	print("FileSystemUI: Spawned scene into world (%s): %s from %s" % [mode_label, inst.name, scene_path])
	_refresh_scene_hierarchy()


func _get_world_root() -> Node:
	if GameManager and GameManager.current_world:
		return GameManager.current_world
	if get_tree() and get_tree().current_scene:
		return get_tree().current_scene
	if get_tree() and get_tree().root and get_tree().root.get_child_count() > 0:
		return get_tree().root.get_child(0)
	return null


func _get_player_node() -> Node3D:
	if not get_tree():
		return null
	var player := get_tree().get_first_node_in_group("xr_player")
	if player and player is Node3D:
		return player as Node3D
	player = get_tree().get_first_node_in_group("player")
	if player and player is Node3D:
		return player as Node3D
	var fallback = get_tree().root.find_child("XRPlayer", true, false) if get_tree().root else null
	if fallback and fallback is Node3D:
		return fallback as Node3D
	return null


func _get_spawn_transform() -> Transform3D:
	var basis := Basis.IDENTITY
	var origin := Vector3.ZERO
	var player := _get_player_node()
	if player:
		var tf: Transform3D = player.global_transform
		var forward := -tf.basis.z.normalized()
		origin = tf.origin + forward * spawn_forward_distance + Vector3.UP * spawn_height_offset
		basis = tf.basis
	else:
		var world := _get_world_root()
		if world:
			var spawn_point = world.find_child("SpawnPoint", true, false)
			if spawn_point and spawn_point is Node3D:
				origin = (spawn_point as Node3D).global_position + Vector3.UP * 0.5
				basis = (spawn_point as Node3D).global_transform.basis
	return Transform3D(basis, origin)


func _apply_spawn_transform(node: Node) -> void:
	if node is Node3D:
		var n3d := node as Node3D
		n3d.global_transform = _get_spawn_transform()


func _make_unique_name(parent: Node, base_name: String) -> String:
	var unique_name := base_name
	var counter := 2
	while _has_child_with_name(parent, unique_name):
		unique_name = "%s%d" % [base_name, counter]
		counter += 1
	return unique_name


func _has_child_with_name(parent: Node, target_name: String) -> bool:
	for child in parent.get_children():
		if child.name == target_name:
			return true
	return false


func _set_owner_recursive(node: Node, new_owner: Node) -> void:
	if not node or not new_owner:
		return
	node.owner = new_owner
	for child in node.get_children():
		_set_owner_recursive(child, new_owner)


func _refresh_scene_hierarchy() -> void:
	var panels = get_tree().get_nodes_in_group("scene_hierarchy") if get_tree() else []
	for panel in panels:
		if panel and panel.has_method("_populate_tree"):
			panel.call_deferred("_populate_tree")


## Refresh the filesystem tree
func refresh() -> void:
	_scan_filesystem()


## Navigate to and select a specific path
func select_path(path: String) -> void:
	if not tree or not _tree_root:
		return
	
	# Find the item with matching path
	var item = _find_item_by_path(_tree_root, path)
	if item:
		# Expand parent folders
		var parent = item.get_parent()
		while parent:
			parent.set_collapsed(false)
			parent = parent.get_parent()
		
		item.select(0)
		tree.scroll_to_item(item)


func _find_item_by_path(item: TreeItem, path: String) -> TreeItem:
	if item.get_metadata(0) == path:
		return item
	
	var child = item.get_first_child()
	while child:
		var found = _find_item_by_path(child, path)
		if found:
			return found
		child = child.get_next()
	
	return null


func _show_spawn_limit_warning(current: int, limit: int) -> void:
	"""Show a warning popup when spawn limit is reached."""
	# Create a temporary warning label that fades out
	var warning := Label.new()
	warning.text = "⚠️ Spawn limit reached (%d/%d)\nClear spawned scenes first" % [current, limit]
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.add_theme_color_override("font_color", Color(1, 0.65, 0.65))
	warning.add_theme_font_size_override("font_size", 14)
	
	var container := $MarginContainer/VBoxContainer
	if container:
		container.add_child(warning)
		container.move_child(warning, 0)
		
		# Auto-remove after 3 seconds
		var timer := get_tree().create_timer(3.0)
		timer.timeout.connect(func(): 
			if is_instance_valid(warning):
				warning.queue_free()
		)


## Clear all spawned scenes (utility for performance)
func clear_spawned_scenes() -> void:
	var pool := ToolPoolManager.find()
	if pool:
		pool.clear_all_spawned_scenes()
		print("FileSystemUI: Cleared all spawned scenes")
		_refresh_scene_hierarchy()
