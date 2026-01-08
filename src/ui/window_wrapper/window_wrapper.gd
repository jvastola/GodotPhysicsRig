extends Node3D

# window_wrapper.gd
# Wraps a UIViewport3D with a managed window frame (chrome) using another UIViewport3D for the UI-based bar.
# Acts as the primary "HandPointer" delegate so that grabbing moves the whole hierarchy.

@export var title: String = "Window Board" : set = set_title
@export var content_viewport_scene: PackedScene

# Resources
const VIEWPORT_3D_SCENE = preload("res://src/ui/UIViewport3D.tscn")
const WINDOW_BAR_UI_SCENE = preload("res://src/ui/window_wrapper/WindowBarUI.tscn")

@onready var content_anchor: Node3D = $ContentAnchor
@onready var chrome_anchor: Node3D = $ChromeAnchor
@onready var anim_player: AnimationPlayer = $AnimationPlayer

var _content_instance: Node3D = null
var _chrome_viewport_3d: Node3D = null
var _window_bar_ui: Control = null

func _ready() -> void:
	# We don't need to be in "pointer_interactable" group specifically if the children proxy to us
	# but it doesn't hurt.
	add_to_group("pointer_interactable")
	
	_spawn_content()

func set_title(new_title: String) -> void:
	title = new_title
	if _window_bar_ui and _window_bar_ui.has_method("set_title"):
		_window_bar_ui.set_title(title)

func _spawn_content() -> void:
	if not content_viewport_scene:
		return
		
	# Clear existing content
	for child in content_anchor.get_children():
		child.queue_free()
		
	_content_instance = content_viewport_scene.instantiate()
	content_anchor.add_child(_content_instance)
	
	# Configure the content to NOT handle its own grab
	if _content_instance.get("enable_panel_grab") != null:
		_content_instance.enable_panel_grab = false
		# We DO NOT assign grab_delegate here, so the panel cannot be used to move the window.
	
	# Connect resize signal if available
	if _content_instance.has_signal("panel_resized"):
		if not _content_instance.panel_resized.is_connected(_on_content_resized):
			_content_instance.panel_resized.connect(_on_content_resized)
		
	call_deferred("_setup_chrome")

func _setup_chrome() -> void:
	if not _content_instance:
		return
		
	# Determine size
	var size = Vector2(2.0, 1.5) # Default
	var mesh_instance = _content_instance.get_node_or_null("MeshInstance3D")
	if mesh_instance and mesh_instance.mesh is QuadMesh:
		size = mesh_instance.mesh.size
		
	# 1. Spawn Chrome Viewport (The UI Bar)
	_chrome_viewport_3d = VIEWPORT_3D_SCENE.instantiate()
	_chrome_viewport_3d.name = "ChromeViewport3D"
	if "enable_resize_handles" in _chrome_viewport_3d:
		_chrome_viewport_3d.enable_resize_handles = false
	
	# Configure Chrome 3D settings
	var bar_height_3d = 0.12
	var bar_width_3d = size.x
	
	# Set the UI resolution
	var px_width = bar_width_3d * 1024
	var px_height = bar_height_3d * 1024
	_chrome_viewport_3d.ui_size = Vector2(px_width, px_height)
	
	# Delegate grab to us
	_chrome_viewport_3d.enable_panel_grab = false
	if "grab_delegate" in _chrome_viewport_3d:
		_chrome_viewport_3d.grab_delegate = self
	
	# Add to scene FIRST
	chrome_anchor.add_child(_chrome_viewport_3d)
	
	# Resize mesh
	if _chrome_viewport_3d.has_method("set_panel_size"):
		_chrome_viewport_3d.set_panel_size(Vector2(bar_width_3d, bar_height_3d))
	
	# Position
	var padding = 0.05
	_chrome_viewport_3d.position.y = -size.y * 0.5 - bar_height_3d * 0.5 - padding
	
	# 2. Add the 2D UI
	var subviewport = _chrome_viewport_3d.get_node_or_null("SubViewport")
	if subviewport:
		# Clear default content (e.g. UIPanel from the scene)
		for child in subviewport.get_children():
			child.queue_free()
			
		_window_bar_ui = WINDOW_BAR_UI_SCENE.instantiate()
		subviewport.add_child(_window_bar_ui)
		if _window_bar_ui.has_signal("close_pressed"):
			_window_bar_ui.close_pressed.connect(close_window)
		set_title(title)
		
	# No extra Grip Area needed now!
	
	
func close_window() -> void:
	if anim_player and anim_player.has_animation("close"):
		anim_player.play("close")
		await anim_player.animation_finished
	queue_free()

func _on_content_resized(new_size: Vector2) -> void:
	#"""Update chrome bar when content size changes."""
	# Wait for frame end to ensure content panel has fully applied its new position/anchor
	if not is_inside_tree(): return
	await get_tree().process_frame
	
	if not _chrome_viewport_3d or not _content_instance:
		return
		
	# Keep fixed height for bar, match width
	var bar_height = 0.12
	var bar_width = new_size.x
	var padding = 0.05
	
	# Update size logic (reuse set_panel_size if available for clean update)
	if _chrome_viewport_3d.has_method("set_panel_size"):
		_chrome_viewport_3d.set_panel_size(Vector2(bar_width, bar_height))
	else:
		if "quad_size" in _chrome_viewport_3d:
			_chrome_viewport_3d.quad_size = Vector2(bar_width, bar_height)
			
	# Update position relative to new content center
	# The content panel MOVES its local position to maintain anchor during resize.
	# We must align with its new center.
	
	# Match X position (center alignment)
	_chrome_viewport_3d.position.x = _content_instance.position.x
	
	# Match Y position (Bottom edge attachment)
	# Target Y = Content Center Y - Half Height - Half Bar Height - Padding
	var new_y = _content_instance.position.y - (new_size.y * 0.5) - (bar_height * 0.5) - padding
	_chrome_viewport_3d.position.y = new_y


# ============================================================================
# POINTER GRAB INTERFACE (Direct Implementation)
# ============================================================================

func pointer_grab_set_distance(new_distance: float, pointer: Node3D) -> void:
	if not pointer: return
	
	var pointer_forward: Vector3 = -pointer.global_transform.basis.z.normalized()
	var pointer_origin: Vector3 = pointer.global_transform.origin
	var new_position: Vector3 = pointer_origin + pointer_forward * new_distance
	global_position = new_position
	
	var direction: Vector3 = (global_position - pointer_origin).normalized()
	if direction.length_squared() > 0.001:
		var look_away: Vector3 = global_position + direction
		look_at(look_away, Vector3.UP)

func pointer_grab_set_scale(_new_scale: float) -> void:
	pass

func pointer_grab_set_rotation(pointer: Node3D, grab_point: Vector3 = Vector3.INF) -> void:
	if not pointer: return
	var pointer_origin: Vector3 = pointer.global_transform.origin
	var direction: Vector3 = Vector3.ZERO
	
	if grab_point.is_finite():
		direction = (grab_point - pointer_origin).normalized()
	else:
		direction = (global_position - pointer_origin).normalized()
		
	if direction.length_squared() > 0.001:
		var look_away: Vector3 = global_position + direction
		look_at(look_away, Vector3.UP)

func pointer_grab_get_distance(pointer: Node3D) -> float:
	if not pointer: return 0.0
	return global_position.distance_to(pointer.global_transform.origin)

func pointer_grab_get_scale() -> float:
	return scale.x
