extends GdUnitTestSuite

const ANNA_SCENE_PATH := "res://core_v2/tests/TestScene_ANNA.tscn"
const AnnaInterface = preload("res://core_v2/anna/AnnaInterface.gd")
const AnnaBridge = preload("res://core_v2/anna/AnnaBridge.gd")
const InputProviderV2 = preload("res://core_v2/input/InputProviderV2.gd")

class DummyAIController extends Node:
	var heuristic := "ai"

class DummyConsole extends Node:
	var queued := []
	var logs := []

	func enqueue_command(line: String) -> void:
		queued.append(line)

	func get_logs() -> Array:
		return logs

class DummyOLCSManager extends Node:
	var injected := []
	var outputs := []
	var rebuild_calls := 0

	func anna_get_snapshot(max_entries := 64) -> Dictionary:
		return {
			"available": true,
			"manager": name,
			"nodes": [
				{"id": "LeverA", "type": "PROP", "state": true}
			],
			"connections": [
				{"from": "LeverA", "to": "DoorA", "type": "WIRED", "broken": false}
			],
			"max_entries_seen": int(max_entries)
		}

	func anna_inject_input(target_id: String, input_id: String, value: bool) -> bool:
		injected.append({"target": target_id, "input": input_id, "value": value})
		return true

	func anna_set_output(source_id: String, value: bool) -> bool:
		outputs.append({"source": source_id, "value": value})
		return true

	func anna_rebuild_cables() -> bool:
		rebuild_calls += 1
		return true

class DummyInspectable extends Spatial:
	export(String) var lock_id := "door_01"
	export(bool) var starts_locked := true
	var runtime_only := 42

class DummyInputProbe extends Spatial:
	var input_provider = InputProviderV2.new()

func _free_node(node: Node) -> void:
	if node and is_instance_valid(node):
		node.queue_free()
	yield (get_tree(), "idle_frame")

func _release_test_actions() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_forward")
	Input.action_release("move_backward")

func _hierarchy_contains_name(entry: Dictionary, target: String) -> bool:
	if str(entry.get("name", "")) == target:
		return true
	var children = entry.get("children", [])
	if typeof(children) != TYPE_ARRAY:
		return false
	for child in children:
		if typeof(child) == TYPE_DICTIONARY and _hierarchy_contains_name(child, target):
			return true
	return false

func _setup_rl_context(runner) -> Dictionary:
	var scene = runner.scene()
	var pilot = scene.get_node_or_null("Pilot")
	assert_object(pilot).is_not_null()

	var sm = get_node_or_null("/root/SessionManager")
	assert_object(sm).is_not_null()

	var previous_player = sm.player
	var previous_recording = sm.is_recording
	var previous_override = sm._oys_input_override

	sm.player = pilot
	sm.is_recording = true
	sm._oys_input_override = {}

	var anna = AnnaInterface.new()
	scene.add_child(anna)
	yield (runner.simulate_frames(2), "completed")

	var target = Area.new()
	target.name = "UnitRLTarget"
	target.add_to_group("anna_target")
	var col = CollisionShape.new()
	var shape = SphereShape.new()
	shape.radius = 1.0
	col.shape = shape
	target.add_child(col)
	target.translation = pilot.translation + Vector3(6.0, 1.0, 0.0)
	scene.add_child(target)
	yield (runner.simulate_frames(1), "completed")

	anna.reset_simulation()
	yield (runner.simulate_frames(1), "completed")

	return {
		"scene": scene,
		"pilot": pilot,
		"target": target,
		"anna": anna,
		"sm": sm,
		"previous_player": previous_player,
		"previous_recording": previous_recording,
		"previous_override": previous_override
	}

func _teardown_rl_context(ctx: Dictionary) -> void:
	var sm = ctx.get("sm", null)
	if sm:
		sm.player = ctx.get("previous_player", null)
		sm.is_recording = ctx.get("previous_recording", false)
		sm._oys_input_override = ctx.get("previous_override", {})
	var anna = ctx.get("anna", null)
	if anna:
		yield (_free_node(anna), "completed")

func test_anna_special_scene_has_required_layout() -> void:
	var runner = scene_runner(ANNA_SCENE_PATH)
	yield (runner.simulate_frames(2), "completed")

	var scene = runner.scene()
	assert_object(scene).is_not_null()
	assert_object(scene.get_node_or_null("Pilot")).is_not_null()
	assert_object(scene.get_node_or_null("Floor")).is_not_null()
	assert_object(scene.get_node_or_null("InteractableBeacon")).is_not_null()
	assert_object(scene.get_node_or_null("FarBeacon")).is_not_null()

	var near = scene.get_node("InteractableBeacon")
	var far = scene.get_node("FarBeacon")
	assert_bool(near.is_in_group("interactable")).is_true()
	assert_bool(far.is_in_group("interactable")).is_true()
	assert_bool(near.global_transform.origin.z > 0.0).is_true()

func test_anna_interface_returns_fallback_collisions_without_player() -> void:
	var sm = get_node_or_null("/root/SessionManager")
	assert_object(sm).is_not_null()

	var previous_player = sm.player
	sm.player = null

	var anna = AnnaInterface.new()
	get_tree().root.add_child(anna)
	yield (get_tree(), "idle_frame")

	var obs = anna.get_observation()
	assert_bool(obs.has("anna")).is_true()
	assert_bool(obs.has("collisions")).is_true()
	assert_int(obs["collisions"].size()).is_equal(32)
	for dist in obs["collisions"]:
		assert_float(float(dist)).is_equal(20.0)

	sm.player = previous_player
	yield (_free_node(anna), "completed")

func test_anna_interface_detects_nearby_interactable_and_applies_recorded_input() -> void:
	var runner = scene_runner(ANNA_SCENE_PATH)
	yield (runner.simulate_frames(2), "completed")

	var scene = runner.scene()
	var pilot = scene.get_node_or_null("Pilot")
	assert_object(pilot).is_not_null()

	var sm = get_node_or_null("/root/SessionManager")
	assert_object(sm).is_not_null()

	var previous_player = sm.player
	var previous_recording = sm.is_recording
	var previous_override = sm._oys_input_override

	sm.player = pilot
	sm.is_recording = true
	sm._oys_input_override = {}

	var anna = AnnaInterface.new()
	scene.add_child(anna)
	yield (runner.simulate_frames(2), "completed")

	var obs = anna.get_observation()
	assert_bool(obs.has("proximity")).is_true()
	assert_bool(obs.has("metrics")).is_true()
	assert_bool(obs.has("collisions")).is_true()
	assert_bool(obs.has("anna")).is_true()
	assert_int(obs["collisions"].size()).is_equal(32)
	assert_str(str(obs["anna"].get("protocol", ""))).is_equal("anna.v1")
	assert_bool(int(obs["anna"].get("physics_frame", -1)) >= 0).is_true()

	var seen_near := false
	var seen_far := false
	for entry in obs["proximity"]:
		var node_name = str(entry.get("name", ""))
		if node_name == "InteractableBeacon":
			seen_near = true
		if node_name == "FarBeacon":
			seen_far = true
	assert_bool(seen_near).is_true()
	assert_bool(seen_far).is_false()

	anna.apply_action({
		"jump": true,
		"move": [3.25, -4.5],
		"look": [3000.0, -3000.0],
		"interact": true
	})

	var injected = sm._oys_input_override
	assert_bool(injected.has("move_vec")).is_true()
	assert_bool(injected.has("mouse_delta")).is_true()
	assert_bool(bool(injected.get("jump", false))).is_true()
	assert_bool(bool(injected.get("interact", false))).is_true()

	var move_vec = injected.get("move_vec", Vector2.ZERO)
	var mouse_delta = injected.get("mouse_delta", Vector2.ZERO)
	assert_float(move_vec.x).is_equal(1.0)
	assert_float(move_vec.y).is_equal(-1.0)
	assert_float(mouse_delta.x).is_equal(250.0)
	assert_float(mouse_delta.y).is_equal(-250.0)

	anna.apply_action({"jump": true})
	assert_bool(bool(sm._oys_input_override.get("jump", false))).is_true()

	sm.player = previous_player
	sm.is_recording = previous_recording
	sm._oys_input_override = previous_override
	yield (_free_node(anna), "completed")

func test_anna_human_heuristic_invalidates_ai_move_action() -> void:
	var runner = scene_runner(ANNA_SCENE_PATH)
	yield (runner.simulate_frames(2), "completed")

	var scene = runner.scene()
	var pilot = scene.get_node_or_null("Pilot")
	assert_object(pilot).is_not_null()

	var sm = get_node_or_null("/root/SessionManager")
	assert_object(sm).is_not_null()

	var previous_player = sm.player
	var previous_recording = sm.is_recording
	var previous_override = sm._oys_input_override
	_release_test_actions()

	sm.player = pilot
	sm.is_recording = true
	sm._oys_input_override = {}

	var anna = AnnaInterface.new()
	anna.allow_human_heuristic_override = true
	scene.add_child(anna)

	var ai = DummyAIController.new()
	ai.name = "AIController"
	ai.heuristic = "human"
	scene.add_child(ai)
	anna.ai_controller_path = NodePath("../AIController")

	yield (runner.simulate_frames(2), "completed")
	Input.action_press("move_right", 1.0)
	Input.action_press("move_forward", 1.0)

	anna.apply_action({
		"move": [0.0, 0.0]
	})

	var injected = sm._oys_input_override
	var move_vec = injected.get("move_vec", Vector2.ZERO)
	assert_float(move_vec.x).is_equal(1.0)
	assert_float(move_vec.y).is_equal(-1.0)

	_release_test_actions()
	sm.player = previous_player
	sm.is_recording = previous_recording
	sm._oys_input_override = previous_override
	yield (_free_node(ai), "completed")
	yield (_free_node(anna), "completed")

func test_anna_bridge_builds_observation_payload_with_runtime_metadata() -> void:
	var runner = scene_runner(ANNA_SCENE_PATH)
	yield (runner.simulate_frames(2), "completed")

	var scene = runner.scene()
	var pilot = scene.get_node_or_null("Pilot")
	assert_object(pilot).is_not_null()

	var sm = get_node_or_null("/root/SessionManager")
	assert_object(sm).is_not_null()

	var previous_player = sm.player
	sm.player = pilot

	var bridge = AnnaBridge.new()
	scene.add_child(bridge)
	yield (runner.simulate_frames(2), "completed")

	var payload = bridge._build_observation_payload()
	assert_bool(payload.has("anna")).is_true()
	assert_str(str(payload["anna"].get("protocol", ""))).is_equal("anna.v1")
	assert_bool(int(payload["anna"].get("peer_count", -1)) >= 0).is_true()
	assert_bool(int(payload["anna"].get("physics_frame", -1)) >= 0).is_true()

	var mcp_tree = bridge._run_mcp_command("get_tree", {"max_depth": 1})
	assert_bool(bool(mcp_tree.get("ok", false))).is_true()
	assert_str(str(mcp_tree.get("data", {}).get("resource", ""))).is_equal("odisea://scene/hierarchy")

	var mcp_inspect = bridge._run_mcp_command("inspect_node", {"node_path": str(pilot.get_path())})
	assert_bool(bool(mcp_inspect.get("ok", false))).is_true()
	assert_str(str(mcp_inspect.get("data", {}).get("path", ""))).is_equal(str(pilot.get_path()))

	yield (_free_node(bridge), "completed")
	sm.player = previous_player

func test_anna_mcp_resources_scene_telemetry_and_filters_internal_nodes() -> void:
	var runner = scene_runner(ANNA_SCENE_PATH)
	yield (runner.simulate_frames(2), "completed")

	var scene = runner.scene()
	var pilot = scene.get_node_or_null("Pilot")
	assert_object(pilot).is_not_null()

	var sm = get_node_or_null("/root/SessionManager")
	assert_object(sm).is_not_null()
	var previous_player = sm.player
	sm.player = pilot

	var anna = AnnaInterface.new()
	scene.add_child(anna)

	var hidden = Node.new()
	hidden.name = "_Timer"
	scene.add_child(hidden)
	yield (runner.simulate_frames(1), "completed")

	var hierarchy = anna.get_scene_hierarchy_resource(3, 64)
	assert_str(str(hierarchy.get("resource", ""))).is_equal("odisea://scene/hierarchy")
	assert_bool(bool(hierarchy.get("available", false))).is_true()
	var tree = hierarchy.get("tree", {})
	assert_bool(_hierarchy_contains_name(tree, "Pilot")).is_true()
	assert_bool(_hierarchy_contains_name(tree, "_Timer")).is_false()

	var telemetry = anna.get_simulation_telemetry_resource()
	assert_str(str(telemetry.get("resource", ""))).is_equal("odisea://simulation/telemetry")
	assert_bool(bool(telemetry.get("elias", {}).get("available", false))).is_true()
	assert_bool(telemetry.get("elias", {}).has("active_velocity")).is_true()
	assert_bool(telemetry.has("oys")).is_true()
	assert_bool(telemetry.has("hardware")).is_true()
	assert_bool(bool(telemetry.get("hardware", {}).get("available", false))).is_true()
	assert_bool(telemetry.get("hardware", {}).has("shadow_policy")).is_true()

	sm.player = previous_player
	yield (_free_node(hidden), "completed")
	yield (_free_node(anna), "completed")

func test_anna_mcp_tools_inspect_execute_query_docs_and_logic_state() -> void:
	var existing_console = get_tree().root.get_node_or_null("OYS_Console")
	if existing_console and is_instance_valid(existing_console):
		yield (_free_node(existing_console), "completed")

	var anna = AnnaInterface.new()
	get_tree().root.add_child(anna)
	yield (get_tree(), "idle_frame")

	var console = DummyConsole.new()
	console.name = "OYS_Console"
	get_tree().root.add_child(console)

	var inspectable = DummyInspectable.new()
	inspectable.name = "InspectableDoor"
	get_tree().root.add_child(inspectable)

	var manager = DummyOLCSManager.new()
	manager.name = "LogicCircuitManager"
	manager.add_to_group("olcs_manager")
	get_tree().root.add_child(manager)
	yield (get_tree(), "idle_frame")

	var inspect = anna.inspect_node(str(inspectable.get_path()))
	assert_bool(bool(inspect.get("ok", false))).is_true()
	assert_str(str(inspect.get("export_vars", {}).get("lock_id", ""))).is_equal("door_01")
	assert_bool(bool(inspect.get("export_vars", {}).get("starts_locked", false))).is_true()

	var exec_res = anna.execute_oys("echo hi from mcp")
	assert_bool(bool(exec_res.get("ok", false))).is_true()
	assert_int(console.queued.size()).is_equal(1)
	assert_bool(String(console.queued[0]).begins_with("run ")).is_true()
	assert_bool(String(console.queued[0]).find("mcp_inline_") != -1).is_true()
	assert_str(String(exec_res.get("source_command", ""))).is_equal("echo hi from mcp")

	var logic_state = anna.get_olcs_logic_state_resource()
	assert_str(str(logic_state.get("resource", ""))).is_equal("odisea://olcs/logic-state")
	assert_bool(bool(logic_state.get("available", false))).is_true()
	assert_int(logic_state.get("levers", []).size()).is_equal(1)

	var docs = anna.query_codex_docs("odisea", 5)
	assert_bool(docs.has("matches")).is_true()
	assert_bool(int(docs.get("scanned_files", 0)) >= 1).is_true()

	yield (_free_node(manager), "completed")
	yield (_free_node(inspectable), "completed")
	yield (_free_node(console), "completed")
	yield (_free_node(anna), "completed")

func test_anna_inspect_node_supports_visual_and_input_runtime_options() -> void:
	var anna = AnnaInterface.new()
	get_tree().root.add_child(anna)
	yield (get_tree(), "idle_frame")

	var probe = DummyInputProbe.new()
	probe.name = "ProbePilot"
	get_tree().root.add_child(probe)

	var visual_root = Spatial.new()
	visual_root.name = "Visual"
	probe.add_child(visual_root)

	var mesh_node = MeshInstance.new()
	mesh_node.name = "BodyMesh"
	mesh_node.mesh = CubeMesh.new()
	var mat = SpatialMaterial.new()
	mat.flags_unshaded = true
	mesh_node.set_surface_material(0, mat)
	visual_root.add_child(mesh_node)
	yield (get_tree(), "idle_frame")

	var inspect = anna.inspect_node(str(mesh_node.get_path()), {
		"include_visual": true,
		"include_children": true,
		"max_depth": 3,
		"max_children": 16,
		"probe_fields": ["visible", "runtime_only"]
	})
	assert_bool(bool(inspect.get("ok", false))).is_true()
	assert_bool(inspect.has("runtime_fields")).is_true()
	assert_bool(inspect["runtime_fields"].has("visible")).is_true()
	assert_str(str(inspect["runtime_fields"].get("runtime_only", ""))).is_equal("__missing__")
	assert_bool(inspect.has("visual")).is_true()
	assert_bool(inspect.get("visual", {}).has("mesh")).is_true()
	var materials = inspect.get("visual", {}).get("mesh", {}).get("materials", [])
	assert_bool(materials.size() >= 1).is_true()
	assert_bool(bool(materials[0].get("flags_unshaded", false))).is_true()
	assert_bool(inspect.has("input_runtime")).is_true()
	assert_bool(bool(inspect.get("input_runtime", {}).get("available", false))).is_true()
	assert_str(str(inspect.get("input_runtime", {}).get("source_path", ""))).is_equal(str(probe.get_path()))
	assert_str(str(inspect.get("input_runtime", {}).get("source_strategy", ""))).is_equal("ancestor")
	assert_bool(inspect.has("children")).is_true()

	var bridge = AnnaBridge.new()
	get_tree().root.add_child(bridge)
	yield (get_tree(), "idle_frame")

	var mcp_inspect = bridge._run_mcp_command("inspect_node", {
		"node_path": str(mesh_node.get_path()),
		"include_visual": true,
		"probe_fields": ["visible"],
		"max_depth": 2
	})
	assert_bool(bool(mcp_inspect.get("ok", false))).is_true()
	assert_bool(mcp_inspect.get("data", {}).has("runtime_fields")).is_true()
	assert_bool(mcp_inspect.get("data", {}).has("visual")).is_true()

	yield (_free_node(bridge), "completed")
	yield (_free_node(probe), "completed")
	yield (_free_node(anna), "completed")

func test_anna_set_property_supports_nested_paths_and_bridge_tool() -> void:
	var anna = AnnaInterface.new()
	get_tree().root.add_child(anna)
	yield (get_tree(), "idle_frame")

	var world_env = WorldEnvironment.new()
	world_env.name = "TestWorldEnvironment"
	var env = Environment.new()
	env.glow_enabled = true
	env.ssao_enabled = true
	world_env.environment = env
	get_tree().root.add_child(world_env)
	yield (get_tree(), "idle_frame")

	var set_res = anna.set_property(str(world_env.get_path()), "environment.glow_enabled", false)
	assert_bool(bool(set_res.get("ok", false))).is_true()
	assert_bool(bool(set_res.get("had_property", false))).is_true()
	assert_bool(bool(set_res.get("new_value", true))).is_false()
	assert_bool(world_env.environment.glow_enabled).is_false()

	var set_color = anna.set_property(str(world_env.get_path()), "environment.ambient_light_color", {
		"type": "color",
		"value": [0.15, 0.25, 0.35, 1.0]
	})
	assert_bool(bool(set_color.get("ok", false))).is_true()
	assert_bool(is_equal_approx(world_env.environment.ambient_light_color.r, 0.15)).is_true()
	assert_bool(is_equal_approx(world_env.environment.ambient_light_color.g, 0.25)).is_true()
	assert_bool(is_equal_approx(world_env.environment.ambient_light_color.b, 0.35)).is_true()

	var bridge = AnnaBridge.new()
	get_tree().root.add_child(bridge)
	yield (get_tree(), "idle_frame")

	var bridge_set = bridge._run_mcp_command("set_property", {
		"node_path": str(world_env.get_path()),
		"property": "environment.glow_enabled",
		"value": true
	})
	assert_bool(bool(bridge_set.get("ok", false))).is_true()
	assert_bool(bool(world_env.environment.glow_enabled)).is_true()

	var bridge_fail = bridge._run_mcp_command("set_property", {
		"node_path": str(world_env.get_path()),
		"property": "environment.not_a_real_property",
		"value": 1
	})
	assert_bool(bool(bridge_fail.get("ok", true))).is_false()
	assert_str(str(bridge_fail.get("data", {}).get("error", ""))).is_equal("property_not_found")

	yield (_free_node(bridge), "completed")
	yield (_free_node(world_env), "completed")
	yield (_free_node(anna), "completed")

func test_anna_structured_oys_action_queues_console_commands() -> void:
	var existing_console = get_tree().root.get_node_or_null("OYS_Console")
	if existing_console and is_instance_valid(existing_console):
		yield (_free_node(existing_console), "completed")

	var anna = AnnaInterface.new()
	get_tree().root.add_child(anna)
	yield (get_tree(), "idle_frame")

	var console = DummyConsole.new()
	console.name = "OYS_Console"
	get_tree().root.add_child(console)
	yield (get_tree(), "idle_frame")

	anna.apply_action({
		"oys": {
			"once_id": "run-1",
			"command": "echo hi from anna",
			"run": "res://core_v2/tests/test_salto_vertical.oys",
			"exec": "default_env.cfg"
		}
	})

	assert_int(console.queued.size()).is_equal(3)
	assert_str(String(console.queued[0])).is_equal("echo hi from anna")
	assert_str(String(console.queued[1])).is_equal("run res://core_v2/tests/test_salto_vertical.oys")
	assert_str(String(console.queued[2])).is_equal("exec default_env.cfg")

	# Same once_id should be ignored
	anna.apply_action({
		"oys": {
			"once_id": "run-1",
			"command": "echo should not run"
		}
	})
	assert_int(console.queued.size()).is_equal(3)

	yield (_free_node(console), "completed")
	yield (_free_node(anna), "completed")

func test_anna_olcs_observation_and_action_integration() -> void:
	var anna = AnnaInterface.new()
	get_tree().root.add_child(anna)
	yield (get_tree(), "idle_frame")

	var manager = DummyOLCSManager.new()
	manager.name = "LogicCircuitManager"
	manager.add_to_group("olcs_manager")
	get_tree().root.add_child(manager)
	yield (get_tree(), "idle_frame")

	var obs = anna.get_observation()
	assert_bool(obs.has("olcs")).is_true()
	assert_bool(bool(obs["olcs"].get("available", false))).is_true()
	assert_int(obs["olcs"].get("nodes", []).size()).is_equal(1)
	assert_int(int(obs["olcs"].get("max_entries_seen", 0))).is_equal(32)

	anna.apply_action({
		"ocls": {
			"once_id": "olcs-1",
			"inject": {"target": "DoorA", "input": "LeverA", "value": true},
			"set_output": {"source": "LeverA", "value": true},
			"rebuild_cables": true
		}
	})

	assert_int(manager.injected.size()).is_equal(1)
	assert_int(manager.outputs.size()).is_equal(1)
	assert_int(manager.rebuild_calls).is_equal(1)

	# once_id dedupe
	anna.apply_action({
		"olcs": {
			"once_id": "olcs-1",
			"rebuild_cables": true
		}
	})
	assert_int(manager.rebuild_calls).is_equal(1)

	yield (_free_node(manager), "completed")
	yield (_free_node(anna), "completed")

func test_rl_progress_regression_penalizes_when_distance_increases() -> void:
	var runner = scene_runner(ANNA_SCENE_PATH)
	yield (runner.simulate_frames(2), "completed")
	var ctx = yield (_setup_rl_context(runner), "completed")
	var anna = ctx["anna"]
	var pilot = ctx["pilot"]
	var target = ctx["target"]

	# Force a clear "moving away" condition: previous distance tiny, current distance large.
	target.global_transform.origin = pilot.global_transform.origin + Vector3(12.0, 1.0, 0.0)
	anna._last_dist_to_target = 0.5
	if "velocity" in pilot:
		pilot.velocity = Vector3(2.5, 0.0, 0.0)

	var step_obs = anna.get_rl_observation()
	assert_bool(bool(step_obs.get("done", true))).is_false()
	assert_float(float(step_obs.get("reward", 0.0))).is_less_equal(-2.4)
	yield (_teardown_rl_context(ctx), "completed")

func test_rl_reward_clamp_applies_to_shaping_but_not_timeout_terminal() -> void:
	var runner = scene_runner(ANNA_SCENE_PATH)
	yield (runner.simulate_frames(2), "completed")
	var ctx = yield (_setup_rl_context(runner), "completed")
	var anna = ctx["anna"]
	var pilot = ctx["pilot"]
	var target = ctx["target"]

	target.global_transform.origin = pilot.global_transform.origin + Vector3(10.0, 1.0, 0.0)

	# Non-terminal step: shaping reward should be clamped.
	anna._episode_step_count = 0
	anna._rl_max_episode_steps = 900
	anna._killzone_triggered = false
	if "velocity" in pilot:
		pilot.velocity = Vector3(25.0, 0.0, 25.0)
	var non_terminal = anna.get_rl_observation()
	assert_bool(bool(non_terminal.get("done", true))).is_false()
	assert_bool(abs(float(non_terminal.get("reward", 0.0))) <= (float(anna._rl_shaping_reward_clamp) + 0.001)).is_true()

	# Timeout terminal reward should be outside shaping clamp.
	anna._episode_step_count = anna._rl_max_episode_steps
	if "velocity" in pilot:
		pilot.velocity = Vector3.ZERO
	var timeout_step = anna.get_rl_observation()
	assert_bool(bool(timeout_step.get("done", false))).is_true()
	assert_float(float(timeout_step.get("reward", 0.0))).is_less_equal(-10.0)
	yield (_teardown_rl_context(ctx), "completed")

func test_rl_apply_action_anti_collapse_gate_throttles_forward_when_misaligned() -> void:
	var runner = scene_runner(ANNA_SCENE_PATH)
	yield (runner.simulate_frames(2), "completed")
	var ctx = yield (_setup_rl_context(runner), "completed")
	var anna = ctx["anna"]
	var pilot = ctx["pilot"]
	var sm = ctx["sm"]
	var target = ctx["target"]

	var t = pilot.global_transform
	t.basis = Basis()
	pilot.global_transform = t

	target.global_transform.origin = pilot.global_transform.origin + Vector3(10.0, 1.0, 0.0)

	anna.apply_rl_action(1) # Forward
	var injected = sm._oys_input_override
	var move_vec = injected.get("move_vec", Vector2.ZERO)
	assert_bool(move_vec.y <= -0.1 and move_vec.y >= -1.0).is_true()
	yield (_teardown_rl_context(ctx), "completed")

func test_rl_scene_choose_episode_override_is_applied() -> void:
	var runner = scene_runner("res://core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn")
	yield (runner.simulate_frames(3), "completed")
	var scene = runner.scene()
	var pilot = scene.get_node_or_null("Pilot")
	var target = scene.get_node_or_null("RL_Target")
	assert_object(pilot).is_not_null()
	assert_object(target).is_not_null()

	var sm = get_node_or_null("/root/SessionManager")
	assert_object(sm).is_not_null()
	var previous_player = sm.player
	var previous_recording = sm.is_recording
	var previous_override = sm._oys_input_override
	sm.player = pilot
	sm.is_recording = true
	sm._oys_input_override = {}

	var anna = AnnaInterface.new()
	scene.add_child(anna)
	yield (runner.simulate_frames(2), "completed")

	anna.reset_simulation()
	yield (runner.simulate_frames(1), "completed")
	assert_int(int(anna._rl_max_episode_steps)).is_equal(1500)

	var p = target.global_transform.origin
	assert_bool(p.y > 4.0).is_true()
	assert_bool(p.x > 2.0 and p.x < 10.5).is_true()
	assert_bool(p.z < -3.0 and p.z > -10.5).is_true()

	sm.player = previous_player
	sm.is_recording = previous_recording
	sm._oys_input_override = previous_override
	yield (_free_node(anna), "completed")

func test_rl_spawn_random_yaw_toggle_controls_reset_heading() -> void:
	var runner = scene_runner("res://core_v2/tests/TestScene_RL.tscn")
	yield (runner.simulate_frames(3), "completed")
	var scene = runner.scene()
	var pilot = scene.get_node_or_null("Pilot")
	assert_object(pilot).is_not_null()

	var sm = get_node_or_null("/root/SessionManager")
	assert_object(sm).is_not_null()
	var previous_player = sm.player
	var previous_recording = sm.is_recording
	var previous_override = sm._oys_input_override
	sm.player = pilot
	sm.is_recording = true
	sm._oys_input_override = {}

	var anna = AnnaInterface.new()
	scene.add_child(anna)
	yield (runner.simulate_frames(2), "completed")

	anna._rl_spawn_random_yaw = false
	anna.reset_simulation()
	yield (runner.simulate_frames(1), "completed")
	var yaw_fixed = pilot.global_transform.basis.get_euler().y
	assert_float(abs(yaw_fixed)).is_less_equal(0.001)

	anna._rl_spawn_random_yaw = true
	var seen_non_zero := false
	for _i in range(6):
		anna.reset_simulation()
		yield (runner.simulate_frames(1), "completed")
		var yaw_now = pilot.global_transform.basis.get_euler().y
		if abs(yaw_now) > 0.05:
			seen_non_zero = true
			break
	assert_bool(seen_non_zero).is_true()

	sm.player = previous_player
	sm.is_recording = previous_recording
	sm._oys_input_override = previous_override
	yield (_free_node(anna), "completed")
