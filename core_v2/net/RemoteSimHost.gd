extends Node

# RemoteSimHost.gd - FD-316: Headless/Authority simulation runner on remote controller.
# Runs 60Hz physics + logic simulation and broadcasts tick snapshots over UDP.

signal snapshot_generated(snapshot)

var RemoteProtocol = load("res://core_v2/net/RemoteProtocol.gd")
var SimLogicFreeze = load("res://core_v2/net/SimLogicFreeze.gd")
var RemoteSimStats = load("res://core_v2/net/RemoteSimStats.gd")

export var target_ip: String = ""
export var target_port: int = 10444
export var active: bool = false

# FD-316: la autoridad solo emite cuando el nivel pedido por el render-esclavo
# (sim_hello) esta cargado y tiene jugador. Antes de eso capture_snapshot no tiene
# nada que mostrar: el esclavo no debe recibir basura de RemoteControlHome.
var sim_ready: bool = false
# Nivel de simulacion: se instancia en un Viewport propio con UPDATE_DISABLED, SIN
# own_world (comparte el mundo/fisica principal, ver FD-316 "Decision de
# implementacion"). current_scene del control queda intacto: RemoteControlHome sigue
# siendo la pantalla y el gamepad del sim host.
var _sim_viewport: Viewport = null
var _sim_level: Node = null
var _sim_player: Node = null
# Escena del nivel montado (para reconocer una re-promocion del MISMO nivel sin
# recargarlo; ver load_sim_level). El nombre del recurso del nivel instanciado.
var _sim_scene_path: String = ""

# FD-316: stop blando. La sesion se cayo pero el nivel se conserva para reanudar. Nadie
# llama _apply_authority_input_frame, asi que sin congelar la logica el Pilot oculto cae
# a su InputProvider local (el teclado del control lo mueve), los timers/cinematicas
# avanzan y la bateria se gasta. Se congela igual que el render-esclavo (SimLogicFreeze)
# y se descongela al retomar.
var _freezer = SimLogicFreeze.new()
var _soft_stopped: bool = false
# Vencimiento (msec, OS.get_ticks_msec) del nivel conservado. Si no hay re-promocion en
# SOFT_STOP_UNLOAD_SEC, se descarga.
const SOFT_STOP_UNLOAD_SEC := 60.0
var _soft_stop_deadline_ms: int = 0

var _udp = PacketPeerUDP.new()
var _current_tick: int = 0
var _token: String = ""
var _tracked_group: String = "replay_sync"

# Deterministic input queue: list of input entries ordered by target tick
var _input_queue: Array = []
# Ultimo estado de input del handheld (axes/buttons) y su look acumulado entre ticks.
# FD-316: la autoridad fusiona el input del control (provider local) con el del
# handheld en UN InputDataV2 por tick y lo inyecta con player.inject_input(). Antes se
# materializaba como acciones globales del InputMap (Input.action_press), que ensuciaba
# el input de la maquina del control y no admitia el look (no es una accion).
var _client_input_state: Dictionary = {}
var _client_camera: Dictionary = {}
# Flanco del interact del handheld (para no re-dispararlo cada tick mientras se sostiene).
var _client_interact_was_down := false
# FD-316: expiracion del input del handheld. Si no llega un sim_input valido en
# CLIENT_INPUT_TIMEOUT_MSEC, el estado del esclavo vuelve a cero: sin esto el ultimo
# axes/buttons se re-inyectaba tick a tick y el personaje seguia corriendo a ciegas
# cuando se cortaba la red (bug 1 del review FD-316).
const CLIENT_INPUT_TIMEOUT_MSEC := 200
# Marca de llegada (OS.get_ticks_msec) del ultimo sim_input del esclavo; 0 = ninguno.
var _last_client_input_ms: int = 0
# Ultimo seq aceptado del esclavo: descarta duplicados/reordenados de WiFi que si no
# vuelven a sumar el delta de camara (bugs 1 y 3 del review FD-316).
var _last_client_seq: int = -1

# FD-316 (tarea E): instrumentacion de carga del sim host. Ventana de 5 s; last_stats
# queda expuesto para la telemetria ANNAV2.
var _stats = RemoteSimStats.new()
var last_stats: Dictionary = {}
# Ultimo seq del esclavo APLICADO al tick (no solo encolado): viaja en cada snapshot
# como ack_seq para que el esclavo cierre su RTT input->snapshot.
var _last_applied_client_seq: int = 0
# Marca del ultimo sim_input del esclavo aceptado, para el gap maximo de input.
var _stats_last_input_ms: int = 0

func _ready() -> void:
	set_physics_process(false)
	# _process solo se usa para vigilar el vencimiento del stop blando (ver _process).
	set_process(false)
	# FD-316: el snapshot se captura DESPUES del step del Pilot (mismo tick): si corre
	# antes, cam_t/rig/arm llegan un tick atrasados y el esclavo ve un angulo que no
	# coincide con el movimiento que la autoridad acaba de simular (movimiento relativo a
	# camara). Misma prioridad tardia que RemoteSimClient para aplicar.
	process_priority = 1000

func start_simulation(p_target_ip: String, p_target_port: int, p_token: String = "") -> void:
	target_ip = p_target_ip
	target_port = p_target_port
	_token = p_token
	# Sesion nueva: el seq del esclavo arranca de cero y no hay input pegado de la
	# sesion anterior (ver _last_client_seq / _last_client_input_ms).
	_last_client_seq = -1
	_last_applied_client_seq = 0
	_release_client_input()
	# Instrumentacion (tarea E): la ventana arranca con la sesion.
	_stats.reset(OS.get_ticks_msec())
	_stats_last_input_ms = 0
	# FD-316: reanudar tras un stop blando descongela el nivel conservado antes de que
	# nadie lo re-promueva (si no, queda con la logica apagada y no simula nada).
	_clear_soft_stop()
	# FD-316: una re-promocion puede llegar tras una caida transitoria (el control
	# perdio foco/pauso) con el nivel todavia montado: se conserva y sigue el tick.
	# Resetear el tick a 0 lo dejaria por detras del ultimo aplicado en el esclavo, que
	# descarta todo lo viejo, y el nivel recargado volveria a correr su intro (el pod
	# sonaba de nuevo). Solo se descarta el nivel si NO esta listo.
	var keep_level: bool = sim_ready and _sim_level != null and is_instance_valid(_sim_level)
	if not keep_level:
		_current_tick = 0
		_unload_sim_level()
	if target_port > 0:
		_udp.close()
		var err = _udp.listen(target_port)
		# FD-316: el bind que falla es SILENCIOSO si no se chequea: el sim host deja de
		# recibir sim_input del esclavo y el input del handheld muere sin mensaje alguno
		# (visto en el E2E same-host: esclavo y host pelean el mismo puerto).
		if err != OK:
			printerr("[RemoteSimHost] ERROR: no se pudo escuchar UDP ", target_port,
				" err=", err, " — el input del render-esclavo NO llegara")
	active = true
	set_physics_process(true)

# keep_level: la sesion se cayo pero el nivel se conserva para reanudar sin recargar
# (ver RemoteControlManager._soft_stop_sim_host_if_active). Un stop definitivo lo
# descarga.
func stop_simulation(keep_level: bool = false) -> void:
	active = false
	set_physics_process(false)
	_udp.close()
	_release_client_input()
	if keep_level and sim_ready and _sim_level != null and is_instance_valid(_sim_level):
		# El nivel se conserva, pero su logica no puede seguir corriendo: sin la
		# inyeccion de input de la autoridad el Pilot leeria su provider local y el
		# control (el teclado del sim host) lo moveria solo. Se congela y se arranca
		# el reloj del vencimiento.
		_freeze_sim_level()
		_soft_stopped = true
		_soft_stop_deadline_ms = OS.get_ticks_msec() + int(SOFT_STOP_UNLOAD_SEC * 1000.0)
		set_process(true)
		print("[RemoteSimHost] stop blando: nivel conservado para reanudar")
		return
	_unload_sim_level()

# Congela la logica del nivel conservado (subarbol del nivel + el jugador, que puede no
# colgar de el). Mismo patron que el render-esclavo, via el helper compartido.
func _freeze_sim_level() -> void:
	var root: Node = _sim_level if _sim_level != null and is_instance_valid(_sim_level) else null
	_freezer.freeze(root, _sim_player)

# Revierte el stop blando: descongela y cancela el vencimiento. Idempotente; se llama al
# retomar (start_simulation / reuso del nivel) y al descargar.
func _clear_soft_stop() -> void:
	_soft_stopped = false
	_soft_stop_deadline_ms = 0
	set_process(false)
	_freezer.thaw()

# Vigila el vencimiento del stop blando: sin re-promocion en SOFT_STOP_UNLOAD_SEC el
# nivel conservado se descarga (deja de ocupar memoria y de existir sin dueno).
func _process(_delta: float) -> void:
	if not _soft_stopped:
		return
	if OS.get_ticks_msec() < _soft_stop_deadline_ms:
		return
	print("[RemoteSimHost] stop blando vencido sin re-promocion: se descarga el nivel")
	_unload_sim_level()

# --- FD-316: carga del nivel del handheld en el sim host (offload real) ---

# Recibe el sim_hello del render-esclavo: carga su nivel sin reemplazar la UI del
# control, aplica semilla y estado de spawn, y recien entonces habilita la emision.
func load_sim_level(hello: Dictionary) -> bool:
	if not active:
		printerr("[RemoteSimHost] sim_hello ignorado: simulacion no activa")
		return false
	# FD-316: el token de la sesion puede llegar por el sim_hello ademas de por la
	# directiva start_sim_host. Si ya vino en start_simulation se conserva.
	if _token == "":
		_token = String(hello.get("token", ""))
	var scene_path := String(hello.get("scene", "")).strip_edges()
	if scene_path == "" or not scene_path.begins_with("res://"):
		printerr("[RemoteSimHost] sim_hello sin escena valida: '", scene_path, "'")
		return false
	# FD-316: re-promocion sobre el MISMO nivel (p.ej. reconexion del control tras
	# perder foco): recargarlo volvia a correr el _ready del nivel y con el la intro/
	# cinematica de despertar (el pod se abria y sonaba otra vez). Si ya esta montado y
	# listo se conserva: solo se re-sincroniza la pose del handheld.
	if _reuse_sim_level_if_same(scene_path, hello):
		return true
	if not ResourceLoader.exists(scene_path):
		printerr("[RemoteSimHost] sim_hello: escena inexistente en este build: ", scene_path)
		return false
	var packed = load(scene_path)
	if packed == null or not (packed is PackedScene):
		printerr("[RemoteSimHost] sim_hello: el recurso no es PackedScene: ", scene_path)
		return false
	# Determinismo: la semilla viaja en sim_hello y se fija ANTES de instanciar, para
	# que los sistemas del nivel (p.ej. RandomLeakSeeder) deriven lo mismo que en el
	# esclavo. Nunca se sortea aca.
	var session = get_node_or_null("/root/SessionManager")
	var run_seed := int(hello.get("run_seed", 0))
	if session != null and "run_seed" in session and run_seed != 0:
		session.run_seed = run_seed
		print("[RemoteSimHost] run_seed del esclavo aplicado: ", run_seed)
	var level = packed.instance()
	if level == null:
		printerr("[RemoteSimHost] no se pudo instanciar ", scene_path)
		return false
	print("[RemoteSimHost] cargando nivel del handheld (sin render): ", scene_path)
	return _attach_sim_level(level, hello)

# True si el nivel YA montado corresponde a esa escena y esta listo: no se recarga
# (se conserva su estado) y solo se re-sincroniza el spawn del handheld.
func _reuse_sim_level_if_same(scene_path: String, hello: Dictionary = {}) -> bool:
	if not sim_ready or _sim_level == null or not is_instance_valid(_sim_level):
		return false
	if _sim_scene_path != scene_path:
		return false
	# FD-316: reanudar un nivel conservado por stop blando. Aca tambien se descongela
	# por si el reuso llega sin un start_simulation previo.
	_clear_soft_stop()
	print("[RemoteSimHost] mismo nivel ya montado: se conserva (sin recargar)")
	_apply_spawn_state(hello)
	return true

# Monta level_root como nivel de simulacion (seam de test: load_sim_level lo llama
# con la escena ya instanciada). Devuelve true si quedo listo para emitir.
func _attach_sim_level(level_root: Node, hello: Dictionary = {}) -> bool:
	_unload_sim_level()
	if level_root == null:
		return false
	var vp := Viewport.new()
	vp.name = "SimViewport"
	# Sin render y con listener propio: el nivel existe para simular y sonar, no para
	# dibujar (ver FD-316 "Decision de implementacion" para por que comparte mundo).
	vp.render_target_update_mode = Viewport.UPDATE_DISABLED
	vp.audio_listener_enable_3d = true
	add_child(vp)
	vp.add_child(level_root)
	_sim_viewport = vp
	_sim_level = level_root
	# Escena del nivel montado: con esto load_sim_level reconoce una re-promocion del
	# mismo nivel y no lo recarga (ver _reuse_sim_level_if_same).
	_sim_scene_path = String(hello.get("scene", level_root.filename))
	_sim_player = _ensure_sim_player()
	_apply_spawn_state(hello)
	# FD-316 paso 3: sim_ready = nivel listo Y con jugador. Sin jugador no hay nada
	# que simular: no se emite y el esclavo nunca deja su simulacion local.
	sim_ready = _sim_player != null
	if not sim_ready:
		printerr("[RemoteSimHost] nivel sin jugador: la simulacion queda en espera (no se emite)")
	else:
		print("[RemoteSimHost] sim_ready: nivel montado con jugador")
	return sim_ready

# El spawn lo resuelve el mismo camino que un F6: SceneManager busca SpawnPointV2 e
# instancia Pilot_v2 si el nivel no lo trae incrustado (solo lectura: no tocamos el
# autoload). Si no hay spawn point no hay jugador: queda sin sim_ready.
func _ensure_sim_player() -> Node:
	if _sim_level == null or not is_instance_valid(_sim_level):
		return null
	var existing = _find_player_under(_sim_level)
	if existing != null:
		return existing
	var sm = get_node_or_null("/root/SceneManager")
	if sm != null and sm.has_method("_ensure_player_in_current_scene"):
		sm._ensure_player_in_current_scene(_sim_level)
		return _find_player_under(_sim_level)
	return null

func _find_player_under(root: Node) -> Node:
	if root == null or not is_instance_valid(root):
		return null
	if root.is_in_group("player"):
		return root
	for pilot in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(pilot) and root.is_a_parent_of(pilot):
			return pilot
	return null

# Estado de spawn del esclavo: snapshot completo del controlador si viajo (checkpoint,
# mismo restore_snapshot que entre escenas), si no posicion+yaw directos.
func _apply_spawn_state(hello: Dictionary) -> void:
	if _sim_player == null or not is_instance_valid(_sim_player):
		return
	var checkpoint: Dictionary = hello.get("checkpoint", {}) if hello.get("checkpoint") is Dictionary else {}
	var player_snapshot: Dictionary = checkpoint.get("player_snapshot", {}) if checkpoint.get("player_snapshot", {}) is Dictionary else {}
	if not player_snapshot.empty() and _sim_player.has_method("restore_snapshot"):
		_sim_player.call("restore_snapshot", player_snapshot)
		return
	var spawn: Dictionary = hello.get("spawn", {}) if hello.get("spawn") is Dictionary else {}
	if not spawn.has("position"):
		return
	var pos_arr: Array = spawn["position"]
	if pos_arr is Array and pos_arr.size() >= 3:
		var t: Transform = _sim_player.global_transform
		t.origin = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		if spawn.has("yaw"):
			t.basis = Basis(Vector3.UP, float(spawn["yaw"]))
		if _sim_player.has_method("teleport_to"):
			_sim_player.call("teleport_to", t)
		elif _sim_player is Spatial:
			(_sim_player as Spatial).global_transform = t

func _unload_sim_level() -> void:
	_clear_soft_stop()
	sim_ready = false
	_sim_player = null
	_sim_level = null
	_sim_scene_path = ""
	if _sim_viewport != null and is_instance_valid(_sim_viewport):
		_sim_viewport.queue_free()
	_sim_viewport = null

func _physics_process(_delta: float) -> void:
	if not active:
		return
	# Sin nivel del esclavo cargado (sim_hello pendiente) no hay tick ni emision:
	# capture_snapshot sobre RemoteControlHome no sirve a nadie (FD-316 paso 3).
	if not sim_ready:
		return
	_stats.tally("tick")
	_poll_udp_input()
	_current_tick += 1
	_process_input_queue_for_tick(_current_tick)
	_apply_authority_input_frame()
	var snapshot = capture_snapshot()
	emit_signal("snapshot_generated", snapshot)
	if target_ip != "" and target_port > 0:
		send_snapshot_udp(snapshot)
	_flush_host_stats()

func receive_sim_input(input_dict: Dictionary, source_id: String = "remote") -> void:
	if source_id == "client":
		# Token: con sesion firmada, un peer LAN que no conoce el token no puede
		# inyectar input (riesgo "Sin auth" del review FD-316).
		if not _client_token_ok(input_dict):
			return
		# Paquete recibido = enlace vivo, aunque sea duplicado: renueva la expiracion.
		_last_client_input_ms = OS.get_ticks_msec()
		# Dedupe por seq monotono: un duplicado/reordenado no vuelve a sumar su
		# delta de camara (bug 3 del review FD-316).
		var seq := int(input_dict.get("seq", 0))
		if seq <= _last_client_seq:
			return
		_last_client_seq = seq
		# Instrumentacion (tarea E): input del esclavo aceptado (los duplicados ya
		# salieron por el dedupe) y gap maximo entre paquetes.
		var now_ms := OS.get_ticks_msec()
		if _stats_last_input_ms > 0:
			_stats.observe_max("input_gap_ms", float(now_ms - _stats_last_input_ms))
		_stats_last_input_ms = now_ms
		_stats.tally("input")

	var target_tick = int(input_dict.get("last_tick", _current_tick))
	if target_tick <= 0:
		target_tick = _current_tick

	var entry = {
		"tick": target_tick,
		"source": source_id,
		"seq": int(input_dict.get("seq", 0)),
		"axes": input_dict.get("axes", {}),
		"buttons": input_dict.get("buttons", {}),
		"camera": input_dict.get("camera", {})
	}

	var inserted = false
	for i in range(_input_queue.size()):
		if int(_input_queue[i]["tick"]) > target_tick:
			_input_queue.insert(i, entry)
			inserted = true
			break
	if not inserted:
		_input_queue.append(entry)

# Token valido del esclavo: sin token fijado (legacy/tests) se acepta cualquiera.
func _client_token_ok(input_dict: Dictionary) -> bool:
	if _token == "":
		return true
	return String(input_dict.get("token", "")) == _token

func _poll_udp_input() -> void:
	while _udp.get_available_packet_count() > 0:
		var pkt = _udp.get_packet()
		var pkt_str = pkt.get_string_from_utf8()
		var dict = RemoteProtocol.decode_json(pkt_str)
		if dict.get("type", "") == "sim_input":
			receive_sim_input(dict, "client")

func _process_input_queue_for_tick(tick: int) -> void:
	var idx = 0
	while idx < _input_queue.size():
		var entry = _input_queue[idx]
		if int(entry["tick"]) <= tick:
			_apply_sim_input_entry(entry)
			_input_queue.remove(idx)
		else:
			idx += 1

func _apply_sim_input_entry(entry: Dictionary) -> void:
	if String(entry.get("source", "")) != "client":
		return
	# Instrumentacion (tarea E): el seq que viaja como ack_seq es el APLICADO al tick.
	_last_applied_client_seq = int(entry.get("seq", 0))
	# El estado del handheld se guarda (axes/buttons) y su look se acumula: recien al
	# cerrar el tick se fusiona con el input del control y se inyecta como un InputDataV2.
	_client_input_state = entry
	_accumulate_client_camera(entry.get("camera", {}))

# FD-316: el look de camara no es una accion del InputMap. El handheld lo manda en el
# campo "camera" del sim_input; se acumula hasta el cierre del tick.
func _accumulate_client_camera(camera) -> void:
	if not (camera is Dictionary):
		return
	for key in ["x", "y", "zoom"]:
		if camera.has(key):
			_client_camera[key] = float(_client_camera.get(key, 0.0)) + float(camera[key])

# FD-316: UN frame de input por tick para la autoridad. Fusiona el input local del
# control (el InputProvider del player, que ya aplica curvas/sensibilidades y el gate de
# puntero) con el del handheld (axes/buttons/look que llegaron por sim_input) y lo
# inyecta con player.inject_input(). Es el lenguaje de input del Core: la autoridad
# simula exactamente el frame, sin materializar acciones globales en la maquina del
# control (Input.action_press ensuciaba su input y no admitia el look).
func _apply_authority_input_frame() -> void:
	# FD-316: sin paquetes del esclavo por mas de CLIENT_INPUT_TIMEOUT_MSEC su estado
	# se suelta: el ultimo axes/buttons no se re-inyecta para siempre (bug 1).
	_expire_stale_client_input()
	var player = _get_authority_player()
	if player == null or not is_instance_valid(player) or not player.has_method("inject_input"):
		_client_camera = {}
		return
	var provider = _get_authority_input_provider()
	var frame: InputDataV2 = null
	if provider != null and provider.has_method("get_input"):
		frame = provider.get_input()
	if frame == null:
		frame = InputDataV2.new()

	# Handheld: SU frame ya procesado se suma sobre el frame local del control.
	var axes: Dictionary = _client_input_state.get("axes", {})
	frame.move_vec += Vector2(float(axes.get("move_x", 0.0)), float(axes.get("move_y", 0.0)))
	if frame.move_vec.length() > 1.0:
		frame.move_vec = frame.move_vec.normalized()
	frame.analog_move_active = frame.analog_move_active or bool(axes.get("analog", false))
	var buttons: Dictionary = _client_input_state.get("buttons", {})
	if bool(buttons.get("jump", false)):
		frame.jump = true
	if bool(buttons.get("sprint", false)):
		frame.sprint = true
	if bool(buttons.get("crouch", false)):
		frame.crouch = true
	# interact es un flanco (just_pressed): mientras se sostiene, interact_held y un solo
	# flanco al apretar (si no, se re-dispararia cada tick).
	var interact_down := bool(buttons.get("interact", false))
	frame.interact_held = frame.interact_held or interact_down
	frame.interact = frame.interact or (interact_down and not _client_interact_was_down)
	_client_interact_was_down = interact_down

	# Look del handheld: ya viene PROCESADO por su InputProvider (mouse, stick, D-pad con
	# ramp y touch), asi que se suma tal cual, sin volver a escalar ni invertir. El look
	# del control ya esta en `frame` porque el provider de la autoridad lo proceso.
	frame.mouse_delta += Vector2(float(_client_camera.get("x", 0.0)), float(_client_camera.get("y", 0.0)))
	frame.zoom_delta += float(_client_camera.get("zoom", 0.0))
	_client_camera = {}

	player.inject_input(frame.to_dict())

func _get_authority_player() -> Node:
	if _sim_player != null and is_instance_valid(_sim_player):
		return _sim_player
	var session = get_node_or_null("/root/SessionManager")
	if session != null and "player" in session:
		return session.player
	return null

func _get_authority_input_provider():
	var player = _get_authority_player()
	if player == null or not is_instance_valid(player):
		return null
	if "input_provider" in player:
		return player.input_provider
	return null

func _release_client_input() -> void:
	# Ya no se materializan acciones globales: el estado del handheld se suelta
	# limpiando el frame (el proximo tick inyecta solo el input local del control).
	_client_input_state = {}
	_client_camera = {}
	# Tambien el flanco del interact: si el release se perdio, el proximo press tiene
	# que volver a contar como flanco.
	_client_interact_was_down = false
	_last_client_input_ms = 0

# FD-316: expiracion del input del esclavo. Pasado CLIENT_INPUT_TIMEOUT_MSEC sin un
# sim_input valido, se suelta su estado y su look acumulado: el personaje no corre a
# ciegas con el ultimo paquete (bug 1 del review FD-316).
func _expire_stale_client_input() -> void:
	if _last_client_input_ms <= 0:
		return
	if OS.get_ticks_msec() - _last_client_input_ms <= CLIENT_INPUT_TIMEOUT_MSEC:
		return
	if _client_input_state.empty() and _client_camera.empty():
		return
	print("[RemoteSimHost] sim_input vencido (", CLIENT_INPUT_TIMEOUT_MSEC,
		" ms sin paquetes validos): input del handheld a cero")
	_release_client_input()

func capture_snapshot() -> Dictionary:
	# Instrumentacion (tarea E): costo de armar el snapshot (Tarea E).
	var started_us := OS.get_ticks_usec()
	var tree = get_tree()
	if tree == null:
		return {}

	# FD-316: con nivel de simulacion montado, las rutas de entidades son relativas a
	# EL (el esclavo las resuelve contra SU current_scene, que es el mismo nivel).
	# Fallback legacy: lo que el host tenga como current_scene.
	var scene: Node = _sim_level if _sim_level != null and is_instance_valid(_sim_level) else tree.current_scene
	var scene_path = scene.filename if scene != null else ""

	var entities: Dictionary = {}
	# Estado logico de los actores (get_snapshot) por path relativo al nivel simulado.
	var actor_states: Dictionary = {}

	# Track replay_sync nodes. El Pilot real NO esta en replay_sync (solo sus hijos
	# ControllerManager/MultiTool lo estan), asi que el grupo nunca queda vacio y el
	# fallback viejo al grupo "player" no disparaba: el transform/anim del jugador no
	# viajaba y en el esclavo el mesh quedaba en el spawn mientras la camara seguia a
	# la autoridad (se "perdia" al Player). Se agrega siempre el jugador del nivel
	# simulado, ademas de los replay_sync.
	var sync_nodes = tree.get_nodes_in_group(_tracked_group)
	if scene != null:
		for player_node in tree.get_nodes_in_group("player"):
			if is_instance_valid(player_node) and not sync_nodes.has(player_node):
				sync_nodes.append(player_node)

	for node in sync_nodes:
		if is_instance_valid(node) and node is Spatial:
			# Con nivel de simulacion, solo nodos de ese nivel viajan (el resto del
			# arbol del control no existe en el esclavo).
			if _sim_level != null and is_instance_valid(_sim_level) \
					and not _sim_level.is_a_parent_of(node) and node != _sim_level:
				continue
			var path_str = String(scene.get_path_to(node)) if scene != null else String(node.get_path())
			var state = {
				"t": RemoteProtocol.encode_transform(node.global_transform),
				"v": node.visible
			}
			if node is Light:
				state["l_energy"] = node.light_energy
			# FD-316: la velocidad y el piso del jugador viajan para que el
			# render-esclavo anime walk/run/aire: alla no hay simulacion local.
			if node.is_in_group("player"):
				var node_velocity = node.get("velocity")
				if node_velocity is Vector3:
					state["vel"] = [node_velocity.x, node_velocity.y, node_velocity.z]
					state["g"] = bool(node.call("is_effectively_grounded")) if node.has_method("is_effectively_grounded") else false
				# La direccion de caminar orienta el cuerpo en el esclavo (alla el input
				# local esta congelado y el wish queda en cero).
				if node.has_method("get_wish_direction"):
					var wish = node.call("get_wish_direction")
					if wish is Vector3:
						state["wish"] = [wish.x, wish.y, wish.z]
				# FD-316: la linterna del casco no esta en replay_sync: su estado logico
				# (encendido/bateria) viaja con el jugador. La orientacion del haz la saca
				# el esclavo de la camara replicada (ver HelmetFlashlight._process).
				var flashlight = node.get_node_or_null(RemoteProtocol.FLASHLIGHT_PATH)
				if flashlight != null and "enabled" in flashlight:
					state["flash"] = {
						"on": bool(flashlight.enabled),
						"battery": float(flashlight.battery)
					}
			else:
				# FD-316: estado RICO del actor (get_snapshot), no solo el transform: los
				# interactuables (p.ej. LightGroup del pedestal) se replican por su estado
				# logico; sin esto el switch cambiaba en la autoridad y las luces del
				# esclavo quedaban apagadas.
				if node.has_method("get_snapshot"):
					actor_states[path_str] = node.call("get_snapshot")
			entities[path_str] = state

	var globals: Dictionary = {
		"scene": scene_path
	}
	# FD-316: la interaccion es parte de la simulacion. El host render-esclavo no
	# simula fisica, asi que su Area de interaccion no se actualiza; la autoridad
	# resuelve el interactuable y manda prompt+path en cada snapshot.
	globals["interact"] = _capture_interaction_state()
	# FD-316: estado logico de los interactuables (switch de luces, valvulas, ascensores).
	if not actor_states.empty():
		globals["states"] = actor_states

	# FD-316: ademas de la camara final (cam_t), viaja el rig COMPLETO (CameraRig/Yaw/
	# Pitch/OTS_Offset/SpringArm) y el largo del kinematic arm. Sin esto el esclavo se
	# quedaba con el rig en la pose de spawn: la vista se forzaba por cam_t pero el resto
	# del rig (arm, listener, efectos) divergia de la autoridad.
	globals["rig"] = _capture_player_rig()
	globals["arm_len"] = _capture_arm_length()

	# Capture camera state: la del nivel simulado (viewport oculto), no la del UI.
	var camera: Camera = null
	if _sim_viewport != null and is_instance_valid(_sim_viewport):
		camera = _sim_viewport.get_camera()
	if camera == null:
		camera = tree.root.get_viewport().get_camera()
	if camera != null and is_instance_valid(camera):
		globals["cam_t"] = RemoteProtocol.encode_transform(camera.global_transform)
		globals["cam_fov"] = camera.fov

	var snap = RemoteProtocol.create_sim_snapshot(_current_tick, OS.get_ticks_msec(), entities, globals, _token, _last_applied_client_seq)
	_stats.add("capture_us", float(OS.get_ticks_usec() - started_us))
	_stats.tally("snap")
	return snap

# La cadena del rig la define RemoteProtocol.RIG_CHAIN: host y esclavo comparten una sola
# (ver capture_snapshot).
func _capture_player_rig() -> Array:
	var out: Array = []
	var player = _get_authority_player()
	if player == null or not is_instance_valid(player):
		return out
	for path in RemoteProtocol.RIG_CHAIN:
		var n = player.get_node_or_null(path)
		out.append(RemoteProtocol.encode_transform(n.global_transform) if n is Spatial else null)
	return out

func _capture_arm_length() -> float:
	var player = _get_authority_player()
	if player == null or not is_instance_valid(player):
		return -1.0
	var arm = player.get_node_or_null(RemoteProtocol.RIG_CHAIN[RemoteProtocol.RIG_CHAIN.size() - 1])
	if arm != null and "current_length" in arm:
		return float(arm.current_length)
	return -1.0

func _capture_interaction_state() -> Dictionary:
	# Con nivel simulado, la interaccion se lee del jugador de ESE nivel: el
	# SessionManager del control no lo encuentra (no esta bajo current_scene) y
	# _find_player lo pisaria a null en cada tick.
	var player: Node = _sim_player if _sim_player != null and is_instance_valid(_sim_player) else null
	if player == null:
		var session = get_node_or_null("/root/SessionManager")
		if session != null and "player" in session:
			player = session.player
	if player != null and is_instance_valid(player) and player.has_method("get_interaction_state"):
		var state: Dictionary = player.call("get_interaction_state")
		# El path nace absoluto en el arbol del control; el esclavo lo resuelve
		# contra su escena: recortar el prefijo del nivel simulado.
		if _sim_level != null and is_instance_valid(_sim_level) and state.get("path", "") != "":
			var prefix := String(_sim_level.get_path()) + "/"
			var path := String(state["path"])
			if path.begins_with(prefix):
				state["path"] = path.substr(prefix.length())
		return state
	return {"prompt": "", "path": ""}

func send_snapshot_udp(snapshot: Dictionary) -> void:
	if target_ip == "" or target_port <= 0:
		return
	var json_str = RemoteProtocol.encode_json(snapshot)
	var bytes = json_str.to_utf8()
	# Instrumentacion (tarea E): tamanio real del datagrama del snapshot.
	_stats.add("snap_bytes", float(bytes.size()))
	_udp.set_dest_address(target_ip, target_port)
	_udp.put_packet(bytes)

# FD-316 (tarea E): cierra la ventana de stats cada RemoteSimStats.WINDOW_MS con UNA
# linea, publica el dict en last_stats (telemetria ANNAV2) y arranca la ventana nueva.
func _flush_host_stats() -> void:
	var now_ms := OS.get_ticks_msec()
	if not _stats.is_due(now_ms):
		return
	var elapsed_s: float = max(float(_stats.elapsed_ms(now_ms)) / 1000.0, 0.001)
	var snap_count: int = _stats.count("snap")
	var stats := {
		"tick_hz": float(_stats.count("tick")) / elapsed_s,
		"capture_ms_avg": (_stats.sum("capture_us") / float(max(snap_count, 1))) / 1000.0,
		"snap_bytes_avg": _stats.sum("snap_bytes") / float(max(snap_count, 1)),
		"input_hz": float(_stats.count("input")) / elapsed_s,
		"input_gap_ms_max": _stats.max_value("input_gap_ms")
	}
	last_stats = stats
	print("[RemoteSimHost] stats tick_hz=", "%.1f" % stats["tick_hz"],
		" capture_ms_avg=", "%.3f" % stats["capture_ms_avg"],
		" snap_bytes_avg=", "%.0f" % stats["snap_bytes_avg"],
		" input_hz=", "%.1f" % stats["input_hz"],
		" input_gap_ms_max=", "%.1f" % stats["input_gap_ms_max"])
	_stats.reset(now_ms)
