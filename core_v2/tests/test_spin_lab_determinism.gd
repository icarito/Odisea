extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

# FD-323 Fase 3C — determinismo del ensamble SpinLab.
# Corre el mismo .oys sobre dos instancias frescas de SpinLab.tscn (Box3D) y
# exige hash idéntico de posición, velocidad, _up y gravity_mode (drift == 0).

const LabScene = preload("res://core_v2/levels/spin_lab/SpinLab.tscn")
const OYSInterpreter = preload("res://core_v2/systems/OYS_Interpreter.gd")
const OYS_PATH := "res://core_v2/tests/test_spin_lab_determinism.oys"

func before() -> void:
	var anna = get_node_or_null("/root/ANNAV2")
	if anna and anna.has_method("set_replay_mode"):
		anna.set_replay_mode(true)

func _run_oys_once() -> Dictionary:
	var lab = LabScene.instance()
	add_child(lab)
	lab.set_physics_process(false)
	var pilot = lab.get_node("Pilot")
	pilot.set_physics_process(false)
	var file := File.new()
	assert_int(file.open(OYS_PATH, File.READ)).is_equal(OK)
	var script: String = file.get_as_text()
	file.close()
	var interpreter = OYSInterpreter.new(lab)
	interpreter.parse(script)
	interpreter.run()
	var state: Dictionary = lab._determinism_state.duplicate(true)
	remove_child(lab)
	lab.free()
	return state

func _hash_state(state: Dictionary) -> String:
	var p: Vector3 = state["position"]
	var v: Vector3 = state["velocity"]
	var u: Vector3 = state["up"]
	var payload := "%0.9f|%0.9f|%0.9f|%0.9f|%0.9f|%0.9f|%0.9f|%0.9f|%0.9f|%d" % [
		p.x, p.y, p.z, v.x, v.y, v.z, u.x, u.y, u.z, int(state["gravity_mode"])
	]
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(payload.to_utf8())
	return ctx.finish().hex_encode()

func test_same_oys_twice_is_bit_identical() -> void:
	var first: Dictionary = _run_oys_once()
	var second: Dictionary = _run_oys_once()
	assert_bool(first.empty()).is_false()
	assert_bool(second.empty()).is_false()

	var position_drift: float = (first["position"] as Vector3).distance_to(second["position"])
	var velocity_drift: float = (first["velocity"] as Vector3).distance_to(second["velocity"])
	var up_drift: float = (first["up"] as Vector3).distance_to(second["up"])
	assert_float(position_drift).is_less(0.000000001)
	assert_float(velocity_drift).is_less(0.000000001)
	assert_float(up_drift).is_less(0.000000001)
	assert_int(int(first["gravity_mode"])).is_equal(int(second["gravity_mode"]))
	assert_str(_hash_state(first)).is_equal(_hash_state(second))
