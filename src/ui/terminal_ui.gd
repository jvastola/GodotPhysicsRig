extends PanelContainer

# Terminal UI - Production-safe terminal for Quest 3
# Works entirely within app sandbox - no shell execution
# Captures logs, provides debug commands, and displays system info

signal command_executed(command: String, result: String)
signal log_added(message: String, level: int)

enum LogLevel { DEBUG, INFO, WARNING, ERROR, SYSTEM }

@export var max_lines: int = 500
@export var auto_scroll: bool = true
@export var font_size: int = 11
@export var capture_godot_logs: bool = true

@onready var output_label: RichTextLabel = $MarginContainer/VBoxContainer/ScrollContainer/OutputLabel
@onready var scroll_container: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer
@onready var command_input: LineEdit = $MarginContainer/VBoxContainer/CommandRow/CommandInput
@onready var run_button: Button = $MarginContainer/VBoxContainer/CommandRow/RunButton
@onready var clear_button: Button = $MarginContainer/VBoxContainer/ButtonRow/ClearButton
@onready var copy_button: Button = $MarginContainer/VBoxContainer/ButtonRow/CopyButton
@onready var sysinfo_button: Button = $MarginContainer/VBoxContainer/ButtonRow/SysInfoButton
@onready var perf_button: Button = $MarginContainer/VBoxContainer/ButtonRow/PerfButton
@onready var filter_option: OptionButton = $MarginContainer/VBoxContainer/ButtonRow/FilterOption
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusRow/StatusLabel

var _output_lines: Array[Dictionary] = []  # {text: String, level: LogLevel, timestamp: String}
var _filter_level: int = -1  # -1 = show all
var _command_history: PackedStringArray = []
var _history_index: int = -1
var _current_dir: String = "user://"  # Current working directory for filesystem commands

# Colors for terminal output
const LEVEL_COLORS = {
	LogLevel.DEBUG: Color(0.6, 0.6, 0.65),
	LogLevel.INFO: Color(0.85, 0.85, 0.9),
	LogLevel.WARNING: Color(1.0, 0.85, 0.3),
	LogLevel.ERROR: Color(1.0, 0.4, 0.4),
	LogLevel.SYSTEM: Color(0.5, 0.8, 1.0),
}

const LEVEL_PREFIXES = {
	LogLevel.DEBUG: "DBG",
	LogLevel.INFO: "INF",
	LogLevel.WARNING: "WRN",
	LogLevel.ERROR: "ERR",
	LogLevel.SYSTEM: "SYS",
}

# Built-in commands
var _commands: Dictionary = {}

# Static instance for global access
static var instance: PanelContainer = null


func _ready() -> void:
	instance = self
	_register_commands()
	
	if output_label:
		output_label.bbcode_enabled = true
		output_label.scroll_following = auto_scroll
		output_label.add_theme_font_size_override("normal_font_size", font_size)
	
	if clear_button:
		clear_button.pressed.connect(_on_clear_pressed)
	
	if copy_button:
		copy_button.pressed.connect(_on_copy_pressed)
	
	if sysinfo_button:
		sysinfo_button.pressed.connect(func(): execute_command("sysinfo"))
	
	if perf_button:
		perf_button.pressed.connect(func(): execute_command("perf"))
	
	if run_button:
		run_button.pressed.connect(_on_run_pressed)
	
	if command_input:
		command_input.text_submitted.connect(_on_command_submitted)
		command_input.gui_input.connect(_on_command_input_gui)
	
	if filter_option:
		filter_option.add_item("All", -1)
		filter_option.add_item("Debug+", LogLevel.DEBUG)
		filter_option.add_item("Info+", LogLevel.INFO)
		filter_option.add_item("Warn+", LogLevel.WARNING)
		filter_option.add_item("Errors", LogLevel.ERROR)
		filter_option.item_selected.connect(_on_filter_changed)
	
	_update_status("Ready")
	_log(LogLevel.SYSTEM, "Terminal initialized")
	_log(LogLevel.INFO, "Type 'help' for available commands")
	
	# Hook into Godot's logging if enabled
	if capture_godot_logs:
		_setup_log_capture()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if instance == self:
			instance = null


func _register_commands() -> void:
	_commands = {
		# System commands
		"help": _cmd_help,
		"clear": _cmd_clear,
		"sysinfo": _cmd_sysinfo,
		"perf": _cmd_perf,
		"memory": _cmd_memory,
		"nodes": _cmd_nodes,
		"groups": _cmd_groups,
		"signals": _cmd_signals,
		"tree": _cmd_tree,
		"fps": _cmd_fps,
		"xr": _cmd_xr,
		"audio": _cmd_audio,
		"input": _cmd_input,
		"physics": _cmd_physics,
		"render": _cmd_render,
		"autoloads": _cmd_autoloads,
		"resources": _cmd_resources,
		"time": _cmd_time,
		"echo": _cmd_echo,
		"env": _cmd_env,
		"gc": _cmd_gc,
		"version": _cmd_version,
		"scene": _cmd_scene,
		"viewport": _cmd_viewport,
		"network": _cmd_network,
		# Filesystem commands
		"pwd": _cmd_pwd,
		"cd": _cmd_cd,
		"ls": _cmd_ls,
		"dir": _cmd_ls,  # Alias
		"cat": _cmd_cat,
		"head": _cmd_head,
		"tail": _cmd_tail,
		"touch": _cmd_touch,
		"mkdir": _cmd_mkdir,
		"rm": _cmd_rm,
		"rmdir": _cmd_rmdir,
		"cp": _cmd_cp,
		"mv": _cmd_mv,
		"write": _cmd_write,
		"append": _cmd_append,
		"stat": _cmd_stat,
		"find": _cmd_find,
		"grep": _cmd_grep,
		"df": _cmd_df,
		"wc": _cmd_wc,
	}


func _setup_log_capture() -> void:
	# Note: Godot doesn't have a direct log callback, but we can use push_error/warning hooks
	# For production, you'd typically use a custom Logger singleton
	pass


## Log a message
func _log(level: LogLevel, message: String) -> void:
	var timestamp := Time.get_time_string_from_system()
	_output_lines.append({
		"text": message,
		"level": level,
		"timestamp": timestamp,
	})
	
	while _output_lines.size() > max_lines:
		_output_lines.pop_front()
	
	_refresh_display()
	log_added.emit(message, level)


## Public logging methods
static func log_debug(message: String) -> void:
	if instance:
		instance._log(LogLevel.DEBUG, message)

static func log_info(message: String) -> void:
	if instance:
		instance._log(LogLevel.INFO, message)

static func log_warning(message: String) -> void:
	if instance:
		instance._log(LogLevel.WARNING, message)

static func log_error(message: String) -> void:
	if instance:
		instance._log(LogLevel.ERROR, message)

static func log_system(message: String) -> void:
	if instance:
		instance._log(LogLevel.SYSTEM, message)


## Execute a command
func execute_command(command_line: String) -> void:
	var trimmed := command_line.strip_edges()
	if trimmed.is_empty():
		return
	
	# Add to history
	if _command_history.is_empty() or _command_history[-1] != trimmed:
		_command_history.append(trimmed)
	_history_index = -1
	
	_log(LogLevel.SYSTEM, "$ " + trimmed)
	
	var parts := trimmed.split(" ", false)
	if parts.is_empty():
		return
	
	var cmd_name := parts[0].to_lower()
	var args := parts.slice(1)
	
	if _commands.has(cmd_name):
		var result: String = _commands[cmd_name].call(args)
		if not result.is_empty():
			for line in result.split("\n"):
				_log(LogLevel.INFO, line)
	else:
		_log(LogLevel.ERROR, "Unknown command: " + cmd_name)
		_log(LogLevel.INFO, "Type 'help' for available commands")
	
	command_executed.emit(trimmed, "")


## Refresh the display
func _refresh_display() -> void:
	if not output_label:
		return
	
	var lines: PackedStringArray = []
	
	for entry in _output_lines:
		var level: LogLevel = entry["level"]
		
		# Apply filter
		if _filter_level >= 0 and level < _filter_level:
			continue
		
		var color: Color = LEVEL_COLORS[level]
		var prefix: String = LEVEL_PREFIXES[level]
		var timestamp: String = entry["timestamp"]
		var text: String = entry["text"]
		
		var line := "[color=#666666][%s][/color] [color=#%s][%s] %s[/color]" % [
			timestamp,
			color.to_html(false),
			prefix,
			text.replace("[", "［").replace("]", "］")  # Escape BBCode brackets in content
		]
		lines.append(line)
	
	output_label.text = "\n".join(lines)
	
	if auto_scroll and scroll_container:
		await get_tree().process_frame
		scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value


func _update_status(status: String) -> void:
	if status_label:
		status_label.text = status


func _on_clear_pressed() -> void:
	_output_lines.clear()
	_refresh_display()
	_log(LogLevel.SYSTEM, "Terminal cleared")


func _on_copy_pressed() -> void:
	var text := ""
	for entry in _output_lines:
		text += "[%s] [%s] %s\n" % [entry["timestamp"], LEVEL_PREFIXES[entry["level"]], entry["text"]]
	DisplayServer.clipboard_set(text)
	_log(LogLevel.SYSTEM, "Copied %d lines to clipboard" % _output_lines.size())


func _on_run_pressed() -> void:
	if command_input and not command_input.text.strip_edges().is_empty():
		execute_command(command_input.text)
		command_input.text = ""


func _on_command_submitted(command: String) -> void:
	execute_command(command)
	if command_input:
		command_input.text = ""


func _on_command_input_gui(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP:
			_navigate_history(-1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_DOWN:
			_navigate_history(1)
			get_viewport().set_input_as_handled()


func _navigate_history(direction: int) -> void:
	if _command_history.is_empty() or not command_input:
		return
	
	if _history_index < 0:
		_history_index = _command_history.size()
	
	_history_index = clampi(_history_index + direction, 0, _command_history.size())
	
	if _history_index < _command_history.size():
		command_input.text = _command_history[_history_index]
		command_input.caret_column = command_input.text.length()
	else:
		command_input.text = ""


func _on_filter_changed(index: int) -> void:
	_filter_level = filter_option.get_item_id(index)
	_refresh_display()


# ============================================================================
# BUILT-IN COMMANDS
# ============================================================================

func _cmd_help(_args: Array) -> String:
	var lines: PackedStringArray = [
		"=== System Commands ===",
		"  help       - Show this help",
		"  clear      - Clear terminal",
		"  sysinfo    - System information",
		"  perf       - Performance stats",
		"  memory     - Memory usage",
		"  nodes      - Node count by type",
		"  groups     - List scene groups",
		"  tree       - Scene tree overview",
		"  fps        - FPS statistics",
		"  xr         - XR/VR status",
		"  audio      - Audio info",
		"  input      - Input devices",
		"  physics    - Physics stats",
		"  render     - Rendering info",
		"  autoloads  - List autoloads",
		"  resources  - Resource stats",
		"  time       - Time info",
		"  scene      - Current scene info",
		"  viewport   - Viewport info",
		"  network    - Network status",
		"  gc         - Garbage collection",
		"  version    - Engine version",
		"  echo <msg> - Echo message",
		"  env        - Environment info",
		"",
		"=== Filesystem Commands ===",
		"  pwd              - Print working directory",
		"  cd <path>        - Change directory (user://, res://)",
		"  ls [-la] [path]  - List directory contents",
		"  cat <file>       - Display file contents",
		"  head <file> [n]  - Show first n lines (default 10)",
		"  tail <file> [n]  - Show last n lines (default 10)",
		"  touch <file>     - Create empty file",
		"  mkdir <dir>      - Create directory",
		"  rm <file>        - Remove file",
		"  rmdir <dir>      - Remove empty directory",
		"  cp <src> <dst>   - Copy file",
		"  mv <src> <dst>   - Move/rename file",
		"  write <file> <text> - Write text to file",
		"  append <file> <text> - Append text to file",
		"  stat <path>      - File/directory info",
		"  find <pattern>   - Find files matching pattern",
		"  grep <pattern> <file> - Search in file",
		"  df               - Disk space info",
		"  wc <file>        - Word/line count",
		"",
		"Note: Filesystem limited to user:// (writable) and res:// (read-only)",
	]
	return "\n".join(lines)


func _cmd_clear(_args: Array) -> String:
	_output_lines.clear()
	_refresh_display()
	return "Terminal cleared"


func _cmd_sysinfo(_args: Array) -> String:
	var lines: PackedStringArray = [
		"=== System Information ===",
		"OS: %s" % OS.get_name(),
		"Model: %s" % OS.get_model_name(),
		"Processor: %d cores" % OS.get_processor_count(),
		"Locale: %s" % OS.get_locale(),
		"Video Adapter: %s" % RenderingServer.get_video_adapter_name(),
		"Video Vendor: %s" % RenderingServer.get_video_adapter_vendor(),
	]
	
	if OS.has_feature("android"):
		lines.append("Android SDK: %s" % OS.get_environment("ANDROID_SDK_VERSION") if OS.has_environment("ANDROID_SDK_VERSION") else "Android: Yes")
	
	if OS.has_feature("mobile"):
		lines.append("Platform: Mobile")
	
	var granted := OS.get_granted_permissions()
	if not granted.is_empty():
		lines.append("Permissions: %s" % ", ".join(granted))
	
	return "\n".join(lines)


func _cmd_perf(_args: Array) -> String:
	var lines: PackedStringArray = [
		"=== Performance ===",
		"FPS: %.1f" % Performance.get_monitor(Performance.TIME_FPS),
		"Process Time: %.2f ms" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000),
		"Physics Time: %.2f ms" % (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000),
		"Navigation Time: %.2f ms" % (Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000),
		"Objects: %d" % Performance.get_monitor(Performance.OBJECT_COUNT),
		"Resources: %d" % Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"Nodes: %d" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"Orphan Nodes: %d" % Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
	]
	return "\n".join(lines)


func _cmd_memory(_args: Array) -> String:
	var static_mem := Performance.get_monitor(Performance.MEMORY_STATIC)
	var static_max := Performance.get_monitor(Performance.MEMORY_STATIC_MAX)
	
	var lines: PackedStringArray = [
		"=== Memory ===",
		"Static: %.2f MB" % (static_mem / 1048576.0),
		"Static Max: %.2f MB" % (static_max / 1048576.0),
		"Object Mem: %.2f MB" % (Performance.get_monitor(Performance.MEMORY_MESSAGE_BUFFER_MAX) / 1048576.0),
	]
	return "\n".join(lines)


func _cmd_nodes(_args: Array) -> String:
	var counts: Dictionary = {}
	var root := get_tree().root
	_count_nodes_recursive(root, counts)
	
	var lines: PackedStringArray = ["=== Node Types ==="]
	var sorted_types := counts.keys()
	sorted_types.sort_custom(func(a, b): return counts[b] < counts[a])
	
	for type_name in sorted_types.slice(0, 15):
		lines.append("  %s: %d" % [type_name, counts[type_name]])
	
	lines.append("Total: %d nodes" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	return "\n".join(lines)


func _count_nodes_recursive(node: Node, counts: Dictionary) -> void:
	var type_name := node.get_class()
	counts[type_name] = counts.get(type_name, 0) + 1
	for child in node.get_children():
		_count_nodes_recursive(child, counts)


func _cmd_groups(_args: Array) -> String:
	var groups: Dictionary = {}
	var root := get_tree().root
	_collect_groups_recursive(root, groups)
	
	var lines: PackedStringArray = ["=== Scene Groups ==="]
	for group_name in groups.keys():
		lines.append("  %s: %d nodes" % [group_name, groups[group_name]])
	
	if groups.is_empty():
		lines.append("  (no groups found)")
	
	return "\n".join(lines)


func _collect_groups_recursive(node: Node, groups: Dictionary) -> void:
	for group in node.get_groups():
		var g := str(group)
		if not g.begins_with("_"):  # Skip internal groups
			groups[g] = groups.get(g, 0) + 1
	for child in node.get_children():
		_collect_groups_recursive(child, groups)


func _cmd_signals(_args: Array) -> String:
	return "Use 'signals <node_path>' to list signals for a specific node"


func _cmd_tree(_args: Array) -> String:
	var lines: PackedStringArray = ["=== Scene Tree ==="]
	var scene := get_tree().current_scene
	if scene:
		lines.append("Current: %s" % scene.name)
		_tree_recursive(scene, lines, "", 0, 3)
	else:
		lines.append("No current scene")
	return "\n".join(lines)


func _tree_recursive(node: Node, lines: PackedStringArray, indent: String, depth: int, max_depth: int) -> void:
	if depth > max_depth:
		if node.get_child_count() > 0:
			lines.append(indent + "  ... (%d children)" % node.get_child_count())
		return
	
	for i in node.get_child_count():
		var child := node.get_child(i)
		var prefix := "├─ " if i < node.get_child_count() - 1 else "└─ "
		var child_indent := "│  " if i < node.get_child_count() - 1 else "   "
		lines.append(indent + prefix + child.name + " [%s]" % child.get_class())
		_tree_recursive(child, lines, indent + child_indent, depth + 1, max_depth)


func _cmd_fps(_args: Array) -> String:
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var frame_time := 1000.0 / maxf(fps, 0.001)
	return "FPS: %.1f (%.2f ms/frame)" % [fps, frame_time]


func _cmd_xr(_args: Array) -> String:
	var lines: PackedStringArray = ["=== XR Status ==="]
	
	var xr_interface := XRServer.primary_interface
	if xr_interface:
		lines.append("Interface: %s" % xr_interface.name)
		lines.append("Initialized: %s" % str(xr_interface.is_initialized()))
		lines.append("Passthrough: %s" % str(xr_interface.is_passthrough_enabled() if xr_interface.has_method("is_passthrough_enabled") else "N/A"))
		
		var hmd := XRServer.get_hmd_transform()
		lines.append("HMD Pos: (%.2f, %.2f, %.2f)" % [hmd.origin.x, hmd.origin.y, hmd.origin.z])
	else:
		lines.append("No XR interface active")
	
	var trackers := XRServer.get_trackers(XRServer.TRACKER_ANY)
	lines.append("Trackers: %d" % trackers.size())
	
	return "\n".join(lines)


func _cmd_audio(_args: Array) -> String:
	var lines: PackedStringArray = [
		"=== Audio ===",
		"Driver: %s" % AudioServer.get_driver_name(),
		"Mix Rate: %d Hz" % AudioServer.get_mix_rate(),
		"Output Latency: %.1f ms" % (AudioServer.get_output_latency() * 1000),
		"Bus Count: %d" % AudioServer.bus_count,
	]
	
	for i in AudioServer.bus_count:
		var bus_name := AudioServer.get_bus_name(i)
		var volume := AudioServer.get_bus_volume_db(i)
		var muted := AudioServer.is_bus_mute(i)
		lines.append("  Bus %d: %s (%.1f dB%s)" % [i, bus_name, volume, ", muted" if muted else ""])
	
	return "\n".join(lines)


func _cmd_input(_args: Array) -> String:
	var lines: PackedStringArray = ["=== Input ==="]
	
	var joypad_count := Input.get_connected_joypads().size()
	lines.append("Connected Joypads: %d" % joypad_count)
	
	for joy_id in Input.get_connected_joypads():
		lines.append("  %d: %s" % [joy_id, Input.get_joy_name(joy_id)])
	
	var mouse_mode_names := ["Visible", "Hidden", "Captured", "Confined", "Confined Hidden"]
	var mode_idx: int = Input.mouse_mode
	var mode_name: String = mouse_mode_names[mode_idx] if mode_idx < mouse_mode_names.size() else "Unknown"
	lines.append("Mouse Mode: %s" % mode_name)
	
	return "\n".join(lines)


func _cmd_physics(_args: Array) -> String:
	var lines: PackedStringArray = [
		"=== Physics ===",
		"Active Objects 2D: %d" % Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS),
		"Collision Pairs 2D: %d" % Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS),
		"Island Count 2D: %d" % Performance.get_monitor(Performance.PHYSICS_2D_ISLAND_COUNT),
		"Active Objects 3D: %d" % Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"Collision Pairs 3D: %d" % Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		"Island Count 3D: %d" % Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT),
	]
	return "\n".join(lines)


func _cmd_render(_args: Array) -> String:
	var lines: PackedStringArray = [
		"=== Rendering ===",
		"Draw Calls: %d" % Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"Objects: %d" % Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"Primitives: %d" % Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"Video Mem: %.2f MB" % (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		"Texture Mem: %.2f MB" % (Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0),
		"Buffer Mem: %.2f MB" % (Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0),
	]
	return "\n".join(lines)


func _cmd_autoloads(_args: Array) -> String:
	var lines: PackedStringArray = ["=== Autoloads ==="]
	var root := get_tree().root
	for child in root.get_children():
		if child != get_tree().current_scene:
			lines.append("  %s [%s]" % [child.name, child.get_class()])
	return "\n".join(lines)


func _cmd_resources(_args: Array) -> String:
	var lines: PackedStringArray = [
		"=== Resources ===",
		"Total: %d" % Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
	]
	return "\n".join(lines)


func _cmd_time(_args: Array) -> String:
	var datetime := Time.get_datetime_dict_from_system()
	var ticks := Time.get_ticks_msec()
	var lines: PackedStringArray = [
		"=== Time ===",
		"System: %04d-%02d-%02d %02d:%02d:%02d" % [datetime.year, datetime.month, datetime.day, datetime.hour, datetime.minute, datetime.second],
		"Uptime: %.1f seconds" % (ticks / 1000.0),
		"Unix Time: %d" % Time.get_unix_time_from_system(),
	]
	return "\n".join(lines)


func _cmd_echo(args: Array) -> String:
	return " ".join(args) if not args.is_empty() else ""


func _cmd_env(_args: Array) -> String:
	var lines: PackedStringArray = [
		"=== Environment ===",
		"User Data: %s" % OS.get_user_data_dir(),
		"Executable: %s" % OS.get_executable_path(),
		"Cmdline: %s" % " ".join(OS.get_cmdline_args()),
	]
	
	if OS.has_feature("debug"):
		lines.append("Build: Debug")
	else:
		lines.append("Build: Release")
	
	return "\n".join(lines)


func _cmd_gc(_args: Array) -> String:
	# Note: GDScript doesn't have direct GC control, but we can hint
	return "Garbage collection hint sent (GDScript manages memory automatically)"


func _cmd_version(_args: Array) -> String:
	var info := Engine.get_version_info()
	return "Godot %s.%s.%s %s (%s)" % [info.major, info.minor, info.patch, info.status, info.hash.left(8)]


func _cmd_scene(_args: Array) -> String:
	var scene := get_tree().current_scene
	if not scene:
		return "No current scene"
	
	var lines: PackedStringArray = [
		"=== Current Scene ===",
		"Name: %s" % scene.name,
		"Path: %s" % (scene.scene_file_path if scene.scene_file_path else "(runtime)"),
		"Children: %d" % scene.get_child_count(),
	]
	return "\n".join(lines)


func _cmd_viewport(_args: Array) -> String:
	var vp := get_viewport()
	var lines: PackedStringArray = [
		"=== Viewport ===",
		"Size: %s" % str(vp.size),
		"Visible Rect: %s" % str(vp.get_visible_rect()),
	]
	if vp is SubViewport:
		var update_modes: Array[String] = ["Disabled", "Once", "When Visible", "When Parent Visible", "Always"]
		var mode_idx: int = vp.render_target_update_mode
		var mode_name: String = update_modes[mode_idx] if mode_idx < update_modes.size() else "Unknown"
		lines.append("Render Target: %s" % mode_name)
	else:
		lines.append("Render Target: Main")
	return "\n".join(lines)


func _cmd_network(_args: Array) -> String:
	var lines: PackedStringArray = ["=== Network ==="]
	
	var mp := get_tree().get_multiplayer()
	if mp and mp.multiplayer_peer and mp.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		lines.append("Connected: Yes")
		lines.append("Peer ID: %d" % mp.get_unique_id())
		lines.append("Is Server: %s" % str(mp.is_server()))
	else:
		lines.append("Connected: No")
	
	return "\n".join(lines)


# ============================================================================
# FILESYSTEM COMMANDS
# ============================================================================

## Resolve a path relative to current directory
func _resolve_path(path: String) -> String:
	if path.is_empty():
		return _current_dir
	
	# Absolute paths
	if path.begins_with("user://") or path.begins_with("res://"):
		return path
	
	# Handle special cases
	if path == "~" or path == "~/" :
		return "user://"
	
	if path.begins_with("~/"):
		return "user://" + path.substr(2)
	
	# Handle .. and .
	var base := _current_dir.rstrip("/")
	var parts := path.split("/")
	
	for part in parts:
		if part == "..":
			# Go up one directory
			var last_slash := base.rfind("/")
			if last_slash > 6:  # Keep at least "user://" or "res://"
				base = base.substr(0, last_slash)
		elif part == "." or part.is_empty():
			continue
		else:
			base = base + "/" + part
	
	return base


## Check if path is writable (only user:// is writable)
func _is_writable(path: String) -> bool:
	return path.begins_with("user://")


## Format file size
func _format_size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	elif bytes < 1048576:
		return "%.1f KB" % (bytes / 1024.0)
	elif bytes < 1073741824:
		return "%.1f MB" % (bytes / 1048576.0)
	else:
		return "%.1f GB" % (bytes / 1073741824.0)


func _cmd_pwd(_args: Array) -> String:
	return _current_dir


func _cmd_cd(args: Array) -> String:
	if args.is_empty():
		_current_dir = "user://"
		return "Changed to user://"
	
	var target := _resolve_path(args[0])
	
	# Verify directory exists
	if not DirAccess.dir_exists_absolute(target):
		return "Error: Directory not found: %s" % target
	
	_current_dir = target.rstrip("/") + "/"
	_update_status(_current_dir)
	return "Changed to %s" % _current_dir


func _cmd_ls(args: Array) -> String:
	var show_hidden := false
	var long_format := false
	var target_path := _current_dir
	
	# Parse arguments
	for arg in args:
		if arg.begins_with("-"):
			if "a" in arg:
				show_hidden = true
			if "l" in arg:
				long_format = true
		else:
			target_path = _resolve_path(arg)
	
	var dir := DirAccess.open(target_path)
	if not dir:
		return "Error: Cannot open directory: %s" % target_path
	
	var lines: PackedStringArray = []
	var entries: Array[Dictionary] = []
	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not show_hidden and file_name.begins_with("."):
			file_name = dir.get_next()
			continue
		
		var full_path := target_path.rstrip("/") + "/" + file_name
		var is_dir := dir.current_is_dir()
		var size := 0
		var modified := ""
		
		if long_format:
			if not is_dir and FileAccess.file_exists(full_path):
				var f := FileAccess.open(full_path, FileAccess.READ)
				if f:
					size = f.get_length()
					f.close()
				modified = Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(full_path))
		
		entries.append({
			"name": file_name,
			"is_dir": is_dir,
			"size": size,
			"modified": modified,
		})
		
		file_name = dir.get_next()
	dir.list_dir_end()
	
	# Sort: directories first, then alphabetically
	entries.sort_custom(func(a, b):
		if a.is_dir != b.is_dir:
			return a.is_dir  # Directories first
		return a.name.to_lower() < b.name.to_lower()
	)
	
	if long_format:
		lines.append("total %d" % entries.size())
		for entry in entries:
			var type_char := "d" if entry.is_dir else "-"
			var perms := "rwxr-xr-x" if entry.is_dir else "rw-r--r--"
			var size_str := _format_size(entry.size) if not entry.is_dir else "<DIR>"
			var name_display: String = str(entry.name) + ("/" if entry.is_dir else "")
			lines.append("%s%s %8s %s %s" % [type_char, perms, size_str, entry.modified.left(16) if entry.modified else "                ", name_display])
	else:
		var row: PackedStringArray = []
		for entry in entries:
			var name_display: String = str(entry.name) + ("/" if entry.is_dir else "")
			row.append(name_display)
			if row.size() >= 4:
				lines.append("  ".join(row))
				row.clear()
		if not row.is_empty():
			lines.append("  ".join(row))
	
	if lines.is_empty():
		return "(empty directory)"
	
	return "\n".join(lines)


func _cmd_cat(args: Array) -> String:
	if args.is_empty():
		return "Usage: cat <file>"
	
	var path := _resolve_path(args[0])
	
	if not FileAccess.file_exists(path):
		return "Error: File not found: %s" % path
	
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return "Error: Cannot read file: %s" % path
	
	var content := file.get_as_text()
	file.close()
	
	if content.length() > 10000:
		return content.left(10000) + "\n... (truncated, file too large)"
	
	return content if not content.is_empty() else "(empty file)"


func _cmd_head(args: Array) -> String:
	if args.is_empty():
		return "Usage: head <file> [lines]"
	
	var path := _resolve_path(args[0])
	var num_lines := 10
	if args.size() > 1 and args[1].is_valid_int():
		num_lines = args[1].to_int()
	
	if not FileAccess.file_exists(path):
		return "Error: File not found: %s" % path
	
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return "Error: Cannot read file: %s" % path
	
	var lines: PackedStringArray = []
	var count := 0
	while not file.eof_reached() and count < num_lines:
		lines.append(file.get_line())
		count += 1
	file.close()
	
	return "\n".join(lines)


func _cmd_tail(args: Array) -> String:
	if args.is_empty():
		return "Usage: tail <file> [lines]"
	
	var path := _resolve_path(args[0])
	var num_lines := 10
	if args.size() > 1 and args[1].is_valid_int():
		num_lines = args[1].to_int()
	
	if not FileAccess.file_exists(path):
		return "Error: File not found: %s" % path
	
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return "Error: Cannot read file: %s" % path
	
	var all_lines: PackedStringArray = []
	while not file.eof_reached():
		all_lines.append(file.get_line())
	file.close()
	
	var start := maxi(0, all_lines.size() - num_lines)
	return "\n".join(all_lines.slice(start))


func _cmd_touch(args: Array) -> String:
	if args.is_empty():
		return "Usage: touch <file>"
	
	var path := _resolve_path(args[0])
	
	if not _is_writable(path):
		return "Error: Cannot write to res:// (read-only)"
	
	if FileAccess.file_exists(path):
		return "File already exists: %s" % path
	
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return "Error: Cannot create file: %s" % path
	
	file.close()
	return "Created: %s" % path


func _cmd_mkdir(args: Array) -> String:
	if args.is_empty():
		return "Usage: mkdir <directory>"
	
	var path := _resolve_path(args[0])
	
	if not _is_writable(path):
		return "Error: Cannot write to res:// (read-only)"
	
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		return "Error: Cannot create directory: %s (error %d)" % [path, err]
	
	return "Created: %s" % path


func _cmd_rm(args: Array) -> String:
	if args.is_empty():
		return "Usage: rm <file>"
	
	var path := _resolve_path(args[0])
	
	if not _is_writable(path):
		return "Error: Cannot modify res:// (read-only)"
	
	if not FileAccess.file_exists(path):
		return "Error: File not found: %s" % path
	
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		return "Error: Cannot remove file: %s (error %d)" % [path, err]
	
	return "Removed: %s" % path


func _cmd_rmdir(args: Array) -> String:
	if args.is_empty():
		return "Usage: rmdir <directory>"
	
	var path := _resolve_path(args[0])
	
	if not _is_writable(path):
		return "Error: Cannot modify res:// (read-only)"
	
	if not DirAccess.dir_exists_absolute(path):
		return "Error: Directory not found: %s" % path
	
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		return "Error: Cannot remove directory (not empty?): %s" % path
	
	return "Removed: %s" % path


func _cmd_cp(args: Array) -> String:
	if args.size() < 2:
		return "Usage: cp <source> <destination>"
	
	var src := _resolve_path(args[0])
	var dst := _resolve_path(args[1])
	
	if not _is_writable(dst):
		return "Error: Cannot write to res:// (read-only)"
	
	if not FileAccess.file_exists(src):
		return "Error: Source file not found: %s" % src
	
	# Read source
	var src_file := FileAccess.open(src, FileAccess.READ)
	if not src_file:
		return "Error: Cannot read source: %s" % src
	
	var content := src_file.get_buffer(src_file.get_length())
	src_file.close()
	
	# If destination is a directory, use source filename
	if DirAccess.dir_exists_absolute(dst):
		dst = dst.rstrip("/") + "/" + src.get_file()
	
	# Write destination
	var dst_file := FileAccess.open(dst, FileAccess.WRITE)
	if not dst_file:
		return "Error: Cannot write destination: %s" % dst
	
	dst_file.store_buffer(content)
	dst_file.close()
	
	return "Copied: %s -> %s" % [src, dst]


func _cmd_mv(args: Array) -> String:
	if args.size() < 2:
		return "Usage: mv <source> <destination>"
	
	var src := _resolve_path(args[0])
	var dst := _resolve_path(args[1])
	
	if not _is_writable(src) or not _is_writable(dst):
		return "Error: Cannot modify res:// (read-only)"
	
	if not FileAccess.file_exists(src) and not DirAccess.dir_exists_absolute(src):
		return "Error: Source not found: %s" % src
	
	# If destination is a directory, use source filename
	if DirAccess.dir_exists_absolute(dst):
		dst = dst.rstrip("/") + "/" + src.get_file()
	
	var dir := DirAccess.open(src.get_base_dir())
	if not dir:
		return "Error: Cannot access source directory"
	
	var err := dir.rename(src, dst)
	if err != OK:
		return "Error: Cannot move: %s (error %d)" % [src, err]
	
	return "Moved: %s -> %s" % [src, dst]


func _cmd_write(args: Array) -> String:
	if args.size() < 2:
		return "Usage: write <file> <text...>"
	
	var path := _resolve_path(args[0])
	var text := " ".join(args.slice(1))
	
	if not _is_writable(path):
		return "Error: Cannot write to res:// (read-only)"
	
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return "Error: Cannot write file: %s" % path
	
	file.store_string(text)
	file.close()
	
	return "Wrote %d bytes to %s" % [text.length(), path]


func _cmd_append(args: Array) -> String:
	if args.size() < 2:
		return "Usage: append <file> <text...>"
	
	var path := _resolve_path(args[0])
	var text := " ".join(args.slice(1))
	
	if not _is_writable(path):
		return "Error: Cannot write to res:// (read-only)"
	
	# Read existing content
	var existing := ""
	if FileAccess.file_exists(path):
		var read_file := FileAccess.open(path, FileAccess.READ)
		if read_file:
			existing = read_file.get_as_text()
			read_file.close()
	
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return "Error: Cannot write file: %s" % path
	
	file.store_string(existing + text + "\n")
	file.close()
	
	return "Appended %d bytes to %s" % [text.length() + 1, path]


func _cmd_stat(args: Array) -> String:
	if args.is_empty():
		return "Usage: stat <path>"
	
	var path := _resolve_path(args[0])
	var lines: PackedStringArray = ["=== %s ===" % path]
	
	if DirAccess.dir_exists_absolute(path):
		lines.append("Type: Directory")
		lines.append("Writable: %s" % str(_is_writable(path)))
		
		# Count contents
		var dir := DirAccess.open(path)
		if dir:
			var file_count := 0
			var dir_count := 0
			dir.list_dir_begin()
			var name := dir.get_next()
			while name != "":
				if dir.current_is_dir():
					dir_count += 1
				else:
					file_count += 1
				name = dir.get_next()
			dir.list_dir_end()
			lines.append("Contents: %d files, %d directories" % [file_count, dir_count])
	elif FileAccess.file_exists(path):
		lines.append("Type: File")
		lines.append("Writable: %s" % str(_is_writable(path)))
		
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			lines.append("Size: %s (%d bytes)" % [_format_size(file.get_length()), file.get_length()])
			file.close()
		
		var mod_time := FileAccess.get_modified_time(path)
		if mod_time > 0:
			lines.append("Modified: %s" % Time.get_datetime_string_from_unix_time(mod_time))
		
		# Detect file type by extension
		var ext := path.get_extension().to_lower()
		var file_type := "Unknown"
		match ext:
			"gd": file_type = "GDScript"
			"tscn": file_type = "Scene"
			"tres": file_type = "Resource"
			"json": file_type = "JSON"
			"txt": file_type = "Text"
			"cfg": file_type = "Config"
			"png", "jpg", "jpeg", "webp": file_type = "Image"
			"wav", "ogg", "mp3": file_type = "Audio"
			"glb", "gltf": file_type = "3D Model"
			"ttf", "otf": file_type = "Font"
		lines.append("File Type: %s" % file_type)
	else:
		return "Error: Path not found: %s" % path
	
	return "\n".join(lines)


func _cmd_find(args: Array) -> String:
	if args.is_empty():
		return "Usage: find <pattern>"
	
	var pattern: String = str(args[0]).to_lower()
	var results: PackedStringArray = []
	
	_find_recursive(_current_dir, pattern, results, 0, 5)
	
	if results.is_empty():
		return "No files found matching: %s" % pattern
	
	return "Found %d matches:\n%s" % [results.size(), "\n".join(results)]


func _find_recursive(dir_path: String, pattern: String, results: PackedStringArray, depth: int, max_depth: int) -> void:
	if depth > max_depth or results.size() > 50:
		return
	
	var dir := DirAccess.open(dir_path)
	if not dir:
		return
	
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full_path := dir_path.rstrip("/") + "/" + name
		
		if name.to_lower().contains(pattern):
			results.append(full_path)
		
		if dir.current_is_dir() and not name.begins_with("."):
			_find_recursive(full_path, pattern, results, depth + 1, max_depth)
		
		name = dir.get_next()
	dir.list_dir_end()


func _cmd_grep(args: Array) -> String:
	if args.size() < 2:
		return "Usage: grep <pattern> <file>"
	
	var pattern: String = str(args[0]).to_lower()
	var path := _resolve_path(args[1])
	
	if not FileAccess.file_exists(path):
		return "Error: File not found: %s" % path
	
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return "Error: Cannot read file: %s" % path
	
	var results: PackedStringArray = []
	var line_num := 0
	
	while not file.eof_reached():
		line_num += 1
		var line := file.get_line()
		if line.to_lower().contains(pattern):
			results.append("%d: %s" % [line_num, line.left(100)])
			if results.size() > 50:
				results.append("... (too many matches)")
				break
	file.close()
	
	if results.is_empty():
		return "No matches found for: %s" % pattern
	
	return "\n".join(results)


func _cmd_df(_args: Array) -> String:
	var lines: PackedStringArray = ["=== Storage ==="]
	
	# User data directory info
	var user_path := OS.get_user_data_dir()
	lines.append("User Data: %s" % user_path)
	
	# Try to estimate space by checking some known paths
	var total_size := 0
	_calculate_dir_size("user://", total_size)
	lines.append("User Data Size: ~%s" % _format_size(total_size))
	
	# Resource path
	lines.append("Resource Path: %s" % ProjectSettings.globalize_path("res://"))
	
	return "\n".join(lines)


func _calculate_dir_size(dir_path: String, total: int) -> int:
	var dir := DirAccess.open(dir_path)
	if not dir:
		return total
	
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full_path := dir_path.rstrip("/") + "/" + name
		if dir.current_is_dir():
			if not name.begins_with("."):
				total = _calculate_dir_size(full_path, total)
		else:
			var file := FileAccess.open(full_path, FileAccess.READ)
			if file:
				total += file.get_length()
				file.close()
		name = dir.get_next()
	dir.list_dir_end()
	return total


func _cmd_wc(args: Array) -> String:
	if args.is_empty():
		return "Usage: wc <file>"
	
	var path := _resolve_path(args[0])
	
	if not FileAccess.file_exists(path):
		return "Error: File not found: %s" % path
	
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return "Error: Cannot read file: %s" % path
	
	var content := file.get_as_text()
	var bytes := file.get_length()
	file.close()
	
	var lines := content.split("\n").size()
	var words := content.split(" ", false).size()
	var chars := content.length()
	
	return "%d lines, %d words, %d chars, %d bytes" % [lines, words, chars, bytes]
