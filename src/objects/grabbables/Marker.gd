# Marker - A grabbable pen that draws lines like VRCMarker
# Based on VRCMarker implementation
extends Grabbable
class_name Marker

# Configuration
@export var marker_mesh: MeshInstance3D
@export var marker_trail: Node
@export var marker_sync: Node
@export var erase: Node

@export var color_texture_wrap_mode: int = 0  # TextureWrapMode.CLAMP
@export var color_texture_property: String = "_DetailAlbedoMap"

# State
var _cached_update_rate: float = 0.0
const RemoteUpdateRateMult: float = 2.0  # fix for drawing more lines than synced lines
var _prev_trigger_pressed: bool = false

# Color texture
var _color_texture: Texture2D = null


func _ready() -> void:
	# Call parent Grabbable._ready() for standard grabbable setup
	# Call parent Grabbable._ready() for standard grabbable setup
	super._ready()

	# Auto-find child nodes if not assigned
	if not marker_trail:
		marker_trail = get_node_or_null("MarkerTrail")
	if not marker_sync:
		marker_sync = get_node_or_null("MarkerSync")
	if not erase:
		erase = get_node_or_null("Erase")
	
	_cached_update_rate = marker_trail.update_rate if marker_trail else 0.03
	if marker_trail:
		marker_trail.update_rate = _cached_update_rate * RemoteUpdateRateMult
	
	set_color()
	
	# Connect to grab/release signals
	grabbed.connect(_on_pen_grabbed)
	released.connect(_on_pen_released)
	
	# Set up erase interaction
	if is_instance_valid(erase):
		# In Godot, we don't have direct ownership checking like VRC
		# We'll just enable interactive for now
		erase.disable_interactive = false
	
	print("Marker: Ready")


func _on_pen_grabbed(_hand: RigidBody3D) -> void:
	"""Called when the pen is grabbed"""
	if marker_trail:
		marker_trail.update_rate = _cached_update_rate
		marker_trail.is_local = true
	
	# Set ownership
	if is_instance_valid(marker_sync):
		# In Godot, we don't have direct ownership setting like VRC
		# We'll handle this through the network manager
		pass
	
	if is_instance_valid(erase):
		erase.disable_interactive = false


func _on_pen_released() -> void:
	"""Called when the pen is released"""
	if marker_trail:
		marker_trail.stop_writing()
		if marker_sync and marker_sync.has_method("sync_marker"):
			marker_sync.sync_marker()
	
	if marker_trail:
		marker_trail.update_rate = _cached_update_rate * RemoteUpdateRateMult
		marker_trail.is_local = false
		if marker_trail.has_method("reset_sync_lines"):
			marker_trail.reset_sync_lines()


func _physics_process(delta: float) -> void:
	# Call parent physics process for grabbable functionality
	super._physics_process(delta)
	
	# Check if grabbed (either by VR hand or desktop)
	if not is_grabbed:
		return
	
	# Read trigger input
	var trigger_value: float = 0.0
	
	# Fallback to InputMap for desktop
	if InputMap.has_action("trigger_click"):
		trigger_value = Input.get_action_strength("trigger_click")
	
	var trigger_pressed = trigger_value > 0.1
	
	# Debug logging
	if trigger_pressed and not _prev_trigger_pressed:
		print("Marker: Trigger pressed, starting writing")
	elif not trigger_pressed and _prev_trigger_pressed:
		print("Marker: Trigger released, stopping writing")
	
	# Handle trigger state changes
	if trigger_pressed and not _prev_trigger_pressed:
		# Trigger just pressed - start writing
		if marker_trail and marker_trail.has_method("start_writing"):
			marker_trail.start_writing()
	elif not trigger_pressed and _prev_trigger_pressed:
		# Trigger just released - stop writing
		if marker_trail and marker_trail.has_method("stop_writing"):
			marker_trail.stop_writing()
		if marker_sync and marker_sync.has_method("sync_marker"):
			marker_sync.sync_marker()
	
	_prev_trigger_pressed = trigger_pressed


func start_writing_remote() -> void:
	"""Called remotely to start writing"""
	if marker_sync:
		marker_sync.state = 0
		if marker_sync.has_method("sync_marker"):
			marker_sync.sync_marker()


func set_color() -> void:
	"""Set the color of the marker"""
	_create_color_texture()


func _create_color_texture() -> void:
	"""Create a color texture for the marker"""
	if not _color_texture:
		_color_texture = ImageTexture.new()
	
	var image = Image.create(1, 32, false, Image.FORMAT_RGBA8)
	
	if marker_trail and marker_trail.trail_type == 0:
		# Solid color
		for i in range(32):
			image.set_pixel(0, i, marker_trail.color)
	else:
		# Gradient
		if marker_trail and marker_trail.gradient:
			for i in range(32):
				var t = float(i) / 32.0
				image.set_pixel(0, i, marker_trail.gradient.sample(t))
	
	_color_texture = ImageTexture.create_from_image(image)
	
	# Apply to material
	if marker_mesh and marker_mesh is MeshInstance3D:
		var material = marker_mesh.material_override
		if material is ShaderMaterial:
			material.set_shader_parameter("_DetailAlbedoMap", _color_texture)
		elif material is StandardMaterial3D:
			material.albedo_texture = _color_texture


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Clean up texture
		if _color_texture:
			_color_texture = null
