extends Control

const PerformanceMonitor = preload("res://src/systems/performance_monitor.gd")

@onready var perf_mode_check: CheckBox = $MarginContainer/VBoxContainer/PerfModeCheck
@onready var viewports_check: CheckBox = $MarginContainer/VBoxContainer/ViewportsCheck
@onready var mirrors_check: CheckBox = $MarginContainer/VBoxContainer/MirrorsCheck
@onready var shadows_check: CheckBox = $MarginContainer/VBoxContainer/ShadowsCheck
@onready var spawn_shadow_check: CheckBox = $MarginContainer/VBoxContainer/SpawnShadowCheck

var _monitor: PerformanceMonitor = null

func _ready() -> void:
	_monitor = _get_monitor()
	_refresh_state()
	_connect_signals()


func _connect_signals() -> void:
	if perf_mode_check and not perf_mode_check.toggled.is_connected(_on_perf_mode_toggled):
		perf_mode_check.toggled.connect(_on_perf_mode_toggled)
	if viewports_check and not viewports_check.toggled.is_connected(_on_viewports_toggled):
		viewports_check.toggled.connect(_on_viewports_toggled)
	if mirrors_check and not mirrors_check.toggled.is_connected(_on_mirrors_toggled):
		mirrors_check.toggled.connect(_on_mirrors_toggled)
	if shadows_check and not shadows_check.toggled.is_connected(_on_shadows_toggled):
		shadows_check.toggled.connect(_on_shadows_toggled)
	if spawn_shadow_check and not spawn_shadow_check.toggled.is_connected(_on_spawn_shadows_toggled):
		spawn_shadow_check.toggled.connect(_on_spawn_shadows_toggled)


func _get_monitor() -> PerformanceMonitor:
	if Engine.has_singleton("GameManager"):
		var gm = GameManager
		if gm and gm.performance_monitor:
			return gm.performance_monitor
	if PerformanceMonitor and PerformanceMonitor.instance:
		return PerformanceMonitor.instance
	return null


func _refresh_state() -> void:
	if not _monitor:
		return
	perf_mode_check.button_pressed = _monitor.perf_mode_enabled
	viewports_check.button_pressed = _monitor.viewports_suspended
	mirrors_check.button_pressed = _monitor.mirrors_hidden
	shadows_check.button_pressed = _monitor.shadow_distance_reduced
	spawn_shadow_check.button_pressed = _monitor.disable_shadows_for_spawns


func _on_perf_mode_toggled(enabled: bool) -> void:
	if not _monitor:
		_monitor = _get_monitor()
	if not _monitor:
		return
	_monitor.set_perf_mode(enabled)
	_refresh_state()


func _on_viewports_toggled(enabled: bool) -> void:
	if not _monitor:
		return
	_monitor.set_suspend_viewports(enabled)
	_monitor.viewports_suspended = enabled


func _on_mirrors_toggled(enabled: bool) -> void:
	if not _monitor:
		return
	_monitor.set_hide_mirrors(enabled)
	_monitor.mirrors_hidden = enabled


func _on_shadows_toggled(enabled: bool) -> void:
	if not _monitor:
		return
	_monitor.set_reduce_shadow_distance(enabled)
	_monitor.shadow_distance_reduced = enabled


func _on_spawn_shadows_toggled(enabled: bool) -> void:
	if not _monitor:
		return
	_monitor.set_disable_spawn_shadows(enabled)
	spawn_shadow_check.text = "Disable Spawn Shadows" if enabled else "Disable Spawn Shadows"
