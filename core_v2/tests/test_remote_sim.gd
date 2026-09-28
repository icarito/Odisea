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

	client.start_render_slave(0)
	client.receive_snapshot(RemoteProtocolScript.create_sim_snapshot(7, 100, {}, {"scene": "x"}, "t"))
	assert_bool(client.is_engaged()).is_true()
	assert_bool(audio._render_slave_audio_muted).is_true()
	assert_bool(client._interaction_authority_applied).is_true()
	assert_bool(player.is_remote_render_slave()).is_true()

	client.stop_render_slave()
	assert_bool(client.is_engaged()).is_false()
	assert_bool(audio._render_slave_audio_muted).is_false()
	assert_bool(client._interaction_authority_applied).is_false()
	assert_bool(player.is_remote_render_slave()).is_false()
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
func _make_sim_level() -> Spatial:
	var level := Spatial.new()
	level.name = "SimLevel"
	var fake = auto_free(FakePlayer.new())
	fake.name = "Player"
	fake.add_to_group("player")
	fake.add_to_group("replay_sync")
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

class FakePlayer extends Spatial:
	var velocity := Vector3(0, 0, 3)
	func is_effectively_grounded() -> bool:
		return true


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
# encolado en _client_input_state sin aplicarse a ninguna accion del InputMap: el
# personaje nunca se movia en la simulacion y por eso jamas se acercaba a un interactuable.
func test_sim_host_applies_client_input_to_engine():
	var host = auto_free(RemoteSimHostScript.new())
	add_child(host)

	var press = RemoteProtocolScript.create_sim_input({"move_x": 1.0}, {"interact": true}, 1)
	host.receive_sim_input(press, "client")
	host._process_input_queue_for_tick(1)

	assert_bool(Input.is_action_pressed("move_right")).is_true()
	assert_bool(Input.is_action_pressed("interact")).is_true()

	# El proximo estado del cliente ya no tiene esas acciones: se sueltan, no quedan pegadas.
	var release = RemoteProtocolScript.create_sim_input({"move_x": 0.0}, {"interact": false}, 2)
	host.receive_sim_input(release, "client")
	host._process_input_queue_for_tick(2)

	assert_bool(Input.is_action_pressed("move_right")).is_false()
	assert_bool(Input.is_action_pressed("interact")).is_false()

	host.stop_simulation()


# FD-316: entrar/salir del rol render-esclavo YA NO muta al promover: el mute (y la
# cesion de fisica/interaccion) ocurre con el primer snapshot valido — ver
# test_render_slave_does_not_engage_on_promotion / test_render_slave_engages_on_first_valid_snapshot.
