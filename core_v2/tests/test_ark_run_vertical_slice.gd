extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

# FD-324 F7 — recorrido integrado + determinismo del vertical slice.
# Corre test_ark_run_vertical_slice.oys sobre DOS instancias frescas de
# ArkRunSlice.tscn (Box3D) y exige hash idéntico entre runs y contra el hash
# dorado versionado en core_v2/tests/ark_run_vertical_slice.hash.

const SliceScene = preload("res://core_v2/levels/ark_run/ArkRunSlice.tscn")
const OYSInterpreter = preload("res://core_v2/systems/OYS_Interpreter.gd")
const OYS_PATH := "res://core_v2/tests/test_ark_run_vertical_slice.oys"
const HASH_PATH := "res://core_v2/tests/ark_run_vertical_slice.hash"

var _previous_gravity_mode := -1

func before() -> void:
	var anna = get_node_or_null("/root/ANNAV2")
	if anna and anna.has_method("set_replay_mode"):
		anna.set_replay_mode(true)
	var world = get_node_or_null("/root/GravityWorld")
	if world != null:
		_previous_gravity_mode = int(world.get_current_gravity_mode())

func after() -> void:
	var world = get_node_or_null("/root/GravityWorld")
	if world != null and _previous_gravity_mode >= 0:
		world.set_gravity_mode(_previous_gravity_mode)

func _run_oys_once() -> Dictionary:
	var slice = SliceScene.instance()
	add_child(slice)
	slice.set_physics_process(false)
	slice.pilot.set_physics_process(false)
	var file := File.new()
	assert_int(file.open(OYS_PATH, File.READ)).is_equal(OK)
	var script: String = file.get_as_text()
	file.close()
	var interpreter = OYSInterpreter.new(slice)
	interpreter.parse(script)
	interpreter.run()
	var wiring = slice.get_node_or_null("ArkRunWiring")
	assert_object(wiring).is_not_null()
	var state: Dictionary = wiring._determinism_state.duplicate(true)
	remove_child(slice)
	slice.free()
	return state

static func _normalize(value) -> String:
	if typeof(value) == TYPE_VECTOR3:
		return "%0.9f,%0.9f,%0.9f" % [value.x, value.y, value.z]
	if typeof(value) == TYPE_REAL:
		return "%0.9f" % value
	if typeof(value) == TYPE_BOOL:
		return "1" if value else "0"
	return str(value)

func _hash_state(state: Dictionary) -> String:
	var keys: Array = state.keys()
	keys.sort()
	var parts: Array = []
	for key in keys:
		parts.append("%s=%s" % [String(key), _normalize(state[key])])
	var payload := PoolStringArray(parts).join("|")
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(payload.to_utf8())
	return context.finish().hex_encode()

func _golden_hash() -> String:
	var file := File.new()
	if file.open(HASH_PATH, File.READ) != OK:
		return ""
	var text: String = file.get_as_text().strip_edges()
	file.close()
	return text

func test_two_fresh_runs_match_the_versioned_golden_hash() -> void:
	var first: Dictionary = _run_oys_once()
	var second: Dictionary = _run_oys_once()
	assert_bool(first.empty()).is_false()
	assert_bool(second.empty()).is_false()
	var first_hash: String = _hash_state(first)
	var second_hash: String = _hash_state(second)
	assert_str(first_hash).is_equal(second_hash)
	var golden: String = _golden_hash()
	if golden == "":
		printerr("ARK_RUN_GOLDEN_HASH=%s" % first_hash)
	assert_str(first_hash).is_equal(golden)

func test_scenario_covers_the_six_integrated_beats() -> void:
	var state: Dictionary = _run_oys_once()
	assert_bool(state.empty()).is_false()
	# 1) Explosión hacia el Puente (+Z) y aterrizaje grande acotado a slide.
	assert_float((state["launch_velocity"] as Vector3).z).is_greater(0.0)
	assert_float(float(state["landing_speed"])).is_greater(0.0)
	# 2) Cuerda enganchada a un anclaje de domo.
	assert_bool(bool(state["rope_attached"])).is_true()
	assert_float(float(state["rope_length"])).is_greater(0.0)
	# 3) Ascensor radial operativo con radio determinista.
	assert_bool(bool(state["elevator_operational"])).is_true()
	assert_float(float(state["elevator_radius"])).is_greater(0.0)
	# 4) Autonavegación al Motor con ruta activa y margen humano >= 25 %.
	assert_str(String(state["nav_destination"])).is_equal("engine")
	assert_int(int(state["nav_route_size"])).is_greater(1)
	assert_float(float(state["margin_pct"])).is_greater_equal(25.0)
	assert_bool(bool(state["margin_ok"])).is_true()
	# 5) Encendido al cruzar z=0 de regreso, conversión 3 s y colapso #9.
	assert_str(String(state["ignition_state"])).is_equal("ACTIVE")
	assert_float(float(state["a_axial"])).is_equal_approx(9.8, 1e-4)
	assert_float(float(state["conversion_elapsed"])).is_equal_approx(3.0, 1e-6)
	assert_int(int(state["collapses"])).is_greater(0)
	# 6) Meta, reinicio instantáneo y fantasma conservado.
	assert_int(int(state["ghost_samples_best"])).is_greater(0)
	assert_int(int(state["restart_runs"])).is_equal(1)
	assert_str(String(state["restart_ignition"])).is_equal("IDLE")
	assert_int(int(state["ghost_samples_after_restart"])).is_greater(0)
