extends GdUnitTestSuite

# Guard de regresion: T3 (FD-289) agrega BlastDoorController reusando la mecanica de
# FloorHatch.tscn sin tocarla. Este test verifica que la trampilla original sigue
# deslizando y siendo snapshot-able, para detectar cualquier rotura futura.

const FloorHatchScene = preload("res://core_v2/props/doors/FloorHatch.tscn")

func test_floor_hatch_door_still_slides_and_snapshots() -> void:
	var host: Spatial = auto_free(Spatial.new())
	host.name = "FloorHatchRegressionHost"
	add_child(host)
	var hatch: Node = FloorHatchScene.instance()
	host.add_child(hatch)
	yield(get_tree(), "idle_frame")

	var door = hatch.get_node_or_null("HatchDoor")
	assert_object(door).is_not_null()
	assert_bool(door.is_in_group("replay_sync")).is_true()
	assert_bool(door.has_method("get_snapshot")).is_true()
	assert_bool(door.has_method("restore_snapshot")).is_true()

	var start_x: float = door.translation.x
	door.set_active(true, true)
	assert_float(door.translation.x).is_equal(start_x + door.slide_vector.x)

	var snapshot = door.get_snapshot()
	assert_bool(bool(snapshot.get("active", false))).is_true()
	assert_float(float(snapshot.get("progress", 0.0))).is_equal(1.0)
