extends SceneTree

const CRITICAL_RESOURCES := [
	"res://core_v2/ui/retro/RetroOS.tres",
	"res://core_v2/components/PushableBoxV2.tscn",
	"res://core_v2/components/SlidingObjectV2.tscn",
	# Fails early when the GLB import pipeline is still incomplete.
	"res://core_v2/actors/Pilot_v2.tscn",
	"res://core_v2/actors/Programmer_v2.tscn",
	# Stage-3 curriculum coverage (doors/sparks/HDR and BaseTerrace deps).
	"res://core_v2/props/VerticalDoor.tscn",
	"res://core_v2/props/SparkEmitterV2.tscn",
	"res://core_v2/levels/BaseTerrace.tscn",
	"res://core_v2/tests/TestScene_RL_BaseTerrace.tscn",
]

func _normalize_dep_path(dep: String) -> String:
	var sep = dep.find("::")
	if sep == -1:
		return dep
	return dep.substr(0, sep)

func _collect_dependency_issues(path: String, visited: Dictionary, issues: Array) -> void:
	if path == "" or visited.has(path):
		return
	visited[path] = true
	if not ResourceLoader.exists(path):
		issues.append({"path": path, "reason": "exists=false"})
		return
	var res = load(path)
	if res == null:
		issues.append({"path": path, "reason": "load=null"})
		return
	var deps = ResourceLoader.get_dependencies(path)
	for dep in deps:
		var dep_path = _normalize_dep_path(String(dep))
		if dep_path.begins_with("res://"):
			_collect_dependency_issues(dep_path, visited, issues)

func _diagnose_failed_resource(path: String) -> void:
	var visited := {}
	var issues := []
	_collect_dependency_issues(path, visited, issues)
	if issues.empty():
		print("[CI_SMOKE][Deps] fail=%s issues=none" % path)
		return
	for item in issues:
		print("[CI_SMOKE][Deps] fail=%s dep=%s reason=%s" % [path, item.get("path", ""), item.get("reason", "")])

func _init() -> void:
	var failed := []
	for path in CRITICAL_RESOURCES:
		var res = load(path)
		if res == null:
			failed.append(path)
			printerr("[CI_SMOKE] Failed to load: ", path)
			_diagnose_failed_resource(path)
		else:
			print("[CI_SMOKE] OK: ", path)

	if failed.size() > 0:
		printerr("[CI_SMOKE] Missing resources count: ", failed.size())
		quit(1)
		return

	print("[CI_SMOKE] Critical resources loaded successfully.")
	quit(0)
