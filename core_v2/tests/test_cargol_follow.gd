extends GdUnitTestSuite

# test_cargol_follow.gd
# Verifies CargolDroneV2 following behavior, state changes, and remote interaction.

func test_follow_player() -> void:
	var runner := scene_runner("res://core_v2/tests/TestScene_Cargol.tscn")
	yield(runner.simulate_frames(5), "completed")

	var drone = runner.scene().find_node("CargolDrone", true, false)
	var player = runner.scene().find_node("Pilot", true, false)
	
	assert_object(drone).is_not_null()
	assert_object(player).is_not_null()

	# Use a more controlled test: teleport drone near player and see if it moves
	player.set_physics_process(false)
	drone.collision_mask = 0
	drone.global_transform.origin = player.global_transform.origin + Vector3(0, 0, 10)
	
	# Start following
	drone.follow_target(player, 2.0)
	assert_int(drone.current_state).is_equal(2) # State.FOLLOW_TARGET
	var toward_player = player.global_transform.origin - drone.global_transform.origin
	var follow_velocity = drone._logic_follow_target(1.0 / 60.0)
	assert_bool(follow_velocity.dot(toward_player) > 0.0).is_true()

func test_state_led_colors() -> void:
	var runner := scene_runner("res://core_v2/tests/TestScene_Cargol.tscn")
	yield(runner.simulate_frames(5), "completed")
	var drone = runner.scene().find_node("CargolDrone", true, false)
	var mesh: MeshInstance = drone.get_node("MeshInstance")
	
	# IDLE -> Blue
	drone.current_state = 0 # State.IDLE
	# Ensure material exists first
	drone._update_led(Color(0.2, 0.4, 1.0))
	yield(runner.simulate_frames(1), "completed")
	var mat: SpatialMaterial = mesh.get_surface_material(0)
	assert_bool(mat != null).is_true()
	assert_bool(mat.albedo_color.is_equal_approx(Color(0.2, 0.4, 1.0))).is_true()
	
	# RETURN_HOME -> Green
	drone.current_state = 3 # State.RETURN_HOME
	yield(runner.simulate_frames(1), "completed")
	assert_bool(mat.albedo_color.is_equal_approx(Color(0.2, 1.0, 0.4))).is_true()
	
	# ALERT -> Red
	drone.current_state = 4 # State.ALERT
	yield(runner.simulate_frames(1), "completed")
	assert_bool(mat.albedo_color.is_equal_approx(Color(1.0, 0.2, 0.2))).is_true()

func test_remote_interact() -> void:
	var runner := scene_runner("res://core_v2/tests/TestScene_Cargol.tscn")
	yield(runner.simulate_frames(5), "completed")
	var drone = runner.scene().find_node("CargolDrone", true, false)
	
	# Create a dummy interactable
	var dummy = Spatial.new()
	dummy.name = "DummyInteractable"
	dummy.set_script(load("res://core_v2/components/InteractableBaseV2.gd"))
	runner.scene().add_child(dummy)
	
	# Warp drone to dummy to avoid pathfinding issues in headless
	var target_pos = Vector3(5, 1, 5)
	dummy.global_transform.origin = target_pos
	drone.global_transform.origin = target_pos
	
	# Set interaction target and call internal check
	drone._interaction_target = dummy
	drone.step(0.01) # Trigger check
	
	# Check if dummy was activated
	assert_bool(dummy.is_active).is_true()
