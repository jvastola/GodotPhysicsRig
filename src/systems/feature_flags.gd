extends Node
## FeatureFlags - Centralized management of experimental/debug features
## Integrates with ConfigManager to allow remote toggles if needed.

# --- Flag Definitions ---
# Use standard naming: CATEGORY_FEATURE_NAME

# Debug Features
const DEBUG_INVENTORY_TOOLS = "debug_inventory_tools"
const DEBUG_NETWORK_STATS = "debug_network_stats"

# Experimental Features
const EXP_VOXEL_SYNC_V2 = "exp_voxel_sync_v2"
const EXP_SPATIAL_INTERACTIONS = "exp_spatial_interactions"

var _flags: Dictionary = {
	DEBUG_INVENTORY_TOOLS: false,
	DEBUG_NETWORK_STATS: true,
	EXP_VOXEL_SYNC_V2: false,
	EXP_SPATIAL_INTERACTIONS: true
}

func _ready() -> void:
	# Default to true for debug features ONLY if in editor/debug build
	if OS.is_debug_build():
		_flags[DEBUG_INVENTORY_TOOLS] = true
	
	_load_overrides()

func is_enabled(flag_name: String) -> bool:
	if not _flags.has(flag_name):
		push_warning("FeatureFlags: Accessing unknown flag '", flag_name, "'")
		return false
	return _flags[flag_name]

func _load_overrides() -> void:
	# Load overrides from ConfigManager
	if has_node("/root/ConfigManager"):
		var cm = get_node("/root/ConfigManager")
		for flag in _flags.keys():
			var env_key = "FLAG_" + flag.to_upper()
			var override = cm.get_value(env_key)
			if override != null:
				if override is String:
					_flags[flag] = (override.to_lower() == "true")
				else:
					_flags[flag] = bool(override)
	
	print("FeatureFlags: Initialized with flags: ", _flags)
