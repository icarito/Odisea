extends GdUnitTestSuite

# test_snapshot_trace.gd - FD-316 (tarea DD): traza binaria de snapshots del render-esclavo.
# El benchmark graba en desktop durante un replay y reproduce solo-render en el Anbernic.

const RemoteProtocolScript = preload("res://core_v2/net/RemoteProtocol.gd")
const SnapshotTraceScript = preload("res://core_v2/net/SnapshotTrace.gd")
const RemoteSimClientScript = preload("res://core_v2/net/RemoteSimClient.gd")

const TRACE_PATH := "user://test_snapshot_trace.bin"

# Roundtrip: N snapshots (con Transform y globals) escritos con var2bytes y releidos.
func test_snapshot_trace_roundtrip():
	var snaps: Array = []
	for i in range(5):
		var t := Transform(Basis(), Vector3(i, i * 2, -i))
		snaps.append(RemoteProtocolScript.create_sim_snapshot(i, i * 16, {
			"Rig": {"t": t, "v": true}
		}, {"cam_t": t, "snap_step": 2}))

	assert_bool(SnapshotTraceScript.write(TRACE_PATH, snaps)).is_true()
	assert_int(SnapshotTraceScript.count(TRACE_PATH)).is_equal(5)

	var read := SnapshotTraceScript.read(TRACE_PATH)
	assert_int(read.size()).is_equal(5)
	for i in range(5):
		assert_int(int(read[i]["tick"])).is_equal(i)
		var dec = RemoteProtocolScript.decode_transform(read[i]["entities"]["Rig"]["t"])
		assert_vector3(dec.origin).is_equal_approx(Vector3(i, i * 2, -i), Vector3.ONE * 0.001)
		assert_bool(bool(read[i]["entities"]["Rig"]["v"])).is_true()

	var dir := Directory.new()
	dir.remove(TRACE_PATH)

# El Reader del playback decodifica de a uno, sin retener la traza entera en memoria.
func test_snapshot_trace_reader_decodes_incrementally():
	var snaps: Array = []
	for i in range(4):
		snaps.append(RemoteProtocolScript.create_sim_snapshot(i, i * 16, {}, {"snap_step": 2}))
	SnapshotTraceScript.write(TRACE_PATH, snaps)

	var reader = SnapshotTraceScript.Reader.new(TRACE_PATH)
	assert_bool(reader.is_open()).is_true()
	assert_int(reader.count()).is_equal(4)
	var seen := 0
	while reader.has_next():
		var snap: Dictionary = reader.next()
		assert_int(int(snap["tick"])).is_equal(seen)
		seen += 1
	assert_int(seen).is_equal(4)
	assert_bool(reader.has_next()).is_false()
	reader.close()

	var dir := Directory.new()
	dir.remove(TRACE_PATH)

# Playback solo-render: el cliente alimenta el nivel desde el archivo (sin red), compromete
# el mismo congelado del offload y aplica el transform del snapshot mas nuevo.
func test_snapshot_playback_applies_without_network_and_freezes():
	var level := Spatial.new()
	level.name = "PlaybackLevel"
	var box := Spatial.new()
	box.name = "Box"
	level.add_child(box)
	var player := Spatial.new()
	player.name = "Pilot"
	player.add_to_group("player")
	level.add_child(player)

	var previous_scene = get_tree().current_scene
	get_tree().root.add_child(level)
	get_tree().current_scene = level

	var snaps: Array = []
	snaps.append(RemoteProtocolScript.create_sim_snapshot(0, 0, {
		"Box": {"t": Transform(Basis(), Vector3(0, 0, 0))}}, {"snap_step": 2}))
	snaps.append(RemoteProtocolScript.create_sim_snapshot(1, 16, {
		"Box": {"t": Transform(Basis(), Vector3(3, 0, 0))}}, {"snap_step": 2}))
	snaps.append(RemoteProtocolScript.create_sim_snapshot(2, 32, {
		"Box": {"t": Transform(Basis(), Vector3(6, 0, 0))}}, {"snap_step": 2}))
	SnapshotTraceScript.write(TRACE_PATH, snaps)

	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)
	assert_bool(client.start_snapshot_playback(TRACE_PATH)).is_true()
	# Sin red: no escucha UDP ni tiene destino al que mandar input.
	assert_bool(client.is_render_slave).is_true()
	assert_bool(client._playback_active).is_true()
	assert_int(client._listening_port).is_equal(0)
	assert_str(client._target_ip).is_equal("")

	# Se alimentan los ticks 0 y 2; el tick 1 se salta por el paso de la traza.
	assert_bool(client._feed_next_playback_snapshot()).is_true()
	assert_bool(client._feed_next_playback_snapshot()).is_true()
	assert_bool(client.is_engaged()).is_true()
	assert_bool(client._freezer.frozen_root_is(level)).is_true()

	# El snapshot mas nuevo se aplica al nivel (alpha 1 sobre el tick 2).
	client._render_tick = 2.0
	client._render_interpolated()
	assert_vector3(box.global_transform.origin).is_equal_approx(
		Vector3(6, 0, 0), Vector3.ONE * 0.001)

	client.stop_render_slave()
	assert_bool(client._freezer.is_frozen()).is_false()
	if previous_scene != null:
		get_tree().current_scene = previous_scene
	level.queue_free()
	var dir := Directory.new()
	dir.remove(TRACE_PATH)

# Al agotarse el archivo el playback vuelca la traza de perf (fps, frame_ms, script/render/
# apply/interp, draw_calls, vertices, objetos por muestra) en user://replay_perf.json.
func test_snapshot_playback_writes_perf_trace_at_end():
	var level := Spatial.new()
	level.name = "PerfLevel"
	var player := Spatial.new()
	player.name = "Pilot"
	player.add_to_group("player")
	level.add_child(player)

	var previous_scene = get_tree().current_scene
	get_tree().root.add_child(level)
	get_tree().current_scene = level

	var snaps: Array = []
	for i in range(3):
		snaps.append(RemoteProtocolScript.create_sim_snapshot(i * 2, i * 32, {}, {"snap_step": 2}))
	SnapshotTraceScript.write(TRACE_PATH, snaps)

	var client = auto_free(RemoteSimClientScript.new())
	add_child(client)
	assert_bool(client.start_snapshot_playback(TRACE_PATH)).is_true()

	# Dos frames del reloj de playback: cada uno alimenta un snapshot y arma su muestra.
	client._process(1.0 / 30.0)
	client._process(1.0 / 30.0)
	assert_int(client._playback_samples.size()).is_greater_equal(1)

	# Fin de la traza (quit_game=false no mata el runner de tests).
	client._finish_playback(false)
	assert_bool(client._playback_active).is_false()
	assert_bool(client._playback_finished).is_true()

	var f := File.new()
	assert_int(f.open(RemoteSimClientScript.PLAYBACK_PERF_PATH, File.READ)).is_equal(OK)
	var data = JSON.parse(f.get_as_text()).result
	f.close()
	assert_bool(data is Dictionary).is_true()
	assert_str(String(data["modo"])).is_equal("snapshot_playback")
	assert_int(int(data["total"])).is_equal(client._playback_samples.size())
	assert_int(int(data["total"])).is_greater_equal(1)
	var sample: Dictionary = data["muestras"][0]
	for key in ["fps", "frame_ms", "script_ms", "render_ms", "apply_ms", "interp_ms",
			"draw_calls", "vertices", "objects"]:
		assert_bool(sample.has(key)).is_true()

	client.stop_render_slave()
	if previous_scene != null:
		get_tree().current_scene = previous_scene
	level.queue_free()
	var dir := Directory.new()
	dir.remove(TRACE_PATH)
	dir.remove(RemoteSimClientScript.PLAYBACK_PERF_PATH)

