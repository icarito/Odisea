extends SceneTree

# test_circuit_logic.gd
# Tests the Logic Circuit System

func _init():
	print("Running Logic Circuit System Test...")

	# 1. Setup Scene
	var root = get_root()
	var test_node = Node.new()
	test_node.name = "TestRoot"
	root.add_child(test_node)

	# 2. Create Manager
	var LogicMgr = load("res://core_v2/systems/circuit/LogicCircuitManager.gd")
	var manager = LogicMgr.new()
	manager.name = "LogicManager"
	test_node.add_child(manager)

	# 3. Create Props
	var Interactable = load("res://core_v2/components/InteractableBaseV2.gd")

	var source_prop = Interactable.new()
	source_prop.name = "SourceProp"
	test_node.add_child(source_prop)

	var target_prop = Interactable.new()
	target_prop.name = "TargetProp"
	test_node.add_child(target_prop)

	# 4. Create Graph Resource
	var GraphRes = load("res://core_v2/systems/circuit/CircuitGraphResource.gd")
	var graph = GraphRes.new()

	# Add Nodes
	graph.add_node("node_a", {
		"type": "PROP",
		"scene_path": NodePath("../SourceProp"), # Relative to Manager
		"position": Vector2(0, 0)
	})

	graph.add_node("node_b", {
		"type": "PROP",
		"scene_path": NodePath("../TargetProp"),
		"position": Vector2(200, 0)
	})

	# Add Connection
	graph.connect_nodes("node_a", 0, "node_b", 0)

	# Assign to Manager
	manager.circuit_data = graph

	# 5. Initialize Runtime Logic
	manager._build_runtime_logic()

	# 6. Test Propagation
	print("Testing Direct Connection...")

	# Initial state: Both inactive
	manager.step(0.1)
	assert_state(target_prop, false, "Initial Target State")

	# Activate Source
	print("Activating Source...")
	source_prop.set_active(true)

	# Step logic (propagation delay 0)
	manager.step(0.1)

	# Assert Target is Active
	assert_state(target_prop, true, "Target after Source Activation")

	# Deactivate Source
	print("Deactivating Source...")
	source_prop.set_active(false)

	# Step logic
	manager.step(0.1)

	# Assert Target is Inactive
	assert_state(target_prop, false, "Target after Source Deactivation")

	# 7. Test Logic Gate (AND)
	print("Testing AND Gate...")

	var source_prop_2 = Interactable.new()
	source_prop_2.name = "SourceProp2"
	test_node.add_child(source_prop_2)

	# Update Graph
	graph.clear()
	graph.add_node("node_a", { "type": "PROP", "scene_path": NodePath("../SourceProp") })
	graph.add_node("node_c", { "type": "PROP", "scene_path": NodePath("../SourceProp2") })
	graph.add_node("node_b", { "type": "PROP", "scene_path": NodePath("../TargetProp") })
	graph.add_node("gate_and", { "type": "GATE", "gate_type": "AND" })

	graph.connect_nodes("node_a", 0, "gate_and", 0)
	graph.connect_nodes("node_c", 0, "gate_and", 0) # Same input port usually means list of inputs
	graph.connect_nodes("gate_and", 0, "node_b", 0)

	# Rebuild Logic
	manager._build_runtime_logic()

	# Reset Props
	source_prop.set_active(false)
	source_prop_2.set_active(false)
	target_prop.set_active(false)

	# 1. A=True, C=False -> AND=False -> B=False
	source_prop.set_active(true)
	manager.step(0.1)
	assert_state(target_prop, false, "AND Gate (T, F)")

	# 2. A=True, C=True -> AND=True -> B=True
	source_prop_2.set_active(true)
	manager.step(0.1)
	assert_state(target_prop, true, "AND Gate (T, T)")

	# 3. A=False, C=True -> AND=False -> B=False
	source_prop.set_active(false)
	manager.step(0.1)
	assert_state(target_prop, false, "AND Gate (F, T)")

	# 8. Test DELAY Gate
	print("Testing DELAY Gate...")
	graph.clear()
	graph.add_node("node_a", { "type": "PROP", "scene_path": NodePath("../SourceProp") })
	graph.add_node("node_b", { "type": "PROP", "scene_path": NodePath("../TargetProp") })
	graph.add_node("gate_delay", { "type": "GATE", "gate_type": "DELAY", "delay_time": 0.5 })

	graph.connect_nodes("node_a", 0, "gate_delay", 0)
	graph.connect_nodes("gate_delay", 0, "node_b", 0)

	manager._build_runtime_logic()

	source_prop.set_active(false)
	target_prop.set_active(false)

	# Activate Source
	source_prop.set_active(true)
	manager.step(0.1)

	# Should be inactive yet (delay 0.5 > 0.1)
	assert_state(target_prop, false, "DELAY Gate (Pre-Delay)")

	# Step more (total 0.6 > 0.5)
	manager.step(0.5)
	assert_state(target_prop, true, "DELAY Gate (Post-Delay)")

	# 9. Test Cable Generation
	print("Testing Cable Generation...")
	manager.auto_build_cables = true
	manager.generate_cables()

	var cable_count = 0
	for child in manager.get_children():
		if child is Spatial and child.has_method("build"): # Rough check for CircuitCable
			cable_count += 1

	if cable_count >= 2: # 2 connections in Delay test
		print("PASS: Cable Generation (%d cables)" % cable_count)
	else:
		print("FAIL: Cable Generation expected >= 2, got %d" % cable_count)
		quit(1)

	print("ALL TESTS PASSED")
	quit()

func assert_state(prop, expected, msg):
	if prop.is_active == expected:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg + ". Expected " + str(expected) + ", Got " + str(prop.is_active))
		quit(1)
