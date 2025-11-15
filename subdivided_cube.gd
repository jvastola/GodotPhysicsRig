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
@export var subdivisions_axis: Vector3i = Vector3i(4, 4, 4)
@export var seed: int = 0
@export var material_unshaded: bool = false
@export var flip_winding: bool = false
@export_flags_3d_physics var collision_layers: int = (1 << 0) | (1 << 5)
@export_flags_3d_physics var collision_mask: int = 0
@export var pointer_group: StringName = &"pointer_interactable"
@export var allow_continuous_paint: bool = true
@export var require_pointer_color: bool = false
@export var debug_logs: bool = false

var _cell_colors: Array = [] # faces x rows x columns
var _paint_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _hover_cell: Dictionary = {}
var _face_cell_dims: Array = []

func _axis_counts() -> Vector3i:
	return Vector3i(
		max(1, subdivisions_axis.x),
		max(1, subdivisions_axis.y),
		max(1, subdivisions_axis.z)
	)

func _count_for_axis(axis: Vector3, axis_counts: Vector3i) -> int:
	var abs_axis := axis.abs()
	if abs_axis.x > 0.5:
		return axis_counts.x
	elif abs_axis.y > 0.5:
		return axis_counts.y
	else:
		return axis_counts.z

func _compute_face_dims(axis_counts: Vector3i) -> Array:
	var dims: Array = []
	for face in FACE_DEFS:
		var u_div := _count_for_axis(face["u"], axis_counts)
		var v_div := _count_for_axis(face["v"], axis_counts)
		dims.append(Vector2i(u_div, v_div))
	return dims

func _subdivision_meta_matches(meta: Variant, axis_counts: Vector3i) -> bool:
	if meta is Vector3i:
		return meta == axis_counts
	elif meta is Vector3:
		return Vector3i(int(meta.x), int(meta.y), int(meta.z)) == axis_counts
	elif meta is Dictionary and meta.has("x") and meta.has("y") and meta.has("z"):
		return Vector3i(int(meta["x"]), int(meta["y"]), int(meta["z"])) == axis_counts
	elif meta is Array and meta.size() >= 3:
		return Vector3i(int(meta[0]), int(meta[1]), int(meta[2])) == axis_counts
	else:
		var uniform := int(meta)
		return axis_counts.x == uniform and axis_counts.y == uniform and axis_counts.z == uniform

func _ready() -> void:
	if pointer_group != StringName(""):
		add_to_group(pointer_group)
	if seed != 0:
		_paint_rng.seed = seed + 1
	else:
		_paint_rng.randomize()
	
	# Try to load saved paint state
	_load_paint_state()
	
	build_mesh()

func build_mesh() -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()

	var axis_counts: Vector3i = _axis_counts()
	_face_cell_dims = _compute_face_dims(axis_counts)
	_ensure_cell_storage(_face_cell_dims, rng)

	for fi in range(FACE_DEFS.size()):
		var face: Dictionary = FACE_DEFS[fi] as Dictionary
		var dims: Vector2i = _face_cell_dims[fi]
		var nx: int = max(1, dims.x)
		var ny: int = max(1, dims.y)
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
	# Reduce noisy per-frame logging. Only emit logs for important transitions
	# or when debug_logs is explicitly enabled.
	if debug_logs:
		print_debug("subdivided_cube: handle_pointer_event ->", event_type, "from", event.get("handler"))
	match event_type:
		"press":
			if debug_logs:
				print_debug("subdivided_cube: press event, applying paint at", event.get("global_position"))
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
			if debug_logs:
				print_debug("subdivided_cube: enter -> cell", _hover_cell)
		"exit":
			_hover_cell = {}
			if debug_logs:
				print_debug("subdivided_cube: exit")
		_:
			pass

func paint_cell(global_point: Vector3, color_override: Variant = null) -> bool:
	if _cell_colors.size() != FACE_DEFS.size() or _face_cell_dims.size() != FACE_DEFS.size():
		build_mesh()
		if _cell_colors.size() != FACE_DEFS.size():
			return false

	var local_point: Vector3 = global_transform.affine_inverse() * global_point
	var cell: Dictionary = _locate_cell(local_point)
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
	if debug_logs:
		print_debug("subdivided_cube: painted cell", fi, ix, iy, "color", new_color)
	build_mesh()
	cell_painted.emit(fi, ix, iy, new_color)
	_update_player_head_texture()
	
	# Save paint state to disk
	_save_paint_state()
	
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

func _locate_cell(local_point: Vector3) -> Dictionary:
	if _face_cell_dims.size() != FACE_DEFS.size():
		_face_cell_dims = _compute_face_dims(_axis_counts())
	for fi in range(FACE_DEFS.size()):
		var face: Dictionary = FACE_DEFS[fi]
		var dims: Vector2i = _face_cell_dims[fi]
		var nx: int = max(1, dims.x)
		var ny: int = max(1, dims.y)
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
	var local_point: Vector3 = global_transform.affine_inverse() * global_point
	return _locate_cell(local_point)

func _determine_paint_color(color_override: Variant) -> Color:
	if color_override is Color:
		return color_override
	return Color(_paint_rng.randf(), _paint_rng.randf(), _paint_rng.randf(), 1.0)

func _ensure_cell_storage(face_dims: Array, rng: RandomNumberGenerator) -> void:
	if _cell_colors.size() != FACE_DEFS.size():
		_cell_colors.clear()
		for fi in range(FACE_DEFS.size()):
			var dims: Vector2i = face_dims[fi]
			_cell_colors.append(_create_face_color_grid(max(1, dims.x), max(1, dims.y), rng))
		return

	for fi in range(FACE_DEFS.size()):
		var dims: Vector2i = face_dims[fi]
		var nx: int = max(1, dims.x)
		var ny: int = max(1, dims.y)
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


func _update_player_head_texture() -> void:
	"""Generate texture from current cell colors and apply to XR player head mesh"""
	var player_body = get_tree().get_first_node_in_group("player")
	if not player_body:
		print("subdivided_cube: No player found in group 'player'")
		return
	
	# The player script is on the parent of PlayerBody
	var player = player_body.get_parent()
	if not player:
		print("subdivided_cube: PlayerBody has no parent")
		return
	
	print("subdivided_cube: Found player: ", player.name, ", script: ", player.get_script())
	
	if not player.has_method("apply_texture_to_head"):
		print("subdivided_cube: Player does not have apply_texture_to_head method")
		return
	
	print("subdivided_cube: Found player, generating texture...")
	var texture: ImageTexture = _generate_texture_from_cells()
	if texture:
		print("subdivided_cube: Applying texture to player head, size: ", texture.get_width(), "x", texture.get_height())
		player.apply_texture_to_head(texture)
	else:
		print("subdivided_cube: Failed to generate texture")


func _generate_texture_from_cells() -> ImageTexture:
	"""Generate a texture from the current cell colors with UV layout"""
	if _face_cell_dims.size() != FACE_DEFS.size():
		_face_cell_dims = _compute_face_dims(_axis_counts())

	print("subdivided_cube: Generating texture with per-face dims: ", _face_cell_dims)

	var column_faces := [
		[3, 1],  # left/back column
		[4, 0],  # top/front column
		[2, 5]   # right/bottom column
	]
	var row_faces := [
		[3, 4, 2],  # top row
		[1, 0, 5]   # bottom row
	]

	var col_widths: Array[int] = []
	for faces in column_faces:
		var width := 1
		for fi in faces:
			width = max(width, _face_cell_dims[fi].x)
		col_widths.append(width)

	var row_heights: Array[int] = []
	for faces in row_faces:
		var height := 1
		for fi in faces:
			height = max(height, _face_cell_dims[fi].y)
		row_heights.append(height)

	var tex_width := 0
	for width in col_widths:
		tex_width += width
	var tex_height := 0
	for height in row_heights:
		tex_height += height

	var img := Image.create(tex_width, tex_height, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	var col_offsets: Array[int] = []
	var acc := 0
	for width in col_widths:
		col_offsets.append(acc)
		acc += width
	var row_offsets: Array[int] = []
	acc = 0
	for height in row_heights:
		row_offsets.append(acc)
		acc += height

	var face_to_row := [1, 1, 0, 0, 0, 1]
	var face_to_col := [1, 0, 2, 0, 1, 2]

	for fi in range(FACE_DEFS.size()):
		var dims: Vector2i = _face_cell_dims[fi]
		var offset: Vector2i = Vector2i(col_offsets[face_to_col[fi]], row_offsets[face_to_row[fi]])

		# The allocated slot for this face may be larger than the face's
		# subdivided dims (because col/row sizes are the max within the
		# column/row group). Fill any extra pixels by repeating the nearest
		# cell edge color so we don't leave transparent gaps.
		var alloc_w: int = col_widths[face_to_col[fi]]
		var alloc_h: int = row_heights[face_to_row[fi]]
		# Map the face's cell grid evenly to the allocated slot. We pick the
		# nearest source cell for each output pixel by scaling the indices so
		# each cell fills alloc_w/nx pixels in X (and alloc_h/ny in Y).
		var nx: int = max(1, dims.x)
		var ny: int = max(1, dims.y)
		for iy in range(alloc_h):
			var sample_y: int = clamp(int(floor(float(iy) * float(ny) / float(alloc_h))), 0, ny - 1)
			for ix in range(alloc_w):
				var sample_x: int = clamp(int(floor(float(ix) * float(nx) / float(alloc_w))), 0, nx - 1)
				var color: Color = _cell_colors[fi][sample_y][sample_x]
				img.set_pixel(offset.x + ix, offset.y + iy, color)

	return ImageTexture.create_from_image(img)


func _save_paint_state() -> void:
	"""Save current paint state to SaveManager"""
	if not SaveManager:
		return
	SaveManager.save_head_paint(_cell_colors, _axis_counts())


func _load_paint_state() -> void:
	"""Load saved paint state from SaveManager"""
	if not SaveManager:
		return
	
	var paint_data := SaveManager.load_head_paint()
	if paint_data.is_empty():
		print("subdivided_cube: No saved paint state found")
		return
	
	# Validate loaded data matches current subdivision signature
	var axis_counts: Vector3i = _axis_counts()
	var saved_subdivisions: Variant = paint_data.get("subdivisions", axis_counts)
	if not _subdivision_meta_matches(saved_subdivisions, axis_counts):
		print("subdivided_cube: Saved subdivisions (", saved_subdivisions, ") != current (", axis_counts, "), ignoring saved paint")
		return
	
	var saved_colors: Array = paint_data.get("cell_colors", [])
	if saved_colors.size() == FACE_DEFS.size():
		_cell_colors = saved_colors
		print("subdivided_cube: Loaded saved paint state with axis counts ", axis_counts)
		# Will rebuild mesh and update head texture after this returns
	else:
		print("subdivided_cube: Saved cell colors size mismatch, ignoring")
