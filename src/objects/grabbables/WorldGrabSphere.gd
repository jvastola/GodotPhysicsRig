extends Grabbable

# Custom World Grab Logic (Anchored)
# Moves the player body to keep the grabbed point anchored to the hand.

@export var move_sensitivity: float = 1.0
@export var invert_grab: bool = false # If true, pulling hand pulls player (fly/climb). If false, pulling hand pulls world (drag).

var _grabbing_hand_ref: RigidBody3D = null
var _player_body: Node3D = null
var _anchor_local: Vector3 = Vector3.ZERO
var _is_anchored: bool = false

# Visuals
var _debug_line: MeshInstance3D
var _debug_anchor: MeshInstance3D

func _ready() -> void:
	super._ready()
	_setup_visuals()

func _setup_visuals() -> void:
	# Line mesh (ImmediateMesh)
	_debug_line = MeshInstance3D.new()
	_debug_line.mesh = ImmediateMesh.new()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 1.0, 1.0, 1.0) # Cyan
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_line.material_override = mat
	_debug_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_debug_line)
	_debug_line.visible = false
	
	# Anchor sphere
	_debug_anchor = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.03
	sphere.height = 0.06
	_debug_anchor.mesh = sphere
	var mat2 = StandardMaterial3D.new()
	mat2.albedo_color = Color(0.0, 1.0, 1.0, 0.8)
	mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_anchor.material_override = mat2
	_debug_anchor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_debug_anchor)
	_debug_anchor.visible = false

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	if is_grabbed and is_instance_valid(grabbing_hand):
		# Check if we should be anchoring
		_process_anchor_logic()
	else:
		if _is_anchored:
			_end_anchor()

func _process_anchor_logic() -> void:
	var controller = _get_controller_from_hand(grabbing_hand)
	var trigger_pressed = false
	
	if controller:
		trigger_pressed = _is_trigger_pressed(controller)
	
	if trigger_pressed:
		if not _is_anchored or _grabbing_hand_ref != grabbing_hand:
			_start_anchor()
		_update_anchor_move()
	else:
		if _is_anchored:
			_end_anchor()

func _get_controller_from_hand(hand: RigidBody3D) -> XRController3D:
	if hand.get("target") and hand.target is XRController3D:
		return hand.target
	return null

func _is_trigger_pressed(controller: XRController3D) -> bool:
	if controller.has_method("get_float"):
		var val = controller.get_float("trigger")
		if val == 0.0:
			val = controller.get_float("trigger_click")
		return val > 0.5
	if controller.has_method("is_button_pressed"):
		# "trigger_click" is usually action 15 in OpenXR but varies
		# It's better to use float
		pass
	return false

func _start_anchor() -> void:
	_grabbing_hand_ref = grabbing_hand
	_is_anchored = true
	
	# Find player body
	if GameManager.player_instance:
		_player_body = GameManager.player_instance.get_node_or_null("PlayerBody")
		
	if not _player_body:
		# Fallback search
		if _grabbing_hand_ref.has_method("get") and _grabbing_hand_ref.get("player_rigidbody"):
			_player_body = _grabbing_hand_ref.player_rigidbody
			
	if _player_body:
		# Store where the hand is relative to the player at moment of grab (Trigger Press)
		_anchor_local = _player_body.to_local(_grabbing_hand_ref.global_position)
		print("WorldGrabSphere: Anchor started (Trigger Pressed).")
		_debug_line.visible = true
		_debug_anchor.visible = true
	else:
		print("WorldGrabSphere: Could not find PlayerBody!")
		_is_anchored = false

func _update_anchor_move() -> void:
	if not _player_body or not is_instance_valid(_grabbing_hand_ref):
		_end_anchor()
		return
		
	# Where should the hand be in world space, if the player hasn't moved relative to anchor?
	var current_anchor_world = _player_body.to_global(_anchor_local)
	
	# Where is the hand actually?
	var hand_pos = _grabbing_hand_ref.global_position
	
	# Visuals update
	_update_visuals(hand_pos, current_anchor_world)
	
	# Diff
	var diff = hand_pos - current_anchor_world
	
	if diff.length_squared() < 0.000001:
		return
		
	# Apply movement
	var move = diff * move_sensitivity
	if invert_grab:
		move *= -1.0
		
	# Move player
	_player_body.global_position += move

func _update_visuals(start: Vector3, end: Vector3) -> void:
	if not _debug_line or not _debug_anchor:
		return
		
	# Anchor sphere at the target anchor point
	_debug_anchor.global_position = end
	
	# Line from hand (start) to anchor (end)
	var im = _debug_line.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	
	# Convert to local space
	var local_start = to_local(start)
	var local_end = to_local(end)
	
	im.surface_add_vertex(local_start)
	im.surface_add_vertex(local_end)
	im.surface_end()

func _end_anchor() -> void:
	_is_anchored = false
	_grabbing_hand_ref = null
	_player_body = null
	_debug_line.visible = false
	_debug_anchor.visible = false
	print("WorldGrabSphere: Anchor ended (Trigger Released).")
