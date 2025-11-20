extends Node3D
## NetworkPlayer - Represents a remote player in the network
## Handles interpolation and visualization of networked player transforms

@export var peer_id: int = -1
@export var interpolation_speed: float = 15.0

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

# Label to show player name/ID
var label_3d: Label3D = null


func _ready() -> void:
	_create_visuals()
	_create_name_label()


func _process(delta: float) -> void:
	_interpolate_transforms(delta)


## Update target transforms from network data
func update_from_network_data(player_data: Dictionary) -> void:
	target_head_position = player_data.get("head_position", Vector3.ZERO)
	target_head_rotation = player_data.get("head_rotation", Vector3.ZERO)
	target_left_hand_position = player_data.get("left_hand_position", Vector3.ZERO)
	target_left_hand_rotation = player_data.get("left_hand_rotation", Vector3.ZERO)
	target_right_hand_position = player_data.get("right_hand_position", Vector3.ZERO)
	target_right_hand_rotation = player_data.get("right_hand_rotation", Vector3.ZERO)
	target_scale = player_data.get("player_scale", Vector3.ONE)


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
	
	# Update body position (midpoint between hands at chest height)
	var body_pos = (target_left_hand_position + target_right_hand_position) / 2.0
	body_pos.y = target_head_position.y - 0.3 # Slightly below head
	body_visual.global_position = body_visual.global_position.lerp(body_pos, lerp_factor)


## Create simple visual meshes for the player
func _create_visuals() -> void:
	# Head - sphere
	if not head_visual:
		head_visual = MeshInstance3D.new()
		head_visual.name = "Head"
		add_child(head_visual)
	
	var head_mesh = SphereMesh.new()
	head_mesh.radius = 0.12
	head_mesh.height = 0.24
	head_visual.mesh = head_mesh
	
	var head_material = StandardMaterial3D.new()
	head_material.albedo_color = Color(0.8, 0.6, 0.4) # Skin tone
	head_visual.material_override = head_material
	
	# Left hand - smaller sphere
	if not left_hand_visual:
		left_hand_visual = MeshInstance3D.new()
		left_hand_visual.name = "LeftHand"
		add_child(left_hand_visual)
	
	var left_hand_mesh = SphereMesh.new()
	left_hand_mesh.radius = 0.06
	left_hand_visual.mesh = left_hand_mesh
	
	var left_material = StandardMaterial3D.new()
	left_material.albedo_color = Color(0.3, 0.6, 1.0) # Blue for left
	left_hand_visual.material_override = left_material
	
	# Right hand - smaller sphere
	if not right_hand_visual:
		right_hand_visual = MeshInstance3D.new()
		right_hand_visual.name = "RightHand"
		add_child(right_hand_visual)
	
	var right_hand_mesh = SphereMesh.new()
	right_hand_mesh.radius = 0.06
	right_hand_visual.mesh = right_hand_mesh
	
	var right_material = StandardMaterial3D.new()
	right_material.albedo_color = Color(1.0, 0.3, 0.3) # Red for right
	right_hand_visual.material_override = right_material
	
	# Body - capsule
	if not body_visual:
		body_visual = MeshInstance3D.new()
		body_visual.name = "Body"
		add_child(body_visual)
	
	var body_mesh = CapsuleMesh.new()
	body_mesh.radius = 0.15
	body_mesh.height = 0.6
	body_visual.mesh = body_mesh
	
	var body_material = StandardMaterial3D.new()
	body_material.albedo_color = Color(0.4, 0.4, 0.4) # Gray
	body_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_material.albedo_color.a = 0.5
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


func _physics_process(_delta: float) -> void:
	_update_label_position()
