extends Area3D
class_name DarkZoneArea

@export_node_path("DirectionalLight3D") var directional_light_path: NodePath
@export_node_path("WorldEnvironment") var world_environment_path: NodePath
@export var dark_light_energy: float = 0.08
@export var dark_ambient_energy: float = 0.03
@export var dark_sky_energy: float = 0.0
@export var dark_fog_light_energy: float = 0.05
@export var transition_duration: float = 0.5

var _directional_light: DirectionalLight3D
var _world_environment: WorldEnvironment
var _original_light_energy: float = 1.0
var _original_ambient_energy: float = 1.0
var _original_sky_energy: float = 1.0
var _original_bg_energy: float = 1.0
var _original_fog_light_energy: float = 0.39
var _player_overlap_count: int = 0
var _tween: Tween
var _visual_mesh: MeshInstance3D


func _ready() -> void:
	monitoring = true
	monitorable = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Hide the visual mesh from outside
	_visual_mesh = get_node_or_null("Visual") as MeshInstance3D
	if _visual_mesh:
		_visual_mesh.visible = false

	# Defer lookup so sibling nodes are guaranteed to be in the tree
	call_deferred("_find_references")


func _find_references() -> void:
	# Try exported paths first
	if not directional_light_path.is_empty():
		_directional_light = get_node_or_null(directional_light_path) as DirectionalLight3D
	if not world_environment_path.is_empty():
		_world_environment = get_node_or_null(world_environment_path) as WorldEnvironment

	# Fallback: search siblings and scene tree if paths didn't resolve
	if not _directional_light:
		var parent := get_parent()
		if parent:
			for child in parent.get_children():
				if child is DirectionalLight3D:
					_directional_light = child
					break
	if not _world_environment:
		var parent := get_parent()
		if parent:
			for child in parent.get_children():
				if child is WorldEnvironment:
					_world_environment = child
					break

	# Store original values
	if _directional_light:
		_original_light_energy = _directional_light.light_energy
		print("DarkZoneArea: Found DirectionalLight3D — energy=", _original_light_energy)
	else:
		push_warning("DarkZoneArea: Could not find any DirectionalLight3D")

	if _world_environment and _world_environment.environment:
		var env := _world_environment.environment
		_original_ambient_energy = env.ambient_light_energy
		_original_bg_energy = env.background_energy_multiplier
		_original_fog_light_energy = env.fog_light_energy if env.fog_enabled else 0.0
		print("DarkZoneArea: Found WorldEnvironment — ambient=", _original_ambient_energy,
			  " bg_energy=", _original_bg_energy, " fog_light=", _original_fog_light_energy)
	else:
		push_warning("DarkZoneArea: Could not find any WorldEnvironment")


func _on_body_entered(body: Node) -> void:
	if not _is_player(body):
		return

	_player_overlap_count += 1
	if _player_overlap_count == 1:
		print("DarkZoneArea: Player entered — transitioning to dark")
		if _visual_mesh:
			_visual_mesh.visible = true
		_transition_to_dark()


func _on_body_exited(body: Node) -> void:
	if not _is_player(body):
		return

	_player_overlap_count = maxi(_player_overlap_count - 1, 0)
	if _player_overlap_count == 0:
		print("DarkZoneArea: Player exited — restoring light")
		if _visual_mesh:
			_visual_mesh.visible = false
		_transition_to_light()


func _transition_to_dark() -> void:
	if not _directional_light and not (_world_environment and _world_environment.environment):
		push_warning("DarkZoneArea: No light references found, cannot transition")
		return
	_kill_tween()
	_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

	if _directional_light:
		_tween.tween_property(_directional_light, "light_energy", dark_light_energy, transition_duration)

	if _world_environment and _world_environment.environment:
		var env := _world_environment.environment
		_tween.tween_property(env, "ambient_light_energy", dark_ambient_energy, transition_duration)
		_tween.tween_property(env, "background_energy_multiplier", 0.0, transition_duration)
		if env.fog_enabled:
			_tween.tween_property(env, "fog_light_energy", dark_fog_light_energy, transition_duration)


func _transition_to_light() -> void:
	if not _directional_light and not (_world_environment and _world_environment.environment):
		return
	_kill_tween()
	_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

	if _directional_light:
		_tween.tween_property(_directional_light, "light_energy", _original_light_energy, transition_duration)

	if _world_environment and _world_environment.environment:
		var env := _world_environment.environment
		_tween.tween_property(env, "ambient_light_energy", _original_ambient_energy, transition_duration)
		_tween.tween_property(env, "background_energy_multiplier", _original_bg_energy, transition_duration)
		if env.fog_enabled:
			_tween.tween_property(env, "fog_light_energy", _original_fog_light_energy, transition_duration)


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null


func _is_player(node: Node) -> bool:
	if node == null:
		return false
	# Use group membership — PlayerBody is in the "player" group in both VR and desktop modes
	return node.is_in_group("player") or node.is_in_group("player_body")
