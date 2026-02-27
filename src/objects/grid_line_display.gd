extends Node3D
## Displays dynamic grid lines above a subdivided plane mesh
## Lines follow terrain near player and rise above it at distance

@export var grid_size: int = 10  ## Number of subdivisions (creates grid_size x grid_size grid)
@export var cell_size: float = 1.0  ## Size of each grid cell in meters
@export var height_noise_scale: float = 0.5  ## Maximum height variation from noise
@export var noise_frequency: float = 0.3  ## Frequency of height noise

@export_group("Zone Settings")
@export var zone1_distance: float = 5.0  ## Distance where lines follow terrain
@export var zone2_distance: float = 7.0  ## Distance where lines become invisible
@export var line_height_offset: float = 1.0  ## Height above terrain in transition zone

@export_group("Line Appearance")
@export var line_color: Color = Color(0.0, 1.0, 1.0, 1.0)  ## Color of grid lines
@export var line_width: float = 0.02  ## Width of lines

@export_group("Mirror Settings")
@export_range(0, 31) var render_layer: int = 15  ## Layer for mirror-only rendering

var terrain_mesh_instance: MeshInstance3D
var lines_mesh_instance: MeshInstance3D
var player: Node3D
var shader_material: ShaderMaterial
var noise: FastNoiseLite

# Store terrain vertex positions for line generation
var terrain_vertices: PackedVector3Array = PackedVector3Array()


func _ready() -> void:
	# Initialize noise generator
	noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = noise_frequency
	noise.seed = randi()
	
	# Create the terrain and line meshes
	_create_terrain_mesh()
	_create_lines_mesh()
	
	# Find player
	call_deferred("_find_player")


func _find_player() -> void:
	"""Find the player in the scene"""
	player = get_tree().get_first_node_in_group("xr_player")
	if not player:
		push_warning("GridLineDisplay: Could not find player in 'xr_player' group")


func _process(_delta: float) -> void:
	if player and shader_material:
		# Update player position in shader
		var player_pos: Vector3 = Vector3.ZERO
		if player.has_method("get_camera_position"):
			player_pos = player.get_camera_position()
		elif player.has_node("PlayerBody"):
			var player_body = player.get_node("PlayerBody")
			player_pos = player_body.global_position
		else:
			player_pos = player.global_position
		
		shader_material.set_shader_parameter("player_position", player_pos)


func _create_terrain_mesh() -> void:
	"""Generate a subdivided plane mesh with height noise"""
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Calculate grid dimensions
	var total_size: float = grid_size * cell_size
	var half_size: float = total_size / 2.0
	
	# Generate vertices with height noise
	for z in range(grid_size + 1):
		for x in range(grid_size + 1):
			var x_pos: float = (x * cell_size) - half_size
			var z_pos: float = (z * cell_size) - half_size
			
			# Apply noise to height
			var height: float = noise.get_noise_2d(x_pos, z_pos) * height_noise_scale
			
			var vertex := Vector3(x_pos, height, z_pos)
			terrain_vertices.append(vertex)
			
			surface_tool.set_normal(Vector3.UP)
			surface_tool.set_uv(Vector2(float(x) / grid_size, float(z) / grid_size))
			surface_tool.add_vertex(vertex)
	
	# Generate triangles
	for z in range(grid_size):
		for x in range(grid_size):
			var i0: int = z * (grid_size + 1) + x
			var i1: int = i0 + 1
			var i2: int = (z + 1) * (grid_size + 1) + x
			var i3: int = i2 + 1
			
			# Triangle 1
			surface_tool.add_index(i0)
			surface_tool.add_index(i2)
			surface_tool.add_index(i1)
			
			# Triangle 2
			surface_tool.add_index(i1)
			surface_tool.add_index(i2)
			surface_tool.add_index(i3)
	
	surface_tool.generate_normals()
	var mesh := surface_tool.commit()
	
	# Create mesh instance
	terrain_mesh_instance = MeshInstance3D.new()
	terrain_mesh_instance.mesh = mesh
	terrain_mesh_instance.name = "TerrainMesh"
	terrain_mesh_instance.layers = 1 << render_layer
	
	# Create a simple material
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.3, 0.2)
	material.roughness = 0.8
	terrain_mesh_instance.material_override = material
	
	add_child(terrain_mesh_instance)


func _create_lines_mesh() -> void:
	"""Generate grid lines mesh"""
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_LINES)
	
	# Helper function to get vertex index
	var get_vertex_idx = func(x: int, z: int) -> int:
		return z * (grid_size + 1) + x
	
	# Generate horizontal lines
	for z in range(grid_size + 1):
		for x in range(grid_size):
			var idx0: int = get_vertex_idx.call(x, z)
			var idx1: int = get_vertex_idx.call(x + 1, z)
			
			surface_tool.add_vertex(terrain_vertices[idx0])
			surface_tool.add_vertex(terrain_vertices[idx1])
	
	# Generate vertical lines
	for x in range(grid_size + 1):
		for z in range(grid_size):
			var idx0: int = get_vertex_idx.call(x, z)
			var idx1: int = get_vertex_idx.call(x, z + 1)
			
			surface_tool.add_vertex(terrain_vertices[idx0])
			surface_tool.add_vertex(terrain_vertices[idx1])
	
	var mesh := surface_tool.commit()
	
	# Create mesh instance for lines
	lines_mesh_instance = MeshInstance3D.new()
	lines_mesh_instance.mesh = mesh
	lines_mesh_instance.name = "GridLines"
	lines_mesh_instance.layers = 1 << render_layer
	
	# Load and setup shader material
	var shader := load("res://assets/shaders/grid_lines.gdshader") as Shader
	shader_material = ShaderMaterial.new()
	shader_material.shader = shader
	
	# Set shader parameters
	shader_material.set_shader_parameter("zone1_distance", zone1_distance)
	shader_material.set_shader_parameter("zone2_distance", zone2_distance)
	shader_material.set_shader_parameter("line_height_offset", line_height_offset)
	shader_material.set_shader_parameter("line_color", line_color)
	shader_material.set_shader_parameter("line_width", line_width)
	shader_material.set_shader_parameter("player_position", Vector3.ZERO)
	
	# Enable transparency
	shader_material.render_priority = 1
	
	lines_mesh_instance.material_override = shader_material
	lines_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	add_child(lines_mesh_instance)
