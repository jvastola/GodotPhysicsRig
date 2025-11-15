# SaveManager Autoload
# Manages persistent game state across sessions
extends Node

const SAVE_FILE_PATH := "user://save_data.json"

# Cached save data
var _save_data: Dictionary = {}
var _save_dirty := false
var _autosave_timer := 0.0
const AUTOSAVE_INTERVAL := 2.0  # Auto-save every 2 seconds if dirty


func _serialize_subdivision_meta(meta: Variant) -> Variant:
	"""Convert subdivision metadata to JSON-friendly data (array of ints when possible)."""
	if meta is Vector3i:
		return [meta.x, meta.y, meta.z]
	elif meta is Vector3:
		return [int(meta.x), int(meta.y), int(meta.z)]
	elif meta is Array and meta.size() >= 3:
		return [int(meta[0]), int(meta[1]), int(meta[2])]
	elif meta is Dictionary and meta.has("x") and meta.has("y") and meta.has("z"):
		return [int(meta["x"]), int(meta["y"]), int(meta["z"])]
	return int(meta)


func _deserialize_subdivision_meta(meta: Variant) -> Variant:
	"""Convert saved subdivision metadata back into Vector3i when possible."""
	if meta is Vector3i:
		return meta
	elif meta is Vector3:
		return Vector3i(int(meta.x), int(meta.y), int(meta.z))
	elif meta is Dictionary and meta.has("x") and meta.has("y") and meta.has("z"):
		return Vector3i(int(meta["x"]), int(meta["y"]), int(meta["z"]))
	elif meta is Array and meta.size() >= 3:
		return Vector3i(int(meta[0]), int(meta[1]), int(meta[2]))
	return int(meta)


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


# --- HEAD PAINT PERSISTENCE ---

func save_head_paint(cell_colors: Array, subdivisions_meta: Variant) -> void:
	"""Save head mesh paint state"""
	# Convert Color objects to arrays for JSON serialization
	var serialized_colors := []
	for face in cell_colors:
		var face_data := []
		for row in face:
			var row_data := []
			for color in row:
				if color is Color:
					row_data.append([color.r, color.g, color.b, color.a])
				else:
					row_data.append([1.0, 1.0, 1.0, 1.0])  # Default white
			face_data.append(row_data)
		serialized_colors.append(face_data)
	
	var serialized_subdivisions: Variant = _serialize_subdivision_meta(subdivisions_meta)
	_save_data["head_paint"] = {
		"subdivisions": serialized_subdivisions,
		"cell_colors": serialized_colors
	}
	_save_dirty = true
	print("SaveManager: Head paint state marked for save (subdivisions=", serialized_subdivisions, ")")


func load_head_paint() -> Dictionary:
	"""Load head mesh paint state. Returns {subdivisions: Variant, cell_colors: Array}"""
	if not _save_data.has("head_paint"):
		return {}
	
	var paint_data: Dictionary = _save_data["head_paint"]
	
	# Convert arrays back to Color objects
	var cell_colors := []
	if paint_data.has("cell_colors"):
		for face in paint_data["cell_colors"]:
			var face_data := []
			for row in face:
				var row_data := []
				for color_array in row:
					if color_array is Array and color_array.size() >= 4:
						row_data.append(Color(color_array[0], color_array[1], color_array[2], color_array[3]))
					else:
						row_data.append(Color.WHITE)
				face_data.append(row_data)
			cell_colors.append(face_data)
	
	return {
		"subdivisions": _deserialize_subdivision_meta(paint_data.get("subdivisions", 1)),
		"cell_colors": cell_colors
	}


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
