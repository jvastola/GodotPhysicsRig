extends RefCounted
class_name GitService

## Lightweight helper to run git commands inside the project repo.
## Uses `git -C <repo>` to avoid changing the working directory.

var repo_root: String

func _init(repo_path: String = "") -> void:
	repo_root = repo_path
	if repo_root.is_empty():
		repo_root = ProjectSettings.globalize_path("res://")
	repo_root = repo_root.rstrip("/")  # Normalize trailing slash


func _run_git(args: Array) -> Dictionary:
	var output: Array = []
	var cmd: Array = ["-C", repo_root]
	cmd.append_array(args)
	var exit_code := OS.execute("git", cmd, output, true)
	var stdout := "\n".join(output)
	return {
		"code": exit_code,
		"output": stdout
	}


func get_status() -> Dictionary:
	# Returns a dictionary with staged, unstaged, and untracked arrays.
	var res := _run_git(["status", "--porcelain=v1"])
	if res.code != 0:
		return {"error": res.output.strip_edges()}
	return _parse_status(res.output)


func stage_paths(paths: Array) -> Dictionary:
	if paths.is_empty():
		return {"code": 0, "output": "Nothing to stage"}
	var res := _run_git(["add", "--"] + paths)
	return {"code": res.code, "output": res.output.strip_edges()}


func unstage_paths(paths: Array) -> Dictionary:
	if paths.is_empty():
		return {"code": 0, "output": "Nothing to unstage"}
	# Prefer restore --staged; falls back gracefully if git is old enough to fail.
	var res := _run_git(["restore", "--staged", "--"] + paths)
	if res.code != 0:
		res = _run_git(["reset", "HEAD", "--"] + paths)
	return {"code": res.code, "output": res.output.strip_edges()}


func stage_all() -> Dictionary:
	return _run_git(["add", "-A"])


func unstage_all() -> Dictionary:
	return _run_git(["restore", "--staged", "."])


func commit(message: String) -> Dictionary:
	var msg := message.strip_edges()
	if msg.is_empty():
		return {"code": 1, "output": "Commit message is empty"}
	return _run_git(["commit", "-m", msg])


func get_history(limit: int = 20) -> Dictionary:
	var res := _run_git([
		"log",
		"--pretty=format:%h%x09%ad%x09%an%x09%s",
		"--date=short",
		"-n",
		str(limit)
	])
	if res.code != 0:
		return {"error": res.output.strip_edges()}
	var history: Array[Dictionary] = []
	for line in res.output.split("\n"):
		if line.strip_edges().is_empty():
			continue
		var parts: PackedStringArray = line.split("\t")
		if parts.size() >= 4:
			var message_parts: Array[String] = []
			for i in range(3, parts.size()):
				message_parts.append(parts[i])
			var message: String = " ".join(message_parts)
			history.append({
				"hash": parts[0],
				"date": parts[1],
				"author": parts[2],
				"message": message
			})
	return {"history": history}


func get_branch() -> String:
	var res := _run_git(["rev-parse", "--abbrev-ref", "HEAD"])
	if res.code != 0:
		return ""
	return res.output.strip_edges()


func _parse_status(raw: String) -> Dictionary:
	var staged: Array = []
	var unstaged: Array = []
	var untracked: Array = []
	for line in raw.split("\n"):
		if line.strip_edges().is_empty():
			continue
		var x := line.substr(0, 1)
		var y := line.substr(1, 1)
		var path := line.substr(3, line.length())
		var entry := {
			"code": line.substr(0, 2),
			"path": path
		}
		if x == "?" or y == "?":
			untracked.append(entry)
		elif x != " ":
			staged.append(entry)
		elif y != " ":
			unstaged.append(entry)
	return {
		"staged": staged,
		"unstaged": unstaged,
		"untracked": untracked
	}
