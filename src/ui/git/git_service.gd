extends RefCounted
class_name GitService

## Lightweight local version tracker (no git CLI required).
## Stores commit snapshots and staging info in user://gitpanel_state.json.

var repo_root: String
const USER_REPO_ROOT := "user://workspace_repo"
const STATE_FILE := "user://gitpanel_state.json"
const TRACK_EXTS := [
	"gd", "tscn", "tres", "gdshader", "shader", "cfg", "json", "txt", "md", "cs"
]
const IGNORE_DIRS := [".git", ".godot", ".import", "android/build", "bin", "dist", "tmp"]
const IGNORE_SUFFIX := [".import"]

func _init(repo_path: String = "") -> void:
	repo_root = repo_path
	if repo_root.is_empty():
		repo_root = _prepare_user_repo_root()
	repo_root = repo_root.rstrip("/")  # Normalize trailing slash
	_ensure_state()


func get_status() -> Dictionary:
	# Returns staged/unstaged/untracked arrays comparing current files to last commit snapshot.
	var state := _load_state()
	var commits: Array = state.get("commits", [])
	var last_snapshot: Dictionary = {}
	if commits.size() > 0:
		last_snapshot = commits[-1].get("hashes", {})
	var staged_paths: Array = state.get("staged", [])
	var current := _current_snapshot()
	var staged: Array = []
	var unstaged: Array = []
	var untracked: Array = []

	# Detect added/modified files present now
	for path in current.keys():
		var cur_hash: String = current[path]
		var prev_hash: String = last_snapshot.get(path, "")
		var is_staged := staged_paths.has(path)
		if prev_hash == "":
			# New file
			if is_staged:
				staged.append({"code": "A ", "path": path})
			else:
				untracked.append({"code": "??", "path": path})
		elif prev_hash != cur_hash:
			if is_staged:
				staged.append({"code": "M ", "path": path})
			else:
				unstaged.append({"code": " M", "path": path})
		else:
			if is_staged:
				# Staged but unchanged vs snapshot; leave unstaged to avoid clutter.
				staged.append({"code": "S ", "path": path})

	# Detect deletions (present in snapshot but missing now)
	for path in last_snapshot.keys():
		if current.has(path):
			continue
		var is_staged := staged_paths.has(path)
		if is_staged:
			staged.append({"code": "D ", "path": path})
		else:
			unstaged.append({"code": " D", "path": path})

	return {
		"staged": staged,
		"unstaged": unstaged,
		"untracked": untracked
	}


func stage_paths(paths: Array) -> Dictionary:
	if paths.is_empty():
		return {"code": 0, "output": "Nothing to stage"}
	var state := _load_state()
	var staged: Array = state.get("staged", [])
	for p in paths:
		if not staged.has(p):
			staged.append(p)
	state["staged"] = staged
	_save_state(state)
	return {"code": 0, "output": "Staged %d file(s)" % paths.size()}


func unstage_paths(paths: Array) -> Dictionary:
	if paths.is_empty():
		return {"code": 0, "output": "Nothing to unstage"}
	var state := _load_state()
	var staged: Array = state.get("staged", [])
	for p in paths:
		staged.erase(p)
	state["staged"] = staged
	_save_state(state)
	return {"code": 0, "output": "Unstaged %d file(s)" % paths.size()}


func stage_all() -> Dictionary:
	var status := get_status()
	var to_stage: Array = []
	for e in status.get("unstaged", []):
		to_stage.append(e.get("path", ""))
	for e in status.get("untracked", []):
		to_stage.append(e.get("path", ""))
	return stage_paths(to_stage)


func unstage_all() -> Dictionary:
	var state := _load_state()
	state["staged"] = []
	_save_state(state)
	return {"code": 0, "output": "Unstaged all"}


func commit(message: String) -> Dictionary:
	var msg := message.strip_edges()
	if msg.is_empty():
		return {"code": 1, "output": "Commit message is empty"}
	var state := _load_state()
	var staged: Array = state.get("staged", [])
	if staged.is_empty():
		return {"code": 1, "output": "Nothing staged"}

	var current := _current_snapshot()
	var last_snapshot: Dictionary = {}
	var commits: Array = state.get("commits", [])
	if commits.size() > 0:
		last_snapshot = commits[-1].get("hashes", {})

	# Start from previous snapshot and update with staged file states
	var new_snapshot := last_snapshot.duplicate(true)
	var contents: Dictionary = {}
	for p in staged:
		if current.has(p):
			new_snapshot[p] = current[p]
			var global_path := ProjectSettings.globalize_path(p)
			var file := FileAccess.open(global_path, FileAccess.READ)
			if file:
				contents[p] = file.get_as_text()
		else:
			# File deleted
			new_snapshot.erase(p)

	var commit_id := str(Time.get_unix_time_from_system()) + "-" + str(randi())
	var ts := Time.get_datetime_string_from_system()
	var entry := {
		"id": commit_id,
		"message": msg,
		"timestamp": ts,
		"hashes": new_snapshot,
		"contents": contents
	}
	commits.append(entry)
	state["commits"] = commits
	state["staged"] = []
	_save_state(state)
	return {"code": 0, "output": "Committed: %s" % msg}


func get_history(limit: int = 20) -> Dictionary:
	var history: Array[Dictionary] = []
	var state := _load_state()
	var commits: Array = state.get("commits", [])
	var start: int = int(max(0, commits.size() - limit))
	for i in range(commits.size() - 1, start - 1, -1):
		var c: Dictionary = commits[i]
		history.append({
			"hash": c.get("id", ""),
			"date": c.get("timestamp", ""),
			"author": "local",
			"message": c.get("message", "")
		})
	return {"history": history}


func get_branch() -> String:
	# Single local branch
	return "local"


func restore_commit(commit_id: String) -> Dictionary:
	var state := _load_state()
	var commits: Array = state.get("commits", [])
	var target: Dictionary = {}
	for c in commits:
		if c.get("id", "") == commit_id:
			target = c
			break
	if target.is_empty():
		return {"code": 1, "output": "Commit not found"}

	var hashes: Dictionary = target.get("hashes", {})
	var contents: Dictionary = target.get("contents", {})

	# Delete files not in target snapshot
	var current := _current_snapshot()
	for path in current.keys():
		if not hashes.has(path):
			_remove_file(path)

	# Restore files from contents
	for path in hashes.keys():
		if contents.has(path):
			_write_file_text(path, contents[path])

	# Clear staged after restore
	state["staged"] = []
	_save_state(state)

	return {"code": 0, "output": "Restored commit %s" % commit_id}


func _prepare_user_repo_root() -> String:
	var user_root_local := USER_REPO_ROOT
	var user_root_abs := ProjectSettings.globalize_path(user_root_local)
	_make_dir_recursive(user_root_local)
	_sync_from_res(user_root_abs)
	return user_root_abs


func _sync_from_res(target_abs_root: String) -> void:
	var src_abs := ProjectSettings.globalize_path("res://")
	_copy_dir_filtered(src_abs, target_abs_root)


func _copy_dir_filtered(src_abs: String, dst_abs: String) -> void:
	var dir := DirAccess.open(src_abs)
	if dir == null:
		return
	var err := dir.list_dir_begin()
	if err != OK:
		push_warning("_copy_dir_filtered: failed to list %s (err %s)" % [src_abs, err])
		return
	var name := dir.get_next()
	while name != "":
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		var src_path := src_abs.path_join(name)
		var dst_path := dst_abs.path_join(name)
		if dir.current_is_dir():
			if _is_ignored_dir(name):
				name = dir.get_next()
				continue
			_make_dir_recursive(dst_path)
			_copy_dir_filtered(src_path, dst_path)
		else:
			if _is_ignored_file(name):
				name = dir.get_next()
				continue
			if not _is_tracked_extension(name):
				name = dir.get_next()
				continue
			_copy_file_if_changed(src_path, dst_path)
		name = dir.get_next()
	dir.list_dir_end()


func _copy_file_if_changed(src_path: String, dst_path: String) -> void:
	var src_md5 := FileAccess.get_md5(src_path)
	var dst_md5 := FileAccess.get_md5(dst_path)
	if src_md5 != "" and src_md5 == dst_md5:
		return
	var bytes := FileAccess.get_file_as_bytes(src_path)
	if bytes.is_empty():
		return
	_make_dir_recursive(dst_path.get_base_dir())
	var f := FileAccess.open(dst_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(bytes)


func _make_dir_recursive(path: String) -> void:
	var d := DirAccess.open("user://")
	if d:
		d.make_dir_recursive(path)


func _write_file_text(repo_path: String, content: String) -> void:
	var global := ProjectSettings.globalize_path(repo_path)
	_make_dir_recursive(global.get_base_dir())
	var f := FileAccess.open(global, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(content)


func _remove_file(repo_path: String) -> void:
	var global := ProjectSettings.globalize_path(repo_path)
	if FileAccess.file_exists(global):
		DirAccess.remove_absolute(global)


func _current_snapshot() -> Dictionary:
	var results: Dictionary = {}
	_scan_dir(repo_root, results)
	return results


func _scan_dir(dir_path: String, results: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			if _is_ignored_dir(name):
				name = dir.get_next()
				continue
			_scan_dir(full, results)
		else:
			if _is_ignored_file(name):
				name = dir.get_next()
				continue
			if not _is_tracked_extension(name):
				name = dir.get_next()
				continue
			var md5 := FileAccess.get_md5(full)
			if md5 != "":
				var res_path := ProjectSettings.localize_path(full)
				results[res_path] = md5
		name = dir.get_next()
	dir.list_dir_end()


func _is_ignored_dir(name: String) -> bool:
	for d in IGNORE_DIRS:
		if name == d:
			return true
	return false


func _is_ignored_file(name: String) -> bool:
	for sfx in IGNORE_SUFFIX:
		if name.ends_with(sfx):
			return true
	return false


func _is_tracked_extension(name: String) -> bool:
	var ext := name.get_extension().to_lower()
	return TRACK_EXTS.has(ext)


func _ensure_state() -> void:
	var state := _load_state()
	if not state.has("commits"):
		state["commits"] = []
	if not state.has("staged"):
		state["staged"] = []
	if not state.has("root"):
		state["root"] = ProjectSettings.localize_path(repo_root)
	_save_state(state)


func _load_state() -> Dictionary:
	if not FileAccess.file_exists(STATE_FILE):
		return {
			"commits": [],
			"staged": [],
			"root": ProjectSettings.localize_path(repo_root)
		}
	var f := FileAccess.open(STATE_FILE, FileAccess.READ)
	if f == null:
		return {
			"commits": [],
			"staged": [],
			"root": ProjectSettings.localize_path(repo_root)
		}
	var txt := f.get_as_text()
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		return {
			"commits": [],
			"staged": [],
			"root": ProjectSettings.localize_path(repo_root)
		}
	if not data.has("commits"):
		data["commits"] = []
	if not data.has("staged"):
		data["staged"] = []
	if not data.has("root"):
		data["root"] = ProjectSettings.localize_path(repo_root)
	return data


func _save_state(state: Dictionary) -> void:
	var f := FileAccess.open(STATE_FILE, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(state, "  "))
