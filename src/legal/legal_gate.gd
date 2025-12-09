extends Node3D

## Entry point that gates the main experience behind a TOS/Privacy acceptance screen.
## Uses SaveManager to persist the accepted version and routes to either the legal
## intro scene or the main scene accordingly.

const CURRENT_TOS_VERSION := "2025-12-07"
const LEGAL_INTRO_SCENE := preload("res://src/levels/LegalIntro.tscn")
const MAIN_SCENE := preload("res://src/levels/MainScene.tscn")

var _active_instance: Node = null


func _ready() -> void:
	_evaluate_legal_gate()


func _evaluate_legal_gate() -> void:
	var accepted: Dictionary = SaveManager.get_legal_acceptance()
	var accepted_version: String = accepted.get("tos_version", "")
	if accepted_version == CURRENT_TOS_VERSION:
		_switch_to_scene(MAIN_SCENE)
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
	_switch_to_scene(MAIN_SCENE)

