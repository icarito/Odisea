extends Control

const FIRST_GAME_SCENE := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const MENU_BGM := "Tin Cosmos"
# Debe coincidir con el bgm_stream de BGMZoneV2 en Dome_Intro.tscn (mismo path
# res://assets/music/<nombre>) para que el crossfade arrancado aqui empalme sin corte
# cuando la zona real se registre al terminar de cargar el nivel.
const FIRST_GAME_BGM := "Elias... wake"

export var enable_touch_buttons := true

onready var fade_rect: ColorRect = $CanvasLayer/ColorRect
onready var tween: Tween = $Tween
onready var new_game_button = find_node("NewGame")
onready var continue_button = find_node("Continue")
onready var remote_control_button = find_node("RemoteControl")
onready var options_button = find_node("Options")
onready var quit_button = find_node("Quit")
onready var options_menu = $OptionsMenu
onready var version_label = get_node_or_null("VersionLabel")
var _continue_scene_path := ""

func _ready():
	var audio_mgr = get_node_or_null("/root/AudioManager")
	if audio_mgr:
		audio_mgr.crossfade_to_song(MENU_BGM, 1.0, 0.0, false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# FD-228: Confirm stable boot for UpdateManager
	if get_node_or_null("/root/UpdateManager"):
		get_node("/root/UpdateManager").confirm_boot()

	_check_save_game()
	_connect_signals()
	_setup_remote_control()
	_initialize_version_label()

	# Ni HTML5 ni iOS deben mostrar "salir": en la web no hay a donde salir, y en iOS
	# Apple desaconseja explicitamente que una app se cierre sola (ademas el boton no
	# funcionaba alla). Si se agrega otra plataforma sin cierre, va en esta lista y en
	# la gemela de PauseMenu.gd.
	if quit_button and OS.get_name() in ["HTML5", "iOS"]:
		quit_button.visible = false

	if continue_button.visible and not continue_button.disabled:
		continue_button.grab_focus()
	else:
		new_game_button.grab_focus()

	# Fade in al cargar
	fade_rect.modulate.a = 1.0
	tween.interpolate_property(fade_rect, "modulate:a", 1.0, 0.0, 1.0, Tween.TRANS_LINEAR, Tween.EASE_IN)
	tween.start()

	if enable_touch_buttons:
		var handler = $TouchCanvasLayer/TouchHandler
		var temp_buttons = []
		for b in [new_game_button, continue_button, options_button, quit_button]:
			if b and b.visible:
				temp_buttons.append(b)
		handler.buttons = temp_buttons
	call_deferred("_request_first_scene_preload")
	call_deferred("_spawn_shader_warmup")

# FD-290: warmup de shaders de la primera escena de juego mientras el jugador esta
# en el Menu. El trigger espera a que el preload de Dome_Intro termine (evita la
# carrera del load() sincronico) y recien ahi compila, de a lotes, en background.
# Con esto el primer draw del nivel no paga los ~90 programas GLES3 (medido en
# WebGL: ~27 s de stall hasta first_idle_frame sin warmup).
func _spawn_shader_warmup():
	if Engine.editor_hint:
		return
	# Android entra recien ahora. Hasta que el ubershader de escena dejo de exceder
	# el presupuesto de samplers del driver (Adreno rechazaba el link), precalentar
	# ahi solo habria compilado programas que fallaban. Con el ubershader enlazando,
	# el mismo stall que se midio en WebGL aparece en el celular: el arranque en frio
	# de Dome_Intro paga ~90 programas GLES3 de a uno.
	if not OS.get_name() in ["HTML5", "Android"]:
		return
	var trigger := preload("res://core_v2/levels/ShaderWarmupTrigger.gd").new()
	trigger.name = "DomeIntroShaderWarmup"
	trigger.shader_cache_scene_path = "res://core_v2/levels/shader_cache/DomeIntroShaderCache.tscn"
	trigger.wait_for_startup_gate = true
	trigger.wait_preload_conflict = true
	# Armado, no arrancado. Compilar traba el hilo principal de a lotes, y hacerlo con
	# el Menu a la vista congela el fundido de salida a mitad de camino. Lo dispara
	# quien ya tenga una pantalla encima: la de consentimiento, o el fin del fundido.
	trigger.autostart = false
	add_child(trigger)

func begin_shader_warmup() -> void:
	var trigger = get_node_or_null("DomeIntroShaderWarmup")
	if trigger and trigger.has_method("begin"):
		trigger.begin()

func _request_first_scene_preload() -> void:
	yield(get_tree(), "idle_frame")
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager and scene_manager.has_method("request_scene_preload"):
		scene_manager.request_scene_preload(FIRST_GAME_SCENE)

func _check_save_game():
	var persistence = get_node_or_null("/root/PersistenceManager")
	_continue_scene_path = persistence.get_continue_scene_path() if persistence and persistence.has_method("get_continue_scene_path") else ""
	continue_button.disabled = _continue_scene_path == ""

func _initialize_version_label():
	if version_label:
		var VersionLabelHelper = load("res://core_v2/ui/VersionLabel.gd")
		if VersionLabelHelper:
			version_label.text = VersionLabelHelper.get_formatted_version()

func _setup_remote_control():
	var rcm = get_node_or_null("/root/RemoteControlManager")
	if rcm:
		rcm.connect("pairing_prompt_requested", self, "_on_remote_pairing_prompt_requested")

func _on_remote_pairing_prompt_requested(device_name: String, pin: String, callback: FuncRef):
	var dialog_script = load("res://core_v2/ui/RemotePairingDialog.gd")
	if dialog_script:
		var dialog = load("res://core_v2/ui/RemotePairingDialog.tscn").instance()
		add_child(dialog)
		dialog.prompt_pairing(device_name, pin, callback)

func _connect_signals():
	new_game_button.connect("pressed", self, "_on_NewGame_pressed")
	continue_button.connect("pressed", self, "_on_Continue_pressed")
	if remote_control_button:
		remote_control_button.connect("pressed", self, "_on_RemoteControl_pressed")
	options_button.connect("pressed", self, "_on_Options_pressed")
	quit_button.connect("pressed", self, "_on_Quit_pressed")

func _on_RemoteControl_pressed():
	var packed = load("res://core_v2/ui/RemoteControlMenu.tscn")
	if packed:
		var menu = packed.instance()
		add_child(menu)
		menu.open_menu()

func _on_NewGame_pressed():
	_start_game(FIRST_GAME_SCENE)

func _on_Continue_pressed():
	if _continue_scene_path == "":
		return
	var persistence = get_node_or_null("/root/PersistenceManager")
	if not persistence or not persistence.has_method("request_continue") or not persistence.request_continue():
		_check_save_game()
		return
	_start_game(_continue_scene_path)

func _on_Options_pressed():
	options_menu.show()
	options_menu.on_show()

func _on_Quit_pressed():
	get_tree().quit()

func _start_game(scene_path):
	# FD-292: la primera vez, el consentimiento va ANTES del fundido, no al abrir el
	# menu. Dos razones. Una, se pregunta cuando el jugador ya decidio jugar, que es
	# cuando la pregunta viene al caso. Dos, el arranque en frio del primer nivel
	# compila alrededor de noventa programas GLES3 de a uno; ese rato existe igual, y
	# asi se gasta leyendo en vez de mirando una barra sola.
	var sm = get_node_or_null("/root/SettingsManager")
	if sm and sm.has_method("needs_privacy_consent") and sm.needs_privacy_consent():
		_show_first_run_consent(scene_path)
		return
	_begin_start_game(scene_path)

func _show_first_run_consent(scene_path) -> void:
	for b in [new_game_button, continue_button, options_button, quit_button]:
		if b:
			b.disabled = true
	var packed = load("res://core_v2/ui/FirstRunConsent.tscn")
	if packed == null:
		# Sin la pantalla no hay forma de preguntar; arrancar igual y dejar la
		# telemetria apagada, que es el lado seguro de no haber preguntado.
		printerr("[Menu] No se pudo cargar FirstRunConsent.tscn; se arranca sin preguntar.")
		_begin_start_game(scene_path)
		return
	var screen = packed.instance()
	screen.target_scene_path = String(scene_path)
	screen.connect("consent_completed", self, "_on_first_run_consent_done", [scene_path], CONNECT_ONESHOT)
	add_child(screen)

func _on_first_run_consent_done(_accepted: bool, scene_path) -> void:
	_begin_start_game(scene_path)

func _begin_start_game(scene_path):
	# La pantalla de carga NO se muestra aca. El overlay vive en layer 1000, encima
	# del fundido del menu, y su texto y su barra son opacos: revelarlos en el frame
	# del click los pega sobre el menu todavia visible durante los 0.85 s que dura el
	# fade de abajo. Se revela al terminar ese fade, que es cuando la pantalla ya esta
	# negra -- lo hace goto_scene() en _on_fade_out_complete(), que pide show_loading.
	# El click igual se siente atendido: los botones se deshabilitan y el fundido
	# arranca en el mismo frame. (Y si el hilo principal se bloquea cargando la BGM,
	# una barra tampoco se animaria: el bloqueo se lleva el frame entero.)
	# Avoid double-triggering if a button is pressed twice during the fade.
	for b in [new_game_button, continue_button, options_button, quit_button]:
		if b:
			b.disabled = true
	tween.stop_all()
	tween.interpolate_property(fade_rect, "modulate:a", fade_rect.modulate.a, 1.0, 0.85, Tween.TRANS_QUAD, Tween.EASE_IN)
	tween.start()
	if not tween.is_connected("tween_completed", self, "_on_fade_out_complete"):
		tween.connect("tween_completed", self, "_on_fade_out_complete", [scene_path], CONNECT_ONESHOT)
	# Si el destino es el nivel inicial, arrancar ya su musica (crossfade sin fijar
	# override) para que vaya sonando durante la pantalla de carga en vez de esperar a
	# que la BGMZoneV2 del nivel se registre. Otros destinos (Continue a mitad de
	# partida) dejan que SceneManager haga su fade-out/in por defecto y que la propia
	# zona decida la musica al cargar.
	if scene_path == FIRST_GAME_SCENE:
		_start_first_game_bgm()

# crossfade_to_song() hace un load() sincronico del mp3 (AudioManager.gd): la
# primera vez cuesta cientos de ms y caia justo en el frame del click. Un frame
# despues, con el fundido del menu ya en marcha, ese mismo costo no se ve.
func _start_first_game_bgm() -> void:
	yield(get_tree(), "idle_frame")
	var audio_mgr = get_node_or_null("/root/AudioManager")
	if audio_mgr:
		audio_mgr.crossfade_to_song(FIRST_GAME_BGM, 2.0, 0.0, false)

func _on_fade_out_complete(_object, _key, scene_path):
	# Pantalla ya cubierta: desde aca un lote de compilacion no se ve como un tiron.
	begin_shader_warmup()
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager and scene_manager.has_method("goto_scene"):
		# Gameplay scenes are heavy to load. Show the same loading
		# screen + progress bar the BootLoader uses, otherwise the player stares at a
		# frozen black fade with no feedback during the long interactive load.
		var params := {
			"transition": "loading",
			"show_loading": true,
			"show_progress": true,
			"loading_message": "Cargando...",
			"fade_out": 0.0,
			"fade_in": 3.0
		}
		if scene_path == FIRST_GAME_SCENE:
			# El fade-out/in automatico de SceneManager cortaria o reiniciaria el
			# crossfade a FIRST_GAME_BGM que ya arrancamos en _start_game(); dejarlo
			# vivir solo, la BGMZoneV2 del nivel lo toma sin corte al registrarse.
			params["skip_audio_fade"] = true
		scene_manager.goto_scene(scene_path, params)
	else:
		get_tree().change_scene(scene_path)
