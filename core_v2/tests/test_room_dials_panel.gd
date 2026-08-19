extends GdUnitTestSuite

# test_room_dials_panel.gd - Unit tests for RoomDialsPanel control (FD-270).

const RoomDialsPanelScript = preload("res://core_v2/things/RoomDialsPanel.gd")
const Room3DScript = preload("res://core_v2/systems/room/Room3D.gd")


func test_normalization_ranges() -> void:
	var panel = auto_free(RoomDialsPanelScript.new())

	# Temperature normalization defaults: min_temp = -25.0, max_temp = 40.0 (span 65)
	assert_float(panel._normalize_temperature(-25.0, -25.0, 40.0)).is_equal(0.0)
	assert_float(panel._normalize_temperature(40.0, -25.0, 40.0)).is_equal(1.0)
	assert_float(panel._normalize_temperature(7.5, -25.0, 40.0)).is_equal(0.5)
	assert_float(panel._normalize_temperature(-50.0, -25.0, 40.0)).is_equal(0.0)
	assert_float(panel._normalize_temperature(100.0, -25.0, 40.0)).is_equal(1.0)

	# Pressure normalization defaults: max_press = 2.88
	assert_float(panel._normalize_pressure(0.0, 2.88)).is_equal(0.0)
	assert_float(panel._normalize_pressure(2.88, 2.88)).is_equal(1.0)
	assert_float(panel._normalize_pressure(1.44, 2.88)).is_equal(0.5)
	assert_float(panel._normalize_pressure(-1.0, 2.88)).is_equal(0.0)
	assert_float(panel._normalize_pressure(5.0, 2.88)).is_equal(1.0)

	# Contamination normalization (0..1)
	assert_float(panel._normalize_contamination(0.0)).is_equal(0.0)
	assert_float(panel._normalize_contamination(1.0)).is_equal(1.0)
	assert_float(panel._normalize_contamination(0.5)).is_equal(0.5)
	assert_float(panel._normalize_contamination(-0.2)).is_equal(0.0)
	assert_float(panel._normalize_contamination(1.5)).is_equal(1.0)


func test_panel_null_room_safe_draw() -> void:
	var panel = auto_free(RoomDialsPanelScript.new())
	add_child(panel)

	# Must not crash when _room is null
	panel.notification(CanvasItem.NOTIFICATION_DRAW)
	assert_object(panel._room).is_null()


func test_panel_room_integration() -> void:
	var room = auto_free(Room3DScript.new())
	room.name = "TestRoom3D"
	add_child(room)

	var panel = auto_free(RoomDialsPanelScript.new())
	panel.room_path = room.get_path()
	add_child(panel)

	assert_object(panel._room).is_equal(room)

	# Emit value changes and ensure panel handles notifications without errors
	room.set_temperature(-30.0) # Lethal cold threshold
	room.set_pressure(3.0) # Overpressure threshold
	room.set_contamination(0.8) # Hazard threshold

	panel.notification(CanvasItem.NOTIFICATION_DRAW)
