extends PanelContainer

# Add Node UI - Displays a list of node types that can be added to the scene
# Designed for 3D worldspace rendering via SubViewport

## Emitted when a node type is selected to be added
signal node_type_selected(type_name: String)
signal close_requested

@onready var search_bar: LineEdit = $MarginContainer/VBoxContainer/SearchBar
@onready var node_list: ItemList = $MarginContainer/VBoxContainer/NodeList
@onready var close_button: Button = $MarginContainer/VBoxContainer/TitleRow/CloseButton

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


func _ready() -> void:
	if search_bar:
		search_bar.text_changed.connect(_on_search_text_changed)
		search_bar.placeholder_text = "🔍 Search node types..."
		search_bar.clear_button_enabled = true
	
	if node_list:
		node_list.item_activated.connect(_on_node_type_activated)
	
	if close_button:
		close_button.pressed.connect(func(): close_requested.emit())
	
	# Populate the list
	_populate_list("")


func _populate_list(filter: String) -> void:
	if not node_list:
		return
	
	node_list.clear()
	var filter_lower = filter.to_lower()
	
	for type_name in _node_types:
		if filter.is_empty() or type_name.to_lower().contains(filter_lower):
			node_list.add_item(type_name)


func _on_search_text_changed(new_text: String) -> void:
	_populate_list(new_text)


func _on_node_type_activated(index: int) -> void:
	if not node_list:
		return
	
	var type_name = node_list.get_item_text(index)
	print("AddNodeUI: Selected node type: ", type_name)
	node_type_selected.emit(type_name)
	
	# Close the panel after selection
	var panel_manager := UIPanelManager.find()
	if panel_manager:
		# Find our parent viewport name to close
		var parent = get_parent()
		while parent:
			if parent.name == "AddNodeViewport3D":
				panel_manager.close_panel(parent.name)
				break
			parent = parent.get_parent()
