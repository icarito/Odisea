extends ColorRect

const VirtualMouse = preload("res://core_v2/ui/VirtualMouse.gd")

# FD-292 / FD-290. Pantalla de primera partida: protocolo, aviso de privacidad y la
# pregunta de consentimiento. El nivel NO arranca hasta que el jugador responde.
#
# Antes la carga del nivel empezaba al tocar CONTINUAR, detras del aviso. Eso tenia un
# costo que no se veia en la pantalla: el nivel cargaba con su gameplay vivo, y su
# terminal holografica entraba en modo foco y tomaba el mouse antes de que el jugador
# pudiera responder. El aviso es una pantalla propia y la carga recien arranca con la
# decision (aceptar o rechazar); a partir de ahi esta pantalla hace de cartel de carga.
#
# La barra sale de SceneManager.transition_progress, o sea de la carga real de la
# escena. El warmup compila los ubershaders, pero lo que tarda al entrar son las
# variantes reales, que se compilan igual: la espera es una sola y es la que importa.
#
# Esta pantalla sobrevive al cambio de escena: cuelga de un CanvasLayer propio en la
# raiz, no del Menu, porque el Menu se libera a mitad de la carga.
#
# Los dos botones aparecen JUNTOS. Ninguno viene preseleccionado.

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
# LinkButton, no Button: se dibuja como texto subrayado para que el enlace al aviso
# completo no compita visualmente con la decision que si hay que tomar.
onready var _privacy_link: BaseButton = find_node("PrivacyLinkButton")
onready var _progress: ProgressBar = find_node("Progress")
onready var _choice_box: Control = find_node("ChoiceBox")

var _progress_01 := 0.0
var _transition_done := false
var _screen_released := false

func _ready() -> void:
	# La carga del nivel puede correr con el arbol pausado por otros sistemas: esta
	# pantalla es el cartel de carga y tiene que seguir procesando igual.
	pause_mode = Node.PAUSE_MODE_PROCESS
	# El Menu puede desaparecer mientras esta pantalla permanece sobre la carga. Conserva el
	# cursor compartido como solicitado por esta UI, incluso despues de liberar el Menu.
	VirtualMouse.attach_popup(self)
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
	_ok_button.disabled = true
	# El aviso y la pregunta son una pantalla propia: el nivel NO arranca aca. Si
	# arrancara detras, su gameplay (la terminal holografica, la camara) tomaria el
	# mouse antes de que el jugador pudiera responder. La carga empieza recien con
	# la decision, en _on_choice.
	_progress.get_parent().visible = false
	_choice_box.visible = true
	_arm_choice()

func _process(_delta: float) -> void:
	_refresh_progress()

func _refresh_progress() -> void:
	var shown: float = 1.0 if _transition_done else _progress_01
	_progress.value = clamp(shown, 0.0, 1.0) * 100.0
	if _transition_done and not _screen_released:
		_release_when_loaded()

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

func _release_when_loaded() -> void:
	_screen_released = true
	set_process(false)
	# El nivel ya termino de cargar y dibuja detras: se libera el CanvasLayer entero,
	# no solo esta pantalla. A partir de aca el nivel es lo unico que queda a la vista.
	var host := get_parent()
	if host is CanvasLayer:
		host.queue_free()
	else:
		queue_free()

func _arm_choice() -> void:
	# Los botones nacen inertes y se arman medio segundo despues. Sin esta ventana, la
	# decision se registraba sola en el mismo instante en que aparecian: el clic que
	# acababa de responder el aviso alcanzaba al boton recien enfocado. Una eleccion de
	# privacidad que se contesta sin que nadie la conteste no vale nada.
	_accept_button.disabled = true
	_decline_button.disabled = true
	var tree := get_tree()
	if tree:
		yield(tree.create_timer(0.5), "timeout")
	if not is_instance_valid(self):
		return
	_accept_button.disabled = false
	_decline_button.disabled = false
	# Aceptar es la opcion por defecto: queda enfocada para que el mando o el teclado
	# la activen sin navegar. Rechazar esta al lado, del mismo tamaño y visible desde
	# el primer momento, asi que el atajo no esconde la alternativa.
	_accept_button.grab_focus()

func _on_choice(accepted: bool) -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.telemetry_enabled = accepted
		sm.error_reports_enabled = accepted
		sm.consent_asked = true
		sm.save_settings()
		sm.apply_privacy_settings()
	emit_signal("consent_completed", accepted)
	# Recien ahora arranca la carga del nivel: la decision de privacidad ya esta tomada.
	# Esta pantalla se queda como cartel de carga (opaca) hasta que el nivel este listo;
	# ahi _release_when_loaded libera el CanvasLayer entero.
	_choice_box.visible = false
	_progress.value = 0.0
	_progress.get_parent().visible = true
	set_process(true)
	emit_signal("loading_requested")

func _on_privacy_link_pressed() -> void:
	OS.shell_open(PRIVACY_URL)
