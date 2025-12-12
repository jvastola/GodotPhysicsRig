extends Object

# Lightweight, leveled logging helper.
enum Level { DEBUG, INFO, WARN, ERROR }

# Default log level; can be adjusted at runtime (e.g., from a debug menu).
static var level: int = Level.INFO


static func set_level(new_level: int) -> void:
	level = clamp(new_level, Level.DEBUG, Level.ERROR)


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
	match msg_level:
		Level.DEBUG:
			return "DEBUG"
		Level.INFO:
			return "INFO"
		Level.WARN:
			return "WARN"
		Level.ERROR:
			return "ERROR"
	return str(msg_level)
