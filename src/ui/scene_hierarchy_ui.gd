extends PanelContainer

# Scene Hierarchy UI - Displays the current scene tree in a Tree control
# Designed for 3D worldspace rendering via SubViewport
# Enhanced with Godot-like editing: context menu, drag-drop, search, undo/redo

## Emitted when a node is selected in the hierarchy tree
signal node_selected(node_path: NodePath)
signal node_deleted(node_path: NodePath)
signal node_duplicated(original_path: NodePath, new_path: NodePath)
signal node_renamed(old_path: NodePath, new_path: NodePath)
signal node_reparented(node_path: NodePath, new_parent_path: NodePath)
signal close_requested

@export var auto_refresh_interval: float = 2.0  # Seconds between auto-refresh (0 to disable)
@export var show_internal_nodes: bool = false   # Show nodes that start with underscore

@onready var tree: Tree = $MarginContainer/VBoxContainer/ScrollContainer/Tree
@onready var save_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/SaveButton
@onready var refresh_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/RefreshButton
@onready var collapse_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/CollapseButton
@onready var expand_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/ExpandButton
@onready var actions_button: Button = $MarginContainer/VBoxContainer/HBoxContainer2/ActionsButton
@onready var undo_button: Button = $MarginContainer/VBoxContainer/HBoxContainer2/UndoButton
@onready var redo_button: Button = $MarginContainer/VBoxContainer/HBoxContainer2/RedoButton
@onready var add_node_button: Button = $MarginContainer/VBoxContainer/AddNodeRow/AddNodeButton
@onready var search_bar: LineEdit = $MarginContainer/VBoxContainer/SearchBar
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/TitleRow/CloseButton

var _root_scene: Node = null
var _refresh_timer: float = 0.0
var _tree_items: Dictionary = {}  # node -> TreeItem mapping for updates

# Context menu
var _context_menu: PopupMenu = null
var _context_target_item: TreeItem = null

# Clipboard for copy/paste
var _clipboard_node_data: Dictionary = {}

# Search/filter
var _search_filter: String = ""

# Add Node popup
var _add_node_popup: PopupPanel = null
var _add_node_search: LineEdit = null
var _add_node_list: ItemList = null
var _node_types: Array[String] = [
	"Node", "Node2D", "Node3D",
	"MeshInstance3D", "CSGBox3D", "CSGSphere3D", "CSGCylinder3D",
	"StaticBody3D", "RigidBody3D", "CharacterBody3D", "AnimatableBody3D",
	"CollisionShape3D", "Area3D",
	"Camera3D", "DirectionalLight3D", "OmniLight3D", "SpotLight3D",
	"Marker3D", "Path3D", "PathFollow3D",
	"AudioStreamPlayer3D", "GPUParticles3D",
	"Control", "Label", "Button", "Panel", "Label3D",
	"Timer", "AnimationPlayer"
]

# Undo/Redo
var _undo_redo: UndoRedo = null

# Context menu item IDs
enum ContextMenuID {
	COPY = 0,
	PASTE = 1,
	DUPLICATE = 2,
	RENAME = 3,
	DELETE = 4,
	TOGGLE_VISIBILITY = 5,
	EXPAND_ALL = 6,
	COLLAPSE_ALL = 7,
	TELEPORT_TO_NODE = 8
}


func _ready() -> void:
	# Add to group so inspector can find us
	add_to_group("scene_hierarchy")
	
	# Initialize undo/redo
	_undo_redo = UndoRedo.new()
	
	# Set up button connections
	if save_button:
		save_button.pressed.connect(_on_save_scene_pressed)
	if refresh_button:
		refresh_button.pressed.connect(_on_refresh_pressed)
	if collapse_button:
		collapse_button.pressed.connect(_on_collapse_pressed)
	if expand_button:
		expand_button.pressed.connect(_on_expand_pressed)
	if actions_button:
		actions_button.pressed.connect(_on_actions_button_pressed)
	if undo_button:
		undo_button.pressed.connect(_on_undo_pressed)
	if redo_button:
		redo_button.pressed.connect(_on_redo_pressed)
	if add_node_button:
		add_node_button.pressed.connect(_on_add_node_pressed)
	if close_button:
		close_button.pressed.connect(func(): close_requested.emit())
	
	# Configure tree
	if tree:
		tree.hide_root = false
		tree.allow_reselect = true
		tree.select_mode = Tree.SELECT_SINGLE
		tree.item_selected.connect(_on_item_selected)
		tree.item_edited.connect(_on_item_edited)
		if not tree.gui_input.is_connected(_on_tree_gui_input):
			tree.gui_input.connect(_on_tree_gui_input)
		# Note: Drag-drop disabled - conflicts with scroll in VR worldspace
		# tree.set_drag_forwarding(_tree_get_drag_data, _tree_can_drop_data, _tree_drop_data)
	
	# Set up context menu
	_setup_context_menu()
	
	# Set up add node popup
	_setup_add_node_popup()
	
	# Set up search bar
	if search_bar:
		search_bar.text_changed.connect(_on_search_text_changed)
		search_bar.placeholder_text = "🔍 Filter nodes..."
	
	# Initial population with a small delay to ensure scene is ready
	call_deferred("_populate_tree")
	_update_status_label()


func _process(delta: float) -> void:
	if auto_refresh_interval > 0:
		_refresh_timer += delta
		if _refresh_timer >= auto_refresh_interval:
			_refresh_timer = 0.0
			_populate_tree()


func _setup_context_menu() -> void:
	_context_menu = PopupMenu.new()
	_context_menu.name = "ContextMenu"
	add_child(_context_menu)
	
	_context_menu.add_item("📋 Copy", ContextMenuID.COPY)
	_context_menu.add_item("📥 Paste", ContextMenuID.PASTE)
	_context_menu.add_separator()
	_context_menu.add_item("📑 Duplicate", ContextMenuID.DUPLICATE)
	_context_menu.add_item("✏️ Rename", ContextMenuID.RENAME)
	_context_menu.add_separator()
	_context_menu.add_item("🗑️ Delete", ContextMenuID.DELETE)
	_context_menu.add_separator()
	_context_menu.add_item("📍 Teleport to Node", ContextMenuID.TELEPORT_TO_NODE)
	_context_menu.add_separator()
	_context_menu.add_item("👁️ Toggle Visibility", ContextMenuID.TOGGLE_VISIBILITY)
	_context_menu.add_separator()
	_context_menu.add_item("▼ Expand All", ContextMenuID.EXPAND_ALL)
	_context_menu.add_item("▲ Collapse All", ContextMenuID.COLLAPSE_ALL)
	
	_context_menu.id_pressed.connect(_on_context_menu_item_selected)


func _on_tree_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			var item = tree.get_item_at_position(mouse_event.position)
			if item:
				tree.set_selected(item, 0)
				_context_target_item = item
				_update_context_menu_state()
				_show_context_menu(mouse_event.global_position)
				accept_event()  # Stop further propagation of the right-click


func _on_actions_button_pressed() -> void:
	# VR-friendly: Show context menu for currently selected node
	var selected = tree.get_selected()
	if not selected:
		print("SceneHierarchy: No node selected - select a node first")
		return
	
	_context_target_item = selected
	_update_context_menu_state()
	
	# Position near the button
	if actions_button:
		_show_context_menu(actions_button.global_position + Vector2(0, actions_button.size.y))
	else:
		_show_context_menu(get_global_mouse_position())


func _show_context_menu(_pos: Vector2) -> void:
	if not _context_menu:
		return
	_context_menu.hide()
	_context_menu.position = global_position
	_context_menu.popup()


func _update_context_menu_state() -> void:
	# Disable Paste if clipboard is empty
	_context_menu.set_item_disabled(ContextMenuID.PASTE, _clipboard_node_data.is_empty())
	
	# Disable Delete for root node
	if _context_target_item:
		var node_path = _context_target_item.get_metadata(0)
		var node = get_node_or_null(node_path)
		var is_root = (node == _root_scene)
		_context_menu.set_item_disabled(ContextMenuID.DELETE, is_root)
		_context_menu.set_item_disabled(ContextMenuID.TELEPORT_TO_NODE, not _can_teleport_node(node))


func _on_context_menu_item_selected(id: int) -> void:
	match id:
		ContextMenuID.COPY:
			_copy_selected_node()
		ContextMenuID.PASTE:
			_paste_to_selected()
		ContextMenuID.DUPLICATE:
			_duplicate_selected_node()
		ContextMenuID.RENAME:
			_start_rename_selected_node()
		ContextMenuID.DELETE:
			_delete_selected_node()
		ContextMenuID.TOGGLE_VISIBILITY:
			_toggle_visibility_selected_node()
		ContextMenuID.TELEPORT_TO_NODE:
			_teleport_to_selected_node()
		ContextMenuID.EXPAND_ALL:
			_on_expand_pressed()
		ContextMenuID.COLLAPSE_ALL:
			_on_collapse_pressed()


# ============================================================================
# NODE OPERATIONS
# ============================================================================

func _copy_selected_node() -> void:
	var selected = tree.get_selected()
	if not selected:
		return
	
	var node_path = selected.get_metadata(0)
	var node = get_node_or_null(node_path)
	if not node:
		return
	
	# Store node data for paste
	_clipboard_node_data = {
		"name": node.name,
		"class": node.get_class(),
		"path": node_path,
		"scene_file": node.scene_file_path if node.scene_file_path else ""
	}
	print("SceneHierarchy: Copied node - ", node.name)


func _paste_to_selected() -> void:
	if _clipboard_node_data.is_empty():
		print("SceneHierarchy: Clipboard is empty")
		return
	
	var selected = tree.get_selected()
	var parent_node: Node
	
	if selected:
		var parent_path = selected.get_metadata(0)
		parent_node = get_node_or_null(parent_path)
	else:
		parent_node = _root_scene
	
	if not parent_node:
		return
	
	# Get original node to duplicate
	var original_path = _clipboard_node_data.get("path")
	var original_node = get_node_or_null(original_path)
	
	if not original_node:
		print("SceneHierarchy: Original node no longer exists")
		return
	
	# Duplicate the node
	var new_node = original_node.duplicate()
	new_node.name = _generate_unique_name(parent_node, original_node.name)
	
	parent_node.add_child(new_node)
	new_node.owner = _root_scene
	_set_owner_recursive(new_node, _root_scene)
	
	print("SceneHierarchy: Pasted node - ", new_node.name)
	call_deferred("_populate_tree")


func _duplicate_selected_node() -> void:
	var selected = tree.get_selected()
	if not selected:
		return
	
	var node_path = selected.get_metadata(0)
	var node = get_node_or_null(node_path)
	if not node:
		return
	
	var parent = node.get_parent()
	if not parent:
		return
	
	# Create action for undo/redo
	var new_node = node.duplicate()
	new_node.name = _generate_unique_name(parent, node.name)
	
	parent.add_child(new_node)
	new_node.owner = _root_scene
	_set_owner_recursive(new_node, _root_scene)
	
	print("SceneHierarchy: Duplicated node - ", node.name, " -> ", new_node.name)
	node_duplicated.emit(node_path, new_node.get_path())
	call_deferred("_populate_tree")


func _start_rename_selected_node() -> void:
	var selected = tree.get_selected()
	if not selected:
		return
	
	# Enable editing on the tree item
	selected.set_editable(0, true)
	tree.edit_selected()


func _on_item_edited() -> void:
	var selected = tree.get_selected()
	if not selected:
		return
	
	var node_path = selected.get_metadata(0)
	var node = get_node_or_null(node_path)
	if not node:
		return
	
	var new_text = selected.get_text(0)
	# Extract just the name from "Name [Type]" format
	var bracket_pos = new_text.find(" [")
	var new_name = new_text.substr(0, bracket_pos) if bracket_pos > 0 else new_text
	new_name = new_name.strip_edges()
	
	if new_name.is_empty():
		# Revert to original name
		selected.set_text(0, _get_node_display_text(node))
	elif new_name != node.name:
		var old_path = node.get_path()
		node.name = new_name
		selected.set_metadata(0, node.get_path())
		selected.set_text(0, _get_node_display_text(node))
		print("SceneHierarchy: Renamed node - ", old_path, " -> ", node.get_path())
		node_renamed.emit(old_path, node.get_path())
	
	# Disable editing
	selected.set_editable(0, false)


func _delete_selected_node() -> void:
	var selected = tree.get_selected()
	if not selected:
		return
	
	var node_path = selected.get_metadata(0)
	var node = get_node_or_null(node_path)
	if not node:
		return
	
	# Prevent deleting root
	if node == _root_scene:
		print("SceneHierarchy: Cannot delete root node")
		return
	
	print("SceneHierarchy: Deleted node - ", node.name)
	node_deleted.emit(node_path)
	node.queue_free()
	call_deferred("_populate_tree")


func _toggle_visibility_selected_node() -> void:
	var selected = tree.get_selected()
	if not selected:
		return
	
	var node_path = selected.get_metadata(0)
	var node = get_node_or_null(node_path)
	if not node:
		return
	
	if node is Node3D:
		(node as Node3D).visible = not (node as Node3D).visible
		_style_tree_item(selected, node)
		print("SceneHierarchy: Toggled visibility - ", node.name, " = ", (node as Node3D).visible)
	elif node is CanvasItem:
		(node as CanvasItem).visible = not (node as CanvasItem).visible
		_style_tree_item(selected, node)
		print("SceneHierarchy: Toggled visibility - ", node.name, " = ", (node as CanvasItem).visible)
	else:
		print("SceneHierarchy: Node has no visible property - ", node.name)


func _teleport_to_selected_node() -> void:
	var selected = tree.get_selected()
	if not selected:
		return
	
	var node_path = selected.get_metadata(0)
	var node = get_node_or_null(node_path)
	if not node:
		return
	
	var target_pos: Vector3 = _get_node_global_position(node)
	if target_pos == null:
		print("SceneHierarchy: Teleport requires a node with a 3D transform - ", node.name)
		return
	target_pos += Vector3.UP * 0.5
	
	var player: Node = get_tree().get_first_node_in_group("xr_player")
	if not player:
		player = get_tree().root.find_child("XRPlayer", true, false)
	
	if player and player.has_method("teleport_to"):
		player.call_deferred("teleport_to", target_pos)
		print("SceneHierarchy: Teleporting player to ", node.name, " at ", target_pos)
	else:
		print("SceneHierarchy: Player not found or cannot teleport")


func _can_teleport_node(node: Node) -> bool:
	if not node:
		return false
	if "global_transform" in node:
		var gt = node.get("global_transform")
		if gt is Transform3D:
			return true
	if node.has_method("get_global_transform"):
		var gt2 = node.call("get_global_transform")
		if gt2 is Transform3D:
			return true
	return false


func _get_node_global_position(node: Node) -> Variant:
	if not node:
		return null
	if "global_transform" in node:
		var gt = node.get("global_transform")
		if gt is Transform3D:
			return (gt as Transform3D).origin
	if node.has_method("get_global_transform"):
		var gt2 = node.call("get_global_transform")
		if gt2 is Transform3D:
			return (gt2 as Transform3D).origin
	return null


func _generate_unique_name(parent: Node, base_name: String) -> String:
	# Remove any existing number suffix
	var regex = RegEx.new()
	regex.compile("(\\d+)$")
	var result = regex.search(base_name)
	var name_without_number = base_name
	var counter = 2
	
	if result:
		name_without_number = base_name.substr(0, result.get_start())
		counter = int(result.get_string()) + 1
	
	# Find unique name
	var new_name = name_without_number + str(counter)
	while parent.has_node(new_name):
		counter += 1
		new_name = name_without_number + str(counter)
	
	return new_name


func _set_owner_recursive(node: Node, new_owner: Node) -> void:
	for child in node.get_children():
		child.owner = new_owner
		_set_owner_recursive(child, new_owner)


# ============================================================================
# DRAG AND DROP
# ============================================================================

func _tree_get_drag_data(at_position: Vector2) -> Variant:
	var item = tree.get_item_at_position(at_position)
	if not item:
		return null
	
	var node_path = item.get_metadata(0)
	var node = get_node_or_null(node_path)
	if not node or node == _root_scene:
		return null  # Can't drag root
	
	# Create drag preview
	var preview = Label.new()
	preview.text = "📦 " + node.name
	tree.set_drag_preview(preview)
	
	return {"type": "scene_hierarchy_node", "path": node_path, "name": node.name}


func _tree_can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or data.get("type") != "scene_hierarchy_node":
		return false
	
	var target_item = tree.get_item_at_position(at_position)
	if not target_item:
		return false
	
	var source_path: String = data["path"]
	var target_path: String = target_item.get_metadata(0)
	
	# Can't drop onto self
	if source_path == target_path:
		return false
	
	# Can't drop parent into child (would create cycle)
	if target_path.begins_with(source_path + "/"):
		return false
	
	return true


func _tree_drop_data(at_position: Vector2, data: Variant) -> void:
	var target_item = tree.get_item_at_position(at_position)
	if not target_item:
		return
	
	var source_path: NodePath = data["path"]
	var target_path: NodePath = target_item.get_metadata(0)
	
	var source_node = get_node_or_null(source_path)
	var target_node = get_node_or_null(target_path)
	
	if not source_node or not target_node:
		return
	
	# Reparent the node
	var old_parent = source_node.get_parent()
	if old_parent == target_node:
		return  # Already a child
	
	source_node.reparent(target_node)
	source_node.owner = _root_scene
	
	print("SceneHierarchy: Reparented ", source_node.name, " to ", target_node.name)
	node_reparented.emit(source_path, target_path)
	call_deferred("_populate_tree")


# ============================================================================
# SEARCH / FILTER
# ============================================================================

func _on_search_text_changed(new_text: String) -> void:
	_search_filter = new_text.to_lower().strip_edges()
	_apply_search_filter()


func _apply_search_filter() -> void:
	if not tree or not tree.get_root():
		return
	
	if _search_filter.is_empty():
		_set_all_items_visible(tree.get_root(), true)
	else:
		_filter_items_recursive(tree.get_root())


func _set_all_items_visible(item: TreeItem, should_be_visible: bool) -> void:
	item.visible = should_be_visible
	var child = item.get_first_child()
	while child:
		_set_all_items_visible(child, should_be_visible)
		child = child.get_next()


func _filter_items_recursive(item: TreeItem) -> bool:
	var text = item.get_text(0).to_lower()
	var self_matches = text.contains(_search_filter)
	
	var any_child_matches = false
	var child = item.get_first_child()
	while child:
		if _filter_items_recursive(child):
			any_child_matches = true
		child = child.get_next()
	
	var should_show = self_matches or any_child_matches
	item.visible = should_show
	
	# Expand to show matching children
	if any_child_matches and not self_matches:
		item.collapsed = false
	
	return should_show


# ============================================================================
# STATUS LABEL
# ============================================================================

func _update_status_label() -> void:
	if not status_label:
		return
	
	var total_nodes = _tree_items.size()
	var selected = tree.get_selected() if tree else null
	
	if selected:
		var node_path = selected.get_metadata(0)
		var node = get_node_or_null(node_path)
		if node:
			status_label.text = "📍 " + node.name + " | " + str(total_nodes) + " nodes"
		else:
			status_label.text = str(total_nodes) + " nodes"
	else:
		status_label.text = str(total_nodes) + " nodes"


# ============================================================================
# TREE POPULATION (Enhanced)
# ============================================================================

func _populate_tree() -> void:
	if not tree:
		return
	
	tree.clear()
	_tree_items.clear()
	
	# Get the main scene root (not our UI viewport)
	_root_scene = _find_main_scene_root()
	if not _root_scene:
		var root_item = tree.create_item()
		root_item.set_text(0, "[No Scene Found]")
		return
	
	# Build the tree recursively
	var main_root = tree.create_item()
	_add_node_to_tree(_root_scene, main_root)
	_update_status_label()


func _find_main_scene_root() -> Node:
	# Navigate up to find the actual scene root
	# We want to find the main scene, not this UI's SubViewport
	var scene_tree = get_tree()
	if not scene_tree:
		return null
	
	# Get the main scene root
	var current_scene = scene_tree.current_scene
	if current_scene:
		return current_scene
	
	# Fallback: get tree root
	var root = scene_tree.root
	if root and root.get_child_count() > 0:
		# Return the first child that isn't a Viewport-related node
		for child in root.get_children():
			if not child is Viewport:
				return child
		# If all are viewports, return the first child's first child (usually main scene)
		return root.get_child(0)
	
	return null


func _add_node_to_tree(node: Node, parent_item: TreeItem) -> void:
	if not node:
		return
	
	# Skip internal nodes if configured
	if not show_internal_nodes and node.name.begins_with("_"):
		return
	
	# Skip nodes inside SubViewports (like our own UI)
	if node is SubViewport:
		return
	
	# Set the tree item text
	var display_text = _get_node_display_text(node)
	parent_item.set_text(0, display_text)
	parent_item.set_metadata(0, node.get_path())
	
	# Set icon/color based on node type
	_style_tree_item(parent_item, node)
	
	# Store mapping
	_tree_items[node] = parent_item
	
	# Recursively add children
	for child in node.get_children():
		# Skip SubViewports to avoid showing our own UI tree
		if child is SubViewport:
			continue
		if not show_internal_nodes and child.name.begins_with("_"):
			continue
		
		var child_item = tree.create_item(parent_item)
		_add_node_to_tree(child, child_item)


func _get_node_display_text(node: Node) -> String:
	var type_name = node.get_class()
	
	# Shortened type names for common types
	var short_types = {
		"Node3D": "N3D",
		"Node2D": "N2D",
		"MeshInstance3D": "Mesh",
		"StaticBody3D": "Static",
		"RigidBody3D": "Rigid",
		"CharacterBody3D": "Char",
		"CollisionShape3D": "Col",
		"Camera3D": "Cam",
		"DirectionalLight3D": "DirLight",
		"SpotLight3D": "Spot",
		"OmniLight3D": "Omni",
		"WorldEnvironment": "Env",
		"SubViewport": "VP",
		"Control": "Ctrl",
		"PanelContainer": "Panel",
		"VBoxContainer": "VBox",
		"HBoxContainer": "HBox",
		"Button": "Btn",
		"Label": "Lbl",
		"Label3D": "Lbl3D",
		"Tree": "Tree",
		"XROrigin3D": "XROrigin",
		"XRCamera3D": "XRCam",
		"XRController3D": "XRCtrl",
	}
	
	var short_type = short_types.get(type_name, type_name)
	return "%s [%s]" % [node.name, short_type]


func _style_tree_item(item: TreeItem, node: Node) -> void:
	# Color coding based on node type
	var color: Color = Color.WHITE
	
	if node is Camera3D or node is XRCamera3D:
		color = Color(0.4, 0.8, 1.0)  # Light blue for cameras
	elif node is Light3D:
		color = Color(1.0, 1.0, 0.4)  # Yellow for lights
	elif node is PhysicsBody3D:
		color = Color(0.4, 1.0, 0.6)  # Green for physics bodies
	elif node is Control:
		color = Color(0.8, 0.6, 1.0)  # Purple for UI
	elif node is MeshInstance3D:
		color = Color(1.0, 0.7, 0.4)  # Orange for meshes
	elif node is Marker3D:
		color = Color(0.6, 0.6, 0.6)  # Gray for markers
	
	item.set_custom_color(0, color)
	
	# Dim invisible nodes
	if node is CanvasItem and not (node as CanvasItem).visible:
		item.set_custom_color(0, color * 0.5)
	elif node is Node3D and not (node as Node3D).visible:
		item.set_custom_color(0, color * 0.5)


func _on_refresh_pressed() -> void:
	_populate_tree()


func _on_save_scene_pressed() -> void:
	var msg := _save_current_scene()
	if not msg.is_empty() and status_label:
		status_label.text = msg


func _save_current_scene() -> String:
	var scene_tree := get_tree()
	if not scene_tree:
		return "No scene tree"
	var current_scene := scene_tree.current_scene
	if current_scene == null:
		return "No active scene"
	var path := current_scene.scene_file_path
	if path.is_empty():
		return "Save failed: scene path is empty"
	var packed := PackedScene.new()
	var pack_err := packed.pack(current_scene)
	if pack_err != OK:
		push_error("SceneHierarchyUI: Pack failed %s" % pack_err)
		var user_target := _to_user_repo_path(path)
		_notify_version_tracker([user_target])  # still stage so change is visible
		return "Save failed (pack %s) at %s" % [pack_err, path]
	var target_path := _to_user_repo_path(path)
	_make_dir_recursive(target_path.get_base_dir())
	var save_err := ResourceSaver.save(packed, target_path)
	if save_err != OK:
		push_error("SceneHierarchyUI: Save failed %s" % save_err)
		_notify_version_tracker([target_path])  # still stage so change is visible
		return "Save failed (code %s) for %s" % [save_err, target_path]
	print("SceneHierarchyUI: Saved scene to ", target_path)
	_notify_version_tracker([target_path])
	return "💾 Saved scene"


func _notify_version_tracker(paths: Array) -> void:
	if paths.is_empty():
		return
	var localized: Array = []
	for p in paths:
		localized.append(ProjectSettings.localize_path(p))
	var panel := _get_git_panel()
	if panel:
		panel.stage_paths_and_refresh(localized)
		_refresh_git_panel(panel)
	else:
		var git := GitService.new()
		git.stage_paths(localized)
		_refresh_git_panel(_get_git_panel())  # try again in case it appeared


func _get_git_panel() -> GitPanelUI:
	if GitPanelUI.instance:
		return GitPanelUI.instance
	if get_tree():
		var node = get_tree().get_first_node_in_group("git_panel")
		if node and node is GitPanelUI:
			return node
	return null


func _refresh_git_panel(panel: GitPanelUI) -> void:
	if panel:
		panel.refresh_status()
		panel.refresh_history()


func _to_user_repo_path(path: String) -> String:
	if path.begins_with("user://workspace_repo/"):
		return path
	if path.begins_with("res://"):
		var relative := path.substr("res://".length())
		return "user://workspace_repo/" + relative
	return path


func _make_dir_recursive(path: String) -> void:
	var d := DirAccess.open("user://")
	if d:
		d.make_dir_recursive(path)


func _on_collapse_pressed() -> void:
	if tree and tree.get_root():
		_set_collapsed_recursive(tree.get_root(), true)


func _on_expand_pressed() -> void:
	if tree and tree.get_root():
		_set_collapsed_recursive(tree.get_root(), false)


func _set_collapsed_recursive(item: TreeItem, collapsed: bool) -> void:
	item.collapsed = collapsed
	var child = item.get_first_child()
	while child:
		_set_collapsed_recursive(child, collapsed)
		child = child.get_next()


func _on_item_selected() -> void:
	var selected = tree.get_selected()
	if selected:
		var node_path = selected.get_metadata(0)
		if node_path:
			print("SceneHierarchyUI: Selected node: ", node_path)
			# Emit signal for connected inspector panels
			node_selected.emit(node_path)
	_update_status_label()


# ============================================================================
# UNDO / REDO
# ============================================================================

func _on_undo_pressed() -> void:
	if _undo_redo and _undo_redo.has_undo():
		_undo_redo.undo()
		call_deferred("_populate_tree")
		print("SceneHierarchy: Undo")
	else:
		print("SceneHierarchy: Nothing to undo")


func _on_redo_pressed() -> void:
	if _undo_redo and _undo_redo.has_redo():
		_undo_redo.redo()
		call_deferred("_populate_tree")
		print("SceneHierarchy: Redo")
	else:
		print("SceneHierarchy: Nothing to redo")


# ============================================================================
# ADD NODE POPUP
# ============================================================================

func _setup_add_node_popup() -> void:
	_add_node_popup = PopupPanel.new()
	_add_node_popup.name = "AddNodePopup"
	add_child(_add_node_popup)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_add_node_popup.add_child(vbox)
	
	# Title
	var title = Label.new()
	title.text = "➕ Add New Node"
	title.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	title.add_theme_font_size_override("font_size", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# Search filter
	_add_node_search = LineEdit.new()
	_add_node_search.placeholder_text = "🔍 Search node types..."
	_add_node_search.clear_button_enabled = true
	_add_node_search.custom_minimum_size = Vector2(250, 32)
	_add_node_search.text_changed.connect(_on_add_node_search_changed)
	vbox.add_child(_add_node_search)
	
	# Node type list
	_add_node_list = ItemList.new()
	_add_node_list.custom_minimum_size = Vector2(250, 300)
	_add_node_list.allow_reselect = true
	_add_node_list.item_activated.connect(_on_add_node_type_activated)
	vbox.add_child(_add_node_list)
	
	# Populate with node types
	_populate_add_node_list("")
	
	# Cancel button
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func(): _add_node_popup.hide())
	vbox.add_child(cancel_btn)


func _populate_add_node_list(filter: String) -> void:
	if not _add_node_list:
		return
	
	_add_node_list.clear()
	var filter_lower = filter.to_lower()
	
	for type_name in _node_types:
		if filter.is_empty() or type_name.to_lower().contains(filter_lower):
			_add_node_list.add_item(type_name)


func _on_add_node_search_changed(new_text: String) -> void:
	_populate_add_node_list(new_text)


func _on_add_node_pressed() -> void:
	if not _add_node_popup:
		return
	
	# Clear search and repopulate
	if _add_node_search:
		_add_node_search.text = ""
	_populate_add_node_list("")
	
	# Show popup
	_add_node_popup.popup_centered()


func _on_add_node_type_activated(index: int) -> void:
	if not _add_node_list:
		return
	
	var type_name = _add_node_list.get_item_text(index)
	_add_new_node(type_name)
	_add_node_popup.hide()


func _add_new_node(type_name: String) -> void:
	# Determine parent node
	var parent_node: Node = null
	var selected = tree.get_selected() if tree else null
	
	if selected:
		var parent_path = selected.get_metadata(0)
		parent_node = get_node_or_null(parent_path)
	
	if not parent_node:
		parent_node = _root_scene
	
	if not parent_node:
		print("SceneHierarchy: No parent node available")
		return
	
	# Create new node instance
	var new_node: Node = null
	match type_name:
		"Node":
			new_node = Node.new()
		"Node2D":
			new_node = Node2D.new()
		"Node3D":
			new_node = Node3D.new()
		"MeshInstance3D":
			new_node = MeshInstance3D.new()
		"CSGBox3D":
			new_node = CSGBox3D.new()
		"CSGSphere3D":
			new_node = CSGSphere3D.new()
		"CSGCylinder3D":
			new_node = CSGCylinder3D.new()
		"StaticBody3D":
			new_node = StaticBody3D.new()
		"RigidBody3D":
			new_node = RigidBody3D.new()
		"CharacterBody3D":
			new_node = CharacterBody3D.new()
		"AnimatableBody3D":
			new_node = AnimatableBody3D.new()
		"CollisionShape3D":
			new_node = CollisionShape3D.new()
		"Area3D":
			new_node = Area3D.new()
		"Camera3D":
			new_node = Camera3D.new()
		"DirectionalLight3D":
			new_node = DirectionalLight3D.new()
		"OmniLight3D":
			new_node = OmniLight3D.new()
		"SpotLight3D":
			new_node = SpotLight3D.new()
		"Marker3D":
			new_node = Marker3D.new()
		"Path3D":
			new_node = Path3D.new()
		"PathFollow3D":
			new_node = PathFollow3D.new()
		"AudioStreamPlayer3D":
			new_node = AudioStreamPlayer3D.new()
		"GPUParticles3D":
			new_node = GPUParticles3D.new()
		"Control":
			new_node = Control.new()
		"Label":
			new_node = Label.new()
		"Button":
			new_node = Button.new()
		"Panel":
			new_node = Panel.new()
		"Label3D":
			new_node = Label3D.new()
		"Timer":
			new_node = Timer.new()
		"AnimationPlayer":
			new_node = AnimationPlayer.new()
		_:
			# Try to create using ClassDB for any valid class
			if ClassDB.class_exists(type_name) and ClassDB.can_instantiate(type_name):
				new_node = ClassDB.instantiate(type_name)
			else:
				print("SceneHierarchy: Unknown node type - ", type_name)
				return
	
	if not new_node:
		print("SceneHierarchy: Failed to create node of type - ", type_name)
		return
	
	# Set name and add to parent
	new_node.name = _generate_unique_name(parent_node, type_name)
	parent_node.add_child(new_node)
	new_node.owner = _root_scene
	
	print("SceneHierarchy: Added new ", type_name, " named ", new_node.name)
	call_deferred("_populate_tree")

