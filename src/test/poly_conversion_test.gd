extends Node3D

const POLY_TOOL_SCENE = preload("res://src/objects/grabbables/PolyTool.tscn")
const TEST_MODEL_URL = "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/Duck/glTF-Binary/Duck.glb"
const TEST_MODEL_PATH = "user://test_duck_conversion.glb"

var poly_tool: PolyTool
var http_request: HTTPRequest
var duck_node: Node3D
var _is_editable: bool = false

var uv_container: Control
var uv_background: TextureRect
var uv_wireframe: Control

var _orig_uvs: PackedVector2Array = []
var _orig_tris: Array[Array] = []

func _ready():
	print("--- PolyTool Conversion Test Start ---")
	print("--- PRESS SPACE TO TOGGLE CONVERSION ---")
	
	# 1. Setup PolyTool
	poly_tool = POLY_TOOL_SCENE.instantiate()
	add_child(poly_tool)
	poly_tool.global_position = Vector3(0, 1, -1)
	
	_setup_uv_ui()
	
	# 2. Download Model if missing
	if not FileAccess.file_exists(TEST_MODEL_PATH):
		print("Downloading test model...")
		http_request = HTTPRequest.new()
		add_child(http_request)
		http_request.request_completed.connect(_on_download_completed)
		var err = http_request.request(TEST_MODEL_URL)
		if err != OK:
			print("Request start error: ", err)
	else:
		print("Test model already exists, spawning...")
		_spawn_initial()

func _setup_uv_ui():
	var cl = CanvasLayer.new()
	add_child(cl)
	
	uv_container = Control.new()
	uv_container.custom_minimum_size = Vector2(300, 300)
	uv_container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	uv_container.position -= Vector2(320, 320)
	cl.add_child(uv_container)
	
	var panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	uv_container.add_child(panel)
	
	uv_background = TextureRect.new()
	uv_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	uv_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	uv_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	uv_background.modulate.a = 0.5
	uv_container.add_child(uv_background)
	
	uv_wireframe = Control.new()
	uv_wireframe.set_anchors_preset(Control.PRESET_FULL_RECT)
	uv_wireframe.draw.connect(_on_uv_wireframe_draw)
	uv_container.add_child(uv_wireframe)
	
	var label = Label.new()
	label.text = "UV Map Visualization"
	label.position = Vector2(0, -25)
	uv_container.add_child(label)
	
	uv_container.visible = false

func _on_uv_wireframe_draw():
	var uvs: PackedVector2Array = []
	var tris: Array[Array] = []
	
	if _is_editable:
		var layers = poly_tool.get_layers()
		if layers.is_empty(): return
		var layer = layers[poly_tool.active_layer_idx]
		uvs = layer.point_uvs
		tris = layer.triangles
	else:
		uvs = _orig_uvs
		tris = _orig_tris
		
	if uvs.is_empty() or tris.is_empty(): return
	
	var size = uv_wireframe.size
	for tri in tris:
		if tri.size() < 3: continue
		var uv1 = uvs[tri[0]] * size
		var uv2 = uvs[tri[1]] * size
		var uv3 = uvs[tri[2]] * size
		
		# Invert Y for drawing (0 at top)
		uv1.y = size.y - uv1.y
		uv2.y = size.y - uv2.y
		uv3.y = size.y - uv3.y
		
		uv_wireframe.draw_line(uv1, uv2, Color.YELLOW, 1.0)
		uv_wireframe.draw_line(uv2, uv3, Color.YELLOW, 1.0)
		uv_wireframe.draw_line(uv3, uv1, Color.YELLOW, 1.0)

func _on_download_completed(result, response_code, headers, body):
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("Download failed! Result: %d, Code: %d" % [result, response_code])
		return
		
	var file = FileAccess.open(TEST_MODEL_PATH, FileAccess.WRITE)
	file.store_buffer(body)
	file.close()
	
	print("Download complete, spawning...")
	_spawn_initial()

func _spawn_initial():
	# 3. Spawn the model
	var doc = GLTFDocument.new()
	var state = GLTFState.new()
	var err = doc.append_from_file(TEST_MODEL_PATH, state)
	if err != OK:
		print("Failed to append GLB: ", err)
		return
		
	duck_node = doc.generate_scene(state)
	add_child(duck_node)
	_force_unshaded_recursive(duck_node)
	duck_node.global_position = Vector3(1, 1, -1)
	
	# Extract original UVs for comparison
	_extract_orig_uv_data_recursive(duck_node)
	uv_container.visible = true
	_update_uv_background()
	uv_wireframe.queue_redraw()
	
	print("Initial model spawned. Press SPACE to convert.")

func _extract_orig_uv_data_recursive(node: Node):
	if node is MeshInstance3D and node.mesh:
		for s in node.mesh.get_surface_count():
			var arrays = node.mesh.surface_get_arrays(s)
			var surface_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var surface_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			
			if surface_uvs.is_empty(): continue
			
			var offset = _orig_uvs.size()
			_orig_uvs.append_array(surface_uvs)
			
			if surface_indices.is_empty():
				for i in range(0, surface_uvs.size(), 3):
					_orig_tris.append([offset + i, offset + i + 1, offset + i + 2])
			else:
				for i in range(0, surface_indices.size(), 3):
					_orig_tris.append([
						offset + surface_indices[i], 
						offset + surface_indices[i+1], 
						offset + surface_indices[i+2]
					])
					
	for child in node.get_children():
		_extract_orig_uv_data_recursive(child)

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		if _is_editable:
			_revert_to_original()
		else:
			_convert_to_editable()

func _convert_to_editable():
	if not duck_node: return
	
	print("Converting model into PolyTool...")
	var conv_err = poly_tool.import_from_node(duck_node)
	
	if conv_err == OK:
		print("CONVERSION SUCCESS!")
		duck_node.visible = false
		_is_editable = true
		uv_container.visible = true
		_update_uv_background()
		uv_wireframe.queue_redraw()
	else:
		print("CONVERSION FAILED: ", conv_err)

func _update_uv_background():
	# Try to find a texture from the duck's material
	var mesh_inst = _find_first_mesh_instance(duck_node)
	if mesh_inst and mesh_inst.mesh:
		var mat = mesh_inst.get_surface_override_material(0)
		if not mat:
			mat = mesh_inst.mesh.surface_get_material(0)
		
		if mat is StandardMaterial3D and mat.albedo_texture:
			uv_background.texture = mat.albedo_texture

func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var res = _find_first_mesh_instance(child)
		if res: return res
	return null

func _revert_to_original():
	print("Reverting to original model...")
	var layers = poly_tool.get_layers()
	for layer in layers:
		if layer.mesh_instance:
			layer.mesh_instance.visible = false
		if layer.point_multimesh:
			layer.point_multimesh.visible = false
	
	if duck_node:
		duck_node.visible = true
	_is_editable = false
	uv_container.visible = false
	print("Original model restored.")

func _force_unshaded_recursive(node: Node):
	if node is MeshInstance3D:
		var meshes = [node]
		for m in meshes:
			if m.material_override:
				_force_mat_unshaded(m.material_override)
			if m.mesh:
				for s in m.mesh.get_surface_count():
					var mat = m.mesh.surface_get_material(s)
					if mat:
						# Since surface materials might be shared, we duplicate to be safe
						var dup = mat.duplicate()
						_force_mat_unshaded(dup)
						m.set_surface_override_material(s, dup)
						
	for child in node.get_children():
		_force_unshaded_recursive(child)

func _force_mat_unshaded(mat: Material):
	if mat is StandardMaterial3D:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
