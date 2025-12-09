extends Node
## Runtime input binding helper that supports multi-press combos and sequences.

const MODE_ANY := "any"
const MODE_CHORD := "chord"
const MODE_SEQUENCE := "sequence"

const CHORD_WINDOW_MS := 350
const SEQUENCE_WINDOW_MS := 900

static var _instance: Node

static func get_singleton() -> Node:
	if _instance:
		return _instance
	var root: Node = Engine.get_main_loop().root
	_instance = (load("res://src/systems/input_binding_manager.gd") as Script).new()
	if root:
		# Defer to avoid "parent busy setting up children" during scene _ready calls
		root.call_deferred("add_child", _instance)
	return _instance


var bindings := {} # action -> {events: Array[InputEvent], mode: String}
var _sequence_state := {} # action -> {index:int, start:int}
var _chord_state := {} # action -> {pressed: Dictionary<int, int>}
var _just_triggered := {} # action -> bool


func set_binding(action: String, events: Array, mode: String = MODE_ANY) -> void:
	if action == "":
		return
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var clean_events: Array[InputEvent] = []
	for ev in events:
		if ev is InputEvent:
			clean_events.append(ev.duplicate())
	bindings[action] = {
		"events": clean_events,
		"mode": mode
	}
	# Keep InputMap in sync for standard action checks
	InputMap.action_erase_events(action)
	if mode == MODE_ANY:
		for ev in clean_events:
			InputMap.action_add_event(action, ev)
	_sequence_state.erase(action)
	_chord_state.erase(action)


func get_binding(action: String) -> Dictionary:
	return bindings.get(action, {})


func ensure_binding(action: String, default_events: Array, mode: String = MODE_ANY) -> void:
	if bindings.has(action):
		return
	set_binding(action, default_events, mode)


func is_action_just_triggered(action: String) -> bool:
	# Standard InputMap hit is always valid
	if Input.is_action_just_pressed(action):
		return true
	if not bindings.has(action):
		return false
	if _just_triggered.get(action, false):
		_just_triggered[action] = false
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if not _is_pressed_event(event):
		return
	var now_ms := Time.get_ticks_msec()
	for action in bindings.keys():
		var binding: Dictionary = bindings[action]
		var events: Array = binding.get("events", [])
		if events.is_empty():
			continue
		var mode: String = binding.get("mode", MODE_ANY)
		if mode == MODE_ANY:
			continue # InputMap already handles it
		if mode == MODE_CHORD:
			_process_chord(action, events, event, now_ms)
		elif mode == MODE_SEQUENCE:
			_process_sequence(action, events, event, now_ms)


func _process_chord(action: String, expected: Array, event: InputEvent, now_ms: int) -> void:
	var state: Dictionary = _chord_state.get(action, {"pressed": {}})
	for i in expected.size():
		var target: InputEvent = expected[i]
		if target.is_match(event):
			state["pressed"][i] = now_ms
	# Drop stale presses
	for key in state["pressed"].keys():
		if now_ms - int(state["pressed"][key]) > CHORD_WINDOW_MS:
			state["pressed"].erase(key)
	if state["pressed"].size() == expected.size():
		_just_triggered[action] = true
		state["pressed"].clear()
	_chord_state[action] = state


func _process_sequence(action: String, expected: Array, event: InputEvent, now_ms: int) -> void:
	var state: Dictionary = _sequence_state.get(action, {"index": 0, "start": 0})
	if state["index"] == 0:
		if expected[0].is_match(event):
			state["start"] = now_ms
			if expected.size() == 1:
				_just_triggered[action] = true
				state["index"] = 0
				state["start"] = 0
			else:
				state["index"] = 1
	else:
		if now_ms - int(state["start"]) > SEQUENCE_WINDOW_MS:
			state["index"] = 0
			state["start"] = 0
		elif expected[state["index"]].is_match(event):
			if state["index"] == expected.size() - 1:
				_just_triggered[action] = true
				state["index"] = 0
				state["start"] = 0
			else:
				state["index"] += 1
	_sequence_state[action] = state


func _is_pressed_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed
	if event is InputEventMouseButton:
		return event.pressed
	if event is InputEventJoypadButton:
		return event.pressed
	if event is InputEventJoypadMotion:
		# Consider motion meaningful when significant
		return abs(event.axis_value) > 0.5
	return false
