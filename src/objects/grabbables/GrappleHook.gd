extends RigidBody3D

# Grabbable properties (from Grabbable class)
enum GrabMode {
	FREE_GRAB,
	ANCHOR_GRAB
}

@export var grab_mode: GrabMode = GrabMode.ANCHOR_GRAB
@export var grab_anchor_offset: Vector3 = Vector3.ZERO
@export var grab_anchor_rotation: Vector3 = Vector3.ZERO
@export var save_id: String = ""
@export var prototype_scene: PackedScene


var is_grabbed := false
var grabbing_hand: RigidBody3D = null
var original_parent: Node = null
var grab_offset: Vector3 = Vector3.ZERO
var grab_rotation_offset: Quaternion = Quaternion.IDENTITY
var grabbed_collision_shapes: Array = []
var grabbed_mesh_instances: Array = []
var network_manager: Node = null
var is_network_owner: bool = true
var network_update_timer: float = 0.0
const NETWORK_UPDATE_RATE = 0.05

signal grabbed(hand: RigidBody3D)
signal released()

# GrappleHook specific properties
@export var max_distance: float = 20.0
@export var impulse_speed: float = 12.0
@export var winch_speed: float = 4.0
@export var grapple_collision_mask: int = 1
@export var enable_debug_logs: bool = false
@export var hitmarker_radius: float = 0.06
@export var hitmarker_color: Color = Color8(255, 100, 50)

var _is_hooked: bool = false
var _hook_point: Vector3 = Vector3.ZERO
var _hook_object: Node = null
var _hand: RigidBody3D = null
var _controller: Node = null
var _player_body: RigidBody3D = null
var _hitmarker: MeshInstance3D = null
var _use_global_visuals: bool = false
var _global_visuals = null
var _hook_local_offset: Vector3 = Vector3.ZERO
var _rope_cylinder: CylinderMesh = null
var _rope_visual: MeshInstance3D = null
var _rope_line_mesh: ImmediateMesh = null
var _rope_line_instance: MeshInstance3D = null
@export var rope_thickness: float = 0.02
@export var rope_segments: int = 10
@export var rope_sag_factor: float = 0.5
@export var rope_sag_max: float = 2.0
var _rope_container: Node3D = null
var _rope_segments_arr: Array = []
var _last_rope_points: Array = []
@export var rope_start_stiffness: float = 0.05
@export var rope_end_stiffness: float = 0.05
@export var rope_mid_sag_bias: float = 1.0
@export var rope_start_min_length: float = 0.2
@export var rope_color: Color = Color8(255, 200, 80)
@export var use_line_visual: bool = true
var _visuals_pending_parent: bool = false
@export var persist_visuals_across_scenes: bool = true

func _ready() -> void:
	# Setup network sync for grabbable functionality
	_setup_network_sync()
	
	contact_monitor = true
	max_contacts_reported = 10
	add_to_group("grabbable")
	body_entered.connect(_on_collision_entered)

	grabbed.connect(_on_grabbed)
	released.connect(_on_released)

	# Detect global visuals manager (autoload) and use it if available
	_global_visuals = get_node_or_null("/root/GrappleVisuals")
	if _global_visuals:
		_use_global_visuals = true
		_global_visuals.init_segments(rope_segments)
	elif persist_visuals_across_scenes:
		# If the user didn't set GrappleVisuals as an autoload, create it now
		# so visuals persist across scenes for this grapple instance.
		var gv_script = preload("res://src/objects/grabbables/GrappleVisuals.gd")
		if gv_script and not get_node_or_null("/root/GrappleVisuals"):
			var gv = gv_script.new()
			gv.name = "GrappleVisuals"
			# Attach to root deferred so we don't collide with setup
			get_tree().root.call_deferred("add_child", gv)
			_global_visuals = gv
			_use_global_visuals = true
			# init segments after the new node is added to the scene tree so _ready() has run
			_global_visuals.call_deferred("init_segments", rope_segments)
	else:
		# Create a simple world-space hitmarker (a small emissive sphere)
		var sphere = SphereMesh.new()
		# Set radius inside the else scope
		sphere.radius = hitmarker_radius
		var mi = MeshInstance3D.new()
		mi.mesh = sphere
		var mat = StandardMaterial3D.new()
		mat.albedo_color = hitmarker_color
		mat.emission_enabled = true
		mat.emission = hitmarker_color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = mat
		mi.visible = false
		mi.name = "GrappleHitmarker"
		_hitmarker = mi
	# Add hitmarker to the scene tree root so it persists across scene changes
	# Use call_deferred because the scene tree may be busy setting up children when _ready runs.
	# ensure root is available before attempting to attach visuals
	var root = get_tree().root
	if not root:
		# Try again next idle frame; using call_deferred on the node ensures
		# _attach_visuals_to_root will run when the SceneTree is ready.
		call_deferred("_attach_visuals_to_root")
		return
	_attach_visuals_to_root()

	# Create a rope visual as a thin CylinderMesh and a MeshInstance3D
	# Predeclare rope material so it can be used later in segment initialization
	var rope_mat: StandardMaterial3D = null
	if _use_global_visuals:
		# global visuals are managing segments and rope
		pass
	else:
		_rope_cylinder = CylinderMesh.new()
		# Keep the mesh base radius as 1.0 and control final thickness with scale.x/z
		_rope_cylinder.top_radius = 1.0
		_rope_cylinder.bottom_radius = 1.0
		_rope_cylinder.height = 1.0
		_rope_cylinder.radial_segments = 12
		_rope_visual = MeshInstance3D.new()
		_rope_visual.mesh = _rope_cylinder
		rope_mat = StandardMaterial3D.new()
		rope_mat.flags_unshaded = true
		rope_mat.emission_enabled = true
		rope_mat.emission = rope_color
		rope_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rope_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_rope_visual.material_override = rope_mat
		_rope_visual.visible = false
		_rope_visual.name = "GrappleRope"
	# Add rope visual and container (deferred) — single helper prevents duplicate calls
	_attach_visuals_to_root()

	# Create a container for rope segments
	if not _use_global_visuals:
		_rope_container = Node3D.new()
		_rope_container.name = "GrappleRopeContainer"
		var root2 = get_tree().root
		if not root2:
			call_deferred("_attach_visuals_to_root")
		else:
			_attach_visuals_to_root()

	# Initialize segment MeshInstances
	if not _use_global_visuals:
		for i in range(rope_segments):
			var seg = MeshInstance3D.new()
			seg.mesh = _rope_cylinder
			seg.material_override = rope_mat
			seg.visible = false
			_rope_container.add_child(seg)
			_rope_segments_arr.append(seg)
		# Create line visual (ImmediateMesh) for a simple single-line rope
		if use_line_visual:
			_rope_line_mesh = ImmediateMesh.new()
			_rope_line_instance = MeshInstance3D.new()
			_rope_line_instance.mesh = _rope_line_mesh
			var line_mat = StandardMaterial3D.new()
			line_mat.flags_unshaded = true
			line_mat.emission_enabled = true
			line_mat.emission = rope_color
			line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_rope_line_instance.material_override = line_mat
			_rope_line_instance.visible = false
			_rope_line_instance.name = "GrappleRopeLine"
			_attach_visuals_to_root()

	if enable_debug_logs:
		print("GrappleHook: ready at", global_transform.origin, "collision_layer=", collision_layer)

func _on_grabbed(hand: RigidBody3D) -> void:
	_hand = hand
	_controller = null
	_player_body = null
	if is_instance_valid(hand) and hand.has_method("get"):
		var maybe_target = hand.get("target")
		if maybe_target and maybe_target is Node3D:
			_controller = maybe_target

		var maybe_player = hand.get("player_rigidbody")
		if maybe_player and maybe_player is RigidBody3D:
			_player_body = maybe_player

	set_physics_process(true)
	# show prediction marker while grabbed (global visuals will be updated in _physics_process)
	if is_instance_valid(_hitmarker):
		if _use_global_visuals and _global_visuals:
			# let physics process update the hitmarker position
			pass
		else:
			_hitmarker.visible = true

func _on_released() -> void:
	_end_grapple()
	set_physics_process(false)
	if is_instance_valid(_hitmarker):
		if _use_global_visuals and _global_visuals:
			_global_visuals.hide_hitmarker()
		else:
			_hitmarker.visible = false
			if use_line_visual and is_instance_valid(_rope_line_instance):
				_rope_line_instance.visible = false
	if is_instance_valid(_rope_visual):
		if _use_global_visuals and _global_visuals:
			_global_visuals.hide_segments()
		else:
			_rope_visual.visible = false
		if _rope_cylinder:
			# Reset scale and height
			_rope_visual.scale = Vector3.ONE
			_rope_visual.mesh = _rope_cylinder
		if use_line_visual and is_instance_valid(_rope_line_instance):
			_rope_line_instance.visible = false

func _end_grapple() -> void:
	_is_hooked = false
	_hook_object = null
	# Hide the hitmarker when grappling ends (cleanup)
	if is_instance_valid(_hitmarker):
		if _use_global_visuals and _global_visuals:
			_global_visuals.hide_hitmarker()
		else:
			_hitmarker.visible = false
	if is_instance_valid(_rope_visual):
		if _use_global_visuals and _global_visuals:
			_global_visuals.hide_segments()
		else:
			_rope_visual.visible = false
		if _rope_cylinder:
			# Reset scale and mesh if we later toggle rope on
			_rope_visual.mesh = _rope_cylinder
		if use_line_visual and is_instance_valid(_rope_line_instance):
			_rope_line_instance.visible = false

	# Hide segments on release
	if _use_global_visuals and _global_visuals:
		_global_visuals.hide_segments()
	else:
		for seg in _rope_segments_arr:
			if is_instance_valid(seg):
				seg.visible = false

func _physics_process(delta: float) -> void:
	# Ensure visuals are parented to the SceneTree root so they persist across scene changes
	_ensure_visuals_parent()
	if not is_grabbed:
		return
	if not is_instance_valid(_hand):
		return

	# Determine controller transform (prefer controller target when present)
	var controller_transform: Transform3D
	if is_instance_valid(_controller) and _controller is Node3D:
		controller_transform = (_controller as Node3D).global_transform
	else:
		controller_transform = _hand.global_transform

	# Read trigger input
	var trigger_pressed: bool = false
	if is_instance_valid(_controller) and _controller.has_method("is_button_pressed"):
		trigger_pressed = _controller.is_button_pressed("trigger_click")
	elif InputMap.has_action("trigger_click"):
		trigger_pressed = Input.is_action_pressed("trigger_click")

	# Prediction: while grabbed and not hooked, update hitmarker to where the grapple would land
	if is_instance_valid(_hitmarker) and not _is_hooked:
		var _from = controller_transform.origin
		var _forward_vec: Vector3 = controller_transform.basis.z
		var _dir: Vector3 = _forward_vec.normalized() * -1.0
		var _to = _from + _dir * max_distance
		var _space = get_world_3d().direct_space_state
		var _exclude = [self]
		if is_instance_valid(_hand):
			_exclude.append(_hand)
		var _q = PhysicsRayQueryParameters3D.create(_from, _to)
		_q.exclude = _exclude
		_q.collision_mask = grapple_collision_mask
		var _pres = _space.intersect_ray(_q)
		if _pres:
			if _use_global_visuals and _global_visuals:
				_global_visuals.show_hitmarker(_pres.position)
			else:
				_hitmarker.global_transform = Transform3D(Basis(), _pres.position)
				_hitmarker.visible = true
				# Draw prediction line while aiming
				if use_line_visual and is_instance_valid(_rope_line_mesh) and is_instance_valid(_rope_line_instance):
					_rope_line_mesh.clear_surfaces()
					_rope_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
					_rope_line_mesh.surface_add_vertex(_from)
					_rope_line_mesh.surface_add_vertex(_pres.position)
					_rope_line_mesh.surface_end()
					_rope_line_instance.visible = true
		else:
			_hitmarker.visible = false
	# Launch grapple
	if trigger_pressed and not _is_hooked:
		var from = controller_transform.origin
		var forward_vec: Vector3 = controller_transform.basis.z
		var aim_dir: Vector3 = forward_vec.normalized() * -1.0
		var to = from + aim_dir * max_distance
		var space = get_world_3d().direct_space_state
		var exclude = [self]
		if is_instance_valid(_hand):
			exclude.append(_hand)
		var query = PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = exclude
		query.collision_mask = grapple_collision_mask
		var res = space.intersect_ray(query)
		if res:
			_is_hooked = true
			_hook_point = res.position
			_hook_object = res.collider
			if is_instance_valid(_hook_object) and _hook_object is Node3D:
				# store offset in object-local coordinates so it moves with rotation and scale
				_hook_local_offset = (_hook_object as Node3D).to_local(_hook_point)
			else:
				_hook_local_offset = Vector3.ZERO
			if enable_debug_logs:
				print("GrappleHook: hooked at", _hook_point, "collider=", _hook_object)
			# Use the object's local offset to calculate the actual world hook point to apply the initial
			# impulse toward the dynamic surface point if the object moves/rotates.
			var world_hook_point: Vector3 = _hook_point
			if is_instance_valid(_hook_object) and _hook_object is Node3D:
				world_hook_point = (_hook_object as Node3D).to_global(_hook_local_offset)
			# Apply initial impulse to the player body if available, towards live world hook point
			if is_instance_valid(_player_body):
				var impulse = (world_hook_point - _player_body.global_transform.origin).normalized() * impulse_speed
				_player_body.apply_central_impulse(impulse)
		# Ensure hitmarker stays at the actual hook location once hooked
		if _use_global_visuals and _global_visuals:
			_global_visuals.show_hitmarker(((_hook_object as Node3D).to_global(_hook_local_offset)) if is_instance_valid(_hook_object) and _hook_object is Node3D else _hook_point)
		elif is_instance_valid(_hitmarker):
			_hitmarker.visible = true
			if is_instance_valid(_hook_object) and _hook_object is Node3D:
				_hitmarker.global_transform = Transform3D(Basis(), (_hook_object as Node3D).to_global(_hook_local_offset))
			else:
				_hitmarker.global_transform = Transform3D(Basis(), _hook_point)


	# While hooked, apply winch force
	if _is_hooked:
		if not trigger_pressed:
			_end_grapple()
		else:
			# Compute a live world hook point that updates as the hooked object moves/rotates
			var live_hook_point: Vector3 = _hook_point
			if is_instance_valid(_hook_object) and _hook_object is Node3D:
				live_hook_point = (_hook_object as Node3D).to_global(_hook_local_offset)

			# Update hitmarker while hooked
			if _use_global_visuals and _global_visuals:
				_global_visuals.show_hitmarker(live_hook_point)
			elif is_instance_valid(_hitmarker):
				_hitmarker.visible = true
				_hitmarker.global_transform = Transform3D(Basis(), live_hook_point)

			# Position and orient a thin cylinder between controller and hook point
			# Draw curved rope using quadratic bezier segmentation
			var rope_start: Vector3 = controller_transform.origin
			var rope_end: Vector3 = live_hook_point
			var v: Vector3 = rope_end - rope_start
			var length: float = v.length()
			if length > 0.001:
				# Compute cubic Bezier control points to get a tensioned rope with straighter ends
				var sag_amount: float = clamp(length * rope_sag_factor, 0.0, rope_sag_max)
				# direction from start to end
				var curve_dir: Vector3 = v.normalized()
				# p0 = start, p3 = end
				var p0: Vector3 = rope_start
				var p3: Vector3 = rope_end
				# control points near both ends to enforce stiffness
				# For the start control, allow a minimum forward offset in the controller's forward direction
				var controller_forward: Vector3 = Vector3.ZERO
				if is_instance_valid(_controller) and _controller is Node3D:
					controller_forward = ((_controller as Node3D).global_transform.basis.z).normalized() * -1.0
				else:
					controller_forward = curve_dir
				# pick distance for p1 using stiffness or a minimum forward length
				var desired_p1_dist: float = max(length * rope_start_stiffness, rope_start_min_length)
				# clamp to a safe fraction of the rope length so p1 doesn't cross p2
				desired_p1_dist = clamp(desired_p1_dist, 0.001, length * 0.45)
				var p1: Vector3 = p0 + controller_forward * desired_p1_dist
				var p2: Vector3 = p3 - curve_dir * (length * rope_end_stiffness)
				# ensure p2 also doesn't cross p1
				var p2_dist = (p3 - p2).length()
				if p2_dist < desired_p1_dist:
					# push back p2 so it remains after p1
					p2 = p3 - curve_dir * (length * rope_end_stiffness + (desired_p1_dist - p2_dist))
				# apply sag bias - move both controls downward to create center sag; bias can push p1 a little less than p2
				p1 += Vector3.DOWN * (sag_amount * (rope_mid_sag_bias * 0.5))
				p2 += Vector3.DOWN * (sag_amount * (rope_mid_sag_bias * 1.0))
				# sample points along cubic bezier (S-like curvature)
				var points: Array = []
				for i in range(rope_segments + 1):
					var t: float = float(i) / rope_segments
					# cubic bezier formula
					var mt: float = 1.0 - t
					var p: Vector3 = mt * mt * mt * p0 + 3.0 * mt * mt * t * p1 + 3.0 * mt * t * t * p2 + t * t * t * p3
					points.append(p)
					_last_rope_points = points
				# update segments with bounds checking
				if points.size() < 2:
					# nothing to draw
					for seg in _rope_segments_arr:
						if is_instance_valid(seg):
							seg.visible = false
				else:
					if _use_global_visuals and _global_visuals:
						# Hide any previously visible global segments before updating
						_global_visuals.hide_segments()
						var seg_count: int = min(max(rope_segments, 0), max(0, points.size() - 1))
						for i in range(seg_count):
							var a: Vector3 = points[i]
							var b: Vector3 = points[i + 1]
							_global_visuals.update_segment(i, a, b, rope_thickness)
					else:
						# choose the number of segments we can actually update
						var seg_count: int = min(max(rope_segments, 0), max(0, points.size() - 1))
						seg_count = min(seg_count, _rope_segments_arr.size())
						for i in range(seg_count):
							var a: Vector3 = points[i]
							var b: Vector3 = points[i + 1]
							var seg = _rope_segments_arr[i]
							if not is_instance_valid(seg):
								continue
							var seg_v: Vector3 = b - a
							var seg_length: float = seg_v.length()
							if seg_length <= 0.0001:
								seg.visible = false
								continue
							# compute orientation basis (Y aligns with seg_v)
							var seg_dir = seg_v / seg_length
							var up = Vector3.UP
							if abs(seg_dir.dot(up)) > 0.999:
								up = Vector3.FORWARD
							var right = up.cross(seg_dir).normalized()
							var forward = seg_dir.cross(right).normalized()
							var seg_basis = Basis(right, seg_dir, forward)
							var seg_mid = a + seg_v * 0.5
							seg.global_transform = Transform3D(seg_basis, seg_mid)
							seg.scale = Vector3(rope_thickness, seg_length, rope_thickness)
							seg.visible = true
						# hide any remaining segment instances if we have fewer points than instances
						for j in range(seg_count, _rope_segments_arr.size()):
							var extra = _rope_segments_arr[j]
							if is_instance_valid(extra):
								extra.visible = false
				# If a simple line visual is enabled, draw a single line from start to end
				if use_line_visual and is_instance_valid(_rope_line_mesh) and is_instance_valid(_rope_line_instance):
					_rope_line_mesh.clear_surfaces()
					_rope_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
					_rope_line_mesh.surface_add_vertex(rope_start)
					_rope_line_mesh.surface_add_vertex(rope_end)
					_rope_line_mesh.surface_end()
					_rope_line_instance.visible = true
			else:
				# hide segments
				for seg in _rope_segments_arr:
					if is_instance_valid(seg):
						seg.visible = false
			# Hide line visual when segments are hidden
			if use_line_visual and is_instance_valid(_rope_line_instance):
				_rope_line_instance.visible = false
				if _use_global_visuals and _global_visuals:
					# hide global
					_global_visuals.hide_segments()
				else:
					# local segments already hidden
					pass

			# Apply winch force toward the live hook point
			if is_instance_valid(_player_body):
				var to_hook = live_hook_point - _player_body.global_transform.origin
				var dist = to_hook.length()
				if dist > 0.1:
					var dir2 = to_hook.normalized()
					var vdot = _player_body.linear_velocity.dot(dir2)
					if vdot < winch_speed:
						var force = dir2 * (_player_body.mass * (winch_speed - vdot)) * delta * 8.0
						_player_body.apply_central_impulse(force)
			if enable_debug_logs:
				print("GrappleHook(frame): player=", _player_body.global_transform.origin, ", hook=", live_hook_point)

			# If using global visuals, ensure visuals remain attached
			if _use_global_visuals and _global_visuals and persist_visuals_across_scenes:
				# no-op: autoload visuals are persistent
				pass
			else:
				_ensure_visuals_parent()
	
	# Network sync: Send position updates if we own this object
	if is_network_owner and network_manager:
		network_manager.update_grabbed_object(
			save_id,
			global_position,
			global_transform.basis.get_rotation_quaternion()
		)

func _exit_tree() -> void:
	_end_grapple()
	if is_instance_valid(_hitmarker):
		if persist_visuals_across_scenes:
			# If visuals are persistent across scenes we keep them in the tree.
			# Do not auto-hide here; let the global visuals manager or game flow control visibility.
			pass
		else:
			_hitmarker.queue_free()
	if is_instance_valid(_rope_visual):
		if persist_visuals_across_scenes:
			# Keep the visuals when persisting across scenes.
			# If a global visuals manager is present, hide segments there. Otherwise keep visible.
			if _use_global_visuals and _global_visuals:
				_global_visuals.hide_segments()
			else:
				_rope_visual.visible = false
		else:
			_rope_visual.queue_free()
	if use_line_visual and is_instance_valid(_rope_line_instance):
		if persist_visuals_across_scenes:
			# just hide the visual but keep it around
			_rope_line_instance.visible = false
		else:
			_rope_line_instance.queue_free()
	if is_instance_valid(_rope_container):
		if persist_visuals_across_scenes:
			# When persisting, keep visuals attached to tree so they survive scene loads.
			# If a global visual manager exists, delegate hiding to it; otherwise keep segments visible
			if _use_global_visuals and _global_visuals:
				_global_visuals.hide_segments()
			else:
				for seg in _rope_segments_arr:
					if is_instance_valid(seg):
						seg.visible = false
			_rope_container.visible = false
		else:
			_rope_container.queue_free()
	for seg in _rope_segments_arr:
		if is_instance_valid(seg):
			seg.queue_free()
	if _rope_cylinder:
		_rope_cylinder = null
	# If we were hooked and using global visuals, request the visuals manager to persist
	if _is_hooked and persist_visuals_across_scenes and _use_global_visuals and _global_visuals and _last_rope_points.size() > 0:
		_global_visuals.persist_rope(_last_rope_points, rope_thickness, 10.0)

func _ensure_visuals_parent() -> void:
	# Reparent to get_tree().root so visuals persist across scene changes or editor reloads
	var root = get_tree().root
	var _scheduled: bool = false
	if is_instance_valid(_hitmarker) and _hitmarker.get_parent() != root:
		if _visuals_pending_parent:
			# already waiting for add_child to execute
			pass
		else:
			if _hitmarker.get_parent():
				_hitmarker.get_parent().remove_child(_hitmarker)
			root.call_deferred("add_child", _hitmarker)
	if is_instance_valid(_rope_visual) and _rope_visual.get_parent() != root:
		if _visuals_pending_parent:
			pass
		else:
			if _rope_visual.get_parent():
				_rope_visual.get_parent().remove_child(_rope_visual)
			root.call_deferred("add_child", _rope_visual)
			_visuals_pending_parent = true
	if is_instance_valid(_rope_container) and _rope_container.get_parent() != root:
		# If the container is unparented, attach deferred; otherwise move it
		if _visuals_pending_parent:
			pass
		else:
			if _rope_container.get_parent():
				_rope_container.get_parent().remove_child(_rope_container)
			root.call_deferred("add_child", _rope_container)
			_visuals_pending_parent = true
	# Clear pending if visuals are already attached
	if is_instance_valid(_hitmarker) and _hitmarker.get_parent() == root and is_instance_valid(_rope_visual) and _rope_visual.get_parent() == root and is_instance_valid(_rope_container) and _rope_container.get_parent() == root:
		_visuals_pending_parent = false
	# If using the line visual then include it in the check
	if use_line_visual and is_instance_valid(_rope_line_instance) and _rope_line_instance.get_parent() == root:
		_visuals_pending_parent = false
	# Consider the line instance as part of visuals too
	if use_line_visual and is_instance_valid(_rope_line_instance) and _rope_line_instance.get_parent() != root:
		root.call_deferred("add_child", _rope_line_instance)
		_visuals_pending_parent = true

func _attach_visuals_to_root() -> void:
	# Helper to attach the visuals once using call_deferred; prevents duplicated add_child calls
	if _visuals_pending_parent:
		return
	_visuals_pending_parent = true
	var root = get_tree().root
	if not root:
		# Schedule another attempt to attach visuals once the SceneTree becomes available
		call_deferred("_attach_visuals_to_root")
		return
	var scheduled: bool = false
	if not root:
		return
	if is_instance_valid(_hitmarker) and _hitmarker.get_parent() == null:
		root.call_deferred("add_child", _hitmarker)
		scheduled = true
	if is_instance_valid(_rope_visual) and _rope_visual.get_parent() == null:
		root.call_deferred("add_child", _rope_visual)
		scheduled = true
	if is_instance_valid(_rope_container) and _rope_container.get_parent() == null:
		root.call_deferred("add_child", _rope_container)
		scheduled = true
	if use_line_visual and is_instance_valid(_rope_line_instance) and _rope_line_instance.get_parent() == null:
		root.call_deferred("add_child", _rope_line_instance)
		scheduled = true
	if scheduled:
		_visuals_pending_parent = true


# ============================================================================
# Grabbable Functionality (copied from Grabbable class)
# ============================================================================

func try_grab(hand: RigidBody3D) -> bool:
	"""Attempt to grab this object with a hand"""
	if is_grabbed:
		return false
	
	# Check if another player owns this object
	if network_manager and network_manager.is_object_grabbed_by_other(save_id):
		print("Grabbable: ", save_id, " is grabbed by another player")
		return false
	
	is_grabbed = true
	grabbing_hand = hand
	original_parent = get_parent()
	is_network_owner = true
	
	# Sync with hand's held_object
	if hand.has_method("set") and hand.get("held_object") != self:
		hand.set("held_object", self)
	
	# Calculate the offset in hand's local space
	var hand_inv = hand.global_transform.affine_inverse()
	var obj_to_hand = hand_inv * global_transform
	
	if grab_mode == GrabMode.FREE_GRAB:
		grab_offset = obj_to_hand.origin
		grab_rotation_offset = obj_to_hand.basis.get_rotation_quaternion()
	else:  # ANCHOR_GRAB
		grab_offset = grab_anchor_offset
		grab_rotation_offset = Quaternion(Vector3.FORWARD, grab_anchor_rotation.z) * \
							   Quaternion(Vector3.UP, grab_anchor_rotation.y) * \
							   Quaternion(Vector3.RIGHT, grab_anchor_rotation.x)
	
	# Clone collision shapes and meshes as direct children of the hand
	grabbed_collision_shapes.clear()
	grabbed_mesh_instances.clear()
	
	for child in get_children():
		if child is CollisionShape3D and child.shape:
			var new_collision = CollisionShape3D.new()
			new_collision.shape = child.shape
			new_collision.transform = Transform3D(Basis(grab_rotation_offset), grab_offset) * child.transform
			new_collision.name = name + "_grabbed_collision_" + str(grabbed_collision_shapes.size())
			hand.add_child(new_collision)
			grabbed_collision_shapes.append(new_collision)
			
		elif child is MeshInstance3D and child.mesh:
			var new_mesh = MeshInstance3D.new()
			new_mesh.mesh = child.mesh
			new_mesh.transform = Transform3D(Basis(grab_rotation_offset), grab_offset) * child.transform
			new_mesh.name = name + "_grabbed_mesh_" + str(grabbed_mesh_instances.size())
			hand.add_child(new_mesh)
			grabbed_mesh_instances.append(new_mesh)
	
	visible = false
	collision_layer = 0
	collision_mask = 0
	freeze = true
	
	# Notify network
	if network_manager and is_network_owner:
		network_manager.grab_object(save_id)
	
	grabbed.emit(hand)
	print("Grabbable: Object grabbed by ", hand.name)
	
	return true


func release() -> void:
	"""Release the object from the hand"""
	if not is_grabbed:
		return
	
	print("Grabbable: Object released")
	
	# Notify network
	if network_manager and is_network_owner:
		network_manager.release_object(save_id, global_position, global_transform.basis.get_rotation_quaternion())
	
	is_network_owner = false
	
	var release_global_transform = global_transform
	if grabbed_collision_shapes.size() > 0 and is_instance_valid(grabbed_collision_shapes[0]):
		release_global_transform = grabbed_collision_shapes[0].global_transform
	elif is_instance_valid(grabbing_hand):
		release_global_transform = grabbing_hand.global_transform * Transform3D(Basis(grab_rotation_offset), grab_offset)
	
	var hand_velocity = Vector3.ZERO
	var hand_angular_velocity = Vector3.ZERO
	
	if is_instance_valid(grabbing_hand):
		hand_velocity = grabbing_hand.linear_velocity
		hand_angular_velocity = grabbing_hand.angular_velocity * 0.5
		
		for collision_shape in grabbed_collision_shapes:
			if is_instance_valid(collision_shape) and collision_shape.get_parent() == grabbing_hand:
				grabbing_hand.remove_child(collision_shape)
				collision_shape.queue_free()
		
		for mesh_instance in grabbed_mesh_instances:
			if is_instance_valid(mesh_instance) and mesh_instance.get_parent() == grabbing_hand:
				grabbing_hand.remove_child(mesh_instance)
				mesh_instance.queue_free()
	else:
		for collision_shape in grabbed_collision_shapes:
			if is_instance_valid(collision_shape):
				collision_shape.queue_free()
		for mesh_instance in grabbed_mesh_instances:
			if is_instance_valid(mesh_instance):
				mesh_instance.queue_free()
	
	grabbed_collision_shapes.clear()
	grabbed_mesh_instances.clear()
	
	visible = true
	freeze = false
	collision_layer = 1
	collision_mask = 1
	
	global_transform = release_global_transform
	linear_velocity = hand_velocity
	angular_velocity = hand_angular_velocity
	
	if is_instance_valid(grabbing_hand) and grabbing_hand.has_method("set"):
		grabbing_hand.set("held_object", null)
	
	is_grabbed = false
	grabbing_hand = null
	
	released.emit()


func _setup_network_sync() -> void:
	"""Connect to network manager for multiplayer sync"""
	network_manager = get_node_or_null("/root/NetworkManager")
	
	if not network_manager:
		return
	
	network_manager.grabbable_grabbed.connect(_on_network_grab)
	network_manager.grabbable_released.connect(_on_network_release)
	network_manager.grabbable_sync_update.connect(_on_network_sync)
	
	print("Grabbable: ", save_id, " network sync initialized")


func _on_network_grab(object_id: String, peer_id: int) -> void:
	if object_id != save_id:
		return
	
	if network_manager and peer_id == network_manager.get_multiplayer_id():
		return
	
	print("Grabbable: ", save_id, " grabbed by remote player ", peer_id)
	is_network_owner = false
	_set_remote_grabbed_visual(true)


func _on_network_release(object_id: String, peer_id: int) -> void:
	if object_id != save_id:
		return
	
	if network_manager and peer_id == network_manager.get_multiplayer_id():
		return
	
	print("Grabbable: ", save_id, " released by remote player ", peer_id)
	_set_remote_grabbed_visual(false)


func _on_network_sync(object_id: String, data: Dictionary) -> void:
	if object_id != save_id:
		return
	
	if is_network_owner or is_grabbed:
		return
	
	if data.has("position"):
		var target_pos = data["position"]
		global_position = global_position.lerp(target_pos, 0.3)
	
	if data.has("rotation"):
		var target_rot = data["rotation"]
		var current_quat = global_transform.basis.get_rotation_quaternion()
		var interpolated = current_quat.slerp(target_rot, 0.3)
		global_transform.basis = Basis(interpolated)


func _set_remote_grabbed_visual(is_grabbed_visual: bool) -> void:
	for child in get_children():
		if child is MeshInstance3D:
			if is_grabbed_visual:
				if not child.material_override:
					var mat = StandardMaterial3D.new()
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat.albedo_color = Color(1, 1, 1, 0.5)
					child.material_override = mat
			else:
				child.material_override = null


func _on_collision_entered(_body: Node) -> void:
	pass
