extends Node

# RemoteControlManager.gd - Autoload coordinator for ODISEA Remote Control subsystem.

signal remote_input_received(input_type, payload)
signal pairing_prompt_requested(device_name, pin, callback)

var RemoteAnnouncer = load("res://core_v2/net/RemoteAnnouncer.gd")
var RemoteDiscovery = load("res://core_v2/net/RemoteDiscovery.gd")
var RemoteControlServer = load("res://core_v2/net/RemoteControlServer.gd")
var RemoteControlClient = load("res://core_v2/net/RemoteControlClient.gd")
var RemoteProtocol = load("res://core_v2/net/RemoteProtocol.gd")
var SuitOSRemoteBridge = load("res://core_v2/components/SuitOSRemoteBridge.gd")
var RemoteSimHost = load("res://core_v2/net/RemoteSimHost.gd")
var RemoteSimClient = load("res://core_v2/net/RemoteSimClient.gd")

var announcer: Node = null
var discovery: Node = null
var server: Node = null
var client: Node = null
var bridge: Node = null
var sim_host: Node = null
var sim_client: Node = null

var is_host_active: bool = false
var allow_low_tier_offload: bool = false
var is_sim_host_active: bool = false
var is_render_slave_active: bool = false
var remote_control_enabled: bool = true
var _paused_for_pairing: bool = false
var _mouse_mode_before_pairing: int = Input.MOUSE_MODE_VISIBLE
# id -> payload de soltar, por cada tecla/boton/eje que el control remoto dejo apretado.
# Si el control se desconecta o pierde el foco sin mandar el key-up, el host se quedaria
# con la tecla pegada (el jugador corriendo solo).
var _remote_held: Dictionary = {}
# Ultimo estado de pausa avisado a los controles; -1 fuerza reenviarlo.
var _sent_paused: int = -1
# FD-316 (review bug 5): ultimo estado de pausa del esclavo avisado a la autoridad; -1
# fuerza reenviarlo al activar el rol.
var _sent_sim_paused: int = -1
# FD-316 (review bug 7): si start_render_slave falla (puerto sim ocupado) no hay rol y no
# se martilla el bind cada frame: se reintenta recien pasado este plazo.
const RENDER_SLAVE_START_RETRY_MSEC := 2000
var _render_slave_retry_at_ms: int = 0
# FD-316 (tarea F): guard de foco del sim host. Con la ventana oculta u ocluida, un
# compositor con vsync puede bloquear el swap y bajar el loop a ~1 fps; como la fisica
# corre por frames, la simulacion que ve el render-esclavo se arrastra. Mientras seamos
# sim host (o quede su nivel conservado) y la ventana no tenga foco se apaga vsync y se
# fija target_fps al ritmo de fisica; al recuperar el foco o terminar el rol se restaura
# el valor previo. Ver is_sim_host_holding_simulation / update_sim_host_focus_guard.
var _sim_host_focus_guard_active: bool = false
var _sim_host_saved_vsync: bool = true
var _sim_host_saved_target_fps: int = 0
var _sim_host_saved_low_proc: bool = false
# Seam de test: -1 = consultar OS, 0 = sin foco, 1 = con foco. En produccion siempre -1.
var _sim_host_focus_override: int = -1
# El aviso de emparejamiento va por encima del menu de pausa (CanvasLayer 50): si la ventana
# perdio el foco mientras llegaba la solicitud, al volver el menu lo tapaba y no se podia
# aceptar. Ver tambien PauseManager, que se hace a un lado mientras este abierto.
const PAIRING_DIALOG_LAYER := 60
var _pairing_dialog: Node = null
# FD-316: en tier LOW (handheld/flat) el anuncio UDP es lo que habilita el
# emparejamiento y el offload, asi que ya no se omite; pero no queremos pagar el
# broadcast cada 2 s en un SoC lento, asi que se anuncia con menos frecuencia.
const LOW_TIER_BROADCAST_INTERVAL := 4.0
# FD-316: true cuando el ciclo completo de offload esta hecho y testado: handshake
# (sim_hello con escena/semilla/spawn), carga del nivel en el sim host sin reemplazar
# la UI del control, emision recien en sim_ready, engagement del esclavo con el
# primer snapshot y salida limpia al desemparejar. Ver el FD, "Decision de
# implementacion". La validacion en vivo (Anbernic + control) queda en el reporte.
const RENDER_SLAVE_OFFLOAD_READY := true

# FD-316 (tareas K2/K3): un solo dueno de la camara. Mientras el rol de render-esclavo esta
# activo, la vista la impone el snapshot de la autoridad: ninguna logica local (terminales,
# cinematicas) debe pedir ni soltar camaras por su cuenta, porque pelea con la vista
# replicada (el sintoma era el ida y vuelta de foco del terminal en el handheld). Punto
# unico de consulta para no dispersar el guard; estatico para que lo usen nodos que no
# tienen por que depender del autoload instanciado.
static func render_slave_owns_camera() -> bool:
	var loop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return false
	var root = (loop as SceneTree).root
	if root == null:
		return false
	var manager = root.get_node_or_null("RemoteControlManager")
	if manager == null:
		return false
	if bool(manager.get("is_render_slave_active")):
		return true
	# FD-316 (tarea K3): ventana de armado del offload. En tier LOW con un control
	# emparejado ESTE device ya no es dueno de la camara, aunque el canal de snapshots
	# todavia no haya arrancado (p. ej. el bind del puerto sim esta en reintento): en esa
	# ventana el terminal local se colaba a foco y despues el snapshot le peleaba la vista.
	if not bool(manager.get("allow_low_tier_offload")):
		return false
	var server = manager.get("server")
	if server == null or not is_instance_valid(server) or not server.has_method("has_paired_client"):
		return false
	return bool(server.call("has_paired_client"))

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	# HTML5: el navegador no puede ser servidor (WebSocketServer no es instanciable) ni
	# hacer broadcast UDP para el descubrimiento. Sin hijos, todo el subsistema queda inerte.
	if OS.has_feature("web"):
		remote_control_enabled = false
		set_process(false)
		return
	# Tier LOW (handheld lento): solo se cae el HOST. Nadie va a manejar el handheld
	# desde otro equipo, y announcer/server/bridge cuestan _process por frame mas el
	# broadcast UDP y los puertos. El CLIENTE si va: el handheld es un mando comodo
	# para una partida que corre en otra maquina.
	var low_tier := _is_low_tier()
	if low_tier:
		print("[RemoteControlManager] tier LOW: solo cliente (sin host)")
	else:
		announcer = RemoteAnnouncer.new()
		announcer.name = "RemoteAnnouncer"
		add_child(announcer)

	discovery = RemoteDiscovery.new()
	discovery.name = "RemoteDiscovery"
	add_child(discovery)

	if not low_tier:
		server = RemoteControlServer.new()
		server.name = "RemoteControlServer"
		server.pause_mode = Node.PAUSE_MODE_PROCESS
		add_child(server)

	client = RemoteControlClient.new()
	client.name = "RemoteControlClient"
	add_child(client)

	if client != null:
		client.connect("ui_directive_received", self, "_on_client_ui_directive")
		# FD-316: el sim host simula el nivel de OTRO device. Si la SESION TERMINA,
		# la autoridad deja de simular y descarga el nivel. Si la CONEXION SE CAE
		# (p.ej. el control perdio foco y pauso), es transitorio: se conserva el nivel
		# para reanudar sin recargarlo ni re-disparar la intro de despertar.
		client.connect("connection_lost", self, "_soft_stop_sim_host_if_active")
		client.connect("session_ended", self, "_stop_sim_host_if_active")
		# FD-294: el idioma del control viaja al emparejar y al retomar la sesion.
		client.connect("pair_result_received", self, "_on_client_pair_result")
		client.connect("connection_restored", self, "_on_client_connection_restored")

	if SuitOSRemoteBridge != null and not low_tier:
		bridge = SuitOSRemoteBridge.new()
		bridge.name = "SuitOSRemoteBridge"
		bridge.pause_mode = Node.PAUSE_MODE_PROCESS
		add_child(bridge)

	if RemoteSimHost != null:
		sim_host = RemoteSimHost.new()
		sim_host.name = "RemoteSimHost"
		add_child(sim_host)

	if RemoteSimClient != null:
		sim_client = RemoteSimClient.new()
		sim_client.name = "RemoteSimClient"
		add_child(sim_client)

	if low_tier:
		# _process solo sincroniza el host (escena y pausa): sin host no tiene nada que hacer.
		set_process(false)

	if server != null:
		server.connect("client_pair_requested", self, "_on_server_pair_requested")
		server.connect("input_received", self, "_on_server_input_received")
		server.connect("client_disconnected", self, "_on_server_client_disconnected")
		server.connect("client_stalled", self, "_on_server_client_disconnected")
		server.connect("client_connected", self, "_on_server_client_connected")
		server.connect("ui_directive_received", self, "_on_server_ui_directive")

	_apply_settings()
	call_deferred("_sync_host_for_scene")
	# FD-316: el handheld low-tier ahora SI anuncia (y puede portar el host de
	# offload) cuando el control remoto esta habilitado. Antes quedaba mudo.
	if low_tier and remote_control_enabled:
		enable_low_tier_offload()

func _process(_delta: float) -> void:
	_sync_host_for_scene()
	_sync_pause_to_controls()
	_sync_sim_pause_to_authority()
	update_offload_roles()
	# FD-316 (tarea F): en corridas automatizadas no se toca el loop global; los tests
	# ejercitan el guard llamando update_sim_host_focus_guard() con el override de foco.
	if not _is_automated_session():
		update_sim_host_focus_guard()

func enable_low_tier_offload() -> void:
	allow_low_tier_offload = true
	if announcer == null and RemoteAnnouncer != null:
		announcer = RemoteAnnouncer.new()
		announcer.name = "RemoteAnnouncer"
		add_child(announcer)
	if announcer != null and _is_low_tier():
		announcer.broadcast_interval = LOW_TIER_BROADCAST_INTERVAL
	if server == null and RemoteControlServer != null:
		server = RemoteControlServer.new()
		server.name = "RemoteControlServer"
		server.pause_mode = Node.PAUSE_MODE_PROCESS
		add_child(server)
		server.connect("client_pair_requested", self, "_on_server_pair_requested")
		server.connect("input_received", self, "_on_server_input_received")
		server.connect("client_disconnected", self, "_on_server_client_disconnected")
		server.connect("client_stalled", self, "_on_server_client_disconnected")
		server.connect("client_connected", self, "_on_server_client_connected")
		server.connect("ui_directive_received", self, "_on_server_ui_directive")
	if bridge == null and SuitOSRemoteBridge != null:
		bridge = SuitOSRemoteBridge.new()
		bridge.name = "SuitOSRemoteBridge"
		bridge.pause_mode = Node.PAUSE_MODE_PROCESS
		add_child(bridge)
	set_process(true)
	_sync_host_for_scene()

func update_offload_roles() -> void:
	var is_low_host: bool = _is_low_tier()
	# El tier LOW puede resolverse recien al entrar a un nivel, despues de _ready: sin
	# esto el handheld quedaba como desktop y start_host_services lo vetaba (LOW sin
	# allow_low_tier_offload), asi que el offload nunca arrancaba.
	if is_low_host and not allow_low_tier_offload and remote_control_enabled:
		enable_low_tier_offload()
	var has_paired: bool = (server != null and server.has_paired_client())
	var scene = get_tree().current_scene
	var in_gameplay: bool = scene != null and _is_gameplay_scene(scene.filename)

	# FD-316: la promocion a render-esclavo requiere nivel real abierto (no menu): el
	# sim_hello describe ESTA escena y su jugador; sin jugador no hay nada que ceder.
	if is_low_host and has_paired and RENDER_SLAVE_OFFLOAD_READY and in_gameplay:
		# Review bug 7: si el bind del puerto sim falla no hay rol; no se reintenta cada
		# frame (ver RENDER_SLAVE_START_RETRY_MSEC).
		if not is_render_slave_active and OS.get_ticks_msec() >= _render_slave_retry_at_ms:
			_start_render_slave_role()
	else:
		if is_render_slave_active:
			_stop_render_slave_role()

func _start_render_slave_role() -> void:
	if sim_client == null:
		printerr("[RemoteControlManager] sin RemoteSimClient: no se activa el render-esclavo")
		_render_slave_retry_at_ms = OS.get_ticks_msec() + RENDER_SLAVE_START_RETRY_MSEC
		return
	# El canal de snapshots NO puede ser el sensor_udp_port: el server ya lo tiene
	# tomado en esta misma maquina, asi que el render-esclavo escucha en el siguiente.
	var sim_port: int = (server.sensor_udp_port + 1) if server != null else 10445
	# FD-316: el token de la sesion firma cada sim_input y valida los snapshots.
	var sim_token: String = String(server._active_token) if server != null else ""
	# Review bug 7: si el puerto sim esta ocupado start_render_slave devuelve false. Antes
	# se ignoraba: el manager se marcaba activo y mandaba start_sim_host/sim_hello, dejando
	# a la autoridad simulando para un esclavo sordo y sin input.
	if not sim_client.start_render_slave(sim_port, "", sim_port, sim_token):
		printerr("[RemoteControlManager] start_render_slave fallo (puerto ", sim_port,
			" ocupado): no se activa el render-esclavo")
		_render_slave_retry_at_ms = OS.get_ticks_msec() + RENDER_SLAVE_START_RETRY_MSEC
		return
	is_render_slave_active = true
	# El primer _process del rol reenvia el estado de pausa actual a la autoridad.
	_sent_sim_paused = -1
	if server != null:
		server.send_ui_directive("start_sim_host", {"target_port": sim_port})
		# FD-316 paso 1: el handshake con TODO el estado que la autoridad necesita:
		# escena abierta, semilla de la corrida y spawn/checkpoint del jugador.
		server.send_ui_directive("sim_hello", _build_sim_hello())

# Lo que la autoridad levantara del lado del control. El snapshot del jugador es el
# mismo mecanismo que entre escenas (SessionManager.capture_scene_transition_state):
# restore_snapshot en el sim host lo deja en la posicion/velocidad/yaw exactos.
func _build_sim_hello() -> Dictionary:
	var scene = get_tree().current_scene
	var scene_path: String = scene.filename if scene != null else ""
	var session = get_node_or_null("/root/SessionManager")
	var run_seed: int = int(session.run_seed) if session != null and "run_seed" in session else 0
	var spawn := {}
	var checkpoint := {}
	if session != null and scene_path != "" and session.has_method("capture_scene_transition_state"):
		var captured: Dictionary = session.capture_scene_transition_state()
		if captured.has("player_snapshot"):
			checkpoint["player_snapshot"] = captured["player_snapshot"]
			var snapshot: Dictionary = captured["player_snapshot"]
			if snapshot.has("position"):
				spawn["position"] = snapshot["position"]
			if snapshot.has("yaw"):
				spawn["yaw"] = float(snapshot["yaw"])
	var token: String = server._active_token if server != null else ""
	return RemoteProtocol.create_sim_hello(scene_path, 60, token, spawn, run_seed, checkpoint,
		_capture_level_states(scene))

# FD-316: estado persistente del nivel que el sim host tiene que adoptar para no
# recargarlo desde cero: los actores replay_sync con get_snapshot (p. ej. RingHubWakeup,
# la escotilla del criopod, el OYSTrigger de despertar). Sin esto la autoridad instancia
# el nivel, su _ready corre la intro de nuevo y la escotilla se abre/suena otra vez.
# La clave es el path relativo a la escena; la raiz del nivel queda como "." para que
# viaje tambien el estado del propio RingHubWakeup (secuencia de despertar ya liberada).
func _capture_level_states(scene: Node) -> Dictionary:
	var states: Dictionary = {}
	if scene == null or not is_inside_tree():
		return states
	for node in get_tree().get_nodes_in_group("replay_sync"):
		if not is_instance_valid(node):
			continue
		if node != scene and not scene.is_a_parent_of(node):
			continue
		if not node.has_method("get_snapshot"):
			continue
		states[String(scene.get_path_to(node))] = node.call("get_snapshot")
	return states

func _stop_render_slave_role() -> void:
	is_render_slave_active = false
	if sim_client != null:
		sim_client.stop_render_slave()
	if server != null:
		server.send_ui_directive("stop_sim_host", {})

# Locale propio del host, guardado al aplicar el idioma del control (para restaurarlo
# cuando la sesion termina). "" = no hay idioma remoto aplicado.
var _remote_locale_applied := ""

# --- FD-316 (tarea N): canal confiable esclavo(server) -> autoridad(client) ---
# Las acciones discretas del render-esclavo (acciones de SuitOS/HUD y flancos del InputMap
# fuera del set del sim_input) no pueden quedarse locales: la autoridad es la que simula y
# decide la camara. Viajan por el WS existente reusando la forma de SuitOSRemoteBridge
# ("remote_action"/"screen_select"); en la autoridad las recibe _on_client_ui_directive.
# Devuelve true solo si el mensaje salio: el llamador no ejecuta nada local en ese caso.
func send_render_slave_directive(op: String, payload) -> bool:
	if not is_render_slave_active:
		return false
	if server == null or not is_instance_valid(server) or not server.has_method("send_ui_directive"):
		return false
	server.send_ui_directive(op, payload)
	return true

# Accion de SuitOS disparada en el esclavo (perform_action, select del drawer): la ejecuta la
# autoridad sobre SU SuitOS, que tiene el nivel simulado. El resultado visual y la camara
# vuelven por el snapshot.
func forward_suitos_action(screen_id: String, op: String, args: Dictionary = {}) -> bool:
	return send_render_slave_directive("remote_action", {
		"screen_id": screen_id,
		"op": op,
		"args": args
	})

# Pantalla abierta/cerrada en el HUD del esclavo: la autoridad abre la misma en su nivel
# simulado y le pide/suelta el foco, que es lo que mueve la camara cinematica.
func forward_render_slave_screen_select(screen_id: String) -> bool:
	return send_render_slave_directive("screen_select", {"id": screen_id})

# Flanco de una accion discreta del InputMap (linterna y similares).
func forward_discrete_action(action: String) -> bool:
	return send_render_slave_directive("sim_action", {"action": action})

func _on_client_ui_directive(op: String, payload) -> void:
	if op == "start_sim_host":
		var port = int(payload.get("target_port", 10444)) if payload is Dictionary else 10444
		var target_ip = client._host_ip if client != null and client._host_ip != "" else "127.0.0.1"
		is_sim_host_active = true
		if sim_host != null:
			# La simulacion queda activa PERO sin emitir: nada sale hasta que llegue
			# el sim_hello con el nivel (RemoteSimHost.sim_ready).
			# FD-316: el token de la sesion viaja a la autoridad para que descarte
			# sim_input/snapshots de un peer LAN ajeno (riesgo "Sin auth" del review).
			var session_token: String = String(client._session_token) if client != null else ""
			sim_host.start_simulation(target_ip, port, session_token)
	elif op == "sim_hello":
		# FD-316 paso 2: el esclavo dice QUE nivel simular y desde donde.
		if sim_host != null:
			sim_host.load_sim_level(payload if payload is Dictionary else {})
	elif op == "stop_sim_host":
		is_sim_host_active = false
		if sim_host != null:
			sim_host.stop_simulation()
	elif op == "sim_pause":
		# FD-316 (review bug 5): el handheld pauso su arbol; la autoridad congela la
		# logica del nivel sin descargarlo (mismo congelado que el stop blando).
		var sim_paused: bool = bool(payload.get("paused", false)) if payload is Dictionary else false
		_set_sim_host_paused(sim_paused)
	elif op == "remote_action":
		# FD-316 (tarea N): accion de SuitOS disparada en el render-esclavo. Se ejecuta
		# sobre el SuitOS de la autoridad (el nivel simulado registra sus pantallas).
		_apply_remote_suitos_action(payload)
	elif op == "screen_select":
		# FD-316 (tarea N): pantalla elegida en el HUD del esclavo: se abre tambien en el
		# nivel simulado y se le pide el foco (la camara cinematica viaja en el snapshot).
		_apply_remote_screen_select(payload)
	elif op == "sim_action":
		# FD-316 (tarea N): flanco de una accion discreta del InputMap (linterna).
		var action := String(payload.get("action", "")) if payload is Dictionary else ""
		if sim_host != null and action != "":
			sim_host.apply_client_action(action)

# La accion de SuitOS la resuelve la MISMA API que usa el juego local (perform_action). Como
# la autoridad no es render-esclavo, ahi no se reenvia: se ejecuta de verdad.
func _apply_remote_suitos_action(payload) -> void:
	if not (payload is Dictionary):
		return
	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os == null:
		return
	var screen_id := String((payload as Dictionary).get("screen_id", ""))
	var action_op := String((payload as Dictionary).get("op", ""))
	var args: Dictionary = (payload as Dictionary).get("args", {}) \
		if typeof((payload as Dictionary).get("args")) == TYPE_DICTIONARY else {}
	if screen_id == "" or action_op == "" or not suit_os.has_screen(screen_id):
		return
	suit_os.perform_action(screen_id, action_op, args)

# Abre/cierra la pantalla en el SuitOS de la autoridad y le pide/suelta el foco. El foco es lo
# unico que mueve la camara; sin esto elegir la criocapsula en el drawer no hacia la
# transicion cinematica en el esclavo.
func _apply_remote_screen_select(payload) -> void:
	if not (payload is Dictionary):
		return
	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os == null:
		return
	var screen_id := String((payload as Dictionary).get("id", ""))
	var previous := String(suit_os.get_active_screen_id())
	if screen_id != previous and previous != "":
		var prev_screen = suit_os.get_screen(previous)
		if prev_screen != null and prev_screen.has_method("exit_focus_mode"):
			prev_screen.call("exit_focus_mode")
	if screen_id == "":
		suit_os.close_screen()
		return
	if not suit_os.has_screen(screen_id):
		return
	suit_os.open_screen(screen_id)
	var screen = suit_os.get_screen(screen_id)
	if screen != null and screen.has_method("enter_focus_mode"):
		screen.call("enter_focus_mode")

# FD-316 (review bug 5): pausa del esclavo. El sim host sigue emitiendo snapshots del
# estado congelado (es lo que el esclavo pausado debe mostrar), pero su mundo no avanza
# detras del menu. Reusa el congelado compartido; al despausar se descongela.
func _set_sim_host_paused(paused: bool) -> void:
	if sim_host == null or not is_sim_host_active:
		return
	if paused:
		if sim_host.sim_ready:
			sim_host._freeze_sim_level()
	elif not sim_host._soft_stopped:
		sim_host._freezer.thaw()

# Directivas que el CONTROL manda a este host (client.send_ui_directive llega por el
# server, no por _on_client_ui_directive, que es el sentido host -> control).
func _on_server_ui_directive(op: String, payload) -> void:
	if op == "set_language":
		# FD-294: el idioma del CONTROL manda en el host mientras dura la sesion (el HUD
		# y los prompts del nivel se muestran en el idioma de quien juega). Al cerrar la
		# sesion se restaura el locale propio del host.
		_apply_control_language(payload if payload is Dictionary else {})

# FD-316: sesion caida o cerrada mientras este device era la autoridad: nivel fuera.
func _stop_sim_host_if_active() -> void:
	if not is_sim_host_active:
		return
	is_sim_host_active = false
	if sim_host != null:
		sim_host.stop_simulation()

# FD-316: la conexion se cayo pero puede volver (el control perdio foco y pauso). El
# nivel se conserva: al retomar, load_sim_level lo reusa y no se recarga ni se repite
# la intro (era el "vuelve a sonar la apertura del pod" al cambiar de ventana).
func _soft_stop_sim_host_if_active() -> void:
	if not is_sim_host_active:
		return
	is_sim_host_active = false
	if sim_host != null:
		sim_host.stop_simulation(true)

# FD-316 (tarea F): true mientras esta maquina deba mantener su simulacion a ritmo: es
# sim host activo, o el nivel quedo conservado por un stop blando (reconexion en curso).
# Cubre la caida transitoria de connection_lost al perder foco: mientras el nivel siga
# conservado, PauseManager no pausa el arbol y el guard de foco mantiene el ritmo.
func is_sim_host_holding_simulation() -> bool:
	if is_sim_host_active:
		return true
	if sim_host == null or not is_instance_valid(sim_host):
		return false
	var level = sim_host.get("_sim_level")
	return bool(sim_host.get("_soft_stopped")) and bool(sim_host.get("sim_ready")) \
		and level != null and is_instance_valid(level)

# FD-316 (tarea F): un solo lugar aplica y restaura el ritmo del loop cuando la ventana
# del sim host pierde el foco. Fuera del rol (o con foco) no toca nada: vsync, target_fps
# y el modo de bajo consumo vuelven a su valor previo.
func update_sim_host_focus_guard() -> void:
	var should_guard: bool = is_sim_host_holding_simulation() and not _sim_host_window_focused()
	if should_guard == _sim_host_focus_guard_active:
		return
	_sim_host_focus_guard_active = should_guard
	if should_guard:
		_sim_host_saved_vsync = OS.vsync_enabled
		_sim_host_saved_target_fps = Engine.target_fps
		_sim_host_saved_low_proc = OS.low_processor_usage_mode
		OS.vsync_enabled = false
		OS.low_processor_usage_mode = false
		var physics_fps: int = int(round(Engine.iterations_per_second))
		Engine.target_fps = physics_fps if physics_fps > 0 else 60
		print("[RemoteControlManager] sim host sin foco: vsync off, target_fps=", Engine.target_fps)
	else:
		_restore_sim_host_loop_state()

func _restore_sim_host_loop_state() -> void:
	OS.vsync_enabled = _sim_host_saved_vsync
	Engine.target_fps = _sim_host_saved_target_fps
	OS.low_processor_usage_mode = _sim_host_saved_low_proc

# Sin esto, si el nodo sale del arbol con el guard activo (cierre de app o tests) la
# ventana quedaria con vsync off.
func _release_sim_host_focus_guard() -> void:
	if not _sim_host_focus_guard_active:
		return
	_sim_host_focus_guard_active = false
	_restore_sim_host_loop_state()

func _sim_host_window_focused() -> bool:
	if _sim_host_focus_override >= 0:
		return _sim_host_focus_override == 1
	return OS.is_window_focused()

# El control remoto muestra cuando la partida esta en pausa aca (menu de pausa, perdida
# de foco, dialogo de emparejamiento). Solo se manda al cambiar, y de nuevo a cada
# control que se empareja o retoma (_on_server_client_connected).
func _sync_pause_to_controls() -> void:
	if not is_host_active:
		return
	var paused: int = int(get_tree().paused)
	if paused != _sent_paused:
		_sent_paused = paused
		server.send_ui_directive("host_paused", {"paused": paused == 1})

func _on_server_client_connected(_device_name: String) -> void:
	_sent_paused = -1

# FD-316 (review bug 5): el handheld render-esclavo avisa a la autoridad cuando su arbol
# queda pausado (menu/pausa rapida), para que el sim host congele la logica del nivel en
# vez de simular el mundo detras del menu. Solo al cambiar; RemoteSimClient manda ademas
# el frame neutro. La pausa se resuelve en _set_sim_host_paused del lado de la autoridad.
func _sync_sim_pause_to_authority() -> void:
	if not is_render_slave_active:
		_sent_sim_paused = -1
		return
	var paused: int = int(get_tree().paused)
	if paused == _sent_sim_paused:
		return
	_sent_sim_paused = paused
	if server != null:
		server.send_ui_directive("sim_pause", {"paused": paused == 1})

# Cerrar la app (Salir, quit) tambien es cerrar la partida: el control recibe session_end
# y se va en vez de reintentar 30 s. Si el sistema mata el proceso no hay aviso posible.
func _exit_tree() -> void:
	_release_sim_host_focus_guard()
	stop_host_services()

func _apply_settings() -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm and "remote_control_enabled" in sm:
		remote_control_enabled = sm.remote_control_enabled

	_sync_host_for_scene()

func _sync_host_for_scene() -> void:
	var scene = get_tree().current_scene
	# A mitad de un cambio de escena SceneManager deja current_scene en null un frame:
	# eso no es "salir del juego". Apagar ahi cortaba al control remoto en cada cambio
	# de nivel (y el control se cierra solo cuando se le cae la sesion).
	if scene == null:
		return
	var scene_path: String = scene.filename
	var should_host: bool = remote_control_enabled and _is_gameplay_scene(scene_path) and not _is_automated_session()
	if should_host and not is_host_active:
		start_host_services()
	elif not should_host and is_host_active:
		stop_host_services()

func _is_gameplay_scene(scene_path: String) -> bool:
	return scene_path != "" and scene_path.find("Menu.tscn") == -1 and scene_path.find("Boot.tscn") == -1 \
		and scene_path.find("RemoteControlHome.tscn") == -1 and scene_path.find("HotzonePlayer.tscn") == -1

func _is_automated_session() -> bool:
	if OS.has_feature("Server"):
		return true
	if Engine.has_singleton("GdUnit3") and Engine.get_singleton("GdUnit3").is_test_suite():
		return true
	var session = get_node_or_null("/root/SessionManager") if is_inside_tree() else null
	return session != null and (bool(session.get("is_cli_mode")) or bool(session.get("is_replaying")))

# Handheld lento: se apaga el HOST (nadie lo va a manejar desde otro equipo, y sus nodos
# cuestan _process por frame). El cliente no pasa por aca: en LOW se instancia igual.
func _is_low_tier() -> bool:
	var gate = get_node_or_null("/root/GLES3VendorGate")
	return gate != null and gate.has_method("is_low_tier") and gate.is_low_tier()

func start_host_services(session_name: String = "") -> void:
	if not remote_control_enabled or server == null or _is_automated_session():
		return
	if _is_low_tier() and not allow_low_tier_offload:
		return
	if is_host_active:
		return
	if session_name == "":
		# $HOSTNAME casi nunca llega a una app grafica (y en Android no existe): todos
		# los hosts se anunciaban como "Odisea Host".
		session_name = RemoteProtocol.device_hostname()
		if session_name == "":
			session_name = "Odisea Host"

	if server.start_server():
		announcer.start_announcing(session_name, server.ws_port, server.sensor_udp_port)
		is_host_active = true

func stop_host_services() -> void:
	if not is_host_active:
		return
	announcer.stop_announcing()
	server.stop_server()
	_release_remote_inputs()
	is_host_active = false

# Hay un control remoto emparejado desde esta misma maquina.
func has_local_remote_control() -> bool:
	return is_host_active and is_instance_valid(server) \
		and server.has_method("has_local_paired_client") and server.has_local_paired_client()

func set_remote_control_enabled(enabled: bool) -> void:
	remote_control_enabled = enabled
	_sync_host_for_scene()

func _on_server_pair_requested(device_name: String, pin: String, callback: FuncRef) -> void:
	if not is_host_active:
		callback.call_func(false)
		return
	_paused_for_pairing = not get_tree().paused
	_mouse_mode_before_pairing = Input.get_mouse_mode()
	# El nativo no se muestra: el dialogo de pairing prende el cursor virtual.
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	get_tree().paused = true
	var dialog = load("res://core_v2/ui/RemotePairingDialog.tscn").instance()
	dialog.pause_mode = Node.PAUSE_MODE_PROCESS
	var layer := CanvasLayer.new()
	layer.name = "RemotePairingLayer"
	layer.layer = PAIRING_DIALOG_LAYER
	layer.pause_mode = Node.PAUSE_MODE_PROCESS
	get_tree().root.add_child(layer)
	layer.add_child(dialog)
	_pairing_dialog = dialog
	dialog.connect("pairing_completed", self, "_on_pairing_completed", [dialog], CONNECT_ONESHOT)
	dialog.prompt_pairing(device_name, pin, callback)

# Hay una solicitud de emparejamiento esperando respuesta: tiene prioridad sobre la pausa.
func is_pairing_prompt_open() -> bool:
	return is_instance_valid(_pairing_dialog)

func _on_pairing_completed(_accepted: bool, dialog: Node) -> void:
	if _paused_for_pairing:
		get_tree().paused = false
		Input.set_mouse_mode(_mouse_mode_before_pairing)
		_paused_for_pairing = false
	_pairing_dialog = null
	var layer = dialog.get_parent()
	if layer is CanvasLayer and layer.name == "RemotePairingLayer":
		layer.queue_free()
	else:
		dialog.queue_free()

func _on_server_input_received(input_type: String, payload: Dictionary) -> void:
	# Jugar desde el control saca al host de la pausa: desde que ESC ya no viaja, es la forma de
	# volver a la partida sin tocar la otra pantalla.
	if _is_remote_activity(input_type, payload) and _host_pause_is_wakeable():
		get_node("/root/PauseManager").resume()
	var session = get_node_or_null("/root/SessionManager")
	var player = session.player if session and is_instance_valid(session.player) else null
	var input_provider = player.input_provider if player and "input_provider" in player else null
	match input_type:
		# Un solo protocolo para cualquier control, tactil o de escritorio: eventos que
		# dejan el estado en el Input del host hasta que llega el contrario. Antes el tactil
		# mandaba una foto de InputDataV2 por tick que el jugador consumia y olvidaba: un
		# tick sin foto soltaba todo (caia la velocidad) y el controlador sacaba flancos
		# falsos del hueco (el crouch sostenido se alternaba solo).
		"event":
			# FD-316 render-esclavo: el handheld no simula, y RemoteSimClient reenvia a la
			# autoridad lo que quede en SU Input. Si ademas metieramos aca los eventos del
			# control, la autoridad recibiria el mismo input DOS veces (local por su
			# provider + eco por sim_input). El control lo lee la autoridad del lado suyo.
			if not is_render_slave_active:
				_apply_remote_event(payload)
		"touch_camera":
			# TouchCameraControls ya entrega unidades de camara: van por el mismo acumulador
			# que usa el touch local, no por mouse_delta_accum (que invierte Y y aplica la
			# sensibilidad del mouse). Como render-esclavo no simulamos: se reenvia a la
			# autoridad o el giro de camara del control se pierde (FD-316).
			if is_render_slave_active and sim_client != null:
				sim_client.queue_camera_input(float(payload.get("x", 0.0)), float(payload.get("y", 0.0)), float(payload.get("zoom", 0.0)), true)
			elif input_provider:
				input_provider.add_touch_camera_drag(Vector2(float(payload.get("x", 0.0)), float(payload.get("y", 0.0))))
				input_provider.add_touch_camera_zoom(float(payload.get("zoom", 0.0)))
		"mouse_delta":
			# El mouse del otro lado ya esta capturado; aca se suma directo al acumulador
			# que llena PlayerControllerV2._input, que en un host tactil nunca ve el
			# mouse como capturado y descartaria el movimiento.
			if is_render_slave_active and sim_client != null:
				sim_client.queue_camera_input(float(payload.get("x", 0.0)), float(payload.get("y", 0.0)))
			elif input_provider:
				input_provider.mouse_delta_accum += Vector2(float(payload.get("x", 0.0)), float(payload.get("y", 0.0)))
		"release_all":
			_release_remote_inputs()
	emit_signal("remote_input_received", input_type, payload)

# Actividad = alguien jugando: apretar algo o mover la camara. Un release no (el release_all
# que manda el control al perder el foco reanudaria el host), ni el ruido de un stick en reposo.
const REMOTE_ACTIVITY_AXIS_DEADZONE := 0.5

func _is_remote_activity(input_type: String, payload: Dictionary) -> bool:
	match input_type:
		"event":
			if String(payload.get("k", "")) == "jm":
				return abs(float(payload.get("v", 0.0))) >= REMOTE_ACTIVITY_AXIS_DEADZONE
			return bool(payload.get("p", false))
		"mouse_delta", "touch_camera":
			return abs(float(payload.get("x", 0.0))) + abs(float(payload.get("y", 0.0))) > 0.0
	return false

# Solo la pausa del menu (la de perder el foco incluida). No la del modo HUD del host, que es
# de quien lo esta usando, ni la de un aviso de emparejamiento, que espera una respuesta.
func _host_pause_is_wakeable() -> bool:
	if not is_inside_tree() or not get_tree().paused or is_pairing_prompt_open():
		return false
	var pause_mgr = get_node_or_null("/root/PauseManager")
	if pause_mgr == null or pause_mgr.is_hud_mode_paused():
		return false
	var menu = pause_mgr.get("pause_menu_instance")
	return is_instance_valid(menu) and menu.visible

# El evento entra como si fuera hardware local: todo el InputMap (ui_*, pausa, zoom,
# modificadores) se comporta igual que con el teclado propio del host.
func _apply_remote_event(payload: Dictionary) -> void:
	var ev: InputEvent = RemoteProtocol.decode_event(payload, _viewport_size())
	if ev == null:
		return
	var id: String = _remote_held_id(payload)
	if bool(payload.get("p", false)) or abs(float(payload.get("v", 0.0))) > 0.0:
		var release: Dictionary = payload.duplicate()
		release["p"] = false
		release["e"] = false
		release["v"] = 0.0
		release["s"] = 0.0
		_remote_held[id] = release
	else:
		_remote_held.erase(id)
	Input.parse_input_event(ev)

# Que quedo apretado, para soltarlo si el control se cae. En una accion "a" es su nombre (en
# joypad es el eje): con int() todas las acciones compartian id y soltar una borraba otra.
func _remote_held_id(payload: Dictionary) -> String:
	var kind := String(payload.get("k", ""))
	if kind == "act":
		return "act:%s" % String(payload.get("a", ""))
	return "%s:%d:%d" % [kind, int(payload.get("sc", payload.get("b", payload.get("a", 0)))), int(payload.get("psc", 0))]

# Solo la posicion del mouse la necesita; una accion no, y fuera del arbol no hay viewport.
func _viewport_size() -> Vector2:
	return get_tree().root.get_visible_rect().size if is_inside_tree() else Vector2.ZERO

func _release_remote_inputs() -> void:
	var viewport_size: Vector2 = _viewport_size()
	for release in _remote_held.values():
		Input.parse_input_event(RemoteProtocol.decode_event(release, viewport_size))
	_remote_held.clear()

func _on_server_client_disconnected(_device_name: String) -> void:
	_release_remote_inputs()
	# FD-294: la sesion termino; el host vuelve a su propio idioma.
	if _remote_locale_applied != "":
		TranslationServer.set_locale(_remote_locale_applied)
		_remote_locale_applied = ""

# Aplica el idioma efectivo del control al host. La primera vez guarda el locale propio
# para restaurarlo al desemparejar.
func _apply_control_language(payload: Dictionary) -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	# has_method, no `in`: el operador `in` de GDScript 1.x solo mira propiedades, y con
	# `in` este guard daba siempre true y el idioma del control nunca se aplicaba.
	if sm == null or not sm.has_method("resolve_effective_language"):
		return
	var locale := String(payload.get("locale", ""))
	if locale == "" or not locale in sm.UI_LOCALES:
		return
	if _remote_locale_applied == "":
		_remote_locale_applied = sm.resolve_effective_language()
	if locale == TranslationServer.get_locale():
		return
	TranslationServer.set_locale(locale)
	print("[RemoteControlManager] idioma del control aplicado al host: ", locale)

# El control manda su idioma al emparejar y al retomar la sesion: el host muestra HUD y
# prompts en el idioma de quien juega (tambien el render-esclavo en offload).
func _send_language_to_host() -> void:
	if client == null or not client._is_paired:
		return
	var sm = get_node_or_null("/root/SettingsManager")
	if sm == null or not sm.has_method("resolve_effective_language"):
		return
	client.send_ui_directive("set_language", {"locale": sm.resolve_effective_language()})

func _on_client_pair_result(ok: bool, _reason) -> void:
	if ok:
		_send_language_to_host()

func _on_client_connection_restored() -> void:
	_send_language_to_host()
