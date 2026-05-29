# GdUnit3 generated TestSuite
extends GdUnitTestSuite

# TestSuite for PipeValve and Manometer integration

const PipeValve = preload("res://core_v2/props/pipe/PipeValve.tscn")
const Manometer = preload("res://core_v2/props/Manometer.tscn")

func test_valve_manometer_integration() -> void:
	var scene = Spatial.new()
	var valve = PipeValve.instance()
	var mano = Manometer.instance()

	scene.add_child(valve)
	scene.add_child(mano)

	# Connect them
	valve.connect("valve_state_changed", mano, "set_active")

	# Initial state
	assert_bool(valve.is_active).is_false()
	assert_float(mano.pressure_value).is_equal(0.0)

	# Interact with valve
	valve.interact()
	assert_bool(valve.is_active).is_true()

	# Valve animation takes time, but it should emit signal on completion or if we snap it.
	# Let's snap it for instant check
	valve.set_active(true, true)
	assert_float(mano.pressure_value).is_equal(1.0)

	valve.set_active(false, true)
	assert_float(mano.pressure_value).is_equal(0.0)

	scene.free()
