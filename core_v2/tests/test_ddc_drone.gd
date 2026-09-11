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
