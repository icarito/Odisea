extends GdUnitTestSuite

const CONVEYOR_SCENE = preload("res://core_v2/props/Conveyor.tscn")
const CARROUSEL_SCENE = preload("res://core_v2/props/ConveyorCarrousel.tscn")

func _spawn(scene: PackedScene) -> Node:
	var host: Spatial = auto_free(Spatial.new())
	add_child(host)
	var node: Node = auto_free(scene.instance())
	host.add_child(node)
	yield(get_tree(), "idle_frame")
	return node

func test_conveyor_defaults_create_feedback_and_support_geometry():
	var conveyor = yield(_spawn(CONVEYOR_SCENE), "completed")

	assert_float(conveyor.width).is_equal(3.0)
	assert_object(conveyor.get_node("Ground/BaseVisual")).is_not_null()
	assert_object(conveyor.get_node("EntryPlate")).is_not_null()
	assert_object(conveyor.get_node("SidePlateLeft")).is_not_null()
	assert_object(conveyor.get_node("Indicators/IndicatorReadyLight")).is_not_null()
	assert_object(conveyor.get_node("Indicators/IndicatorRunningMesh")).is_not_null()
	assert_object(conveyor.get_node("Indicators/IndicatorDisabledMesh")).is_not_null()
	assert_object(conveyor.get_node("Indicators/IndicatorReadyPlate/CollisionShape")).is_not_null()

	var plate_collision: CollisionShape = conveyor.get_node("Indicators/IndicatorReadyPlate/CollisionShape")
	assert_float(plate_collision.shape.extents.y).is_less_equal(0.03)

func test_conveyor_ready_state_keeps_visual_idle_without_pushing():
	var conveyor = yield(_spawn(CONVEYOR_SCENE), "completed")
	conveyor.set_active(true, true)
	conveyor.occupancy_detection = true
	conveyor.step(0.5)

	assert_str(conveyor.get_feedback_state()).is_equal("ready")
	assert_bool(conveyor.is_running()).is_false()
	assert_bool(conveyor.get_node("Indicators/IndicatorReadyMesh").visible).is_true()

	var snapshot: Dictionary = conveyor.get_snapshot()
	assert_bool(snapshot.has("occupancy_detection")).is_true()
	assert_bool(snapshot.has("visual_speed")).is_true()
	assert_bool(float(snapshot["visual_speed"]) > 0.0).is_true()

func test_conveyor_running_state_without_occupancy_detection():
	var conveyor = yield(_spawn(CONVEYOR_SCENE), "completed")
	conveyor.occupancy_detection = false
	conveyor.set_active(true, true)
	conveyor.step(0.5)

	assert_str(conveyor.get_feedback_state()).is_equal("running")
	assert_bool(conveyor.is_running()).is_true()
	assert_bool(conveyor.get_node("Indicators/IndicatorRunningLight").visible).is_true()

func test_conveyor_carrousel_push_is_tangential():
	var carrousel = yield(_spawn(CARROUSEL_SCENE), "completed")
	carrousel.radius = 3.0
	carrousel.angular_speed = 1.5
	yield(get_tree(), "idle_frame")

	var velocity: Vector3 = carrousel.compute_nominal_push_velocity_for_point(carrousel.global_transform.origin + Vector3(3.0, 0.0, 0.0))
	assert_float(velocity.x).is_equal_approx(0.0, 0.001)
	assert_float(velocity.y).is_equal_approx(0.0, 0.001)
	assert_float(velocity.z).is_equal_approx(-4.5, 0.001)

func test_conveyor_carrousel_snapshot_and_feedback_nodes_exist():
	var carrousel = yield(_spawn(CARROUSEL_SCENE), "completed")
	carrousel.occupancy_detection = false
	carrousel.set_active(true, true)
	carrousel.step(0.5)

	assert_object(carrousel.get_node("OuterRail")).is_not_null()
	assert_object(carrousel.get_node("Indicators/IndicatorDisabledLight")).is_not_null()
	assert_str(carrousel.get_feedback_state()).is_equal("running")

	var snapshot: Dictionary = carrousel.get_snapshot()
	assert_bool(snapshot.has("radius")).is_true()
	assert_bool(snapshot.has("angular_speed")).is_true()
	assert_bool(snapshot.has("visual_phase")).is_true()
