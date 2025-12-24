extends PanelContainer
class_name GitPanelUI

## Git Panel UI for tracking user:// folder and syncing with GitHub

signal commit_created(message: String, hash: String)
signal changes_detected(staged_count: int, unstaged_count: int)
signal remote_push_completed(success: bool, message: String)

@export_range(5, 50, 1) var history_limit: int = 20

# Main scroll container to prevent cutoff
@onready var main_scroll: ScrollContainer = $MainScroll
@onready var content_container: VBoxContainer = $MainScroll/ContentContainer

# Header section
@onready var path_label: Label = $MainScroll/ContentContainer/HeaderSection/HeaderVBox/PathLabel
@onready var branch_label: Label = $MainScroll/ContentContainer/HeaderSection/HeaderVBox/BranchLabel
@onready var status_label: Label = $MainScroll/ContentContainer/HeaderSection/HeaderVBox/StatusRow/StatusLabel

# Changes section
@onready var changes_list: ItemList = $MainScroll/ContentContainer/ChangesSection/ChangesList
@onready var staged_list: ItemList = $MainScroll/ContentContainer/StagedSection/StagedList

# Commit section
@onready var commit_message: TextEdit = $MainScroll/ContentContainer/CommitSection/CommitMessage
@onready var commit_button: Button = $MainScroll/ContentContainer/CommitSection/CommitButtons/CommitButton
@onready var use_llm_query_check: CheckBox = $MainScroll/ContentContainer/CommitSection/CommitButtons/UseLLMQueryCheck

# History section
@onready var history_list: ItemList = $MainScroll/ContentContainer/HistorySection/HistoryList
@onready var restore_button: Button = $MainScroll/ContentContainer/HistorySection/HistoryButtons/RestoreButton

# Remote section
@onready var remote_section: VBoxContainer = $MainScroll/ContentContainer/RemoteSection
@onready var remote_url_input: LineEdit = $MainScroll/ContentContainer/RemoteSection/RemoteUrlRow/RemoteUrlInput
@onready var remote_token_input: LineEdit = $MainScroll/ContentContainer/RemoteSection/RemoteTokenRow/RemoteTokenInput
@onready var push_button: Button = $MainScroll/ContentContainer/RemoteSection/RemoteButtons/PushButton
@onready var pull_button: Button = $MainScroll/ContentContainer/RemoteSection/RemoteButtons/PullButton
@onready var connect_github_button: Button = $MainScroll/ContentContainer/RemoteSection/RemoteButtons/ConnectGitHubButton

# Action buttons
@onready var stage_selected_button: Button = $MainScroll/ContentContainer/ChangesSection/ChangesButtons/StageSelectedButton
@onready var stage_all_button: Button = $MainScroll/ContentContainer/ChangesSection/ChangesButtons/StageAllButton
@onready var unstage_selected_button: Button = $MainScroll/ContentContainer/StagedSection/StagedButtons/UnstageSelectedButton
@onready var unstage_all_button: Button = $MainScroll/ContentContainer/StagedSection/StagedButtons/UnstageAllButton
@onready var refresh_button: Button = $MainScroll/ContentContainer/HeaderSection/HeaderVBox/StatusRow/RefreshButton
@onready var baseline_button: Button = $MainScroll/ContentContainer/HeaderSection/HeaderVBox/StatusRow/BaselineButton

# Git service tracking user:// folder
var git := GitService.new(ProjectSettings.globalize_path("user://"))
var _busy: bool = false
var _last_llm_query: String = ""

static var instance: GitPanelUI = null

const SETTINGS_FILE := "user://git_panel_settings.json"


func _ready() -> void:
	instance = self
	add_to_group("git_panel")
	_setup_lists()
	_connect_signals()
	_load_settings()
	_update_header()
	refresh_status()
	refresh_history()
	_connect_llm_signals()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and instance == self:
		instance = null


func _setup_lists() -> void:
	if changes_list:
		changes_list.select_mode = ItemList.SELECT_MULTI
	if staged_list:
		staged_list.select_mode = ItemList.SELECT_MULTI
	if history_list:
		history_list.select_mode = ItemList.SELECT_SINGLE


func _connect_signals() -> void:
	if commit_button:
		commit_button.pressed.connect(_on_commit_pressed)
	if stage_selected_button:
		stage_selected_button.pressed.connect(_on_stage_selected_pressed)
	if stage_all_button:
		stage_all_button.pressed.connect(_on_stage_all_pressed)
	if unstage_selected_button:
		unstage_selected_button.pressed.connect(_on_unstage_selected_pressed)
	if unstage_all_button:
		unstage_all_button.pressed.connect(_on_unstage_all_pressed)
	if refresh_button:
		refresh_button.pressed.connect(_on_refresh_pressed)
	if baseline_button:
		baseline_button.pressed.connect(_on_baseline_pressed)
	if changes_list:
		changes_list.item_activated.connect(_on_changes_item_activated)
	if staged_list:
		staged_list.item_activated.connect(_on_staged_item_activated)
	if history_list:
		history_list.item_activated.connect(_on_history_item_activated)
		history_list.item_selected.connect(_on_history_item_selected)
	if restore_button:
		restore_button.pressed.connect(_on_restore_pressed)
	if push_button:
		push_button.pressed.connect(_on_push_pressed)
	if pull_button:
		pull_button.pressed.connect(_on_pull_pressed)
	if connect_github_button:
		connect_github_button.pressed.connect(_on_connect_github_pressed)


func _connect_llm_signals() -> void:
	var llm_chat = _get_llm_chat()
	if llm_chat and llm_chat.has_signal("message_sent"):
		if not llm_chat.message_sent.is_connected(_on_llm_message_sent):
			llm_chat.message_sent.connect(_on_llm_message_sent)


func _get_llm_chat() -> Node:
	if get_tree():
		var node = get_tree().get_first_node_in_group("llm_chat")
		if node:
			return node
	return null


func _on_llm_message_sent(message: String) -> void:
	_last_llm_query = message
	if use_llm_query_check and use_llm_query_check.button_pressed:
		if commit_message:
			var clean_msg := message.strip_edges()
			if clean_msg.length() > 100:
				clean_msg = clean_msg.substr(0, 97) + "..."
			commit_message.text = clean_msg
	call_deferred("refresh_status")


func _update_header() -> void:
	if path_label:
		path_label.text = "Tracking: user://"
	if branch_label:
		branch_label.text = "Branch: %s (Local)" % git.get_branch()


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
	var staged_count: int = res.get("staged", []).size()
	var unstaged_count: int = res.get("unstaged", []).size() + res.get("untracked", []).size()
	changes_detected.emit(staged_count, unstaged_count)
	_set_status("Changes: %d staged, %d unstaged" % [staged_count, unstaged_count])
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
	_set_busy(false)


func _populate_changes(status: Dictionary) -> void:
	if changes_list:
		changes_list.clear()
	if staged_list:
		staged_list.clear()
	
	var pending: Array = []
	pending.append_array(status.get("untracked", []))
	pending.append_array(status.get("unstaged", []))
	for entry in pending:
		_add_item(changes_list, entry)
	for entry in status.get("staged", []):
		_add_item(staged_list, entry)


func _populate_history(history: Array) -> void:
	if not history_list:
		return
	history_list.clear()
	var idx := 0
	for entry in history:
		var short_hash: String = entry.hash.substr(0, 8) if entry.hash.length() > 8 else entry.hash
		var label := "[%s] %s" % [short_hash, entry.message]
		history_list.add_item(label)
		history_list.set_item_metadata(idx, entry)
		history_list.set_item_tooltip(idx, "%s\n%s" % [entry.hash, entry.date])
		idx += 1
	_update_restore_button_state(false)


func _add_item(list: ItemList, entry: Dictionary) -> void:
	if not list:
		return
	var code: String = entry.get("code", "")
	var path: String = entry.get("path", "")
	var icon_color := _get_status_color(code)
	var label := "%s  %s" % [code, path.get_file()]
	var idx := list.get_item_count()
	list.add_item(label)
	list.set_item_metadata(idx, entry)
	list.set_item_tooltip(idx, path)
	list.set_item_custom_fg_color(idx, icon_color)


func _get_status_color(code: String) -> Color:
	match code.strip_edges():
		"A", "A ": return Color(0.4, 0.9, 0.4)
		"M", " M", "M ": return Color(0.9, 0.7, 0.3)
		"D", " D", "D ": return Color(0.9, 0.4, 0.4)
		"??": return Color(0.6, 0.6, 0.9)
		_: return Color(0.8, 0.8, 0.8)


func _on_commit_pressed() -> void:
	if _busy:
		return
	var msg := commit_message.text.strip_edges() if commit_message else ""
	if msg.is_empty():
		_set_status("Enter a commit message")
		return
	_set_busy(true)
	var res := git.commit(msg)
	if res.code == 0:
		if commit_message:
			commit_message.text = ""
		_set_status("Committed: %s" % msg.substr(0, 30))
		commit_created.emit(msg, res.get("hash", ""))
	else:
		_set_status("Commit failed: %s" % res.output)
	_set_busy(false)
	refresh_status()
	refresh_history()


func _on_baseline_pressed() -> void:
	if _busy:
		return
	_set_busy(true)
	var res := git.create_initial_baseline()
	_set_status(res.output)
	_set_busy(false)
	if res.code == 0:
		if baseline_button:
			baseline_button.disabled = true
		refresh_status()
		refresh_history()


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
	_set_busy(false)
	refresh_status()


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
	_set_busy(false)
	refresh_status()


func _on_refresh_pressed() -> void:
	refresh_status()
	refresh_history()


func _on_changes_item_activated(index: int) -> void:
	if not changes_list:
		return
	var entry: Dictionary = changes_list.get_item_metadata(index)
	_stage_paths([entry.path])


func _on_staged_item_activated(index: int) -> void:
	if not staged_list:
		return
	var entry: Dictionary = staged_list.get_item_metadata(index)
	_unstage_paths([entry.path])


func _on_history_item_activated(index: int) -> void:
	if not history_list:
		return
	var entry: Dictionary = history_list.get_item_metadata(index)
	if entry:
		_set_status("[%s] %s" % [entry.hash.substr(0, 8), entry.message])
		_update_restore_button_state(true)


func _on_history_item_selected(index: int) -> void:
	_update_restore_button_state(index >= 0)


func _on_restore_pressed() -> void:
	if _busy or not history_list:
		return
	var idx := history_list.get_selected_items()
	if idx.is_empty():
		_set_status("Select a commit to restore")
		return
	var entry: Dictionary = history_list.get_item_metadata(idx[0])
	if not entry:
		_set_status("No commit data")
		return
	_set_busy(true)
	var res := git.restore_commit(entry.hash)
	if res.code == 0:
		_set_status("Restored commit")
	else:
		_set_status("Restore failed: %s" % res.output)
	_set_busy(false)
	refresh_status()
	refresh_history()


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
	_set_busy(false)
	refresh_status()


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
	_set_busy(false)
	refresh_status()


# ============================================================================
# REMOTE OPERATIONS
# ============================================================================

func _on_push_pressed() -> void:
	if _busy:
		return
	var remote_url := remote_url_input.text.strip_edges() if remote_url_input else ""
	var token := remote_token_input.text.strip_edges() if remote_token_input else ""
	
	if remote_url.is_empty():
		_set_status("Enter a remote URL")
		return
	if token.is_empty():
		_set_status("Enter a GitHub token")
		return
	
	var config_result := git.configure_remote(remote_url, token)
	if config_result.code != 0:
		_set_status(config_result.output)
		return
	
	_save_settings()
	_set_busy(true)
	_set_status("Pushing to GitHub...")
	
	git.create_push_request(self, func(success: bool, message: String):
		_set_busy(false)
		_set_status(message)
		remote_push_completed.emit(success, message)
	)


func _on_pull_pressed() -> void:
	if _busy:
		return
	var remote_url := remote_url_input.text.strip_edges() if remote_url_input else ""
	var token := remote_token_input.text.strip_edges() if remote_token_input else ""
	
	if remote_url.is_empty():
		_set_status("Enter a remote URL")
		return
	if token.is_empty():
		_set_status("Enter a GitHub token")
		return
	
	var config_result := git.configure_remote(remote_url, token)
	if config_result.code != 0:
		_set_status(config_result.output)
		return
	
	_save_settings()
	_set_busy(true)
	_set_status("Pulling from GitHub...")
	
	git.create_pull_request(self, func(success: bool, message: String):
		_set_busy(false)
		_set_status(message)
		if success:
			refresh_status()
			refresh_history()
	)


func _on_connect_github_pressed() -> void:
	_set_status("Enter repo URL and token (with repo scope)")


# ============================================================================
# UTILITY
# ============================================================================

func _get_selected_paths(list: ItemList) -> Array:
	var selected: Array = []
	if not list:
		return selected
	for i in list.get_selected_items():
		var entry: Dictionary = list.get_item_metadata(i)
		if entry and entry.has("path"):
			selected.append(entry.path)
	return selected


func _set_busy(value: bool) -> void:
	_busy = value
	var buttons := [
		commit_button, stage_selected_button, stage_all_button,
		unstage_selected_button, unstage_all_button, refresh_button,
		restore_button, push_button, pull_button, baseline_button
	]
	for btn in buttons:
		if btn:
			btn.disabled = value
	if commit_message:
		commit_message.editable = not value


func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text


func _update_restore_button_state(enabled: bool) -> void:
	if restore_button:
		restore_button.disabled = not enabled or _busy


func _load_settings() -> void:
	if remote_url_input and git.remote_url:
		remote_url_input.text = git.remote_url
	
	if not FileAccess.file_exists(SETTINGS_FILE):
		return
	var f := FileAccess.open(SETTINGS_FILE, FileAccess.READ)
	if not f:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	if remote_url_input and data.has("remote_url") and not data.remote_url.is_empty():
		remote_url_input.text = data.remote_url
	if remote_token_input and data.has("remote_token"):
		remote_token_input.text = data.remote_token
	if use_llm_query_check and data.has("use_llm_query"):
		use_llm_query_check.button_pressed = data.use_llm_query


func _save_settings() -> void:
	var data := {
		"remote_url": remote_url_input.text if remote_url_input else "",
		"remote_token": remote_token_input.text if remote_token_input else "",
		"use_llm_query": use_llm_query_check.button_pressed if use_llm_query_check else false
	}
	var f := FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))


func set_commit_message(msg: String) -> void:
	if commit_message:
		commit_message.text = msg


func get_last_llm_query() -> String:
	return _last_llm_query
