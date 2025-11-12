extends MeshInstance3D

signal cell_painted(face_index: int, cell_x: int, cell_y: int, color: Color)

const FACE_DEFS: Array[Dictionary] = [
	{"n": Vector3(0, 0, 1), "u": Vector3(1, 0, 0), "v": Vector3(0, 1, 0)},
	{"n": Vector3(0, 0, -1), "u": Vector3(-1, 0, 0), "v": Vector3(0, 1, 0)},
	{"n": Vector3(1, 0, 0), "u": Vector3(0, 0, -1), "v": Vector3(0, 1, 0)},
	{"n": Vector3(-1, 0, 0), "u": Vector3(0, 0, 1), "v": Vector3(0, 1, 0)},
	{"n": Vector3(0, 1, 0), "u": Vector3(1, 0, 0), "v": Vector3(0, 0, -1)},
	{"n": Vector3(0, -1, 0), "u": Vector3(1, 0, 0), "v": Vector3(0, 0, 1)}
]

@export var size: Vector3 = Vector3(2.0, 2.0, 2.0)
@export_range(1, 128, 1) var subdivisions: int = 1
@export var seed: int = 0
@export var material_unshaded: bool = false
@export var flip_winding: bool = false
@export_flags_3d_physics var collision_layers: int = (1 << 0) | (1 << 5)
@export_flags_3d_physics var collision_mask: int = 0
@export var pointer_group: StringName = &"pointer_interactable"
@export var allow_continuous_paint: bool = true
@export var require_pointer_color: bool = false

var _cell_colors: Array = [] # faces x rows x columns
var _paint_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _hover_cell: Dictionary = {}

func _ready() -> void:
	if pointer_group != StringName(""):
		add_to_group(pointer_group)
	if seed != 0:
		_paint_rng.seed = seed + 1
	else:
		_paint_rng.randomize()
	build_mesh()

func build_mesh() -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()

	var nx: int = max(1, subdivisions)
	var ny: int = max(1, subdivisions)
	_ensure_cell_storage(nx, ny, rng)

	for fi in range(FACE_DEFS.size()):
		var face: Dictionary = FACE_DEFS[fi]
		var n: Vector3 = face["n"]
		var u: Vector3 = face["u"]
		var v: Vector3 = face["v"]
		for iy in range(ny):
			for ix in range(nx):
				var su: float = float(ix) / float(nx)
				var eu: float = float(ix + 1) / float(nx)
				var sv: float = float(iy) / float(ny)
				var ev: float = float(iy + 1) / float(ny)

				var p00: Vector3 = ((u * (su - 0.5)) + (v * (sv - 0.5)) + n * 0.5) * size
				var p10: Vector3 = ((u * (eu - 0.5)) + (v * (sv - 0.5)) + n * 0.5) * size
				var p11: Vector3 = ((u * (eu - 0.5)) + (v * (ev - 0.5)) + n * 0.5) * size
				var p01: Vector3 = ((u * (su - 0.5)) + (v * (ev - 0.5)) + n * 0.5) * size

				var normal: Vector3 = n.normalized()
				var col: Color = _cell_colors[fi][iy][ix]

				if flip_winding:
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p00)
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p11)
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p10)

					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p00)
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p01)
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p11)
				else:
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p00)
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p10)
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p11)

					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p00)
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p11)
					st.set_normal(normal)
					st.set_color(col)
					st.add_vertex(p01)

	var meshres: ArrayMesh = st.commit()
	if meshres:
		mesh = meshres
		_assign_material(meshres)
		_ensure_collision(meshres)

func interact_at_point(global_point: Vector3, paint_color: Color) -> bool:
	return paint_cell(global_point, paint_color)

func handle_pointer_event(event: Dictionary) -> void:
	if event.is_empty():
		return
	var event_type: String = String(event.get("type", ""))
	print_debug("subdivided_cube: handle_pointer_event ->", event_type, "from", event.get("handler"))
	match event_type:
		"press":
			_apply_paint_event(event)
		"hold":
			if allow_continuous_paint:
				_apply_paint_event(event)
		"hover":
			# paint when the trigger is just pressed while hovering (match floor behavior)
			if event.get("action_just_pressed", false):
				_apply_paint_event(event)
			elif allow_continuous_paint and event.get("action_pressed", false):
				_apply_paint_event(event)
		"drag":
			if allow_continuous_paint:
				_apply_paint_event(event)
		"enter":
			_hover_cell = _cell_from_world_point(event.get("global_position", global_transform.origin))
		"exit":
			_hover_cell = {}
		_:
			pass

func paint_cell(global_point: Vector3, color_override: Variant = null) -> bool:
	var nx: int = max(1, subdivisions)
	var ny: int = max(1, subdivisions)
	if _cell_colors.size() != FACE_DEFS.size():
		build_mesh()
		if _cell_colors.size() != FACE_DEFS.size():
			return false
		nx = max(1, subdivisions)
		ny = max(1, subdivisions)

	var local_point: Vector3 = global_transform.affine_inverse() * global_point
	var cell: Dictionary = _locate_cell(local_point, nx, ny)
	if cell.is_empty():
		return false

	var fi: int = cell["face"]
	var ix: int = cell["x"]
	var iy: int = cell["y"]
	var new_color: Color = _determine_paint_color(color_override)
	var current_color: Color = _cell_colors[fi][iy][ix]
	if current_color == new_color:
		return false

	_cell_colors[fi][iy][ix] = new_color
	print_debug("subdivided_cube: painted cell", fi, ix, iy, "color", new_color)
	build_mesh()
	cell_painted.emit(fi, ix, iy, new_color)
	return true

func _apply_paint_event(event: Dictionary) -> void:
	if require_pointer_color and not (event.has("pointer_color") and event["pointer_color"] is Color):
		return
	var color_variant: Variant = event.get("pointer_color") if event.has("pointer_color") else null
	var world_point: Vector3 = event.get("global_position", global_transform.origin)
	paint_cell(world_point, color_variant)

func _assign_material(meshres: Mesh) -> void:
	if material_unshaded:
		var shader := Shader.new()
		shader.code = """
		shader_type spatial;
		render_mode unshaded, cull_back;
		void fragment() {
			ALBEDO = COLOR.rgb;
		}
		"""
		var shmat := ShaderMaterial.new()
		shmat.shader = shader
		material_override = shmat
		return

	var mat := StandardMaterial3D.new()
	var assigned := false
	if "vertex_color_use_as_albedo" in mat:
		mat.vertex_color_use_as_albedo = true
		assigned = true
	elif "use_vertex_color" in mat:
		mat.use_vertex_color = true
		assigned = true

	if assigned:
		if "cull_mode" in mat:
			mat.cull_mode = BaseMaterial3D.CULL_BACK
		material_override = mat
	else:
		var shader := Shader.new()
		shader.code = """
		shader_type spatial;
		render_mode unshaded, cull_back;
		void fragment() {
			ALBEDO = COLOR.rgb;
		}
		"""
		var shmat := ShaderMaterial.new()
		shmat.shader = shader
		material_override = shmat

func _ensure_collision(meshres: Mesh) -> void:
	var col_body: StaticBody3D = get_node_or_null("CollisionBody") as StaticBody3D
	if not col_body:
		col_body = StaticBody3D.new()
		col_body.name = "CollisionBody"
		col_body.input_ray_pickable = true
		add_child(col_body)
		if owner:
			col_body.owner = owner

	col_body.collision_layer = collision_layers
	col_body.collision_mask = collision_mask

	var col_shape: CollisionShape3D = col_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not col_shape:
		col_shape = CollisionShape3D.new()
		col_shape.name = "CollisionShape3D"
		col_body.add_child(col_shape)
		if owner:
			col_shape.owner = owner

	if meshres and meshres.has_method("create_trimesh_shape"):
		col_shape.shape = meshres.create_trimesh_shape()
	elif meshres is ArrayMesh:
		col_shape.shape = (meshres as ArrayMesh).create_trimesh_shape()

	col_shape.disabled = false

func _locate_cell(local_point: Vector3, nx: int, ny: int) -> Dictionary:
	for fi in range(FACE_DEFS.size()):
		var face: Dictionary = FACE_DEFS[fi]
		var n: Vector3 = face["n"]
		var u: Vector3 = face["u"]
		var v: Vector3 = face["v"]
		# account for the mesh 'size' when locating which face/cell was hit
		var half: Vector3 = size * 0.5
		var offset_point: Vector3 = Vector3(n.x * half.x, n.y * half.y, n.z * half.z)
		var d: float = (local_point - offset_point).dot(n)
		if abs(d) > 0.001 * max(max(half.x, half.y), half.z):
			continue
		# project onto the face axes and normalize by the corresponding size components
		var size_u: float = abs(u.x) * size.x + abs(u.y) * size.y + abs(u.z) * size.z
		var size_v: float = abs(v.x) * size.x + abs(v.y) * size.y + abs(v.z) * size.z
		if size_u == 0.0 or size_v == 0.0:
			continue
		var su: float = (local_point.dot(u) / size_u) + 0.5
		var sv: float = (local_point.dot(v) / size_v) + 0.5
		if su < 0.0 or su >= 1.0 or sv < 0.0 or sv >= 1.0:
			continue
		var ix: int = clamp(int(floor(su * nx)), 0, nx - 1)
		var iy: int = clamp(int(floor(sv * ny)), 0, ny - 1)
		return {"face": fi, "x": ix, "y": iy}
	return {}

func _cell_from_world_point(global_point: Vector3) -> Dictionary:
	var nx: int = max(1, subdivisions)
	var ny: int = max(1, subdivisions)
	var local_point: Vector3 = global_transform.affine_inverse() * global_point
	return _locate_cell(local_point, nx, ny)

func _determine_paint_color(color_override: Variant) -> Color:
	if color_override is Color:
		return color_override
	return Color(_paint_rng.randf(), _paint_rng.randf(), _paint_rng.randf(), 1.0)

func _ensure_cell_storage(nx: int, ny: int, rng: RandomNumberGenerator) -> void:
	if _cell_colors.size() != FACE_DEFS.size():
		_cell_colors.clear()
		for _i in range(FACE_DEFS.size()):
			_cell_colors.append(_create_face_color_grid(nx, ny, rng))
		return

	for fi in range(FACE_DEFS.size()):
		var face_arr: Array = _cell_colors[fi]
		if face_arr.size() != ny:
			_cell_colors[fi] = _create_face_color_grid(nx, ny, rng)
			continue
		for row_index in range(ny):
			var row: Array = face_arr[row_index]
			if row.size() != nx:
				face_arr[row_index] = _create_color_row(nx, rng)

func _create_face_color_grid(nx: int, ny: int, rng: RandomNumberGenerator) -> Array:
	var face_arr: Array = []
	for _y in range(ny):
		face_arr.append(_create_color_row(nx, rng))
	return face_arr

func _create_color_row(nx: int, rng: RandomNumberGenerator) -> Array:
	var row: Array = []
	for _x in range(nx):
		row.append(Color(rng.randf(), rng.randf(), rng.randf(), 1.0))
	return row
