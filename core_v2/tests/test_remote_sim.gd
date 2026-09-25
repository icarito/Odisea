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
