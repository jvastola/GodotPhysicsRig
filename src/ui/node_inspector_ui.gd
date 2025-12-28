extends PanelContainer

# Node Inspector UI - Enhanced to match Godot's inspector style
# Features: Collapsible sections, class hierarchy grouping, editable properties

signal property_changed(node_path: NodePath, property_name: String, new_value: Variant)
signal script_requested(script_path: String)
signal close_requested

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleRow/TitleLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/TitleRow/CloseButton
@onready var scroll_container: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer
@onready var properties_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/PropertiesContainer
@onready var no_selection_label: Label = $MarginContainer/VBoxContainer/NoSelectionLabel

var _current_node: Node = null
var _property_controls: Dictionary = {}  # property_name -> Control
var _collapsed_sections: Dictionary = {}  # section_name -> bool (true = collapsed)

# Godot-like colors
const COLOR_SECTION_HEADER = Color(0.4, 0.55, 0.85, 1.0)
const COLOR_CLASS_HEADER = Color(0.35, 0.65, 0.45, 1.0)
const COLOR_LABEL = Color(0.65, 0.65, 0.7)
const COLOR_VALUE = Color(0.9, 0.9, 0.95)
const COLOR_X = Color(1.0, 0.4, 0.4)  # Red for X
const COLOR_Y = Color(0.4, 1.0, 0.4)  # Green for Y
const COLOR_Z = Color(0.4, 0.6, 1.0)  # Blue for Z

# Properties to skip (internal or redundant)
const SKIP_PROPERTIES = [
	"script", "owner", "multiplayer", "process_mode", "process_priority",
	"process_physics_priority", "process_thread_group", "process_thread_group_order",
	"process_thread_messages", "editor_description", "unique_name_in_owner"
]


func _ready() -> void:
	_show_no_selection()
	
	if close_button:
		close_button.pressed.connect(func(): close_requested.emit())


func inspect_node(node: Node) -> void:
	"""Display the properties of the given node."""
	if not node:
		_show_no_selection()
		return
	
	_current_node = node
	_build_inspector_ui()


func inspect_node_by_path(path: NodePath) -> void:
	"""Find and inspect a node by its path."""
	var node = get_tree().root.get_node_or_null(path)
	if node:
		inspect_node(node)
	else:
		_show_no_selection()
		push_warning("NodeInspectorUI: Could not find node at path: ", path)


func clear_selection() -> void:
	"""Clear the current selection and show 'no selection' message."""
	_current_node = null
	_show_no_selection()


func _show_no_selection() -> void:
	if title_label:
		title_label.text = "🔍 Inspector"
	if scroll_container:
		scroll_container.visible = false
	if no_selection_label:
		no_selection_label.visible = true
	_property_controls.clear()


func _build_inspector_ui() -> void:
	if not _current_node:
		return
	
	# Update title with icon based on class
	var icon = _get_class_icon(_current_node.get_class())
	if title_label:
		title_label.text = icon + " " + _current_node.name
	
	# Show scroll container, hide no-selection label
	if scroll_container:
		scroll_container.visible = true
	if no_selection_label:
		no_selection_label.visible = false
	
	# Clear existing properties
	if properties_container:
		for child in properties_container.get_children():
			child.queue_free()
	_property_controls.clear()
	
	# Wait a frame for children to be freed
	await get_tree().process_frame
	
	# Add node info section (always expanded)
	_add_collapsible_section("Node Info", func():
		_add_readonly_property("Name", _current_node.name)
		_add_readonly_property("Class", _current_node.get_class())
		_add_readonly_property("Path", str(_current_node.get_path()))
	, false)  # Start expanded
	
	# Actions section
	if _can_teleport_node(_current_node):
		_add_collapsible_section("Actions", func():
			_add_action_button(
				"📍 Teleport to Node",
				"Move the player to this node's position",
				func(): _teleport_current_node()
			)
		, false)
	
	# Script section
	var script = _current_node.get_script()
	if script:
		_add_collapsible_section("Script", func():
			_add_script_button(script)
		, false)
	
	# Get class hierarchy and add sections for each class
	var class_hierarchy = _get_class_hierarchy(_current_node)
	var property_list = _current_node.get_property_list()
	
	# Group properties by their class
	var properties_by_class = _group_properties_by_class(property_list, class_hierarchy)
	
	# Add properties for each class in the hierarchy (most derived first)
	for class_name_str in class_hierarchy:
		if properties_by_class.has(class_name_str) and properties_by_class[class_name_str].size() > 0:
			var class_icon = _get_class_icon(class_name_str)
			_add_collapsible_section(class_icon + " " + class_name_str, func():
				_add_properties_for_class(properties_by_class[class_name_str])
			, class_name_str != class_hierarchy[0])  # Collapse all except most derived
	
	# Add exported properties section
	_add_exported_properties()


func _get_class_hierarchy(node: Node) -> Array:
	"""Get the inheritance chain of a node's class."""
	var hierarchy: Array = []
	var current_class = node.get_class()
	
	while current_class != "" and current_class != "Object":
		hierarchy.append(current_class)
		current_class = ClassDB.get_parent_class(current_class)
	
	return hierarchy


func _class_has_property(class_name_str: String, property_name: String) -> bool:
	"""Check if a class has a specific property using ClassDB."""
	var property_list = ClassDB.class_get_property_list(class_name_str, true)  # true = no inheritance
	for prop in property_list:
		if prop["name"] == property_name:
			return true
	return false


func _group_properties_by_class(property_list: Array, class_hierarchy: Array) -> Dictionary:
	"""Group properties by which class they belong to."""
	var result: Dictionary = {}
	for class_name_str in class_hierarchy:
		result[class_name_str] = []
	
	for prop in property_list:
		var prop_name: String = prop["name"]
		var usage: int = prop["usage"]
		
		# Skip internal properties
		if prop_name in SKIP_PROPERTIES:
			continue
		if prop_name.begins_with("_"):
			continue
		if not (usage & PROPERTY_USAGE_EDITOR):
			continue
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue  # These go to exported properties section
		
		# Find which class this property belongs to
		for class_name_str in class_hierarchy:
			if _class_has_property(class_name_str, prop_name):
				# Check if parent has it too
				var parent_class = ClassDB.get_parent_class(class_name_str)
				if parent_class == "" or not _class_has_property(parent_class, prop_name):
					result[class_name_str].append(prop)
				break
	
	return result


func _add_properties_for_class(properties: Array) -> void:
	"""Add property controls for a list of properties."""
	for prop in properties:
		var prop_name: String = prop["name"]
		var prop_type: int = prop["type"]
		var prop_value = _current_node.get(prop_name)
		var prop_hint: int = prop.get("hint", 0)
		var prop_hint_string: String = prop.get("hint_string", "")
		
		# Format display name (convert snake_case to Title Case)
		var display_name = _format_property_name(prop_name)
		
		match prop_type:
			TYPE_BOOL:
				_add_bool_property(display_name, prop_value, prop_name)
			TYPE_INT:
				if prop_hint == PROPERTY_HINT_ENUM:
					_add_enum_property(display_name, prop_value, prop_name, prop_hint_string)
				else:
					_add_int_property(display_name, prop_value, prop_name)
			TYPE_FLOAT:
				_add_float_property(display_name, prop_value, prop_name)
			TYPE_STRING:
				_add_string_property(display_name, prop_value, prop_name)
			TYPE_VECTOR2:
				_add_vector2_property(display_name, prop_value, prop_name)
			TYPE_VECTOR3:
				_add_vector3_property(display_name, prop_value, prop_name)
			TYPE_COLOR:
				_add_color_property(display_name, prop_value, prop_name)
			TYPE_OBJECT:
				if prop_value != null:
					_add_resource_property(display_name, prop_value, prop_name)
				else:
					_add_readonly_property(display_name, "<null>")
			TYPE_NODE_PATH:
				_add_readonly_property(display_name, str(prop_value) if prop_value else "<empty>")
			TYPE_TRANSFORM3D:
				if prop_value is Transform3D:
					_add_transform_property(display_name, prop_value, prop_name)
			_:
				_add_readonly_property(display_name, str(prop_value).left(50))


func _format_property_name(prop_name: String) -> String:
	"""Convert snake_case to Title Case."""
	var words = prop_name.replace("_", " ").split(" ")
	var result = []
	for word in words:
		if word.length() > 0:
			result.append(word[0].to_upper() + word.substr(1))
	return " ".join(result)


func _get_class_icon(class_name_str: String) -> String:
	"""Get an icon emoji for a class."""
	match class_name_str:
		"Node": return "📦"
		"Node2D": return "🖼"
		"Node3D", "Spatial": return "🎲"
		"Control": return "🪟"
		"Camera3D": return "📷"
		"MeshInstance3D": return "🔷"
		"Light3D", "DirectionalLight3D", "OmniLight3D", "SpotLight3D": return "💡"
		"RigidBody3D": return "⚽"
		"CharacterBody3D": return "🏃"
		"StaticBody3D": return "🧱"
		"Area3D": return "🌀"
		"CollisionShape3D": return "📐"
		"AudioStreamPlayer3D": return "🔊"
		"AnimationPlayer": return "🎬"
		"Timer": return "⏱"
		"GPUParticles3D": return "✨"
		"Label", "Label3D": return "🏷"
		"Button": return "🔘"
		"Sprite2D", "Sprite3D": return "🖼"
		"XROrigin3D": return "🥽"
		"XRCamera3D": return "👁"
		"XRController3D": return "🎮"
		_: return "📄"


func _add_collapsible_section(title: String, content_builder: Callable, start_collapsed: bool = true) -> void:
	"""Add a collapsible section with a header."""
	if not properties_container:
		return
	
	var section_key = title
	if not _collapsed_sections.has(section_key):
		_collapsed_sections[section_key] = start_collapsed
	
	var is_collapsed = _collapsed_sections[section_key]
	
	# Create header button
	var header = Button.new()
	header.text = ("▶ " if is_collapsed else "▼ ") + title
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", COLOR_SECTION_HEADER)
	header.add_theme_color_override("font_hover_color", Color(0.5, 0.7, 1.0))
	header.flat = true
	properties_container.add_child(header)
	
	# Add separator
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	properties_container.add_child(sep)
	
	# Create content container
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	
	# Add left margin for indentation
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_child(content)
	margin.visible = not is_collapsed
	properties_container.add_child(margin)
	
	# Store reference for toggle
	header.set_meta("content_container", margin)
	header.set_meta("section_key", section_key)
	
	# Connect toggle
	header.pressed.connect(func():
		var container: MarginContainer = header.get_meta("content_container")
		var key: String = header.get_meta("section_key")
		_collapsed_sections[key] = not _collapsed_sections[key]
		container.visible = not _collapsed_sections[key]
		header.text = ("▶ " if _collapsed_sections[key] else "▼ ") + title
	)
	
	# Build content (temporarily swap properties_container)
	var old_container = properties_container
	properties_container = content
	content_builder.call()
	properties_container = old_container


func _add_exported_properties() -> void:
	"""Add controls for exported (@export) properties."""
	if not _current_node:
		return
	
	var property_list = _current_node.get_property_list()
	var export_props: Array = []
	
	for prop in property_list:
		# Only show exported properties (PROPERTY_USAGE_SCRIPT_VARIABLE + PROPERTY_USAGE_EDITOR)
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and prop["usage"] & PROPERTY_USAGE_EDITOR:
			export_props.append(prop)
	
	if export_props.size() == 0:
		return
	
	_add_collapsible_section("📝 Exported Properties", func():
		for prop in export_props:
			var prop_name: String = prop["name"]
			var prop_value = _current_node.get(prop_name)
			var prop_type: int = prop["type"]
			var prop_hint: int = prop.get("hint", 0)
			var prop_hint_string: String = prop.get("hint_string", "")
			var display_name = _format_property_name(prop_name)
			
			match prop_type:
				TYPE_BOOL:
					_add_bool_property(display_name, prop_value, prop_name)
				TYPE_INT:
					if prop_hint == PROPERTY_HINT_ENUM:
						_add_enum_property(display_name, prop_value, prop_name, prop_hint_string)
					else:
						_add_int_property(display_name, prop_value, prop_name)
				TYPE_FLOAT:
					_add_float_property(display_name, prop_value, prop_name)
				TYPE_STRING:
					_add_string_property(display_name, prop_value, prop_name)
				TYPE_VECTOR2:
					_add_vector2_property(display_name, prop_value, prop_name)
				TYPE_VECTOR3:
					_add_vector3_property(display_name, prop_value, prop_name)
				TYPE_COLOR:
					_add_color_property(display_name, prop_value, prop_name)
				_:
					_add_readonly_property(display_name, str(prop_value))
	, false)


func _add_script_button(script: Script) -> void:
	if not properties_container or not script:
		return
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	
	var script_button = Button.new()
	script_button.text = "📜 " + script.resource_path.get_file()
	script_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	script_button.add_theme_font_size_override("font_size", 11)
	script_button.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	
	var script_path = script.resource_path
	script_button.pressed.connect(func(): _on_script_button_pressed(script_path))
	script_button.tooltip_text = "Click to view: " + script_path
	hbox.add_child(script_button)
	
	properties_container.add_child(hbox)


func _on_script_button_pressed(script_path: String) -> void:
	print("NodeInspectorUI: Opening script: ", script_path)
	script_requested.emit(script_path)
	
	# Prefer the editable ScriptEditor if available, otherwise fall back to the viewer
	if ScriptEditorUI and ScriptEditorUI.instance:
		ScriptEditorUI.instance.open_script(script_path)
	elif ScriptViewerUI and ScriptViewerUI.instance:
		ScriptViewerUI.instance.open_script(script_path)


func _add_readonly_property(label_text: String, value: String) -> void:
	if not properties_container:
		return
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 100
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COLOR_LABEL)
	hbox.add_child(label)
	
	var value_label = Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 11)
	value_label.add_theme_color_override("font_color", COLOR_VALUE)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hbox.add_child(value_label)
	
	properties_container.add_child(hbox)


func _add_bool_property(label_text: String, value: bool, prop_name: String) -> void:
	if not properties_container:
		return
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 100
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COLOR_LABEL)
	hbox.add_child(label)
	
	var checkbox = CheckBox.new()
	checkbox.button_pressed = value
	checkbox.toggled.connect(func(pressed): _on_property_changed(prop_name, pressed))
	hbox.add_child(checkbox)
	
	properties_container.add_child(hbox)
	_property_controls[prop_name] = checkbox


func _add_float_property(label_text: String, value: float, prop_name: String) -> void:
	if not properties_container:
		return
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 100
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COLOR_LABEL)
	hbox.add_child(label)
	
	var spinbox = SpinBox.new()
	spinbox.value = value
	spinbox.step = 0.01
	spinbox.min_value = -10000
	spinbox.max_value = 10000
	spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spinbox.value_changed.connect(func(val): _on_property_changed(prop_name, val))
	hbox.add_child(spinbox)
	
	# Register with KeyboardManager
	_register_spinbox(spinbox)
	
	properties_container.add_child(hbox)
	_property_controls[prop_name] = spinbox


func _add_int_property(label_text: String, value: int, prop_name: String) -> void:
	if not properties_container:
		return
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 100
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COLOR_LABEL)
	hbox.add_child(label)
	
	var spinbox = SpinBox.new()
	spinbox.value = value
	spinbox.step = 1
	spinbox.min_value = -10000
	spinbox.max_value = 10000
	spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spinbox.value_changed.connect(func(val): _on_property_changed(prop_name, int(val)))
	hbox.add_child(spinbox)
	
	# Register with KeyboardManager
	_register_spinbox(spinbox)
	
	properties_container.add_child(hbox)
	_property_controls[prop_name] = spinbox


func _add_string_property(label_text: String, value: String, prop_name: String) -> void:
	if not properties_container:
		return
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 100
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COLOR_LABEL)
	hbox.add_child(label)
	
	var line_edit = LineEdit.new()
	line_edit.text = value
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit.text_submitted.connect(func(text): _on_property_changed(prop_name, text))
	hbox.add_child(line_edit)
	
	# Register with KeyboardManager for virtual keyboard input
	_register_line_edit(line_edit)
	
	properties_container.add_child(hbox)
	_property_controls[prop_name] = line_edit


func _add_enum_property(label_text: String, value: int, prop_name: String, hint_string: String) -> void:
	"""Add an enum property with dropdown."""
	if not properties_container:
		return
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 100
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COLOR_LABEL)
	hbox.add_child(label)
	
	var option_btn = OptionButton.new()
	option_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Parse enum values from hint_string (format: "Value1,Value2,Value3")
	var options = hint_string.split(",")
	for i in range(options.size()):
		option_btn.add_item(options[i].strip_edges(), i)
	
	option_btn.select(value)
	option_btn.item_selected.connect(func(idx): _on_property_changed(prop_name, idx))
	hbox.add_child(option_btn)
	
	properties_container.add_child(hbox)
	_property_controls[prop_name] = option_btn


func _add_action_button(text: String, tooltip: String, on_pressed: Callable) -> void:
	if not properties_container:
		return
	var btn = Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(on_pressed)
	properties_container.add_child(btn)


func _register_line_edit(line_edit: LineEdit) -> void:
	# Find parent viewport for context
	var viewport: SubViewport = null
	var parent = get_parent()
	while parent:
		if parent is SubViewport:
			viewport = parent
			break
		parent = parent.get_parent()
	
	if KeyboardManager and KeyboardManager.instance:
		KeyboardManager.instance.register_control(line_edit, viewport)


func _add_vector3_property(label_text: String, value: Vector3, prop_name: String) -> void:
	if not properties_container:
		return
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COLOR_LABEL)
	vbox.add_child(label)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	
	var container_x = _create_component_spinbox("X", value.x, COLOR_X)
	var container_y = _create_component_spinbox("Y", value.y, COLOR_Y)
	var container_z = _create_component_spinbox("Z", value.z, COLOR_Z)
	
	hbox.add_child(container_x)
	hbox.add_child(container_y)
	hbox.add_child(container_z)
	
	# Extract the actual SpinBox controls from the containers
	var spinbox_x: SpinBox = container_x.get_meta("spinbox")
	var spinbox_y: SpinBox = container_y.get_meta("spinbox")
	var spinbox_z: SpinBox = container_z.get_meta("spinbox")
	
	# Connect value changes
	var update_vector = func(_val):
		var new_vec = Vector3(spinbox_x.value, spinbox_y.value, spinbox_z.value)
		_on_property_changed(prop_name, new_vec)
	
	spinbox_x.value_changed.connect(update_vector)
	spinbox_y.value_changed.connect(update_vector)
	spinbox_z.value_changed.connect(update_vector)
	
	vbox.add_child(hbox)
	properties_container.add_child(vbox)


func _add_vector2_property(label_text: String, value: Vector2, prop_name: String) -> void:
	"""Add editable Vector2 property with X/Y spinboxes."""
	if not properties_container:
		return
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COLOR_LABEL)
	vbox.add_child(label)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	
	var container_x = _create_component_spinbox("X", value.x, COLOR_X)
	var container_y = _create_component_spinbox("Y", value.y, COLOR_Y)
	
	hbox.add_child(container_x)
	hbox.add_child(container_y)
	
	var spinbox_x: SpinBox = container_x.get_meta("spinbox")
	var spinbox_y: SpinBox = container_y.get_meta("spinbox")
	
	var update_vector = func(_val):
		var new_vec = Vector2(spinbox_x.value, spinbox_y.value)
		_on_property_changed(prop_name, new_vec)
	
	spinbox_x.value_changed.connect(update_vector)
	spinbox_y.value_changed.connect(update_vector)
	
	vbox.add_child(hbox)
	properties_container.add_child(vbox)


func _add_color_property(label_text: String, value: Color, prop_name: String) -> void:
	"""Add editable Color property with color picker button."""
	if not properties_container:
		return
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 100
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COLOR_LABEL)
	hbox.add_child(label)
	
	var color_picker_btn = ColorPickerButton.new()
	color_picker_btn.color = value
	color_picker_btn.custom_minimum_size = Vector2(60, 24)
	color_picker_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_picker_btn.color_changed.connect(func(new_color): _on_property_changed(prop_name, new_color))
	hbox.add_child(color_picker_btn)
	
	var hex_label = Label.new()
	hex_label.text = "#" + value.to_html(false)
	hex_label.add_theme_font_size_override("font_size", 10)
	hex_label.add_theme_color_override("font_color", COLOR_VALUE)
	hbox.add_child(hex_label)
	
	# Update hex label when color changes
	color_picker_btn.color_changed.connect(func(new_color):
		hex_label.text = "#" + new_color.to_html(false)
	)
	
	properties_container.add_child(hbox)
	_property_controls[prop_name] = color_picker_btn


func _add_resource_property(label_text: String, value: Object, prop_name: String) -> void:
	"""Add a resource/object property display."""
	if not properties_container:
		return
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 100
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COLOR_LABEL)
	hbox.add_child(label)
	
	var type_name = value.get_class() if value else "null"
	var res_path = ""
	if value is Resource and value.resource_path:
		res_path = value.resource_path.get_file()
	
	var resource_btn = Button.new()
	resource_btn.text = "📁 " + type_name + (" (" + res_path + ")" if res_path else "")
	resource_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resource_btn.add_theme_font_size_override("font_size", 10)
	resource_btn.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
	resource_btn.tooltip_text = "Resource: " + type_name
	hbox.add_child(resource_btn)
	
	properties_container.add_child(hbox)


func _add_transform_property(label_text: String, value: Transform3D, prop_name: String) -> void:
	"""Add a Transform3D property display (readonly for now)."""
	if not properties_container:
		return
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COLOR_LABEL)
	vbox.add_child(label)
	
	# Show origin
	var origin_text = "Origin: (%.2f, %.2f, %.2f)" % [value.origin.x, value.origin.y, value.origin.z]
	var origin_label = Label.new()
	origin_label.text = origin_text
	origin_label.add_theme_font_size_override("font_size", 10)
	origin_label.add_theme_color_override("font_color", COLOR_VALUE)
	vbox.add_child(origin_label)
	
	properties_container.add_child(vbox)


func _create_component_spinbox(component_label: String, value: float, color: Color) -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var label = Label.new()
	label.text = component_label
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", color)
	label.custom_minimum_size.x = 12
	hbox.add_child(label)
	
	var spinbox = SpinBox.new()
	spinbox.value = value
	spinbox.step = 0.01
	spinbox.min_value = -10000
	spinbox.max_value = 10000
	spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spinbox.custom_minimum_size.x = 55
	hbox.add_child(spinbox)
	
	# Register the SpinBox's internal LineEdit with KeyboardManager
	_register_spinbox(spinbox)
	
	# Store reference for retrieval
	hbox.set_meta("spinbox", spinbox)
	
	return hbox


func _register_spinbox(spinbox: SpinBox) -> void:
	# SpinBox has an internal LineEdit that we need to register
	var line_edit = spinbox.get_line_edit()
	if line_edit:
		_register_line_edit(line_edit)


func _on_property_changed(prop_name: String, new_value: Variant) -> void:
	if not _current_node:
		return
	
	# Apply the change to the node
	if prop_name in _current_node:
		_current_node.set(prop_name, new_value)
		print("NodeInspectorUI: Changed ", _current_node.name, ".", prop_name, " = ", new_value)
		property_changed.emit(_current_node.get_path(), prop_name, new_value)


func _teleport_current_node() -> void:
	if not _current_node:
		return
	var target_pos: Vector3 = _get_node_global_position(_current_node)
	if target_pos == null:
		print("NodeInspectorUI: Teleport requires a node with a 3D transform - ", _current_node.name)
		return
	
	target_pos += Vector3.UP * 0.5
	var player: Node = get_tree().get_first_node_in_group("xr_player")
	if not player:
		player = get_tree().root.find_child("XRPlayer", true, false)
	
	if player and player.has_method("teleport_to"):
		player.call_deferred("teleport_to", target_pos)
		print("NodeInspectorUI: Teleporting player to ", _current_node.name, " at ", target_pos)
	else:
		print("NodeInspectorUI: Player not found or cannot teleport")


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
