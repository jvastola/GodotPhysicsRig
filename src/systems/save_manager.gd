# SaveManager Autoload
# Manages persistent game state across sessions
extends Node

const SAVE_FILE_PATH := "user://save_data.json"

# Cached save data
var _save_data: Dictionary = {}
var _save_dirty := false
var _autosave_timer := 0.0
const AUTOSAVE_INTERVAL := 2.0  # Auto-save every 2 seconds if dirty


func _ready() -> void:
	# Load save data on startup
	load_game_state()
	print("SaveManager: Initialized, save file: ", SAVE_FILE_PATH)


func _process(delta: float) -> void:
	# Auto-save if data has changed
	if _save_dirty:
		_autosave_timer += delta
		if _autosave_timer >= AUTOSAVE_INTERVAL:
			save_game_state()
			_autosave_timer = 0.0


func save_game_state() -> void:
	"""Write current save data to disk"""
	var json_string := JSON.stringify(_save_data, "\t")
	var file := FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	
	if file:
		file.store_string(json_string)
		file.close()
		_save_dirty = false
		print("SaveManager: Game state saved to ", SAVE_FILE_PATH)
	else:
		push_error("SaveManager: Failed to write save file: ", FileAccess.get_open_error())


func load_game_state() -> void:
	"""Load save data from disk"""
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		print("SaveManager: No save file found, starting fresh")
		_save_data = {}
		return
	
	var file := FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if file:
		var json_string := file.get_as_text()
		file.close()
		
		var json := JSON.new()
		var parse_result := json.parse(json_string)
		
		if parse_result == OK:
			_save_data = json.data
			print("SaveManager: Loaded save data: ", _save_data.keys())
		else:
			push_error("SaveManager: Failed to parse save file at line ", json.get_error_line(), ": ", json.get_error_message())
			_save_data = {}
	else:
		push_error("SaveManager: Failed to read save file: ", FileAccess.get_open_error())
		_save_data = {}


# --- GRABBED OBJECTS PERSISTENCE ---

func save_grabbed_object(object_id: String, is_grabbed: bool, hand_name: String = "", position: Vector3 = Vector3.ZERO, rotation: Quaternion = Quaternion.IDENTITY, scene: String = "", relative_position: Array = [], relative_rotation: Array = []) -> void:
	"""Save individual grabbable object state"""
	if not _save_data.has("grabbed_objects"):
		_save_data["grabbed_objects"] = {}
	
	var obj_data := {
		"grabbed": is_grabbed,
		"hand": hand_name,
		"position": [position.x, position.y, position.z],
		"rotation": [rotation.x, rotation.y, rotation.z, rotation.w],
		"scene": scene,
		"relative_position": relative_position,
		"relative_rotation": relative_rotation
	}
	
	_save_data["grabbed_objects"][object_id] = obj_data
	_save_dirty = true
	print("SaveManager: Saved object state - ", object_id, " grabbed=", is_grabbed, " hand=", hand_name, " scene=", scene)


func load_grabbed_object(object_id: String) -> Dictionary:
	"""Load individual grabbable object state. Returns {grabbed: bool, hand: String, position: Vector3, rotation: Quaternion, scene: String}"""
	if not _save_data.has("grabbed_objects"):
		return {}
	
	var objects: Dictionary = _save_data["grabbed_objects"]
	if not objects.has(object_id):
		return {}
	
	var obj_data: Dictionary = objects[object_id]
	
	var pos := Vector3.ZERO
	if obj_data.has("position") and obj_data["position"] is Array and obj_data["position"].size() >= 3:
		var p = obj_data["position"]
		pos = Vector3(p[0], p[1], p[2])
	
	var rot := Quaternion.IDENTITY
	if obj_data.has("rotation") and obj_data["rotation"] is Array and obj_data["rotation"].size() >= 4:
		var r = obj_data["rotation"]
		rot = Quaternion(r[0], r[1], r[2], r[3])
	
	return {
		"grabbed": obj_data.get("grabbed", false),
		"hand": obj_data.get("hand", ""),
		"position": pos,
		"rotation": rot,
		"scene": obj_data.get("scene", "")
	}


func get_all_grabbed_objects() -> Dictionary:
	"""Get all saved grabbed object states"""
	if not _save_data.has("grabbed_objects"):
		return {}
	return _save_data["grabbed_objects"].duplicate()


func clear_save_data() -> void:
	"""Clear all save data (for debugging/reset)"""
	_save_data.clear()
	save_game_state()
	print("SaveManager: All save data cleared")


# --- SCENE TRANSITION HELPERS ---

func get_grabbed_objects_for_scene(scene_path: String) -> Dictionary:
	"""Get all saved grabbed objects that originated from a specific scene.
	Returns {object_id: data_dict} for objects whose 'scene' field matches or is empty."""
	if not _save_data.has("grabbed_objects"):
		return {}
	
	var result: Dictionary = {}
	var objects: Dictionary = _save_data["grabbed_objects"]
	
	for object_id in objects.keys():
		var obj_data: Dictionary = objects[object_id]
		var obj_scene: String = obj_data.get("scene", "")
		# Include objects from this scene or objects without a scene (legacy/global)
		if obj_scene == "" or obj_scene == scene_path or obj_scene.ends_with(scene_path.get_file()):
			result[object_id] = obj_data.duplicate()
	
	return result


func get_currently_grabbed_objects() -> Dictionary:
	"""Get all objects that are marked as currently grabbed.
	Returns {object_id: data_dict} for objects with grabbed=true."""
	if not _save_data.has("grabbed_objects"):
		return {}
	
	var result: Dictionary = {}
	var objects: Dictionary = _save_data["grabbed_objects"]
	
	for object_id in objects.keys():
		var obj_data: Dictionary = objects[object_id]
		if obj_data.get("grabbed", false):
			result[object_id] = obj_data.duplicate()
	
	return result


func load_grabbed_object_full(object_id: String) -> Dictionary:
	"""Load full grabbable object state including relative transforms.
	Returns complete data including relative_position and relative_rotation arrays."""
	if not _save_data.has("grabbed_objects"):
		return {}
	
	var objects: Dictionary = _save_data["grabbed_objects"]
	if not objects.has(object_id):
		return {}
	
	var obj_data: Dictionary = objects[object_id]
	
	var pos := Vector3.ZERO
	if obj_data.has("position") and obj_data["position"] is Array and obj_data["position"].size() >= 3:
		var p = obj_data["position"]
		pos = Vector3(p[0], p[1], p[2])
	
	var rot := Quaternion.IDENTITY
	if obj_data.has("rotation") and obj_data["rotation"] is Array and obj_data["rotation"].size() >= 4:
		var r = obj_data["rotation"]
		rot = Quaternion(r[0], r[1], r[2], r[3])
	
	var rel_pos := Vector3.ZERO
	if obj_data.has("relative_position") and obj_data["relative_position"] is Array and obj_data["relative_position"].size() >= 3:
		var rp = obj_data["relative_position"]
		rel_pos = Vector3(rp[0], rp[1], rp[2])
	
	var rel_rot := Quaternion.IDENTITY
	if obj_data.has("relative_rotation") and obj_data["relative_rotation"] is Array and obj_data["relative_rotation"].size() >= 4:
		var rr = obj_data["relative_rotation"]
		rel_rot = Quaternion(rr[0], rr[1], rr[2], rr[3])
	
	return {
		"grabbed": obj_data.get("grabbed", false),
		"hand": obj_data.get("hand", ""),
		"position": pos,
		"rotation": rot,
		"scene": obj_data.get("scene", ""),
		"relative_position": rel_pos,
		"relative_rotation": rel_rot
	}


func mark_object_released(object_id: String) -> void:
	"""Mark a grabbed object as released without providing full state.
	Useful when an object is auto-released during scene transitions."""
	if not _save_data.has("grabbed_objects"):
		return
	if not _save_data["grabbed_objects"].has(object_id):
		return
	
	_save_data["grabbed_objects"][object_id]["grabbed"] = false
	_save_data["grabbed_objects"][object_id]["hand"] = ""
	_save_dirty = true
	print("SaveManager: Marked object released - ", object_id)


# --- CURRENCY SYSTEM ---

func get_currency(type: String) -> int:
	"""Get amount of specific currency (gold, gems, tokens)"""
	if not _save_data.has("currency"):
		_save_data["currency"] = { "gold": 0, "gems": 0, "tokens": 0 }
	
	return _save_data["currency"].get(type, 0)


func add_currency(type: String, amount: int) -> void:
	"""Add currency amount"""
	if not _save_data.has("currency"):
		_save_data["currency"] = { "gold": 0, "gems": 0, "tokens": 0 }
	
	var current = _save_data["currency"].get(type, 0)
	_save_data["currency"][type] = current + amount
	_save_dirty = true
	print("SaveManager: Added ", amount, " ", type, ". New total: ", _save_data["currency"][type])


func spend_currency(type: String, amount: int) -> bool:
	"""Try to spend currency. Returns true if successful."""
	if not _save_data.has("currency"):
		_save_data["currency"] = { "gold": 0, "gems": 0, "tokens": 0 }
	
	var current = _save_data["currency"].get(type, 0)
	if current >= amount:
		_save_data["currency"][type] = current - amount
		_save_dirty = true
		print("SaveManager: Spent ", amount, " ", type, ". Remaining: ", _save_data["currency"][type])
		return true
	
	return false


# --- INVENTORY SYSTEM ---

func get_inventory() -> Array:
	"""Get inventory items array"""
	if not _save_data.has("inventory"):
		_save_data["inventory"] = []
	return _save_data["inventory"]


func save_inventory(items: Array) -> void:
	"""Save inventory state"""
	_save_data["inventory"] = items
	_save_dirty = true
