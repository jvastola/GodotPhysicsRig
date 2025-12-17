class_name BlockLibraryUI
extends PanelContainer

## UI for managing the block texture library and reference block settings

static var instance: BlockLibraryUI = null

var _reference_block: ReferenceBlock = null
var _color_picker_ui: ColorPickerUI = null

# UI elements (created dynamically)
var paint_mode_dropdown: OptionButton
var grid_size_spinbox: SpinBox
var save_button: Button
var fill_button: Button
var clear_button: Button
var block_list_container: VBoxContainer
var scroll_container: ScrollContainer
var status_label: Label
var selected_label: Label


func _ready() -> void:
	instance = self
	add_to_group("block_library_ui")
	
	# Set minimum size to prevent cutoff
	custom_minimum_size = Vector2(280, 400)
	
	_build_ui()
	call_deferred("_find_reference_block")
	call_deferred("_find_color_picker")
	call_deferred("_populate_block_list")


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _build_ui() -> void:
	# Clear any existing children
	for child in get_children():
		child.queue_free()
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)
	
	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 4)
	margin.add_child(main_vbox)
	
	# Title
	var title := Label.new()
	title.text = "🧱 Block Library"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	main_vbox.add_child(title)
	
	main_vbox.add_child(HSeparator.new())
	
	# === PAINT SETTINGS - Compact ===
	var settings_grid := GridContainer.new()
	settings_grid.columns = 2
	settings_grid.add_theme_constant_override("h_separation", 8)
	settings_grid.add_theme_constant_override("v_separation", 4)
	main_vbox.add_child(settings_grid)
	
	# Mode
	var mode_label := Label.new()
	mode_label.text = "Mode:"
	settings_grid.add_child(mode_label)
	
	paint_mode_dropdown = OptionButton.new()
	paint_mode_dropdown.add_item("Single")
	paint_mode_dropdown.add_item("All Faces")
	paint_mode_dropdown.add_item("Sides")
	paint_mode_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paint_mode_dropdown.item_selected.connect(_on_paint_mode_changed)
	settings_grid.add_child(paint_mode_dropdown)
	
	# Grid
	var grid_label := Label.new()
	grid_label.text = "Grid:"
	settings_grid.add_child(grid_label)
	
	grid_size_spinbox = SpinBox.new()
	grid_size_spinbox.min_value = 1
	grid_size_spinbox.max_value = 16
	grid_size_spinbox.value = 4
	grid_size_spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_size_spinbox.value_changed.connect(_on_grid_size_changed)
	settings_grid.add_child(grid_size_spinbox)
	
	# Action Buttons Row
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 4)
	main_vbox.add_child(action_row)
	
	fill_button = Button.new()
	fill_button.text = "Fill"
	fill_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill_button.pressed.connect(_on_fill_pressed)
	action_row.add_child(fill_button)
	
	clear_button = Button.new()
	clear_button.text = "Clear"
	clear_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_button.pressed.connect(_on_clear_pressed)
	action_row.add_child(clear_button)
	
	save_button = Button.new()
	save_button.text = "💾 Save"
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(_on_save_pressed)
	action_row.add_child(save_button)
	
	main_vbox.add_child(HSeparator.new())
	
	# === LIBRARY SECTION ===
	var lib_label := Label.new()
	lib_label.text = "Saved Blocks"
	lib_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	main_vbox.add_child(lib_label)
	
	# Scrollable block list
	scroll_container = ScrollContainer.new()
	scroll_container.custom_minimum_size = Vector2(0, 120)
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll_container)
	
	block_list_container = VBoxContainer.new()
	block_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block_list_container.add_theme_constant_override("separation", 2)
	scroll_container.add_child(block_list_container)
	
	main_vbox.add_child(HSeparator.new())
	
	# Status Section
	selected_label = Label.new()
	selected_label.text = "Active: None"
	selected_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	selected_label.add_theme_font_size_override("font_size", 12)
	main_vbox.add_child(selected_label)
	
	status_label = Label.new()
	status_label.text = ""
	status_label.add_theme_font_size_override("font_size", 11)
	main_vbox.add_child(status_label)


func _find_reference_block() -> void:
	if ReferenceBlock.instance:
		_reference_block = ReferenceBlock.instance
	else:
		var blocks := get_tree().get_nodes_in_group("reference_block")
		if blocks.size() > 0:
			_reference_block = blocks[0] as ReferenceBlock
	
	if _reference_block:
		if not _reference_block.block_saved.is_connected(_on_block_saved):
			_reference_block.block_saved.connect(_on_block_saved)
		if not _reference_block.block_selected.is_connected(_on_block_selected_signal):
			_reference_block.block_selected.connect(_on_block_selected_signal)
		_sync_ui_to_block()


func _find_color_picker() -> void:
	if ColorPickerUI.instance:
		_color_picker_ui = ColorPickerUI.instance
	else:
		var pickers := get_tree().get_nodes_in_group("color_picker_ui")
		if pickers.size() > 0:
			_color_picker_ui = pickers[0] as ColorPickerUI


func _sync_ui_to_block() -> void:
	if not _reference_block:
		return
	if paint_mode_dropdown:
		paint_mode_dropdown.selected = _reference_block.get_paint_mode()
	if grid_size_spinbox:
		grid_size_spinbox.value = _reference_block.get_grid_subdivisions()
	_update_selected_label()


func _populate_block_list() -> void:
	if not block_list_container:
		return
	
	# Clear existing items
	for child in block_list_container.get_children():
		child.queue_free()
	
	if not _reference_block:
		_find_reference_block()
	
	if not _reference_block:
		var empty_label := Label.new()
		empty_label.text = "(No reference block)"
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		block_list_container.add_child(empty_label)
		return
	
	var names := _reference_block.get_library_names()
	if names.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(Empty - save a block)"
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		block_list_container.add_child(empty_label)
		return
	
	for block_name in names:
		_add_block_row(block_name)


func _add_block_row(block_name: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	
	# Select button (main block button)
	var select_btn := Button.new()
	select_btn.text = "📦 " + block_name
	select_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	select_btn.pressed.connect(_on_block_select.bind(block_name))
	row.add_child(select_btn)
	
	# Delete button
	var delete_btn := Button.new()
	delete_btn.text = "✕"
	delete_btn.custom_minimum_size = Vector2(30, 0)
	delete_btn.pressed.connect(_on_block_delete.bind(block_name))
	row.add_child(delete_btn)
	
	block_list_container.add_child(row)


func _on_block_select(block_name: String) -> void:
	print("BlockLibraryUI: Selecting block '%s'" % block_name)
	if not _reference_block:
		_find_reference_block()
		if not _reference_block:
			_set_status("Reference block not found", true)
			return
	_reference_block.select_block(block_name)
	_reference_block.load_from_library(block_name)
	_update_selected_label()
	_set_status("Selected: %s" % block_name)


func _on_block_delete(block_name: String) -> void:
	print("BlockLibraryUI: Deleting block '%s'" % block_name)
	if not _reference_block:
		_find_reference_block()
		if not _reference_block:
			_set_status("Reference block not found", true)
			return
	_reference_block.delete_from_library(block_name)
	_populate_block_list()
	_update_selected_label()
	_set_status("Deleted: %s" % block_name)


func _update_selected_label() -> void:
	if not selected_label:
		return
	if not _reference_block:
		selected_label.text = "Active: None"
		return
	var selected := _reference_block.get_selected_block()
	if selected.is_empty():
		selected_label.text = "Active: None"
	else:
		selected_label.text = "Active: %s" % selected


func _set_status(text: String, is_error: bool = false) -> void:
	if not status_label:
		return
	status_label.text = text
	var color := Color(0.7, 0.9, 0.7) if not is_error else Color(1.0, 0.6, 0.6)
	status_label.add_theme_color_override("font_color", color)


func _on_paint_mode_changed(index: int) -> void:
	if not _reference_block:
		_set_status("Reference block not found", true)
		return
	_reference_block.set_paint_mode(index as ReferenceBlock.PaintMode)
	var modes := ["Single Cell", "All Faces", "All Sides"]
	_set_status("Mode: %s" % modes[index])


func _on_grid_size_changed(value: float) -> void:
	if not _reference_block:
		_set_status("Reference block not found", true)
		return
	_reference_block.set_grid_subdivisions(int(value))
	_set_status("Grid: %dx%d" % [int(value), int(value)])


func _on_fill_pressed() -> void:
	if not _reference_block:
		_set_status("Reference block not found", true)
		return
	var color := Color.WHITE
	if _color_picker_ui:
		color = _color_picker_ui.get_current_color()
	_reference_block.fill_all_faces(color)
	_set_status("Filled block")


func _on_clear_pressed() -> void:
	if not _reference_block:
		_set_status("Reference block not found", true)
		return
	_reference_block.fill_all_faces(Color(0.7, 0.7, 0.7, 1.0))
	_set_status("Cleared block")


func _on_save_pressed() -> void:
	if not _reference_block:
		_set_status("Reference block not found", true)
		return
	var name := _reference_block.save_to_library()
	_set_status("Saved: %s" % name)


func _on_block_saved(_block_name: String, _texture: ImageTexture) -> void:
	_populate_block_list()


func _on_block_selected_signal(_block_name: String) -> void:
	_update_selected_label()
