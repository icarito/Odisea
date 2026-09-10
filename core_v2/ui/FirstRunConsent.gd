extends ColorRect

# FD-292 / FD-290. Pantalla de primera partida: pide el consentimiento de telemetria
# mientras el juego compila los shaders de la primera escena.
#
# El orden no es cosmetico. Un arranque en frio de Dome_Intro paga alrededor de
# noventa programas GLES3 de a uno, y ese costo hay que pagarlo igual; lo unico que
# se elige es si el jugador lo mira como una pantalla congelada o como el rato en que
# lee de que se trata la telemetria. Por eso la barra que avanza abajo es real: sale
# de la cola del warmup (ShaderCacheManager.progress), no de un temporizador. Si la
# maquina es rapida, el texto se lee igual y los botones aparecen enseguida.
#
# Los dos botones aparecen JUNTOS y recien al 100%. Ninguno viene preseleccionado:
# la espera sirve para que la decision se tome leyendo, no para empujarla.

signal consent_completed(accepted)

const PRIVACY_URL := "https://odisea.educa.juegos/privacidad"

# Cuanto del recorrido de la barra ocupa cada mitad. La precarga de la escena termina
# mucho antes que el warmup, asi que se lleva la porcion chica.
const PRELOAD_SHARE := 0.25

export(String) var target_scene_path := ""

onready var _intro_panel: Control = find_node("IntroPanel")
onready var _telemetry_panel: Control = find_node("TelemetryPanel")
onready var _ok_button: Button = find_node("OkButton")
onready var _accept_button: Button = find_node("AcceptButton")
onready var _decline_button: Button = find_node("DeclineButton")
onready var _privacy_link: Button = find_node("PrivacyLinkButton")
onready var _progress: ProgressBar = find_node("Progress")
onready var _progress_label: Label = find_node("ProgressLabel")
onready var _choice_box: Control = find_node("ChoiceBox")

var _warm_done := 0
var _warm_total := 0
var _warm_finished := false
var _ready_announced := false

func _ready() -> void:
	_telemetry_panel.visible = false
	_choice_box.visible = false
	set_process(false)

	_ok_button.connect("pressed", self, "_on_ok_pressed")
	_accept_button.connect("pressed", self, "_on_choice", [true])
	_decline_button.connect("pressed", self, "_on_choice", [false])
	if _privacy_link:
		_privacy_link.connect("pressed", self, "_on_privacy_link_pressed")

	var warm = get_node_or_null("/root/ShaderCacheManager")
	if warm:
		if warm.has_signal("progress"):
			warm.connect("progress", self, "_on_warm_progress")
		if warm.has_signal("compiled"):
			warm.connect("compiled", self, "_on_warm_compiled")

	_ok_button.grab_focus()

func _on_ok_pressed() -> void:
	_intro_panel.visible = false
	_telemetry_panel.visible = true
	_progress.value = 0.0
	# Recien ahora se compila. Antes de este punto el Menu esta a la vista y un lote
	# de compilacion se veria como un tiron; a partir de aca esta pantalla lo tapa y
	# el rato tiene una barra que lo explica.
	var menu = get_parent()
	if menu and menu.has_method("begin_shader_warmup"):
		menu.begin_shader_warmup()
	set_process(true)
	_refresh_progress()

func _process(_delta: float) -> void:
	_refresh_progress()

func _refresh_progress() -> void:
	var preload_done := 1.0
	var sm = get_node_or_null("/root/SceneManager")
	if sm and target_scene_path != "" and sm.has_method("is_scene_preloading"):
		if sm.is_scene_preloading(target_scene_path):
			preload_done = 0.0

	var warm_done := 1.0
	if not _warm_finished:
		warm_done = float(_warm_done) / float(_warm_total) if _warm_total > 0 else 0.0

	var total: float = preload_done * PRELOAD_SHARE + warm_done * (1.0 - PRELOAD_SHARE)
	_progress.value = clamp(total, 0.0, 1.0) * 100.0

	if total >= 1.0 and not _ready_announced:
		_announce_ready()

func _on_warm_progress(done: int, total: int) -> void:
	_warm_done = done
	_warm_total = total

func _on_warm_compiled(_cache_path) -> void:
	_warm_finished = true

func _announce_ready() -> void:
	_ready_announced = true
	set_process(false)
	_progress.value = 100.0
	if _progress_label:
		_progress_label.text = "Listo."
	_choice_box.visible = true
	# A proposito sin grab_focus(): que ninguno de los dos arranque preseleccionado.

func _on_choice(accepted: bool) -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.telemetry_enabled = accepted
		sm.error_reports_enabled = accepted
		sm.consent_asked = true
		sm.save_settings()
		sm.apply_privacy_settings()
	emit_signal("consent_completed", accepted)
	queue_free()

func _on_privacy_link_pressed() -> void:
	OS.shell_open(PRIVACY_URL)
