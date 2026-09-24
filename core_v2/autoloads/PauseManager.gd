extends Node

const VirtualMouseScript = preload("res://core_v2/ui/VirtualMouse.gd")

var pause_menu_scene_path = "res://core_v2/ui/PauseMenu.tscn"
var pause_menu_instance = null
var _uptime_frames: int = 0
var _menu_hidden_by_focus: bool = false
# FD-296 F3: el mundo esta pausado por el modo HUD, no por el menu. Mientras dure,
# ui_cancel (ESC/back) es del overlay del modo HUD y no abre ni cierra la pausa.
var _hud_mode_paused: bool = false
# Modo de mouse que habia antes de abrir el HUD. En modo HUD el puntero se OCULTA (HIDDEN), nunca
# se captura/centra: con el mundo pausado no hay mouse-look y dejar el grab rompe al salir de la
# ventana. Se restaura al cerrar.
var _mouse_mode_before_hud: int = -1
# Pausa rapida de Start (JOY_START): congela el mundo sin abrir el PauseMenu. Start de nuevo la
# levanta; Select sigue abriendo el menu completo.
var _quick_paused: bool = false
# Auto-hide del menu de pausa: si no hay movimiento, el menu se oculta y arranca la orbita
# pasiva de camara (T5). Mover el mouse/stick o tocar el mando lo vuelve a mostrar.
var _menu_idle_timer: float = 0.0
const PASSIVE_MENU_AUTOHIDE_SEC := 3.0
# Resume diferido: la orbita pasiva devuelve la camara a su vista determinista ANTES de
# despausar la fisica, para que el primer step no reescriba el rig desde otro lugar.
var _orbit_resume_pending: bool = false

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	get_tree().set_quit_on_go_back(false)

func _process(delta: float) -> void:
	if _uptime_frames < 120:
		_uptime_frames += 1
	_process_passive_menu_timeout(delta)

func _notification(what: int) -> void:
	# En Android el botón "back" envía WM_GO_BACK_REQUEST (sin evento de tecla). Se
	# traduce a ui_cancel para que haga lo mismo que Esc: cierra lo que esté abierto
	# (Opciones, control remoto, terminal, pausa) y en juego abre la pausa. Antes solo
	# alternaba la pausa, así que en el menú principal no cerraba Opciones.
	if what == MainLoop.NOTIFICATION_WM_GO_BACK_REQUEST:
		_send_ui_cancel()
	# Al perder el foco de la ventana (alt-tab, cambio de app, etc.) pausamos el
	# juego en vez de solo silenciar el audio. El AudioManager ya silencia con su
	# propio handler de foco; aquí detenemos la simulación. Mientras no haya foco el
	# menú se reduce a la etiqueta "PAUSA" (para poder tomar capturas limpias) y
	# vuelve completo con el primer input. No reanudamos solo con FOCUS_IN: el
	# jugador decide cuándo continuar desde el menú de pausa.
	elif what == MainLoop.NOTIFICATION_WM_FOCUS_OUT:
		_pause_on_focus_loss()
		# Gate de foco: sin ventana activa la orbita se congela (el spec la pide solo con foco).
		var cm = get_node_or_null("/root/CinematicManager")
		if cm and cm.has_method("pause_idle_orbit"):
			cm.pause_idle_orbit()
	# Al recuperar el foco, si seguimos en pausa pasiva (menu oculto) arranca la orbita.
	elif what == MainLoop.NOTIFICATION_WM_FOCUS_IN:
		_on_window_focus_gained()

func _send_ui_cancel() -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = "ui_cancel"
		ev.pressed = pressed
		Input.parse_input_event(ev)

func _can_pause_in_current_scene() -> bool:
	var current_scene = get_tree().current_scene
	if current_scene == null:
		return false
	var fname := String(current_scene.filename)
	# No pausar en el menú principal ni en el boot. Tampoco en la pantalla del control
	# remoto: ahí Esc es del juego controlado (se reenvía al host) y no hay nada que pausar.
	return fname.find("Menu.tscn") == -1 and fname.find("Boot.tscn") == -1 \
		and fname.find("RemoteControlHome.tscn") == -1

func _pause_on_focus_loss() -> void:
	if _uptime_frames < 120:
		return
	if _is_automated_run():
		return
	# Un replay es una reproducción, no una sesión jugable: perder el foco (alt-tab,
	# tomar capturas, mirar la terminal) no debe congelar el playback. El visor ya
	# silencia la telemetría y oculta el touch UI por su cuenta.
	if _is_replay_playback():
		return
	if not _can_pause_in_current_scene() or _hud_mode_paused:
		return
	if _controlled_from_this_machine():
		return
	# La solicitud ya pauso el mundo; el menu encima solo taparia el aviso.
	if _pairing_prompt_open():
		return
	_menu_hidden_by_focus = true
	if get_tree().paused:
		_apply_menu_visibility()
	else:
		pause()

# Con un control remoto emparejado en ESTA misma maquina, alternar entre la ventana del
# juego y la del control es parte de jugar: pausar al perder el foco estorba y no protege
# nada (el jugador sigue delante de la pantalla). Con el control en otro dispositivo la
# pausa se mantiene: ahi perder el foco si es irse.
func _controlled_from_this_machine() -> bool:
	var rcm = get_node_or_null("/root/RemoteControlManager")
	return rcm != null and rcm.has_method("has_local_remote_control") \
		and rcm.has_local_remote_control()

func _pairing_prompt_open() -> bool:
	var rcm = get_node_or_null("/root/RemoteControlManager")
	return rcm != null and rcm.has_method("is_pairing_prompt_open") and rcm.is_pairing_prompt_open()

func _apply_menu_visibility() -> void:
	if pause_menu_instance and pause_menu_instance.has_method("set_minimal"):
		pause_menu_instance.set_minimal(_menu_hidden_by_focus)

func _on_window_focus_gained() -> void:
	if get_tree().paused and _menu_hidden_by_focus:
		_start_passive_orbit()

# Pausa pasiva: menu visible y sin movimiento. Tras el timeout se oculta y arranca la orbita.
func _process_passive_menu_timeout(delta: float) -> void:
	if not get_tree().paused or _hud_mode_paused:
		_menu_idle_timer = 0.0
		return
	if _menu_hidden_by_focus:
		_menu_idle_timer = 0.0
		return
	_menu_idle_timer += delta
	if _menu_idle_timer >= PASSIVE_MENU_AUTOHIDE_SEC:
		_menu_idle_timer = 0.0
		_menu_hidden_by_focus = true
		_apply_menu_visibility()
		_start_passive_orbit()

func _get_player() -> Node:
	var players = get_tree().get_nodes_in_group("player")
	if players.empty():
		return null
	return players[0]

func _idle_orbit_available() -> bool:
	if _hud_mode_paused or not _menu_hidden_by_focus or not get_tree().paused:
		return false
	if _is_automated_run() or _is_replay_playback():
		return false
	return OS.is_window_focused()

func _start_passive_orbit() -> void:
	if not _idle_orbit_available():
		return
	var cm = get_node_or_null("/root/CinematicManager")
	if cm == null:
		return
	if cm.has_method("is_idle_orbit_active") and cm.is_idle_orbit_active():
		if cm.has_method("resume_idle_orbit"):
			cm.resume_idle_orbit()
		return
	if not cm.has_method("begin_idle_orbit"):
		return
	if cm.has_method("is_idle_orbit_return_active") and cm.is_idle_orbit_return_active():
		return
	var player = _get_player()
	if player == null:
		return
	cm.begin_idle_orbit(player)

# Muestra el menu y PAUSA la orbita en la pose actual (sin devolver la camara). Al ocultarse
# el menu, _start_passive_orbit la retoma desde donde estaba.
func _reveal_passive_menu() -> void:
	_menu_idle_timer = 0.0
	var cm = get_node_or_null("/root/CinematicManager")
	if cm and cm.has_method("pause_idle_orbit"):
		cm.pause_idle_orbit()
	if not _menu_hidden_by_focus:
		return
	_menu_hidden_by_focus = false
	_apply_menu_visibility()
	# El menu expandido si pide el cursor: recien ahora se libera/muestra. Entrar en pausa pasiva
	# con Start no lo hace (el menu minimal no es solicitante del cursor).
	VirtualMouseScript.set_pointer_released(true)

# Volver a la pausa pasiva desde el menu visible (clic fuera del panel): oculta el menu y
# retoma la orbita.
func enter_passive_pause_menu_hidden() -> void:
	if not get_tree().paused or _hud_mode_paused:
		return
	if _menu_hidden_by_focus:
		return
	_menu_hidden_by_focus = true
	_menu_idle_timer = 0.0
	_apply_menu_visibility()
	_start_passive_orbit()

# El menu oculto se revela con movimiento de mouse/stick o con cualquier boton del mando
# salvo Start (Start con el menu oculto reanuda, no revela).
func _is_menu_reveal_event(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		return true
	if event is InputEventJoypadMotion:
		return abs((event as InputEventJoypadMotion).axis_value) > 0.5
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		return jb.pressed and jb.button_index != JOY_START
	return false

# Select: alterna el puntero. Si esta liberado, lo RECAPTURA (captura el mouse y apaga el cursor
# virtual); si esta capturado, lo libera (cursor virtual, nunca el nativo). Nunca pausa ni
# despausa: la inhibicion del control del jugador la aplica el gate global de InputProviderV2
# (puntero liberado en gameplay) y al recapturar se levanta sola.
func _toggle_select_control() -> void:
	if VirtualMouseScript.is_pointer_released():
		VirtualMouseScript.set_pointer_released(false)
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		VirtualMouseScript.set_pointer_released(true)

func _restores_menu(event: InputEvent) -> bool:
	if event is InputEventKey or event is InputEventMouseButton \
			or event is InputEventJoypadButton or event is InputEventScreenTouch:
		return event.pressed
	return false

func _is_automated_run() -> bool:
	if OS.has_feature("Server"):
		return true
	if Engine.has_singleton("GdUnit3") and Engine.get_singleton("GdUnit3").is_test_suite():
		return true
	if OS.get_environment("ANNA_RL_MODE").to_lower() in ["1", "true", "yes", "on"]:
		return true
	return false

func _is_replay_playback() -> bool:
	var session = get_node_or_null("/root/SessionManager")
	if session == null:
		return false
	# JSON replay puro (is_replaying sin grabar) y playback de hotzone .bin.
	return (session.is_replaying and not session.is_recording) \
		or (("is_hotzone_playback" in session) and session.is_hotzone_playback)

func _input(event):
	if _hud_mode_paused:
		return
	# Con un aviso de emparejamiento abierto la pausa se hace a un lado: el primer clic al
	# volver el foco se lo comia para restaurar el menu (era el clic de "Permitir"), y Esc
	# abria el menu en vez de rechazar la solicitud.
	if _pairing_prompt_open():
		return
	# Start (JOY_START): SOLO alterna la pausa pasiva. Si el mundo esta pausado despausa
	# (cualquier pausa); si no, pausa pasiva. Nunca abre ni activa el menu completo. Va
	# primero y se consume siempre para que nada mas lo intercepte (ni la GUI con ui_accept).
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_START \
			and (event as InputEventJoypadButton).pressed:
		call_deferred("toggle_quick_pause")
		get_tree().set_input_as_handled()
		return
	# Cualquier input con el menu visible reinicia el temporizador de auto-hide.
	if get_tree().paused and not _menu_hidden_by_focus:
		_menu_idle_timer = 0.0
	# Select: alterna el puntero (libera/recaptura). Nunca pausa, nunca despausa, nunca revela el
	# menu; se consume siempre para que no llegue a la GUI ni a SessionManager.
	if event is InputEventJoypadButton \
			and (event as InputEventJoypadButton).button_index == JOY_SELECT \
			and (event as InputEventJoypadButton).pressed:
		if not get_tree().paused and not _hud_mode_paused and _can_pause_in_current_scene():
			_toggle_select_control()
		get_tree().set_input_as_handled()
		return
	# Boton derecho en pausa pasiva (menu oculto): despausa. Es el gesto de escritorio de
	# "volver al juego"; el clic izquierdo sigue su camino de siempre.
	if get_tree().paused and _menu_hidden_by_focus \
			and event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_RIGHT:
		resume()
		get_tree().set_input_as_handled()
		return
	# Pausa pasiva (menu oculto): mover mouse/stick o tocar el mando revela el menu y corta
	# la orbita. Start se maneja mas abajo (con el menu oculto reanuda, no revela).
	if get_tree().paused and _menu_hidden_by_focus and _is_menu_reveal_event(event):
		_reveal_passive_menu()
		get_tree().set_input_as_handled()
		return
	# Primer input tras recuperar el foco. Un clic sobre el juego en pausa es "volver a jugar":
	# reanuda. Cualquier otra entrada devuelve el menu completo, sin actuar.
	if _menu_hidden_by_focus and get_tree().paused and _restores_menu(event):
		if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
			resume()
		else:
			_reveal_passive_menu()
		get_tree().set_input_as_handled()
		return
	# Start (JOY_START) se maneja arriba, antes de todo.
	if not is_pause_request(event):
		return
	if not _can_pause_in_current_scene():
		return
	if get_tree().paused:
		call_deferred("_toggle_pause")
		get_tree().set_input_as_handled()
		return
	call_deferred("_toggle_pause")
	get_tree().set_input_as_handled()

# Pausar es ESC, el back de Android o el gamepad. El boton derecho del mouse tambien es
# ui_cancel en el InputMap, pero es "soltar el mouse" (lo hace SessionManager), no pausar.
# Select (JOY_SELECT) tambien es ui_cancel, pero en juego alterna el puntero (libera/recaptura) e
# inhibe el control del jugador: no pausa. Durante la pausa no hace nada (a lo sumo revela el menu).
static func is_pause_request(event: InputEvent) -> bool:
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_SELECT:
		return false
	return event.is_action_pressed("ui_cancel") and not event is InputEventMouseButton

func _toggle_pause() -> void:
	if not _can_pause_in_current_scene():
		return # No pausar en el menú principal ni en el boot

	if get_tree().paused:
		resume()
	else:
		# FD-234: Si no está pausado, pausar sin importar el modo del mouse.
		# Esto permite pausar si el mouse se liberó por otra UI o si el
		# jugador simplemente quiere pausar en cualquier momento.
		pause()

func pause():
	_quick_paused = false # el menu completo reemplaza la pausa rapida
	if pause_menu_instance == null:
		var scene = load(pause_menu_scene_path)
		if scene:
			pause_menu_instance = scene.instance()
			var canvas = CanvasLayer.new()
			canvas.layer = 50
			canvas.name = "PauseMenuLayer"
			get_tree().root.call_deferred("add_child", canvas)
			canvas.call_deferred("add_child", pause_menu_instance)
			# Defer the rest until the child is added
			call_deferred("_finish_pause")
			return
		else:
			printerr("[PauseManager] No se pudo cargar PauseMenu.tscn")
			return

	_finish_pause()

func _finish_pause() -> void:
	if pause_menu_instance == null:
		return
	get_tree().paused = true
	# El cursor nativo no se muestra: el PauseMenu cuelga un VirtualMouse que aparece al mover el
	# mouse (modo desktop) o con el stick.
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	pause_menu_instance.show()
	if pause_menu_instance.has_method("on_show"):
		pause_menu_instance.on_show()
	_apply_menu_visibility()
	_refresh_mobile_ui()
	var audio_mgr = get_node_or_null("/root/AudioManager")
	if audio_mgr and audio_mgr.has_method("set_music_paused_by_menu"):
		audio_mgr.set_music_paused_by_menu(true)
	_menu_idle_timer = 0.0
	_start_passive_orbit()

func resume():
	_menu_hidden_by_focus = false
	_quick_paused = false
	_menu_idle_timer = 0.0
	# Si hay una orbita pasiva corriendo, devolver la camara a la vista determinista ANTES de
	# despausar: el primer step de fisica reescribe el rig desde yaw/pitch.
	var cm = get_node_or_null("/root/CinematicManager")
	if cm and cm.has_method("is_idle_orbit_active") and cm.is_idle_orbit_active() \
			and cm.has_method("start_idle_orbit_return"):
		if not cm.is_connected("idle_orbit_return_finished", self, "_on_idle_orbit_return_finished"):
			cm.connect("idle_orbit_return_finished", self, "_on_idle_orbit_return_finished")
		_orbit_resume_pending = true
		cm.start_idle_orbit_return()
		return
	_apply_resume()

func _on_idle_orbit_return_finished() -> void:
	if not _orbit_resume_pending:
		return
	_orbit_resume_pending = false
	_apply_resume()

func _apply_resume() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Recapturar apaga el cursor virtual del puntero liberado (ui_cancel en gameplay).
	VirtualMouseScript.set_pointer_released(false)
	if pause_menu_instance:
		pause_menu_instance.hide()
	_refresh_mobile_ui()
	var audio_mgr = get_node_or_null("/root/AudioManager")
	if audio_mgr and audio_mgr.has_method("set_music_paused_by_menu"):
		audio_mgr.set_music_paused_by_menu(false)

# Start del mando: la MISMA pausa que al perder el foco de la ventana, o sea el PauseMenu
# reducido a la etiqueta "PAUSA" (revision 2026-09-19, Sebastian). Antes era una pausa
# invisible propia, sin ningun aviso en pantalla.
# Start de nuevo la cancela, este reducida o expandida: Start nunca entra al menu.
func toggle_quick_pause() -> void:
	if _hud_mode_paused:
		return
	# Cancelar no depende de la escena: si el mundo esta pausado, Start lo despausa y punto.
	# El chequeo de escena es para no PAUSAR en el menu principal ni en el boot, y ahi no
	# hay nada pausado que cancelar.
	if get_tree().paused:
		resume()
		return
	if not _can_pause_in_current_scene():
		return
	pause_quick()

func pause_quick() -> void:
	if get_tree().paused:
		return
	# El mismo camino que _pause_on_focus_loss: menu reducido a "PAUSA", sin oscurecer.
	_menu_hidden_by_focus = true
	pause()
	# pause() limpia _quick_paused (el menu completo lo reemplaza). Aca la pausa ES de
	# Start, asi que se vuelve a marcar despues.
	_quick_paused = true

func resume_quick() -> void:
	if not _quick_paused:
		return
	resume()

func is_quick_paused() -> bool:
	return _quick_paused

# El jugador solto el puntero (clic derecho/Esc): al salir del HUD no hay que recapturar.
func _virtual_mouse_released() -> bool:
	var script = preload("res://core_v2/ui/VirtualMouse.gd")
	return script != null and script.is_pointer_released()

# FD-296 F3: modo HUD. NO congela el mundo (el nivel sigue simulando detras de la
# pantalla, a proposito: la terminal/radial es una overlay, no una pausa) y sin tocar el
# mouse salvo ocultarlo: el radial lee el gesto con el mouse capturado. Devuelve false si
# no se puede abrir (menu/boot, o el juego ya esta pausado de verdad por otra cosa).
func pause_hud_mode() -> bool:
	if _hud_mode_paused or get_tree().paused or not _can_pause_in_current_scene():
		return false
	_hud_mode_paused = true
	# Solo ocultar el puntero: nada de capturarlo/centrarlo. El radial se apunta con el stick o el
	# mouse (que ahora sigue moviendose) y las pantallas usan el cursor virtual.
	if _mouse_mode_before_hud < 0:
		_mouse_mode_before_hud = Input.get_mouse_mode()
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	_refresh_mobile_ui()
	_set_music_paused_by_menu(true)
	return true

func resume_hud_mode() -> void:
	if not _hud_mode_paused:
		return
	_hud_mode_paused = false
	if _mouse_mode_before_hud >= 0:
		var restore: int = _mouse_mode_before_hud
		_mouse_mode_before_hud = -1
		# Si el jugador solto el puntero (clic derecho/Esc), NO se recaptura al salir del HUD.
		if _virtual_mouse_released():
			Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		else:
			# Nunca volver a VISIBLE: el cursor nativo no se muestra en gameplay.
			Input.set_mouse_mode(restore if restore != Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_CAPTURED)
	_refresh_mobile_ui()
	_set_music_paused_by_menu(false)

func is_hud_mode_paused() -> bool:
	return _hud_mode_paused

func _set_music_paused_by_menu(paused: bool) -> void:
	var audio_mgr = get_node_or_null("/root/AudioManager")
	if audio_mgr and audio_mgr.has_method("set_music_paused_by_menu"):
		audio_mgr.set_music_paused_by_menu(paused)

func _refresh_mobile_ui() -> void:
	# Show/hide the on-screen touch controls in sync with pause state. They live on
	# a high CanvasLayer and would intercept the touches meant for the pause menu.
	var mobile = get_node_or_null("/root/MobileUIManager")
	if mobile and mobile.has_method("refresh_for_pause"):
		mobile.refresh_for_pause()
	# Lo mismo para los widgets del HUD de SuitOS (capa 115, encima del menu de pausa).
	# Se le pide el host a SuitOS en vez de buscarlo por path: el path se rompe en silencio
	# si el nodo se renombra, y SuitOS ya es el duenio del host.
	var widget_host = _suit_os_widget_host()
	if widget_host and widget_host.has_method("refresh_visibility"):
		widget_host.refresh_visibility()

# El host de widgets de SuitOS, sin hardcodear su path en el arbol.
func _suit_os_widget_host() -> Node:
	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os == null or not suit_os.has_method("get_widget_host"):
		return null
	return suit_os.get_widget_host()
