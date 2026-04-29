extends GdUnitTestSuite

func test_terminal_bridge_processes_pending_command_dictionary_without_dot_access_errors() -> void:
	var bridge_script: Script = load("res://core_v2/systems/circuit/CircuitTerminalBridge.gd")
	assert_object(bridge_script).is_not_null()

	var bridge: Node = auto_free(Node.new())
	bridge.set_script(bridge_script)
	add_child(bridge)

	bridge.send_terminal_command("activate", {"source": "test"})
	bridge.step(0.02)

	var pending: Array = bridge.get("_pending_commands")
	assert_int(pending.size()).is_equal(0)

func test_terminal_bridge_snapshot_includes_pending_args() -> void:
	var bridge_script: Script = load("res://core_v2/systems/circuit/CircuitTerminalBridge.gd")
	assert_object(bridge_script).is_not_null()

	var bridge: Node = auto_free(Node.new())
	bridge.set_script(bridge_script)
	add_child(bridge)

	bridge.send_terminal_command("toggle", {"source": "test"})
	var snapshot: Dictionary = bridge.get_snapshot()
	var pending: Array = snapshot.get("pending", [])

	assert_int(pending.size()).is_equal(1)
	assert_str(String(pending[0].get("command", ""))).is_equal("toggle")
	assert_dict(pending[0].get("args", {})).contains_keys(["source"])
