extends PanelContainer

# Scene Hierarchy UI - Displays the current scene tree in a Tree control
# Designed for 3D worldspace rendering via SubViewport

@export var auto_refresh_interval: float = 2.0  # Seconds between auto-refresh (0 to disable)
@export var show_internal_nodes: bool = false   # Show nodes that start with underscore

@onready var tree: Tree = $MarginContainer/VBoxContainer/ScrollContainer/Tree
@onready var refresh_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/RefreshButton
@onready var collapse_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/CollapseButton
@onready var expand_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/ExpandButton

var _root_scene: Node = null
var _refresh_timer: float = 0.0
var _tree_items: Dictionary = {}  # node -> TreeItem mapping for updates

func _ready() -> void:
	# Set up button connections
	if refresh_button:
		refresh_button.pressed.connect(_on_refresh_pressed)
	if collapse_button:
		collapse_button.pressed.connect(_on_collapse_pressed)
	if expand_button:
		expand_button.pressed.connect(_on_expand_pressed)
	
	# Configure tree
	if tree:
		tree.hide_root = false
		tree.allow_reselect = true
		tree.item_selected.connect(_on_item_selected)
	
	# Initial population with a small delay to ensure scene is ready
	call_deferred("_populate_tree")


func _process(delta: float) -> void:
	if auto_refresh_interval > 0:
		_refresh_timer += delta
		if _refresh_timer >= auto_refresh_interval:
			_refresh_timer = 0.0
			_populate_tree()


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
	var root_item = tree.create_item()
	_add_node_to_tree(_root_scene, root_item)


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
