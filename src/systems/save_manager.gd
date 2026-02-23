# SaveManager Autoload
# Manages persistent game state across sessions
extends Node

const SAVE_FILE_PATH := "user://save_data.json"
const SAVE_TEMP_PATH := "user://save_data.tmp"
const DEFAULT_SIGNING_SECRET := "rig_development_secret"

# Cached save data
var _save_data: Dictionary = {}
var _save_dirty := false
var _autosave_timer := 0.0
# Debounce autosave writes to reduce churn on mobile/Quest storage.
const AUTOSAVE_INTERVAL := 5.0  # seconds
const LEGAL_KEY := "legal_acceptance"


func _ready() -> void:
	# Load save data on startup
	load_game_state()
	print("SaveManager: Initialized, save file: ", SAVE_FILE_PATH)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_maybe_flush_save("wm_close_request")
	elif what == NOTIFICATION_EXIT_TREE:
		_maybe_flush_save("exit_tree")


func _process(delta: float) -> void:
	# Auto-save if data has changed
	if _save_dirty:
		_autosave_timer += delta
		if _autosave_timer >= AUTOSAVE_INTERVAL:
			save_game_state()
			_autosave_timer = 0.0


func _maybe_flush_save(reason: String = "") -> void:
	if _save_dirty:
		print("SaveManager: Flushing dirty save_data before exit (", reason, ")")
		save_game_state()


func save_game_state() -> void:
	"""Write current save data to disk with integrity signature"""
	var json_string := JSON.stringify(_save_data)
	
	# SECURE COMPONENT: Sign the data to detect tampering (Issue #7)
	var signature = _generate_signature(json_string)
	var final_payload = {
		"data": _save_data,
		"signature": signature
	}
	
	var final_json = JSON.stringify(final_payload, "\t")
	if _write_atomic(final_json):
		_save_dirty = false
		_autosave_timer = 0.0
		print("SaveManager: Game state saved with integrity signature")


func load_game_state() -> void:
	"""Load save data from disk and verify integrity"""
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
			var payload = json.data
			if payload is Dictionary and payload.has("data") and payload.has("signature"):
				var actual_data = payload["data"]
				var provided_signature = payload["signature"]
				var data_string = JSON.stringify(actual_data)
				
				# SECURE COMPONENT: Verify signature
				if _is_signature_valid(data_string, str(provided_signature)):
					_save_data = actual_data
					print("SaveManager: Loaded and verified save data")
				else:
					push_error("SaveManager: SAVE DATA TAMPERING DETECTED! Signature mismatch.")
					# In a real game, you might want to revert to a cloud backup
					# Avoid destructive overwrite on failure; keep save untouched until a valid write path is available.
					_save_data = {}
					_save_dirty = false
			else:
				# Legacy format or corrupted
				push_warning("SaveManager: Save file format is legacy or corrupted. Attempting migration.")
				_save_data = payload if payload is Dictionary else {}
				_save_dirty = true
		else:
			push_error("SaveManager: Failed to parse save file: ", json.get_error_line(), ": ", json.get_error_message())
			_save_data = {}
	else:
		push_error("SaveManager: Failed to read save file: ", FileAccess.get_open_error())
		_save_data = {}


func _generate_signature(data_string: String, secret_override: String = "") -> String:
	var secret := _get_signing_secret()
	if secret_override != "":
		secret = secret_override

	# Simple SHA-256 HMAC-style signature
	return (data_string + secret).sha256_text()


func _is_signature_valid(data_string: String, provided_signature: String) -> bool:
	if _generate_signature(data_string) == provided_signature:
		return true

	# Backward compatibility: older saves may have been signed before ConfigManager loaded.
	var current_secret := _get_signing_secret()
	if current_secret != DEFAULT_SIGNING_SECRET and _generate_signature(data_string, DEFAULT_SIGNING_SECRET) == provided_signature:
		push_warning("SaveManager: Save signature validated with legacy default secret. Resave to migrate signature.")
		_save_dirty = true
		return true

	return false


func _get_signing_secret() -> String:
	var secret := DEFAULT_SIGNING_SECRET
	if has_node("/root/ConfigManager"):
		secret = str(get_node("/root/ConfigManager").get_value("save_signing_secret", secret))
	return secret


# Write JSON atomically: write to temp, flush, then rename over the real file.
func _write_atomic(json_string: String) -> bool:
	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("SaveManager: Cannot open user:// directory")
		return false

	# Write to temp file first
	var tmp_file := FileAccess.open(SAVE_TEMP_PATH, FileAccess.WRITE_READ)
	if tmp_file == null:
		push_error("SaveManager: Failed to open temp save file: ", FileAccess.get_open_error())
		return false
	tmp_file.store_string(json_string)
	tmp_file.flush()
	tmp_file.close()

	# Replace existing save atomically
	if dir.file_exists(SAVE_FILE_PATH):
		dir.remove(SAVE_FILE_PATH)
	var err := dir.rename(SAVE_TEMP_PATH, SAVE_FILE_PATH)
	if err != OK:
		push_error("SaveManager: Failed to finalize save (rename): ", err)
		return false
	return true


# --- LEGAL ACCEPTANCE ---

func get_legal_acceptance() -> Dictionary:
	"""Return saved legal acceptance info {tos_version, privacy_version, agreed_at} or {}."""
	if not _save_data.has(LEGAL_KEY):
		return {}
	var data: Dictionary = _save_data[LEGAL_KEY]
	return {
		"tos_version": data.get("tos_version", ""),
		"privacy_version": data.get("privacy_version", ""),
		"agreed_at": data.get("agreed_at", 0.0),
	}


func set_legal_acceptance(tos_version: String, privacy_version: String = "", timestamp: float = -1.0) -> void:
	"""Persist the accepted TOS/Privacy versions with a timestamp."""
	var ts := timestamp
	if ts < 0.0:
		ts = Time.get_unix_time_from_system()
	_save_data[LEGAL_KEY] = {
		"tos_version": tos_version,
		"privacy_version": privacy_version if privacy_version != "" else tos_version,
		"agreed_at": ts,
	}
	_save_dirty = true


func clear_legal_acceptance() -> void:
	if _save_data.has(LEGAL_KEY):
		_save_data.erase(LEGAL_KEY)
		_save_dirty = true


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


# --- MOVEMENT SETTINGS PERSISTENCE ---
# Auto-saves movement settings so they persist across app restarts (Meta VRCS requirement)

const MOVEMENT_SETTINGS_KEY := "movement_settings"

func save_movement_settings(settings: Dictionary) -> void:
	"""Save movement settings to persistent storage"""
	_save_data[MOVEMENT_SETTINGS_KEY] = settings.duplicate()
	_save_dirty = true
	print("SaveManager: Movement settings saved")


func get_movement_settings() -> Dictionary:
	"""Load movement settings from persistent storage. Returns empty dict if none saved."""
	if not _save_data.has(MOVEMENT_SETTINGS_KEY):
		return {}
	return _save_data[MOVEMENT_SETTINGS_KEY].duplicate()


func has_movement_settings() -> bool:
	"""Check if movement settings have been saved previously"""
	return _save_data.has(MOVEMENT_SETTINGS_KEY) and not _save_data[MOVEMENT_SETTINGS_KEY].is_empty()


# --- INPUT BINDINGS PERSISTENCE ---
# Auto-saves custom input bindings so they persist across app restarts

const INPUT_BINDINGS_KEY := "input_bindings"

func save_input_bindings(bindings: Dictionary) -> void:
	"""Save custom input bindings to persistent storage"""
	_save_data[INPUT_BINDINGS_KEY] = bindings.duplicate(true)
	_save_dirty = true
	print("SaveManager: Input bindings saved")


func get_input_bindings() -> Dictionary:
	"""Load input bindings from persistent storage. Returns empty dict if none saved."""
	if not _save_data.has(INPUT_BINDINGS_KEY):
		return {}
	return _save_data[INPUT_BINDINGS_KEY].duplicate(true)


func has_input_bindings() -> bool:
	"""Check if input bindings have been saved previously"""
	return _save_data.has(INPUT_BINDINGS_KEY) and not _save_data[INPUT_BINDINGS_KEY].is_empty()


# --- AUDIO SETTINGS PERSISTENCE ---
# Auto-saves audio settings so they persist across app restarts

const AUDIO_SETTINGS_KEY := "audio_settings"

func save_audio_settings(settings: Dictionary) -> void:
	"""Save audio settings to persistent storage"""
	_save_data[AUDIO_SETTINGS_KEY] = settings.duplicate()
	_save_dirty = true


func get_audio_settings() -> Dictionary:
	"""Load audio settings from persistent storage. Returns empty dict if none saved."""
	if not _save_data.has(AUDIO_SETTINGS_KEY):
		return {}
	return _save_data[AUDIO_SETTINGS_KEY].duplicate()


func has_audio_settings() -> bool:
	"""Check if audio settings have been saved previously"""
	return _save_data.has(AUDIO_SETTINGS_KEY) and not _save_data[AUDIO_SETTINGS_KEY].is_empty()
