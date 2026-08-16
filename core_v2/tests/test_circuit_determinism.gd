extends GdUnitTestSuite

class DummyProp extends Spatial:
	signal activated()
	signal deactivated()

	var is_active: bool = false

	func set_active(v: bool) -> void:
		is_active = v

	func activate() -> void:
		is_active = true
		emit_signal("activated")

	func deactivate() -> void:
		is_active = false
		emit_signal("deactivated")


func _create_test_circuit() -> Dictionary:
	var manager_script = load("res://core_v2/systems/circuit/LogicCircuitManager.gd")
	var graph_script = load("res://core_v2/systems/circuit/CircuitGraphResource.gd")

	var manager: Spatial = auto_free(Spatial.new())
	manager.set_script(manager_script)

	var in1: DummyProp = auto_free(DummyProp.new())
	in1.name = "PropIn1"
	manager.add_child(in1)

	var in2: DummyProp = auto_free(DummyProp.new())
	in2.name = "PropIn2"
	manager.add_child(in2)

	var out: DummyProp = auto_free(DummyProp.new())
	out.name = "PropOut"
	manager.add_child(out)

	var graph: Resource = auto_free(Resource.new())
	graph.set_script(graph_script)

	graph.call("add_node", "prop_in1", {
		"type": "PROP",
		"scene_path": NodePath("PropIn1")
	})
	graph.call("add_node", "prop_in2", {
		"type": "PROP",
		"scene_path": NodePath("PropIn2")
	})
	graph.call("add_node", "gate_and", {
		"type": "GATE",
		"gate_type": "AND"
	})
	graph.call("add_node", "gate_delay", {
		"type": "GATE",
		"gate_type": "DELAY",
		"delay_time": 0.1
	})
	graph.call("add_node", "prop_out", {
		"type": "PROP",
		"scene_path": NodePath("PropOut")
	})

	graph.call("connect_nodes", "prop_in1", 0, "gate_and", 0)
	graph.call("connect_nodes", "prop_in2", 0, "gate_and", 1)
	graph.call("connect_nodes", "gate_and", 0, "gate_delay", 0)
	graph.call("connect_nodes", "gate_delay", 0, "prop_out", 0)

	manager.set("circuit_data", graph)
	add_child(manager)

	return {
		"manager": manager,
		"graph": graph,
		"in1": in1,
		"in2": in2,
		"out": out
	}


func test_circuit_manager_belongs_to_replay_sync_group() -> void:
	var circuit_data = _create_test_circuit()
	var manager: Spatial = circuit_data["manager"]
	assert_bool(manager.is_in_group("replay_sync")).is_true()


func test_circuit_snapshot_restore_determinism() -> void:
	var circuit_data = _create_test_circuit()
	var manager: Spatial = circuit_data["manager"]
	var in1: DummyProp = circuit_data["in1"]
	var in2: DummyProp = circuit_data["in2"]
	var out: DummyProp = circuit_data["out"]

	in1.activate()
	in2.activate()

	var dt: float = 1.0 / 60.0
	# Run 10 ticks
	for i in range(10):
		manager.call("step", dt)

	assert_bool(out.is_active).is_true()

	var snapshot: Dictionary = manager.call("get_snapshot")
	assert_dict(snapshot).contains_keys(["runtime_nodes", "input_queue", "output_queue"])

	# Create a second clean circuit to restore into
	var circuit_data2 = _create_test_circuit()
	var manager2: Spatial = circuit_data2["manager"]
	var out2: DummyProp = circuit_data2["out"]

	manager2.call("restore_snapshot", snapshot)

	assert_bool(out2.is_active).is_true()

	# Run 5 more ticks on both and verify state matches
	for i in range(5):
		manager.call("step", dt)
		manager2.call("step", dt)

	var snap_final1: Dictionary = manager.call("get_snapshot")
	var snap_final2: Dictionary = manager2.call("get_snapshot")

	assert_bool(snap_final1["runtime_nodes"]["prop_out"]["state"]).is_equal(snap_final2["runtime_nodes"]["prop_out"]["state"])
	assert_bool(out.is_active).is_equal(out2.is_active)


func test_delay_gate_pending_queue_snapshot_restore() -> void:
	var circuit_data = _create_test_circuit()
	var manager: Spatial = circuit_data["manager"]
	var in1: DummyProp = circuit_data["in1"]
	var in2: DummyProp = circuit_data["in2"]
	var out: DummyProp = circuit_data["out"]

	in1.activate()
	in2.activate()

	var dt: float = 1.0 / 60.0
	# Step 2 ticks: delay_time is 0.1s (~6-7 ticks total). Pending output is in output_queue with remaining delay
	for i in range(2):
		manager.call("step", dt)

	assert_bool(out.is_active).is_false()

	var snap_mid: Dictionary = manager.call("get_snapshot")
	var out_q: Array = snap_mid.get("output_queue", [])
	assert_bool(out_q.size() > 0).is_true()
	assert_str(String(out_q[0].get("source", ""))).is_equal("gate_delay")
	assert_bool(float(out_q[0].get("delay", 0.0)) > 0.0).is_true()

	# Create restored circuit manager and load mid-delay snapshot
	var circuit_data_restored = _create_test_circuit()
	var manager_restored: Spatial = circuit_data_restored["manager"]
	var out_restored: DummyProp = circuit_data_restored["out"]

	manager_restored.call("restore_snapshot", snap_mid)

	# Step tick-by-tick and verify both managers remain identical at every tick
	var triggered: bool = false
	for i in range(10):
		manager.call("step", dt)
		manager_restored.call("step", dt)
		assert_bool(out_restored.is_active).is_equal(out.is_active)
		if out.is_active:
			triggered = true
			break

	assert_bool(triggered).is_true()
	assert_bool(out.is_active).is_true()
	assert_bool(out_restored.is_active).is_true()


func test_restore_snapshot_tolerates_missing_or_extra_node_ids() -> void:
	var circuit_data = _create_test_circuit()
	var manager: Spatial = circuit_data["manager"]

	var bad_snapshot = {
		"runtime_nodes": {
			"non_existent_node_99": {
				"state": true,
				"inputs": {"unknown": true}
			}
		},
		"input_queue": [
			{"target": "unknown_target", "input": "unknown_input", "value": true}
		],
		"output_queue": [
			{"source": "unknown_source", "value": true, "delay": 0.5}
		]
	}

	# Should tolerate missing/unknown nodes without throwing errors or crashing
	manager.call("restore_snapshot", bad_snapshot)
	var snap: Dictionary = manager.call("get_snapshot")
	assert_dict(snap).contains_keys(["runtime_nodes", "input_queue", "output_queue"])
