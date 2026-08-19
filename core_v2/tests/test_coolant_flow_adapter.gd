extends GdUnitTestSuite

const PipeNetworkResourceScript := preload("res://core_v2/systems/pipe/PipeNetworkResource.gd")
const CoolantFlowAdapterScript := preload("res://core_v2/systems/cryo/CoolantFlowAdapter.gd")

class MockValve extends Node:
	signal valve_state_changed(is_open)
	var _open: bool = true

	func _init(p_open: bool = true) -> void:
		_open = p_open

	func is_open() -> bool:
		return _open

	func set_open(p_open: bool) -> void:
		_open = p_open
		emit_signal("valve_state_changed", _open)


class MockLeak extends Node:
	signal state_changed(new_state)
	var _intensity: float = 0.0

	func _init(p_intensity: float = 0.0) -> void:
		_intensity = p_intensity

	func get_leak_intensity() -> float:
		return _intensity

	func set_intensity(p_intensity: float) -> void:
		_intensity = p_intensity
		emit_signal("state_changed", 0)


class MockPipeRun extends Node:
	var flow_speed: float = 0.0
	var flow_intensity: float = 0.0

	func set_flow_speed(v: float) -> void:
		flow_speed = v

	func set_flow_intensity(v: float) -> void:
		flow_intensity = v


class MockTank extends Node:
	var tank_level: float = 1.0
	var drain_rate: float = 0.1

	func set_tank_level(v: float) -> void:
		tank_level = v


func test_flow_prefix_scan() -> void:
	var root: Node = auto_free(Node.new())
	root.name = "Root"

	var tank: MockTank = MockTank.new()
	tank.name = "Tank"
	root.add_child(tank)

	var p0: MockPipeRun = MockPipeRun.new()
	p0.name = "Pipe0"
	root.add_child(p0)

	var p1: MockPipeRun = MockPipeRun.new()
	p1.name = "Pipe1"
	root.add_child(p1)

	var p2: MockPipeRun = MockPipeRun.new()
	p2.name = "Pipe2"
	root.add_child(p2)

	var v2: MockValve = MockValve.new(false) # Closed valve at segment 2
	v2.name = "Valve2"
	root.add_child(v2)

	var p3: MockPipeRun = MockPipeRun.new()
	p3.name = "Pipe3"
	root.add_child(p3)

	var net: Resource = auto_free(Resource.new())
	net.set_script(PipeNetworkResourceScript)
	net.set("branches", {
		"west": {
			"tank": NodePath("Tank"),
			"segments": [
				{"pipe_run": NodePath("Pipe0"), "valve": NodePath(""), "leak": NodePath(""), "flow_dir": Vector3.FORWARD},
				{"pipe_run": NodePath("Pipe1"), "valve": NodePath(""), "leak": NodePath(""), "flow_dir": Vector3.FORWARD},
				{"pipe_run": NodePath("Pipe2"), "valve": NodePath("Valve2"), "leak": NodePath(""), "flow_dir": Vector3.FORWARD},
				{"pipe_run": NodePath("Pipe3"), "valve": NodePath(""), "leak": NodePath(""), "flow_dir": Vector3.FORWARD}
			]
		}
	})

	var adapter: Node = auto_free(Node.new())
	adapter.set_script(CoolantFlowAdapterScript)
	adapter.set("network", net)
	adapter.set("branch_id", "west")
	root.add_child(adapter)

	adapter._ready()

	# Verify prefix scan logic
	assert_float(adapter.get_segment_flow(0)).is_greater(0.0)
	assert_float(adapter.get_segment_flow(1)).is_greater(0.0)
	assert_float(adapter.get_segment_flow(2)).is_equal(0.0)
	assert_float(adapter.get_segment_flow(3)).is_equal(0.0)

	# Open valve at segment 2 and verify signal updates downstream flows
	v2.set_open(true)
	assert_float(adapter.get_segment_flow(2)).is_greater(0.0)
	assert_float(adapter.get_segment_flow(3)).is_greater(0.0)


func test_leak_kills_downstream() -> void:
	var root: Node = auto_free(Node.new())
	root.name = "Root"

	var tank: MockTank = MockTank.new()
	tank.name = "Tank"
	root.add_child(tank)

	var p0: MockPipeRun = MockPipeRun.new()
	p0.name = "Pipe0"
	root.add_child(p0)

	var p1: MockPipeRun = MockPipeRun.new()
	p1.name = "Pipe1"
	root.add_child(p1)

	var l1: MockLeak = MockLeak.new(1.0) # Leak with intensity 1.0 at segment 1
	l1.name = "Leak1"
	root.add_child(l1)

	var p2: MockPipeRun = MockPipeRun.new()
	p2.name = "Pipe2"
	root.add_child(p2)

	var net: Resource = auto_free(Resource.new())
	net.set_script(PipeNetworkResourceScript)
	net.set("branches", {
		"west": {
			"tank": NodePath("Tank"),
			"segments": [
				{"pipe_run": NodePath("Pipe0"), "valve": NodePath(""), "leak": NodePath(""), "flow_dir": Vector3.FORWARD},
				{"pipe_run": NodePath("Pipe1"), "valve": NodePath(""), "leak": NodePath("Leak1"), "flow_dir": Vector3.FORWARD},
				{"pipe_run": NodePath("Pipe2"), "valve": NodePath(""), "leak": NodePath(""), "flow_dir": Vector3.FORWARD}
			]
		}
	})

	var adapter: Node = auto_free(Node.new())
	adapter.set_script(CoolantFlowAdapterScript)
	adapter.set("network", net)
	adapter.set("branch_id", "west")
	root.add_child(adapter)

	adapter._ready()

	# Upstream flow (segment 0) is active
	assert_float(adapter.get_segment_flow(0)).is_equal(1.0)

	# Leak at segment 1 with intensity 1.0 absorbs flow -> segment 1 flow is 0.0
	assert_float(adapter.get_segment_flow(1)).is_equal(0.0)

	# Downstream flow (segment 2) remains 0.0
	assert_float(adapter.get_segment_flow(2)).is_equal(0.0)

	# is_pressurized_at() responde por el caudal de ENTRADA al tramo (lo que empuja
	# contra la fisura), no por lo que sale después de que la propia fuga lo consume.
	# Con el tanque lleno y sin válvulas cerradas aguas arriba, hay presión de entrada
	# aunque la fuga absorba el 100% de lo que sale — es justamente esa presión la
	# que sostiene la fuga y exige un parche provisorio, no firme (H6 / FD-270 §4).
	assert_bool(adapter.is_pressurized_at(l1)).is_equal(true)

	# Reduce leak intensity to 0.4 — el caudal de salida sube, la entrada no cambia
	l1.set_intensity(0.4)
	assert_float(adapter.get_segment_flow(1)).is_equal_approx(0.6, 0.0001)
	assert_float(adapter.get_segment_flow(2)).is_equal_approx(0.6, 0.0001)
	assert_bool(adapter.is_pressurized_at(l1)).is_equal(true)


func test_pressurized_at_false_when_upstream_valve_closed() -> void:
	var root: Node = auto_free(Node.new())
	root.name = "Root"

	var tank: MockTank = MockTank.new()
	tank.name = "Tank"
	root.add_child(tank)

	var v0: MockValve = MockValve.new(false) # Válvula cerrada, aguas arriba de la fuga
	v0.name = "Valve0"
	root.add_child(v0)

	var p0: MockPipeRun = MockPipeRun.new()
	p0.name = "Pipe0"
	root.add_child(p0)

	var l1: MockLeak = MockLeak.new(1.0)
	l1.name = "Leak1"
	root.add_child(l1)

	var net: Resource = auto_free(Resource.new())
	net.set_script(PipeNetworkResourceScript)
	net.set("branches", {
		"west": {
			"tank": NodePath("Tank"),
			"segments": [
				{"pipe_run": NodePath("Pipe0"), "valve": NodePath("Valve0"), "leak": NodePath("Leak1"), "flow_dir": Vector3.FORWARD}
			]
		}
	})

	var adapter: Node = auto_free(Node.new())
	adapter.set_script(CoolantFlowAdapterScript)
	adapter.set("network", net)
	adapter.set("branch_id", "west")
	root.add_child(adapter)

	adapter._ready()

	# Con la válvula cerrada, no hay presión de entrada al tramo — este es el caso
	# real que justifica un parche firme.
	assert_bool(adapter.is_pressurized_at(l1)).is_equal(false)

	v0.set_open(true)
	assert_bool(adapter.is_pressurized_at(l1)).is_equal(true)


func test_snapshot_restore() -> void:
	var root: Node = auto_free(Node.new())
	root.name = "Root"

	var tank: MockTank = MockTank.new()
	tank.name = "Tank"
	root.add_child(tank)

	var p0: MockPipeRun = MockPipeRun.new()
	p0.name = "Pipe0"
	root.add_child(p0)

	var p1: MockPipeRun = MockPipeRun.new()
	p1.name = "Pipe1"
	root.add_child(p1)

	var net: Resource = auto_free(Resource.new())
	net.set_script(PipeNetworkResourceScript)
	net.set("branches", {
		"west": {
			"tank": NodePath("Tank"),
			"segments": [
				{"pipe_run": NodePath("Pipe0"), "valve": NodePath(""), "leak": NodePath(""), "flow_dir": Vector3.FORWARD},
				{"pipe_run": NodePath("Pipe1"), "valve": NodePath(""), "leak": NodePath(""), "flow_dir": Vector3.FORWARD}
			]
		}
	})

	var adapter: Node = auto_free(Node.new())
	adapter.set_script(CoolantFlowAdapterScript)
	adapter.set("network", net)
	adapter.set("branch_id", "west")
	root.add_child(adapter)

	adapter._ready()

	var snap: Dictionary = adapter.get_snapshot()
	assert_bool(snap.has("segment_flows")).is_true()
	var flows: Array = snap["segment_flows"]
	assert_int(flows.size()).is_equal(2)

	# Simulate restoring snapshot with modified flows
	adapter.restore_snapshot({"segment_flows": [0.0, 0.0]})
	assert_float(adapter.get_segment_flow(0)).is_equal(0.0)
	assert_float(p0.flow_speed).is_equal(0.0)
