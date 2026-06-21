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

	var remote_ver = info.get("version", "v?.?.?")
	var local_ver = "v0.0.0"
	var constants = get_node_or_null("/root/Constants")
	if constants:
		local_ver = constants.get("GAME_VERSION")

	label.text = "Actualización %s disponible (Local: %s)" % [remote_ver, local_ver]

	var channel = info.get("channel", "unknown")
	var artifact = UpdateManager.get_selected_artifact(info)
	var type = "Completo"
	if artifact.get("is_delta", false):
		type = "Delta"

	var size_mb = artifact.get("size", 0) / (1024.0 * 1024.0)
	metadata_label.text = "Canal: %s | Tipo: %s | Tamaño: %.1f MB" % [channel, type, size_mb]

	release_notes_button.visible = _release_notes_url != ""

	_setup_severity_ui(severity)
	panel.show()

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
