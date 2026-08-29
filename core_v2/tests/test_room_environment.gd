extends GdUnitTestSuite

# test_room_environment.gd - GdUnit3 unit tests for Room3D environmental aggregator (FD-269).
# Verifies variable accumulation, threshold signals, hazard damage, and snapshot determinism.

const Room3DScript = preload("res://core_v2/systems/room/Room3D.gd")
const STEP := 1.0 / 60.0

class DummyCoolantLeak extends Node:
	var intensity: float = 0.0

	func _init(value: float) -> void:
		intensity = value
		add_to_group("coolant_leak")

	func get_leak_intensity() -> float:
		return intensity


func _step_room(room, seconds: float) -> void:
	var steps := int(round(seconds / STEP))
	for _i in range(steps):
		room._physics_process(STEP)


# 1. Delta accumulation and value bounds
func test_delta_accumulation_and_bounds() -> void:
	var room = auto_free(Room3DScript.new())
	room.temperature = 20.0
	room.pressure = 1.0
	room.contamination = 0.0
	add_child(room)

	room.add_temperature(-10.0)
	assert_float(room.temperature).is_equal(10.0)

	room.add_pressure(0.5)
	assert_float(room.pressure).is_equal(1.5)

	room.add_contamination(0.4)
	assert_float(room.contamination).is_equal(0.4)

	# Clamping bounds test
	room.add_contamination(1.5)
	assert_float(room.contamination).is_equal(1.0) # Clamped to 1.0

	room.add_contamination(-2.0)
	assert_float(room.contamination).is_equal(0.0) # Clamped to 0.0

	room.add_pressure(-5.0)
	assert_float(room.pressure).is_equal(0.0) # Clamped to 0.0


# 2. Discrete threshold crossings and signals
func test_threshold_crossings_and_signals() -> void:
	var room = auto_free(Room3DScript.new())
	room.temperature = 10.0
	room.pressure = 1.0
	room.contamination = 0.0
	add_child(room)

	var freezing_signals := [0]
	var lethal_signals := [0]
	var fog_signals := [0]
	var hazard_signals := [0]
	var overpressure_signals := [0]

	room.connect("freezing_changed", self, "_on_signal_event", [freezing_signals])
	room.connect("lethal_cold_changed", self, "_on_signal_event", [lethal_signals])
	room.connect("fog_changed", self, "_on_signal_event", [fog_signals])
	room.connect("hazard_changed", self, "_on_signal_event", [hazard_signals])
	room.connect("overpressure_changed", self, "_on_signal_event", [overpressure_signals])

	# 1) Temperature drops to freezing (<= 0.0)
	room.set_temperature(-5.0)
	assert_bool(room.is_freezing()).is_true()
	assert_int(freezing_signals[0]).is_equal(1)

	# Setting temp further below freezing point shouldn't re-emit freezing signal
	room.set_temperature(-10.0)
	assert_int(freezing_signals[0]).is_equal(1)

	# 2) Temperature drops to lethal cold (<= -50.0)
	room.set_temperature(-55.0)
	assert_bool(room.is_lethal_cold()).is_true()
	assert_int(lethal_signals[0]).is_equal(1)

	# 3) Contamination crosses fog threshold (>= 0.3)
	room.set_contamination(0.4)
	assert_bool(room.is_fog_active()).is_true()
	assert_int(fog_signals[0]).is_equal(1)

	# 4) Contamination crosses hazard threshold (>= 0.7)
	room.set_contamination(0.8)
	assert_bool(room.is_hazard_active()).is_true()
	assert_int(hazard_signals[0]).is_equal(1)

	# 5) Pressure crosses overpressure threshold (> 2.4)
	room.set_pressure(3.0)
	assert_bool(room.is_overpressured()).is_true()
	assert_int(overpressure_signals[0]).is_equal(1)

	# Resetting back to nominal emits signals again (transition to false)
	room.set_temperature(20.0)
	assert_bool(room.is_freezing()).is_false()
	assert_bool(room.is_lethal_cold()).is_false()
	assert_int(freezing_signals[0]).is_equal(2)
	assert_int(lethal_signals[0]).is_equal(2)


# 3. Environmental hazard damage ticks
func test_environmental_hazard_damage() -> void:
	var room = auto_free(Room3DScript.new())
	room.temperature = -60.0 # Lethal cold (below -50 threshold)
	room.contamination = 0.8 # Vapor hazard
	room.cold_damage_per_second = 10.0
	room.vapor_damage_per_second = 20.0
	add_child(room)

	# Dummy player node in group "player"
	var player = auto_free(Spatial.new())
	player.add_to_group("player")
	player.set_script(load("res://core_v2/tests/helpers/DummyPlayerWithHealth.gd") if ResourceLoader.exists("res://core_v2/tests/helpers/DummyPlayerWithHealth.gd") else null)

	var health_dict := {"health": 100.0}
	player.set_meta("health", health_dict)

	# Attach take_damage method dynamically
	player.set_script(null)
	var script = GDScript.new()
	script.source_code = "extends Spatial\nvar health = 100.0\nfunc take_damage(amount):\n\thealth -= amount\n"
	script.reload()
	player.set_script(script)
	add_child(player)

	# Step 1 second of room physics process (both lethal cold + vapor hazard active = 30 dmg/sec)
	_step_room(room, 1.0)

	assert_float(player.health).is_equal_approx(70.0, 0.1)


# 4. Snapshot determinism
func test_snapshot_restore_determinism() -> void:
	var room = auto_free(Room3DScript.new())
	room.temperature = -15.0
	room.pressure = 2.8
	room.contamination = 0.5
	add_child(room)

	_step_room(room, 0.1)

	var snapshot: Dictionary = room.get_snapshot()

	assert_float(snapshot["temperature"]).is_equal(-15.0)
	assert_float(snapshot["pressure"]).is_equal(2.8)
	assert_float(snapshot["contamination"]).is_equal(0.5)
	assert_bool(snapshot["is_freezing"]).is_true()
	assert_bool(snapshot["is_fog_active"]).is_true()

	# Alter room state
	room.set_temperature(30.0)
	room.set_pressure(1.0)
	room.set_contamination(0.0)

	assert_bool(room.is_freezing()).is_false()

	# Restore snapshot
	var temperature_signals := [0]
	var pressure_signals := [0]
	var contamination_signals := [0]
	room.connect("temperature_changed", self, "_on_signal_event", [temperature_signals])
	room.connect("pressure_changed", self, "_on_signal_event", [pressure_signals])
	room.connect("contamination_changed", self, "_on_signal_event", [contamination_signals])
	room.restore_snapshot(snapshot)

	assert_float(room.temperature).is_equal(-15.0)
	assert_float(room.pressure).is_equal(2.8)
	assert_float(room.contamination).is_equal(0.5)
	assert_bool(room.is_freezing()).is_true()
	assert_bool(room.is_fog_active()).is_true()
	assert_int(temperature_signals[0]).is_equal(1)
	assert_int(pressure_signals[0]).is_equal(1)
	assert_int(contamination_signals[0]).is_equal(1)


func test_cold_room_recovers_only_after_coolant_leaks_stop() -> void:
	var room = auto_free(Room3DScript.new())
	room.temperature = -2.0
	room.recover_from_inactive_coolant_leaks = true
	room.coolant_temperature_recovery_rate = 1.0
	add_child(room)
	var leak: DummyCoolantLeak = auto_free(DummyCoolantLeak.new(1.0))
	add_child(leak)

	room._physics_process(1.0)
	assert_float(room.temperature).is_equal_approx(-2.0, 0.0001)

	leak.intensity = 0.0
	room._physics_process(1.0)
	assert_float(room.temperature).is_equal_approx(-1.0, 0.0001)
	room._physics_process(2.0)
	assert_float(room.temperature).is_equal_approx(0.0, 0.0001)


func _on_signal_event(_arg, sink: Array) -> void:
	sink[0] += 1
