extends Node3D

signal focus_lost
signal focus_gained
signal pose_recentered
signal vr_mode_active(is_active: bool)

@export var maximum_refresh_rate : int = 90

var xr_interface : OpenXRInterface
var xr_is_focussed = false
var is_vr_mode := false

# Called when the node enters the scene tree for the first time.
func _ready():
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		print("OpenXR instantiated successfully.")
		var vp : Viewport = get_viewport()

		# Enable XR on our viewport
		vp.use_xr = true

		# Make sure v-sync is off, v-sync is handled by OpenXR
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

		# Enable VRS
		if RenderingServer.get_rendering_device():
			vp.vrs_mode = Viewport.VRS_XR
		elif int(ProjectSettings.get_setting("xr/openxr/foveation_level")) == 0:
			push_warning("OpenXR: Recommend setting Foveation level to High in Project Settings")

		# Connect the OpenXR events
		xr_interface.session_begun.connect(_on_openxr_session_begun)
		xr_interface.session_visible.connect(_on_openxr_visible_state)
		xr_interface.session_focussed.connect(_on_openxr_focused_state)
		xr_interface.session_stopping.connect(_on_openxr_stopping)
		xr_interface.pose_recentered.connect(_on_openxr_pose_recentered)
		
		is_vr_mode = true
		emit_signal("vr_mode_active", true)
	else:
		# We couldn't start OpenXR - continue in desktop mode for development
		print("OpenXR not instantiated! Running in desktop mode.")
		is_vr_mode = false
		emit_signal("vr_mode_active", false)

# Handle OpenXR session ready
func _on_openxr_session_begun() -> void:
	# Get the reported refresh rate
	var current_refresh_rate = xr_interface.get_display_refresh_rate()
	if current_refresh_rate > 0:
		print("OpenXR: Refresh rate reported as ", str(current_refresh_rate))
	else:
		print("OpenXR: No refresh rate given by XR runtime")

	# See if we have a better refresh rate available
	var new_rate = current_refresh_rate
	var available_rates : Array = xr_interface.get_available_display_refresh_rates()
	if available_rates.size() == 0:
		print("OpenXR: Target does not support refresh rate extension")
	elif available_rates.size() == 1:
		# Only one available, so use it
		new_rate = available_rates[0]
	else:
		print("OpenXR: Available refresh rates: ", available_rates)
		# Prefer 90 Hz if available, otherwise use the highest rate up to maximum
		var preferred_rate = 90.0
		if preferred_rate in available_rates and preferred_rate <= maximum_refresh_rate:
			new_rate = preferred_rate
			print("OpenXR: Using preferred 90 Hz rate")
		else:
			for rate in available_rates:
				if rate > new_rate and rate <= maximum_refresh_rate:
					new_rate = rate

	# Did we find a better rate?
	if current_refresh_rate != new_rate:
		print("OpenXR: Setting refresh rate to ", str(new_rate))
		xr_interface.set_display_refresh_rate(new_rate)
		current_refresh_rate = new_rate
	else:
		print("OpenXR: Keeping current refresh rate: ", str(current_refresh_rate))

	# Now match our physics rate
	Engine.physics_ticks_per_second = current_refresh_rate
	print("OpenXR: Physics ticks per second set to: ", Engine.physics_ticks_per_second)

# Handle OpenXR visible state
func _on_openxr_visible_state() -> void:
	# We always pass this state at startup,
	# but the second time we get this it means our player took off their headset
	if xr_is_focussed:
		print("OpenXR lost focus")

		xr_is_focussed = false

		# pause our game
		get_tree().paused = true

		emit_signal("focus_lost")

# Handle OpenXR focused state
func _on_openxr_focused_state() -> void:
	print("OpenXR gained focus")
	xr_is_focussed = true

	# unpause our game
	get_tree().paused = false

	emit_signal("focus_gained")

# Handle OpenXR stopping state
func _on_openxr_stopping() -> void:
	# Our session is being stopped.
	print("OpenXR is stopping")

# Handle OpenXR pose recentered signal
func _on_openxr_pose_recentered() -> void:
	# User recentered view (Meta Horizon Home button long-press).
	# Reset the XROrigin3D rotation to align forward with the headset's current facing direction.
	print("OpenXR: Pose recenter requested")
	_recenter_player_orientation()
	emit_signal("pose_recentered")


func _recenter_player_orientation() -> void:
	"""Reset the player's forward orientation based on the current headset facing direction."""
	# Get the XRCamera3D (headset) to determine current facing direction
	var camera := get_node_or_null("XRCamera3D") as XRCamera3D
	if not camera:
		push_warning("XROrigin3D: Cannot recenter - XRCamera3D not found")
		return
	
	# Get the headset's current Y rotation (yaw) in the XROrigin's local space
	# We only care about the horizontal rotation, not pitch/roll
	var camera_basis := camera.transform.basis
	var camera_forward := -camera_basis.z
	camera_forward.y = 0  # Project onto horizontal plane
	
	if camera_forward.length_squared() < 0.001:
		# Camera is looking straight up or down, can't determine forward
		push_warning("XROrigin3D: Cannot recenter - camera looking vertically")
		return
	
	camera_forward = camera_forward.normalized()
	
	# Calculate the angle to rotate the origin so the camera faces world forward (-Z)
	var target_forward := Vector3(0, 0, -1)
	var angle := camera_forward.signed_angle_to(target_forward, Vector3.UP)
	
	# Apply the rotation to the XROrigin3D
	# This rotates the entire play space so the headset now faces forward
	rotate_y(angle)
	
	print("OpenXR: Player orientation recentered (rotated ", rad_to_deg(angle), " degrees)")
