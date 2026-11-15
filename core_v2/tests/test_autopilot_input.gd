extends GdUnitTestSuite

# Transit-Run · modo asistido. AutopilotInputV2 recorre con el piloto REAL una pista calibrada
# al contrato de docs/canon/WFC_FLOW_METRICS.md (hueco al 70% de D_max, escalon al 70% de
# H_max) y cede el control al humano en el mismo tick.
#
# Geometria estatica: se usa la receta de .operator-shared/guides/tests-de-travesia.md
# (tick real del piloto varias veces por frame del motor).

const PILOT_SCENE = preload("res://core_v2/actors/Pilot_v2.tscn")
const AutopilotScript = preload("res://core_v2/input/AutopilotInputV2.gd")
const FlowMetricsScript = preload("res://core_v2/systems/flow/FlowMetrics.gd")
const VirtualMouseScript = preload("res://core_v2/ui/VirtualMouse.gd")

const ORIGIN := Vector3(6000.0, 6000.0, 6000.0)
const TICKS_PER_FRAME := 8
const ACTIONS := ["move_forward", "move_backward", "move_left", "move_right", "jump", "run", "crouch", "nav_assist"]
const DECK := Vector3(6.0, 1.0, 10.0)

var _root: Spatial = null
var _pilot: KinematicBody = null
var _auto = null
var _ticks := 0


func before_test() -> void:
	_release_all()
	VirtualMouseScript.set_pointer_released(false)
	_root = Spatial.new()
	_root.translation = ORIGIN
	get_tree().root.add_child(_root)
	var fm = FlowMetricsScript.from_scene()
	var gap: float = 0.7 * fm.d_max()
	var rise: float = 0.7 * fm.h_max()
	# A (salida) -> hueco -> B -> escalon -> C. Las tapas son la superficie caminable.
	_deck(Vector3(0.0, 0.0, 0.0), Vector3(6.0, 1.0, 20.0))
	var b_z: float = 10.0 + gap + DECK.z * 0.5
	var c_z: float = b_z + DECK.z
	_deck(Vector3(0.0, 0.0, b_z), DECK)
	_deck(Vector3(0.0, rise, c_z), DECK)
	_pilot = PILOT_SCENE.instance()
	_pilot.translation = Vector3(0.0, 0.05, -8.0)
	_root.add_child(_pilot)
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "physics_frame")
	_pilot.set_physics_process(false)
	_pilot.input_provider.set_live_mode()
	_pilot.input_provider.hardware_input_enabled = true
	_auto = AutopilotScript.new()
	_auto.setup(_pilot)
	_auto.set_route([
		{"position": ORIGIN + Vector3(0.0, 0.0, b_z), "size": DECK},
		{"position": ORIGIN + Vector3(0.0, rise, c_z), "size": DECK},
	])
	_auto.enabled = true
	_pilot.input_provider.autopilot = _auto
	_ticks = 0


func after_test() -> void:
	_release_all()
	if is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_pilot = null
	yield(get_tree(), "idle_frame")


# `top` es el centro de la tapa (y = altura caminable).
func _deck(top: Vector3, size: Vector3) -> void:
	var body := StaticBody.new()
	var col := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = size * 0.5
	col.shape = box
	body.add_child(col)
	body.translation = top - Vector3(0.0, size.y * 0.5, 0.0)
	body.collision_layer = 1
	_root.add_child(body)


func _release_all() -> void:
	for a in ACTIONS:
		if InputMap.has_action(a):
			Input.action_release(a)


# Todo tick corre DENTRO de un frame de fisica: fuera de el, move_and_slide usa el delta de
# proceso y el piloto avanza a otra velocidad (el test pasaba o fallaba segun el desfase).
func _tick(n: int = 1):
	for _i in range(n):
		if _ticks % TICKS_PER_FRAME == 0:
			yield(get_tree(), "physics_frame")
		_pilot._physics_process(0.0)
		_ticks += 1
	yield(get_tree(), "physics_frame")


func _h_speed() -> float:
	return Vector2(_pilot.velocity.x, _pilot.velocity.z).length()


func test_drives_only_while_nav_assist_is_held() -> void:
	# Sin TAB no hace nada, por mucho que el jugador se quede quieto.
	yield(_tick(60), "completed")
	assert_bool(_auto.is_active()).is_false()
	assert_float(_h_speed()).is_less(0.1)
	Input.action_press("nav_assist")
	for _i in range(150):
		if _auto.is_finished():
			break
		yield(_tick(8), "completed")
	prints("[autopilot] ticks=", _ticks, "pos=", _pilot.global_transform.origin - ORIGIN)
	assert_bool(_auto.is_finished()).is_true()
	# Llego (arriba del escalon, sobre la tapa de C) y no sigue de largo.
	var end: Vector3 = _pilot.global_transform.origin - ORIGIN
	assert_float(end.y).is_between(2.3, 2.9)
	yield(_tick(60), "completed")
	assert_float((_pilot.global_transform.origin - ORIGIN).y).is_between(2.3, 2.9)


func test_releasing_nav_assist_returns_control_in_the_same_tick() -> void:
	Input.action_press("nav_assist")
	yield(_tick(40), "completed")
	assert_bool(_auto.is_active()).is_true()
	Input.action_release("nav_assist")
	yield(_tick(1), "completed")
	assert_bool(_auto.is_active()).is_false()
	var d = _pilot.input_provider.last_input
	assert_float(d.move_vec.length()).is_less(0.01)
	assert_bool(d.jump).is_false()


func test_human_input_takes_over_same_tick_without_momentum_jump() -> void:
	Input.action_press("nav_assist")
	yield(_tick(60), "completed")
	assert_bool(_auto.is_active()).is_true()
	var before: float = _h_speed()
	assert_float(before).is_greater(3.0)

	# Con TAB todavia sostenido, el humano manda.
	Input.action_press("move_left")
	yield(_tick(1), "completed")
	assert_bool(_auto.is_active()).is_false()
	var d = _pilot.input_provider.last_input
	assert_bool(d.sprint).is_false()
	assert_bool(d.jump).is_false()
	assert_float(d.move_vec.x).is_less(-0.5)
	# El relevo solo cambia intents: en un tick la velocidad no puede variar mas que a·dt.
	assert_float(abs(_h_speed() - before)).is_less(1.5)

	Input.action_release("move_left")
	yield(_tick(1), "completed")
	assert_bool(_auto.is_active()).is_true()
