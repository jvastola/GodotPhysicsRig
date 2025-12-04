extends PanelContainer
class_name FileSystemUI

## FileSystemUI - Displays project files in a tree structure
## Works like Godot's FileSystem dock for VR browsing

signal file_selected(path: String)
signal folder_selected(path: String)
signal file_double_clicked(path: String)

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var tree: Tree = $MarginContainer/VBoxContainer/Tree

var _root_path: String = "res://"
var _tree_root: TreeItem = null

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


func _ready() -> void:
	instance = self
	_setup_tree()
	# Delay the scan to ensure the tree is ready
	call_deferred("_scan_filesystem")


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if instance == self:
			instance = null


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


func _scan_filesystem() -> void:
	if not tree:
		return
	
	tree.clear()
	_tree_root = tree.create_item()
	_tree_root.set_text(0, "📂 res://")
	_tree_root.set_metadata(0, "res://")
	
	_scan_directory("res://", _tree_root)
	
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
		for hidden in HIDDEN_FOLDERS:
			if full_path.contains(hidden):
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
	var selected = tree.get_selected()
	if not selected:
		return
	
	var path: String = selected.get_metadata(0)
	
	if DirAccess.dir_exists_absolute(path):
		folder_selected.emit(path)
		# Toggle folder collapsed state
		selected.set_collapsed(not selected.is_collapsed())
		# Update icon
		var folder_name = path.get_file()
		if selected.is_collapsed():
			selected.set_text(0, ICONS["folder"] + " " + folder_name)
		else:
			selected.set_text(0, ICONS["folder_open"] + " " + folder_name)
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
		
		# If it's a script, open in ScriptViewer
		if path.ends_with(".gd"):
			if ScriptViewerUI and ScriptViewerUI.instance:
				ScriptViewerUI.instance.open_script(path)


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
