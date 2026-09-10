extends ColorRect

# FD-292 / FD-290. Pantalla de primera partida: pide el consentimiento de telemetria
# mientras el primer nivel se carga de verdad.
#
# La barra sale de SceneManager.transition_progress, o sea de la carga real de la
# escena. Un intento anterior media el warmup de shaders en vez de eso, y el jugador
# terminaba esperando dos veces: la barra llegaba al final, aceptaba, y recien ahi el
# nivel empezaba su propia carga de casi cuarenta segundos. El warmup compila los
# ubershaders, pero lo que tarda al entrar son las variantes reales, que se compilan
# igual. Ahora la espera es una sola y es la que importa.
#
# Esta pantalla sobrevive al cambio de escena: cuelga de un CanvasLayer propio en la
# raiz, no del Menu, porque el Menu se libera a mitad de la carga.
#
# Los dos botones aparecen JUNTOS y recien al final. Ninguno viene preseleccionado.

signal consent_completed(accepted)
# Pedido de arrancar la carga del nivel: lo atiende el Menu, que es quien sabe como
# encadenar su fundido y el crossfade de musica.
signal loading_requested

const PRIVACY_URL := "https://odisea.educa.juegos/privacidad"

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

var _progress_01 := 0.0
var _transition_done := false
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

	var sm = get_node_or_null("/root/SceneManager")
	if sm:
		if sm.has_signal("transition_progress"):
			sm.connect("transition_progress", self, "_on_transition_progress")
		if sm.has_signal("transition_completed"):
			sm.connect("transition_completed", self, "_on_transition_completed")

	_ok_button.grab_focus()

func _on_ok_pressed() -> void:
	_intro_panel.visible = false
	_telemetry_panel.visible = true
	_progress.value = 0.0
	_ok_button.disabled = true
	# Recien ahora arranca la carga del nivel. Antes de este punto el Menu esta a la
	# vista y compilar shaders se veria como un tiron; a partir de aca esta pantalla
	# lo tapa entero.
	emit_signal("loading_requested")
	set_process(true)
	_refresh_progress()

func _process(_delta: float) -> void:
	_refresh_progress()

func _refresh_progress() -> void:
	var shown: float = 1.0 if _transition_done else _progress_01
	_progress.value = clamp(shown, 0.0, 1.0) * 100.0
	if _transition_done and not _ready_announced:
		_announce_ready()

func _on_transition_progress(path, progress) -> void:
	if target_scene_path != "" and String(path) != target_scene_path:
		return
	# La barra no retrocede: durante el swap el reporte puede saltar hacia atras y
	# eso se lee como si algo hubiera fallado.
	_progress_01 = max(_progress_01, float(progress))

func _on_transition_completed(path, _scene, _params) -> void:
	if target_scene_path != "" and String(path) != target_scene_path:
		return
	_transition_done = true

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
	# Liberar el CanvasLayer entero, no solo esta pantalla: al descubrirla, el nivel
	# ya esta cargado y dibujando detras.
	var host := get_parent()
	if host is CanvasLayer:
		host.queue_free()
	else:
		queue_free()

func _on_privacy_link_pressed() -> void:
	OS.shell_open(PRIVACY_URL)
