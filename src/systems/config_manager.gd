extends Node
## ConfigManager - Handles environment-based configuration and secrets
## Centralizes access to Nakama settings, LiveKit tokens, and other sensitive data

const CONFIG_FILE_PATH = "res://config.json"
const USER_CONFIG_PATH = "user://config.json"

var _config: Dictionary = {
	"nakama_host": "158.101.21.99",
	"nakama_port": 7350,
	"nakama_server_key": "defaultkey",
	"nakama_use_ssl": false,
	"auth_service_url": ""
}
var _config_loaded := false

func _ready() -> void:
	_load_config()

func get_value(key: String, default: Variant = null) -> Variant:
	if not _config_loaded:
		_load_config()
	return _config.get(key, default)

func _load_config() -> void:
	if _config_loaded:
		return

	# 1. Start with defaults (already in _config)
	
	# 2. Try to load from res://config.json (packaged config)
	_merge_config_from_file(CONFIG_FILE_PATH)
	
	# 3. Try to load from user://config.json (local overrides/developer config)
	_merge_config_from_file(USER_CONFIG_PATH)
	
	# 4. Check Environment Variables (OS.get_environment)
	# This is critical for Docker/Server deployments
	for key in _config.keys():
		var env_val = OS.get_environment(key.to_upper())
		if not env_val.is_empty():
			if _config[key] is bool:
				_config[key] = (env_val.to_lower() == "true")
			elif _config[key] is int:
				_config[key] = env_val.to_int()
			else:
				_config[key] = env_val

	_config_loaded = true
	
	print("ConfigManager: Configuration loaded.")

func _merge_config_from_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
		
	var file = FileAccess.open(path, FileAccess.READ)
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	if error == OK:
		var data = json.get_data()
		if data is Dictionary:
			for key in data:
				_config[key] = data[key]
			print("ConfigManager: Merged config from ", path)
