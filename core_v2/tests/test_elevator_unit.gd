extends GdUnitTestSuite

func test_elevator_platform_move_to_sets_target():
	var platform = preload("res://core_v2/components/ElevatorPlatform.gd").new()
	platform.set_script(load("res://core_v2/components/ElevatorPlatform.gd"))
	
	platform.target_height = 0.0
	platform.is_moving = false
	
	platform.move_to(5.0)
	
	assert_float(platform.target_height).is_equal(5.0)
	assert_bool(platform.is_moving).is_true()
	
	platform.free()

func test_elevator_controller_request_queues_floor():
	var controller = preload("res://core_v2/props/ElevatorController.gd").new()
	controller.set_script(load("res://core_v2/props/ElevatorController.gd"))
	
	controller.requests = []
	controller.current_floor = 0
	controller.is_moving = false
	
	controller._on_floor_request(1)
	
	assert_array(controller.requests).contains([1])
	
	controller.free()
