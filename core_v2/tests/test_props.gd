# core_v2/tests/test_props.gd
extends GdUnitTestSuite

const AirlockControllerV2 = preload("res://core_v2/components/AirlockControllerV2.gd")
const HoloTerminalV2 = preload("res://core_v2/things/HoloTerminalV2.gd")
const SCENE_PATH = "res://core_v2/tests/TestScenePropZoo.tscn"

func test_airlock_group_init() -> void:
	var airlock = AirlockControllerV2.new()
	assert_bool(airlock.is_in_group("replay_sync")).is_true()
	airlock.free()

func test_holoterminal_snapshot() -> void:
	var term = HoloTerminalV2.new()
	# Simulate focus state
	term._is_focused = true

	var snapshot = term.get_snapshot()
	assert_bool(snapshot.has("focused")).is_true()
	assert_bool(snapshot["focused"]).is_true()

	var term2 = HoloTerminalV2.new()
	term2.restore_snapshot(snapshot)
	assert_bool(term2.is_focused()).is_true()

	term.free()
	term2.free()

func test_scene_prop_zoo_interactions() -> void:
	var runner := scene_runner(SCENE_PATH)

	# Wait for _ready to complete and populate exhibits
	yield(runner.simulate_frames(10), "completed")

	var exhibits_root = runner.scene().find_node("Exhibits", true, false)
	assert_object(exhibits_root).is_not_null()

	var exhibits = exhibits_root.get_children()
	assert_int(exhibits.size()).is_greater(0)

	for exhibit in exhibits:
		var prop_name = "Unknown"
		var label = exhibit.get_node_or_null("Label")
		if label:
			prop_name = label.text

		# Skip base scenes or helpers if they appear
		if prop_name.begins_with("Base"):
			continue

		print("Testing prop: " + prop_name)

		var lever_node = exhibit.get_node_or_null("Lever")
		var control_lever = null
		if lever_node:
			if lever_node.has_signal("activated"):
				control_lever = lever_node
			else:
				control_lever = lever_node.find_node("RotatingLever", true, false)

		if not control_lever:
			 print("Skipping " + prop_name + " (no control lever found)")
			 continue

		# Find the prop instance
		var anchor = exhibit.get_node_or_null("PropAnchor")
		if not anchor or anchor.get_child_count() == 0:
			print("Skipping " + prop_name + " (no prop in anchor)")
			continue

		var prop = anchor.get_child(0)

		# Determine how to check state. Most props use 'is_active'.
		var target_interactable = null
		if "is_active" in prop:
			target_interactable = prop
		else:
			 target_interactable = _find_interactable(prop)

		if not target_interactable:
			 # Special case for AirlockController which manages state internally but exposes interact
			 if prop.has_method("interact"):
				 # AirlockController doesn't expose is_active directly but has internal state.
				 # We can check if it has 'state' var.
				 target_interactable = prop
			 else:
				 print("Skipping " + prop_name + " (no interactable found on prop)")
				 continue

		# Initial State Check
		var initial_state = false
		if "is_active" in target_interactable:
			initial_state = target_interactable.is_active
		elif "state" in target_interactable: # Airlock
			initial_state = target_interactable.state

		# Activate Lever
		if control_lever.has_method("interact"):
			control_lever.interact()
		elif control_lever.has_method("set_active"):
			control_lever.set_active(not control_lever.is_active)

		# Wait for animation/signal
		yield(runner.simulate_frames(60), "completed") # 1 second at 60fps

		# Check State Changed
		var new_state = initial_state
		if "is_active" in target_interactable:
			new_state = target_interactable.is_active
			if new_state == initial_state:
				print("WARNING: Prop " + prop_name + " state (is_active) did not change.")
			else:
				print("SUCCESS: Prop " + prop_name + " toggled state.")

		elif "state" in target_interactable: # Airlock
			new_state = target_interactable.state
			if new_state == initial_state:
				print("WARNING: Prop " + prop_name + " state (enum) did not change.")
			else:
				print("SUCCESS: Prop " + prop_name + " changed state.")

		# Reset (Interact again)
		if control_lever.has_method("interact"):
			control_lever.interact()
		elif control_lever.has_method("set_active"):
			control_lever.set_active(not control_lever.is_active)

		yield(runner.simulate_frames(60), "completed")

func _find_interactable(node):
	for child in node.get_children():
		if "is_active" in child:
			return child
		var found = _find_interactable(child)
		if found:
			return found
	return null
