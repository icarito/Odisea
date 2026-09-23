extends Control

const VirtualMouse = preload("res://core_v2/ui/VirtualMouse.gd")
const FIRST_GAME_SCENE := "res://core_v2/levels/RingHub_Level.tscn"
const MENU_BGM := "Tin Cosmos"
# RingHub no tiene BGMZoneV2, asi que este crossfade es la unica musica del arranque: queda
# sonando la entrada al nivel en vez de cortarse.
const FIRST_GAME_BGM := "Elias... wake"
# Warmup de shaders por escena: el cache a usar si la escena de arranque tiene uno horneado.
# RingHub ya lo tiene, asi que en Android/HTML5 se precalienta en el Menu.
const FIRST_GAME_SHADER_CACHE := {
	"res://core_v2/levels/interiors/Dome_Intro.tscn": "res://core_v2/levels/shader_cache/DomeIntroShaderCache.tscn",
	"res://core_v2/levels/RingHub_Level.tscn": "res://core_v2/levels/shader_cache/RingHubShaderCache.tscn",
}

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
# estado -> [estilo dorado, estilo gris] del boton de control remoto
var _remote_styles: Dictionary = {}

func _ready():
	VirtualMouse.attach_to(self)
	var audio_mgr = get_node_or_null("/root/AudioManager")
	if audio_mgr:
		audio_mgr.crossfade_to_song(MENU_BGM, 1.0, 0.0, false)
	# El cursor nativo no se muestra: arranca oculto y el virtual aparece al mover el mouse
	# (VirtualMouse, modo desktop). Con gamepad el virtual lo maneja el stick.
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	# Volver desde una partida puede dejar el modo HUD o los widgets vivos (el overlay y el
	# SuitOSWidgetHost cuelgan de autoloads, no del nivel): se limpian al entrar al menu.
	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os != null and suit_os.has_method("close_hud_mode"):
		suit_os.close_hud_mode()
	# Por SuitOS, no por path: el path se rompe en silencio si el nodo se renombra.
	var host = suit_os.get_widget_host() if suit_os != null and suit_os.has_method("get_widget_host") else null
	if host != null and host.has_method("refresh_visibility"):
		host.refresh_visibility()

	# FD-228: Confirm stable boot for UpdateManager
	if get_node_or_null("/root/UpdateManager"):
		get_node("/root/UpdateManager").confirm_boot()

	# Dev on-device: entrar directo al nivel sin input. Permite medir el frame de
	# gameplay real en un build release (sin replay y sin engine debug), que es lo
	# que necesita el plan low-end para comparar tasas de fisica con FRT_PERF.
	if OS.get_environment("ODISEA_AUTOSTART_GAME") != "":
		call_deferred("_start_game", FIRST_GAME_SCENE)

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

	# Fade in al cargar. Mientras dura, el fundido se traga clics y toques y ningun boton
	# tiene foco: el cambio de escena que trae hasta aca (OK de "Salir" del control remoto,
	# Menu principal de la pausa) carga sincronico, y el toque impaciente que el jugador
	# repite durante esa carga llega recien ahora, justo sobre NUEVA PARTIDA.
	fade_rect.modulate.a = 1.0
	fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	tween.interpolate_property(fade_rect, "modulate:a", 1.0, 0.0, 1.0, Tween.TRANS_LINEAR, Tween.EASE_IN)
	tween.connect("tween_all_completed", self, "_on_fade_in_complete", [], CONNECT_ONESHOT)
	tween.start()

	call_deferred("_request_first_scene_preload")
	call_deferred("_spawn_shader_warmup")

	# El menu principal se dibuja a resolucion completa: a render_scale < 1 (default 0.75 del
	# tier LOW) el texto queda ilegible en 640x480. Mismo mecanismo que Opciones/modo HUD.
	connect("visibility_changed", self, "_hold_full_resolution")
	_hold_full_resolution()

func _hold_full_resolution() -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm and sm.has_method("hold_full_resolution_ui"):
		sm.hold_full_resolution_ui(self, is_visible_in_tree())

func _on_fade_in_complete() -> void:
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_focus_default_button()
	# El warmup de shaders NO arranca aca: compilar traba el hilo principal de a lotes y
	# con el Menu interactivo a la vista se lee como un cuelgue. Lo dispara el arranque
	# de partida, ya con una pantalla opaca encima: el consentimiento de primera vez, o
	# el fundido de salida (ver _wait_shader_warmup).

func _focus_default_button() -> void:
	if continue_button.visible and not continue_button.disabled:
		continue_button.grab_focus()
	else:
		new_game_button.grab_focus()

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
	var cache_path: String = String(FIRST_GAME_SHADER_CACHE.get(FIRST_GAME_SCENE, ""))
	if cache_path == "":
		return # la escena de arranque no tiene cache horneado: no compilar la de otra
	var trigger := preload("res://core_v2/levels/ShaderWarmupTrigger.gd").new()
	trigger.name = "DomeIntroShaderWarmup"
	trigger.shader_cache_scene_path = cache_path
	trigger.wait_for_startup_gate = true
	trigger.wait_preload_conflict = true
	# Armado, no arrancado. Compilar traba el hilo principal de a lotes, y hacerlo con
	# el Menu a la vista congela el fundido de salida a mitad de camino. Lo dispara
	# quien ya tenga una pantalla encima: la de consentimiento, o el fin del fundido.
	trigger.autostart = false
	add_child(trigger)

# Enciende la compilacion asincronica. Antes de este punto -- arranque y menu -- el
# ubershader no cubre nada y solo cuesta: medido en un Redmi Note 9 Pro, 26
# ubershaders a ~0.8 s cada uno antes de que el menu llegue a aparecer. Con el async
# dormido ese mismo arranque son 1.4 s.
# En modo sincrono (shader_compilation_mode 0) no hay cola async que encender, y pedirlo
# leia un entero sin inicializar: config.async_compilation_max_simultaneous sale de
# initialize() SOLO cuando el modo es >= 1. No era la causa del "index out of bounds" del
# web (se probo: con este guard puesto el trap persiste), pero es UB igual y el arreglo de
# fondo esta en el fork desde godot-box3d-3 73b056d.
func enable_async_shader_compilation() -> void:
	if int(ProjectSettings.get_setting("rendering/gles3/shaders/shader_compilation_mode")) < 1:
		return
	if VisualServer.has_method("set_shader_async_compilation_enabled"):
		VisualServer.set_shader_async_compilation_enabled(true)

# El warmup va aparte porque tiene un requisito que el encendido no tiene: ShaderCache
# cuelga su escena de la camara activa, asi que solo funciona mientras el Menu sigue en
# pie. Por eso lo dispara quien ya tenga una pantalla opaca encima y todavia no haya
# cambiado de escena: la pantalla de consentimiento (que espera a que termine antes de
# activar su boton CONTINUAR) o el fundido de salida, en _on_fade_out_complete.
# Idempotente: si el warmup ya termino (o el trigger se libero) vuelve en el acto, asi que
# los dos llamadores pueden pedirlo sin coordinarse.
func _wait_shader_warmup() -> void:
	enable_async_shader_compilation()
	var trigger = get_node_or_null("DomeIntroShaderWarmup")
	if trigger != null and trigger.has_method("begin"):
		trigger.begin()
		# Mientras corre, el trigger pide el cursor en reloj de arena (push_busy_global).
	# Y se le avisa al SceneManager que la transicion sigue viva: el watchdog cuenta
	# desde que arranco y sin esto resetea la carga (quedaba en "Preparando el primer
	# nivel..." para siempre). keep_transition_alive() es no-op fuera de una transicion.
	while is_instance_valid(trigger) and not trigger.is_finished():
		var scene_manager = get_node_or_null("/root/SceneManager")
		if scene_manager and scene_manager.has_method("keep_transition_alive"):
			scene_manager.keep_transition_alive()
		yield(get_tree(), "idle_frame")
	# Cede un frame siempre, incluso sin trigger (desktop): asi la funcion es corrutina
	# en todos los caminos y quien hace yield(_wait_shader_warmup(), "completed") nunca
	# cae en yield(null, ...).
	yield(get_tree(), "idle_frame")

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
	if not remote_control_button:
		return
	if rcm == null or rcm.discovery == null:
		remote_control_button.hide()
		return
	# El boton se ve gris mientras no hay ninguna partida anunciandose en la red, y toma
	# su dorado cuando aparece una. Nunca se deshabilita: tocarlo sin partidas muestra
	# la explicacion de que hace falta otro dispositivo en la misma wifi.
	for state in ["normal", "hover", "pressed"]:
		var gold: StyleBoxFlat = remote_control_button.get_stylebox(state)
		_remote_styles[state] = [gold, _grayscale(gold)]
	_set_remote_host_found(false)
	# El Menu escucha la red mientras esta abierto (no solo con el panel del control
	# remoto a la vista); lo apaga en _exit_tree.
	if rcm and rcm.discovery:
		rcm.discovery.connect("sessions_updated", self, "_on_remote_sessions_updated")
		rcm.discovery.start_discovery()
		_set_remote_host_found(not rcm.discovery.discovered_sessions.empty())

func _exit_tree() -> void:
	var rcm = get_node_or_null("/root/RemoteControlManager")
	if rcm and rcm.discovery:
		rcm.discovery.stop_discovery()
	# Suelta la resolucion completa del menu: en el nivel vuelve la escala de render.
	var sm = get_node_or_null("/root/SettingsManager")
	if sm and sm.has_method("hold_full_resolution_ui"):
		sm.hold_full_resolution_ui(self, false)

func _on_remote_sessions_updated(sessions: Dictionary) -> void:
	_set_remote_host_found(not sessions.empty())
	_try_resume_remote_session(sessions)

# Una sesion de control remoto que se cayo por falta de conexion se retoma sola cuando
# ese host vuelve a anunciarse: el host todavia reconoce el token, asi que no hay PIN.
func _try_resume_remote_session(sessions: Dictionary) -> void:
	var rcm = get_node_or_null("/root/RemoteControlManager")
	if not rcm or not rcm.client or _is_starting_game():
		return
	for session in sessions.values():
		if rcm.client.can_resume(session):
			if not rcm.client.is_connected("connection_restored", self, "_on_remote_session_resumed"):
				rcm.client.connect("connection_restored", self, "_on_remote_session_resumed", [], CONNECT_ONESHOT)
			rcm.client.resume_session(session)
			return

func _on_remote_session_resumed() -> void:
	if _is_starting_game():
		# El jugador eligio arrancar su propia partida mientras se retomaba: gana eso.
		get_node("/root/RemoteControlManager").client.disconnect_from_host()
		return
	get_tree().change_scene("res://core_v2/ui/RemoteControlHome.tscn")

# _begin_start_game y el consentimiento deshabilitan los botones al arrancar.
func _is_starting_game() -> bool:
	return new_game_button.disabled

func _set_remote_host_found(found: bool) -> void:
	for state in _remote_styles:
		remote_control_button.add_stylebox_override(state, _remote_styles[state][0 if found else 1])
	remote_control_button.hint_tooltip = tr("Control remoto: hay una partida en la red") if found else tr("Control remoto: no se detectan partidas en la red")

# Misma luminancia, sin tinte: el hover del gris sigue viendose mas claro que el reposo.
static func _grayscale(sb: StyleBoxFlat) -> StyleBoxFlat:
	var gray := sb.duplicate() as StyleBoxFlat
	for prop in ["bg_color", "border_color"]:
		var c: Color = sb.get(prop)
		var l: float = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
		gray.set(prop, Color(l, l, l, c.a))
	return gray

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
		menu.connect("closed", self, "_focus_default_button")
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
	if OS.has_feature("JavaScript") and Engine.has_singleton("JavaScript"):
		JavaScript.eval("window.OdiseaShell && window.OdiseaShell.hideNativeNotice && window.OdiseaShell.hideNativeNotice();", true)
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
	# Cuelga de la raiz, no del Menu: el Menu se libera a mitad de la carga y se
	# llevaria la pantalla puesta. El layer va por encima del 1000 de TransitionLayer
	# para que ni el fundido ni el cartel de carga asomen por debajo.
	var host := CanvasLayer.new()
	host.name = "FirstRunConsentLayer"
	host.layer = 2000
	host.add_child(screen)
	get_tree().root.add_child(host)
	screen.connect("loading_requested", self, "_on_first_run_loading_requested", [scene_path], CONNECT_ONESHOT)

# El jugador respondio el aviso (aceptar o rechazar): recien ahora se carga el nivel, con
# el panel de telemetria ("Preparando el primer nivel...") cubriendo el trabajo. El warmup de
# shaders corre ahi adentro, como pre_load_hook de goto_scene, asi no se paga dos veces ni se
# bloquea ninguna pantalla interactiva.
func _on_first_run_loading_requested(scene_path) -> void:
	enable_async_shader_compilation()
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
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager and scene_manager.has_method("goto_scene"):
		# Gameplay scenes are heavy to load. Show the same loading
		# screen + progress bar the BootLoader uses, otherwise the player stares at a
		# frozen black fade with no feedback during the long interactive load.
		# Cuando la pantalla de consentimiento esta arriba, ella ES el cartel de carga:
		# mostrar el de TransitionLayer por debajo solo apila dos barras que cuentan lo
		# mismo, y la de abajo asoma al final del fundido.
		var covered := is_instance_valid(get_tree().root.get_node_or_null("FirstRunConsentLayer"))
		var params := {
			"transition": "loading",
			"show_loading": not covered,
			"show_progress": not covered,
			"loading_message": "Cargando...",
			"fade_out": 0.0,
			"fade_in": 0.0 if covered else 3.0
		}
		# El warmup de shaders corre como pre_load_hook: SceneManager ya mostro la
		# pantalla de carga, la escena todavia no se intercambio (el Menu sigue vivo y
		# con camara), y ninguna UI interactiva aparecio aun. Solo para la escena de
		# arranque, que es la unica con cache horneado.
		if scene_path == FIRST_GAME_SCENE:
			params["pre_load_hook"] = funcref(self, "_wait_shader_warmup")
			# El fade-out/in automatico de SceneManager cortaria o reiniciaria el
			# crossfade a FIRST_GAME_BGM que ya arrancamos en _start_game(); dejarlo
			# vivir solo, la BGMZoneV2 del nivel lo toma sin corte al registrarse.
			params["skip_audio_fade"] = true
		scene_manager.goto_scene(scene_path, params)
	else:
		# Sin SceneManager no hay donde colgar el hook: se espera aca, con el fundido
		# ya terminado.
		if scene_path == FIRST_GAME_SCENE:
			yield(_wait_shader_warmup(), "completed")
		get_tree().change_scene(scene_path)
