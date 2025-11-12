extends MeshInstance3D

@export var size: Vector3 = Vector3(2.0, 2.0, 2.0)
@export var subdivisions: int = 16
@export var seed: int = 0
@export var material_unshaded: bool = false
@export var flip_winding: bool = false

func _ready() -> void:
	build_mesh()

func build_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rng := RandomNumberGenerator.new()
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()

	# Faces: normal, u axis, v axis (local cube centered at origin, size 1)
	var faces = [
		{"n": Vector3(0,0,1), "u": Vector3(1,0,0), "v": Vector3(0,1,0)},
		{"n": Vector3(0,0,-1), "u": Vector3(-1,0,0), "v": Vector3(0,1,0)},
		{"n": Vector3(1,0,0), "u": Vector3(0,0,-1), "v": Vector3(0,1,0)},
		{"n": Vector3(-1,0,0), "u": Vector3(0,0,1), "v": Vector3(0,1,0)},
		{"n": Vector3(0,1,0), "u": Vector3(1,0,0), "v": Vector3(0,0,-1)},
		{"n": Vector3(0,-1,0), "u": Vector3(1,0,0), "v": Vector3(0,0,1)}
	]

	var half = Vector3(0.5,0.5,0.5)
	var nx = max(1, subdivisions)
	var ny = max(1, subdivisions)

	for f in faces:
		var n: Vector3 = f["n"]
		var u: Vector3 = f["u"]
		var v: Vector3 = f["v"]
		# For each cell
		for iy in range(ny):
			for ix in range(nx):
				# cell corners in [-0.5,0.5] range
				var su = float(ix) / nx
				var eu = float(ix+1) / nx
				var sv = float(iy) / ny
				var ev = float(iy+1) / ny

				# positions
				var p00 = ( (u * (su - 0.5)) + (v * (sv - 0.5)) + n * 0.5 ) * size
				var p10 = ( (u * (eu - 0.5)) + (v * (sv - 0.5)) + n * 0.5 ) * size
				var p11 = ( (u * (eu - 0.5)) + (v * (ev - 0.5)) + n * 0.5 ) * size
				var p01 = ( (u * (su - 0.5)) + (v * (ev - 0.5)) + n * 0.5 ) * size

				var normal = n.normalized()
				# random color per cell
				var col = Color(rng.randf(), rng.randf(), rng.randf(), 1.0)

				# triangle 1: p00, p10, p11
				if not flip_winding:
					# triangle 1: p00, p10, p11
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p00)
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p10)
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p11)

					# triangle 2: p00, p11, p01
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p00)
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p11)
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p01)
				else:
					# flipped winding: invert the vertex order so outside faces remain
					# front-facing when transforms flip winding
					# triangle 1: p00, p11, p10
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p00)
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p11)
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p10)

					# triangle 2: p00, p01, p11
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p00)
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p01)
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p11)

	# commit
	var meshres = st.commit()
	if meshres:
		mesh = meshres
		# create a simple material that uses vertex colors
		var mat = StandardMaterial3D.new()
		# Use vertex color for albedo if property exists; set defensively
		var assigned := false
		# Try to enable vertex color on StandardMaterial3D if supported
		if mat is StandardMaterial3D:
			if "vertex_color_use_as_albedo" in mat:
				mat.vertex_color_use_as_albedo = true
				assigned = true
			elif "use_vertex_color" in mat:
				mat.use_vertex_color = true
				assigned = true
		# If the StandardMaterial didn't expose vertex color control, fall back
		# to a simple ShaderMaterial that uses the VERTEX_COLOR input.
		if not assigned:
			var shader := Shader.new()
			# explicitly enable back-face culling in the shader fallback so
			# the cube won't render interior faces when viewed from outside
			shader.code = """
			shader_type spatial;
			render_mode unshaded, cull_back;
			void fragment() {
				ALBEDO = VERTEX_COLOR.rgb;
			}
			"""
			var shmat := ShaderMaterial.new()
			shmat.shader = shader
			material_override = shmat
		else:
			# ensure back-face culling is enabled on the StandardMaterial3D
			# (use the BaseMaterial3D enum value for clarity)
			if "cull_mode" in mat:
				mat.cull_mode = BaseMaterial3D.CULL_BACK
			material_override = mat
