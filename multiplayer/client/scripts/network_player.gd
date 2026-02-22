extends Node3D
## NetworkPlayer - Represents a remote player in the network
## Handles interpolation and visualization of networked player transforms

@export var peer_id: Variant = -1
@export var interpolation_speed: float = 15.0
@export var use_interpolation_buffer: bool = true
@export var buffer_size: int = 3

# Visual representations
@onready var head_visual: MeshInstance3D = $Head
@onready var left_hand_visual: MeshInstance3D = $LeftHand
@onready var right_hand_visual: MeshInstance3D = $RightHand
@onready var body_visual: MeshInstance3D = $Body

# Target transforms for interpolation
var target_head_position: Vector3 = Vector3.ZERO
var target_head_rotation: Vector3 = Vector3.ZERO
var target_left_hand_position: Vector3 = Vector3.ZERO
var target_left_hand_rotation: Vector3 = Vector3.ZERO
var target_right_hand_position: Vector3 = Vector3.ZERO
var target_right_hand_rotation: Vector3 = Vector3.ZERO
var target_scale: Vector3 = Vector3.ONE

# Interpolation buffer for smoother movement
var position_buffer: Array = []
var rotation_buffer: Array = []
var buffer_index: int = 0

# Label to show player name/ID
var label_3d: Label3D = null

# Voice chat - Now handled by PlayerVoiceComponent with LiveKit
# AudioStreamPlayer3D nodes are created and managed by PlayerVoiceComponent

# Avatar texture
var has_custom_avatar: bool = false


func _ready() -> void:
	_create_visuals()
	_create_name_label()
	# Voice player creation removed - now handled by PlayerVoiceComponent

func get_peer_id() -> String:
	return str(peer_id)


func _process(delta: float) -> void:
	_interpolate_transforms(delta)
	_update_label_position()
	# Voice playback removed - now handled by PlayerVoiceComponent


## Update target transforms from network data
func update_from_network_data(player_data: Dictionary) -> void:
	var new_head_pos = player_data.get("head_position", Vector3.ZERO)
	var new_head_rot = player_data.get("head_rotation", Vector3.ZERO)
	
	# Use interpolation buffer for smoother movement
	if use_interpolation_buffer:
		# Add to buffer
		position_buffer.append(new_head_pos)
		rotation_buffer.append(new_head_rot)
		
		# Keep buffer size limited
		if position_buffer.size() > buffer_size:
			position_buffer.pop_front()
			rotation_buffer.pop_front()
		
		# Average the buffer for smoother result
		var avg_pos = Vector3.ZERO
		var avg_rot = Vector3.ZERO
		for pos in position_buffer:
			avg_pos += pos
		for rot in rotation_buffer:
			avg_rot += rot
		target_head_position = avg_pos / position_buffer.size()
		target_head_rotation = avg_rot / rotation_buffer.size()
	else:
		target_head_position = new_head_pos
		target_head_rotation = new_head_rot
	
	target_left_hand_position = player_data.get("left_hand_position", Vector3.ZERO)
	target_left_hand_rotation = player_data.get("left_hand_rotation", Vector3.ZERO)
	target_right_hand_position = player_data.get("right_hand_position", Vector3.ZERO)
	target_right_hand_rotation = player_data.get("right_hand_rotation", Vector3.ZERO)
	target_scale = player_data.get("player_scale", Vector3.ONE)
	
	# Voice samples removed - now handled by PlayerVoiceComponent via LiveKit
	# Old Nakama voice_samples field is no longer used


## Smoothly interpolate to target transforms
func _interpolate_transforms(delta: float) -> void:
	var lerp_factor = interpolation_speed * delta
	
	# Interpolate head
	head_visual.global_position = head_visual.global_position.lerp(target_head_position, lerp_factor)
	head_visual.rotation_degrees = head_visual.rotation_degrees.lerp(target_head_rotation, lerp_factor)
	
	# Interpolate left hand
	left_hand_visual.global_position = left_hand_visual.global_position.lerp(target_left_hand_position, lerp_factor)
	left_hand_visual.rotation_degrees = left_hand_visual.rotation_degrees.lerp(target_left_hand_rotation, lerp_factor)
	
	# Interpolate right hand
	right_hand_visual.global_position = right_hand_visual.global_position.lerp(target_right_hand_position, lerp_factor)
	right_hand_visual.rotation_degrees = right_hand_visual.rotation_degrees.lerp(target_right_hand_rotation, lerp_factor)
	
	# Interpolate scale
	scale = scale.lerp(target_scale, lerp_factor)
	
	# Update body position (directly below head at chest height)
	var body_pos = target_head_position
	body_pos.y = target_head_position.y - 0.3 # Chest height (slightly below head)
	body_visual.global_position = body_visual.global_position.lerp(body_pos, lerp_factor)
	
	# Rotate body to match head's Y rotation only (yaw) to keep it upright
	var target_body_rotation = Vector3(0, target_head_rotation.y, 0)
	body_visual.rotation_degrees = body_visual.rotation_degrees.lerp(target_body_rotation, lerp_factor)


## Create simple visual meshes for the player (rectangles like XRPlayer)
func _create_visuals() -> void:
	# Head - box/rectangle
	if not head_visual:
		head_visual = MeshInstance3D.new()
		head_visual.name = "Head"
		add_child(head_visual)
	
	var head_mesh = BoxMesh.new()
	head_mesh.size = Vector3(0.22, 0.22, 0.22)
	head_visual.mesh = head_mesh
	
	var head_material = StandardMaterial3D.new()
	head_material.albedo_color = Color(0.8, 0.6, 0.4) # Skin tone
	head_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	head_visual.material_override = head_material
	
	# Left hand - box/rectangle
	if not left_hand_visual:
		left_hand_visual = MeshInstance3D.new()
		left_hand_visual.name = "LeftHand"
		add_child(left_hand_visual)
	
	var left_hand_mesh = BoxMesh.new()
	left_hand_mesh.size = Vector3(0.1, 0.1, 0.15)
	left_hand_visual.mesh = left_hand_mesh
	
	var left_material = StandardMaterial3D.new()
	left_material.albedo_color = Color(0.3, 0.6, 1.0) # Blue for left
	left_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	left_hand_visual.material_override = left_material
	
	# Right hand - box/rectangle
	if not right_hand_visual:
		right_hand_visual = MeshInstance3D.new()
		right_hand_visual.name = "RightHand"
		add_child(right_hand_visual)
	
	var right_hand_mesh = BoxMesh.new()
	right_hand_mesh.size = Vector3(0.1, 0.1, 0.15)
	right_hand_visual.mesh = right_hand_mesh
	
	var right_material = StandardMaterial3D.new()
	right_material.albedo_color = Color(1.0, 0.3, 0.3) # Red for right
	right_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	right_hand_visual.material_override = right_material
	
	# Body - box/rectangle
	if not body_visual:
		body_visual = MeshInstance3D.new()
		body_visual.name = "Body"
		add_child(body_visual)
	
	var body_mesh = BoxMesh.new()
	body_mesh.size = Vector3(0.3, 0.4, 0.2) # Match local player body size
	body_visual.mesh = body_mesh
	
	var body_material = StandardMaterial3D.new()
	body_material.albedo_color = Color(0.4, 0.4, 0.4) # Gray
	body_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_material.albedo_color.a = 0.5
	body_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	body_visual.material_override = body_material


## Create floating name label above head
func _create_name_label() -> void:
	label_3d = Label3D.new()
	label_3d.name = "NameLabel"
	label_3d.text = "Player " + str(peer_id)
	label_3d.pixel_size = 0.002
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.no_depth_test = true
	label_3d.modulate = Color(1, 1, 1, 0.8)
	label_3d.outline_size = 8
	label_3d.outline_modulate = Color(0, 0, 0, 0.5)
	add_child(label_3d)


## Update the name label position above head
func _update_label_position() -> void:
	if label_3d and head_visual:
		label_3d.global_position = head_visual.global_position + Vector3(0, 0.3, 0)


## Set the display name directly on the 3D label
func set_player_name(new_name: String) -> void:
	if label_3d:
		label_3d.text = new_name
		print("NetworkPlayer: Set name to ", new_name)



## Apply avatar textures to player meshes
func apply_avatar_textures(textures_data: Dictionary) -> void:
	"""Apply avatar textures to head, body, and hands meshes"""
	if textures_data.is_empty():
		return
	
	print("NetworkPlayer ", peer_id, ": Applying avatar textures...")
	
	# Find GridPainter to use its mesh generation
	var grid_painter = _find_grid_painter()
	if not grid_painter:
		push_error("NetworkPlayer: Cannot find GridPainter to generate meshes")
		return
	
	# Apply head texture with proper cube mesh from GridPainter
	if textures_data.has("head"):
		var texture = _create_texture_from_data(textures_data["head"])
		if texture and head_visual:
			var img = texture.get_image()
			print("  Head texture: ", img.get_width(), "x", img.get_height(), " pixels")
			
			# Use GridPainter's mesh generation to ensure exact match
			var head_surface = grid_painter._get_surface("head")
			if head_surface:
				var cube_mesh = grid_painter._generate_cube_mesh_with_uvs_for_surface(head_surface, Vector3(0.22, 0.22, 0.22))
				if cube_mesh:
					head_visual.mesh = cube_mesh
			
			var mat = StandardMaterial3D.new()
			mat.albedo_texture = texture
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode = BaseMaterial3D.CULL_BACK
			head_visual.material_override = mat
			has_custom_avatar = true
	
	# Apply body texture with proper cube mesh from GridPainter
	if textures_data.has("body"):
		var texture = _create_texture_from_data(textures_data["body"])
		if texture and body_visual:
			var img = texture.get_image()
			print("  Body texture: ", img.get_width(), "x", img.get_height(), " pixels")
			
			# Use GridPainter's mesh generation to ensure exact match
			var body_surface = grid_painter._get_surface("body")
			if body_surface:
				var cube_mesh = grid_painter._generate_cube_mesh_with_uvs_for_surface(body_surface, Vector3(0.3, 0.4, 0.2))
				if cube_mesh:
					body_visual.mesh = cube_mesh
			
			var mat = StandardMaterial3D.new()
			mat.albedo_texture = texture
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode = BaseMaterial3D.CULL_BACK
			body_visual.material_override = mat
	
	# Apply hands texture (same for both hands) with proper cube mesh from GridPainter
	if textures_data.has("hands"):
		var texture = _create_texture_from_data(textures_data["hands"])
		if texture:
			var img = texture.get_image()
			print("  Hands texture: ", img.get_width(), "x", img.get_height(), " pixels")
			
			# Use GridPainter's mesh generation to ensure exact match
			var hand_surface = grid_painter._get_surface("left_hand")
			if hand_surface:
				var hand_cube_mesh = grid_painter._generate_cube_mesh_with_uvs_for_surface(hand_surface, Vector3(0.1, 0.1, 0.1))
				
				var mat = StandardMaterial3D.new()
				mat.albedo_texture = texture
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.cull_mode = BaseMaterial3D.CULL_BACK
				
				if left_hand_visual and hand_cube_mesh:
					left_hand_visual.mesh = hand_cube_mesh.duplicate()
					left_hand_visual.material_override = mat.duplicate()
				if right_hand_visual and hand_cube_mesh:
					right_hand_visual.mesh = hand_cube_mesh.duplicate()
					right_hand_visual.material_override = mat.duplicate()
	
	print("NetworkPlayer: Applied ", textures_data.size(), " avatar textures to player ", peer_id)


func _create_texture_from_data(texture_data: PackedByteArray) -> ImageTexture:
	"""Create an ImageTexture from PNG byte data"""
	var image = Image.new()
	var error = image.load_png_from_buffer(texture_data)
	if error != OK:
		push_error("NetworkPlayer: Failed to load texture from data")
		return null
	return ImageTexture.create_from_image(image)


## Apply avatar texture to head mesh (legacy function for compatibility)
func apply_avatar_texture(texture: ImageTexture) -> void:
	if not head_visual or not texture:
		return
	
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	head_visual.material_override = mat
	has_custom_avatar = true
	print("NetworkPlayer: Applied avatar texture to player ", peer_id)


# Old voice chat implementation removed
# Voice is now handled by PlayerVoiceComponent with LiveKit spatial audio
# AudioStreamPlayer3D nodes are created and managed by PlayerVoiceComponent based on LiveKit participant data


func _find_grid_painter() -> Node:
	"""Find the GridPainter instance in the scene"""
	# Try to find it in the player group
	var players = get_tree().get_nodes_in_group("player")
	for player in players:
		for child in player.get_children():
			if child.get_script() and child.has_method("_generate_cube_mesh_with_uvs_for_surface"):
				return child
	
	# Try to find any GridPainter in the scene
	var all_nodes = get_tree().root.get_children()
	for node in all_nodes:
		var found = _find_grid_painter_recursive(node)
		if found:
			return found
	
	return null


func _find_grid_painter_recursive(node: Node) -> Node:
	"""Recursively search for GridPainter"""
	if node.get_script() and node.has_method("_generate_cube_mesh_with_uvs_for_surface"):
		return node
	
	for child in node.get_children():
		var found = _find_grid_painter_recursive(child)
		if found:
			return found
	
	return null
