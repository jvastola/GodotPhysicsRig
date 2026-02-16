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

# Docking state
var _is_pinned: bool = false
var _dock_mode: String = "" # "", "left", "right", "head"
var _dock_anchor_offset: Vector3 = Vector3.ZERO  # Offset relative to anchor (controller/camera)
var _dock_anchor_rotation: Basis = Basis.IDENTITY  # Stored rotation relative to anchor
var _original_grab_enabled: bool = true
var _base_scale: Vector3 = Vector3.ONE
var _target_scale: float = 1.0
var _current_scale_factor: float = 1.0  # Tracked separately so basis operations don't corrupt it
var _player_scale_multiplier: float = 1.0

func _ready() -> void:
	# We don't need to be in "pointer_interactable" group specifically if the children proxy to us
	# but it doesn't hurt.
	add_to_group("pointer_interactable")
	
	_base_scale = scale
	_update_player_scale()
	
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
		if _window_bar_ui.has_signal("pin_pressed"):
			_window_bar_ui.pin_pressed.connect(_on_pin_pressed)
		if _window_bar_ui.has_signal("dock_left_pressed"):
			_window_bar_ui.dock_left_pressed.connect(_on_dock_left_pressed)
		if _window_bar_ui.has_signal("dock_right_pressed"):
			_window_bar_ui.dock_right_pressed.connect(_on_dock_right_pressed)
		if _window_bar_ui.has_signal("dock_head_pressed"):
			_window_bar_ui.dock_head_pressed.connect(_on_dock_head_pressed)
		if _window_bar_ui.has_signal("bring_close_pressed"):
			_window_bar_ui.bring_close_pressed.connect(_on_bring_close_pressed)
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
	if _is_pinned or not pointer:
		return
	
	var pointer_forward: Vector3 = -pointer.global_transform.basis.z.normalized()
	var pointer_origin: Vector3 = pointer.global_transform.origin
	var new_position: Vector3 = pointer_origin + pointer_forward * new_distance
	global_position = new_position
	
	var direction: Vector3 = (global_position - pointer_origin).normalized()
	if direction.length_squared() > 0.001:
		var look_away: Vector3 = global_position + direction
		look_at(look_away, Vector3.UP)
	
	# Update anchor offset instead of clearing dock mode
	_update_dock_anchor_offset()

func pointer_grab_set_scale(_new_scale: float) -> void:
	pass

func pointer_grab_set_rotation(pointer: Node3D, grab_point: Vector3 = Vector3.INF) -> void:
	if _is_pinned or not pointer:
		return
	
	var pointer_origin: Vector3 = pointer.global_transform.origin
	var direction: Vector3 = Vector3.ZERO
	
	if grab_point.is_finite():
		direction = (grab_point - pointer_origin).normalized()
	else:
		direction = (global_position - pointer_origin).normalized()
		
	if direction.length_squared() > 0.001:
		var look_away: Vector3 = global_position + direction
		look_at(look_away, Vector3.UP)
	
	# Update anchor offset instead of clearing dock mode
	_update_dock_anchor_offset()

func pointer_grab_get_distance(pointer: Node3D) -> float:
	if not pointer: return 0.0
	return global_position.distance_to(pointer.global_transform.origin)

func pointer_grab_get_scale() -> float:
	return scale.x


# ============================================================================
# DOCKING AND POSITIONING FUNCTIONS
# ============================================================================

func _on_pin_pressed() -> void:
	_is_pinned = not _is_pinned
	if _window_bar_ui and _window_bar_ui.has_method("set_pin_state"):
		_window_bar_ui.set_pin_state(_is_pinned)
	
	# When unpinned, clear dock mode
	if not _is_pinned:
		_dock_mode = ""
	
	# When pinned, disable grab functionality
	if _chrome_viewport_3d and "grab_delegate" in _chrome_viewport_3d:
		_chrome_viewport_3d.grab_delegate = null if _is_pinned else self

func _on_dock_left_pressed() -> void:
	_dock_to_hand("left")

func _on_dock_right_pressed() -> void:
	_dock_to_hand("right")

func _on_dock_head_pressed() -> void:
	_dock_to_head()

func _on_bring_close_pressed() -> void:
	_bring_close_to_player()


# ---------- helpers ----------

func _get_controller_for_side(side: String) -> Node3D:
	"""Find the XR controller node for the given side."""
	var player = get_tree().get_first_node_in_group("xr_player")
	if not player:
		return null
	var controller_name = "LeftController" if side == "left" else "RightController"
	# Path: PlayerBody/XROrigin3D/<Controller>
	var origin = player.get_node_or_null("PlayerBody/XROrigin3D")
	if origin:
		return origin.get_node_or_null(controller_name)
	return null


func _update_dock_anchor_offset() -> void:
	"""Recalculate and store offset relative to the current anchor.
	   Called after the user repositions the panel while docked."""
	match _dock_mode:
		"left", "right":
			var controller = _get_controller_for_side(_dock_mode)
			if controller:
				# Store offset in controller-local space
				_dock_anchor_offset = controller.global_transform.affine_inverse() * global_position
				_dock_anchor_rotation = controller.global_transform.basis.inverse() * global_transform.basis
		"head":
			var camera = get_viewport().get_camera_3d()
			if camera:
				# Store offset in camera-local space
				_dock_anchor_offset = camera.global_transform.affine_inverse() * global_position
				_dock_anchor_rotation = camera.global_transform.basis.inverse() * global_transform.basis


func _apply_dock_follow(anchor: Node3D) -> void:
	"""Smoothly move toward stored anchor-relative offset."""
	var target_pos = anchor.global_transform * _dock_anchor_offset
	global_position = global_position.lerp(target_pos, 0.15)
	# Reconstruct rotation from stored basis — must orthonormalize to avoid Quaternion error
	var target_basis = (anchor.global_transform.basis * _dock_anchor_rotation).orthonormalized()
	var current_basis = global_transform.basis.orthonormalized()
	global_transform.basis = current_basis.slerp(target_basis, 0.15)


func _face_camera_from(pos: Vector3) -> void:
	"""Orient the panel so its +Z (content) faces the camera/user.
	look_at() makes -Z face the target, so we look at a point AWAY
	from the camera — that makes +Z face toward the camera."""
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	# Direction from camera to panel = "away" from user
	var away_from_camera = (pos - camera.global_position).normalized()
	if away_from_camera.length_squared() > 0.001:
		look_at(pos + away_from_camera, Vector3.UP)


# ---------- docking actions ----------

func _dock_to_hand(side: String) -> void:
	var controller = _get_controller_for_side(side)
	if not controller:
		return
	
	_dock_mode = side
	_is_pinned = false
	
	# Position slightly above and in front of the controller
	var up_offset = controller.global_transform.basis.y * 0.15
	var forward_offset = -controller.global_transform.basis.z * 0.1
	var target_pos = controller.global_position + up_offset + forward_offset
	
	global_position = target_pos
	_target_scale = 0.75  # Slightly smaller than base when docked to hand
	
	_face_camera_from(global_position)
	
	# Store the anchor-relative offset so _process can follow
	_dock_anchor_offset = controller.global_transform.affine_inverse() * global_position
	_dock_anchor_rotation = controller.global_transform.basis.inverse() * global_transform.basis
	
	# Re-enable grab so user can reposition
	if _chrome_viewport_3d and "grab_delegate" in _chrome_viewport_3d:
		_chrome_viewport_3d.grab_delegate = self

func _dock_to_head() -> void:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	
	_dock_mode = "head"
	_is_pinned = false
	
	# Position above and in front of head
	var forward_vector = -camera.global_transform.basis.z
	var up_vector = camera.global_transform.basis.y
	var target_pos = camera.global_position + forward_vector * 0.6 + up_vector * 0.4
	
	global_position = target_pos
	_target_scale = 1.0  # Keep base scale when docked to head
	
	_face_camera_from(global_position)
	
	# Store the anchor-relative offset so _process can follow
	_dock_anchor_offset = camera.global_transform.affine_inverse() * global_position
	_dock_anchor_rotation = camera.global_transform.basis.inverse() * global_transform.basis
	
	# Re-enable grab so user can reposition
	if _chrome_viewport_3d and "grab_delegate" in _chrome_viewport_3d:
		_chrome_viewport_3d.grab_delegate = self

func _bring_close_to_player() -> void:
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	
	_dock_mode = ""
	_is_pinned = false
	
	# Bring directly in front at comfortable reading distance
	var forward_vector = -camera.global_transform.basis.z
	var target_pos = camera.global_position + forward_vector * 0.5
	
	global_position = target_pos
	_target_scale = 0.85  # Slightly smaller when brought close
	
	_face_camera_from(global_position)

func _process(delta: float) -> void:
	# Update player scale multiplier
	_update_player_scale()
	
	# Follow the anchor if docked (using stored offsets so grab-repositioning is preserved)
	if _dock_mode != "" and not _is_pinned:
		match _dock_mode:
			"left", "right":
				var controller = _get_controller_for_side(_dock_mode)
				if controller:
					_apply_dock_follow(controller)
			"head":
				var camera = get_viewport().get_camera_3d()
				if camera:
					_apply_dock_follow(camera)
	
	# Smoothly interpolate scale using tracked factor (not from transform,
	# because basis operations like slerp/orthonormalize strip scale)
	var desired_scale = _target_scale * _player_scale_multiplier
	_current_scale_factor = lerp(_current_scale_factor, desired_scale, delta * 5.0)
	scale = _base_scale * _current_scale_factor
	
	# Reset target scale when not in special mode
	if _dock_mode == "" and not _is_pinned:
		_target_scale = 1.0


func _update_player_scale() -> void:
	"""Get the player's hand scale to use as a reference"""
	var player = get_tree().get_first_node_in_group("xr_player")
	if player:
		# Try to get physics hand scale (represents player scale)
		var physics_hand = player.get_node_or_null("PhysicsHandLeft")
		if physics_hand and physics_hand is Node3D:
			_player_scale_multiplier = physics_hand.scale.x
		else:
			# Fallback to player body scale
			var player_body = player.get_node_or_null("PlayerBody")
			if player_body and player_body is Node3D:
				_player_scale_multiplier = player_body.scale.x
			else:
				_player_scale_multiplier = 1.0
	else:
		_player_scale_multiplier = 1.0
