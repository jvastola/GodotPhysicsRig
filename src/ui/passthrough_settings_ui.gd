extends Control

signal close_requested

## Passthrough Settings UI
## Controls OpenXR Meta passthrough filters and modes

# Mode buttons
@onready var mode_full_btn: Button = $Panel/VBoxContainer/ModeSection/ModeButtons/FullBtn
@onready var mode_geometry_btn: Button = $Panel/VBoxContainer/ModeSection/ModeButtons/GeometryBtn
@onready var mode_hole_punch_btn: Button = $Panel/VBoxContainer/ModeSection/ModeButtons/HolePunchBtn

# Filter selection
@onready var filter_option: OptionButton = $Panel/VBoxContainer/FilterSection/FilterOption

# BCS sliders
@onready var bcs_section: VBoxContainer = $Panel/VBoxContainer/BCSSection
@onready var brightness_slider: HSlider = $Panel/VBoxContainer/BCSSection/Brightness/HSlider
@onready var brightness_value: Label = $Panel/VBoxContainer/BCSSection/Brightness/Value
@onready var contrast_slider: HSlider = $Panel/VBoxContainer/BCSSection/Contrast/HSlider
@onready var contrast_value: Label = $Panel/VBoxContainer/BCSSection/Contrast/Value
@onready var saturation_slider: HSlider = $Panel/VBoxContainer/BCSSection/Saturation/HSlider
@onready var saturation_value: Label = $Panel/VBoxContainer/BCSSection/Saturation/Value

# LUT weight slider
@onready var lut_section: VBoxContainer = $Panel/VBoxContainer/LUTSection
@onready var lut_weight_slider: HSlider = $Panel/VBoxContainer/LUTSection/LUTWeight/HSlider
@onready var lut_weight_value: Label = $Panel/VBoxContainer/LUTSection/LUTWeight/Value

# Edge color sliders
@onready var edge_section: VBoxContainer = $Panel/VBoxContainer/EdgeSection
@onready var edge_r_slider: HSlider = $Panel/VBoxContainer/EdgeSection/EdgeR/HSlider
@onready var edge_r_value: Label = $Panel/VBoxContainer/EdgeSection/EdgeR/Value
@onready var edge_g_slider: HSlider = $Panel/VBoxContainer/EdgeSection/EdgeG/HSlider
@onready var edge_g_value: Label = $Panel/VBoxContainer/EdgeSection/EdgeG/Value
@onready var edge_b_slider: HSlider = $Panel/VBoxContainer/EdgeSection/EdgeB/HSlider
@onready var edge_b_value: Label = $Panel/VBoxContainer/EdgeSection/EdgeB/Value
@onready var edge_a_slider: HSlider = $Panel/VBoxContainer/EdgeSection/EdgeA/HSlider
@onready var edge_a_value: Label = $Panel/VBoxContainer/EdgeSection/EdgeA/Value

# Opacity slider
@onready var opacity_section: VBoxContainer = $Panel/VBoxContainer/OpacitySection
@onready var opacity_slider: HSlider = $Panel/VBoxContainer/OpacitySection/Opacity/HSlider
@onready var opacity_value: Label = $Panel/VBoxContainer/OpacitySection/Opacity/Value

# Status
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel
@onready var close_button: Button = $Panel/VBoxContainer/TitleRow/CloseButton

# State
var fb_passthrough = null
var xr_interface: XRInterface = null
var world_environment: WorldEnvironment = null
var passthrough_available: bool = false

# Current settings
var brightness_contrast_saturation: Vector3 = Vector3(0.0, 1.0, 1.0)
var edge_color: Color = Color(1.0, 1.0, 1.0, 0.5)
var current_mode: int = 0  # 0=Full, 1=Geometry, 2=GeometryHP
var current_filter: int = 0  # Maps to PASSTHROUGH_FILTER_* enum

# Filter enum constants (from OpenXRFbPassthroughExtensionWrapper)
const FILTER_DISABLED = 0
const FILTER_COLOR_MAP = 1
const FILTER_MONO_MAP = 2
const FILTER_BCS = 3
const FILTER_COLOR_LUT = 4
const FILTER_INTERPOLATED_LUT = 5


func _ready() -> void:
	await get_tree().process_frame
	_init_passthrough()
	_setup_ui()
	_update_section_visibility()
	
	if close_button:
		close_button.pressed.connect(func(): close_requested.emit())


func _init_passthrough() -> void:
	# Get XR interface
	xr_interface = XRServer.find_interface("OpenXR")
	
	# Try to get the FB passthrough extension wrapper
	if Engine.has_singleton("OpenXRFbPassthroughExtensionWrapper"):
		fb_passthrough = Engine.get_singleton("OpenXRFbPassthroughExtensionWrapper")
		passthrough_available = fb_passthrough != null
	else:
		passthrough_available = false
	
	# Find world environment
	var root := get_tree().root
	if root:
		var env_node := root.find_child("WorldEnvironment", true, false)
		if env_node and env_node is WorldEnvironment:
			world_environment = env_node
	
	_update_status()


func _setup_ui() -> void:
	# Set up filter options
	if filter_option:
		filter_option.clear()
		filter_option.add_item("Disabled", FILTER_DISABLED)
		filter_option.add_item("Color Map", FILTER_COLOR_MAP)
		filter_option.add_item("Mono Map", FILTER_MONO_MAP)
		filter_option.add_item("Brightness/Contrast/Saturation", FILTER_BCS)
		filter_option.add_item("Color LUT", FILTER_COLOR_LUT)
		filter_option.add_item("Interpolated Color LUT", FILTER_INTERPOLATED_LUT)
		filter_option.selected = 0
	
	# Set default slider values
	if brightness_slider:
		brightness_slider.value = brightness_contrast_saturation.x
		brightness_value.text = "%.2f" % brightness_contrast_saturation.x
	if contrast_slider:
		contrast_slider.value = brightness_contrast_saturation.y
		contrast_value.text = "%.2f" % brightness_contrast_saturation.y
	if saturation_slider:
		saturation_slider.value = brightness_contrast_saturation.z
		saturation_value.text = "%.2f" % brightness_contrast_saturation.z
	
	if lut_weight_slider:
		lut_weight_slider.value = 0.5
		lut_weight_value.text = "0.50"
	
	if edge_r_slider:
		edge_r_slider.value = edge_color.r
		edge_r_value.text = "%.2f" % edge_color.r
	if edge_g_slider:
		edge_g_slider.value = edge_color.g
		edge_g_value.text = "%.2f" % edge_color.g
	if edge_b_slider:
		edge_b_slider.value = edge_color.b
		edge_b_value.text = "%.2f" % edge_color.b
	if edge_a_slider:
		edge_a_slider.value = edge_color.a
		edge_a_value.text = "%.2f" % edge_color.a
	
	if opacity_slider:
		opacity_slider.value = 1.0
		opacity_value.text = "1.00"
	
	# Disable controls if passthrough not available
	if not passthrough_available:
		_set_controls_enabled(false)


func _set_controls_enabled(enabled: bool) -> void:
	if mode_full_btn:
		mode_full_btn.disabled = not enabled
	if mode_geometry_btn:
		mode_geometry_btn.disabled = not enabled
	if mode_hole_punch_btn:
		mode_hole_punch_btn.disabled = not enabled
	if filter_option:
		filter_option.disabled = not enabled
	if brightness_slider:
		brightness_slider.editable = enabled
	if contrast_slider:
		contrast_slider.editable = enabled
	if saturation_slider:
		saturation_slider.editable = enabled
	if lut_weight_slider:
		lut_weight_slider.editable = enabled
	if edge_r_slider:
		edge_r_slider.editable = enabled
	if edge_g_slider:
		edge_g_slider.editable = enabled
	if edge_b_slider:
		edge_b_slider.editable = enabled
	if edge_a_slider:
		edge_a_slider.editable = enabled
	if opacity_slider:
		opacity_slider.editable = enabled


func _update_section_visibility() -> void:
	# Show/hide sections based on current filter
	if bcs_section:
		bcs_section.visible = (current_filter == FILTER_BCS)
	if lut_section:
		lut_section.visible = (current_filter == FILTER_COLOR_LUT or current_filter == FILTER_INTERPOLATED_LUT)
	if edge_section:
		edge_section.visible = true  # Edge is always available
	if opacity_section:
		opacity_section.visible = true  # Opacity is always available


func _update_status() -> void:
	if not status_label:
		return
	
	if not passthrough_available:
		status_label.text = "⚠️ Passthrough not available"
		status_label.modulate = Color.YELLOW
	elif not xr_interface or not xr_interface.is_initialized():
		status_label.text = "⏳ Waiting for XR session..."
		status_label.modulate = Color.ORANGE
	else:
		var mode_names := ["Full", "Geometry", "Geometry+HP"]
		var filter_names := ["Disabled", "Color Map", "Mono Map", "BCS", "LUT", "Interp LUT"]
		status_label.text = "✅ Mode: %s | Filter: %s" % [mode_names[current_mode], filter_names[current_filter]]
		status_label.modulate = Color.GREEN


# === Mode Buttons ===

func _on_full_btn_pressed() -> void:
	current_mode = 0
	_enable_mode_full()
	_update_status()


func _on_geometry_btn_pressed() -> void:
	current_mode = 1
	_enable_mode_geometry()
	_update_status()


func _on_hole_punch_btn_pressed() -> void:
	current_mode = 2
	_enable_mode_geometry_hp()
	_update_status()


func _enable_mode_full() -> void:
	if not xr_interface:
		return
	get_viewport().transparent_bg = true
	if world_environment and world_environment.environment:
		world_environment.environment.background_mode = Environment.BG_COLOR
		world_environment.environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND


func _enable_mode_geometry() -> void:
	if not xr_interface:
		return
	get_viewport().transparent_bg = true
	if world_environment and world_environment.environment:
		world_environment.environment.background_mode = Environment.BG_COLOR
		world_environment.environment.background_color = Color(0.3, 0.3, 0.3, 0.0)
	xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE


func _enable_mode_geometry_hp() -> void:
	if not xr_interface:
		return
	get_viewport().transparent_bg = false
	if world_environment and world_environment.environment:
		world_environment.environment.background_mode = Environment.BG_SKY
	xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE


# === Filter Selection ===

func _on_filter_option_item_selected(index: int) -> void:
	current_filter = filter_option.get_item_id(index)
	_apply_filter()
	_update_section_visibility()
	_update_status()


func _apply_filter() -> void:
	if not fb_passthrough:
		return
	
	# The extension wrapper uses set_passthrough_filter(filter_type)
	if fb_passthrough.has_method("set_passthrough_filter"):
		fb_passthrough.set_passthrough_filter(current_filter)


# === BCS Sliders ===

func _on_brightness_slider_value_changed(value: float) -> void:
	brightness_contrast_saturation.x = value
	if brightness_value:
		brightness_value.text = "%.2f" % value
	_apply_bcs()


func _on_contrast_slider_value_changed(value: float) -> void:
	brightness_contrast_saturation.y = value
	if contrast_value:
		contrast_value.text = "%.2f" % value
	_apply_bcs()


func _on_saturation_slider_value_changed(value: float) -> void:
	brightness_contrast_saturation.z = value
	if saturation_value:
		saturation_value.text = "%.2f" % value
	_apply_bcs()


func _apply_bcs() -> void:
	if fb_passthrough and fb_passthrough.has_method("set_brightness_contrast_saturation"):
		fb_passthrough.set_brightness_contrast_saturation(
			brightness_contrast_saturation.x,
			brightness_contrast_saturation.y,
			brightness_contrast_saturation.z
		)


# === LUT Weight Slider ===

func _on_lut_weight_slider_value_changed(value: float) -> void:
	if lut_weight_value:
		lut_weight_value.text = "%.2f" % value
	# Note: LUT application requires pre-created OpenXRMetaPassthroughColorLut objects
	# This would need to be set up with actual LUT images
	if fb_passthrough and fb_passthrough.has_method("set_color_lut"):
		# Placeholder - actual LUT object would need to be created from an image
		pass


# === Edge Color Sliders ===

func _on_edge_r_slider_value_changed(value: float) -> void:
	edge_color.r = value
	if edge_r_value:
		edge_r_value.text = "%.2f" % value
	_apply_edge_color()


func _on_edge_g_slider_value_changed(value: float) -> void:
	edge_color.g = value
	if edge_g_value:
		edge_g_value.text = "%.2f" % value
	_apply_edge_color()


func _on_edge_b_slider_value_changed(value: float) -> void:
	edge_color.b = value
	if edge_b_value:
		edge_b_value.text = "%.2f" % value
	_apply_edge_color()


func _on_edge_a_slider_value_changed(value: float) -> void:
	edge_color.a = value
	if edge_a_value:
		edge_a_value.text = "%.2f" % value
	_apply_edge_color()


func _apply_edge_color() -> void:
	if fb_passthrough and fb_passthrough.has_method("set_edge_color"):
		fb_passthrough.set_edge_color(edge_color)


# === Opacity Slider ===

func _on_opacity_slider_value_changed(value: float) -> void:
	if opacity_value:
		opacity_value.text = "%.2f" % value
	if fb_passthrough and fb_passthrough.has_method("set_texture_opacity_factor"):
		fb_passthrough.set_texture_opacity_factor(value)
