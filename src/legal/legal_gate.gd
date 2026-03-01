extends Node3D

## Entry point that gates the main experience behind a TOS/Privacy acceptance screen.
## Uses SaveManager to persist the accepted version and routes to either the legal
## intro scene or the main scene accordingly.

const CURRENT_TOS_VERSION := "2025-12-07"
const LEGAL_INTRO_SCENE := preload("res://src/levels/LegalIntro.tscn")
const MAIN_SCENE := preload("res://src/levels/MainScene.tscn")
const LOADING_SCENE := preload("res://src/levels/loading.tscn")

var _active_instance: Node = null


func _ready() -> void:
	_evaluate_legal_gate()


func _evaluate_legal_gate() -> void:
	var accepted: Dictionary = SaveManager.get_legal_acceptance()
	var accepted_version: String = accepted.get("tos_version", "")
	if accepted_version == CURRENT_TOS_VERSION:
		_start_loading_sequence()
	else:
		_switch_to_scene(LEGAL_INTRO_SCENE, true)


func _switch_to_scene(scene: PackedScene, connect_intro: bool = false) -> void:
	if _active_instance and is_instance_valid(_active_instance):
		_active_instance.queue_free()
	_active_instance = scene.instantiate()
	add_child(_active_instance)
	if connect_intro and _active_instance.has_signal("legal_accepted"):
		_active_instance.connect("legal_accepted", Callable(self, "_on_legal_accepted"))


func _on_legal_accepted() -> void:
	SaveManager.set_legal_acceptance(CURRENT_TOS_VERSION)
	_start_loading_sequence()


func _start_loading_sequence() -> void:
	_switch_to_scene(LOADING_SCENE)
	
	# Start preloading the main scene in the background
	var main_scene_path = "res://src/levels/MainScene.tscn"
	ResourceLoader.load_threaded_request(main_scene_path)
	
	# Minimum wait for 10 seconds as requested
	var timer = get_tree().create_timer(10.0)
	await timer.timeout
	
	# Ensure the scene is fully loaded before switching
	var status = ResourceLoader.load_threaded_get_status(main_scene_path)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(main_scene_path)
	
	var loaded_scene = ResourceLoader.load_threaded_get(main_scene_path) as PackedScene
	if loaded_scene:
		_switch_to_scene(loaded_scene)
	else:
		# Fallback to normal preload if threaded load failed
		_switch_to_scene(MAIN_SCENE)
