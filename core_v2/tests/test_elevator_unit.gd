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


# Each landing's call button owns its own indicator material. _sync_floors clones
# the template floor with Node.duplicate(), which shares resources, so all six
# landings used to light up together; and once the button moved to the prop layer
# PropDitherManager swapped its SpatialMaterial for the dither shader, after which
# none of them lit at all.
func test_landing_buttons_light_independently():
	var elevator = auto_free(preload("res://core_v2/props/machinery/ElevatorProp.tscn").instance())
	elevator.floor_heights = [0.0, 4.6, 9.1]
	add_child(elevator)
	yield(await_idle_frame(), "completed")

	var buttons := []
	for stop in elevator.get_node("Floors").get_children():
		var button = stop.get_node_or_null("Input/PedestalButton")
		assert_object(button).is_not_null()
		buttons.append(button)
	assert_int(buttons.size()).is_equal(3)

	buttons[1].set_active(true, true)

	var lit := []
	for i in range(buttons.size()):
		var mesh = buttons[i].get_node("ButtonMesh")
		var mat = mesh.material_override
		assert_object(mat) \
			.override_failure_message("button %d lost its SpatialMaterial to the dither shader" % i) \
			.is_instanceof(SpatialMaterial)
		if mat.albedo_color.g > mat.albedo_color.r:
			lit.append(i)
	assert_array(lit) \
		.override_failure_message("only the pressed landing should be green, got %s" % [lit]) \
		.is_equal([1])


# The camera's spring arm masks layers 1 and 8 (PlayerControllerV2.camera_collision_mask
# = 129), and PropDitherManager only fades bodies carrying layer 7. So a shaft
# fitting left on layer 1 does both wrong things at once: it shoves the camera
# around inside the car and stays opaque between the camera and the player. The
# pedestal buttons and the door leaves were exactly that.
const PROP_LAYER := 64

func test_every_elevator_body_is_on_the_prop_layer():
	var elevator = auto_free(preload("res://core_v2/props/machinery/ElevatorProp.tscn").instance())
	elevator.floor_heights = [0.0, 4.6, 9.1]
	add_child(elevator)
	yield(await_idle_frame(), "completed")

	var offenders := []
	_collect_non_prop_bodies(elevator, "ElevatorProp", offenders)
	assert_array(offenders) \
		.override_failure_message("bodies off the prop layer: %s" % [offenders]) \
		.is_empty()


# Areas are deliberately not checked: a SpringArm casts against physics bodies
# only, so an Area on any layer neither blocks the camera nor dithers.
func _collect_non_prop_bodies(node: Node, path: String, offenders: Array) -> void:
	if node is PhysicsBody and not (node.collision_layer & PROP_LAYER):
		offenders.append("%s (layer=%d)" % [path, node.collision_layer])
	for child in node.get_children():
		_collect_non_prop_bodies(child, path + "/" + child.name, offenders)
