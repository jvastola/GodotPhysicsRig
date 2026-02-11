
extends Node3D
class_name GridPainter

const TILE_PIXELS: int = 16
const SURFACE_LEFT_HAND := "left_hand"
const SURFACE_RIGHT_HAND := "right_hand"
const SURFACE_HEAD := "head"
const SURFACE_BODY := "body"

@export_group("Player Surfaces")
@export_node_path("Node3D") var player_root_path: NodePath = NodePath("../XRPlayer")
@export var load_for_player: bool = true
@export var link_hands: bool = true
@export var player_target_name: String = "LeftHandMesh"
@export var hand_material_base: Material = preload("res://world_grab_demo/ghost_hand.tres")

@export_subgroup("Hands")
@export_node_path("MeshInstance3D") var left_hand_target: NodePath = NodePath("PlayerBody/XROrigin3D/LeftController/LeftHandMesh")
@export_node_path("MeshInstance3D") var left_hand_path: NodePath = NodePath("PlayerBody/XROrigin3D/LeftController/LeftHandMesh")
@export_node_path("MeshInstance3D") var left_hand_preview_mesh: NodePath = NodePath("")
@export var left_hand_subdivisions: Vector3i = Vector3i(4, 4, 1)
@export_node_path("MeshInstance3D") var right_hand_target: NodePath = NodePath("PlayerBody/XROrigin3D/RightController/RightHandMesh")
@export_node_path("MeshInstance3D") var right_hand_path: NodePath = NodePath("PlayerBody/XROrigin3D/RightController/RightHandMesh")
@export_node_path("MeshInstance3D") var right_hand_preview_mesh: NodePath = NodePath("")
@export var right_hand_subdivisions: Vector3i = Vector3i(4, 4, 1)

@export_subgroup("Head")
@export_node_path("MeshInstance3D") var head_target: NodePath = NodePath("PlayerBody/XROrigin3D/XRCamera3D/HeadArea/HeadMesh")
@export_node_path("MeshInstance3D") var head_path: NodePath = NodePath("PlayerBody/XROrigin3D/XRCamera3D/HeadArea/HeadMesh")
@export_node_path("MeshInstance3D") var head_preview_mesh: NodePath = NodePath("")
@export var head_subdivisions: Vector3i = Vector3i(8, 8, 2)

@export_subgroup("Body")
@export_node_path("MeshInstance3D") var body_target: NodePath = NodePath("PlayerBody/XROrigin3D/XRCamera3D/HeadArea/BodyMesh")
@export_node_path("MeshInstance3D") var body_path: NodePath = NodePath("PlayerBody/XROrigin3D/XRCamera3D/HeadArea/BodyMesh")
@export_node_path("MeshInstance3D") var body_preview_mesh: NodePath = NodePath("")
@export var body_subdivisions: Vector3i = Vector3i(8, 4, 2)

@export var developer_mode: bool = false
@export_group("Debug")
var _reset_saved_grid_data_button := false
@export var reset_saved_grid_data_button: bool:
	get:
		return _reset_saved_grid_data_button
	set(value):
		if value:
			reset_grid_data()
		_reset_saved_grid_data_button = false
@export_group("")

const FACE_DEFS: Array = [
	{"n": Vector3(0, 0, 1), "u": Vector3(1, 0, 0), "v": Vector3(0, 1, 0)},
	{"n": Vector3(0, 0, -1), "u": Vector3(-1, 0, 0), "v": Vector3(0, 1, 0)},
	{"n": Vector3(1, 0, 0), "u": Vector3(0, 0, -1), "v": Vector3(0, 1, 0)},
	{"n": Vector3(-1, 0, 0), "u": Vector3(0, 0, 1), "v": Vector3(0, 1, 0)},
	{"n": Vector3(0, 1, 0), "u": Vector3(1, 0, 0), "v": Vector3(0, 0, -1)},
	{"n": Vector3(0, -1, 0), "u": Vector3(1, 0, 0), "v": Vector3(0, 0, 1)}
]

class SurfaceSlot extends RefCounted:
	var id: String = ""
	var target_relative: NodePath = NodePath("")
	var paint_relative: NodePath = NodePath("")
	var extra_targets: Array[NodePath] = []
	var subdivisions_axis: Vector3i = Vector3i(8, 8, 1)
	var use_player_root: bool = false
	var grid_size_x: int = 1
	var grid_size_y: int = 1
	var grid_colors: Array = []
	var face_cell_dims: Array = []
	var face_offsets: Array = []
	var texture: ImageTexture = null
	var resolved_target_path: NodePath = NodePath("")
	var resolved_paint_path: NodePath = NodePath("")
	var resolved_extra_paths: Array[NodePath] = []
	var preview_meshes: Array[NodePath] = []

	func grid_w() -> int:
		return max(1, grid_size_x)

	func grid_h() -> int:
		return max(1, grid_size_y)

	func matches_origin(origin: NodePath) -> bool:
		if origin == NodePath(""):
			return false
		if resolved_paint_path != NodePath("") and origin == resolved_paint_path:
			return true
		if resolved_target_path != NodePath("") and origin == resolved_target_path:
			return true
		for extra in resolved_extra_paths:
			if extra != NodePath("") and origin == extra:
				return true
		return String(origin) != "" and String(resolved_paint_path) == String(origin)

var _surfaces: Dictionary = {}
var _surface_aliases: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _handler_script: Script = null
var _save_path: String = "user://grid_painter_surfaces.json"
var _save_pending: bool = false
var _save_timer: float = 0.0
var _network_update_pending: bool = false
var _network_update_timer: float = 0.0
var _last_paint_time: float = 0.0
const SAVE_DEBOUNCE_TIME: float = 0.5  # Save at most every 0.5 seconds during continuous painting
const NETWORK_UPDATE_DEBOUNCE_TIME: float = 3.0  # Wait 3 seconds after last paint before sending
const NETWORK_UPDATE_IDLE_CHECK: float = 0.1  # Check every 0.1 seconds if painting has stopped

func _ready() -> void:
	print("GridPainter: _ready() called, load_for_player: ", load_for_player)
	_rng.randomize()
	_load_handler_script()
	print("GridPainter: Registered surfaces: ", _surfaces.keys())
	# Always load saved grid data so both player and preview grids show the same state
	print("GridPainter: Loading saved grid data from: ", _save_path)
	load_grid_data(_save_path)
	# Defer surface resolution and texture application to ensure player meshes are ready
	call_deferred("_deferred_init")


func _process(delta: float) -> void:
	# Handle debounced save
	if _save_pending:
		_save_timer -= delta
		if _save_timer <= 0.0:
			_save_pending = false
			save_grid_data(_save_path)
	
	# Handle debounced network update with idle detection
	if _network_update_pending:
		# Check if user has stopped painting (idle for NETWORK_UPDATE_DEBOUNCE_TIME)
		var time_since_last_paint = Time.get_ticks_msec() / 1000.0 - _last_paint_time
		if time_since_last_paint >= NETWORK_UPDATE_DEBOUNCE_TIME:
			# User stopped painting, send update now
			_network_update_pending = false
			_trigger_network_avatar_update()
			print("GridPainter: Sending avatar update after ", snappedf(time_since_last_paint, 0.1), "s idle")


func _schedule_save() -> void:
	"""Schedule a debounced save to avoid excessive file writes during continuous painting"""
	if not _save_pending:
		_save_pending = true
		_save_timer = SAVE_DEBOUNCE_TIME


func _schedule_network_update() -> void:
	"""Schedule a debounced network avatar update to avoid flooding the network during continuous painting"""
	if load_for_player:
		# Mark that we have pending changes
		_network_update_pending = true
		# Update the last paint time
		_last_paint_time = Time.get_ticks_msec() / 1000.0


func _deferred_init() -> void:
	"""Deferred initialization to ensure player meshes are ready"""
	print("GridPainter: Resolving surface nodes...")
	_resolve_all_surface_nodes()
	_attach_handler_scripts()
	print("GridPainter: Applying all surface textures, surfaces count: ", _surfaces.size())
	_apply_all_surface_textures()
	print("GridPainter: _ready() complete")


func _load_handler_script() -> void:
	if _handler_script:
		return
	if FileAccess.file_exists("res://src/systems/grid_painter_handler.gd"):
		_handler_script = preload("res://src/systems/grid_painter_handler.gd")
	_surfaces.clear()
	_surface_aliases.clear()
	if load_for_player:
		_register_player_surfaces()
	else:
		_register_preview_only_surfaces()

func _register_player_surfaces() -> void:
	var left_previews: Array[NodePath] = _collect_node_paths([left_hand_preview_mesh])
	var right_previews: Array[NodePath] = _collect_node_paths([right_hand_preview_mesh])
	if link_hands:
		var shared_previews: Array[NodePath] = left_previews.duplicate()
		for preview in right_previews:
			if not shared_previews.has(preview):
				shared_previews.append(preview)
		var linked_extras: Array[NodePath] = _collect_node_paths([right_hand_target, right_hand_path])
		var shared_surface := _register_player_surface(SURFACE_LEFT_HAND, left_hand_target, left_hand_path, left_hand_subdivisions, shared_previews, linked_extras)
		if shared_surface:
			_surface_aliases[SURFACE_RIGHT_HAND] = SURFACE_LEFT_HAND
	else:
		_register_player_surface(SURFACE_LEFT_HAND, left_hand_target, left_hand_path, left_hand_subdivisions, left_previews)
		_register_player_surface(SURFACE_RIGHT_HAND, right_hand_target, right_hand_path, right_hand_subdivisions, right_previews)
	var head_previews: Array[NodePath] = _collect_node_paths([head_preview_mesh])
	_register_player_surface(SURFACE_HEAD, head_target, head_path, head_subdivisions, head_previews)
	var body_previews: Array[NodePath] = _collect_node_paths([body_preview_mesh])
	_register_player_surface(SURFACE_BODY, body_target, body_path, body_subdivisions, body_previews)

func _register_preview_only_surfaces() -> void:
	var left_previews: Array[NodePath] = _collect_node_paths([left_hand_preview_mesh])
	var right_previews: Array[NodePath] = _collect_node_paths([right_hand_preview_mesh])
	if link_hands:
		var shared_previews: Array[NodePath] = left_previews.duplicate()
		for preview in right_previews:
			if not shared_previews.has(preview):
				shared_previews.append(preview)
		if not shared_previews.is_empty():
			var canonical_id := SURFACE_LEFT_HAND if left_previews.size() > 0 else SURFACE_RIGHT_HAND
			var alias_id := SURFACE_RIGHT_HAND if canonical_id == SURFACE_LEFT_HAND else SURFACE_LEFT_HAND
			var shared_subdivs := left_hand_subdivisions if canonical_id == SURFACE_LEFT_HAND else right_hand_subdivisions
			var shared_surface := _register_preview_surface(canonical_id, shared_previews[0], shared_subdivs, shared_previews)
			if shared_surface and canonical_id != alias_id:
				_surface_aliases[alias_id] = canonical_id
	else:
		if left_previews.size() > 0:
			_register_preview_surface(SURFACE_LEFT_HAND, left_previews[0], left_hand_subdivisions, left_previews)
		if right_previews.size() > 0:
			_register_preview_surface(SURFACE_RIGHT_HAND, right_previews[0], right_hand_subdivisions, right_previews)
	var head_previews: Array[NodePath] = _collect_node_paths([head_preview_mesh])
	if head_previews.size() > 0:
		_register_preview_surface(SURFACE_HEAD, head_previews[0], head_subdivisions, head_previews)
	var body_previews: Array[NodePath] = _collect_node_paths([body_preview_mesh])
	if body_previews.size() > 0:
		_register_preview_surface(SURFACE_BODY, body_previews[0], body_subdivisions, body_previews)

func _register_player_surface(id: String, target: NodePath, painter_path: NodePath, subdivs: Vector3i, preview_paths: Array[NodePath] = [], extra_meshes: Array[NodePath] = []) -> SurfaceSlot:
	if target == NodePath("") and painter_path == NodePath("") and extra_meshes.size() == 0:
		return null
	var surface := _create_surface(id, target, painter_path, subdivs, true, extra_meshes)
	surface.preview_meshes = preview_paths.duplicate()
	_surfaces[id] = surface
	return surface

func _register_preview_surface(id: String, target: NodePath, subdivs: Vector3i, preview_paths: Array[NodePath] = []) -> SurfaceSlot:
	if target == NodePath(""):
		return null
	var extras: Array[NodePath] = []
	for path in preview_paths:
		if path != target:
			extras.append(path)
	var surface := _create_surface(id, target, target, subdivs, false, extras)
	surface.preview_meshes = preview_paths.duplicate()
	_surfaces[id] = surface
	return surface

func _collect_node_paths(paths: Array) -> Array[NodePath]:
	var result: Array[NodePath] = []
	for entry in paths:
		if not (entry is NodePath):
			continue
		var node_path: NodePath = entry
		if node_path == NodePath(""):
			continue
		if result.has(node_path):
			continue
		result.append(node_path)
	return result

func _create_surface(id: String, target: NodePath, painter_path: NodePath, subdivs: Vector3i, use_player: bool, extras: Array[NodePath] = []) -> SurfaceSlot:
	var surface := SurfaceSlot.new()
	surface.id = id
	surface.target_relative = target
	surface.paint_relative = painter_path if painter_path != NodePath("") else target
	surface.extra_targets = extras.duplicate()
	surface.subdivisions_axis = subdivs
	surface.use_player_root = use_player
	_apply_subdivisions_to_surface(surface, subdivs)
	return surface

func _apply_subdivisions_to_surface(surface: SurfaceSlot, axis_counts: Vector3i) -> void:
	var counts := Vector3i(max(1, axis_counts.x), max(1, axis_counts.y), max(1, axis_counts.z))
	var face_dims: Array = []
	for face in FACE_DEFS:
		var u_div := _count_for_axis(face["u"], counts)
		var v_div := _count_for_axis(face["v"], counts)
		face_dims.append(Vector2i(u_div, v_div))
	var row_faces: Array = [[3, 4, 2], [1, 0, 5]]
	var row_widths: Array[int] = []
	var row_face_offsets: Array = []
	var row_heights: Array[int] = []
	for faces in row_faces:
		var offsets: Array[int] = []
		var acc := 0
		for fi in faces:
			offsets.append(acc)
			acc += face_dims[fi].x
		row_face_offsets.append(offsets)
		row_widths.append(acc)
		var row_h := 0
		for fi in faces:
			row_h = max(row_h, face_dims[fi].y)
		row_heights.append(row_h)
	var tex_w := 0
	for w in row_widths:
		tex_w = max(tex_w, w)
	var tex_h := 0
	for h in row_heights:
		tex_h += h
	surface.grid_size_x = max(1, tex_w)
	surface.grid_size_y = max(1, tex_h)
	surface.face_cell_dims = face_dims
	surface.face_offsets = []
	var y_acc := 0
	for row_idx in range(row_faces.size()):
		var faces: Array = row_faces[row_idx]
		var offsets: Array = row_face_offsets[row_idx]
		for idx in range(faces.size()):
			surface.face_offsets.append(Vector2i(offsets[idx], y_acc))
		y_acc += row_heights[row_idx]
	_reset_surface(surface)

func _reset_surface(surface: SurfaceSlot) -> void:
	surface.grid_colors = []
	for y in range(surface.grid_h()):
		var row: Array = []
		for x in range(surface.grid_w()):
			row.append(Color(0, 0, 0, 0))
		surface.grid_colors.append(row)
	surface.texture = null

func _resolve_all_surface_nodes() -> void:
	for surface in _surfaces.values():
		if surface is SurfaceSlot:
			_resolve_surface_paths(surface)

func _resolve_surface_paths(surface: SurfaceSlot) -> void:
	var base := _get_surface_base(surface)
	if base == null:
		print("GridPainter: Cannot resolve paths for surface ", surface.id, " - base is null")
		return
	print("GridPainter: Resolving surface ", surface.id, " from base: ", base.name)
	if surface.target_relative != NodePath(""):
		var target_node := base.get_node_or_null(surface.target_relative)
		if target_node and target_node is MeshInstance3D:
			surface.resolved_target_path = target_node.get_path()
			print("GridPainter:   Target resolved: ", surface.resolved_target_path)
		else:
			print("GridPainter:   Target NOT found at: ", surface.target_relative)
	if surface.paint_relative != NodePath(""):
		var paint_node := base.get_node_or_null(surface.paint_relative)
		if paint_node and paint_node is MeshInstance3D:
			surface.resolved_paint_path = paint_node.get_path()
			print("GridPainter:   Paint resolved: ", surface.resolved_paint_path)
		else:
			print("GridPainter:   Paint NOT found at: ", surface.paint_relative)
	surface.resolved_extra_paths = []
	for extra in surface.extra_targets:
		var extra_node := base.get_node_or_null(extra)
		if extra_node and extra_node is MeshInstance3D:
			surface.resolved_extra_paths.append(extra_node.get_path())
		else:
			surface.resolved_extra_paths.append(NodePath(""))
	for preview_path in surface.preview_meshes:
		if preview_path == NodePath(""):
			continue
		var preview_node := get_node_or_null(preview_path)
		if preview_node and preview_node is MeshInstance3D:
			surface.resolved_extra_paths.append(preview_node.get_path())

func _get_surface_base(surface: SurfaceSlot) -> Node:
	return _get_player_root() if surface.use_player_root else self

func _get_player_root() -> Node:
	if player_root_path == NodePath(""):
		return null
	var from_self := get_node_or_null(player_root_path)
	if from_self:
		return from_self
	var root := get_tree().get_current_scene()
	return root.get_node_or_null(player_root_path) if root else null

func _attach_handler_scripts() -> void:
	if not _handler_script:
		return
	for surface in _surfaces.values():
		if not (surface is SurfaceSlot):
			continue
		var targets: Array = []
		var tnode := _resolve_surface_node(surface, true)
		if tnode:
			targets.append(tnode)
		var paint_node := _resolve_surface_node(surface, false)
		if paint_node and paint_node not in targets:
			targets.append(paint_node)
		for idx in range(surface.resolved_extra_paths.size()):
			var extra_node := _resolve_surface_node(surface, true, idx)
			if extra_node and extra_node not in targets:
				targets.append(extra_node)
		for node in targets:
			if node and node is MeshInstance3D:
				node.set_script(_handler_script)
				if node.has_method("set"):
					node.set("painter", self.get_path())

func _apply_all_surface_textures() -> void:
	for id in _surfaces.keys():
		_apply_surface_texture(_get_surface(id), true, true)

func _apply_surface_texture(surface: SurfaceSlot, apply_primary: bool = true, apply_extras: bool = true) -> void:
	if not surface:
		print("GridPainter: _apply_surface_texture - surface is null")
		return
	print("GridPainter: Applying texture for surface: ", surface.id)
	if not surface.texture:
		surface.texture = _build_texture_from_surface(surface)
	if apply_primary:
		var target_node := _resolve_surface_node(surface, true)
		if target_node:
			print("GridPainter: Found target node for ", surface.id, ": ", target_node.name)
			var cube_mesh := _build_cube_mesh_for_node(surface, target_node)
			_assign_texture_to_mesh(target_node, surface.texture, cube_mesh)
		else:
			print("GridPainter: No target node found for ", surface.id)
	if apply_extras:
		for idx in range(surface.resolved_extra_paths.size()):
			var extra_node := _resolve_surface_node(surface, true, idx)
			if extra_node:
				var cube_mesh := _build_cube_mesh_for_node(surface, extra_node)
				_assign_texture_to_mesh(extra_node, surface.texture, cube_mesh)

func _build_cube_mesh_for_node(surface: SurfaceSlot, node: MeshInstance3D) -> ArrayMesh:
	var cube_size := _get_mesh_size_for_node(node)
	return _generate_cube_mesh_with_uvs_for_surface(surface, cube_size)

func _get_mesh_size_for_node(node: MeshInstance3D) -> Vector3:
	var default_size := Vector3.ONE
	if not node or not node.mesh:
		return default_size
	var aabb := node.mesh.get_aabb()
	var size := aabb.size
	# Ensure we don't end up with a zero-size cube if the mesh had collapsed geometry.
	if size.x <= 0.0001:
		size.x = 1.0
	if size.y <= 0.0001:
		size.y = 1.0
	if size.z <= 0.0001:
		size.z = 1.0
	return size

func _resolve_surface_node(surface: SurfaceSlot, is_primary: bool, extra_index: int = -1) -> MeshInstance3D:
	var path := NodePath("")
	if extra_index >= 0:
		if extra_index < surface.resolved_extra_paths.size():
			path = surface.resolved_extra_paths[extra_index]
	elif is_primary:
		path = surface.resolved_target_path
	else:
		path = surface.resolved_paint_path if surface.resolved_paint_path != NodePath("") else surface.resolved_target_path
	if path == NodePath(""):
		return null
	var node := get_node_or_null(path)
	return node if node and node is MeshInstance3D else null

func _assign_texture_to_mesh(node: MeshInstance3D, texture: ImageTexture, cube_mesh: ArrayMesh) -> void:
	if cube_mesh:
		node.mesh = cube_mesh
	var mat: StandardMaterial3D
	
	# Check if this node is a hand mesh to apply ghosting effect
	var is_hand = false
	if node.is_in_group("physics_hand") or "HandMesh" in node.name:
		is_hand = true
		
	if is_hand and hand_material_base:
		mat = hand_material_base.duplicate()
	else:
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		
	mat.albedo_texture = texture
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if "cull_mode" in mat:
		mat.cull_mode = BaseMaterial3D.CULL_BACK
	node.material_override = mat

func _build_texture_from_surface(surface: SurfaceSlot) -> ImageTexture:
	var w := int(surface.grid_w() * TILE_PIXELS)
	var h := int(surface.grid_h() * TILE_PIXELS)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for gy in range(surface.grid_h()):
		for gx in range(surface.grid_w()):
			var color: Color = surface.grid_colors[gy][gx]
			for py in range(TILE_PIXELS):
				for px in range(TILE_PIXELS):
					img.set_pixel(gx * TILE_PIXELS + px, gy * TILE_PIXELS + py, color)
	
	if developer_mode:
		print("GridPainter: Built texture for surface '", surface.id, "': ", w, "x", h, " pixels (", surface.grid_w(), "x", surface.grid_h(), " grid cells)")
		print("  Face dims: ", surface.face_cell_dims)
		print("  Face offsets: ", surface.face_offsets)
	
	return ImageTexture.create_from_image(img)

func _generate_cube_mesh_with_uvs_for_surface(surface: SurfaceSlot, cube_size: Vector3 = Vector3(1, 1, 1)) -> ArrayMesh:
	if surface.face_cell_dims.size() != 6 or surface.face_offsets.size() != 6:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var atlas_w := float(surface.grid_w())
	var atlas_h := float(surface.grid_h())
	for fi in range(FACE_DEFS.size()):
		var face: Dictionary = FACE_DEFS[fi]
		var n: Vector3 = face["n"]
		var u: Vector3 = face["u"]
		var v: Vector3 = face["v"]
		var dims: Vector2i = surface.face_cell_dims[fi]
		var offset: Vector2i = surface.face_offsets[fi]
		var uv_x0 := float(offset.x) / atlas_w
		var uv_y0 := float(offset.y) / atlas_h
		var uv_x1 := float(offset.x + dims.x) / atlas_w
		var uv_y1 := float(offset.y + dims.y) / atlas_h
		var p00 := ((u * -0.5) + (v * -0.5) + n * 0.5) * cube_size
		var p10 := ((u * 0.5) + (v * -0.5) + n * 0.5) * cube_size
		var p11 := ((u * 0.5) + (v * 0.5) + n * 0.5) * cube_size
		var p01 := ((u * -0.5) + (v * 0.5) + n * 0.5) * cube_size
		var normal := n.normalized()
		st.set_normal(normal)
		st.set_uv(Vector2(uv_x0, uv_y0))
		st.add_vertex(p00)
		st.set_normal(normal)
		st.set_uv(Vector2(uv_x0, uv_y1))
		st.add_vertex(p01)
		st.set_normal(normal)
		st.set_uv(Vector2(uv_x1, uv_y1))
		st.add_vertex(p11)
		st.set_normal(normal)
		st.set_uv(Vector2(uv_x0, uv_y0))
		st.add_vertex(p00)
		st.set_normal(normal)
		st.set_uv(Vector2(uv_x1, uv_y1))
		st.add_vertex(p11)
		st.set_normal(normal)
		st.set_uv(Vector2(uv_x1, uv_y0))
		st.add_vertex(p10)
	return st.commit()

func randomize_grid(surface_id: String = "") -> void:
	var surface := _get_surface_or_fallback(surface_id)
	if not surface:
		return
	_rng.randomize()
	for y in range(surface.grid_h()):
		for x in range(surface.grid_w()):
			surface.grid_colors[y][x] = Color(_rng.randf(), _rng.randf(), _rng.randf(), 1.0)
	surface.texture = _build_texture_from_surface(surface)
	_apply_surface_texture(surface)

func apply_texture(to_target: bool = true, to_linked: bool = true, surface_id: String = "") -> void:
	var surface := _get_surface_or_fallback(surface_id)
	if not surface:
		return
	_apply_surface_texture(surface, to_target, to_linked)

func get_cell_color(x: int, y: int, surface_id: String = "") -> Color:
	var surface := _get_surface_or_fallback(surface_id)
	if not surface or x < 0 or y < 0 or x >= surface.grid_w() or y >= surface.grid_h():
		return Color(0, 0, 0, 0)
	return surface.grid_colors[y][x]


func set_cell_color(x: int, y: int, color: Color, origin: NodePath = NodePath(""), surface_id: String = "") -> void:
	var surface := _get_surface(surface_id) if surface_id != "" else null
	if not surface and origin != NodePath(""):
		surface = _surface_for_origin(origin)
	if not surface:
		surface = _fallback_surface()
	if not surface or x < 0 or y < 0 or x >= surface.grid_w() or y >= surface.grid_h():
		return
	surface.grid_colors[y][x] = color
	surface.texture = _build_texture_from_surface(surface)
	_apply_surface_texture(surface)
	if origin != NodePath(""):
		var origin_node := get_node_or_null(origin)
		if origin_node and origin_node is MeshInstance3D:
			_assign_texture_to_mesh(origin_node, surface.texture, null)
	# Save and notify other grid painters (debounced to avoid excessive saves during continuous painting)
	_schedule_save()
	# Schedule network update (debounced to avoid flooding the network)
	_schedule_network_update()


func fill_color(color: Color, surface_id: String = "") -> void:
	var surface := _get_surface_or_fallback(surface_id)
	if not surface:
		return
	for y in range(surface.grid_h()):
		for x in range(surface.grid_w()):
			surface.grid_colors[y][x] = color
	surface.texture = _build_texture_from_surface(surface)
	_apply_surface_texture(surface)
	save_grid_data(_save_path)

func paint_at_uv(uv: Vector2, color: Color, origin: NodePath = NodePath(""), surface_id: String = "") -> void:
	if uv.x < 0 or uv.x > 1 or uv.y < 0 or uv.y > 1:
		return
	var surface: SurfaceSlot = null
	if surface_id != "":
		surface = _get_surface(surface_id)
	if not surface and origin != NodePath(""):
		surface = _surface_for_origin(origin)
	if not surface:
		surface = _fallback_surface()
	if not surface:
		return
	var gx := int(clamp(floor(uv.x * surface.grid_w()), 0, surface.grid_w() - 1))
	var gy := int(clamp(floor(uv.y * surface.grid_h()), 0, surface.grid_h() - 1))
	set_cell_color(gx, gy, color, origin, surface.id)

func save_grid_data(path: String = _save_path) -> void:
	var payload := {}
	for id in _surfaces.keys():
		var surface := _get_surface(id)
		if surface:
			payload[id] = _serialize_surface(surface)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		var json_str := JSON.stringify({"surfaces": payload})
		file.store_string(json_str)
		file.close()
		print("GridPainter: Saved ", payload.keys().size(), " surfaces to: ", path)
		# Notify other grid painters to refresh (e.g., player's grid painter)
		_notify_other_grid_painters()
	else:
		push_error("GridPainter: Failed to save grid data to: ", path)


func _notify_other_grid_painters() -> void:
	"""Notify other GridPainter instances to refresh their surfaces from saved data"""
	var tree := get_tree()
	if not tree:
		return
	# Find all GridPainter nodes in the scene
	var all_painters: Array[Node] = []
	_find_grid_painters_recursive(tree.root, all_painters)
	for painter in all_painters:
		if painter == self:
			continue
		if painter.has_method("refresh_all_surfaces"):
			painter.call_deferred("refresh_all_surfaces")
			print("GridPainter: Notified ", painter.name, " to refresh")
	
	# Schedule network avatar update if this is the player's grid painter
	# (uses debouncing to avoid flooding the network)
	_schedule_network_update()


func _find_grid_painters_recursive(node: Node, result: Array[Node]) -> void:
	"""Recursively find all GridPainter nodes"""
	if node is GridPainter:
		result.append(node)
	for child in node.get_children():
		_find_grid_painters_recursive(child, result)

func load_grid_data(path: String = _save_path) -> void:
	const DEFAULT_PATH := "res://assets/textures/grid_painter_surfaces.json"
	var load_path := path
	
	# If no saved file exists, try to load from default
	if not FileAccess.file_exists(path):
		print("GridPainter: No save file found at: ", path)
		if FileAccess.file_exists(DEFAULT_PATH):
			print("GridPainter: Loading default surfaces from: ", DEFAULT_PATH)
			load_path = DEFAULT_PATH
		else:
			print("GridPainter: No default file found either, skipping load")
			return
	
	var file := FileAccess.open(load_path, FileAccess.READ)
	if not file:
		print("GridPainter: Failed to open file: ", load_path)
		return
	var json := JSON.new()
	var file_content := file.get_as_text()
	var err := json.parse(file_content)
	file.close()
	if err != OK:
		push_warning("GridPainter: Unable to parse surface file from: ", load_path)
		return
	var data: Variant = json.get_data()
	if not data.has("surfaces"):
		print("GridPainter: File has no 'surfaces' key: ", load_path)
		return
	print("GridPainter: Loading ", data["surfaces"].keys().size(), " surfaces from: ", load_path)
	for id in data["surfaces"].keys():
		var surface := _get_surface(id)
		if surface:
			_deserialize_surface(surface, data["surfaces"][id])
			surface.texture = _build_texture_from_surface(surface)
			print("GridPainter: Loaded surface '", id, "' with grid size ", surface.grid_w(), "x", surface.grid_h())
		else:
			print("GridPainter: Surface '", id, "' not found in registered surfaces")

func reset_grid_data(path: String = _save_path, remove_save_file: bool = true) -> void:
	for surface in _surfaces.values():
		if not (surface is SurfaceSlot):
			continue
		_reset_surface(surface)
		surface.texture = _build_texture_from_surface(surface)
		_apply_surface_texture(surface)
	if remove_save_file:
		if FileAccess.file_exists(path):
			var err := DirAccess.remove_absolute(path)
			if err != OK:
				push_warning("GridPainter: Failed to delete saved grid data at %s (err=%s)" % [path, err])
	else:
		if load_for_player:
			save_grid_data(path)

func _serialize_surface(surface: SurfaceSlot) -> Dictionary:
	var grid_rows := []
	for row in surface.grid_colors:
		var row_data := []
		for c in row:
			row_data.append({"r": c.r, "g": c.g, "b": c.b, "a": c.a})
		grid_rows.append(row_data)
	return {
		"subdivisions": {"x": surface.subdivisions_axis.x, "y": surface.subdivisions_axis.y, "z": surface.subdivisions_axis.z},
		"grid": grid_rows
	}

func _deserialize_surface(surface: SurfaceSlot, payload: Dictionary) -> void:
	# First, apply subdivisions if they changed (this will reset colors)
	if payload.has("subdivisions"):
		var subs: Dictionary = payload.get("subdivisions", {})
		var axis := Vector3i(int(subs.get("x", surface.subdivisions_axis.x)), int(subs.get("y", surface.subdivisions_axis.y)), int(subs.get("z", surface.subdivisions_axis.z)))
		if axis != surface.subdivisions_axis:
			surface.subdivisions_axis = axis
			_apply_subdivisions_to_surface(surface, axis)
	
	# Then load the grid colors (after any reset from subdivisions)
	if payload.has("grid"):
		var rows = payload["grid"]
		var loaded_count := 0
		for y in range(min(rows.size(), surface.grid_h())):
			var row_data = rows[y]
			for x in range(min(row_data.size(), surface.grid_w())):
				var cd = row_data[x]
				surface.grid_colors[y][x] = Color(cd["r"], cd["g"], cd["b"], cd["a"])
				loaded_count += 1
		print("GridPainter: Deserialized ", loaded_count, " color cells for surface")

func _convert_grid_to_face_colors(surface: SurfaceSlot) -> Array:
	var out: Array = []
	if surface.face_cell_dims.size() != 6 or surface.face_offsets.size() != 6:
		return out
	for fi in range(FACE_DEFS.size()):
		var dims: Vector2i = surface.face_cell_dims[fi]
		var offset: Vector2i = surface.face_offsets[fi]
		var face_rows: Array = []
		for y in range(dims.y):
			var row: Array = []
			for x in range(dims.x):
				var gx := offset.x + x
				var gy := offset.y + y
				row.append(surface.grid_colors[gy][gx])
			face_rows.append(row)
		out.append(face_rows)
	return out

func set_subdivisions_from_axis(axis_counts: Vector3i, surface_id: String = "") -> void:
	var surface := _get_surface_or_fallback(surface_id)
	if not surface:
		return
	surface.subdivisions_axis = axis_counts
	_apply_subdivisions_to_surface(surface, axis_counts)
	surface.texture = _build_texture_from_surface(surface)
	_apply_surface_texture(surface)

func _count_for_axis(axis: Vector3, axis_counts: Vector3i) -> int:
	var abs_axis := axis.abs()
	if abs_axis.x > 0.5:
		return axis_counts.x
	if abs_axis.y > 0.5:
		return axis_counts.y
	return axis_counts.z

func _surface_for_origin(origin: NodePath) -> SurfaceSlot:
	if origin == NodePath(""):
		return null
	for surface in _surfaces.values():
		if surface is SurfaceSlot and surface.matches_origin(origin):
			return surface
	return null

func _get_surface_or_fallback(id: String) -> SurfaceSlot:
	if id != "":
		var explicit := _get_surface(id)
		if explicit:
			return explicit
	return _fallback_surface()

func _fallback_surface() -> SurfaceSlot:
	var preferred_ids: Array = [SURFACE_LEFT_HAND, SURFACE_RIGHT_HAND, SURFACE_HEAD, SURFACE_BODY]
	for pid in preferred_ids:
		var surface := _get_surface(pid)
		if surface:
			return surface
	for surface in _surfaces.values():
		if surface:
			return surface
	return null

func _get_surface(id: String) -> SurfaceSlot:
	if id == "":
		return null
	if _surfaces.has(id):
		return _surfaces[id]
	if _surface_aliases.has(id):
		var canonical_id: String = _surface_aliases[id]
		if _surfaces.has(canonical_id):
			return _surfaces[canonical_id]
	return null

func _exit_tree() -> void:
	save_grid_data(_save_path)

func _editor_randomize_grid(surface_id: String = "") -> void:
	randomize_grid(surface_id)

func _editor_apply_texture(surface_id: String = "") -> void:
	apply_texture(true, true, surface_id)

func _editor_reset_grid_data(path: String = _save_path) -> void:
	reset_grid_data(path)

func _editor_save_grid_png(path: String = "res://grid_painter_output.png", surface_id: String = "") -> void:
	var surface := _get_surface_or_fallback(surface_id)
	if not surface:
		return
	if not surface.texture:
		surface.texture = _build_texture_from_surface(surface)
	surface.texture.get_image().save_png(path)

func _editor_apply_subdivisions(surface_id: String = "", axis_counts: Vector3i = Vector3i(4, 4, 1)) -> void:
	set_subdivisions_from_axis(axis_counts, surface_id)
	randomize_grid(surface_id)
	apply_texture(true, true, surface_id)

func debug_print_grid(surface_id: String = "") -> void:
	if not developer_mode:
		return
	var surface := _get_surface_or_fallback(surface_id)
	if not surface:
		return
	for y in range(surface.grid_h()):
		var line := ""
		for x in range(surface.grid_w()):
			line += "%s " % [surface.grid_colors[y][x]]
		print(line)


func refresh_all_surfaces() -> void:
	"""Reload saved data and reapply all surface textures. Call after edits to update player meshes."""
	print("GridPainter: Refreshing all surfaces...")
	if load_for_player:
		load_grid_data(_save_path)
	_resolve_all_surface_nodes()
	_apply_all_surface_textures()
	print("GridPainter: Refresh complete")


func get_surface_texture(surface_id: String) -> ImageTexture:
	"""Get the texture for a specific surface (head, body, left_hand, right_hand)"""
	var surface := _get_surface(surface_id)
	if not surface:
		return null
	if not surface.texture:
		surface.texture = _build_texture_from_surface(surface)
	return surface.texture


func _trigger_network_avatar_update() -> void:
	"""Trigger a network update to send the updated avatar to other players"""
	# Find the PlayerNetworkComponent in the scene
	var network_component: Node = null
	
	# Try to find it as a sibling or in the player hierarchy
	var parent = get_parent()
	if parent:
		for child in parent.get_children():
			if child.get_script() and child.has_method("send_avatar_texture"):
				network_component = child
				break
	
	# Try finding it in the player group
	if not network_component:
		var players = get_tree().get_nodes_in_group("player")
		for player in players:
			for child in player.get_children():
				if child.get_script() and child.has_method("send_avatar_texture"):
					network_component = child
					break
			if network_component:
				break
	
	if network_component:
		# Defer the call to ensure textures are fully updated
		network_component.call_deferred("send_avatar_texture")
		print("GridPainter: Triggered network avatar update")
	else:
		print("GridPainter: Could not find PlayerNetworkComponent to trigger avatar update")


func force_network_avatar_update() -> void:
	"""Immediately send avatar update to network (bypasses debouncing)"""
	if load_for_player:
		_network_update_pending = false
		_trigger_network_avatar_update()
		print("GridPainter: Forced immediate network avatar update")
