extends GdUnitTestSuite

# The cabin dial has two ways in that are easy to break independently: the rider
# pressing the key (interact) and the car bringing it up on its own (auto_interact,
# which the player controller drives through set_active, never through interact).

const ElevatorScene = preload("res://core_v2/props/machinery/ElevatorProp.tscn")

var _elevator: Node = null
var _selector: Node = null
var _dial: Control = null


func before_test() -> void:
	_elevator = auto_free(ElevatorScene.instance())
	_elevator.floor_heights = [0.0, 4.6, 9.1, 13.6, 18.1, 22.6]
	add_child(_elevator)
	yield(await_idle_frame(), "completed")
	# Deliberately the prop's own panel, not one bolted on by the test: the cabin
	# control once lived only in Dome_Intro.tscn and a level re-save lost it.
	_selector = _elevator.get_node_or_null("Platform/ElevatorFloorSelector")
	if _selector:
		_dial = _selector.get_node("Viewport/RadialSelector")


func test_the_car_ships_with_a_cabin_panel() -> void:
	assert_object(_selector) \
		.override_failure_message("ElevatorProp.tscn has no Platform/ElevatorFloorSelector") \
		.is_not_null()


func _aim_at_option(index: int) -> void:
	var angle: float = _dial._index_to_screen_angle(index)
	var half: float = min(_dial.rect_size.x, _dial.rect_size.y) / 2.0
	_dial.point_at(_dial.rect_size / 2.0 + Vector2(cos(angle), sin(angle)) * half * 0.65)


func _left_click() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = BUTTON_LEFT
	event.pressed = true
	_selector._input(event)


func test_the_prop_script_is_actually_attached() -> void:
	# Without this, a parse error in ElevatorFloorSelector.gd leaves a bare
	# StaticBody and every other test here passes on null returns.
	assert_bool(_selector.has_method("is_dial_open")) \
		.override_failure_message("ElevatorFloorSelector.gd failed to compile") \
		.is_true()


func test_stops_are_numbered_from_one() -> void:
	assert_array(_selector._resolve_labels()).is_equal(["1", "2", "3", "4", "5", "6"])


func test_proximity_activation_actually_shows_the_dial() -> void:
	# What PlayerControllerV2 does for an auto_interact prop: it flips set_active
	# directly. Before, that only grew an empty quad and the rider had to press the
	# key a second time to see anything.
	assert_bool(_selector.is_dial_open()).is_false()
	_selector.set_active(true)
	yield(await_idle_frame(), "completed")
	assert_bool(_selector.is_dial_open()).is_true()
	assert_bool(_dial.visible).is_true()


func test_click_does_nothing_while_the_aim_is_off_the_dial() -> void:
	_selector.set_active(true)
	yield(await_idle_frame(), "completed")
	yield(await_idle_frame(), "completed")
	_dial.clear_pointer()
	_left_click()
	assert_int(_elevator.target_floor).is_equal(-1)
	assert_bool(_selector.is_dial_open()).is_true()


func test_left_click_requests_the_aimed_floor() -> void:
	_selector.set_active(true)
	yield(await_idle_frame(), "completed")
	yield(await_idle_frame(), "completed")
	_aim_at_option(3)
	_left_click()
	assert_int(_elevator.target_floor).is_equal(3)


func test_ambient_panel_stays_up_after_a_pick() -> void:
	# auto_interact is on in the scene: the controller re-triggers the moment
	# is_active goes false, so closing on select would only flicker.
	assert_bool(_selector.auto_interact).is_true()
	_selector.set_active(true)
	yield(await_idle_frame(), "completed")
	yield(await_idle_frame(), "completed")
	_aim_at_option(2)
	_left_click()
	assert_bool(_selector.is_dial_open()).is_true()


func test_manual_panel_closes_after_a_pick() -> void:
	_selector.auto_interact = false
	_selector.interact()
	yield(await_idle_frame(), "completed")
	yield(await_idle_frame(), "completed")
	assert_bool(_selector.is_dial_open()).is_true()
	_aim_at_option(1)
	_left_click()
	assert_bool(_selector.is_dial_open()).is_false()
	assert_int(_elevator.target_floor).is_equal(1)


func test_vertical_mouse_intent_sweeps_to_the_top_floor() -> void:
	_selector.set_active(true)
	yield(await_idle_frame(), "completed")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(30.0, -_selector.mouse_full_arc_distance)
	_selector._input(motion)
	assert_int(_dial.get_hovered_index()).is_equal(5)


# --- Cabin zoom ---

func _make_stand_in_player() -> KinematicBody:
	# A 5.5 m spring arm inside a 3.6 m car frames the cabin from out in the
	# shaft. Riding has to pull the camera in — anywhere in the car, for the whole
	# trip — and give the rider's own distance back when they step out.
	var player := KinematicBody.new()
	player.set_script(load("res://core_v2/tests/helpers/StandInPlayer.gd"))
	player.collision_layer = 2
	player.collision_mask = 0
	var shape := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = Vector3(0.3, 0.9, 0.3)
	shape.shape = box
	player.add_child(shape)
	return player


func test_riding_the_car_pulls_the_camera_in() -> void:
	var player := _make_stand_in_player()
	_elevator.add_child(player)
	player.global_transform.origin = _elevator.get_node("Platform").global_transform.origin + Vector3(1.2, 1.0, 1.2)
	for _i in range(6):
		yield(await_idle_frame(), "completed")
	assert_float(player.base_spring_length_3d) \
		.override_failure_message("boarding should shorten the spring arm") \
		.is_equal(_selector.cabin_zoom_spring_length)


func test_stepping_out_hands_the_distance_back() -> void:
	var player := _make_stand_in_player()
	_elevator.add_child(player)
	player.global_transform.origin = _elevator.get_node("Platform").global_transform.origin + Vector3(1.2, 1.0, 1.2)
	for _i in range(6):
		yield(await_idle_frame(), "completed")
	assert_float(player.base_spring_length_3d).is_equal(_selector.cabin_zoom_spring_length)

	player.global_transform.origin += Vector3(0, 0, 40)
	for _i in range(6):
		yield(await_idle_frame(), "completed")
	assert_float(player.base_spring_length_3d) \
		.override_failure_message("leaving should restore the rider's own distance") \
		.is_equal(5.5)
