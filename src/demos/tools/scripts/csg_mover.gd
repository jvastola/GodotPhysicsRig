@tool
extends Node3D

@export var speed: float = 1.0
@export var amplitude: Vector3 = Vector3(1.0, 0.0, 0.0)
@export var offset: float = 0.0

var _original_position: Vector3

func _ready() -> void:
	_original_position = transform.origin

func _process(_delta: float) -> void:
	var time = Time.get_ticks_msec() / 1000.0
	var phase = sin(time * speed + offset)
	transform.origin = _original_position + amplitude * phase
