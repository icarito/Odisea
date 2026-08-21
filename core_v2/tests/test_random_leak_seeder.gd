extends GdUnitTestSuite

const RandomLeakSeederScript := preload("res://core_v2/systems/cryo/RandomLeakSeeder.gd")


class MockLeakNode extends Spatial:
	var leak_triggered: bool = false

	func trigger_leak() -> void:
		leak_triggered = true


func test_random_leak_seeder_deterministic() -> void:
	var root: Node = auto_free(Node.new())
	add_child(root)

	var candidates := [
		NodePath("LeakA"),
		NodePath("LeakB"),
		NodePath("LeakC"),
		NodePath("LeakD"),
		NodePath("LeakE")
	]

	var seeder1: Node = auto_free(Node.new())
	seeder1.set_script(RandomLeakSeederScript)
	seeder1.set("seed", 12345)
	seeder1.leak_count = 3
	seeder1.candidate_leak_paths = candidates.duplicate()
	root.add_child(seeder1)

	var seeder2: Node = auto_free(Node.new())
	seeder2.set_script(RandomLeakSeederScript)
	seeder2.set("seed", 12345)
	seeder2.leak_count = 3
	seeder2.candidate_leak_paths = candidates.duplicate()
	root.add_child(seeder2)

	var snap1: Dictionary = seeder1.get_snapshot()
	var snap2: Dictionary = seeder2.get_snapshot()

	assert_array(snap1["active_leak_paths"]).is_equal(snap2["active_leak_paths"])
	assert_int(snap1["active_leak_paths"].size()).is_equal(3)


func test_random_leak_seeder_snapshot_roundtrip() -> void:
	var root: Node = auto_free(Node.new())
	add_child(root)

	var candidates := [
		NodePath("LeakA"),
		NodePath("LeakB"),
		NodePath("LeakC"),
		NodePath("LeakD")
	]

	var seeder1: Node = auto_free(Node.new())
	seeder1.set_script(RandomLeakSeederScript)
	seeder1.set("seed", 42)
	seeder1.leak_count = 2
	seeder1.candidate_leak_paths = candidates.duplicate()
	root.add_child(seeder1)

	var snap1: Dictionary = seeder1.get_snapshot()

	var seeder2: Node = auto_free(Node.new())
	seeder2.set_script(RandomLeakSeederScript)
	seeder2.set("seed", 99999)
	seeder2.leak_count = 2
	seeder2.candidate_leak_paths = candidates.duplicate()

	# Restore snapshot on seeder2
	seeder2.restore_snapshot(snap1)
	root.add_child(seeder2)

	var snap2: Dictionary = seeder2.get_snapshot()
	assert_array(snap2["active_leak_paths"]).is_equal(snap1["active_leak_paths"])


func test_restore_snapshot_before_ready() -> void:
	var root: Node = auto_free(Node.new())
	add_child(root)

	var seeder: Node = auto_free(Node.new())
	seeder.set_script(RandomLeakSeederScript)
	seeder.set("seed", 777)
	seeder.candidate_leak_paths = [NodePath("LeakA"), NodePath("LeakB"), NodePath("LeakC")]

	# Restoring before add_child / _ready()
	seeder.restore_snapshot({
		"seed": 42,
		"active_leak_paths": ["LeakC"]
	})

	root.add_child(seeder)

	var snap: Dictionary = seeder.get_snapshot()
	assert_array(snap["active_leak_paths"]).is_equal(["LeakC"])


func test_leak_activation_on_nodes() -> void:
	var root: Node = auto_free(Node.new())
	add_child(root)

	var leak_a: MockLeakNode = MockLeakNode.new()
	leak_a.name = "LeakA"
	root.add_child(leak_a)

	var leak_b: MockLeakNode = MockLeakNode.new()
	leak_b.name = "LeakB"
	root.add_child(leak_b)

	var leak_c: MockLeakNode = MockLeakNode.new()
	leak_c.name = "LeakC"
	root.add_child(leak_c)

	var seeder: Node = auto_free(Node.new())
	seeder.set_script(RandomLeakSeederScript)
	seeder.set("seed", 100)
	seeder.leak_count = 2
	seeder.candidate_leak_paths = [NodePath("LeakA"), NodePath("LeakB"), NodePath("LeakC")]
	root.add_child(seeder)

	var snap: Dictionary = seeder.get_snapshot()
	var active_paths: Array = snap["active_leak_paths"]

	for path_str in active_paths:
		var node = root.get_node(path_str)
		assert_bool(node.leak_triggered).is_false()

	seeder.activate_leaks()
	for path_str in active_paths:
		var node = root.get_node(path_str)
		assert_bool(node.leak_triggered).is_true()


func test_leak_count_exceeds_candidates() -> void:
	var root: Node = auto_free(Node.new())
	add_child(root)

	var seeder: Node = auto_free(Node.new())
	seeder.set_script(RandomLeakSeederScript)
	seeder.set("seed", 1)
	seeder.leak_count = 10
	seeder.candidate_leak_paths = [NodePath("LeakA"), NodePath("LeakB")]
	root.add_child(seeder)

	var snap: Dictionary = seeder.get_snapshot()
	assert_int(snap["active_leak_paths"].size()).is_equal(2)
