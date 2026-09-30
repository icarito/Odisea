extends GdUnitTestSuite

# test_snapshot_trace.gd - FD-316 (tarea DD): traza binaria de snapshots del render-esclavo.
# El benchmark graba en desktop durante un replay y reproduce solo-render en el Anbernic.

const RemoteProtocolScript = preload("res://core_v2/net/RemoteProtocol.gd")
const SnapshotTraceScript = preload("res://core_v2/net/SnapshotTrace.gd")

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
