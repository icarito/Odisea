extends GdUnitTestSuite

# test_remote_sim.gd - FD-316: Tests for remote simulation protocol, snapshot buffer and offload roles.

const RemoteProtocolScript = preload("res://core_v2/net/RemoteProtocol.gd")
const RemoteSimHostScript = preload("res://core_v2/net/RemoteSimHost.gd")
const RemoteSimClientScript = preload("res://core_v2/net/RemoteSimClient.gd")
const SimLogicFreezeScript = preload("res://core_v2/net/SimLogicFreeze.gd")
const RemoteSimStatsScript = preload("res://core_v2/net/RemoteSimStats.gd")
const PlayerScript = preload("res://core_v2/player/PlayerControllerV2.gd")
const RemoteControlManagerScript = preload("res://core_v2/net/RemoteControlManager.gd")

func test_protocol_sim_messages_encode_decode():
	var hello = RemoteProtocolScript.create_sim_hello("res://scenes/TestScene.tscn", 60, "tok123")
	assert_str(hello["type"]).is_equal("sim_hello")
	assert_str(hello["scene"]).is_equal("res://scenes/TestScene.tscn")
	assert_int(hello["sim_fps"]).is_equal(60)
	assert_str(hello["token"]).is_equal("tok123")

	# FD-316: sim_hello completo — spawn (posicion/yaw), semilla de la corrida y
	# checkpoint del jugador sobreviven al viaje JSON (es el camino real por WS).
	var full_hello = RemoteProtocolScript.create_sim_hello(
		"res://core_v2/levels/interiors/Dome_Intro.tscn", 60, "tok316",
		{"position": [1.5, 2.0, -3.5], "yaw": 1.25}, 123456,
		{"player_snapshot": {"position": [1.5, 2.0, -3.5], "yaw": 1.25, "velocity": [0.0, 0.0, 0.0]}})
	var wire = RemoteProtocolScript.decode_json(RemoteProtocolScript.encode_json(full_hello))
	assert_str(wire["type"]).is_equal("sim_hello")
	assert_str(wire["scene"]).is_equal("res://core_v2/levels/interiors/Dome_Intro.tscn")
	assert_str(wire["token"]).is_equal("tok316")
	assert_int(int(wire["run_seed"])).is_equal(123456)
	assert_float(float(wire["spawn"]["position"][0])).is_equal_approx(1.5, 0.001)
	assert_float(float(wire["spawn"]["yaw"])).is_equal_approx(1.25, 0.001)
	assert_bool(wire["checkpoint"]["player_snapshot"].has("yaw")).is_true()

	var snapshot = RemoteProtocolScript.create_sim_snapshot(10, 1000, {"entity1": {}}, {"scene": "test"}, "tok123")
	assert_str(snapshot["type"]).is_equal("sim_snapshot")
	assert_int(snapshot["tick"]).is_equal(10)
	assert_int(snapshot["ts"]).is_equal(1000)
	assert_bool(snapshot["entities"].has("entity1")).is_true()

func test_protocol_transform_encode_decode():
	var t = Transform.IDENTITY
	t.origin = Vector3(1.5, 2.5, -3.5)
	var enc = RemoteProtocolScript.encode_transform(t)
	var dec = RemoteProtocolScript.decode_transform(enc)

	assert_float(dec.origin.x).is_equal_approx(1.5, 0.001)
	assert_float(dec.origin.y).is_equal_approx(2.5, 0.001)
	assert_float(dec.origin.z).is_equal_approx(-3.5, 0.001)

# FD-316 (tarea G): el cliente solo conserva los 2 snapshots mas nuevos (con interpolacion
# el resto no hace falta) y descarta viejos/duplicados por tick.
func test_render_slave_keeps_only_two_newest_snapshots():
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)

	var snap1 = RemoteProtocolScript.create_sim_snapshot(1, 100, {})
	var snap2 = RemoteProtocolScript.create_sim_snapshot(2, 116, {})
	var snap3 = RemoteProtocolScript.create_sim_snapshot(3, 133, {})

	# Receive out of order
	client.receive_snapshot(snap2)
	client.receive_snapshot(snap1)
	client.receive_snapshot(snap3)

	assert_int(client._buffer.size()).is_equal(2)
	assert_int(client._buffer[0]["tick"]).is_equal(2)
	assert_int(client._buffer[1]["tick"]).is_equal(3)
	assert_int(client._latest_applied_tick).is_equal(3)

	# Un duplicado del mas nuevo tampoco entra.
	client.receive_snapshot(snap3)
	assert_int(client._buffer.size()).is_equal(2)


# FD-316 (tarea G): con dos snapshots, el render a mitad del intervalo da el transform
# intermedio de la entidad y de la cadena del rig (Transform.interpolate_with).
func test_render_slave_interpolates_transforms_between_snapshots():
	var level_b := Spatial.new()
	level_b.name = "SimLevelG"
	var player_b = auto_free(FakePlayer.new())
	player_b.name = "Pilot"
	player_b.add_to_group("player")
	var rig_b := Spatial.new()
	rig_b.name = "CameraRig"
	player_b.add_child(rig_b)
	level_b.add_child(player_b)

	var previous_scene = get_tree().current_scene
	get_tree().root.add_child(level_b)
	get_tree().current_scene = level_b
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)
	client.start_render_slave(0)

	var t_a := Transform(Basis(), Vector3(0, 0, 0))
	var t_b := Transform(Basis(), Vector3(10, 0, 0))
	var rig_a := Transform(Basis(), Vector3(0, 2, 0))
	var rig_b_t := Transform(Basis(), Vector3(0, 4, 0))
	var snap_a = RemoteProtocolScript.create_sim_snapshot(1, 0, {
		"Pilot": {"t": RemoteProtocolScript.encode_transform(t_a)}
	}, {"rig": [RemoteProtocolScript.encode_transform(rig_a)]})
	var snap_b = RemoteProtocolScript.create_sim_snapshot(2, 16, {
		"Pilot": {"t": RemoteProtocolScript.encode_transform(t_b)}
	}, {"rig": [RemoteProtocolScript.encode_transform(rig_b_t)]})

	client.receive_snapshot(snap_a)
	client.receive_snapshot(snap_b)
	# Reloj de render en la mitad del intervalo: alpha 0.5.
	client._render_tick = 1.5
	client._render_interpolated()

	assert_vector3(player_b.global_transform.origin).is_equal_approx(
		Vector3(5, 0, 0), Vector3.ONE * 0.001)
	assert_vector3(rig_b.global_transform.origin).is_equal_approx(
		Vector3(0, 3, 0), Vector3.ONE * 0.001)

	client.stop_render_slave()
	if previous_scene != null:
		get_tree().current_scene = previous_scene


# FD-316 (tarea G): sin el siguiente snapshot se sostiene el ultimo (sin extrapolar), aun
# si el reloj de render se pasa del par recibido.
func test_render_slave_holds_last_transform_without_next_snapshot():
	var level_b := Spatial.new()
	level_b.name = "SimLevelHold"
	var player_b = auto_free(FakePlayer.new())
	player_b.name = "Pilot"
	player_b.add_to_group("player")
	level_b.add_child(player_b)

	var previous_scene = get_tree().current_scene
	get_tree().root.add_child(level_b)
	get_tree().current_scene = level_b
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)
	client.start_render_slave(0)

	var t_a := Transform(Basis(), Vector3(2, 0, 0))
	client.receive_snapshot(RemoteProtocolScript.create_sim_snapshot(1, 0, {
		"Pilot": {"t": RemoteProtocolScript.encode_transform(t_a)}
	}, {}))

	client._render_tick = 50.0
	client._render_interpolated()
	assert_vector3(player_b.global_transform.origin).is_equal_approx(
		Vector3(2, 0, 0), Vector3.ONE * 0.001)

	client.stop_render_slave()
	if previous_scene != null:
		get_tree().current_scene = previous_scene


# FD-316 (tarea G): con snapshots cada N ticks, el salto esperado (N-1 ticks) no cuenta
# como perdida; un hueco real si.
func test_render_slave_dropped_ticks_accounts_for_snap_step():
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)
	client.start_render_slave(0)

	# Primer snapshot: base (step 2, ticks 2/4/6...).
	client.receive_snapshot(RemoteProtocolScript.create_sim_snapshot(2, 0, {}, {"snap_step": 2}))
	assert_int(client._stats.count("dropped_ticks")).is_equal(0)
	# El siguiente esperado (tick 4) no suma perdida.
	client.receive_snapshot(RemoteProtocolScript.create_sim_snapshot(4, 0, {}, {"snap_step": 2}))
	assert_int(client._stats.count("dropped_ticks")).is_equal(0)
	# Hueco real: en vez del tick 6 llega el 10 -> 4 ticks perdidos.
	client.receive_snapshot(RemoteProtocolScript.create_sim_snapshot(10, 0, {}, {"snap_step": 2}))
	assert_int(client._stats.count("dropped_ticks")).is_equal(4)

	client.stop_render_slave()

func test_render_slave_toggles_role_flag():
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)

	client.start_render_slave(0)
	assert_bool(client.is_render_slave).is_true()

	client.stop_render_slave()
	assert_bool(client.is_render_slave).is_false()


# FD-316 paso 3: promover SOLO abre el canal. Fisica, audio e interaccion siguen
# locales hasta el primer snapshot valido: si el sim host nunca carga el nivel, el
# handheld sigue jugando su partida sin teletransportes ni silencios en vano.
func test_render_slave_does_not_engage_on_promotion():
	var audio = get_node("/root/AudioManager")
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)

	client.start_render_slave(0)
	assert_bool(client.is_render_slave).is_true()
	assert_bool(client.is_engaged()).is_false()
	assert_bool(audio._render_slave_audio_muted).is_false()
	assert_bool(client._interaction_authority_applied).is_false()

	# Un paquete sin tick no compromete el offload.
	client.receive_snapshot({"type": "sim_snapshot", "garbage": true})
	assert_bool(client.is_engaged()).is_false()
	assert_bool(audio._render_slave_audio_muted).is_false()

	# Salir sin haber recibido nada tampoco deja rastro.
	client.stop_render_slave()
	assert_bool(audio._render_slave_audio_muted).is_false()
	assert_bool(client._interaction_authority_applied).is_false()


# El primer snapshot valido compromete el offload: ahi si se apaga la fisica local
# (engagement), se mutea el bus Master y la interaccion pasa a la autoridad.
func test_render_slave_engages_on_first_valid_snapshot():
	var audio = get_node("/root/AudioManager")
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)

	# Player de reemplazo para que la cesion de interaccion tenga a quien aplicarse
	# (en la suite no hay jugador bajo current_scene). Se devuelve al salir.
	var player = auto_free(PlayerScript.new())
	var session = get_node("/root/SessionManager")
	var prev_player = session.player
	session.player = player

	player.set_physics_process(true)
	client.start_render_slave(0)
	client.receive_snapshot(RemoteProtocolScript.create_sim_snapshot(7, 100, {}, {"scene": "x"}, "t"))
	assert_bool(client.is_engaged()).is_true()
	assert_bool(audio._render_slave_audio_muted).is_true()
	assert_bool(client._interaction_authority_applied).is_true()
	assert_bool(player.is_remote_render_slave()).is_true()
	# El controlador local (y su CameraRig) no simula encima de los snapshots.
	assert_bool(player.is_physics_processing()).is_false()

	client.stop_render_slave()
	assert_bool(client.is_engaged()).is_false()
	assert_bool(audio._render_slave_audio_muted).is_false()
	assert_bool(client._interaction_authority_applied).is_false()
	assert_bool(player.is_remote_render_slave()).is_false()
	assert_bool(player.is_physics_processing()).is_true()
	session.player = prev_player


# FD-316 paso 2/3: el sim host solo emite cuando el nivel del esclavo esta cargado
# (sim_hello aplicado -> sim_ready). Antes de eso no hay tick ni snapshot: capturar
# RemoteControlHome era el bug original (promocion a autoridad vacia).
var _emitted_snapshots: Array = []

func _on_snapshot_generated(snapshot) -> void:
	_emitted_snapshots.append(snapshot)

func test_sim_host_does_not_emit_before_sim_ready():
	_emitted_snapshots.clear()
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)
	host.connect("snapshot_generated", self, "_on_snapshot_generated")

	host.start_simulation("127.0.0.1", 0)
	assert_bool(host.active).is_true()
	assert_bool(host.sim_ready).is_false()
	# Ticks sin nivel: nada se emite, nada se captura.
	host._physics_process(1.0 / 60.0)
	host._physics_process(1.0 / 60.0)
	assert_int(_emitted_snapshots.size()).is_equal(0)

	# Llega el nivel (seam: escena ya instanciada, como dejaria load_sim_level):
	# recien entonces el tick produce un snapshot. Tarea G: con snapshot_every_n_ticks=2
	# (default, 30 Hz) el tick impar no emite; el par si.
	assert_bool(host._attach_sim_level(_make_sim_level(), {})).is_true()
	assert_bool(host.sim_ready).is_true()
	host._physics_process(1.0 / 60.0)
	assert_int(_emitted_snapshots.size()).is_equal(0)
	host._physics_process(1.0 / 60.0)
	assert_int(_emitted_snapshots.size()).is_equal(1)
	assert_int(int(_emitted_snapshots[0]["tick"])).is_equal(2)

	host.stop_simulation()
	assert_bool(host.sim_ready).is_false()


# FD-316 (tarea G): snapshot_every_n_ticks espacia la emision sin frenar la simulacion, y
# snap_step viaja en globals para que el esclavo no cuente el salto esperado como perdida.
func test_sim_host_snapshot_rate_is_configurable():
	_emitted_snapshots.clear()
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)
	host.connect("snapshot_generated", self, "_on_snapshot_generated")
	host.snapshot_every_n_ticks = 3
	host.start_simulation("127.0.0.1", 0)
	assert_bool(host._attach_sim_level(_make_sim_level(), {})).is_true()

	# 6 ticks con emision cada 3: los snapshots salen en los ticks 3 y 6.
	for _i in range(6):
		host._physics_process(1.0 / 60.0)
	assert_int(_emitted_snapshots.size()).is_equal(2)
	assert_int(int(_emitted_snapshots[0]["tick"])).is_equal(3)
	assert_int(int(_emitted_snapshots[1]["tick"])).is_equal(6)
	assert_int(int(_emitted_snapshots[0]["globals"]["snap_step"])).is_equal(3)

	# La simulacion no se frena: los ticks corrieron 6 aunque solo se emitieran 2.
	assert_int(host._current_tick).is_equal(6)

	host.stop_simulation()


# FD-316 (tarea G): con adapt_snapshot_rate el host deriva el paso del fps del esclavo
# (~1.4x su ritmo) y cae al valor configurado si no hay datos o el adaptativo esta off.
# Tarea L: el paso nunca pasa del piso de 30 Hz (a 60 Hz de host, N<=2).
func test_sim_host_adapts_snapshot_step_to_client_rate():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)
	host.snapshot_every_n_ticks = 2
	host.adapt_snapshot_rate = true

	# Esclavo a 10 fps: el adaptativo apuntaria a ~15 Hz, pero el piso de 30 Hz lo
	# limita a N=2.
	host._update_active_snap_step(10.0)
	assert_int(host._active_snap_step).is_equal(2)
	# Esclavo a 30 fps => ya alcanza 60 Hz => N=1.
	host._update_active_snap_step(30.0)
	assert_int(host._active_snap_step).is_equal(1)
	# Sin datos del esclavo cae al valor configurado.
	host._update_active_snap_step(0.0)
	assert_int(host._active_snap_step).is_equal(2)

	# Adaptativo desactivado: siempre el valor configurado.
	host.adapt_snapshot_rate = false
	host._update_active_snap_step(10.0)
	assert_int(host._active_snap_step).is_equal(2)


# FD-316 (tarea L): piso de 30 Hz del ritmo adaptativo. Aunque el esclavo caiga a 5 fps,
# el host no emite por debajo de 30 Hz (N <= host_hz/30); a mas fps del esclavo sube la
# tasa, por encima del piso.
func test_sim_host_adaptive_rate_has_30hz_floor():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)
	host.adapt_snapshot_rate = true
	host.snapshot_every_n_ticks = 2

	host._update_active_snap_step(5.0)
	assert_int(host._active_snap_step).is_equal(2)
	host._update_active_snap_step(1.5)
	assert_int(host._active_snap_step).is_equal(2)
	# Mas fps que el piso: 60 Hz de emision (N=1).
	host._update_active_snap_step(30.0)
	assert_int(host._active_snap_step).is_equal(1)


# FD-316: las entidades viajan con rutas relativas al nivel simulado (el esclavo las
# resuelve contra SU current_scene), y la camara es la del nivel, no la del UI.
func test_sim_host_snapshot_paths_relative_to_sim_level():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)

	var level = _make_sim_level()
	var pod: Spatial = auto_free(Spatial.new())
	pod.name = "CoolantPod"
	pod.add_to_group("replay_sync")
	pod.translation = Vector3(4, 5, 6)
	level.add_child(pod)
	pod.owner = level

	assert_bool(host._attach_sim_level(level, {})).is_true()
	var snap = host.capture_snapshot()
	assert_bool(snap["entities"].has("CoolantPod")).is_true()
	var enc: Dictionary = snap["entities"]["CoolantPod"]["t"]
	assert_float(enc["p"][0]).is_equal_approx(4.0, 0.001)
	# El nivel (sin camara propia) no agrega cam_t: el esclavo conserva la suya.
	assert_bool(snap["globals"].has("cam_t")).is_false()

	host.stop_simulation()


# Nivel de simulacion minimo para el sim host: raiz + jugador (sim_ready lo exige).
# El fake va SOLO en "player", como el Pilot real (que no esta en replay_sync).
func _make_sim_level() -> Spatial:
	var level := Spatial.new()
	level.name = "SimLevel"
	var fake = auto_free(FakePlayer.new())
	fake.name = "Player"
	fake.add_to_group("player")
	level.add_child(fake)
	fake.owner = level
	return level


# sim_hello con escena inexistente (o con la simulacion inactiva) no deja el host
# "listo": sin sim_ready no hay emision y el esclavo nunca se compromete.
func test_load_sim_level_rejects_invalid_requests():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)

	# Sin start_simulation: nada hace.
	assert_bool(host.load_sim_level({"scene": "res://core_v2/tests/test_remote_sim.gd", "run_seed": 1})).is_false()
	assert_bool(host.sim_ready).is_false()

	host.start_simulation("127.0.0.1", 0)
	assert_bool(host.load_sim_level({"scene": "res://no_existe/NivelFantasma.tscn", "run_seed": 1})).is_false()
	assert_bool(host.sim_ready).is_false()
	assert_object(host._sim_level).is_null()

func test_sim_host_captures_snapshot():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)

	var spatial = auto_free(Spatial.new())
	spatial.name = "TestNode"
	spatial.add_to_group("replay_sync")
	spatial.translation = Vector3(10, 0, 0)
	add_child(spatial)

	var snap = host.capture_snapshot()
	assert_str(snap["type"]).is_equal("sim_snapshot")
	assert_bool(snap.has("entities")).is_true()

# FD-316: la interaccion viaja en globals (la resuelve la autoridad; el host la muestra).
func test_sim_snapshot_carries_interaction_globals():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)

	var snap = host.capture_snapshot()
	assert_bool(snap["globals"].has("interact")).is_true()
	assert_bool(snap["globals"]["interact"] is Dictionary).is_true()
	assert_bool(snap["globals"]["interact"].has("prompt")).is_true()
	assert_bool(snap["globals"]["interact"].has("path")).is_true()

func test_sim_input_encode_decode():
	var axes = {"move_x": 1.0, "move_y": 0.0}
	var buttons = {"jump": true, "interact": false}
	var sim_input = RemoteProtocolScript.create_sim_input(axes, buttons, 42, "tok_test", {}, 7)

	assert_str(sim_input["type"]).is_equal("sim_input")
	assert_float(sim_input["axes"]["move_x"]).is_equal(1.0)
	assert_bool(sim_input["buttons"]["jump"]).is_true()
	assert_int(sim_input["last_tick"]).is_equal(42)
	# FD-316: el seq monotono del esclavo sobrevive el viaje JSON (dedupe del host).
	assert_int(int(sim_input["seq"])).is_equal(7)

	# FD-316: el look de camara viaja en su propio campo (no es accion del InputMap).
	var with_camera = RemoteProtocolScript.create_sim_input(axes, buttons, 43, "tok_test",
		{"x": 3.0, "y": -2.0, "zoom": 0.25})
	var wire = RemoteProtocolScript.decode_json(RemoteProtocolScript.encode_json(with_camera))
	assert_float(float(wire["camera"]["x"])).is_equal_approx(3.0, 0.001)
	assert_float(float(wire["camera"]["zoom"])).is_equal_approx(0.25, 0.001)

class FakePlayer extends Spatial:
	var velocity := Vector3(0, 0, 3)
	func is_effectively_grounded() -> bool:
		return true


class FakeArm extends Spatial:
	var current_length := 4.5


class FakeWishPlayer extends Spatial:
	var velocity := Vector3(0, 0, 3)
	func is_effectively_grounded() -> bool:
		return true
	func get_wish_direction() -> Vector3:
		return Vector3(1, 0, 0)


class FakeRemoteAnimPlayer extends Spatial:
	var last_wish := Vector3.ZERO
	var got_state := false
	func set_remote_anim_state(_v: Vector3, _g: bool, w: Vector3 = Vector3.ZERO) -> void:
		last_wish = w
		got_state = true


class FakeSwitchActor extends Spatial:
	var state := {"switch_active": false}
	var applied: Array = []
	func get_snapshot() -> Dictionary:
		return state.duplicate()
	func restore_snapshot(d: Dictionary) -> void:
		applied.append(d)
		state = d.duplicate()


# FD-316 (D2): componente de logica puro en replay_sync, sin transform. Asi es
# RingHubLightState (Node, no Spatial), el dueno de las luces del domo que acciona el
# PedestalLight: su estado tiene que replicarse igual que el de un prop Spatial.
class FakeLogicActor extends Node:
	var state := {"lit": false}
	var applied: Array = []
	func get_snapshot() -> Dictionary:
		return state.duplicate()
	func restore_snapshot(d: Dictionary) -> void:
		applied.append(d)
		state = d.duplicate()


# FD-316 (tarea J): replica el contrato de RingHubWakeup para el despertar del criopod. La
# decision de correr la intro es por el dato explicito `wakeup_completed` (que viaja en el
# snapshot del nivel), no por `gated_oys_script` vacio: usarlo de proxy dejaba al jugador
# encerrado. `open_pod_terminal` es el equivalente de RingHubWakeup._open_pod_terminal.
class FakeWakeupActor extends Spatial:
	var wakeup_completed := false
	var gated_oys_script := ""
	var intro_runs := 0
	var hatch_open := false
	func get_snapshot() -> Dictionary:
		return {"wakeup_completed": wakeup_completed, "gated_oys_script": gated_oys_script}
	func restore_snapshot(d: Dictionary) -> void:
		wakeup_completed = bool(d.get("wakeup_completed", wakeup_completed))
		gated_oys_script = String(d.get("gated_oys_script", gated_oys_script))
	func open_pod_terminal() -> void:
		if wakeup_completed:
			return
		intro_runs += 1
		# La cinematica es la que abre la escotilla; al terminar queda completado.
		wakeup_completed = true
		gated_oys_script = ""
		hatch_open = true


# FD-316 (tarea J): la linterna del casco no esta en replay_sync; su encendido/bateria viajan en el
# estado del jugador (ver RemoteSimHost.capture_snapshot / RemoteSimClient._apply_snapshot).
class FakeFlashlight extends Spatial:
	var enabled := true
	var battery := 42.0
	var toggles := 0
	func toggle() -> void:
		toggles += 1
		enabled = not enabled


class FakeFlashPlayer extends Spatial:
	var velocity := Vector3(0, 0, 3)
	func is_effectively_grounded() -> bool:
		return true


class FakeRemoteFlashlight extends Spatial:
	var applied: Array = []
	func apply_remote_state(on: bool, battery: float) -> void:
		applied.append({"on": on, "battery": battery})


class FakeRemoteFlashPlayer extends Spatial:
	var last_wish := Vector3.ZERO
	func set_remote_anim_state(_v: Vector3, _g: bool, w: Vector3 = Vector3.ZERO) -> void:
		last_wish = w


class FakeProvider extends Reference:
	var hardware_look_sensitivity := 1.0
	# Lee el Input real igual que InputProviderV2: asi el ensayo ejercita el merge del
	# input local del control (acciones) con el del handheld (sim_input).
	func get_input() -> InputDataV2:
		var d := InputDataV2.new()
		d.move_vec = Vector2(
			Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
			Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
		)
		d.jump = Input.is_action_pressed("jump")
		return d


class FakeInjectPlayer extends Spatial:
	var input_provider = FakeProvider.new()
	var injected: Array = []
	func inject_input(d: Dictionary) -> void:
		injected.append(d)
	func is_effectively_grounded() -> bool:
		return true


# FD-316: el look del handheld llega ya PROCESADO por su InputProvider (mouse, stick,
# D-pad digital con rampa, touch) y la autoridad lo suma tal cual al frame inyectado.
func test_sim_host_injects_client_look_in_input_frame():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)

	var player = auto_free(FakeInjectPlayer.new())
	player.add_to_group("player")
	host._sim_player = player

	host.receive_sim_input(RemoteProtocolScript.create_sim_input({"move_x": 0.0}, {"jump": false}, 1,
		"", {"x": 3.0, "y": -2.0, "zoom": 0.25}), "client")
	host._process_input_queue_for_tick(1)
	host._apply_authority_input_frame()

	assert_int(player.injected.size()).is_equal(1)
	var d: Dictionary = player.injected[0]
	assert_float(float(d["mouse_delta"][0])).is_equal_approx(3.0, 0.001)
	assert_float(float(d["mouse_delta"][1])).is_equal_approx(-2.0, 0.001)
	assert_float(float(d["zoom_delta"])).is_equal_approx(0.25, 0.001)

	host.stop_simulation()


# FD-316: ejes y botones del handheld se fusionan sobre el frame local y NO se
# materializan como acciones globales del Input (eso ensuciaba el input del control).
func test_sim_host_injects_merged_input_without_touching_global_input():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)

	var player = auto_free(FakeInjectPlayer.new())
	player.add_to_group("player")
	host._sim_player = player

	host.receive_sim_input(RemoteProtocolScript.create_sim_input(
		{"move_x": 0.5, "move_y": 0.25}, {"jump": true, "interact": true}, 1, "", {}, 1), "client")
	host._process_input_queue_for_tick(1)
	host._apply_authority_input_frame()

	assert_int(player.injected.size()).is_equal(1)
	var d: Dictionary = player.injected[0]
	assert_float(float(d["move_vec"][0])).is_equal_approx(0.5, 0.001)
	assert_float(float(d["move_vec"][1])).is_equal_approx(0.25, 0.001)
	assert_bool(d["jump"]).is_true()
	assert_bool(d["interact"]).is_true()
	assert_bool(d["interact_held"]).is_true()

	# El input global del control queda intacto.
	assert_bool(Input.is_action_pressed("move_right")).is_false()
	assert_bool(Input.is_action_pressed("interact")).is_false()

	# El handheld suelta: el proximo frame ya no trae sus intents.
	host.receive_sim_input(RemoteProtocolScript.create_sim_input(
		{"move_x": 0.0, "move_y": 0.0}, {"jump": false, "interact": false}, 2, "", {}, 2), "client")
	host._process_input_queue_for_tick(2)
	host._apply_authority_input_frame()
	var d2: Dictionary = player.injected[1]
	assert_float(float(d2["move_vec"][0])).is_equal_approx(0.0, 0.001)
	assert_bool(d2["jump"]).is_false()
	assert_bool(d2["interact"]).is_false()

	host.stop_simulation()


# FD-316: el snapshot lleva velocidad/grounded del jugador para que el render-esclavo
# elija la animacion correcta (alla no hay simulacion local).
func test_sim_snapshot_carries_player_motion():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)

	var fake = auto_free(FakePlayer.new())
	fake.name = "FakePlayer"
	add_child(fake)
	fake.add_to_group("player")
	fake.add_to_group("replay_sync")

	var snap = host.capture_snapshot()
	var found := false
	for path_str in snap["entities"]:
		if String(path_str).find("FakePlayer") != -1:
			var state: Dictionary = snap["entities"][path_str]
			assert_bool(state.has("vel")).is_true()
			assert_bool(state.has("g")).is_true()
			assert_bool(state["g"]).is_true()
			assert_float(state["vel"][2]).is_equal_approx(3.0, 0.001)
			found = true
	assert_bool(found).is_true()


# FD-316: el Pilot real NO esta en replay_sync (solo sus hijos ControllerManager/
# MultiTool lo estan), asi que el grupo nunca queda vacio y el fallback viejo al grupo
# "player" no disparaba: el jugador no viajaba en el snapshot y en el handheld se
# perdia el mesh (quedaba en el spawn) mientras la camara seguia a la autoridad.
func test_sim_snapshot_includes_player_outside_replay_sync():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)

	var level = _make_sim_level()
	# Un replay_sync del nivel: llena el grupo y descarta el fallback viejo.
	var prop: Spatial = auto_free(Spatial.new())
	prop.name = "CoolantPod"
	prop.add_to_group("replay_sync")
	level.add_child(prop)
	prop.owner = level

	assert_bool(host._attach_sim_level(level, {})).is_true()
	var snap = host.capture_snapshot()
	assert_bool(snap["entities"].has("Player")).is_true()
	var state: Dictionary = snap["entities"]["Player"]
	assert_bool(state.has("t")).is_true()
	assert_bool(state.has("vel")).is_true()
	assert_float(state["vel"][2]).is_equal_approx(3.0, 0.001)

	host.stop_simulation()


# FD-316: ademas de la camara final (cam_t), el snapshot lleva el rig COMPLETO del
# jugador (CameraRig/Yaw/Pitch/OTS/SpringArm) y el largo del kinematic arm. Sin esto el
# esclavo se quedaba con el rig en la pose de spawn y divergia de la autoridad.
func test_sim_snapshot_carries_player_rig_and_arm_length():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)

	var level := Spatial.new()
	level.name = "SimLevel"
	var player = auto_free(FakePlayer.new())
	player.name = "Pilot"
	player.add_to_group("player")
	var rig := Spatial.new()
	rig.name = "CameraRig"
	var yaw := Spatial.new()
	yaw.name = "Yaw"
	var pitch := Spatial.new()
	pitch.name = "Pitch"
	var ots := Spatial.new()
	ots.name = "OTS_Offset"
	var arm := FakeArm.new()
	arm.name = "SpringArm"
	player.add_child(rig)
	rig.add_child(yaw)
	yaw.add_child(pitch)
	pitch.add_child(ots)
	ots.add_child(arm)
	level.add_child(player)
	player.owner = level

	assert_bool(host._attach_sim_level(level, {})).is_true()
	var snap = host.capture_snapshot()
	assert_bool(snap["globals"].has("rig")).is_true()
	assert_int(snap["globals"]["rig"].size()).is_equal(5)
	assert_float(float(snap["globals"]["arm_len"])).is_equal_approx(4.5, 0.001)
	host.stop_simulation()


# FD-316: ENSAYO LOCAL del pipeline completo, sin devices: host (autoridad) y esclavo en
# el mismo arbol. Verifica (1) que el input del control y el del handheld terminen en UN
# frame inyectado a la autoridad, y (2) que el esclavo reproduzca player + rig + largo del
# arm + camara exactamente lo que la autoridad tenia al capturar el snapshot. Es el banco
# para debuggear la coherencia de las dos mitades por separado.
func test_local_rehearsal_pipeline_matches_authority():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)
	host.start_simulation("127.0.0.1", 0)

	# --- lado autoridad ---
	var level_a := Spatial.new()
	level_a.name = "SimLevelA"
	var player_a = auto_free(FakeInjectPlayer.new())
	player_a.name = "Pilot"
	player_a.add_to_group("player")
	var rig_a := Spatial.new()
	rig_a.name = "CameraRig"
	rig_a.rotation.y = 0.7
	var yaw_a := Spatial.new()
	yaw_a.name = "Yaw"
	var pitch_a := Spatial.new()
	pitch_a.name = "Pitch"
	var ots_a := Spatial.new()
	ots_a.name = "OTS_Offset"
	var arm_a := FakeArm.new()
	arm_a.name = "SpringArm"
	arm_a.current_length = 3.3
	var cam_a := Camera.new()
	cam_a.name = "Camera"
	player_a.add_child(rig_a)
	rig_a.add_child(yaw_a)
	yaw_a.add_child(pitch_a)
	pitch_a.add_child(ots_a)
	ots_a.add_child(arm_a)
	arm_a.add_child(cam_a)
	level_a.add_child(player_a)
	player_a.owner = level_a

	assert_bool(host._attach_sim_level(level_a, {})).is_true()
	cam_a.current = true

	# Input del handheld (su frame YA procesado por su provider: auto-sprint analogico
	# incluido) + input del control (acciones locales del Input).
	host.receive_sim_input(RemoteProtocolScript.create_sim_input(
		{"move_x": 0.5, "analog": true}, {"jump": true, "sprint": true}, 1), "client")
	Input.action_press("move_forward", 0.5)
	host._current_tick = 1
	host._process_input_queue_for_tick(1)
	host._apply_authority_input_frame()
	var snap = host.capture_snapshot()
	Input.action_release("move_forward")

	# (1) ambas fuentes en un solo frame inyectado a la autoridad.
	assert_int(player_a.injected.size()).is_equal(1)
	var frame: Dictionary = player_a.injected[0]
	assert_float(float(frame["move_vec"][0])).is_equal_approx(0.5, 0.001)
	assert_float(float(frame["move_vec"][1])).is_equal_approx(-0.5, 0.001)
	assert_bool(frame["jump"]).is_true()
	assert_bool(frame["sprint"]).is_true()
	assert_bool(frame["analog_move_active"]).is_true()

	# --- lado esclavo: misma escena, otra instancia ---
	var level_b := Spatial.new()
	level_b.name = "SimLevelB"
	var player_b = auto_free(FakePlayer.new())
	player_b.name = "Pilot"
	player_b.add_to_group("player")
	var rig_b := Spatial.new()
	rig_b.name = "CameraRig"
	var yaw_b := Spatial.new()
	yaw_b.name = "Yaw"
	var pitch_b := Spatial.new()
	pitch_b.name = "Pitch"
	var ots_b := Spatial.new()
	ots_b.name = "OTS_Offset"
	var arm_b := FakeArm.new()
	arm_b.name = "SpringArm"
	var cam_b := Camera.new()
	cam_b.name = "Camera"
	player_b.add_child(rig_b)
	rig_b.add_child(yaw_b)
	yaw_b.add_child(pitch_b)
	pitch_b.add_child(ots_b)
	ots_b.add_child(arm_b)
	ots_b.add_child(cam_b)
	level_b.add_child(player_b)

	var previous_scene = get_tree().current_scene
	# El nivel esclavo cuelga de root (como en el juego real): current_scene no acepta
	# nodos que no sean hijos directos de root (ERR silencioso del setter en Godot 3).
	get_tree().root.add_child(level_b)
	get_tree().current_scene = level_b
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)
	client._apply_snapshot(snap)

	# (2) el esclavo reproduce player, rig, arm y camara de la autoridad.
	assert_vector3(player_b.global_transform.origin).is_equal_approx(
		player_a.global_transform.origin, Vector3.ONE * 0.001)
	assert_vector3(rig_b.global_transform.origin).is_equal_approx(
		rig_a.global_transform.origin, Vector3.ONE * 0.001)
	assert_float(arm_b.current_length).is_equal_approx(3.3, 0.001)
	var cam_diff: Vector3 = cam_b.global_transform.origin - cam_a.global_transform.origin
	assert_vector3(cam_diff).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)

	if previous_scene != null:
		get_tree().current_scene = previous_scene
	host.stop_simulation()


# FD-316: la direccion de caminar (wish) viaja con el player y el estado logico de los
# interactuables viaja aparte. Sin esto el cuerpo del esclavo no se orienta (se
# "resetea") y los switches/luces no se replican (el pedestal quedaba apagado).
func test_snapshot_carries_wish_and_actor_states():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)

	var level := Spatial.new()
	level.name = "SimLevel"
	var player = auto_free(FakeWishPlayer.new())
	player.name = "Pilot"
	player.add_to_group("player")
	var switch_actor = auto_free(FakeSwitchActor.new())
	switch_actor.name = "PedestalLight"
	switch_actor.add_to_group("replay_sync")
	switch_actor.state = {"switch_active": true}
	level.add_child(player)
	level.add_child(switch_actor)

	assert_bool(host._attach_sim_level(level, {})).is_true()
	var snap = host.capture_snapshot()

	assert_bool(snap["entities"]["Pilot"].has("wish")).is_true()
	assert_float(float(snap["entities"]["Pilot"]["wish"][0])).is_equal_approx(1.0, 0.001)
	assert_bool(snap["globals"].has("states")).is_true()
	assert_bool(snap["globals"]["states"].has("PedestalLight")).is_true()
	assert_bool(bool(snap["globals"]["states"]["PedestalLight"]["switch_active"])).is_true()

	host.stop_simulation()


func test_render_slave_applies_remote_wish_and_actor_state_on_change():
	var level_b := Spatial.new()
	level_b.name = "SimLevelB"
	var player_b = auto_free(FakeRemoteAnimPlayer.new())
	player_b.name = "Pilot"
	player_b.add_to_group("player")
	var switch_b = auto_free(FakeSwitchActor.new())
	switch_b.name = "PedestalLight"
	level_b.add_child(player_b)
	level_b.add_child(switch_b)

	var previous_scene = get_tree().current_scene
	get_tree().root.add_child(level_b)
	get_tree().current_scene = level_b
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)

	client._apply_snapshot({"tick": 1, "entities": {
		"Pilot": {"vel": [0, 0, 3], "g": true, "wish": [1, 0, 0]}
	}, "globals": {"states": {"PedestalLight": {"switch_active": true}}}})

	assert_bool(player_b.got_state).is_true()
	assert_vector3(player_b.last_wish).is_equal_approx(Vector3(1, 0, 0), Vector3.ONE * 0.001)
	assert_int(switch_b.applied.size()).is_equal(1)

	# Mismo estado: no se re-aplica (no re-dispara el restore cada tick).
	client._apply_snapshot({"tick": 2, "entities": {}, "globals": {"states": {"PedestalLight": {"switch_active": true}}}})
	assert_int(switch_b.applied.size()).is_equal(1)
	# Estado distinto: se aplica.
	client._apply_snapshot({"tick": 3, "entities": {}, "globals": {"states": {"PedestalLight": {"switch_active": false}}}})
	assert_int(switch_b.applied.size()).is_equal(2)

	if previous_scene != null:
		get_tree().current_scene = previous_scene


# FD-316 (D2): el estado logico de un replay_sync NO Spatial (RingHubLightState es un
# Node, no un Spatial) viaja igual en globals.states. Antes se filtraba por
# "node is Spatial" y su get_snapshot no entraba al snapshot: la autoridad encendia las
# luces del domo con el PedestalLight y el esclavo las conservaba apagadas.
func test_snapshot_carries_non_spatial_actor_states():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)

	var level := Spatial.new()
	level.name = "SimLevel"
	var player = auto_free(FakeWishPlayer.new())
	player.name = "Pilot"
	player.add_to_group("player")
	var light_state = auto_free(FakeLogicActor.new())
	light_state.name = "LightState"
	light_state.add_to_group("replay_sync")
	light_state.state = {"lit": true}
	level.add_child(player)
	level.add_child(light_state)

	assert_bool(host._attach_sim_level(level, {})).is_true()
	var snap = host.capture_snapshot()

	assert_bool(snap["globals"].has("states")).is_true()
	assert_bool(snap["globals"]["states"].has("LightState")).is_true()
	assert_bool(bool(snap["globals"]["states"]["LightState"]["lit"])).is_true()
	# Sin transform no entra en entities: de ese nodo solo viaja el estado logico.
	assert_bool(snap["entities"].has("LightState")).is_false()

	host.stop_simulation()


# FD-316 (D2): el esclavo aplica el estado logico de un actor NO Spatial igual que el de
# un prop: la resolucion del path contra current_scene y el restore no dependen del tipo.
func test_render_slave_applies_non_spatial_actor_state():
	var level_b := Spatial.new()
	level_b.name = "SimLevelB"
	var light_b = auto_free(FakeLogicActor.new())
	light_b.name = "LightState"
	level_b.add_child(light_b)

	var previous_scene = get_tree().current_scene
	get_tree().root.add_child(level_b)
	get_tree().current_scene = level_b
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)

	client._apply_snapshot({"tick": 1, "entities": {}, "globals": {"states": {"LightState": {"lit": true}}}})
	assert_int(light_b.applied.size()).is_equal(1)
	assert_bool(bool(light_b.state["lit"])).is_true()
	# Mismo estado: no se re-aplica cada tick.
	client._apply_snapshot({"tick": 2, "entities": {}, "globals": {"states": {"LightState": {"lit": true}}}})
	assert_int(light_b.applied.size()).is_equal(1)

	if previous_scene != null:
		get_tree().current_scene = previous_scene


# FD-316: el sim_hello lleva el estado persistente del nivel (actores con get_snapshot) ademas
# del jugador. Sin esto la autoridad carga el nivel desde cero y su _ready vuelve a correr la
# intro de despertar: la escotilla del criopod se abria y sonaba de nuevo al iniciar el offload.
func test_sim_hello_carries_level_states():
	var hello = RemoteProtocolScript.create_sim_hello(
		"res://core_v2/levels/RingHub_Level.tscn", 60, "tok", {}, 7, {}, {
			".": {"selected_slot": 3, "gated_oys_script": "", "wakeup_completed": true},
			"Criopod_Vert/RotatingObjectV2": {"active": false, "progress": 0.0, "target": 0.0}
		})
	var wire = RemoteProtocolScript.decode_json(RemoteProtocolScript.encode_json(hello))
	assert_bool(wire["states"].has(".")).is_true()
	assert_int(int(wire["states"]["."]["selected_slot"])).is_equal(3)
	assert_str(String(wire["states"]["."]["gated_oys_script"])).is_empty()
	# Tarea J: el dato explicito de "despertar ya completado" viaja con el estado del nivel.
	assert_bool(bool(wire["states"]["."]["wakeup_completed"])).is_true()
	assert_bool(bool(wire["states"]["Criopod_Vert/RotatingObjectV2"]["active"])).is_false()


# FD-316: la autoridad adopta el estado del nivel ANTES de habilitar la emision (sim_ready).
# Asi el estado restaurado (secuencia de despertar ya liberada, escotilla cerrada) neutraliza
# la intro que correria el _ready del nivel recien instanciado.
func test_sim_host_applies_hello_actor_states_before_sim_ready():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)
	host.start_simulation("127.0.0.1", 0)

	var level = _make_sim_level()
	var actor = auto_free(FakeSwitchActor.new())
	actor.name = "PodHatch"
	actor.add_to_group("replay_sync")
	level.add_child(actor)
	actor.owner = level
	actor.state = {"switch_active": false}

	assert_bool(host._attach_sim_level(level, {"scene": "res://x.tscn",
		"states": {"PodHatch": {"switch_active": true}}})).is_true()
	assert_bool(host.sim_ready).is_true()
	assert_int(actor.applied.size()).is_equal(1)
	assert_bool(bool(actor.state["switch_active"])).is_true()

	host.stop_simulation()


# FD-316: una re-promocion del MISMO nivel tambien re-sincroniza el estado persistente (el
# esclavo pudo avanzar mientras estaba desconectado), no solo la pose del jugador.
func test_sim_host_reuse_reapplies_hello_states():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)
	host.start_simulation("127.0.0.1", 0)

	var level = _make_sim_level()
	var actor = auto_free(FakeSwitchActor.new())
	actor.name = "PodHatch"
	actor.add_to_group("replay_sync")
	level.add_child(actor)
	actor.owner = level
	actor.state = {"switch_active": false}

	assert_bool(host._attach_sim_level(level, {"scene": "res://x.tscn",
		"states": {"PodHatch": {"switch_active": true}}})).is_true()
	assert_int(actor.applied.size()).is_equal(1)

	assert_bool(host._reuse_sim_level_if_same("res://x.tscn",
		{"states": {"PodHatch": {"switch_active": false}}})).is_true()
	assert_int(actor.applied.size()).is_equal(2)
	assert_bool(bool(actor.state["switch_active"])).is_false()

	host.stop_simulation()


# FD-316: la raiz del nivel tambien puede tener estado persistente (RingHubWakeup lo replica
# como "." y ahi vive la secuencia de despertar ya liberada). El host lo aplica igual.
func test_sim_host_applies_hello_root_state():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)
	host.start_simulation("127.0.0.1", 0)

	var level = FakeLogicActor.new()
	level.name = "SimLevelRoot"
	level.state = {"lit": false}
	var fake = FakePlayer.new()
	fake.name = "Player"
	fake.add_to_group("player")
	level.add_child(fake)

	assert_bool(host._attach_sim_level(level, {"scene": "res://x.tscn",
		"states": {".": {"lit": true}}})).is_true()
	assert_int(level.applied.size()).is_equal(1)
	assert_bool(bool(level.state["lit"])).is_true()

	host.stop_simulation()


# FD-316: por replicacion, un restore con el estado que el actor YA tiene no debe re-disparar
# efectos one-shot (la apertura/sonido de la escotilla del criopod al reconectar el control).
func test_render_slave_skips_restore_when_actor_already_in_state():
	var level_b := Spatial.new()
	level_b.name = "SimLevelB"
	var actor = auto_free(FakeSwitchActor.new())
	actor.name = "PodHatch"
	actor.state = {"switch_active": true}
	level_b.add_child(actor)

	var previous_scene = get_tree().current_scene
	get_tree().root.add_child(level_b)
	get_tree().current_scene = level_b
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)

	# El actor ya esta en ese estado: no se le llama el restore.
	client._apply_snapshot({"tick": 1, "entities": {}, "globals": {"states": {
		"PodHatch": {"switch_active": true}}}})
	assert_int(actor.applied.size()).is_equal(0)

	# Estado distinto: si se aplica (y el cache queda al dia para los siguientes ticks).
	client._apply_snapshot({"tick": 2, "entities": {}, "globals": {"states": {
		"PodHatch": {"switch_active": false}}}})
	assert_int(actor.applied.size()).is_equal(1)
	assert_bool(bool(actor.state["switch_active"])).is_false()

	if previous_scene != null:
		get_tree().current_scene = previous_scene


# FD-316: el esclavo arma el `states` del sim_hello desde los actores replay_sync del nivel,
# con el path relativo a la escena (la raiz queda como "." para que viaje el estado del
# propio nivel, como la secuencia de despertar de RingHubWakeup).
func test_build_sim_hello_collects_level_actor_states():
	var rcm = get_node("/root/RemoteControlManager")
	# La raiz del nivel es un actor replay_sync con get_snapshot (como RingHubWakeup):
	# su estado viaja con la clave "." (path relativo a si misma).
	var level = FakeLogicActor.new()
	level.name = "SimLevelCollect"
	level.state = {"lit": true}
	level.add_to_group("replay_sync")
	var actor = FakeSwitchActor.new()
	actor.name = "PodHatch"
	actor.state = {"switch_active": true}
	actor.add_to_group("replay_sync")
	level.add_child(actor)

	var previous_scene = get_tree().current_scene
	get_tree().root.add_child(level)
	get_tree().current_scene = level

	var states: Dictionary = rcm._capture_level_states(level)
	assert_bool(states.has(".")).is_true()
	assert_bool(bool(states["."]["lit"])).is_true()
	assert_bool(states.has("PodHatch")).is_true()
	assert_bool(bool(states["PodHatch"]["switch_active"])).is_true()

	if previous_scene != null:
		get_tree().current_scene = previous_scene
	get_tree().root.remove_child(level)
	level.free()


# FD-316 (tarea J) offload, caso "el esclavo YA desperto": el sim_hello trae el estado del
# nivel con `wakeup_completed=true` (y sin secuencia gateada). El host lo adopta ANTES de
# sim_ready y la intro diferida del _ready no vuelve a correr: la escotilla no se reabre ni
# vuelve a sonar al conectar el offload.
func test_offload_wakeup_already_done_does_not_reopen_on_host():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)
	host.start_simulation("127.0.0.1", 0)

	var level = FakeWakeupActor.new()
	level.name = "SimWakeupLevel"
	var player = auto_free(FakePlayer.new())
	player.name = "Player"
	player.add_to_group("player")
	level.add_child(player)

	assert_bool(host._attach_sim_level(level, {"scene": "res://x.tscn", "states": {".": {
		"wakeup_completed": true, "gated_oys_script": ""}}})).is_true()
	assert_bool(host.sim_ready).is_true()
	# El host adopto el dato explicito del esclavo.
	assert_bool(level.wakeup_completed).is_true()

	# La intro diferida no tiene nada que hacer: no reabre la escotilla.
	level.open_pod_terminal()
	assert_int(level.intro_runs).is_equal(0)
	assert_bool(level.hatch_open).is_false()

	host.stop_simulation()


# FD-316 (tarea J) offload, caso "el esclavo TODAVIA no desperto": el sim_hello trae el
# estado con `wakeup_completed=false`. El host lo adopta (sigue pendiente) y la intro corre en
# la autoridad, que abre la escotilla; ese estado es el que se replica de vuelta al esclavo.
func test_offload_wakeup_pending_runs_intro_on_host():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)
	host.start_simulation("127.0.0.1", 0)

	var level = FakeWakeupActor.new()
	level.name = "SimWakeupLevel"
	var player = auto_free(FakePlayer.new())
	player.name = "Player"
	player.add_to_group("player")
	level.add_child(player)

	assert_bool(host._attach_sim_level(level, {"scene": "res://x.tscn", "states": {".": {
		"wakeup_completed": false,
		"gated_oys_script": "res://core_v2/levels/ringhub_wakeup.oys"}}})).is_true()
	assert_bool(level.wakeup_completed).is_false()
	assert_str(level.gated_oys_script).is_equal("res://core_v2/levels/ringhub_wakeup.oys")

	# La autoridad corre la secuencia de despertar y la escotilla se abre.
	level.open_pod_terminal()
	assert_int(level.intro_runs).is_equal(1)
	assert_bool(level.hatch_open).is_true()
	# Estado replicable ya completado (es lo que le llega al esclavo en el proximo snapshot).
	var snap = level.get_snapshot()
	assert_bool(bool(snap["wakeup_completed"])).is_true()
	assert_str(String(snap["gated_oys_script"])).is_empty()

	host.stop_simulation()


# FD-316: la linterna del casco viaja con el jugador (encendido/bateria). El sintoma en
# device era que el esclavo conservaba SU estado local y quedaba prendida/ajena a la
# autoridad.
func test_sim_snapshot_carries_flashlight_state():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)

	var level := Spatial.new()
	level.name = "SimLevel"
	var player = auto_free(FakeFlashPlayer.new())
	player.name = "Pilot"
	player.add_to_group("player")
	var flashlight = auto_free(FakeFlashlight.new())
	flashlight.name = RemoteProtocolScript.FLASHLIGHT_PATH
	flashlight.enabled = true
	flashlight.battery = 42.0
	player.add_child(flashlight)
	level.add_child(player)

	assert_bool(host._attach_sim_level(level, {})).is_true()
	var snap = host.capture_snapshot()

	var state: Dictionary = snap["entities"]["Pilot"]
	assert_bool(state.has("flash")).is_true()
	assert_bool(bool(state["flash"]["on"])).is_true()
	assert_float(float(state["flash"]["battery"])).is_equal_approx(42.0, 0.001)

	host.stop_simulation()


# FD-316: el esclavo aplica el encendido/bateria de la autoridad a su propia linterna.
func test_render_slave_applies_remote_flashlight_state():
	var level_b := Spatial.new()
	level_b.name = "SimLevelB"
	var player_b = auto_free(FakeRemoteFlashPlayer.new())
	player_b.name = "Pilot"
	player_b.add_to_group("player")
	var flashlight_b = auto_free(FakeRemoteFlashlight.new())
	flashlight_b.name = RemoteProtocolScript.FLASHLIGHT_PATH
	player_b.add_child(flashlight_b)
	level_b.add_child(player_b)

	var previous_scene = get_tree().current_scene
	get_tree().root.add_child(level_b)
	get_tree().current_scene = level_b
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)

	client._apply_snapshot({"tick": 1, "entities": {
		"Pilot": {"vel": [0, 0, 3], "g": true, "flash": {"on": true, "battery": 33.0}}
	}})

	assert_int(flashlight_b.applied.size()).is_equal(1)
	assert_bool(bool(flashlight_b.applied[0]["on"])).is_true()
	assert_float(float(flashlight_b.applied[0]["battery"])).is_equal_approx(33.0, 0.001)

	if previous_scene != null:
		get_tree().current_scene = previous_scene


# FD-316: en el render-esclavo la fisica esta congelada (SimLogicFreeze apaga el
# _physics_process de la linterna), asi que su orientacion tiene que salir de _process,
# que no se congela, siguiendo la camara replicada. Antes quedaba clavada en la pose de
# spawn (apagar/prender la arreglaba porque set_enabled re-montaba una vez).
class FakeRemoteSlavePlayer extends Spatial:
	var velocity := Vector3.ZERO
	func is_effectively_grounded() -> bool:
		return true
	func is_remote_render_slave() -> bool:
		return true


func _make_mountable_owner(with_pivot: bool) -> FakeRemoteSlavePlayer:
	var owner_node = auto_free(FakeRemoteSlavePlayer.new())
	owner_node.name = "Pilot"
	add_child(owner_node)
	if with_pivot:
		var visual := Spatial.new()
		visual.name = "Visual"
		var pivot := Spatial.new()
		pivot.name = "Pivot"
		var skel_root := Spatial.new()
		skel_root.name = "Skeleton"
		var mesh := Spatial.new()
		mesh.name = "Skinned_Mesh_0"
		var skeleton := Skeleton.new()
		skeleton.name = "Skeleton"
		skeleton.add_bone("DEF-upper_armR")
		owner_node.add_child(visual)
		visual.add_child(pivot)
		pivot.add_child(skel_root)
		skel_root.add_child(mesh)
		mesh.add_child(skeleton)
	return owner_node


func test_helmet_flashlight_remote_hook_marks_orientation_path():
	# Contrato liviano: con el padre en rol de render-esclavo, la linterna lo detecta y no
	# depende de _physics_process para apuntar (que SimLogicFreeze apaga).
	var packed: PackedScene = load("res://core_v2/props/lights/HelmetFlashlight.tscn")
	var flashlight = auto_free(packed.instance())
	var owner_node = _make_mountable_owner(false)
	owner_node.add_child(flashlight)
	yield(get_tree(), "idle_frame")

	flashlight.apply_remote_state(true, 50.0)
	assert_bool(flashlight.enabled).is_true()
	assert_float(flashlight.get_battery()).is_equal_approx(50.0, 0.001)
	# No re-prende la logica congelada del render-esclavo.
	assert_bool(flashlight.is_physics_processing()).is_false()
	assert_bool(flashlight.is_processing()).is_true()
	assert_bool(flashlight._is_remote_render_slave()).is_true()


func test_helmet_flashlight_remote_aim_follows_camera_in_process():
	var packed: PackedScene = load("res://core_v2/props/lights/HelmetFlashlight.tscn")
	var flashlight = auto_free(packed.instance())
	var owner_node = _make_mountable_owner(true)
	owner_node.add_child(flashlight)
	yield(get_tree(), "idle_frame")

	var cam = auto_free(Camera.new())
	cam.name = "TestRemoteCam"
	add_child(cam)
	cam.current = true

	flashlight.apply_remote_state(true, 50.0)
	# La fisica esta congelada: el apuntado solo puede avanzar por _process.
	flashlight.set_physics_process(false)
	var before: Vector3 = flashlight.get_aim_direction()

	# La autoridad mira hacia +X (la linterna tiene que virar hacia alla, con el tope de 75).
	cam.global_transform = Transform(Basis(Vector3.UP, -PI * 0.5), Vector3.ZERO)
	for _i in range(120):
		flashlight._process(1.0 / 60.0)
	var after: Vector3 = flashlight.get_aim_direction()

	assert_bool(flashlight.is_physics_processing()).is_false()
	# Convergio hacia +X siguiendo la camara replicada, no quedo en el frente.
	assert_float(after.x).is_greater(0.1)
	assert_float(after.x).is_greater(before.x + 0.05)


func test_repeated_sim_hello_same_scene_reuses_level():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)
	host.start_simulation("127.0.0.1", 0)

	var level = _make_sim_level()
	var scene_path := "res://core_v2/levels/RingHub_Level.tscn"
	assert_bool(host._attach_sim_level(level, {"scene": scene_path})).is_true()
	var level_id = host._sim_level.get_instance_id()

	# Mismo nivel: se conserva la instancia (no se recarga).
	assert_bool(host._reuse_sim_level_if_same(scene_path)).is_true()
	assert_int(host._sim_level.get_instance_id()).is_equal(level_id)
	# Otra escena: no reusa (hay que cargar la nueva).
	assert_bool(host._reuse_sim_level_if_same("res://core_v2/levels/interiors/Dome_Intro.tscn")).is_false()

	host.stop_simulation()


# FD-316: en render-esclavo el animator consume la velocidad de la autoridad, no la
# local (que queda en cero porque PhysicsServer esta apagado).
func test_player_remote_anim_state_overrides_local_velocity():
	var player = PlayerScript.new() # sin arbol: no corre _ready ni sus onready
	player.velocity = Vector3.ZERO
	player.set_remote_interaction_authoritative(true)
	player.set_remote_anim_state(Vector3(0, 0, 4.0), true)

	assert_bool(player.is_remote_render_slave()).is_true()
	assert_vector3(player._get_animator_velocity()).is_equal_approx(Vector3(0, 0, 4.0), Vector3.ONE * 0.001)
	assert_bool(player.is_effectively_grounded()).is_true()
	# Sin animator (nodo sin arbol) el step remoto es null-safe: no explota.
	player.step_remote_animator(1.0 / 60.0)

	# Sin rol de render-esclavo vuelve a usar la velocidad local.
	player.set_remote_interaction_authoritative(false)
	assert_vector3(player._get_animator_velocity()).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)
	player.free()


func test_sim_host_input_queue_ordering_and_parallel_sources():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)

	var in_client_t10 = RemoteProtocolScript.create_sim_input({"move_x": 0.5}, {"jump": true}, 10)
	var in_local_t5 = RemoteProtocolScript.create_sim_input({"move_x": -0.5}, {"jump": false}, 5)

	# Out of order insertion
	host.receive_sim_input(in_client_t10, "client")
	host.receive_sim_input(in_local_t5, "remote_local")

	assert_int(host._input_queue.size()).is_equal(2)
	assert_int(host._input_queue[0]["tick"]).is_equal(5)
	assert_str(host._input_queue[0]["source"]).is_equal("remote_local")
	assert_int(host._input_queue[1]["tick"]).is_equal(10)
	assert_str(host._input_queue[1]["source"]).is_equal("client")

	# Process tick 5
	host._process_input_queue_for_tick(5)
	assert_int(host._input_queue.size()).is_equal(1)
	assert_int(host._input_queue[0]["tick"]).is_equal(10)

	# Process tick 10
	host._process_input_queue_for_tick(10)
	assert_int(host._input_queue.size()).is_equal(0)
	assert_float(host._client_input_state["axes"]["move_x"]).is_equal(0.5)


# FD-316: el input del cliente (render-esclavo) llegaba a la autoridad pero se quedaba
# encolado en _client_input_state sin llegar al player: el personaje nunca se movia en
# la simulacion y por eso jamas se acercaba a un interactuable. Ahora se inyecta como
# InputDataV2 (ver test_sim_host_injects_merged_input_without_touching_global_input).
func test_sim_host_client_input_reaches_player_frame():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)

	var player = auto_free(FakeInjectPlayer.new())
	player.add_to_group("player")
	host._sim_player = player

	var press = RemoteProtocolScript.create_sim_input({"move_x": 1.0}, {"interact": true}, 1)
	host.receive_sim_input(press, "client")
	host._process_input_queue_for_tick(1)
	host._apply_authority_input_frame()

	assert_int(player.injected.size()).is_equal(1)
	assert_float(float(player.injected[0]["move_vec"][0])).is_equal_approx(1.0, 0.001)
	assert_bool(player.injected[0]["interact"]).is_true()
	assert_bool(Input.is_action_pressed("move_right")).is_false()

	host.stop_simulation()


# FD-316: entrar/salir del rol render-esclavo YA NO muta al promover: el mute (y la
# cesion de fisica/interaccion) ocurre con el primer snapshot valido — ver
# test_render_slave_does_not_engage_on_promotion / test_render_slave_engages_on_first_valid_snapshot.


# FD-316: stop blando. El nivel conservado no puede seguir simulando: sin la inyeccion de
# input de la autoridad, el Pilot oculto cae a su InputProvider local (el teclado del
# control) y los timers/cinematicas avanzan. Se congela la logica y se descongela al
# retomar; si no hay re-promocion en SOFT_STOP_UNLOAD_SEC, el nivel se descarga.
func test_soft_stop_freezes_level_and_timeout_unloads():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)
	host.start_simulation("127.0.0.1", 0)

	var scene_path := "res://core_v2/levels/RingHub_Level.tscn"
	var level = _make_sim_level()
	assert_bool(host._attach_sim_level(level, {"scene": scene_path})).is_true()
	var player = host._sim_player
	player.set_physics_process(true)
	assert_bool(player.is_physics_processing()).is_true()

	# Stop blando: el nivel se conserva, pero su logica queda congelada.
	host.stop_simulation(true)
	assert_bool(host.sim_ready).is_true()
	assert_bool(host._soft_stopped).is_true()
	assert_bool(player.is_physics_processing()).is_false()

	# Re-promocion antes del timeout: se reusa la MISMA instancia y se descongela.
	var level_id = level.get_instance_id()
	host.start_simulation("127.0.0.1", 0)
	assert_bool(host._reuse_sim_level_if_same(scene_path)).is_true()
	assert_int(host._sim_level.get_instance_id()).is_equal(level_id)
	assert_bool(host._soft_stopped).is_false()
	assert_bool(player.is_physics_processing()).is_true()

	# Otro stop blando y vencimiento del plazo: el nivel conservado se descarga.
	host.stop_simulation(true)
	assert_bool(player.is_physics_processing()).is_false()
	host._soft_stop_deadline_ms = 0
	host._process(0.0)
	assert_object(host._sim_level).is_null()
	assert_bool(host.sim_ready).is_false()
	assert_bool(host._soft_stopped).is_false()


# FD-294/316: el idioma del control llega al host por el server
# (server.ui_directive_received -> _on_server_ui_directive) y cambia TranslationServer. Al
# desconectar el control se restaura el locale propio; si el control vuelve al idioma del
# host, el host vuelve.
func test_set_language_directive_changes_locale_and_disconnect_restores():
	var rcm = get_node("/root/RemoteControlManager")
	var sm = get_node("/root/SettingsManager")
	var previous_locale := TranslationServer.get_locale()
	var previous_applied: String = rcm._remote_locale_applied
	var host_locale: String = sm.resolve_effective_language()
	var remote_locale: String = "en" if host_locale != "en" else "es"

	# La directiva viaja por la senal real del server, no llamando al handler a mano.
	rcm.server.emit_signal("ui_directive_received", "set_language", {"locale": remote_locale})
	assert_str(TranslationServer.get_locale()).is_equal(remote_locale)
	assert_str(rcm._remote_locale_applied).is_equal(host_locale)

	# El control vuelve al idioma del host: el host tambien.
	rcm.server.emit_signal("ui_directive_received", "set_language", {"locale": host_locale})
	assert_str(TranslationServer.get_locale()).is_equal(host_locale)

	# De nuevo remoto y desconexion: se restaura el locale propio del host.
	rcm.server.emit_signal("ui_directive_received", "set_language", {"locale": remote_locale})
	assert_str(TranslationServer.get_locale()).is_equal(remote_locale)
	rcm._on_server_client_disconnected("control")
	assert_str(TranslationServer.get_locale()).is_equal(host_locale)
	assert_str(rcm._remote_locale_applied).is_equal("")

	TranslationServer.set_locale(previous_locale)
	rcm._remote_locale_applied = previous_applied


# FD-316 (review bugs 1 y 3): el esclavo manda un seq monotono por sesion. La autoridad
# descarta los seq <= al ultimo visto, asi dos copias del mismo datagrama (comun en WiFi)
# no vuelven a sumar el delta de camara.
func test_sim_host_dedupes_client_input_seq():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)

	var player = auto_free(FakeInjectPlayer.new())
	player.add_to_group("player")
	host._sim_player = player

	# Dos copias identicas (mismo seq): el look entra una sola vez.
	host.receive_sim_input(RemoteProtocolScript.create_sim_input(
		{"move_x": 0.0}, {"jump": false}, 1, "", {"x": 3.0, "y": -2.0}, 5), "client")
	host.receive_sim_input(RemoteProtocolScript.create_sim_input(
		{"move_x": 0.0}, {"jump": false}, 1, "", {"x": 3.0, "y": -2.0}, 5), "client")
	assert_int(host._input_queue.size()).is_equal(1)

	host._process_input_queue_for_tick(1)
	host._apply_authority_input_frame()
	assert_int(player.injected.size()).is_equal(1)
	var d: Dictionary = player.injected[0]
	assert_float(float(d["mouse_delta"][0])).is_equal_approx(3.0, 0.001)
	assert_float(float(d["mouse_delta"][1])).is_equal_approx(-2.0, 0.001)

	# Un seq menor (paquete reordenado) tambien se descarta.
	host.receive_sim_input(RemoteProtocolScript.create_sim_input(
		{"move_x": 1.0}, {"jump": false}, 2, "", {}, 4), "client")
	assert_int(host._input_queue.size()).is_equal(0)

	host.stop_simulation()


# FD-316 (review bug 1): sin un sim_input valido por mas de CLIENT_INPUT_TIMEOUT_MSEC, el
# estado del handheld se suelta. Antes el ultimo axes/buttons se re-inyectaba tick a tick
# y el personaje seguia corriendo a ciegas al cortarse la red.
func test_sim_host_expires_stale_client_input():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)

	var player = auto_free(FakeInjectPlayer.new())
	player.add_to_group("player")
	host._sim_player = player

	host.receive_sim_input(RemoteProtocolScript.create_sim_input(
		{"move_x": 1.0, "move_y": 0.0}, {"jump": true}, 1, "", {"x": 3.0}, 1), "client")
	host._process_input_queue_for_tick(1)
	host._apply_authority_input_frame()
	var d1: Dictionary = player.injected[0]
	assert_float(float(d1["move_vec"][0])).is_equal_approx(1.0, 0.001)
	assert_float(float(d1["mouse_delta"][0])).is_equal_approx(3.0, 0.001)

	# 250 ms sin paquetes validos: move_vec y look vuelven a cero.
	host._last_client_input_ms -= 250
	host._apply_authority_input_frame()
	var d2: Dictionary = player.injected[1]
	assert_float(float(d2["move_vec"][0])).is_equal_approx(0.0, 0.001)
	assert_float(float(d2["move_vec"][1])).is_equal_approx(0.0, 0.001)
	assert_float(float(d2["mouse_delta"][0])).is_equal_approx(0.0, 0.001)
	assert_float(float(d2["zoom_delta"])).is_equal_approx(0.0, 0.001)

	host.stop_simulation()


# FD-316 (review bug 2): el flanco de jump/interact viaja en un unico datagrama. El
# esclavo repite el true FLANK_REPEAT_PACKETS paquetes para que la perdida del paquete del
# press no borre el tap.
func test_sim_input_flank_latch_survives_lost_packet():
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)
	client.start_render_slave(0)

	var pressed := {"jump": true, "interact": true, "sprint": false, "crouch": false}
	var held := {"jump": false, "interact": false, "sprint": false, "crouch": false}

	# Frame del press: sale con el flanco.
	var first: Dictionary = client._latch_flanked_buttons(pressed)
	assert_bool(bool(first["jump"])).is_true()
	assert_bool(bool(first["interact"])).is_true()

	# Ese datagrama se "pierde": los dos siguientes igual repiten el true.
	var second: Dictionary = client._latch_flanked_buttons(held)
	assert_bool(bool(second["jump"])).is_true()
	assert_bool(bool(second["interact"])).is_true()
	var third: Dictionary = client._latch_flanked_buttons(held)
	assert_bool(bool(third["jump"])).is_true()
	assert_bool(bool(third["interact"])).is_true()

	# Recien el cuarto paquete vuelve a false.
	var fourth: Dictionary = client._latch_flanked_buttons(held)
	assert_bool(bool(fourth["jump"])).is_false()
	assert_bool(bool(fourth["interact"])).is_false()

	client.stop_render_slave()


# FD-316 (review bug 2): el host re-inyecta jump=true mientras dura el latch, pero el
# flanco real del controlador es por transicion (PlayerControllerV2._jump_was_pressed):
# los frames repetidos no producen un segundo salto.
func test_repeated_jump_frames_only_one_edge():
	var player = PlayerScript.new() # sin arbol: no corre _ready
	var frame1 := InputDataV2.new()
	frame1.jump = true
	var edge1: bool = frame1.jump and not player._jump_was_pressed
	player._update_input_edge_state(frame1)

	var frame2 := InputDataV2.new()
	frame2.jump = true
	var edge2: bool = frame2.jump and not player._jump_was_pressed
	player._update_input_edge_state(frame2)

	assert_bool(edge1).is_true()
	assert_bool(edge2).is_false()
	player.free()


# FD-316 (riesgo "Sin auth"): con sesion firmada, la autoridad descarta el sim_input de
# un peer LAN que no conoce el token.
func test_sim_host_ignores_foreign_token_input():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)
	host.start_simulation("127.0.0.1", 0, "sesame")

	var player = auto_free(FakeInjectPlayer.new())
	player.add_to_group("player")
	host._sim_player = player

	# Token ajeno: no se encola.
	host.receive_sim_input(RemoteProtocolScript.create_sim_input(
		{"move_x": 1.0}, {"jump": true}, 1, "otro", {}, 1), "client")
	assert_int(host._input_queue.size()).is_equal(0)
	host._apply_authority_input_frame()
	assert_float(float(player.injected[0]["move_vec"][0])).is_equal_approx(0.0, 0.001)

	# Token de la sesion: si.
	host.receive_sim_input(RemoteProtocolScript.create_sim_input(
		{"move_x": 1.0}, {"jump": false}, 2, "sesame", {}, 2), "client")
	assert_int(host._input_queue.size()).is_equal(1)
	host._process_input_queue_for_tick(2)
	host._apply_authority_input_frame()
	assert_float(float(player.injected[1]["move_vec"][0])).is_equal_approx(1.0, 0.001)

	host.stop_simulation()


# FD-316 (riesgo "Sin auth"): el esclavo no aplica ni adopta la IP de un snapshot con
# token invalido: el suplantador no puede redirigir el sim_input del handheld.
func test_render_slave_ignores_spoofed_snapshot_token():
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)
	client.start_render_slave(0, "192.168.1.10", 10445, "sesame")

	client._handle_udp_packet("10.0.0.9", {"type": "sim_snapshot", "tick": 1, "token": "otro"})
	assert_str(client._target_ip).is_equal("192.168.1.10")
	assert_int(client._buffer.size()).is_equal(0)

	# El token correcto si: se adopta la IP de origen y se encola.
	client._handle_udp_packet("10.0.0.9", {"type": "sim_snapshot", "tick": 1, "token": "sesame"})
	assert_str(client._target_ip).is_equal("10.0.0.9")
	assert_int(client._buffer.size()).is_equal(1)

	client.stop_render_slave()


# FD-316 (review bug 4): lo que entra al nivel DESPUES del congelado (spawners,
# PlateContentStream, pickups) nace simulando encima de los snapshots. El hook
# SceneTree.node_added lo filtra por alcance y lo congela: sin re-scan por frame.
func test_freeze_catches_nodes_added_after_freeze():
	var freezer = SimLogicFreezeScript.new()
	var level := Spatial.new()
	level.name = "FrozenLevel"
	var existing := Spatial.new()
	existing.name = "Existing"
	existing.set_physics_process(true)
	level.add_child(existing)
	get_tree().root.add_child(level)

	freezer.freeze(level)
	assert_bool(freezer.is_frozen()).is_true()
	assert_bool(existing.is_physics_processing()).is_false()

	# Nodo que entra al nivel despues del congelado, con _physics_process activo.
	var spawned := Spatial.new()
	spawned.name = "SpawnedLater"
	spawned.set_physics_process(true)
	level.add_child(spawned)
	assert_bool(spawned.is_physics_processing()).is_false()

	# Fuera del alcance congelado: no se toca.
	var outside := Spatial.new()
	outside.name = "Outside"
	outside.set_physics_process(true)
	get_tree().root.add_child(outside)
	assert_bool(outside.is_physics_processing()).is_true()

	# Al descongelar se restauran los que estaban corriendo y se deja de escuchar.
	freezer.thaw()
	assert_bool(freezer.is_frozen()).is_false()
	assert_bool(existing.is_physics_processing()).is_true()
	assert_bool(spawned.is_physics_processing()).is_true()

	# Despues del thaw un nodo nuevo nace simulando (ya no hay escucha).
	var late := Spatial.new()
	late.name = "AfterThaw"
	late.set_physics_process(true)
	level.add_child(late)
	assert_bool(late.is_physics_processing()).is_true()

	get_tree().root.remove_child(outside)
	get_tree().root.remove_child(level)
	outside.free()
	level.free()


# FD-316 (review bug 5): si el handheld pausa su arbol (menu/pausa rapida), el Input
# singleton NO se pausa, asi que el provider seguiria mandando movimiento a la autoridad.
# En pausa el frame sale NEUTRO; al despausar vuelve el frame del provider.
func test_render_slave_pause_sends_neutral_frame():
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)
	client.start_render_slave(0)
	var session = get_node("/root/SessionManager")
	var previous_player = session.player
	var player = auto_free(FakePadPlayer.new())
	session.player = player

	get_tree().paused = false
	var live: Dictionary = client._build_local_input()
	assert_float(float(live["axes"]["move_x"])).is_equal_approx(1.0, 0.001)
	assert_bool(bool(live["buttons"]["jump"])).is_true()
	assert_float(float(live["camera"]["x"])).is_equal_approx(2.0, 0.001)

	get_tree().paused = true
	var neutral: Dictionary = client._build_local_input()
	get_tree().paused = false
	assert_float(float(neutral["axes"]["move_x"])).is_equal_approx(0.0, 0.001)
	assert_float(float(neutral["axes"]["move_y"])).is_equal_approx(0.0, 0.001)
	assert_bool(bool(neutral["buttons"]["jump"])).is_false()
	assert_bool(bool(neutral["buttons"]["interact"])).is_false()
	assert_float(float(neutral["camera"]["x"])).is_equal_approx(0.0, 0.001)
	assert_float(float(neutral["camera"]["zoom"])).is_equal_approx(0.0, 0.001)

	session.player = previous_player
	client.stop_render_slave()


class FakePadProvider extends Reference:
	func get_input() -> InputDataV2:
		var d := InputDataV2.new()
		d.move_vec = Vector2(1.0, 0.0)
		d.jump = true
		d.mouse_delta = Vector2(2.0, 0.0)
		d.zoom_delta = 0.5
		return d


class FakePadPlayer extends KinematicBody:
	var input_provider = FakePadProvider.new()


# FD-316 (tarea E): el esclavo cierra el RTT input->snapshot con el ack_seq que manda la
# autoridad: guarda el instante de envio por seq y mide la vuelta con su reloj local.
func test_render_slave_rtt_from_known_ack():
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)
	client.start_render_slave(0, "127.0.0.1", 10445)

	client._sent_seq_ms[7] = OS.get_ticks_msec() - 40
	client.receive_snapshot(RemoteProtocolScript.create_sim_snapshot(1, 0, {}, {}, "", 7))

	assert_int(client._stats.sample_count("rtt_ms")).is_equal(1)
	assert_float(client._stats.percentile("rtt_ms", 1.0)).is_greater_equal(40.0)
	# El seq ackeado sale del ring: un ack repetido no vuelve a contar.
	client.receive_snapshot(RemoteProtocolScript.create_sim_snapshot(2, 0, {}, {}, "", 7))
	assert_int(client._stats.sample_count("rtt_ms")).is_equal(1)

	client.stop_render_slave()


# FD-316 (tarea E): la ventana de stats se cierra cada WINDOW_MS: publica last_stats y
# resetea contadores y muestras para la ventana siguiente.
func test_render_slave_stats_flush_and_reset():
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)
	client.start_render_slave(0)

	client._stats.tally("frame")
	client._stats.add_sample("rtt_ms", 12.0)
	client._stats.window_start_ms = OS.get_ticks_msec() - RemoteSimStatsScript.WINDOW_MS - 1
	client._flush_client_stats()

	assert_bool(client.last_stats.has("rtt_ms_p50")).is_true()
	assert_float(float(client.last_stats["rtt_ms_p50"])).is_equal_approx(12.0, 0.001)
	assert_float(float(client.last_stats["fps"])).is_greater(0.0)
	# Ventana nueva: contadores y muestras en cero.
	assert_int(client._stats.count("frame")).is_equal(0)
	assert_int(client._stats.sample_count("rtt_ms")).is_equal(0)

	client.stop_render_slave()


# FD-316 (tarea L/M): la linea de stats publica el desglose del frame: script real medido
# por el probe, physics del motor, draw calls, objetos/vertices en frame, nodos totales y
# el remanente de render (frame - script - physics). Los promedios son de la ventana.
func test_render_slave_stats_reports_frame_breakdown():
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)
	client.start_render_slave(0)

	client._stats.tally("frame")
	client._stats.add("script_us", 10000.0) # 10 ms
	client._stats.add("engine_physics_us", 5000.0) # 5 ms
	client._stats.add("draw_calls", 90.0)
	client._stats.add("objects_in_frame", 200.0)
	client._stats.add("vertices_in_frame", 12345.0)
	client._stats.add("node_count", 400.0)
	client._stats.window_start_ms = OS.get_ticks_msec() - RemoteSimStatsScript.WINDOW_MS - 1
	client._flush_client_stats()

	for key in ["script_ms_avg", "physics_ms_avg", "render_ms_avg", "draw_calls_avg",
			"objects_in_frame_avg", "vertices_in_frame_avg", "node_count_avg"]:
		assert_bool(client.last_stats.has(key)).is_true()
	assert_bool(client.last_stats.has("process_ms_avg")).is_false()
	assert_float(float(client.last_stats["script_ms_avg"])).is_equal_approx(10.0, 0.001)
	assert_float(float(client.last_stats["physics_ms_avg"])).is_equal_approx(5.0, 0.001)
	assert_float(float(client.last_stats["draw_calls_avg"])).is_equal_approx(90.0, 0.001)
	assert_float(float(client.last_stats["objects_in_frame_avg"])).is_equal_approx(200.0, 0.001)
	assert_float(float(client.last_stats["vertices_in_frame_avg"])).is_equal_approx(12345.0, 0.001)
	assert_float(float(client.last_stats["node_count_avg"])).is_equal_approx(400.0, 0.001)
	# Tarea M: ningun componente negativo y el desglose suma el frame de la ventana.
	var frame_ms: float = float(client.last_stats["frame_ms_avg"])
	var render_ms: float = float(client.last_stats["render_ms_avg"])
	assert_float(render_ms).is_greater_equal(0.0)
	assert_float(frame_ms - 15.0).is_equal_approx(render_ms, 0.001)

	client.stop_render_slave()


# FD-316 (tarea M): con una ventana larga y el desglose de un render-esclavo real (la
# fisica local esta apagada, asi que engine_physics ~= 0), script + render cierra el frame
# y ninguno sale negativo (el bug era render_ms < 0 porque TIME_PROCESS se usaba como
# "tiempo de scripts").
func test_render_slave_frame_breakdown_adds_up_and_is_non_negative():
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)
	client.start_render_slave(0)

	# 312 frames en 5 s => frame_ms_avg ~= 16 ms, con 5 ms de scripts y sin fisica local.
	var frames := 312
	for _i in range(frames):
		client._stats.tally("frame")
		client._stats.add("script_us", 5000.0)
	client._stats.window_start_ms = OS.get_ticks_msec() - RemoteSimStatsScript.WINDOW_MS - 1
	client._flush_client_stats()

	var frame_ms: float = float(client.last_stats["frame_ms_avg"])
	var script_ms: float = float(client.last_stats["script_ms_avg"])
	var physics_ms: float = float(client.last_stats["physics_ms_avg"])
	var render_ms: float = float(client.last_stats["render_ms_avg"])
	assert_float(script_ms).is_equal_approx(5.0, 0.01)
	assert_float(physics_ms).is_equal_approx(0.0, 0.01)
	assert_float(script_ms).is_greater_equal(0.0)
	assert_float(render_ms).is_greater_equal(0.0)
	assert_float(frame_ms).is_greater_equal(0.0)
	# Sin fisica local: script + render = frame.
	assert_float(script_ms + render_ms).is_equal_approx(frame_ms, 0.01)
	assert_float(script_ms + physics_ms + render_ms).is_equal_approx(frame_ms, 0.01)

	client.stop_render_slave()


# FD-316 (tarea M): el probe acumula el tramo de scripts por frame en las stats.
func test_render_slave_frame_probe_accumulates_script_us():
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)
	client.start_render_slave(0)

	client._on_frame_probe(7000)
	client._on_frame_probe(3000)
	# Un valor negativo (reloj no monotonico) se descarta.
	client._on_frame_probe(-1)
	assert_float(client._stats.sum("script_us")).is_equal_approx(10000.0, 0.001)

	client.stop_render_slave()


# FD-316 (tarea L): el perfil (opt-in por ODISEA_SLAVE_PROFILE) agrupa por script los
# nodos con _process activo; el cliente mismo queda contado bajo su script.
func test_render_slave_profile_groups_processing_nodes_by_script():
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)
	client.start_render_slave(0)
	var holder: Spatial = auto_free(Spatial.new())
	holder.name = "ProfileHolder"
	holder.set_process(true)
	client.add_child(holder)

	var counts: Dictionary = client._profile_script_counts()
	assert_bool(client.is_processing()).is_true()
	assert_int(int(counts.get("res://core_v2/net/RemoteSimClient.gd", 0))).is_greater_equal(1)
	# El nodo sin script tambien se agrupa (no se pierde en el perfil).
	assert_int(int(counts.get("<sin script>", 0))).is_greater_equal(1)

	client.stop_render_slave()


# FD-316 (tarea M): el censo de vertices del perfil agrupa por hijo de primer nivel de
# current_scene, suma solo mallas VISIBLES y cuenta las instancias visibles de un
# MultiMesh. El conteo por Mesh queda cacheado.
func test_render_slave_profile_vertex_census_groups_by_first_level_child():
	var level := Spatial.new()
	level.name = "CensusLevel"
	var group_a := Spatial.new()
	group_a.name = "GroupA"
	var group_b := Spatial.new()
	group_b.name = "GroupB"
	level.add_child(group_a)
	level.add_child(group_b)

	var mesh_a := _make_test_mesh(3)
	var mi_a := MeshInstance.new()
	mi_a.mesh = mesh_a
	group_a.add_child(mi_a)
	# Oculta: no aporta al censo.
	var mi_hidden := MeshInstance.new()
	mi_hidden.mesh = mesh_a
	mi_hidden.visible = false
	group_a.add_child(mi_hidden)

	var mesh_b := _make_test_mesh(5)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh_b
	mm.instance_count = 4
	mm.visible_instance_count = 2
	var mmi := MultiMeshInstance.new()
	mmi.multimesh = mm
	group_b.add_child(mmi)

	var previous_scene = get_tree().current_scene
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)

	var entries: Array = client._profile_vertex_census()
	var by_group: Dictionary = {}
	for e in entries:
		by_group[String(e["group"])] = int(e["verts"])
	# 3 vertices en A (la copia oculta no cuenta); 5 * 2 instancias visibles en B.
	assert_int(int(by_group.get("GroupA", -1))).is_equal(3)
	assert_int(int(by_group.get("GroupB", -1))).is_equal(10)
	assert_int(entries.size()).is_equal(2)
	# El conteo por malla se cacheo (no se recalcula surface_get_arrays).
	assert_int(client._mesh_vertex_cache.size()).is_equal(2)

	if previous_scene != null:
		get_tree().current_scene = previous_scene
	get_tree().root.remove_child(level)
	level.free()


# Malla de test con una superficie de N vertices (sin triangulos: alcanza para el censo).
func _make_test_mesh(vertex_count: int) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var points := PoolVector3Array()
	for i in range(vertex_count):
		points.append(Vector3(float(i), 0.0, 0.0))
	arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	return mesh


# FD-316 (tarea L): el retardo de interpolacion es UN intervalo de snapshot, y el
# intervalo efectivo viene en globals.snap_step (el host lo adapta por ventana).
func test_render_slave_interp_delay_is_one_snapshot_interval():
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)
	client.start_render_slave(0)

	client.receive_snapshot(RemoteProtocolScript.create_sim_snapshot(2, 0, {}, {"snap_step": 2}))
	assert_float(client._interp_delay_ticks).is_equal_approx(2.0, 0.001)
	client.receive_snapshot(RemoteProtocolScript.create_sim_snapshot(3, 0, {}, {"snap_step": 1}))
	assert_float(client._interp_delay_ticks).is_equal_approx(1.0, 0.001)

	client.stop_render_slave()


# FD-316 (tarea E): el sim host pone el seq APLICADO en ack_seq de cada snapshot y
# publica/resetea sus stats por ventana.
func test_sim_host_ack_seq_and_stats_flush():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)
	host.start_simulation("127.0.0.1", 0)
	assert_bool(host._attach_sim_level(_make_sim_level(), {})).is_true()

	host.receive_sim_input(RemoteProtocolScript.create_sim_input(
		{"move_x": 1.0}, {"jump": false}, 1, "", {}, 9), "client")
	host._process_input_queue_for_tick(1)
	host._physics_process(1.0 / 60.0)

	var snap: Dictionary = host.capture_snapshot()
	assert_int(int(snap["ack_seq"])).is_equal(9)

	host._stats.window_start_ms = OS.get_ticks_msec() - RemoteSimStatsScript.WINDOW_MS - 1
	host._physics_process(1.0 / 60.0)

	assert_bool(host.last_stats.has("tick_hz")).is_true()
	assert_float(float(host.last_stats["tick_hz"])).is_greater(0.0)
	assert_float(float(host.last_stats["capture_ms_avg"])).is_greater_equal(0.0)
	assert_int(host._stats.count("tick")).is_equal(0)

	host.stop_simulation()


# FD-316 (tarea F): la exencion de foco del sim host cubre tambien la caida transitoria
# con el nivel conservado por stop blando (connection_lost al perder foco), no solo el
# rol activo. Sin esto, una caida transitoria apagaba la exencion y PauseManager pausaba.
func test_sim_host_holding_simulation_covers_conserved_level():
	var manager = auto_free(RemoteControlManagerScript.new())
	add_child(manager)

	manager.is_sim_host_active = true
	assert_bool(manager.is_sim_host_holding_simulation()).is_true()

	# Rol caido pero nivel conservado y listo: sigue siendo sim host a los efectos del foco.
	manager.is_sim_host_active = false
	var level := Spatial.new()
	level.name = "SimLevel"
	manager.add_child(level)
	manager.sim_host._sim_level = level
	manager.sim_host.sim_ready = true
	manager.sim_host._soft_stopped = true
	assert_bool(manager.is_sim_host_holding_simulation()).is_true()

	# Sin nivel conservado no hay nada que mantener.
	manager.sim_host._soft_stopped = false
	assert_bool(manager.is_sim_host_holding_simulation()).is_false()


# FD-316 (tarea F): con el rol activo y la ventana sin foco se saca el throttle (vsync off
# + target_fps al ritmo de fisica, sin modo de bajo consumo); con foco o al terminar el rol
# se restaura el estado previo.
func test_sim_host_focus_guard_removes_throttle_only_while_unfocused():
	var manager = auto_free(RemoteControlManagerScript.new())
	add_child(manager)

	var prev_vsync: bool = OS.vsync_enabled
	var prev_fps: int = Engine.target_fps
	var prev_low: bool = OS.low_processor_usage_mode
	OS.vsync_enabled = true
	Engine.target_fps = 0

	manager.is_sim_host_active = true
	manager._sim_host_focus_override = 0 # sin foco
	manager.update_sim_host_focus_guard()
	assert_bool(OS.vsync_enabled).is_false()
	assert_bool(OS.low_processor_usage_mode).is_false()
	assert_int(Engine.target_fps).is_equal(int(round(Engine.iterations_per_second)))

	# Recupera el foco: vuelve el estado previo.
	manager._sim_host_focus_override = 1
	manager.update_sim_host_focus_guard()
	assert_bool(OS.vsync_enabled).is_true()
	assert_int(Engine.target_fps).is_equal(0)

	# Termina el rol estando sin foco: tambien se restaura.
	manager._sim_host_focus_override = 0
	manager.update_sim_host_focus_guard()
	assert_bool(OS.vsync_enabled).is_false()
	manager.is_sim_host_active = false
	manager.update_sim_host_focus_guard()
	assert_bool(OS.vsync_enabled).is_true()
	assert_int(Engine.target_fps).is_equal(0)

	# Sin rol no hay guard aunque falte foco.
	manager._sim_host_focus_override = 0
	manager.update_sim_host_focus_guard()
	assert_bool(OS.vsync_enabled).is_true()

	OS.vsync_enabled = prev_vsync
	Engine.target_fps = prev_fps
	OS.low_processor_usage_mode = prev_low


# FD-316 (tarea F): PauseManager consulta la decision en un solo lugar; con sim host
# conservando la simulacion no pausa el arbol al perder el foco.
func test_pause_manager_exempts_sim_host_on_focus_loss():
	var rcm = get_node("/root/RemoteControlManager")
	var pause_mgr = get_node("/root/PauseManager")
	var prev_active: bool = rcm.is_sim_host_active

	rcm.is_sim_host_active = true
	assert_bool(pause_mgr._sim_host_keeps_simulation()).is_true()

	rcm.is_sim_host_active = false
	assert_bool(pause_mgr._sim_host_keeps_simulation()).is_false()

	rcm.is_sim_host_active = prev_active


# FD-316 (tarea K2): el render-esclavo no es duenno de la camara. Con el rol activo, la
# logica local de un HoloTerminalV2 (auto-interaccion de zona o focus) NO debe entrar en
# foco ni pedir camara, y por lo tanto tampoco salir de foco despues. Sin el guard, el
# terminal enfocaba y desenfocaba al ritmo del jugador replicado (el "Exiting focus mode"
# repetido del handheld).
class SpyTerminal extends HoloTerminalV2:
	var exit_calls := 0
	func _exit_focus_mode():
		exit_calls += 1
		._exit_focus_mode()


func test_render_slave_terminal_does_not_own_camera_by_local_logic():
	var rcm = get_node("/root/RemoteControlManager")
	var prev_active: bool = rcm.is_render_slave_active

	var terminal = auto_free(SpyTerminal.new())
	terminal.use_cinematic_zone = false
	terminal.enable_ui_interaction = true
	terminal.allow_focus_mode = true
	# Con un FocusedRig presente, el UNICO motivo para no enfocar es el guard.
	var rig := Spatial.new()
	rig.name = "FocusedRig"
	auto_free(rig)
	terminal._focused_rig = rig

	rcm.is_render_slave_active = true
	assert_bool(RemoteControlManagerScript.render_slave_owns_camera()).is_true()

	# Entrada de foco: ni foco ni pedido de camara local.
	terminal._enter_focus_mode()
	terminal.focus()
	assert_bool(terminal.is_focused()).is_false()
	assert_int(terminal._focus_camera_request_id).is_equal(-1)

	# Cerrar el terminal (close_on_exit_zone) tampoco dispara la salida de foco local.
	terminal.set_active(false)
	assert_int(terminal.exit_calls).is_equal(0)

	# Fuera del rol el camino normal sigue funcionando (el guard no rompe el foco).
	rcm.is_render_slave_active = false
	assert_bool(RemoteControlManagerScript.render_slave_owns_camera()).is_false()
	terminal._enter_focus_mode()
	assert_bool(terminal.is_focused()).is_true()
	assert_int(terminal._focus_camera_request_id).is_not_equal(-1)
	terminal._exit_focus_mode()
	assert_bool(terminal.is_focused()).is_false()

	rcm.is_render_slave_active = prev_active


# FD-316 (tarea K2): el render-esclavo impone la camara del snapshot (transform + fov)
# sobre su camara actual, sin elegirla ni pedirla localmente.
func test_render_slave_applies_snapshot_camera_transform_and_fov():
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)
	client.start_render_slave(0)

	var holder := Spatial.new()
	var camera := Camera.new()
	holder.add_child(camera)
	get_tree().root.add_child(holder)
	camera.current = true

	var t := Transform(Basis(Vector3.UP, 0.5), Vector3(1.0, 2.0, 3.0))
	client._apply_snapshot({"tick": 1, "entities": {}, "globals": {
		"cam_fov": 71.5,
		"cam_t": RemoteProtocolScript.encode_transform(t)
	}})

	assert_float(camera.fov).is_equal_approx(71.5, 0.001)
	assert_vector3(camera.global_transform.origin).is_equal_approx(t.origin, Vector3.ONE * 0.001)

	camera.current = false
	get_tree().root.remove_child(holder)
	holder.free()
	client.stop_render_slave()


# FD-316 (tarea K2): la autoridad manda la camara ACTIVA del nivel simulado (la del
# terminal/cinematica incluida), no solo la del jugador, con su fov.
func test_sim_host_captures_active_sim_camera_and_fov():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)
	host.start_simulation("127.0.0.1", 0)

	var level = _make_sim_level()
	var cam_holder := Spatial.new()
	cam_holder.name = "CinematicRig"
	var cam := Camera.new()
	cam.name = "Camera"
	cam.fov = 66.0
	cam_holder.add_child(cam)
	level.add_child(cam_holder)

	assert_bool(host._attach_sim_level(level, {})).is_true()
	cam.current = true
	cam.global_transform = Transform(Basis(Vector3.UP, 0.25), Vector3(5.0, 6.0, 7.0))

	var snap: Dictionary = host.capture_snapshot()
	assert_bool(snap["globals"].has("cam_t")).is_true()
	assert_float(float(snap["globals"]["cam_fov"])).is_equal_approx(66.0, 0.001)
	var enc: Dictionary = snap["globals"]["cam_t"]
	var decoded: Transform = RemoteProtocolScript.decode_transform(enc)
	assert_vector3(decoded.origin).is_equal_approx(Vector3(5.0, 6.0, 7.0), Vector3.ONE * 0.001)

	host.stop_simulation()


# FD-316 (tarea K3): en el host de simulacion el nivel vive en un Viewport oculto, pero el
# foco de terminal pide su camara por CinematicManager, que la hace current en el viewport
# PRINCIPAL (la transicion usa /root/CameraTransition). El viewport oculto se queda con la
# camara del jugador, asi que capture_snapshot tiene que resolver la camara del rig activo
# del CinematicManager cuando ese rig vive en el nivel simulado; si no, la terminal de la
# autoridad nunca llega al render-esclavo (la transicion no se ve en el Anbernic).
class FakeCinematicRig extends Spatial:
	var camera: Camera = null
	func get_camera() -> Camera:
		return camera


func test_sim_host_captures_cinematic_focus_camera_in_sim_level():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)
	host.start_simulation("127.0.0.1", 0)

	var level = _make_sim_level()
	# Camara del jugador: es la que queda current en el viewport oculto (lo que K2 mandaba).
	var viewport_cam = auto_free(Camera.new())
	viewport_cam.name = "PlayerCam"
	viewport_cam.fov = 70.0
	level.add_child(viewport_cam)
	# Rig de foco del terminal: vive en el nivel simulado y es lo que la CinematicManager
	# considera activo (la transicion corre sobre el viewport principal).
	var focus_rig = auto_free(FakeCinematicRig.new())
	focus_rig.name = "FocusedRigInside"
	var focus_cam = auto_free(Camera.new())
	focus_cam.name = "Camera"
	focus_cam.fov = 55.0
	focus_rig.camera = focus_cam
	focus_rig.add_child(focus_cam)
	level.add_child(focus_rig)

	assert_bool(host._attach_sim_level(level, {})).is_true()
	viewport_cam.current = true
	focus_cam.global_transform = Transform(Basis(Vector3.UP, 0.4), Vector3(2.0, 3.0, 4.0))

	var cinematic = get_node("/root/CinematicManager")
	var prev_rig = cinematic.active_rig
	cinematic.active_rig = focus_rig
	var snap: Dictionary = host.capture_snapshot()
	cinematic.active_rig = prev_rig

	# La camara current del viewport oculto no gana: manda la del rig de foco, con su fov.
	assert_bool(snap["globals"].has("cam_t")).is_true()
	assert_float(float(snap["globals"]["cam_fov"])).is_equal_approx(55.0, 0.001)
	var decoded: Transform = RemoteProtocolScript.decode_transform(snap["globals"]["cam_t"])
	assert_vector3(decoded.origin).is_equal_approx(Vector3(2.0, 3.0, 4.0), Vector3.ONE * 0.001)

	host.stop_simulation()


# FD-316 (tareas K2/K3): con el render-esclavo activo la vista la impone el snapshot. Entrar
# en foco por logica local no debe pedir ni cambiar ninguna camara; la guarda cubre tambien
# la ventana de armado del offload (emparejado en tier LOW, canal de snapshots todavia no
# arriba), que era por donde se colaba el foco local antes de la promocion.
func test_render_slave_terminal_focus_does_not_change_camera():
	var rcm = get_node("/root/RemoteControlManager")
	var prev_active: bool = rcm.is_render_slave_active
	var prev_allow: bool = rcm.allow_low_tier_offload
	var server = rcm.server
	var injected_peer_id := 999999
	var had_peer: bool = server != null and server._peers.has(injected_peer_id)

	var holder := Spatial.new()
	var camera := Camera.new()
	holder.add_child(camera)
	get_tree().root.add_child(holder)
	camera.current = true
	var before := camera.global_transform

	var terminal = auto_free(SpyTerminal.new())
	terminal.use_cinematic_zone = false
	terminal.enable_ui_interaction = true
	terminal.allow_focus_mode = true
	var focus_rig := Spatial.new()
	focus_rig.name = "FocusedRig"
	var focus_cam := Camera.new()
	focus_cam.fov = 40.0
	focus_rig.add_child(focus_cam)
	auto_free(focus_rig)
	terminal._focused_rig = focus_rig

	# Rol activo: el foco local queda bloqueado antes de pedir camara.
	rcm.is_render_slave_active = true
	terminal._enter_focus_mode()
	assert_bool(terminal.is_focused()).is_false()
	assert_int(terminal._focus_camera_request_id).is_equal(-1)
	assert_bool(focus_cam.current).is_false()

	# Ventana de armado: sin rol todavia, pero tier LOW emparejado.
	rcm.is_render_slave_active = false
	rcm.allow_low_tier_offload = true
	if server != null:
		server._peers[injected_peer_id] = {"paired": true}
	assert_bool(RemoteControlManagerScript.render_slave_owns_camera()).is_true()
	terminal._enter_focus_mode()
	assert_bool(terminal.is_focused()).is_false()
	assert_int(terminal._focus_camera_request_id).is_equal(-1)

	# La camara local no se movio ni se cambio de dueno.
	camera.current = true
	assert_vector3(camera.global_transform.origin).is_equal_approx(before.origin, Vector3.ONE * 0.001)

	if server != null and not had_peer:
		server._peers.erase(injected_peer_id)
	rcm.is_render_slave_active = prev_active
	rcm.allow_low_tier_offload = prev_allow
	camera.current = false
	get_tree().root.remove_child(holder)
	holder.free()


# FD-316 (tarea N): esclavo de prueba que captura las directivas que salen por el WS. El
# server real las manda a sus peers emparejados; aca alcanza con registrar el mensaje.
class DirectiveRecorder extends Node:
	var directives: Array = []
	func send_ui_directive(op: String, payload) -> void:
		directives.append({"op": op, "payload": payload})
	func has_paired_client() -> bool:
		return false


# Pantalla de SuitOS minima: registra si su perform_action se ejecuto local.
class FakeSuitScreen extends Reference:
	var calls: Array = []
	func screen_id() -> String:
		return "test:screen"
	func allowed_actions() -> Array:
		return ["toggle_hatch", "select"]
	func perform_action(op: String, args: Dictionary = {}) -> Dictionary:
		calls.append({"op": op, "args": args})
		return {"ok": true}


# FD-316 (tarea N): el flanco de la linterna en el render-esclavo viaja por el canal
# confiable y la autoridad lo aplica a su jugador simulado (mismo efecto que su input local,
# sin tocar el Input global del control).
func test_render_slave_flashlight_action_reaches_authority():
	var rcm = get_node("/root/RemoteControlManager")
	var prev_active: bool = rcm.is_render_slave_active
	var prev_server = rcm.server
	var prev_host_active: bool = rcm.is_host_active
	var prev_processing: bool = rcm.is_processing()
	var recorder = auto_free(DirectiveRecorder.new())
	rcm.server = recorder
	rcm.is_render_slave_active = true
	rcm.is_host_active = false
	rcm.set_process(false)

	# Esclavo: el flanco sale por el WS con la op "sim_action".
	rcm.sim_client._forward_discrete_action("toggle_flashlight")
	assert_int(recorder.directives.size()).is_equal(1)
	assert_str(String(recorder.directives[0]["op"])).is_equal("sim_action")
	assert_str(String(recorder.directives[0]["payload"]["action"])).is_equal("toggle_flashlight")

	# Autoridad: el mismo mensaje, recibido por la senal real del cliente, cambia el estado
	# de la linterna del jugador simulado.
	var level := Spatial.new()
	level.name = "SimLevel"
	var player = auto_free(FakeFlashPlayer.new())
	player.name = "Pilot"
	var flashlight = auto_free(FakeFlashlight.new())
	flashlight.name = RemoteProtocolScript.FLASHLIGHT_PATH
	flashlight.enabled = false
	player.add_child(flashlight)
	level.add_child(player)
	auto_free(level)
	rcm.sim_host._sim_player = player
	rcm.client.emit_signal("ui_directive_received", recorder.directives[0]["op"], recorder.directives[0]["payload"])
	assert_int(flashlight.toggles).is_equal(1)
	assert_bool(flashlight.enabled).is_true()

	rcm.sim_host._sim_player = null
	rcm.server = prev_server
	rcm.is_render_slave_active = prev_active
	rcm.is_host_active = prev_host_active
	rcm.set_process(prev_processing)


# FD-316 (tarea N): una accion de SuitOS disparada en el esclavo en offload se reenvia a la
# autoridad y NO se ejecuta local (el visual y la camara vuelven por el snapshot). La
# autoridad la ejecuta sobre SU SuitOS con el nivel simulado.
func test_render_slave_suitos_action_forwards_and_skips_local():
	var rcm = get_node("/root/RemoteControlManager")
	var suit_os = get_node("/root/SuitOS")
	var prev_active: bool = rcm.is_render_slave_active
	var prev_server = rcm.server
	var prev_host_active: bool = rcm.is_host_active
	var prev_processing: bool = rcm.is_processing()
	var recorder = auto_free(DirectiveRecorder.new())
	rcm.server = recorder
	rcm.is_render_slave_active = true
	rcm.is_host_active = false
	rcm.set_process(false)

	var screen = auto_free(FakeSuitScreen.new())
	suit_os.register_screen(screen)

	# Esclavo: se reenvia con la forma de SuitOSRemoteBridge y no corre local.
	var result: Dictionary = suit_os.perform_action("test:screen", "toggle_hatch", {})
	assert_bool(bool(result.get("forwarded", false))).is_true()
	assert_int(screen.calls.size()).is_equal(0)
	assert_int(recorder.directives.size()).is_equal(1)
	assert_str(String(recorder.directives[0]["op"])).is_equal("remote_action")
	assert_str(String(recorder.directives[0]["payload"]["screen_id"])).is_equal("test:screen")
	assert_str(String(recorder.directives[0]["payload"]["op"])).is_equal("toggle_hatch")

	# Autoridad (ya sin rol de render-esclavo): la directiva ejecuta la accion de verdad.
	rcm.is_render_slave_active = false
	rcm._on_client_ui_directive(String(recorder.directives[0]["op"]), recorder.directives[0]["payload"])
	assert_int(screen.calls.size()).is_equal(1)
	assert_str(String(screen.calls[0]["op"])).is_equal("toggle_hatch")

	suit_os.unregister_screen(screen)
	rcm.server = prev_server
	rcm.is_render_slave_active = prev_active
	rcm.is_host_active = prev_host_active
	rcm.set_process(prev_processing)


# Pantalla de SuitOS con foco: verifica que elegir una pantalla en el drawer del esclavo le
# pide el foco a la autoridad. Es lo que mueve la camara cinematica (sintoma 2): el foco
# local esta bloqueado por el guard de K2, asi que sin esto no pasaba nada.
class FakeFocusScreen extends Reference:
	var focused_calls := 0
	var exited_calls := 0
	func screen_id() -> String:
		return "test:focus_screen"
	func enter_focus_mode() -> void:
		focused_calls += 1
	func exit_focus_mode() -> void:
		exited_calls += 1


func test_render_slave_screen_select_reaches_authority_focus():
	var rcm = get_node("/root/RemoteControlManager")
	var suit_os = get_node("/root/SuitOS")
	var prev_active: bool = rcm.is_render_slave_active
	var prev_server = rcm.server
	var prev_host_active: bool = rcm.is_host_active
	var prev_processing: bool = rcm.is_processing()
	var recorder = auto_free(DirectiveRecorder.new())
	rcm.server = recorder
	rcm.is_render_slave_active = true
	rcm.is_host_active = false
	rcm.set_process(false)

	var screen = auto_free(FakeFocusScreen.new())
	suit_os.register_screen(screen)

	# Esclavo: abrir la pantalla en el HUD local reenvia la eleccion (y el visual es local).
	assert_bool(suit_os.open_screen("test:focus_screen")).is_true()
	assert_int(recorder.directives.size()).is_equal(1)
	assert_str(String(recorder.directives[0]["op"])).is_equal("screen_select")
	assert_str(String(recorder.directives[0]["payload"]["id"])).is_equal("test:focus_screen")

	# Autoridad: la abre en su nivel simulado y le pide el foco.
	rcm.is_render_slave_active = false
	rcm._on_client_ui_directive("screen_select", recorder.directives[0]["payload"])
	assert_int(screen.focused_calls).is_equal(1)
	assert_str(String(suit_os.get_active_screen_id())).is_equal("test:focus_screen")

	# Cerrar la pantalla suelta el foco.
	rcm._on_client_ui_directive("screen_select", {"id": ""})
	assert_int(screen.exited_calls).is_equal(1)
	assert_str(String(suit_os.get_active_screen_id())).is_equal("")

	suit_os.unregister_screen(screen)
	rcm.server = prev_server
	rcm.is_render_slave_active = prev_active
	rcm.is_host_active = prev_host_active
	rcm.set_process(prev_processing)
