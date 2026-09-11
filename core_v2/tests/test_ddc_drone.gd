extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

const DDCDrone = preload("res://core_v2/actors/DDCDroneV2.gd")

func test_patrol_loop_with_pauses() -> void:
	var drone = DDCDrone.new()
	add_child(drone)
	
	# Create waypoints
	var w1 = Position3D.new()
	w1.name = "Waypoint1"
	w1.translation = Vector3(10, 0, 0)
	drone.add_child(w1)
	
	var w2 = Position3D.new()
	w2.name = "Waypoint2"
	w2.translation = Vector3(0, 0, 10)
	drone.add_child(w2)
	
	drone._discover_patrol_points()
	drone.waypoint_pause_time = 2.0
	
	# Force set state to PATROL
	drone.current_state = 7 # PATROL
	drone.move_to(drone._patrol_points[0])
	
	# Force reach waypoint 1
	drone.global_transform.origin = Vector3(10, 0, 0)
	drone.current_state = 7
	drone.step(0.1)
	
	# Should be pausing now
	assert_float(drone._pause_timer).is_greater(0.0)
	assert_vector3(drone.target_position).is_equal(Vector3(10, 0, 0))
	
	# Wait for pause to finish
	drone.step(2.0)
	
	# Should move to Waypoint 2
	assert_vector3(drone.target_position).is_equal(Vector3(0, 0, 10))
	
	drone.free()

func test_detection_logic_robust() -> void:
	var drone = DDCDrone.new()
	add_child(drone)
	
	var player = KinematicBody.new()
	player.add_to_group("player")
	add_child(player)
	
	# Setup mock stealth
	var stealth_logic = Node.new()
	stealth_logic.name = "Stealth"
	stealth_logic.set_script(load("res://core_v2/player/PlayerStealth.gd"))
	var player_logic = Node.new()
	player_logic.name = "Logic"
	player.add_child(player_logic)
	player_logic.add_child(stealth_logic)
	
	drone._player_ref = player
	drone.detection_radius = 10.0
	drone.vision_angle = 360.0 # See everywhere for test
	
	# Player far away
	player.global_transform.origin = Vector3(20, 0, 0)
	drone._check_detection(0.1)
	assert_int(drone.current_state).is_not_equal(4) # Not Alert (4)
	
	# Player close: with a collider on the player, the raycast hits it and the
	# drone must go straight to Alert (Box3D returns the hit in headless too).
	player.global_transform.origin = Vector3(5, 0, 0)
	var shape = CollisionShape.new()
	var box = BoxShape.new()
	box.extents = Vector3(1, 1, 1)
	shape.shape = box
	player.add_child(shape)
	
	drone._check_detection(0.1)
	assert_int(drone.current_state).is_equal(4) # Alert (4)
	
	drone.free()
	player.free()
