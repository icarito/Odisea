extends GdUnitTestSuite

# test_tremor_zone.gd - GdUnit3 unit tests for TremorZoneV2 (FD-288)

const TremorZoneV2Script = preload("res://core_v2/components/TremorZoneV2.gd")
const OYS_ParserScript = preload("res://core_v2/systems/OYS_Parser.gd")
const OYS_InterpreterScript = preload("res://core_v2/systems/OYS_Interpreter.gd")

const STEP := 1.0 / 60.0

class DummyPlayerNode extends Spatial:
	var external_velocity: Vector3 = Vector3.ZERO
	var is_external_static: bool = true

	func set_external_velocity(v: Vector3) -> void:
		external_velocity = v

	func get_external_velocity() -> Vector3:
		return external_velocity

	func set_external_source_is_static(val: bool) -> void:
		is_external_static = val

class DummyRigidBody extends RigidBody:
	var impulses: Array = []

	func apply_central_impulse(impulse: Vector3) -> void:
		impulses.append(impulse)

class DummyCinematicManager extends Node:
	var shake_calls: Array = []
	var stop_calls: int = 0

	func trigger_camera_shake(duration: float = 0.35, amplitude: float = 0.08, frequency: float = 28.0, roll_degrees: float = 1.0) -> void:
		shake_calls.append({
			"duration": duration,
			"amplitude": amplitude,
			"frequency": frequency,
			"roll": roll_degrees
		})

	func stop_camera_shake() -> void:
		stop_calls += 1


# 1. Determinism test: same seed reproduces exact impulse sequence
func test_deterministic_seed_reproduction() -> void:
	var tremor1 = auto_free(TremorZoneV2Script.new())
	var tremor2 = auto_free(TremorZoneV2Script.new())

	tremor1.seed = 42
	tremor2.seed = 42
	tremor1.period = 0.12
	tremor2.period = 0.12

	for i in range(10):
		var t := i * 0.05
		var dir1: Vector3 = tremor1.get_impulse_direction_at_time(t)
		var dir2: Vector3 = tremor2.get_impulse_direction_at_time(t)
		assert_float(dir1.x).is_equal_approx(dir2.x, 0.0001)
		assert_float(dir1.y).is_equal_approx(dir2.y, 0.0001)
		assert_float(dir1.z).is_equal_approx(dir2.z, 0.0001)


# 2. Player external velocity and rigid body impulse application via step()
func test_player_and_rigid_body_impulses() -> void:
	var tremor = auto_free(TremorZoneV2Script.new())
	tremor.impulse_strength = 6.0
	tremor.period = 0.12
	tremor.seed = 123
	tremor.duration = 1.0
	tremor.camera_amplitude = 0.0 # Disable camera shake in mock

	var player = auto_free(DummyPlayerNode.new())
	var box = auto_free(DummyRigidBody.new())
	box.mode = RigidBody.MODE_RIGID

	add_child(tremor)
	add_child(player)
	add_child(box)

	var dir = tremor.get_impulse_direction_at_time(0.0)
	var expected_impulse = dir * 6.0

	# Exercise step logic via helper method
	tremor._apply_impulse_to_body(player, expected_impulse, STEP)
	tremor._apply_impulse_to_body(box, expected_impulse, STEP)

	assert_float(player.external_velocity.x).is_equal_approx(expected_impulse.x, 0.0001)
	assert_float(player.external_velocity.z).is_equal_approx(expected_impulse.z, 0.0001)
	assert_bool(player.is_external_static).is_false()

	assert_int(box.impulses.size()).is_equal(1)
	var rigid_imp: Vector3 = box.impulses[0]
	assert_float(rigid_imp.x).is_equal_approx((expected_impulse * STEP).x, 0.0001)


# 3. Expiration and process culling when inactive/expired
func test_culling_when_inactive_or_expired() -> void:
	var tremor = auto_free(TremorZoneV2Script.new())
	tremor.duration = 0.1
	tremor.impulse_strength = 5.0
	add_child(tremor)

	tremor.step(0.05) # time_acc becomes 0.05
	assert_bool(tremor.is_active).is_true()

	tremor.step(0.06) # time_acc becomes 0.11
	assert_bool(tremor.is_active).is_true()

	tremor.step(0.01) # Check at start of step: time_acc >= 0.1 -> sets is_active = false
	assert_bool(tremor.is_active).is_false()


# 4. Snapshot round-trip and restore behavior
func test_snapshot_restore() -> void:
	var tremor1 = auto_free(TremorZoneV2Script.new())
	tremor1.seed = 999
	tremor1._time_acc = 0.45
	tremor1._camera_shake_triggered = true
	tremor1.is_active = true

	var snapshot = tremor1.get_snapshot()

	var tremor2 = auto_free(TremorZoneV2Script.new())
	tremor2.is_active = false # Restore into inactive zone
	tremor2.restore_snapshot(snapshot)

	assert_int(tremor2.seed).is_equal(999)
	assert_float(tremor2._time_acc).is_equal_approx(0.45, 0.0001)
	assert_bool(tremor2._camera_shake_triggered).is_true()
	assert_bool(tremor2.is_active).is_true()


# 5. OYS TREMOR and TREMOR_STOP command execution
func test_oys_tremor_commands() -> void:
	var parser_inst = OYS_ParserScript.parse_instruction("TREMOR 2.0 0.08 15.0 42")
	assert_str(parser_inst.command).is_equal("TREMOR")
	assert_float(parser_inst.duration).is_equal(2.0)
	assert_float(parser_inst.amplitude).is_equal(0.08)
	assert_float(parser_inst.frequency).is_equal(15.0)
	assert_int(parser_inst.seed).is_equal(42)

	var stop_inst = OYS_ParserScript.parse_instruction("TREMOR_STOP")
	assert_str(stop_inst.command).is_equal("TREMOR_STOP")

	var host = auto_free(Node.new())
	add_child(host)

	var cm = auto_free(DummyCinematicManager.new())
	cm.name = "CinematicManager"
	host.get_tree().root.add_child(cm)

	var tremor_zone = auto_free(TremorZoneV2Script.new())
	tremor_zone.camera_amplitude = 0.08
	host.add_child(tremor_zone)

	var interpreter = OYS_InterpreterScript.new(host)
	interpreter._execute_instruction(parser_inst, 1)

	assert_bool(tremor_zone.is_active).is_true()
	assert_int(tremor_zone.seed).is_equal(42)
	assert_float(tremor_zone.duration).is_equal(2.0)

	# TremorZoneV2 handles camera shake in its step(), verifying single shake trigger
	tremor_zone.step(0.01)
	assert_int(cm.shake_calls.size()).is_equal(1)

	interpreter._execute_instruction(stop_inst, 1)
	assert_bool(tremor_zone.is_active).is_false()
	assert_int(cm.stop_calls).is_equal(1)

	cm.queue_free()
