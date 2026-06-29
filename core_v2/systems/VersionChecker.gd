extends Node

signal new_version_available(version_data)

# Re-chequear updates cada N segundos para que el diálogo aparezca MID-GAME cuando se
# publica un build nuevo, no solo al arrancar. VersionNotification es autoload global,
# así que el diálogo se muestra en cualquier escena (gameplay incluido).
const PERIODIC_CHECK_INTERVAL_S := 900.0  # 15 min

var has_update := false
var latest_version_data := {}

func _ready():
	UpdateManager.connect("update_available", self, "_on_update_available")

	if Engine.editor_hint:
		return

	# Small delay to let the game initialize
	yield(get_tree().create_timer(5.0), "timeout")
	check_for_updates()

	# Loop de chequeo periódico.
	while is_inside_tree():
		yield(get_tree().create_timer(PERIODIC_CHECK_INTERVAL_S), "timeout")
		# Solo chequear si no hay un update ya en curso (descargando/listo); el
		# UpdateManager ignora el check si no está IDLE/FAILED de todos modos.
		if not has_update:
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
