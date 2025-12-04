extends PanelContainer

# Node Inspector UI - Displays properties of a selected node
# Works in conjunction with SceneHierarchyUI

signal property_changed(node_path: NodePath, property_name: String, new_value: Variant)
signal script_requested(script_path: String)
@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var scroll_container: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer
@onready var properties_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/PropertiesContainer
@onready var no_selection_label: Label = $MarginContainer/VBoxContainer/NoSelectionLabel

var _current_node: Node = null
var _property_controls: Dictionary = {}  # property_name -> Control

# Properties to show for common node types
const TRANSFORM_PROPERTIES = ["position", "rotation", "scale", "global_position", "global_rotation"]
const NODE3D_PROPERTIES = ["visible", "transform"]
const CONTROL_PROPERTIES = ["visible", "size", "position", "rotation", "scale"]


func _ready() -> void:
	_show_no_selection()


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
	
	# Update title
	if title_label:
		title_label.text = "🔍 " + _current_node.name + " [" + _current_node.get_class() + "]"
	
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
	
	# Add node info section
	_add_section_header("Node Info")
	_add_readonly_property("Name", _current_node.name)
	_add_readonly_property("Class", _current_node.get_class())
	_add_readonly_property("Path", str(_current_node.get_path()))
	
	# Add transform section for Node3D
	if _current_node is Node3D:
		var node3d := _current_node as Node3D
		_add_section_header("Transform")
		_add_vector3_property("Position", node3d.position, "position")
		_add_vector3_readonly("Rotation (deg)", node3d.rotation_degrees)
		_add_vector3_property("Scale", node3d.scale, "scale")
		
		_add_section_header("Visibility")
		_add_bool_property("Visible", node3d.visible, "visible")
	
	# Add Control section for UI nodes
	elif _current_node is Control:
		var control := _current_node as Control
		_add_section_header("Layout")
		_add_vector2_readonly("Position", control.position)
		_add_vector2_readonly("Size", control.size)
		
		_add_section_header("Visibility")
		_add_bool_property("Visible", control.visible, "visible")
	
	# Add script info if present
	var script = _current_node.get_script()
	if script:
		_add_section_header("Script")
		_add_script_button(script)
	
	# Add exported properties
	_add_exported_properties()


func _add_exported_properties() -> void:
	"""Add controls for exported (@export) properties."""
	if not _current_node:
		return
	
	var property_list = _current_node.get_property_list()
	var has_exports = false
	
	for prop in property_list:
		# Only show exported properties (PROPERTY_USAGE_SCRIPT_VARIABLE + PROPERTY_USAGE_EDITOR)
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and prop["usage"] & PROPERTY_USAGE_EDITOR:
			if not has_exports:
				_add_section_header("Exported Properties")
				has_exports = true
			
			var prop_name: String = prop["name"]
			var prop_value = _current_node.get(prop_name)
			var prop_type: int = prop["type"]
			
			match prop_type:
				TYPE_BOOL:
					_add_bool_property(prop_name, prop_value, prop_name)
				TYPE_INT:
					_add_int_property(prop_name, prop_value, prop_name)
				TYPE_FLOAT:
					_add_float_property(prop_name, prop_value, prop_name)
				TYPE_STRING:
					_add_string_property(prop_name, prop_value, prop_name)
				TYPE_VECTOR2:
					_add_vector2_readonly(prop_name, prop_value)
				TYPE_VECTOR3:
					_add_vector3_readonly(prop_name, prop_value)
				TYPE_COLOR:
					_add_color_readonly(prop_name, prop_value)
				_:
					_add_readonly_property(prop_name, str(prop_value))


func _add_script_button(script: Script) -> void:
	if not properties_container or not script:
		return
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	
	var label = Label.new()
	label.text = "Script:"
	label.custom_minimum_size.x = 80
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	hbox.add_child(label)
	
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
	
	# Also try to open directly in the ScriptViewerUI if available
	if ScriptViewerUI and ScriptViewerUI.instance:
		ScriptViewerUI.instance.open_script(script_path)


func _add_section_header(title: String) -> void:
	if not properties_container:
		return
	
	var header = Label.new()
	header.text = title
	header.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
	header.add_theme_font_size_override("font_size", 14)
	properties_container.add_child(header)
	
	var sep = HSeparator.new()
	properties_container.add_child(sep)


func _add_readonly_property(label_text: String, value: String) -> void:
	if not properties_container:
		return
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	
	var label = Label.new()
	label.text = label_text + ":"
	label.custom_minimum_size.x = 80
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	hbox.add_child(label)
	
	var value_label = Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
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
	label.text = label_text + ":"
	label.custom_minimum_size.x = 80
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
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
	label.text = label_text + ":"
	label.custom_minimum_size.x = 80
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	hbox.add_child(label)
	
	var spinbox = SpinBox.new()
	spinbox.value = value
	spinbox.step = 0.01
	spinbox.min_value = -10000
	spinbox.max_value = 10000
	spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spinbox.value_changed.connect(func(val): _on_property_changed(prop_name, val))
	hbox.add_child(spinbox)
	
	properties_container.add_child(hbox)
	_property_controls[prop_name] = spinbox


func _add_int_property(label_text: String, value: int, prop_name: String) -> void:
	if not properties_container:
		return
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	
	var label = Label.new()
	label.text = label_text + ":"
	label.custom_minimum_size.x = 80
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	hbox.add_child(label)
	
	var spinbox = SpinBox.new()
	spinbox.value = value
	spinbox.step = 1
	spinbox.min_value = -10000
	spinbox.max_value = 10000
	spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spinbox.value_changed.connect(func(val): _on_property_changed(prop_name, int(val)))
	hbox.add_child(spinbox)
	
	properties_container.add_child(hbox)
	_property_controls[prop_name] = spinbox


func _add_string_property(label_text: String, value: String, prop_name: String) -> void:
	if not properties_container:
		return
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	
	var label = Label.new()
	label.text = label_text + ":"
	label.custom_minimum_size.x = 80
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	hbox.add_child(label)
	
	var line_edit = LineEdit.new()
	line_edit.text = value
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit.text_submitted.connect(func(text): _on_property_changed(prop_name, text))
	hbox.add_child(line_edit)
	
	properties_container.add_child(hbox)
	_property_controls[prop_name] = line_edit


func _add_vector3_property(label_text: String, value: Vector3, prop_name: String) -> void:
	if not properties_container:
		return
	
	var vbox = VBoxContainer.new()
	
	var label = Label.new()
	label.text = label_text + ":"
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	vbox.add_child(label)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	
	var container_x = _create_component_spinbox("X", value.x, Color(1.0, 0.4, 0.4))
	var container_y = _create_component_spinbox("Y", value.y, Color(0.4, 1.0, 0.4))
	var container_z = _create_component_spinbox("Z", value.z, Color(0.4, 0.6, 1.0))
	
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


func _add_vector3_readonly(label_text: String, value: Vector3) -> void:
	var text = "(%.2f, %.2f, %.2f)" % [value.x, value.y, value.z]
	_add_readonly_property(label_text, text)


func _add_vector2_readonly(label_text: String, value: Vector2) -> void:
	var text = "(%.2f, %.2f)" % [value.x, value.y]
	_add_readonly_property(label_text, text)


func _add_color_readonly(label_text: String, value: Color) -> void:
	if not properties_container:
		return
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	
	var label = Label.new()
	label.text = label_text + ":"
	label.custom_minimum_size.x = 80
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	hbox.add_child(label)
	
	var color_rect = ColorRect.new()
	color_rect.color = value
	color_rect.custom_minimum_size = Vector2(60, 20)
	hbox.add_child(color_rect)
	
	var hex_label = Label.new()
	hex_label.text = "#" + value.to_html(false)
	hex_label.add_theme_font_size_override("font_size", 11)
	hbox.add_child(hex_label)
	
	properties_container.add_child(hbox)


func _create_component_spinbox(component_label: String, value: float, color: Color) -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var label = Label.new()
	label.text = component_label
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	label.custom_minimum_size.x = 14
	hbox.add_child(label)
	
	var spinbox = SpinBox.new()
	spinbox.value = value
	spinbox.step = 0.01
	spinbox.min_value = -10000
	spinbox.max_value = 10000
	spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spinbox.custom_minimum_size.x = 60
	hbox.add_child(spinbox)
	
	# Store reference for retrieval
	hbox.set_meta("spinbox", spinbox)
	
	return hbox


func _on_property_changed(prop_name: String, new_value: Variant) -> void:
	if not _current_node:
		return
	
	# Apply the change to the node
	if prop_name in _current_node:
		_current_node.set(prop_name, new_value)
		print("NodeInspectorUI: Changed ", _current_node.name, ".", prop_name, " = ", new_value)
		property_changed.emit(_current_node.get_path(), prop_name, new_value)
