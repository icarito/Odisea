extends Node

# RemoteSimClient.gd - FD-316: Render-slave component running on low-end host.
# Disables local physics simulation and interpolates incoming snapshots from RemoteSimHost.

signal snapshot_applied(tick)

var RemoteProtocol = load("res://core_v2/net/RemoteProtocol.gd")
var SimLogicFreeze = load("res://core_v2/net/SimLogicFreeze.gd")
var RemoteSimStats = load("res://core_v2/net/RemoteSimStats.gd")

export var is_render_slave: bool = false

var _udp = PacketPeerUDP.new()
var _listening_port: int = 0
var _target_ip: String = ""
var _target_port: int = 10444
# FD-316: token de la sesion. Firma cada sim_input y valida los snapshots: un peer LAN
# sin el token no puede suplantar a la autoridad ni cambiarle el destino al esclavo.
var _token: String = ""
# FD-316: seq monotono del esclavo. La autoridad descarta los seq <= al ultimo visto,
# asi un duplicado/reordenado de WiFi no suma dos veces el delta de camara.
var _seq: int = 0
# FD-316: latch corto de flancos. jump/interact viajan en un unico datagrama UDP; si el
# paquete del press se pierde no hay segundo intento. Se repite el true unos paquetes
# mas para sobrevivir a esa perdida (la autoridad deriva el flanco por transicion, asi
# que repetir no duplica la accion).
const FLANK_REPEAT_PACKETS := 3
var _jump_latch: int = 0
var _interact_latch: int = 0
var _buffer: Array = [] # Dos snapshots mas nuevos, ordenados por tick
var _latest_applied_tick: int = -1
# FD-316 (tarea G): el cliente solo parsea los 2 paquetes mas recientes del drenaje UDP.
# Parsear cada datagrama JSON del frame costaba los ~15 ms por frame medidos en device
# (snap_hz 60, fps 10): los intermedios ya no hacen falta con interpolacion.
const MAX_SNAPSHOTS_PER_FRAME := 2
# Tarea L: retardo de interpolacion = UN intervalo de snapshot, en ticks del host. El host
# manda su paso efectivo en globals.snap_step; con el piso de 30 Hz queda en ~2 ticks
# (33 ms). El default (2) cubre snapshots legacy sin snap_step.
var _interp_delay_ticks: float = 2.0
# Tasa de ticks del host (Engine.iterations_per_second = 60): el reloj de render avanza
# en ticks con delta * esta tasa.
var _host_tick_rate: float = 60.0
# Par de snapshots recibidos con su tick: from = anterior, to = mas nuevo. Sin siguiente
# (o si el reloj de render se pasa) se sostiene el ultimo, sin extrapolar.
var _snap_from: Dictionary = {}
var _snap_to: Dictionary = {}
var _from_tick: int = -1
var _to_tick: int = -1
# Tiempo de render en ticks del host (float): avanza por frame y se mantiene dentro de
# [from_tick, to_tick].
var _render_tick: float = -1.0
# True cuando llego un snapshot nuevo y sus globals todavia no se aplicaron.
var _has_new_snapshot: bool = false
# FD-316 (review bug 8): estado del PhysicsServer ANTES de que el offload lo apagara. No
# se re-prende incondicionalmente: otro sistema (p.ej. la sonda split_load_frame de
# SceneManager) pudo haberlo apagado a proposito.
var _physics_was_active: bool = true
# True solo si este componente apago el PhysicsServer: evita tocar el estado global del
# motor cuando el offload nunca se comprometio.
var _physics_disabled_by_offload: bool = false
# FD-316: fisica apagada/audio muteado/interaccion cedida recien con el PRIMER
# snapshot valido, no al promover. Promover solo abre el canal: mientras el sim host
# no cargue el nivel (sim_hello -> sim_ready) no llega nada y el handheld sigue
# jugando su simulacion local, sin teletransportes ni silencios en vano.
var _engaged: bool = false
# FD-316: el player puede no existir cuando arranca el rol (pairing en un menu o
# justo antes de que SceneManager lo instancie). Si eso pasa, el flag de autoridad
# nunca se aplica y el prompt no vuelve. Se reintenta hasta resolverlo.
var _interaction_authority_applied: bool = false
var _interaction_authority_player: Node = null
# FD-316: con el offload comprometido el handheld no simula NADA: apagar PhysicsServer
# frena los cuerpos del motor pero no los _physics_process de GDScript (controlador del
# Pilot y su CameraRig, props, plataformas, ascensores...), que seguian corriendo con el
# input local encima de cada snapshot ("doble simulacion") y gastando el CPU que el
# offload tiene que liberar. Por convencion del proyecto la logica vive en
# _physics_process y lo visual en _process: se congela el primero en todo el nivel y el
# segundo sigue (animaciones, particulas). El congelado vive en SimLogicFreeze,
# compartido con el stop blando del sim host.
var _freezer = SimLogicFreeze.new()

# FD-316 (tarea E): instrumentacion de lag y carga. Ventana de 5 s; last_stats queda
# expuesto para la telemetria ANNAV2. Solo contadores y muestras chicas por evento.
var _stats = RemoteSimStats.new()
var last_stats: Dictionary = {}
# seq -> OS.get_ticks_msec() del envio. Ring chico: los seqs mas viejos sin ack se
# descartan. El RTT input->snapshot se cierra con el ack_seq de la autoridad, siempre con
# el reloj local del esclavo (no se comparan relojes entre maquinas).
const RTT_RING_MAX := 64
var _sent_seq_ms: Dictionary = {}
var _sent_seq_order: Array = []
# Ultimo tick/instante de snapshot recibido: gaps de snapshot y ticks perdidos.
var _stats_last_recv_tick: int = -1
var _stats_last_recv_ms: int = 0

# Tarea L: perfil opt-in por entorno (ODISEA_SLAVE_PROFILE=1). Cada PROFILE_WINDOW_MS se
# recorre el arbol UNA vez (no por frame) y se agrupan por script los nodos con _process
# activo: los que quedan corriendo en el esclavo aunque el nivel este congelado.
const PROFILE_WINDOW_MS := 5000
var _profile_enabled: bool = false
var _profile_last_ms: int = 0

func _ready() -> void:
	# Aplicar el snapshot DESPUES de cualquier otro _process del frame (camara incluida):
	# la autoridad manda sobre lo que quede corriendo en local.
	process_priority = 1000
	set_process(false)
	_profile_enabled = OS.get_environment("ODISEA_SLAVE_PROFILE") == "1"

func start_render_slave(p_port: int = 10444, p_target_ip: String = "", p_target_port: int = 10444, p_token: String = "") -> bool:
	_listening_port = p_port
	_target_ip = p_target_ip
	_target_port = p_target_port
	_token = p_token
	if _listening_port > 0:
		var err = _udp.listen(_listening_port)
		if err != OK:
			printerr("[RemoteSimClient] UDP listen failed on port ", _listening_port, " err=", err)
			return false

	is_render_slave = true
	_engaged = false
	_buffer.clear()
	_latest_applied_tick = -1
	# Tarea G: par de interpolacion y reloj de render en cero para la sesion nueva.
	_snap_from = {}
	_snap_to = {}
	_from_tick = -1
	_to_tick = -1
	_render_tick = -1.0
	_has_new_snapshot = false
	_interp_delay_ticks = 2.0
	_host_tick_rate = float(Engine.iterations_per_second) if Engine.iterations_per_second > 0 else 60.0
	# Tarea L: la primera impresion del perfil sale una ventana despues de arrancar el rol.
	_profile_last_ms = OS.get_ticks_msec()
	# Sesion nueva: el seq arranca de cero y no hay flancos latcheados de la anterior.
	_seq = 0
	_jump_latch = 0
	_interact_latch = 0
	_last_actor_states.clear()
	# Instrumentacion (tarea E): ventana nueva, sin seqs pendientes ni muestras viejas.
	_stats.reset(OS.get_ticks_msec())
	_sent_seq_ms.clear()
	_sent_seq_order.clear()
	_stats_last_recv_tick = -1
	_stats_last_recv_ms = 0

	# El rol se abre solo para ESCUCHAR: fisica, audio e interaccion siguen locales
	# hasta que llegue el primer snapshot valido (FD-316 paso 3).

	set_process(true)
	return true

func stop_render_slave() -> void:
	is_render_slave = false
	_engaged = false
	# Tarea G: sin par de snapshots ni reloj de render que sigan corriendo.
	_buffer.clear()
	_snap_from = {}
	_snap_to = {}
	_from_tick = -1
	_to_tick = -1
	_render_tick = -1.0
	_has_new_snapshot = false
	set_process(false)
	if _listening_port > 0:
		_udp.close()
	_restore_local_physics()
	_thaw_local_simulation()
	_set_player_interaction_authoritative(false)
	_set_local_audio_muted(false)
	# La cache de estados por path se descarta al salir del rol: si no, una re-promocion
	# en otro nivel con los mismos paths no re-aplicaria el estado (review FD-316).
	_last_actor_states.clear()
	# Instrumentacion (tarea E): sin seqs pendientes que un ack ya no va a cerrar.
	_sent_seq_ms.clear()
	_sent_seq_order.clear()

# Primer snapshot valido de la autoridad: recien aca el esclavo deja de simular.
func _engage_offload() -> void:
	if _engaged:
		return
	_engaged = true
	# Disable physics server or local physics stepping to free CPU
	_disable_local_physics()
	_freeze_local_simulation()
	# FD-316: la interaccion la resuelve la autoridad; el host no escanea.
	_set_player_interaction_authoritative(true)
	# El que suena es el control remoto (el que simula); este host solo renderiza.
	_set_local_audio_muted(true)
	print("[RemoteSimClient] offload comprometido con el primer snapshot: fisica local apagada")

func is_engaged() -> bool:
	return _engaged

func _set_local_audio_muted(muted: bool) -> void:
	var audio = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("set_render_slave_audio_muted"):
		audio.set_render_slave_audio_muted(muted)

# FD-316: una sola resolucion del jugador para todo el cliente (interaccion, congelado,
# input, rig y arm). El jugador del nivel (grupo "player" bajo current_scene) manda:
# SessionManager pisa player=null cuando el jugador no esta bajo current_scene, asi que el
# autoload es solo respaldo (ensayo local sin escena, tests). Antes habia dos funciones
# que resolvian distinto y podian congelar uno y animar otro (review FD-316).
func _get_player() -> Node:
	var tree = get_tree()
	if tree != null and tree.current_scene != null:
		for p in tree.get_nodes_in_group("player"):
			if is_instance_valid(p) and tree.current_scene.is_a_parent_of(p):
				return p
	var session = get_node_or_null("/root/SessionManager")
	if session != null and "player" in session:
		var p = session.player
		if p != null and is_instance_valid(p):
			return p
	return null

func _set_player_interaction_authoritative(on: bool) -> void:
	var player = _get_player()
	if player != null and is_instance_valid(player) and player.has_method("set_remote_interaction_authoritative"):
		player.call("set_remote_interaction_authoritative", on)
		_interaction_authority_applied = on
		_interaction_authority_player = player
	elif not on:
		_interaction_authority_applied = false
		_interaction_authority_player = null

# El rol debe volver a aplicarse si el player anterior desaparecio (cambio de escena):
# si no, la instancia nueva sigue con el scan local y sin prompt.
func _interaction_authority_is_current() -> bool:
	return _interaction_authority_applied and is_instance_valid(_interaction_authority_player)

func _apply_player_interaction(prompt: String, target_path: String) -> void:
	var player = _get_player()
	if player != null and is_instance_valid(player) and player.has_method("apply_remote_interaction_state"):
		player.call("apply_remote_interaction_state", prompt, target_path)

func _freeze_local_simulation() -> void:
	var scene = get_tree().current_scene if get_tree() != null else null
	if _freezer.frozen_root_is(scene):
		return
	# El player puede no colgar de current_scene (SessionManager lo resuelve aparte).
	_freezer.freeze(scene, _get_player())

func _thaw_local_simulation() -> void:
	_freezer.thaw()

func _disable_local_physics() -> void:
	if _physics_disabled_by_offload:
		return
	# Guardar el estado previo: al salir del rol se restaura EL MISMO, no un true ciego.
	_physics_was_active = _read_physics_active()
	_physics_disabled_by_offload = true
	PhysicsServer.set_active(false)

func _restore_local_physics() -> void:
	if not _physics_disabled_by_offload:
		return
	_physics_disabled_by_offload = false
	# Restaurar el estado previo, sin re-prender si este componente nunca lo apago.
	PhysicsServer.set_active(_physics_was_active)

# Godot 3 (y el binding de Box3D) no expone un getter del estado global del PhysicsServer:
# `is_active()` no existe. Si el motor algun dia lo expone se usa; mientras tanto se asume
# activo, que es el arranque normal del proyecto.
func _read_physics_active() -> bool:
	if PhysicsServer.has_method("is_active"):
		return PhysicsServer.is_active()
	return true

func receive_snapshot(snapshot: Dictionary, p_packet_bytes: int = 0, p_expected_packets: int = 1) -> void:
	if not snapshot.has("tick"):
		return
	# FD-316 paso 3: el primer snapshot valido compromete el offload. Antes de eso,
	# cualquier paquete no se aplica a un host congelado por error.
	if not _engaged:
		_engage_offload()
	var tick = int(snapshot["tick"])

	# Ignore duplicate or old snapshots
	if tick <= _latest_applied_tick:
		return
	_latest_applied_tick = tick

	# Insert snapshot in sorted order by tick
	var inserted = false
	for i in range(_buffer.size()):
		if int(_buffer[i]["tick"]) == tick:
			return # duplicate
		if int(_buffer[i]["tick"]) > tick:
			_buffer.insert(i, snapshot)
			inserted = true
			break
	if not inserted:
		_buffer.append(snapshot)

	# FD-316 (tarea G): con interpolacion solo hacen falta los 2 mas nuevos; soltar el
	# resto evita arrastrar snapshots que nadie va a aplicar.
	while _buffer.size() > MAX_SNAPSHOTS_PER_FRAME:
		_buffer.pop_front()

	# Instrumentacion (tarea E): recien con el snapshot aceptado (duplicados fuera) se
	# cierra el RTT del ack_seq y se miden tamano, gaps y ticks perdidos.
	_stats_on_snapshot(tick, snapshot, p_packet_bytes, p_expected_packets)

	# Tarea G: refrescar el par de interpolacion; los globals se aplican del mas nuevo en
	# el proximo _process (una sola vez por snapshot).
	# Tarea L: el retardo de interpolacion es UN intervalo, y el intervalo efectivo del
	# host viaja en globals.snap_step (puede adaptarse entre snapshots).
	var step_globals: Dictionary = snapshot.get("globals", {})
	if step_globals is Dictionary and step_globals.has("snap_step"):
		_interp_delay_ticks = float(max(1, int(step_globals["snap_step"])))
	_update_interp_pair()
	_has_new_snapshot = true

# FD-316 (tarea G): fija el par from/to con el que interpola el render. El reloj de render
# no se adelanta a lo recibido y alcanza el retardo objetivo sin saltar hacia atras.
func _update_interp_pair() -> void:
	if _buffer.empty():
		return
	_snap_to = _buffer[_buffer.size() - 1]
	_to_tick = int(_snap_to["tick"])
	_snap_from = _buffer[_buffer.size() - 2] if _buffer.size() >= 2 else _snap_to
	_from_tick = int(_snap_from["tick"])
	if _render_tick < 0.0:
		# Primer snapshot: se sostiene hasta que llegue el siguiente.
		_render_tick = float(_to_tick)
		return
	if _render_tick > float(_to_tick):
		_render_tick = float(_to_tick)
	var target := float(_to_tick) - _interp_delay_ticks
	if _render_tick < target:
		_render_tick = target

func _process(delta: float) -> void:
	if not is_render_slave:
		return

	# Instrumentacion (tarea E): frames de la ventana y costo de _poll_udp + aplicar el
	# estado del snapshot + interpolar, en el mismo tick de OS.get_ticks_usec.
	_stats.tally("frame")
	# Tarea L: muestreo por frame de los monitores del motor para promediarlos por ventana
	# (get_monitor devuelve el ultimo valor, no un promedio). TIME_* vienen en segundos.
	_stats.add("process_us", float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000000.0)
	_stats.add("physics_us", float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000000.0)
	_stats.add("draw_calls", float(Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME)))
	_stats.add("objects_in_frame", float(Performance.get_monitor(Performance.RENDER_OBJECTS_IN_FRAME)))
	_stats.add("vertices_in_frame", float(Performance.get_monitor(Performance.RENDER_VERTICES_IN_FRAME)))
	_stats.add("node_count", float(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	var poll_started_us := OS.get_ticks_usec()
	_poll_udp()
	var poll_us := OS.get_ticks_usec() - poll_started_us

	# El player pudo cambiar de escena (o no existir al arrancar el rol): reintentar
	# hasta que la autoridad de interaccion quede aplicada en la instancia actual.
	# Solo cuando el offload esta comprometido: antes, la interaccion es local.
	if _engaged and not _interaction_authority_is_current():
		_set_player_interaction_authoritative(true)
	# Mismo caso para el congelamiento: una escena nueva (cambio de nivel) nace simulando.
	# Con current_scene en null (mitad de transicion) no hay nada que congelar todavia.
	var current_scene = get_tree().current_scene
	if _engaged and current_scene != null and not _freezer.frozen_root_is(current_scene):
		_freeze_local_simulation()

	# FD-316 (tarea G): el estado NO interpolable (interaccion, estados logicos,
	# velocidad/wish del animator, linterna) se aplica solo del snapshot mas nuevo, una
	# vez por snapshot. Las transforms (entidades, rig, camara) se interpolan por frame.
	var apply_started_us := OS.get_ticks_usec()
	if _has_new_snapshot and not _snap_to.empty():
		_has_new_snapshot = false
		_apply_snapshot_globals(_snap_to)
	if _engaged and _to_tick >= 0:
		_host_tick_rate = float(Engine.iterations_per_second) if Engine.iterations_per_second > 0 else 60.0
		_advance_render_clock(delta)
		var interp_started_us := OS.get_ticks_usec()
		_render_interpolated()
		_stats.add("interp_us", float(OS.get_ticks_usec() - interp_started_us))
	_stats.add("apply_us", float(poll_us + (OS.get_ticks_usec() - apply_started_us)))
	_stats.tally("apply_count")
	# El _physics_process del Pilot esta congelado: el animator se alimenta aca con la
	# velocidad de la autoridad que llego en el snapshot (si no, se queda en idle).
	if _engaged:
		var player = _get_player()
		if player != null and is_instance_valid(player) and player.has_method("step_remote_animator"):
			player.call("step_remote_animator", delta)
	_send_local_input()
	_flush_client_stats()
	_flush_profile(OS.get_ticks_msec())

# FD-316 (tarea G): el tiempo de render avanza en ticks del host y se mantiene dentro del
# par recibido: no se adelanta a lo que llego (nada de extrapolar) ni retrocede.
func _advance_render_clock(delta: float) -> void:
	if _to_tick < 0:
		return
	_render_tick += delta * _host_tick_rate
	if _render_tick > float(_to_tick):
		_render_tick = float(_to_tick)
	if _render_tick < float(_from_tick):
		_render_tick = float(_from_tick)

func _send_local_input() -> void:
	if _target_ip == "" or _target_port <= 0:
		return
	var sim_input = _build_local_input()
	# Instrumentacion (tarea E): guardar el instante de envio de este seq para cerrar el
	# RTT cuando la autoridad lo ackee.
	_record_sent_seq(int(sim_input.get("seq", 0)))
	var bytes = RemoteProtocol.encode_json(sim_input).to_utf8()
	_udp.set_dest_address(_target_ip, _target_port)
	_udp.put_packet(bytes)

# FD-316 (review bug 5): si el handheld pauso su arbol (menu de pausa, pausa rapida), no
# debe mandar movimiento/camara: el Input singleton no se pausa y el sim host seguiria
# moviendo al personaje detras del menu. En pausa se manda un frame NEUTRO (y se limpian
# los latches de flanco) para que la autoridad suelte el input; al despausar vuelve el
# frame del provider. La notificacion del congelado del nivel la manda RemoteControlManager.
func _build_local_input() -> Dictionary:
	var axes := {"move_x": 0.0, "move_y": 0.0, "analog": false}
	var buttons := {"jump": false, "interact": false, "sprint": false, "crouch": false}
	var camera := {"x": 0.0, "y": 0.0, "zoom": 0.0}
	var tree = get_tree()
	var paused: bool = tree != null and tree.paused
	if paused:
		_jump_latch = 0
		_interact_latch = 0
	else:
		# FD-316: el handheld manda SU frame ya procesado por el InputProvider local: el
		# move_vec con curva/sensibilidad, el auto-sprint analogico (vive en el provider, por
		# eso solo caminaba) y la camara (mouse, stick, D-pad con rampa, touch). La autoridad
		# lo suma tal cual sobre SU frame local.
		var player := _get_player()
		if player != null and is_instance_valid(player):
			var provider = player.get("input_provider") if "input_provider" in player else null
			if provider != null and provider.has_method("get_input"):
				var frame = provider.call("get_input")
				if frame != null:
					axes["move_x"] = frame.move_vec.x
					axes["move_y"] = frame.move_vec.y
					axes["analog"] = frame.analog_move_active
					buttons["jump"] = frame.jump
					buttons["sprint"] = frame.sprint
					buttons["crouch"] = frame.crouch
					buttons["interact"] = frame.interact or frame.interact_held
					camera["x"] = frame.mouse_delta.x
					camera["y"] = frame.mouse_delta.y
					camera["zoom"] = frame.zoom_delta
		buttons = _latch_flanked_buttons(buttons)
	return RemoteProtocol.create_sim_input(axes, buttons, _latest_applied_tick, _token, camera, _next_seq())

# FD-316: latch corto de jump/interact. Si el press se pierde con su datagrama, los
# siguientes paquetes ya traerian false y el tap desaparecia (bug 2 del review FD-316).
# Se repite el true FLANK_REPEAT_PACKETS paquetes; la autoridad deriva el flanco por
# transicion (interact_was_down / _jump_was_pressed), asi que repetir no lo duplica.
func _latch_flanked_buttons(buttons: Dictionary) -> Dictionary:
	if bool(buttons.get("jump", false)):
		_jump_latch = FLANK_REPEAT_PACKETS
	if bool(buttons.get("interact", false)):
		_interact_latch = FLANK_REPEAT_PACKETS
	var out: Dictionary = buttons.duplicate()
	if _jump_latch > 0:
		out["jump"] = true
		_jump_latch -= 1
	if _interact_latch > 0:
		out["interact"] = true
		_interact_latch -= 1
	return out

func _next_seq() -> int:
	_seq += 1
	return _seq

# FD-316: el control manda su look ("mouse_delta"/"touch_camera") a ESTE handheld. Como
# render-esclavo no simula, no alcanza con aplicarlo a su player: se mete en el
# InputProvider local para que lo procese igual que su propio hardware y salga en el
# frame procesado que viaja a la autoridad (ver _send_local_input).
func queue_camera_input(dx: float, dy: float, zoom: float = 0.0, is_touch: bool = false) -> void:
	var player := _get_player()
	if player == null or not is_instance_valid(player):
		return
	var provider = player.get("input_provider") if "input_provider" in player else null
	if provider == null:
		return
	if is_touch:
		if provider.has_method("add_touch_camera_drag"):
			provider.call("add_touch_camera_drag", Vector2(dx, dy))
		if provider.has_method("add_touch_camera_zoom"):
			provider.call("add_touch_camera_zoom", zoom)
	elif "mouse_delta_accum" in provider:
		provider.mouse_delta_accum += Vector2(dx, dy)

func _poll_udp() -> void:
	if _listening_port <= 0:
		return
	# FD-316 (tarea G): se drenan TODOS los datagramas del frame (para no acumular atraso en
	# el socket), pero solo se parsean los MAX_SNAPSHOTS_PER_FRAME mas recientes. El JSON
	# de los intermedios es lo que costaba los ~15 ms/frame en el Anbernic.
	var batch: Array = []
	var raw_total := 0
	while _udp.get_available_packet_count() > 0:
		var packet_ip = _udp.get_packet_ip()
		var pkt = _udp.get_packet()
		raw_total += 1
		# Stats de canal con TODO lo que llega: snap_hz/snap_bytes miden la red, no el
		# parseo (que ahora es acotado).
		_stats.tally("raw_snap")
		_stats.add("raw_bytes", float(pkt.size()))
		batch.append({"ip": packet_ip, "pkt": pkt})
		if batch.size() > MAX_SNAPSHOTS_PER_FRAME:
			batch.pop_front()
	if batch.empty():
		return
	# Los paquetes que el filtro descarto son un salto ESPERADO de tick, no perdida: el
	# primero conservado avanzo skipped+1 paquetes respecto del ultimo del frame anterior.
	var skipped: int = max(0, raw_total - batch.size())
	for i in range(batch.size()):
		var expected_packets: int = (skipped + 1) if i == 0 else 1
		var pkt_str: String = batch[i]["pkt"].get_string_from_utf8()
		var dict = RemoteProtocol.decode_json(pkt_str)
		_handle_udp_packet(String(batch[i]["ip"]), dict, batch[i]["pkt"].size(), expected_packets)

# FD-316: un snapshot sin el token de la sesion se descarta por completo: no se aplica
# ni se adopta su IP de origen como destino (suplantacion del sim host, riesgo "Sin auth").
func _handle_udp_packet(packet_ip: String, dict: Dictionary, packet_bytes: int = 0, expected_packets: int = 1) -> void:
	if String(dict.get("type", "")) != "sim_snapshot":
		return
	if not _snapshot_token_ok(dict):
		printerr("[RemoteSimClient] snapshot descartado: token invalido")
		return
	if packet_ip != "":
		_target_ip = packet_ip
	receive_snapshot(dict, packet_bytes, expected_packets)

# Sin token fijado (legacy/tests) se acepta cualquier snapshot.
func _snapshot_token_ok(snapshot: Dictionary) -> bool:
	if _token == "":
		return true
	return String(snapshot.get("token", "")) == _token

# Resuelve una ruta de entidad contra la escena actual; si no esta ahi, contra el arbol
# del cliente (compatibilidad con tests que no montan current_scene).
func _resolve_path(scene, path_str: String) -> Node:
	var node = scene.get_node_or_null(NodePath(path_str)) if scene != null else null
	if node == null:
		node = get_node_or_null(NodePath(path_str))
	return node

# Camino directo (tests, ensayo local): aplica estado logico + transforms de una vez, sin
# pasar por el reloj de interpolacion.
func _apply_snapshot(snapshot: Dictionary) -> void:
	_apply_snapshot_globals(snapshot)
	_apply_transform_pair(snapshot, snapshot, 0.0)
	emit_signal("snapshot_applied", int(snapshot.get("tick", 0)))

# FD-316 (tarea G): estado NO interpolable de un snapshot: visibilidad, luz, velocidad/
# wish del animator, linterna, interaccion y estados logicos. Se aplica solo del mas nuevo.
func _apply_snapshot_globals(snapshot: Dictionary) -> void:
	var tree = get_tree()
	if tree == null:
		return
	var scene = tree.current_scene

	var entities: Dictionary = snapshot.get("entities", {})
	if entities is Dictionary:
		for path_str in entities:
			var node = _resolve_path(scene, path_str)
			if node == null or not is_instance_valid(node):
				continue
			var state = entities[path_str]
			if not (state is Dictionary):
				continue
			if node is Spatial and state.has("v"):
				node.visible = bool(state["v"])
			if state.has("l_energy") and node is Light:
				node.light_energy = float(state["l_energy"])
			# FD-316: el render-esclavo no simula; la velocidad/piso reales vienen de
			# la autoridad para que el animator elija walk/run/aire en vez de idle.
			if state.has("vel") and node.has_method("set_remote_anim_state"):
				var v_arr = state["vel"]
				if v_arr is Array and v_arr.size() >= 3:
					var wish := Vector3.ZERO
					var w_arr = state.get("wish", null)
					if w_arr is Array and w_arr.size() >= 3:
						wish = Vector3(w_arr[0], w_arr[1], w_arr[2])
					node.call("set_remote_anim_state", Vector3(v_arr[0], v_arr[1], v_arr[2]), bool(state.get("g", false)), wish)
			# FD-316: el encendido/bateria de la linterna del casco son de la autoridad
			# (su orientacion la sigue el propio nodo desde la camara replicada).
			if state.has("flash"):
				var flash = node.get_node_or_null(RemoteProtocol.FLASHLIGHT_PATH)
				if flash != null and is_instance_valid(flash) and flash.has_method("apply_remote_state"):
					var f: Dictionary = state["flash"]
					flash.call("apply_remote_state", bool(f.get("on", false)), float(f.get("battery", 0.0)))

	var globals: Dictionary = snapshot.get("globals", {})
	# FD-316: interaccion resuelta por la autoridad (prompt + path del interactuable).
	var inter = globals.get("interact", null)
	if inter is Dictionary:
		_apply_player_interaction(String(inter.get("prompt", "")), String(inter.get("path", "")))
	# FD-316: estado logico de los actores (interactuables: switch de luces, valvulas,
	# ascensores). Se aplica solo cuando CAMBIA, para no re-disparar restores cada tick.
	var states = globals.get("states", null)
	if states is Dictionary:
		_apply_actor_states(states)
	if globals.has("arm_len"):
		_apply_arm_length(float(globals["arm_len"]))
	if globals.has("cam_fov"):
		var camera = tree.root.get_viewport().get_camera()
		if camera != null and is_instance_valid(camera):
			camera.fov = float(globals["cam_fov"])

# FD-316 (tarea G): interpola transforms de entidades, la cadena del rig y la camara
# entre dos snapshots. alpha 0 => from, 1 => to; si from == to (sin siguiente) sostiene.
func _apply_transform_pair(from_snap: Dictionary, to_snap: Dictionary, alpha: float) -> void:
	var tree = get_tree()
	if tree == null:
		return
	var scene = tree.current_scene

	var to_entities: Dictionary = to_snap.get("entities", {})
	var from_entities: Dictionary = from_snap.get("entities", {})
	if to_entities is Dictionary:
		for path_str in to_entities:
			var to_state = to_entities[path_str]
			if not (to_state is Dictionary) or not to_state.has("t"):
				continue
			var node = _resolve_path(scene, path_str)
			if node == null or not is_instance_valid(node) or not (node is Spatial):
				continue
			var t_to = RemoteProtocol.decode_transform(to_state["t"])
			var t_from = t_to
			if from_entities is Dictionary and from_entities.has(path_str):
				var from_state = from_entities[path_str]
				if from_state is Dictionary and from_state.has("t"):
					t_from = RemoteProtocol.decode_transform(from_state["t"])
			node.global_transform = t_from.interpolate_with(t_to, alpha)

	_apply_player_rig_interpolated(from_snap, to_snap, alpha)

	var to_globals: Dictionary = to_snap.get("globals", {})
	if to_globals is Dictionary and to_globals.has("cam_t"):
		var camera = tree.root.get_viewport().get_camera()
		if camera != null and is_instance_valid(camera):
			var t_to2 = RemoteProtocol.decode_transform(to_globals["cam_t"])
			var t_from2 = t_to2
			var from_globals: Dictionary = from_snap.get("globals", {})
			if from_globals is Dictionary and from_globals.has("cam_t"):
				t_from2 = RemoteProtocol.decode_transform(from_globals["cam_t"])
			camera.global_transform = t_from2.interpolate_with(t_to2, alpha)

# Tiempo de render actual (ticks del host) dentro del par [from_tick, to_tick].
func _interp_alpha() -> float:
	var span := _to_tick - _from_tick
	if span <= 0:
		return 0.0
	return clamp((_render_tick - float(_from_tick)) / float(span), 0.0, 1.0)

# FD-316 (tarea G): interpola el par recibido en el tiempo de render actual.
func _render_interpolated() -> void:
	if _snap_to.empty():
		return
	_apply_transform_pair(_snap_from, _snap_to, _interp_alpha())

# La cadena del rig la define RemoteProtocol.RIG_CHAIN (host y esclavo comparten una sola):
# el rig del Pilot se replica entero para que el esclavo no se quede con la pose de spawn.
func _apply_player_rig_interpolated(from_snap: Dictionary, to_snap: Dictionary, alpha: float) -> void:
	var to_globals: Dictionary = to_snap.get("globals", {})
	var to_rig = to_globals.get("rig", null)
	if not (to_rig is Array):
		return
	var player = _get_player()
	if player == null or not is_instance_valid(player):
		return
	var from_globals: Dictionary = from_snap.get("globals", {})
	var from_rig = from_globals.get("rig", null)
	var count: int = int(min(to_rig.size(), RemoteProtocol.RIG_CHAIN.size()))
	for i in range(count):
		if to_rig[i] == null:
			continue
		var node = player.get_node_or_null(RemoteProtocol.RIG_CHAIN[i])
		if node == null or not (node is Spatial):
			continue
		var t_to = RemoteProtocol.decode_transform(to_rig[i])
		var t_from = t_to
		if from_rig is Array and i < from_rig.size() and from_rig[i] != null:
			t_from = RemoteProtocol.decode_transform(from_rig[i])
		node.global_transform = t_from.interpolate_with(t_to, alpha)

func _apply_arm_length(length: float) -> void:
	if length < 0.0:
		return
	var player = _get_player()
	if player == null or not is_instance_valid(player):
		return
	var arm = player.get_node_or_null(RemoteProtocol.RIG_CHAIN[RemoteProtocol.RIG_CHAIN.size() - 1])
	if arm != null and "current_length" in arm:
		arm.current_length = length

# Restaura el estado logico de los actores replicados, solo si cambio desde la ultima
# aplicacion (el host manda el estado actual de todos; aca se filtra por diferencia).
var _last_actor_states: Dictionary = {}

func _apply_actor_states(states: Dictionary) -> void:
	var tree = get_tree()
	var scene = tree.current_scene if tree != null else null
	if scene == null:
		return
	for path_str in states:
		var incoming = states[path_str]
		var cached = _last_actor_states.get(path_str, null)
		if cached != null and RemoteProtocol.states_equal(cached, incoming):
			continue
		var node = scene.get_node_or_null(NodePath(path_str))
		if node == null:
			node = get_node_or_null(NodePath(path_str))
		if node == null or not is_instance_valid(node) or not node.has_method("restore_snapshot"):
			continue
		# Replicacion: si el actor ya esta en ese estado, no se le vuelve a llamar el
		# restore. Re-aplicarlo re-dispararia efectos one-shot (la apertura/sonido de la
		# escotilla del criopod al reconectar, por ejemplo).
		if node.has_method("get_snapshot") and RemoteProtocol.states_equal(node.call("get_snapshot"), incoming):
			_last_actor_states[path_str] = incoming
			continue
		node.call("restore_snapshot", incoming)
		_last_actor_states[path_str] = incoming

# --- FD-316 (tarea E): instrumentacion de lag y carga del render-esclavo ---

# Guarda el instante de envio de cada seq en un ring chico (los mas viejos sin ack se
# descartan). La ventana no puede crecer sin limite ni allocar por frame.
func _record_sent_seq(seq: int) -> void:
	if seq <= 0:
		return
	_sent_seq_ms[seq] = OS.get_ticks_msec()
	_sent_seq_order.append(seq)
	while _sent_seq_order.size() > RTT_RING_MAX:
		_sent_seq_ms.erase(_sent_seq_order.pop_front())

# Llamado por cada snapshot nuevo: cierra el RTT del ack_seq, mide el tamano del paquete,
# el gap entre snapshots y los ticks saltados (perdida de datagramas). `expected_packets`
# es el avance de paquetes que YA se esperaba desde el snapshot anterior (los que el
# filtro de 2 descarto, mas el intervalo `snap_step` del host): no cuenta como perdida.
func _stats_on_snapshot(tick: int, snapshot: Dictionary, packet_bytes: int, expected_packets: int = 1) -> void:
	_stats.tally("snap")
	var now_ms := OS.get_ticks_msec()
	if _stats_last_recv_ms > 0:
		_stats.observe_max("snap_gap_ms", float(now_ms - _stats_last_recv_ms))
	_stats_last_recv_ms = now_ms
	var globals: Dictionary = snapshot.get("globals", {})
	var step: int = 1
	if globals is Dictionary:
		step = int(max(1, int(globals.get("snap_step", 1))))
	if _stats_last_recv_tick >= 0 and tick > _stats_last_recv_tick:
		var expected := expected_packets * step
		var lost := tick - _stats_last_recv_tick - expected
		if lost > 0:
			_stats.tally("dropped_ticks", lost)
	if tick > _stats_last_recv_tick:
		_stats_last_recv_tick = tick
	if snapshot.has("ack_seq"):
		_stats_ack(int(snapshot["ack_seq"]))

# RTT input->snapshot: la autoridad ackea el ultimo seq aplicado y aca se resta contra el
# instante de envio, todo con el reloj local (no se comparan relojes entre maquinas).
func _stats_ack(seq: int) -> void:
	if seq <= 0:
		return
	var sent_ms = _sent_seq_ms.get(seq, null)
	if sent_ms == null:
		return
	_sent_seq_ms.erase(seq)
	_stats.add_sample("rtt_ms", float(OS.get_ticks_msec() - int(sent_ms)))

# Cierra la ventana cada RemoteSimStats.WINDOW_MS con UNA linea, publica el dict en
# last_stats (telemetria ANNAV2) y resetea los acumuladores para la ventana siguiente.
func _flush_client_stats() -> void:
	var now_ms := OS.get_ticks_msec()
	if not _stats.is_due(now_ms):
		return
	var elapsed_ms: int = _stats.elapsed_ms(now_ms)
	var elapsed_s: float = max(float(elapsed_ms) / 1000.0, 0.001)
	var frames: int = _stats.count("frame")
	var frame_den: int = max(frames, 1)
	# Tarea L: promedio por ventana del frame desglosado. render_ms_avg = frame - process
	# - physics es lo que queda para el render/driver, lo unico que el motor no mide
	# aparte (el objetivo de esta tarea es justamente ver donde se va el frame).
	var process_ms_avg: float = (_stats.sum("process_us") / float(frame_den)) / 1000.0
	var physics_ms_avg: float = (_stats.sum("physics_us") / float(frame_den)) / 1000.0
	var frame_ms_avg: float = float(elapsed_ms) / float(frame_den)
	var render_ms_avg: float = frame_ms_avg - process_ms_avg - physics_ms_avg
	# Tarea G: snap_hz/snap_bytes miden el canal (todo lo recibido), no el parseo, que
	# ahora esta acotado a 2 paquetes por frame.
	var raw_snaps: int = _stats.count("raw_snap")
	var stats := {
		"rtt_ms_p50": _stats.percentile("rtt_ms", 0.5),
		"rtt_ms_p95": _stats.percentile("rtt_ms", 0.95),
		"rtt_ms_max": _stats.percentile("rtt_ms", 1.0),
		"snap_hz": float(raw_snaps) / elapsed_s,
		"snap_gap_ms_max": _stats.max_value("snap_gap_ms"),
		"dropped_ticks": _stats.count("dropped_ticks"),
		"apply_ms_avg": (_stats.sum("apply_us") / float(max(_stats.count("apply_count"), 1))) / 1000.0,
		"interp_ms_avg": (_stats.sum("interp_us") / float(max(_stats.count("apply_count"), 1))) / 1000.0,
		"frame_ms_avg": frame_ms_avg,
		"fps": float(frames) / elapsed_s,
		"snap_bytes_avg": _stats.sum("raw_bytes") / float(max(raw_snaps, 1)),
		# Tarea L: contadores del motor promediados por ventana.
		"process_ms_avg": process_ms_avg,
		"physics_ms_avg": physics_ms_avg,
		"render_ms_avg": render_ms_avg,
		"draw_calls_avg": _stats.sum("draw_calls") / float(frame_den),
		"objects_in_frame_avg": _stats.sum("objects_in_frame") / float(frame_den),
		"vertices_in_frame_avg": _stats.sum("vertices_in_frame") / float(frame_den),
		"node_count_avg": _stats.sum("node_count") / float(frame_den)
	}
	last_stats = stats
	print("[RemoteSimClient] stats rtt_ms p50=", "%.1f" % stats["rtt_ms_p50"],
		" p95=", "%.1f" % stats["rtt_ms_p95"],
		" max=", "%.1f" % stats["rtt_ms_max"],
		" snap_hz=", "%.1f" % stats["snap_hz"],
		" snap_gap_ms_max=", "%.1f" % stats["snap_gap_ms_max"],
		" dropped_ticks=", stats["dropped_ticks"],
		" apply_ms_avg=", "%.3f" % stats["apply_ms_avg"],
		" interp_ms_avg=", "%.3f" % stats["interp_ms_avg"],
		" frame_ms_avg=", "%.1f" % stats["frame_ms_avg"],
		" fps=", "%.1f" % stats["fps"],
		" snap_bytes_avg=", "%.0f" % stats["snap_bytes_avg"],
		" process_ms=", "%.2f" % stats["process_ms_avg"],
		" physics_ms=", "%.2f" % stats["physics_ms_avg"],
		" render_ms=", "%.2f" % stats["render_ms_avg"],
		" draw_calls=", "%.0f" % stats["draw_calls_avg"],
		" objects_in_frame=", "%.0f" % stats["objects_in_frame_avg"],
		" vertices_in_frame=", "%.0f" % stats["vertices_in_frame_avg"],
		" nodes=", "%.0f" % stats["node_count_avg"])
	_stats.reset(now_ms)

# Tarea L: perfil opt-in del esclavo. Recorre el arbol UNA vez por ventana (no por frame)
# y agrupa por script los nodos con _process activo: con el nivel congelado, esos son los
# que siguen gastando CPU en el handheld. Imprime el top 10 por cantidad de nodos.
func _flush_profile(now_ms: int) -> void:
	if not _profile_enabled:
		return
	if _profile_last_ms > 0 and now_ms - _profile_last_ms < PROFILE_WINDOW_MS:
		return
	_profile_last_ms = now_ms
	var counts: Dictionary = _profile_script_counts()
	var entries: Array = []
	for script_path in counts:
		entries.append({"script": script_path, "count": int(counts[script_path])})
	entries.sort_custom(self, "_profile_sort_desc")
	var top: int = int(min(entries.size(), 10))
	print("[RemoteSimClient] profile _process activo: ", entries.size(),
		" scripts, top ", top)
	for i in range(top):
		print("  ", entries[i]["count"], " nodos  ", entries[i]["script"])

# Cuenta nodos con _process activo por script (path del recurso; los nodos sin script se
# agrupan bajo un rotulo). Pasada iterativa: sin recursion ni allocs por frame.
func _profile_script_counts() -> Dictionary:
	var counts: Dictionary = {}
	var tree = get_tree()
	if tree == null:
		return counts
	var stack: Array = [tree.root]
	while not stack.empty():
		var node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		if node.is_processing():
			var label := "<sin script>"
			var scr = node.get_script()
			if scr != null:
				label = String(scr.resource_path) if String(scr.resource_path) != "" else "<script en memoria>"
			counts[label] = int(counts.get(label, 0)) + 1
		for child in node.get_children():
			stack.append(child)
	return counts

func _profile_sort_desc(a, b) -> bool:
	return int(a["count"]) > int(b["count"])
