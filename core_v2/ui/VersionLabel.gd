# core_v2/ui/VersionLabel.gd
# FD-234: Helper for reading and formatting the application version.
extends Reference

static func get_version_string() -> String:
	return String(ProjectSettings.get_setting("application/config/version"))

static func get_formatted_version() -> String:
	var v = get_version_string()
	if v == "" or v == "null":
		return "v0.0.0-dev"
	return v
