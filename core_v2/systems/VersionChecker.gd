extends Node

signal new_version_available(version_data)

var has_update := false
var latest_version_data := {}

func _ready():
	UpdateManager.connect("update_available", self, "_on_update_available")

	# Small delay to let the game initialize
	yield(get_tree().create_timer(5.0), "timeout")
	check_for_updates()

func check_for_updates():
	UpdateManager.check_for_updates()

func _on_update_available(info):
	has_update = true
	latest_version_data = info
	# Maintain backward compatibility with the old signal format if needed
	# The old format expected a 'version' key
	if not latest_version_data.has("version") and latest_version_data.has("build_id"):
		latest_version_data["version"] = latest_version_data["build_id"]

	emit_signal("new_version_available", latest_version_data)
	print("[VersionChecker] Delegated update available: ", latest_version_data.get("version"))
