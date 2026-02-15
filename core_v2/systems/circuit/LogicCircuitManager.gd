extends Spatial
class_name LogicCircuitManager

# LogicCircuitManager.gd
# Executes the logic circuit defined in CircuitGraphResource.
# Handles signal propagation and cable generation.
# Implements tick-based logic to handle loops and delays.

export(Resource) var circuit_data
export(bool) var auto_build_cables := false
export(PackedScene) var cable_scene # Optional custom cable scene, defaults to script

# Runtime state
var _runtime_nodes = {} # Map node_id -> RuntimeData
# RuntimeData: {
#   "type": "PROP" | "GATE",
#   "ref": Node (for PROP),
#   "gate_type": String (for GATE),
#   "delay_time": float (for DELAY GATE),
#   "state": bool (current output state),
#   "inputs": Dictionary { from_id: bool } (current input states)
# }

var _cables = {} # Map connection_hash -> CircuitCable

# Event Queues
var _input_queue = [] # Array of { target: String, input: String, value: bool }
var _output_queue = [] # Array of { source: String, value: bool, delay: float }

const MAX_LOGIC_STEPS = 100

func _ready():
	if circuit_data:
		_build_runtime_logic()
		if auto_build_cables:
			generate_cables()

func _physics_process(delta: float):
	step(delta)

func step(delta: float):
	# 1. Advance delays
	var ready_outputs = []
	var keep_outputs = []

	for out_evt in _output_queue:
		if out_evt.delay > 0:
			out_evt.delay -= delta
			if out_evt.delay <= 0:
				ready_outputs.append(out_evt)
			else:
				keep_outputs.append(out_evt)
		else:
			ready_outputs.append(out_evt)

	_output_queue = keep_outputs

	# 2. Iterative Logic Propagation
	var iterations = 0
	while (not ready_outputs.empty() or not _input_queue.empty()) and iterations < MAX_LOGIC_STEPS:
		iterations += 1

		# Process Outputs -> Inputs
		# If we have ready outputs, apply them to connections
		var current_outputs = ready_outputs
		ready_outputs = [] # Clear for next sub-step (new 0-delay outputs will go here? No, to _output_queue)

		for out_evt in current_outputs:
			_apply_output_change(out_evt.source, out_evt.value)

		# Process Inputs -> Outputs
		# If we have inputs, evaluate logic
		var current_inputs = _input_queue
		_input_queue = []

		for in_evt in current_inputs:
			_process_input_change(in_evt.target, in_evt.input, in_evt.value)

		# Check for new 0-delay outputs generated in _process_input_change
		# Move them from _output_queue to ready_outputs for next iteration
		var next_keep = []
		for out_evt in _output_queue:
			if out_evt.delay <= 0:
				ready_outputs.append(out_evt)
			else:
				next_keep.append(out_evt)
		_output_queue = next_keep

	if iterations >= MAX_LOGIC_STEPS:
		printerr("[LogicCircuitManager] Max logic steps reached. Possible infinite loop.")

func _build_runtime_logic():
	_runtime_nodes.clear()
	var nodes = circuit_data.nodes

	for id in nodes:
		var n_data = nodes[id]
		var r_data = {
			"type": n_data.get("type", "PROP"),
			"gate_type": n_data.get("gate_type", "AND"),
			"delay_time": n_data.get("delay_time", 1.0),
			"state": false,
			"inputs": {},
			"ref": null
		}

		if r_data.type == "PROP":
			var path = n_data.get("scene_path", NodePath())
			if path and not path.is_empty():
				var node = get_node_or_null(path)
				if node:
					r_data.ref = node
					# Connect signals
					if node.has_signal("activated"):
						node.connect("activated", self, "_on_prop_activated", [id])
					if node.has_signal("deactivated"):
						node.connect("deactivated", self, "_on_prop_deactivated", [id])

					# Initialize state from prop
					if node.get("is_active"):
						r_data.state = true

		_runtime_nodes[id] = r_data

	# Initial propagation
	for id in _runtime_nodes:
		var r_data = _runtime_nodes[id]
		if r_data.type == "PROP" and r_data.state:
			# Push initial state to output queue with 0 delay
			_output_queue.append({ "source": id, "value": true, "delay": 0.0 })

func _on_prop_activated(id: String):
	_output_queue.append({ "source": id, "value": true, "delay": 0.0 })

func _on_prop_deactivated(id: String):
	_output_queue.append({ "source": id, "value": false, "delay": 0.0 })

func _apply_output_change(source_id: String, value: bool):
	var r_data = _runtime_nodes[source_id]
	# Update internal state
	if r_data.state != value:
		r_data.state = value
		# If it's a Prop, ensure it matches (feedback prevention? No, Prop output drives logic)

	# Find connections
	for conn in circuit_data.connections:
		if conn.from == source_id:
			# Check cable
			var conn_hash = _get_connection_hash(conn)
			if _cables.has(conn_hash):
				var cable = _cables[conn_hash]
				if not is_instance_valid(cable) or (cable.has_method("is_broken") and cable.is_broken()):
					continue

			# Queue input update
			_input_queue.append({ "target": conn.to, "input": source_id, "value": value })

func _process_input_change(target_id: String, input_id: String, value: bool):
	if not _runtime_nodes.has(target_id):
		return

	var r_data = _runtime_nodes[target_id]
	r_data.inputs[input_id] = value

	# Evaluate Logic
	var new_state = false
	if r_data.type == "GATE":
		if r_data.gate_type == "DELAY":
			# For DELAY, we propagate the input value after delay?
			# Usually DELAY gate delays the signal.
			# If input changes, output changes after delay.
			# Assuming single input for DELAY.
			new_state = value # Pass through input

			if new_state != r_data.state:
				# Schedule output change
				# Note: We don't update r_data.state immediately for DELAY logic?
				# Actually, the output state changes later.
				# So we check against current state.
				# If we schedule multiple changes, the last one wins? Or a queue?
				# Simple delay: Schedule change.
				_output_queue.append({ "source": target_id, "value": new_state, "delay": r_data.delay_time })
				# We do NOT update r_data.state here. It updates when output is applied.
				# Wait, _apply_output_change updates r_data.state.
				return
		else:
			new_state = _evaluate_gate(r_data.gate_type, r_data.inputs)
			if new_state != r_data.state:
				_output_queue.append({ "source": target_id, "value": new_state, "delay": 0.0 })

	elif r_data.type == "PROP":
		# OR Logic for Props
		new_state = false
		for k in r_data.inputs:
			if r_data.inputs[k]:
				new_state = true
				break

		# Prop state change is handled by Prop itself?
		# LogicManager drives Prop.
		if new_state != r_data.state:
			# Update Prop
			if r_data.ref and r_data.ref.has_method("set_active"):
				r_data.ref.set_active(new_state)
			# We also update internal state immediately or wait for signal?
			# InteractableBaseV2 emits activated/deactivated.
			# This will loop back to _on_prop_activated -> _output_queue.
			# To avoid loop, check if state matches.
			# InteractableBaseV2.set_active checks `if is_active == value: return`.
			# So it won't emit signal if no change. Safe.
			pass

func _evaluate_gate(type: String, inputs: Dictionary) -> bool:
	var values = inputs.values()
	if values.empty():
		return false

	match type:
		"AND":
			for v in values:
				if not v: return false
			return true
		"OR":
			for v in values:
				if v: return true
			return false
		"XOR":
			var count = 0
			for v in values:
				if v: count += 1
			return count % 2 == 1
		"NOT":
			if values.size() > 0:
				return not values[0]
			return true
	return false

# --- Cable Generation ---

func generate_cables():
	# Clear existing cables
	for c in _cables.values():
		if is_instance_valid(c):
			c.queue_free()
	_cables.clear()

	for conn in circuit_data.connections:
		if conn.type == "WIRELESS":
			continue

		var from_node = _get_node_instance(conn.from)
		var to_node = _get_node_instance(conn.to)

		if from_node and to_node:
			var start_pos = _get_anchor_pos(from_node)
			var end_pos = _get_anchor_pos(to_node)

			var cable = _spawn_cable()
			var curve = Curve3D.new()
			_generate_catenary(curve, start_pos, end_pos)

			cable.path_curve = curve
			cable.build()

			# Listen for break
			cable.connect("connection_broken", self, "_on_cable_broken", [conn])

			var h = _get_connection_hash(conn)
			_cables[h] = cable

func _spawn_cable() -> CircuitCable:
	var c = null
	if cable_scene:
		c = cable_scene.instance()
	else:
		c = load("res://core_v2/systems/circuit/CircuitCable.gd").new()
	add_child(c)
	return c

func _get_node_instance(id: String) -> Spatial:
	if _runtime_nodes.has(id):
		return _runtime_nodes[id].ref
	return null

func _get_anchor_pos(node: Spatial) -> Vector3:
	# Check for "CableAnchor" child
	var anchor = node.find_node("CableAnchor", true, false)
	if anchor:
		return anchor.global_transform.origin
	return node.global_transform.origin

func _generate_catenary(curve: Curve3D, start: Vector3, end: Vector3, slack: float = 0.5):
	# Simplified Catenary: Parabola or Bezier with gravity sag
	# Convert global points to local to Manager (as cables are children of Manager)
	var local_start = to_local(start)
	var local_end = to_local(end)

	# Start point
	# Control points: in, out
	# For hanging cable, out vector points down/forward
	var dist = local_start.distance_to(local_end)
	var sag = dist * 0.2 + slack

	curve.add_point(local_start, Vector3.ZERO, Vector3(0, -sag, 0))
	curve.add_point(local_end, Vector3(0, -sag, 0), Vector3.ZERO)

func _on_cable_broken(conn: Dictionary):
	# Cut connection logically
	var target_id = conn.to
	var source_id = conn.from

	# Queue input update to false
	_input_queue.append({ "target": target_id, "input": source_id, "value": false })

	# Remove from managed cables
	var h = _get_connection_hash(conn)
	_cables.erase(h)

func _get_connection_hash(conn: Dictionary) -> String:
	return "%s:%d->%s:%d" % [conn.from, conn.from_port, conn.to, conn.to_port]
