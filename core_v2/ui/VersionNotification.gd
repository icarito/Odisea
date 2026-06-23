extends CanvasLayer

onready var control = $Control
onready var panel = $Control/MarginContainer/PanelContainer
onready var modal_dim = $Control/ModalDim
onready var label = $Control/MarginContainer/PanelContainer/MarginContainer/VBoxContainer/Label
onready var metadata_label = $Control/MarginContainer/PanelContainer/MarginContainer/VBoxContainer/MetadataLabel
onready var release_notes_button = $Control/MarginContainer/PanelContainer/MarginContainer/VBoxContainer/ReleaseNotesButton
onready var download_progress = $Control/MarginContainer/PanelContainer/MarginContainer/VBoxContainer/DownloadProgress
onready var action_button = $Control/MarginContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/ActionButton
onready var close_button = $Control/MarginContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/CloseButton

var _current_update_info := {}
var _dismissed_manifest_id := ""
var _is_security_critical := false
var _release_notes_url := ""

func _ready():
	panel.hide()
	modal_dim.hide()
	download_progress.hide()

	if OS.is_debug_build() or Engine.editor_hint:
		return

	UpdateManager.connect("update_available", self, "_on_update_available")
	UpdateManager.connect("update_progress", self, "_on_update_progress")
	UpdateManager.connect("update_ready", self, "_on_update_ready")
	UpdateManager.connect("update_failed", self, "_on_update_failed")

	action_button.connect("pressed", self, "_on_action_pressed")
	close_button.connect("pressed", self, "_on_close_pressed")
	release_notes_button.connect("pressed", self, "_on_release_notes_pressed")

	# Initial check
	var pending = UpdateManager.get_current_update()
	if not pending.empty():
		_on_update_available(pending)

func _on_update_available(info: Dictionary):
	var manifest_id = info.get("manifest_id", "")
	var severity = info.get("severity", "optional")

	if severity == "optional" and _dismissed_manifest_id == manifest_id:
		return

	_current_update_info = info
	_is_security_critical = (severity == "security_critical")
	_release_notes_url = info.get("release_notes_url", "")

	var artifact = UpdateManager.get_selected_artifact(info)
	var type = "Completo"
	if artifact.get("is_delta", false):
		type = "Delta"
	var size_mb = artifact.get("size", 0) / (1024.0 * 1024.0)

	# Tabla "burocrática" alineada (fuente monospace del tema retro): compara el build
	# local instalado (de build_meta) con el remoto disponible.
	var local := {}
	if UpdateManager.has_method("get_local_build_info"):
		local = UpdateManager.get_local_build_info()
	label.text = _format_update_table(info, local, type, size_mb)
	metadata_label.visible = false

	release_notes_button.visible = _release_notes_url != ""

	_setup_severity_ui(severity)
	panel.show()

# Arma una "ficha" alineada en monospace: encabezado + filas Campo/Instalado/Nuevo +
# pie con Canal/Tipo/Tamaño. El tema retro usa fuente monoespaciada, así que el
# padding por espacios alinea como tabla burocrática.
func _format_update_table(remote_info: Dictionary, local: Dictionary, type: String, size_mb: float) -> String:
	var l_ver = _short_version(local.get("version", ""))
	var r_ver = _short_version(remote_info.get("version", ""))
	var l_hash = _short_commit(local.get("commit", ""))
	var r_hash = _short_commit(remote_info.get("commit", ""))
	var l_dt = _build_datetime(local.get("version", ""), "")
	var r_dt = _build_datetime(remote_info.get("version", ""), remote_info.get("issued_at", ""))
	var channel = remote_info.get("channel", "?")

	var l_chan = local.get("channel", "?")
	# Anchos de columna calculados del contenido real (ambas columnas de datos), para
	# que todo quede alineado verticalmente como un formulario burocrático.
	var w_field := 9  # "Versión "
	var col1 := _max_len(["Instalado", l_ver, l_hash, l_dt, l_chan])
	var col2 := _max_len(["Nuevo", r_ver, r_hash, r_dt, channel])
	var rows := []
	rows.append(_row("", "Instalado", "Nuevo", w_field, col1, col2))
	rows.append(_rule(w_field, col1, col2))
	rows.append(_row("Versión", l_ver, r_ver, w_field, col1, col2))
	rows.append(_row("Commit", l_hash, r_hash, w_field, col1, col2))
	rows.append(_row("Fecha", l_dt, r_dt, w_field, col1, col2))
	rows.append(_row("Canal", l_chan, channel, w_field, col1, col2))

	var table_width := w_field + 2 + col1 + 2 + col2
	var header := _center("ACTUALIZACIÓN DISPONIBLE", table_width)
	var footer := _center("Tipo: %s    Tamaño: %.1f MB" % [type, size_mb], table_width)
	return header + "\n\n" + PoolStringArray(rows).join("\n") + "\n\n" + footer

func _max_len(items: Array) -> int:
	var m := 0
	for s in items:
		if String(s).length() > m:
			m = String(s).length()
	return m

func _center(s: String, width: int) -> String:
	var pad = int((width - s.length()) / 2.0)
	return " ".repeat(max(0, pad)) + s

func _row(field: String, a: String, b: String, wf: int, w1: int, w2: int) -> String:
	return "%s  %s  %s" % [_pad(field, wf), _pad(a, w1), _pad(b, w2)]

# String.rpad no existe en Godot 3.6; padding manual a la derecha.
func _pad(s: String, width: int) -> String:
	var out = s
	while out.length() < width:
		out += " "
	return out

func _rule(wf: int, w1: int, w2: int) -> String:
	return ("-".repeat(wf + 2 + w1 + 2 + w2))

# "0.3.2-nightly+sha (fecha)" -> "0.3.2-nightly"
func _short_version(v: String) -> String:
	if v == "":
		return "-"
	var s = v
	var plus = s.find("+")
	if plus != -1:
		s = s.substr(0, plus)
	return s.strip_edges()

func _short_commit(c: String) -> String:
	if c == "":
		return "-"
	return c.substr(0, 7)

# Devuelve "YYYY-MM-DD HH:MM": de issued_at (ISO con hora) si está, si no de la
# fecha embebida en la version "(YYYY-MM-DD)".
func _build_datetime(version: String, issued_at: String) -> String:
	if issued_at != "":
		# ISO: 2026-06-23T03:27:11.123Z -> 2026-06-23 03:27
		var iso = issued_at.replace("T", " ")
		if iso.length() >= 16:
			return iso.substr(0, 16)
	# fallback: fecha entre paréntesis en la version
	var op = version.find("(")
	var cp = version.find(")")
	if op != -1 and cp > op:
		return version.substr(op + 1, cp - op - 1)
	return "-"

func _setup_severity_ui(severity: String):
	if severity == "security_critical":
		modal_dim.show()
		close_button.text = "Salir"
		# Requirement: security_critical requests save if in gameplay
		if get_tree().current_scene and get_tree().current_scene.filename != "res://scenes/Menu.tscn":
			var persistence = get_node_or_null("/root/PersistenceManager")
			if persistence:
				print("[VersionNotification] Critical update: saving state...")
				persistence.save_checkpoint_resource(get_tree().current_scene.filename)
	else:
		modal_dim.hide()
		close_button.text = "Cerrar"
		close_button.show()

	_update_action_button_text()

func _update_action_button_text():
	var platform = OS.get_name()
	var update_manager = get_node_or_null("/root/UpdateManager")
	var status = "idle"
	if update_manager:
		status = update_manager.get_status()

	if status == "ready_to_restart":
		action_button.text = "Reiniciar para aplicar"
	elif platform == "Android":
		action_button.text = "Abrir instalador"
	elif platform == "HTML5":
		action_button.text = "Actualizar ahora"
	elif platform == "iOS":
		action_button.text = "Ver en App Store"
	else:
		action_button.text = "Descargar e instalar"

func _on_action_pressed():
	if UpdateManager.get_status() == "ready_to_restart":
		UpdateManager.request_restart()
		return

	var platform = OS.get_name()
	if platform == "iOS":
		var url = _current_update_info.get("downloads_page", "")
		if url != "":
			OS.shell_open(url)
		return

	UpdateManager.begin_update()
	action_button.disabled = true
	download_progress.value = 0
	download_progress.show()

func _on_update_progress(downloaded, total):
	download_progress.show()
	if total > 0:
		download_progress.value = (float(downloaded) / total) * 100

func _on_update_ready(_info):
	download_progress.value = 100
	action_button.disabled = false
	_update_action_button_text()

func _on_update_failed(code, recoverable):
	action_button.disabled = false
	download_progress.hide()
	if not recoverable:
		label.text = "Error de actualización: %s" % code

func _on_close_pressed():
	if _is_security_critical:
		get_tree().quit()
	else:
		panel.hide()
		if _current_update_info.get("severity") == "optional":
			_dismissed_manifest_id = _current_update_info.get("manifest_id", "")

func _on_release_notes_pressed():
	if _release_notes_url != "":
		OS.shell_open(_release_notes_url)
