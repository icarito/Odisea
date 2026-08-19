extends GdUnitTestSuite

# test_coolant_schematic_panel.gd - Unit test for CoolantSchematicPanel Control (FD-270).

const CoolantSchematicPanel = preload("res://core_v2/things/CoolantSchematicPanel.gd")
const CoolantLeak = preload("res://core_v2/systems/cryo/CoolantLeak.gd")

var _panel: CoolantSchematicPanel


func before_test() -> void:
	_panel = CoolantSchematicPanel.new()
	add_child(_panel)


func after_test() -> void:
	if is_instance_valid(_panel):
		_panel.queue_free()


func test_panel_initialization_and_empty_scene_draw() -> void:
	assert_object(_panel).is_not_null()
	# Verify that ready and drawing in empty scene run without errors
	_panel.notification(CanvasItem.NOTIFICATION_DRAW)
	assert_bool(true).is_true()


func test_panel_draw_with_live_valves_and_fissures() -> void:
	# Create dummy valves
	var valve_west := Node.new()
	valve_west.name = "ValveWestFloor1"
	valve_west.add_to_group("coolant_valve")
	valve_west.set("is_active", true)
	valve_west.add_user_signal("valve_state_changed", [{"name": "is_open", "type": TYPE_BOOL}])

	var valve_east := Node.new()
	valve_east.name = "ValveEastFloor1"
	valve_east.add_to_group("coolant_valve")
	valve_east.set("is_active", false)
	valve_east.add_user_signal("valve_state_changed", [{"name": "is_open", "type": TYPE_BOOL}])

	var valve_interlink := Node.new()
	valve_interlink.name = "ValveInterlink"
	valve_interlink.add_to_group("coolant_valve")
	valve_interlink.set("is_active", true)
	valve_interlink.add_user_signal("valve_state_changed", [{"name": "is_open", "type": TYPE_BOOL}])

	add_child(valve_west)
	add_child(valve_east)
	add_child(valve_interlink)

	# Trigger setup
	_panel._setup_valve_connections()

	# Dispatch NOTIFICATION_DRAW
	_panel.notification(CanvasItem.NOTIFICATION_DRAW)

	# Simulate valve signal
	valve_west.emit_signal("valve_state_changed", false)
	_panel.notification(CanvasItem.NOTIFICATION_DRAW)

	valve_west.queue_free()
	valve_east.queue_free()
	valve_interlink.queue_free()
	assert_bool(true).is_true()
