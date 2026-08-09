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
var _user_confirmed := false
var _is_delta_update := false
var _we_paused := false

func _ready():
	panel.hide()
	modal_dim.hide()
	download_progress.hide()

	# NOTA: no filtrar por OS.is_debug_build() aquí. Todo build de Android se exporta
	# con --export-debug (ver .github/workflows/export_all.yml, único canal hoy:
	# nightly) y es_debug_build() es true en ese APK real que corre en el dispositivo
	# del jugador. Con ese guard, este popup nunca se conectaba a UpdateManager en
	# NINGÚN build de Android — el aviso de actualización estaba muerto en esa
	# plataforma. UpdateManager._is_source_checkout() ya distingue correctamente
	# "corriendo desde el editor/checkout" de "build empaquetado"; alcanza con
	# Engine.editor_hint acá para no molestar dentro del editor.
	if Engine.editor_hint:
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
	_user_confirmed = false

	var artifact = UpdateManager.get_selected_artifact(info)
	_is_delta_update = artifact.get("is_delta", false)
	var type = "Completo"
	if _is_delta_update:
		type = "Delta"
	var size_mb = artifact.get("size", 0) / (1024.0 * 1024.0)

	# Delta = descarga chica: pre-bajarla en background ya, para que el clic de
	# confirmación aplique al instante (la barra solo se muestra al confirmar). Solo en
	# plataformas que hacen hot-swap local (no web/iOS, que delegan a shell/store).
	var platform = OS.get_name()
	if _is_delta_update and platform != "HTML5" and platform != "iOS" and platform != "Android":
		if UpdateManager.get_status() == "available":
			UpdateManager.begin_update()

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
	modal_dim.show()
	if severity == "security_critical":
		close_button.text = "Salir"
		if get_tree().current_scene and get_tree().current_scene.filename != "res://scenes/Menu.tscn":
			var persistence = get_node_or_null("/root/PersistenceManager")
			if persistence:
				print("[VersionNotification] Critical update: saving state...")
				persistence.save_checkpoint_resource(get_tree().current_scene.filename)
	else:
		close_button.text = "Cerrar"
		close_button.show()

	if not get_tree().paused:
		_we_paused = true
		get_tree().paused = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_update_action_button_text()

# Un solo botón que confirma TODO el flujo. El texto refleja la acción única que el
# clic dispara según plataforma; tras confirmar, la descarga+aplicación es automática.
func _update_action_button_text():
	var platform = OS.get_name()
	if platform == "Android":
		action_button.text = "Abrir instalador"
	elif platform == "HTML5":
		action_button.text = "Actualizar ahora"
	elif platform == "iOS":
		action_button.text = "Ver en App Store"
	else:
		# Desktop: un clic descarga (si falta) y reinicia para aplicar, sin más pasos.
		action_button.text = "Actualizar y reiniciar"

# Un único clic = confirmación total. Marca _user_confirmed para que, en cuanto la
# descarga termine (update_ready), se aplique automáticamente sin un segundo clic.
func _on_action_pressed():
	var platform = OS.get_name()
	if platform == "iOS":
		var url = _current_update_info.get("downloads_page", "")
		if url != "":
			OS.shell_open(url)
		return

	_user_confirmed = true
	action_button.disabled = true
	download_progress.value = 0
	download_progress.show()

	var status = UpdateManager.get_status()
	if status == "ready_to_restart":
		# Ya descargado (delta pre-bajado o full ya listo): aplicar de inmediato.
		_apply_now()
	elif status == "available":
		# Aún no se descargó (full, o delta que no alcanzó a pre-bajar): iniciar. Al
		# terminar, _on_update_ready aplicará solo porque _user_confirmed está activo.
		UpdateManager.begin_update()
	# Si ya está "downloading"/"verifying" (delta pre-bajándose), no hacemos nada:
	# _on_update_ready aplicará al completarse.

# Aplica el update ya descargado (reinicio en desktop, navegación en web).
func _apply_now():
	UpdateManager.request_restart()

func _on_update_progress(downloaded, total):
	# Mientras el usuario no haya confirmado (p.ej. delta pre-descargándose en
	# background), no mostramos la barra para no distraer; aparece al confirmar.
	if not _user_confirmed:
		return
	download_progress.show()
	if total > 0:
		download_progress.value = (float(downloaded) / total) * 100

func _on_update_ready(_info):
	download_progress.value = 100
	# Si el usuario ya confirmó, aplicar automáticamente (sin segundo clic). Si no
	# (delta pre-bajado en background antes de confirmar), dejamos el botón listo para
	# que su clic aplique al instante.
	if _user_confirmed:
		_apply_now()
	else:
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
		modal_dim.hide()
		_resume_if_we_paused()
		if _current_update_info.get("severity") == "optional":
			_dismissed_manifest_id = _current_update_info.get("manifest_id", "")

func _resume_if_we_paused():
	if _we_paused:
		_we_paused = false
		get_tree().paused = false

# --- API pública para reabrir el diálogo desde Opciones ---

# True si hay un update conocido (disponible o descargado) para mostrar. Lo usa el
# menú de Opciones para decidir si ofrecer el botón "Ver actualización".
func has_pending_update() -> bool:
	if _current_update_info.empty():
		return false
	var st = UpdateManager.get_status()
	return st == "available" or st == "downloading" or st == "verifying" or st == "ready_to_restart"

# Reabre el diálogo de update que el usuario había descartado (desde Opciones). Limpia
# el dismiss para que vuelva a verse y reusa la info ya conocida.
func reopen_update_dialog() -> void:
	if _current_update_info.empty():
		return
	_dismissed_manifest_id = ""
	_on_update_available(_current_update_info)

func _on_release_notes_pressed():
	if _release_notes_url != "":
		OS.shell_open(_release_notes_url)
