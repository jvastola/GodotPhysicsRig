extends PanelContainer
class_name GitPanelUI

@export_range(5, 50, 1) var history_limit: int = 20

@onready var path_label: Label = $MarginContainer/VBoxContainer/PathLabel
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusLabel
@onready var changes_list: ItemList = $MarginContainer/VBoxContainer/ChangesList
@onready var staged_list: ItemList = $MarginContainer/VBoxContainer/StagedList
@onready var history_list: ItemList = $MarginContainer/VBoxContainer/HistoryList
@onready var commit_message: TextEdit = $MarginContainer/VBoxContainer/CommitMessage
@onready var commit_button: Button = $MarginContainer/VBoxContainer/CommitButton
@onready var stage_selected_button: Button = $MarginContainer/VBoxContainer/ChangesButtons/StageSelectedButton
@onready var stage_all_button: Button = $MarginContainer/VBoxContainer/ChangesButtons/StageAllButton
@onready var unstage_selected_button: Button = $MarginContainer/VBoxContainer/StagedButtons/UnstageSelectedButton
@onready var unstage_all_button: Button = $MarginContainer/VBoxContainer/StagedButtons/UnstageAllButton
@onready var refresh_status_button: Button = $MarginContainer/VBoxContainer/RefreshRow/RefreshStatusButton
@onready var refresh_history_button: Button = $MarginContainer/VBoxContainer/RefreshRow/RefreshHistoryButton

var git := GitService.new()
var _busy: bool = false
static var instance: GitPanelUI = null


func _ready() -> void:
	instance = self
	add_to_group("git_panel")
	_setup_lists()
	_connect_signals()
	_update_path_label()
	refresh_status()
	refresh_history()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and instance == self:
		instance = null


func _setup_lists() -> void:
	changes_list.select_mode = ItemList.SELECT_MULTI
	staged_list.select_mode = ItemList.SELECT_MULTI
	history_list.select_mode = ItemList.SELECT_SINGLE


func _connect_signals() -> void:
	commit_button.pressed.connect(_on_commit_pressed)
	stage_selected_button.pressed.connect(_on_stage_selected_pressed)
	stage_all_button.pressed.connect(_on_stage_all_pressed)
	unstage_selected_button.pressed.connect(_on_unstage_selected_pressed)
	unstage_all_button.pressed.connect(_on_unstage_all_pressed)
	refresh_status_button.pressed.connect(refresh_status)
	refresh_history_button.pressed.connect(refresh_history)
	changes_list.item_activated.connect(_on_changes_item_activated)
	staged_list.item_activated.connect(_on_staged_item_activated)
	history_list.item_activated.connect(_on_history_item_activated)


func _update_path_label() -> void:
	var branch := git.get_branch()
	var root := ProjectSettings.localize_path(git.repo_root)
	if branch.is_empty():
		path_label.text = "Repo: %s" % root
	else:
		path_label.text = "Repo: %s (branch: %s)" % [root, branch]


func refresh_status() -> void:
	if _busy:
		return
	_set_busy(true)
	var res := git.get_status()
	if res.has("error"):
		_set_status("Status error: %s" % res.error)
		_set_busy(false)
		return
	_populate_changes(res)
	_set_status("Status updated")
	_set_busy(false)


func refresh_history() -> void:
	if _busy:
		return
	_set_busy(true)
	var res := git.get_history(history_limit)
	if res.has("error"):
		_set_status("History error: %s" % res.error)
		_set_busy(false)
		return
	_populate_history(res.history)
	_set_status("History updated")
	_set_busy(false)


func _populate_changes(status: Dictionary) -> void:
	changes_list.clear()
	staged_list.clear()
	var pending: Array = []
	pending.append_array(status.get("untracked", []))
	pending.append_array(status.get("unstaged", []))
	for entry in pending:
		_add_item(changes_list, entry)
	for entry in status.get("staged", []):
		_add_item(staged_list, entry)


func _populate_history(history: Array) -> void:
	history_list.clear()
	var idx := 0
	for entry in history:
		var label := "[%s] %s | %s" % [entry.hash, entry.date, entry.message]
		history_list.add_item(label)
		history_list.set_item_metadata(idx, entry)
		idx += 1


func _add_item(list: ItemList, entry: Dictionary) -> void:
	var label := "%s   %s" % [entry.get("code", ""), entry.get("path", "")]
	var idx := list.get_item_count()
	list.add_item(label)
	list.set_item_metadata(idx, entry)


func _on_commit_pressed() -> void:
	if _busy:
		return
	var msg := commit_message.text.strip_edges()
	if msg.is_empty():
		_set_status("Enter a commit message")
		return
	_set_busy(true)
	var res := git.commit(msg)
	if res.code == 0:
		commit_message.text = ""
		_set_status("Commit created")
	else:
		_set_status("Commit failed: %s" % res.output)
	refresh_status()
	refresh_history()
	_set_busy(false)


func _on_stage_selected_pressed() -> void:
	_stage_paths(_get_selected_paths(changes_list))


func _on_stage_all_pressed() -> void:
	if _busy:
		return
	_set_busy(true)
	var res := git.stage_all()
	if res.code == 0:
		_set_status("Staged all changes")
	else:
		_set_status("Stage all failed: %s" % res.output)
	refresh_status()
	_set_busy(false)


func _on_unstage_selected_pressed() -> void:
	_unstage_paths(_get_selected_paths(staged_list))


func _on_unstage_all_pressed() -> void:
	if _busy:
		return
	_set_busy(true)
	var res := git.unstage_all()
	if res.code == 0:
		_set_status("Unstaged all changes")
	else:
		_set_status("Unstage all failed: %s" % res.output)
	refresh_status()
	_set_busy(false)


func _on_changes_item_activated(index: int) -> void:
	var entry: Dictionary = changes_list.get_item_metadata(index)
	_stage_paths([entry.path])


func _on_staged_item_activated(index: int) -> void:
	var entry: Dictionary = staged_list.get_item_metadata(index)
	_unstage_paths([entry.path])


func _on_history_item_activated(index: int) -> void:
	var entry: Dictionary = history_list.get_item_metadata(index)
	if entry:
		_set_status("[%s] %s - %s" % [entry.hash, entry.date, entry.message])


func _stage_paths(paths: Array) -> void:
	if _busy or paths.is_empty():
		if paths.is_empty():
			_set_status("No files selected to stage")
		return
	_set_busy(true)
	var res := git.stage_paths(paths)
	if res.code == 0:
		_set_status("Staged %d item(s)" % paths.size())
	else:
		_set_status("Stage failed: %s" % res.output)
	refresh_status()
	_set_busy(false)


func _unstage_paths(paths: Array) -> void:
	if _busy or paths.is_empty():
		if paths.is_empty():
			_set_status("No files selected to unstage")
		return
	_set_busy(true)
	var res := git.unstage_paths(paths)
	if res.code == 0:
		_set_status("Unstaged %d item(s)" % paths.size())
	else:
		_set_status("Unstage failed: %s" % res.output)
	refresh_status()
	_set_busy(false)


func stage_paths_and_refresh(paths: Array) -> void:
	if paths.is_empty():
		return
	var res := git.stage_paths(paths)
	if res.code == 0:
		_set_status("Staged %d item(s)" % paths.size())
	else:
		_set_status("Stage failed: %s" % res.output)
	refresh_status()
	refresh_history()


func _get_selected_paths(list: ItemList) -> Array:
	var selected: Array = []
	for i in list.get_selected_items():
		var entry: Dictionary = list.get_item_metadata(i)
		if entry and entry.has("path"):
			selected.append(entry.path)
	return selected


func _set_busy(value: bool) -> void:
	_busy = value
	var disabled := value
	for btn in [
		commit_button,
		stage_selected_button,
		stage_all_button,
		unstage_selected_button,
		unstage_all_button,
		refresh_status_button,
		refresh_history_button
	]:
		if btn:
			btn.disabled = disabled
	commit_message.editable = not disabled


func _set_status(text: String) -> void:
	status_label.text = text
