# core_v2/tests/test_cargol_drone.gd
extends GdUnitTestSuite

const OYSComponent = preload("res://core_v2/components/OYSComponent.gd")

func test_cargol_drone_logic() -> void:
	var runner := scene_runner("res://core_v2/tests/TestScene_Cargol.tscn")

	# Ensure SessionManager exists for Actor Registration
	var sm = runner.scene().get_tree().root.get_node_or_null("SessionManager")
	if not sm:
		sm = Node.new()
		sm.name = "SessionManager"
		sm.set_script(load("res://core_v2/autoloads/SessionManager.gd"))
		runner.scene().get_tree().root.add_child(sm)

	var drone = runner.scene().find_node("CargolDrone", true, false)
	var cargo = runner.scene().find_node("Cargo", true, false)

	assert_object(drone).is_not_null()
	assert_object(cargo).is_not_null()

	# Manually register if auto-register failed due to missing SM at _ready
	sm.register_oys_actor("CargolDrone", drone)

	# Verify drone is in group
	assert_bool(drone.is_in_group("cargol_drone")).is_true()
	assert_bool(drone.is_in_group("replay_sync")).is_true()

	# Add OYSComponent to run the script
	var comp = OYSComponent.new()
	comp.name = "OYSComponent"
	runner.scene().add_child(comp)

	# Drone starts at (0, 5, 0)
	# Cargo starts at (5, 1, 0)

	# Script to pick up cargo and move it
	var script_content = """
SECTION "Test"
# Move above cargo
CALL CargolDrone "move_to" [5, 2, 0]
WAIT 1.5
# Pickup
CALL CargolDrone "pickup" "../Cargo"
WAIT 0.5
# Move back to origin
CALL CargolDrone "move_to" [0, 5, 0]
WAIT 1.5
# Release
CALL CargolDrone "release" [0, 0, 0]
WAIT 0.5
"""

	comp.interpreter.parse(script_content)

	# Start execution
	var _routine = comp.interpreter.run()

	# Simulate execution
	var timeout = 600 # 600 frames = ~10 seconds at 60fps
	while comp.interpreter.is_running and timeout > 0:
		yield(runner.simulate_frames(1), "completed")
		timeout -= 1

	# Script should have finished
	assert_bool(comp.interpreter.is_running).is_false()

	if timeout <= 0:
		push_error("Test timed out!")

	# Check results
	var cargo_pos = cargo.global_transform.origin
	print("Final Cargo Pos: ", cargo_pos)

	# Cargo should have moved from (5, 1, 0) to roughly (0, 5, 0) then released/fallen.
	# X should be close to 0 (origin) instead of 5
	assert_float(abs(cargo_pos.x)).is_less(2.0)

	# Y might be anywhere (falling), but definitely changed
	assert_float(cargo_pos.distance_to(Vector3(5, 1, 0))).is_greater(2.0)
