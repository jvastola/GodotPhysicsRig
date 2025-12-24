extends RefCounted
class_name GitService

## Git service with real git CLI support and fallback to local tracking.
## Automatically detects if git is available and uses it when possible.
## Includes GitHub API support for Quest/mobile where git CLI isn't available.

signal remote_operation_completed(success: bool, message: String)
signal remote_progress(message: String)

var repo_root: String
var _use_real_git: bool = false

# Remote configuration - defaults for your repo
var remote_url: String = "https://github.com/"
var remote_token: String = ""  # Set via UI or settings file - DO NOT hardcode tokens!
var remote_owner: String = "j"
var remote_repo: String = "scenetreevr"
var remote_branch: String = "main"

const USER_REPO_ROOT := "user://repo"
const STATE_FILE := "user://gitpanel_state.json"
const REMOTE_SETTINGS_FILE := "user://git_remote_settings.json"
const GITHUB_API_BASE := "https://api.github.com"
const TRACK_EXTS: Array = [
	"gd", "tscn", "tres", "gdshader", "shader", "cfg", "json", "txt", "md", "cs"
]
const IGNORE_DIRS: Array = [".git", ".godot", ".import", "addons", "android", "build", "tmp"]
const IGNORE_SUFFIX := [".import"]


func _init(repo_path: String = "") -> void:
	repo_root = repo_path
	if repo_root.is_empty():
		repo_root = ProjectSettings.globalize_path("res://")
	_load_remote_settings()		

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


# ============================================================================
# REMOTE CONFIGURATION
# ============================================================================

func configure_remote(url: String, token: String, branch: String = "main") -> Dictionary:
	## Configure GitHub remote. URL format: https://github.com/owner/repo
	remote_url = url.strip_edges()
	remote_token = token.strip_edges()
	remote_branch = branch
	
	# Parse owner/repo from URL
	var parsed := _parse_github_url(remote_url)
	if parsed.is_empty():
		return {"code": 1, "output": "Invalid GitHub URL. Use: https://github.com/owner/repo"}
	
	remote_owner = parsed.owner
	remote_repo = parsed.repo
	_save_remote_settings()
	
	return {"code": 0, "output": "Remote configured: %s/%s" % [remote_owner, remote_repo]}


func _parse_github_url(url: String) -> Dictionary:
	# Supports: https://github.com/owner/repo or https://github.com/owner/repo.git
	var clean := url.replace(".git", "").strip_edges()
	if clean.begins_with("https://github.com/"):
		var path := clean.replace("https://github.com/", "")
		var parts := path.split("/")
		if parts.size() >= 2:
			return {"owner": parts[0], "repo": parts[1]}
	return {}


func _load_remote_settings() -> void:
	if not FileAccess.file_exists(REMOTE_SETTINGS_FILE):
		return
	var f := FileAccess.open(REMOTE_SETTINGS_FILE, FileAccess.READ)
	if not f:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	remote_url = data.get("remote_url", "")
	remote_token = data.get("remote_token", "")
	remote_owner = data.get("remote_owner", "")
	remote_repo = data.get("remote_repo", "")
	remote_branch = data.get("remote_branch", "main")


func _save_remote_settings() -> void:
	var data := {
		"remote_url": remote_url,
		"remote_token": remote_token,
		"remote_owner": remote_owner,
		"remote_repo": remote_repo,
		"remote_branch": remote_branch
	}
	var f := FileAccess.open(REMOTE_SETTINGS_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))


func is_remote_configured() -> bool:
	return not remote_owner.is_empty() and not remote_repo.is_empty() and not remote_token.is_empty()


# ============================================================================
# GITHUB API - ASYNC OPERATIONS (requires Node for HTTPRequest)
# ============================================================================

## Call these from a Node that can manage HTTPRequest children

func create_push_request(parent_node: Node, callback: Callable) -> void:
	## Push all committed files to GitHub. Callback receives (success: bool, message: String)
	if not is_remote_configured():
		callback.call(false, "Remote not configured")
		return
	
	var state := _load_state()
	var commits: Array = state.get("commits", [])
	if commits.is_empty():
		callback.call(false, "No commits to push")
		return
	
	# Get the latest commit's file contents
	var latest_commit: Dictionary = commits[-1]
	var contents: Dictionary = latest_commit.get("contents", {})
	
	if contents.is_empty():
		callback.call(false, "No file contents in latest commit")
		return
	
	# Start pushing files one by one
	var push_context := {
		"parent": parent_node,
		"callback": callback,
		"files_to_push": contents.keys(),
		"contents": contents,
		"current_index": 0,
		"success_count": 0,
		"error_messages": []
	}
	_push_next_file(push_context)


func _push_next_file(ctx: Dictionary) -> void:
	var files: Array = ctx.files_to_push
	var idx: int = ctx.current_index
	
	if idx >= files.size():
		# All done
		var callback: Callable = ctx.callback
		var errors: Array = ctx.error_messages
		if errors.is_empty():
			callback.call(true, "Pushed %d file(s)" % ctx.success_count)
		else:
			callback.call(false, "Errors: %s" % ", ".join(errors))
		return
	
	var file_path: String = files[idx]
	var content: String = ctx.contents[file_path]
	var parent: Node = ctx.parent
	
	# Convert res:// path to repo-relative path
	var repo_path := file_path.replace("res://", "")
	
	# First, try to get the file's SHA (needed for updates)
	_get_file_sha(parent, repo_path, func(sha: String):
		_upload_file(parent, repo_path, content, sha, func(success: bool, msg: String):
			if success:
				ctx.success_count += 1
			else:
				ctx.error_messages.append("%s: %s" % [repo_path, msg])
			ctx.current_index += 1
			_push_next_file(ctx)
		)
	)


func _get_file_sha(parent: Node, repo_path: String, callback: Callable) -> void:
	## Get SHA of existing file (empty string if file doesn't exist)
	var url := "%s/repos/%s/%s/contents/%s?ref=%s" % [
		GITHUB_API_BASE, remote_owner, remote_repo, repo_path, remote_branch
	]
	
	var http := HTTPRequest.new()
	parent.add_child(http)
	
	http.request_completed.connect(func(result: int, code: int, headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if code == 200:
			var json: Variant = JSON.parse_string(body.get_string_from_utf8())
			if typeof(json) == TYPE_DICTIONARY:
				callback.call(json.get("sha", ""))
				return
		callback.call("")  # File doesn't exist or error
	)
	
	var headers := _get_auth_headers()
	http.request(url, headers, HTTPClient.METHOD_GET)


func _upload_file(parent: Node, repo_path: String, content: String, sha: String, callback: Callable) -> void:
	## Upload/update a file via GitHub Contents API
	var url := "%s/repos/%s/%s/contents/%s" % [
		GITHUB_API_BASE, remote_owner, remote_repo, repo_path
	]
	
	var http := HTTPRequest.new()
	parent.add_child(http)
	
	http.request_completed.connect(func(result: int, code: int, headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if code == 200 or code == 201:
			callback.call(true, "OK")
		else:
			var error_msg := "HTTP %d" % code
			var json: Variant = JSON.parse_string(body.get_string_from_utf8())
			if typeof(json) == TYPE_DICTIONARY and json.has("message"):
				error_msg = json.message
			callback.call(false, error_msg)
	)
	
	var payload := {
		"message": "Update %s" % repo_path,
		"content": Marshalls.raw_to_base64(content.to_utf8_buffer()),
		"branch": remote_branch
	}
	if not sha.is_empty():
		payload["sha"] = sha
	
	var headers := _get_auth_headers()
	headers.append("Content-Type: application/json")
	http.request(url, headers, HTTPClient.METHOD_PUT, JSON.stringify(payload))


func create_pull_request(parent_node: Node, callback: Callable) -> void:
	## Pull files from GitHub. Callback receives (success: bool, message: String)
	if not is_remote_configured():
		callback.call(false, "Remote not configured")
		return
	
	# Get the tree of files from the repo
	var url := "%s/repos/%s/%s/git/trees/%s?recursive=1" % [
		GITHUB_API_BASE, remote_owner, remote_repo, remote_branch
	]
	
	var http := HTTPRequest.new()
	parent_node.add_child(http)
	
	http.request_completed.connect(func(result: int, code: int, headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if code != 200:
			callback.call(false, "Failed to get repo tree: HTTP %d" % code)
			return
		
		var json: Variant = JSON.parse_string(body.get_string_from_utf8())
		if typeof(json) != TYPE_DICTIONARY:
			callback.call(false, "Invalid response from GitHub")
			return
		
		var tree: Array = json.get("tree", [])
		var files_to_pull: Array = []
		
		for item in tree:
			if item.get("type", "") != "blob":
				continue
			var path: String = item.get("path", "")
			var ext := path.get_extension().to_lower()
			if TRACK_EXTS.has(ext):
				files_to_pull.append({"path": path, "sha": item.get("sha", "")})
		
		if files_to_pull.is_empty():
			callback.call(true, "No tracked files to pull")
			return
		
		# Pull files one by one
		var pull_ctx := {
			"parent": parent_node,
			"callback": callback,
			"files": files_to_pull,
			"current_index": 0,
			"success_count": 0,
			"error_messages": []
		}
		_pull_next_file(pull_ctx)
	)
	
	var headers := _get_auth_headers()
	http.request(url, headers, HTTPClient.METHOD_GET)


func _pull_next_file(ctx: Dictionary) -> void:
	var files: Array = ctx.files
	var idx: int = ctx.current_index
	
	if idx >= files.size():
		var callback: Callable = ctx.callback
		var errors: Array = ctx.error_messages
		if errors.is_empty():
			callback.call(true, "Pulled %d file(s)" % ctx.success_count)
		else:
			callback.call(false, "Errors: %s" % ", ".join(errors))
		return
	
	var file_info: Dictionary = files[idx]
	var file_path: String = file_info.path
	var parent: Node = ctx.parent
	
	_download_file(parent, file_path, func(success: bool, content: String, msg: String):
		if success:
			# Write to res:// path
			var local_path := "res://" + file_path
			var global_path := ProjectSettings.globalize_path(local_path)
			
			# Ensure directory exists
			var dir_path := global_path.get_base_dir()
			DirAccess.make_dir_recursive_absolute(dir_path)
			
			var f := FileAccess.open(global_path, FileAccess.WRITE)
			if f:
				f.store_string(content)
				ctx.success_count += 1
			else:
				ctx.error_messages.append("%s: Failed to write" % file_path)
		else:
			ctx.error_messages.append("%s: %s" % [file_path, msg])
		
		ctx.current_index += 1
		_pull_next_file(ctx)
	)


func _download_file(parent: Node, repo_path: String, callback: Callable) -> void:
	## Download a file's content from GitHub
	var url := "%s/repos/%s/%s/contents/%s?ref=%s" % [
		GITHUB_API_BASE, remote_owner, remote_repo, repo_path, remote_branch
	]
	
	var http := HTTPRequest.new()
	parent.add_child(http)
	
	http.request_completed.connect(func(result: int, code: int, headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if code != 200:
			callback.call(false, "", "HTTP %d" % code)
			return
		
		var json: Variant = JSON.parse_string(body.get_string_from_utf8())
		if typeof(json) != TYPE_DICTIONARY:
			callback.call(false, "", "Invalid response")
			return
		
		var content_b64: String = json.get("content", "")
		if content_b64.is_empty():
			callback.call(false, "", "No content")
			return
		
		# GitHub returns base64 with newlines, remove them
		content_b64 = content_b64.replace("\n", "")
		var content_bytes := Marshalls.base64_to_raw(content_b64)
		var content := content_bytes.get_string_from_utf8()
		callback.call(true, content, "OK")
	)
	
	var headers := _get_auth_headers()
	http.request(url, headers, HTTPClient.METHOD_GET)


func _get_auth_headers() -> PackedStringArray:
	return PackedStringArray([
		"Authorization: Bearer %s" % remote_token,
		"Accept: application/vnd.github+json",
		"X-GitHub-Api-Version: 2022-11-28",
		"User-Agent: GodotGitPanel"
	])
