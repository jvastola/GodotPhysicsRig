extends Object

# Lightweight, leveled logging helper.
enum Level { DEBUG, INFO, WARN, ERROR }

const PROJECT_SETTING_KEY := "logger/default_level"

# Default log level; can be adjusted at runtime (e.g., from a debug menu).
static var level: int = Level.INFO


static func set_level(new_level: int) -> void:
	level = clamp(new_level, Level.DEBUG, Level.ERROR)


static func get_level() -> int:
	return level


static func get_level_label(value: int = level) -> String:
	match value:
		Level.DEBUG:
			return "DEBUG"
		Level.INFO:
			return "INFO"
		Level.WARN:
			return "WARN"
		Level.ERROR:
			return "ERROR"
	return str(value)


static func apply_project_setting_default() -> void:
	var configured: int = ProjectSettings.get_setting(PROJECT_SETTING_KEY, level)
	set_level(configured)


static func set_level_from_label(label: String) -> int:
	var normalized := label.strip_edges().to_upper()
	match normalized:
		"DEBUG":
			set_level(Level.DEBUG)
		"INFO":
			set_level(Level.INFO)
		"WARN", "WARNING":
			set_level(Level.WARN)
		"ERR", "ERROR":
			set_level(Level.ERROR)
		_:
			# No change; keep current level
			return level
	return level


static func debug(category: String, message: String, extra: Variant = null) -> void:
	_emit(Level.DEBUG, category, message, extra)


static func info(category: String, message: String, extra: Variant = null) -> void:
	_emit(Level.INFO, category, message, extra)


static func warn(category: String, message: String, extra: Variant = null) -> void:
	_emit(Level.WARN, category, message, extra)


static func error(category: String, message: String, extra: Variant = null) -> void:
	_emit(Level.ERROR, category, message, extra)


static func _emit(msg_level: int, category: String, message: String, extra: Variant) -> void:
	if msg_level < level:
		return
	var parts: Array = ["[%s]" % _level_label(msg_level), "[%s]" % category, message]
	if extra != null:
		if extra is Array:
			for item in extra:
				parts.append(str(item))
		else:
			parts.append(str(extra))
	var line := " ".join(parts)
	match msg_level:
		Level.WARN:
			push_warning(line)
		Level.ERROR:
			push_error(line)
		_:
			print(line)


static func _level_label(msg_level: int) -> String:
	return get_level_label(msg_level)
