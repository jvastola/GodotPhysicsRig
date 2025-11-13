extends MeshInstance3D

@export var mirror_resolution := Vector2i(1024, 1024)
@export var update_mode := SubViewport.UPDATE_ALWAYS
@export var show_debug_visuals := true
@export var debug_line_length := 1.0
@export var near_clip := 0.01  # Minimum distance to avoid clipping issues

var _viewport: SubViewport
var _camera: Camera3D
var _viewport_texture: ViewportTexture
var _debug_normal_line: MeshInstance3D
var _debug_camera_gizmo: MeshInstance3D
var _debug_reflected_cam_gizmo: MeshInstance3D
var _debug_line_material: StandardMaterial3D


func _reflect_point(point: Vector3, plane_point: Vector3, plane_normal: Vector3) -> Vector3:
	var to_point := point - plane_point
	return point - 2.0 * plane_normal.dot(to_point) * plane_normal


func _reflect_vector(vector: Vector3, plane_normal: Vector3) -> Vector3:
	return vector - 2.0 * plane_normal.dot(vector) * plane_normal


func _ready() -> void:
	_setup_mirror()
	if show_debug_visuals:
		_setup_debug_visuals()


func _setup_debug_visuals() -> void:
	# Create a line showing the mirror normal
	_debug_normal_line = MeshInstance3D.new()
	var immediate_mesh := ImmediateMesh.new()
	_debug_normal_line.mesh = immediate_mesh
	add_child(_debug_normal_line)

	_debug_line_material = StandardMaterial3D.new()
	_debug_line_material.albedo_color = Color.GREEN
	_debug_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_line_material.no_depth_test = true
	_debug_normal_line.material_override = _debug_line_material
	
	# Create camera position gizmo (sphere for main camera)
	_debug_camera_gizmo = _create_debug_sphere(Color.BLUE, 0.1)
	add_child(_debug_camera_gizmo)
	
	# Create reflected camera position gizmo (sphere for reflected camera)
	_debug_reflected_cam_gizmo = _create_debug_sphere(Color.RED, 0.1)
	add_child(_debug_reflected_cam_gizmo)


func _create_debug_sphere(color: Color, radius: float) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2
	mesh_inst.mesh = sphere
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mesh_inst.material_override = mat
	
	return mesh_inst


func _update_debug_visuals(mirror_normal: Vector3, main_cam_pos: Vector3, reflected_pos: Vector3) -> void:
	if not show_debug_visuals:
		return
	
	# Update normal line
	if _debug_normal_line and _debug_normal_line.mesh is ImmediateMesh:
		var im := _debug_normal_line.mesh as ImmediateMesh
		im.clear_surfaces()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		
		# Draw normal from mirror center
		var start := to_local(global_position)
		var end := to_local(global_position + mirror_normal * debug_line_length)
		im.surface_add_vertex(start)
		im.surface_add_vertex(end)
		im.surface_end()
		if _debug_line_material:
			im.surface_set_material(0, _debug_line_material)
	
	# Update camera gizmos
	if _debug_camera_gizmo:
		_debug_camera_gizmo.global_position = main_cam_pos
	
	if _debug_reflected_cam_gizmo:
		_debug_reflected_cam_gizmo.global_position = reflected_pos


func _setup_mirror() -> void:
	# Create viewport for rendering the mirror reflection
	_viewport = SubViewport.new()
	_viewport.size = mirror_resolution
	_viewport.render_target_update_mode = update_mode
	_viewport.transparent_bg = false
	_viewport.world_3d = get_world_3d()
	add_child(_viewport)
	
	# Create camera for mirror view
	_camera = Camera3D.new()
	_viewport.add_child(_camera)
	_camera.current = true
	
	# Get viewport texture
	_viewport_texture = _viewport.get_texture()
	
	# Create mirror material
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _viewport_texture
	mat.metallic = 0.9
	mat.roughness = 0.1
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material_override = mat
	
	print("Mirror: Setup complete, resolution: ", mirror_resolution)


func _process(_delta: float) -> void:
	if not _camera:
		return
	
	# Find the active camera (player camera)
	var main_camera := get_viewport().get_camera_3d()
	if not main_camera:
		return
	
	# Calculate mirror reflection transform
	# The mirror's forward direction (local -Z) is the normal
	var mirror_normal := -global_transform.basis.z.normalized()
	var plane_point := global_position
	var camera_pos := main_camera.global_position
	
	# Check if camera is behind the mirror (don't render if so)
	var distance_to_plane := mirror_normal.dot(camera_pos - plane_point)
	if distance_to_plane < 0:
		# Camera is behind mirror, disable rendering
		_camera.current = false
		return
	else:
		_camera.current = true  # Ensure the SubViewport renders from this camera
	
	# Reflect camera position across the mirror plane
	var reflected_pos := _reflect_point(camera_pos, plane_point, mirror_normal) + mirror_normal * 0.01

	# Mirror the camera orientation using reflected target/up
	var main_forward := -main_camera.global_transform.basis.z.normalized()
	var main_target := camera_pos + main_forward
	var reflected_target := _reflect_point(main_target, plane_point, mirror_normal)

	var main_up := main_camera.global_transform.basis.y.normalized()
	var reflected_up := _reflect_vector(main_up, mirror_normal).normalized()
	if reflected_up.length_squared() < 0.001:
		reflected_up = global_transform.basis.y.normalized()

	_camera.global_position = reflected_pos
	_camera.look_at(reflected_target, reflected_up)

	# Match projection and clip planes
	_camera.projection = main_camera.projection
	if _camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		_camera.fov = main_camera.fov
	else:
		_camera.size = main_camera.size
	_camera.near = max(near_clip, main_camera.near)
	_camera.far = main_camera.far
	_camera.keep_aspect = main_camera.keep_aspect
	_camera.cull_mask = main_camera.cull_mask
	
	# Update debug visuals
	_update_debug_visuals(mirror_normal, camera_pos, reflected_pos)
