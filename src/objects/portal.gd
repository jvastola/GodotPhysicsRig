# Portal Script
# Handles scene transitions when player enters
extends Area3D

@export_file("*.tscn") var target_scene: String = ""
@export var spawn_point_name: String = "SpawnPoint"
@export var portal_color: Color = Color(0.3, 0.6, 1.0, 0.5)
@export var use_spawn_point: bool = false

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
var _triggered: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	
	# Set portal visual appearance
	if mesh_instance and mesh_instance.get_surface_override_material_count() > 0:
		var mat = mesh_instance.get_surface_override_material(0)
		if mat is StandardMaterial3D:
			mat.albedo_color = portal_color
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _on_body_entered(body: Node3D) -> void:
	print("Portal: Body entered - ", body.name, " | In player group: ", body.is_in_group("player"))
	
	# Check if it's the player
	if _triggered:
		print("Portal: already triggered, ignoring")
		return

	if body.is_in_group("player") or body.name == "XRPlayer":
		if target_scene.is_empty():
			push_warning("Portal has no target scene set!")
			return
		
		print("Portal: Player detected, transitioning to ", target_scene)
		print("Portal: Spawn point name: ", spawn_point_name)
		
		# Store player position for the target scene
		var player_state = {
			"spawn_point": spawn_point_name,
			"use_spawn_point": use_spawn_point,
			"velocity": body.linear_velocity if body is RigidBody3D else Vector3.ZERO
		}
		
		print("Portal: Player state - ", player_state)
		
		# Use call_deferred to avoid physics callback issues
		# Use GameManager if available, otherwise direct scene change
		if has_node("/root/GameManager"):
			var gm = get_node("/root/GameManager")
			# If GameManager is already processing a scene change, ignore this trigger
			if gm and gm.has_method("get") and gm.get("_is_changing_scene"):
				print("Portal: GameManager busy changing scene - ignoring portal trigger")
				return
			_triggered = true
			# Optionally disable monitoring immediately to avoid further signals
			# Use deferred set so we don't change physics state mid-callback
			call_deferred("set", "monitoring", false)
			print("Portal: Calling GameManager.change_scene_with_player")
			gm.call_deferred("change_scene_with_player", target_scene, player_state)
		else:
			print("Portal: GameManager not found, using fallback")
			# Fallback: direct scene change (also deferred)
			call_deferred("_change_scene_fallback", target_scene)


func _change_scene_fallback(scene_path: String) -> void:
	"""Fallback scene change when GameManager not available"""
	get_tree().change_scene_to_file(scene_path)


func set_target(scene_path: String, spawn_name: String = "SpawnPoint") -> void:
	"""Programmatically set the portal destination"""
	target_scene = scene_path
	spawn_point_name = spawn_name
