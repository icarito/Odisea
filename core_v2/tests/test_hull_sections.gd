extends GdUnitTestSuite

# Entrecasco por secciones: el piloto real, con el autonavegador (TAB sostenido), cruza tres
# anillos con gravedad y giro distintos. Geometria estatica => receta de tests-de-travesia.md,
# avanzando tambien a mano el tick del nivel (que es quien cambia la gravedad).

const LEVEL = preload("res://core_v2/levels/hull_underdeck/HullSections.tscn")
const Registry = preload("res://core_v2/systems/scaffold/ScaffoldChunkRegistry.gd")
const VirtualMouseScript = preload("res://core_v2/ui/VirtualMouse.gd")
const TICKS_PER_FRAME := 8
const ORIGIN := Vector3(9000.0, 3000.0, 9000.0)

var _level: Spatial = null


func after_test() -> void:
	Input.action_release("nav_assist")
	if is_instance_valid(_level):
		_level.queue_free()
	yield(get_tree(), "idle_frame")


func test_autopilot_crosses_three_sections_with_their_own_gravity_and_spin() -> void:
	VirtualMouseScript.set_pointer_released(false)
	_level = LEVEL.instance()
	_level.translation = ORIGIN
	get_tree().root.add_child(_level)
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "physics_frame")
	var pilot: KinematicBody = _level._pilot
	var auto = _level._autopilot
	assert_object(auto).is_not_null()
	pilot.set_physics_process(false)
	_level.set_physics_process(false)
	pilot.input_provider.set_live_mode()
	pilot.input_provider.hardware_input_enabled = true
	Input.action_press("nav_assist")

	var seen := {}        # seccion -> gravedad del jugador al pisarla
	var swept := {}       # seccion -> barrido lateral maximo recibido al entrar
	var ticks := 0
	var limit: int = _level._placements.size() * 12 * 60
	while ticks < limit and not auto.is_finished():
		pilot._physics_process(0.0)
		_level._physics_process(1.0 / 60.0)
		ticks += 1
		var section: int = _level.current_section()
		seen[section] = -float(pilot.jump_logic.gravity)
		swept[section] = max(float(swept.get(section, 0.0)), abs(pilot.get_external_velocity().x))
		if ticks % TICKS_PER_FRAME == 0:
			yield(get_tree(), "physics_frame")
	prints("[hull_sections] ticks=", ticks, "pos=", pilot.global_transform.origin - ORIGIN, "g=", seen, "barrido=", swept)
	assert_bool(auto.is_finished()).override_failure_message(
		"no completo el tramo: pos=%s seccion=%d" % [pilot.global_transform.origin - ORIGIN, _level.current_section()]).is_true()
	assert_int(seen.size()).is_equal(3)
	for i in range(3):
		assert_float(float(seen[i])).is_equal(Registry.gravity_tier(float(_level.sections[i]["gravity"])))
	# Cruzar a un anillo que gira distinto arrastra de costado; el primero no.
	assert_float(float(swept[0])).is_less(0.01)
	assert_float(float(swept[1])).is_greater(1.0)
	assert_float(float(swept[2])).is_greater(1.0)
