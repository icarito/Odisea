extends GdUnitTestSuite

const ANNA_SCENE_PATH := "res://core_v2/tests/TestScene_ANNA.tscn"
const AnnaInterface = preload("res://core_v2/anna/AnnaInterface.gd")
const AnnaBridge = preload("res://core_v2/anna/AnnaBridge.gd")

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

func _free_node(node: Node) -> void:
	if node and is_instance_valid(node):
		node.queue_free()
	yield (get_tree(), "idle_frame")

func _release_test_actions() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_forward")
	Input.action_release("move_backward")

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

	yield (_free_node(bridge), "completed")
	sm.player = previous_player

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
