extends GdUnitTestSuite

# test_remote_sim.gd - FD-316: Tests for remote simulation protocol, interpolation buffer, and offload roles.

const RemoteProtocolScript = preload("res://core_v2/net/RemoteProtocol.gd")
const RemoteSimHostScript = preload("res://core_v2/net/RemoteSimHost.gd")
const RemoteSimClientScript = preload("res://core_v2/net/RemoteSimClient.gd")
const PlayerScript = preload("res://core_v2/player/PlayerControllerV2.gd")

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

	var config = RemoteProtocolScript.create_sim_config(60, 1, "tok123")
	assert_str(config["type"]).is_equal("sim_config")
	assert_int(config["tick_rate"]).is_equal(60)
	assert_int(config["interp_buffer_ticks"]).is_equal(1)

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

func test_client_interpolation_buffer():
	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)

	var snap1 = RemoteProtocolScript.create_sim_snapshot(1, 100, {})
	var snap2 = RemoteProtocolScript.create_sim_snapshot(2, 116, {})
	var snap3 = RemoteProtocolScript.create_sim_snapshot(3, 133, {})

	# Receive out of order
	client.receive_snapshot(snap2)
	client.receive_snapshot(snap1)
	client.receive_snapshot(snap3)

	assert_int(client._buffer.size()).is_equal(3)
	assert_int(client._buffer[0]["tick"]).is_equal(1)
	assert_int(client._buffer[1]["tick"]).is_equal(2)
	assert_int(client._buffer[2]["tick"]).is_equal(3)

func test_render_slave_disables_physics():
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
	# recien entonces el tick produce un snapshot.
	assert_bool(host._attach_sim_level(_make_sim_level(), {})).is_true()
	assert_bool(host.sim_ready).is_true()
	host._physics_process(1.0 / 60.0)
	assert_int(_emitted_snapshots.size()).is_equal(1)
	assert_int(int(_emitted_snapshots[0]["tick"])).is_equal(1)

	host.stop_simulation()
	assert_bool(host.sim_ready).is_false()


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
	var sim_input = RemoteProtocolScript.create_sim_input(axes, buttons, 42, "tok_test")

	assert_str(sim_input["type"]).is_equal("sim_input")
	assert_float(sim_input["axes"]["move_x"]).is_equal(1.0)
	assert_bool(sim_input["buttons"]["jump"]).is_true()
	assert_int(sim_input["last_tick"]).is_equal(42)

	# FD-316: el look de camara viaja en su propio campo (no es accion del InputMap).
	var with_camera = RemoteProtocolScript.create_sim_input(axes, buttons, 43, "tok_test",
		{"x": 3.0, "y": -2.0, "touch_x": 1.0, "touch_y": 0.5, "zoom": 0.25})
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
		"", {"x": 3.0, "y": -2.0, "touch_x": 1.0, "touch_y": 0.5, "zoom": 0.25}), "client")
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
		{"move_x": 0.5, "move_y": 0.25}, {"jump": true, "interact": true}, 1), "client")
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
		{"move_x": 0.0, "move_y": 0.0}, {"jump": false, "interact": false}, 2), "client")
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
