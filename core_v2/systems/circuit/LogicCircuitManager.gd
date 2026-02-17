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
            if Engine.editor_hint and not (cable_scene and cable_scene is PackedScene):
                printerr("[LogicCircuitManager] auto_build_cables is true but running in editor without a 'cable_scene' assigned — skipping generation to avoid crashes")
            else:
                call_deferred("defer_generate_cables")

func defer_generate_cables():
    yield(get_tree(), "idle_frame")
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
    if not is_inside_tree():
        return

    for conn in circuit_data.connections:
        if conn.type == "WIRELESS":
            continue

        var from_node = _get_node_instance(conn.from)
        var to_node = _get_node_instance(conn.to)

        if not from_node or not to_node:
            continue

        var start_pos = _get_anchor_pos(from_node)
        var end_pos = _get_anchor_pos(to_node)

        var cable = _spawn_cable()
        var curve = Curve3D.new()
        _generate_catenary(curve, start_pos, end_pos)

        if cable.has_method("init_from_curve"):
            cable.init_from_curve(curve)
        else:
            printerr("[LogicCircuitManager] Cable instance does not support init_from_curve, skipping cable.")

        _cables[_get_connection_hash(conn)] = cable
    # Clear existing cables
    for c in _cables.values():
        if is_instance_valid(c):
            c.queue_free()
    _cables.clear()

    for conn in circuit_data.connections:
        # skip wireless connections
        if conn.type == "WIRELESS":
            continue

        var from_node = _get_node_instance(conn.from)
        var to_node = _get_node_instance(conn.to)

        if not from_node or not to_node:
            continue

        var start_pos = _get_anchor_pos(from_node)
        var end_pos = _get_anchor_pos(to_node)

        print("[Debug] LogicCircuitManager::Cable Position Debug --> Start Position: ", start_pos, " End Position: ", end_pos) # Ensure DEBUG'able positions.
        print("[LogicCircuitManager] Generating cable for connection:", conn)

        # Debug spheres at anchors for visibility
        var s1 = CSGSphere.new()
        s1.radius = 0.5
        s1.material = SpatialMaterial.new()
        s1.material.emission_enabled = true
        s1.material.emission = Color(1.0,0,0)
        s1.material.albedo_color = Color(1.0,0,0)
        s1.global_transform.origin = start_pos
        add_child(s1)
        var s2 = CSGSphere.new()
        s2.radius = 0.5
        s2.material = SpatialMaterial.new()
        s2.material.emission_enabled = true
        s2.material.emission = Color(0,1.0,0)
        s2.material.albedo_color = Color(0,1.0,0)
        s2.global_transform.origin = end_pos
        add_child(s2)

        var cable = _spawn_cable()
        print("[LogicCircuitManager] cable node type: ", typeof(cable), cable)
        var curve = Curve3D.new()
        _generate_catenary(curve, start_pos, end_pos)

        # Apply curve and build depending on cable implementation
        var applied = false
        if cable and cable.has_method("init_from_curve"):
            # Preferred API: CircuitCable.init_from_curve(curve)
            cable.init_from_curve(curve)
            applied = true
        else:
            # Try property + build using a robust property-list check
            if cable:
                var has_path_prop = false
                var prop_list = []
                # get_property_list may return array of dictionaries describing properties
                if cable.has_method("get_property_list"):
                    prop_list = cable.get_property_list()
                for p in prop_list:
                    if typeof(p) == TYPE_DICTIONARY and p.has("name") and p["name"] == "path_curve":
                        has_path_prop = true
                        break

                if has_path_prop:
                    cable.path_curve = curve
                    if cable.has_method("build"):
                        cable.build()
                    applied = true
                elif cable.has_method("init_from_curve"):
                    # fallback to init_from_curve if it exists
                    cable.init_from_curve(curve)
                    applied = true
                elif cable.has_method("build"):
                    # As a last resort, call build() even if we couldn't set path_curve
                    cable.build()
                    applied = true

        if not applied:
            printerr("[LogicCircuitManager] Created cable instance does not implement expected API; skipping visuals for", conn)

        # Connect break signal if possible
        if cable and cable.has_method("connect"):
            # Wrap in try/catch style guard: connect may fail if signal doesn't exist
            var ok_conn = true
            # Avoid throwing if the node is a plain Spatial
            if cable.has_signal("connection_broken"):
                cable.connect("connection_broken", self, "_on_cable_broken", [conn])

        var h = _get_connection_hash(conn)
        _cables[h] = cable

func _spawn_cable() -> CircuitCable:
    var c = null

    if cable_scene and cable_scene is PackedScene:
        c = cable_scene.instance()
    else:
        var script_path = "res://core_v2/systems/circuit/CircuitCable.gd"
        if ResourceLoader.exists(script_path):
            var script_res = load(script_path)
            if script_res and script_res is Script:
                c = script_res.new()

    if not c:
        c = Spatial.new()

    add_child(c)
    return c
    # Preferred: try to instantiate from the GDScript class (most robust in headless/test env)
    if not c:
        var script_path = "res://core_v2/systems/circuit/CircuitCable.gd"
        print("[LogicCircuitManager] Checking script path exists:", script_path, ResourceLoader.exists(script_path))
        if ResourceLoader.exists(script_path):
            var script_res = load(script_path)
            print("[LogicCircuitManager] Loaded resource:", script_res, " type:", typeof(script_res))
            if script_res and script_res is Script:
                print("[LogicCircuitManager] Resource is Script. Attempting .new() instantiation...")
                var inst = null
                # Try to instantiate and capture result
                inst = script_res.new()
                if inst:
                    c = inst
                    print("[LogicCircuitManager] .new() returned instance:", c, "class:", c.get_class())
                    # Print its exported/property list for diagnostics
                    var prop_names = []
                    for p in c.get_property_list():
                        var pname = p["name"] if (typeof(p) == TYPE_DICTIONARY and p.has("name")) else "<unknown>"
                        prop_names.append(pname)
                    print("[LogicCircuitManager] Instance properties:", prop_names)
                else:
                    printerr("[LogicCircuitManager] script_res.new() returned null")
            else:
                printerr("[LogicCircuitManager] CircuitCable.gd loaded but is not a Script resource; got:", script_res)

    # Next: try user-provided PackedScene
    if not c and cable_scene:
        if cable_scene is PackedScene:
            var inst2 = cable_scene.instance()
            if inst2:
                c = inst2
                print("[LogicCircuitManager] Instantiated cable_scene PackedScene ->", c, "class:", c.get_class())
                # diagnostic property list
                var prop_names2 = []
                for p in c.get_property_list():
                    var pname2 = p["name"] if (typeof(p) == TYPE_DICTIONARY and p.has("name")) else "<unknown>"
                    prop_names2.append(pname2)
                print("[LogicCircuitManager] cable_scene instance properties:", prop_names2)
            else:
                printerr("[LogicCircuitManager] cable_scene.instance() returned null")
        else:
            printerr("[LogicCircuitManager] cable_scene property is not a PackedScene")

    # As a last resort, try loading a tscn bundle (rare)
    if not c and ResourceLoader.exists("res://core_v2/systems/circuit/CircuitCable.tscn"):
        var tscn_path = "res://core_v2/systems/circuit/CircuitCable.tscn"
        print("[LogicCircuitManager] Trying bundled scene:", tscn_path, ResourceLoader.exists(tscn_path))
        var bundled_scene = load(tscn_path)
        print("[LogicCircuitManager] loaded bundled resource:", bundled_scene, " type:", typeof(bundled_scene))
        if bundled_scene and bundled_scene is PackedScene:
            var inst3 = bundled_scene.instance()
            if inst3:
                c = inst3
                print("[LogicCircuitManager] Bundled tscn instantiated:", c, "class:", c.get_class())
            else:
                printerr("[LogicCircuitManager] Bundled CircuitCable.tscn instance() returned null")
        else:
            printerr("[LogicCircuitManager] Bundled resource is not a PackedScene or failed to load")

    # Final safety: create an empty Spatial so scene doesn't crash
    if not c:
        printerr("[LogicCircuitManager] All attempts to create a CircuitCable failed — using empty Spatial as fallback")
        c = Spatial.new()
    else:
        print("[LogicCircuitManager] Successfully instantiated cable node:", c, " type:", typeof(c), "class:", c.get_class())
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
