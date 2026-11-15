extends GdUnitTestSuite

# Transit-Run / WFC flow metrics (fase 1, W1).
#
# Mide EN EL MOTOR las constantes fisicas reales del jugador que definen el alcance de la
# ruta principal de un plataformero cinetico (parkour 3D). Nada se hardcodea: cada constante
# se LEE de la escena instanciada Pilot_v2.tscn (a traves de FlowMetrics, la fuente unica) y
# cada metrica sale de simular input real por las acciones del InputMap que lee el
# InputProviderV2 del propio PlayerControllerV2. No se escriben velocidades privadas: solo se
# lee estado publico (posicion, is_on_floor, get_horizontal_velocity).
#
# Frecuencias: 60 Hz (default) y 30 Hz (handheld, adaptive tick). La fisica de Godot 3 integra
# por tick, asi que el alcance cambia con dt; la ruta principal se calibra contra el peor caso.
# El tick se fija con Engine.iterations_per_second y se avanza por frames REALES del motor
# (yield physics_frame), porque el movimiento del KinematicBody depende del delta de fisica del
# frame: forzar step() fuera del frame usa el delta real y no es reproducible.
#
# El test exporta user://flow_metrics.json (lo medido) y verifica que el documento
# docs/canon/WFC_FLOW_METRICS.md coincida dentro de tolerancia.

const PILOT_SCENE = preload("res://core_v2/actors/Pilot_v2.tscn")
const FlowMetricsScript = preload("res://core_v2/systems/flow/FlowMetrics.gd")
const LedgeV2Script = preload("res://core_v2/components/LedgeV2.gd")
const VirtualMouseScript = preload("res://core_v2/ui/VirtualMouse.gd")
const DOC_PATH := "res://docs/canon/WFC_FLOW_METRICS.md"
const OUT_JSON := "user://flow_metrics.json"

const FLOOR_EXTENTS := Vector3(80.0, 0.5, 80.0)
const TICKS := [60, 30]
const ALL_ACTIONS := ["move_forward", "move_backward", "move_left", "move_right", "jump", "run", "crouch"]

const TOL_REL := 0.15
const TOL_ABS := 0.30

# Cornisa
const WALL_WIDTH := 6.0
const WALL_THICKNESS := 1.2
const LEDGE_ANCHOR_Y := 4.0
const LEDGE_ANCHOR_Z := 0.0
const LEDGE_PLAYER_Z := -0.6

var _root: Spatial = null
var _pilot: KinematicBody = null
var _jump: Node = null
var _move: Node = null
var _traversal: Node = null
var _fm = null
var _tick := 60
var _dt := 1.0 / 60.0
var _prev_ips := 60


# ---------------------------------------------------------------------------
# Ciclo de vida
# ---------------------------------------------------------------------------

func before_test() -> void:
	_prev_ips = Engine.iterations_per_second
	_root = Spatial.new()
	_root.name = "FlowMetricsRoot"
	_root.translation = Vector3(6000.0, 6000.0, 6000.0)
	get_tree().root.add_child(_root)
	_add_static_box(_root, FLOOR_EXTENTS * 2.0, Vector3(0.0, -FLOOR_EXTENTS.y, 0.0))
	VirtualMouseScript.set_pointer_released(false)


func after_test() -> void:
	_release_all()
	Engine.iterations_per_second = _prev_ips
	VirtualMouseScript.set_pointer_released(false)
	if is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_pilot = null
	yield(get_tree(), "idle_frame")


func _add_static_box(parent: Node, size: Vector3, at: Vector3) -> StaticBody:
	var body := StaticBody.new()
	var col := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = size * 0.5
	col.shape = box
	body.add_child(col)
	body.translation = at
	body.collision_layer = 1
	parent.add_child(body)
	return body


func _use_tick(hz: int) -> void:
	_tick = hz
	_dt = 1.0 / float(hz)
	Engine.iterations_per_second = hz


func _spawn_pilot(at: Vector3 = Vector3(0.0, 0.05, 0.0)):
	_pilot = PILOT_SCENE.instance()
	_pilot.name = "Pilot"
	_pilot.translation = at
	_root.add_child(_pilot)
	yield(get_tree(), "idle_frame")
	_jump = _pilot.get_node("Logic/Jump")
	_move = _pilot.get_node("Logic/Movement")
	_traversal = _pilot.get_node("Logic/Traversal")
	_fm = FlowMetricsScript.from_pilot_node(_pilot)
	_fm.set_tick(float(_tick))


func _respawn():
	if is_instance_valid(_pilot):
		_pilot.queue_free()
	_pilot = null
	yield(get_tree(), "idle_frame")
	yield(_spawn_pilot(), "completed")


func _release_all() -> void:
	for a in ALL_ACTIONS:
		if InputMap.has_action(a):
			Input.action_release(a)


func _frame():
	yield(get_tree(), "physics_frame")


func _frames(n: int):
	for _i in range(n):
		yield(get_tree(), "physics_frame")


func _pos() -> Vector3:
	return _pilot.global_transform.origin


func _hdist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _speed() -> float:
	return _move.get_horizontal_velocity().length()


# ---------------------------------------------------------------------------
# Metricas (corrutinas: cada una devuelve su valor via yield)
# ---------------------------------------------------------------------------

# Salto completo con el boton sostenido; sigue la altura hasta el aterrizaje.
func _m_h_max() -> float:
	yield(_frames(10), "completed")
	var y0: float = _pos().y
	var max_y: float = y0
	Input.action_press("jump", 1.0)
	var airborne := false
	for _i in range(200):
		yield(get_tree(), "physics_frame")
		var y: float = _pos().y
		max_y = max(max_y, y)
		if not airborne and not _pilot.is_on_floor():
			airborne = true
		elif airborne and _pilot.is_on_floor():
			break
	_release_all()
	return max_y - y0


func _m_h_tap() -> float:
	yield(_frames(10), "completed")
	var y0: float = _pos().y
	Input.action_press("jump", 1.0)
	var hold := max(1, int(ceil(_fm.min_jump_time * _tick)))
	yield(_frames(hold), "completed")
	Input.action_release("jump")
	var max_y: float = y0
	var airborne := false
	for _i in range(200):
		yield(get_tree(), "physics_frame")
		var y: float = _pos().y
		max_y = max(max_y, y)
		if not airborne and not _pilot.is_on_floor():
			airborne = true
		elif airborne and _pilot.is_on_floor():
			break
	_release_all()
	return max_y - y0


func _m_t_air() -> float:
	yield(_frames(10), "completed")
	Input.action_press("jump", 1.0)
	var airborne := false
	for _i in range(30):
		yield(get_tree(), "physics_frame")
		if not _pilot.is_on_floor():
			airborne = true
			break
	if not airborne:
		_release_all()
		return -1.0
	var frames := 0
	for _i in range(300):
		frames += 1
		yield(get_tree(), "physics_frame")
		if _pilot.is_on_floor():
			break
	_release_all()
	return float(frames) * _dt


func _run_jump_distance(use_run: bool) -> float:
	yield(_frames(10), "completed")
	if use_run:
		Input.action_press("run")
	Input.action_press("move_forward", 1.0)
	yield(_frames(25), "completed")
	Input.action_press("jump", 1.0)
	var airborne := false
	for _i in range(30):
		yield(get_tree(), "physics_frame")
		if not _pilot.is_on_floor():
			airborne = true
			break
	if not airborne:
		_release_all()
		return -1.0
	var takeoff := _pos()
	for _i in range(300):
		yield(get_tree(), "physics_frame")
		if _pilot.is_on_floor():
			break
	var d := _hdist(takeoff, _pos())
	_release_all()
	return d


func _m_start_distance() -> float:
	yield(_frames(10), "completed")
	var start := _pos()
	Input.action_press("run")
	Input.action_press("move_forward", 1.0)
	var threshold: float = _fm.run_speed() * 0.95
	var reached := false
	for _i in range(120):
		yield(get_tree(), "physics_frame")
		if _speed() >= threshold:
			reached = true
			break
	var d := _hdist(start, _pos())
	_release_all()
	return d if reached else -1.0


func _m_stop_distance() -> float:
	yield(_frames(10), "completed")
	Input.action_press("run")
	Input.action_press("move_forward", 1.0)
	yield(_frames(25), "completed")
	var release_pos := _pos()
	_release_all()
	for _i in range(120):
		yield(get_tree(), "physics_frame")
		if _speed() < 0.05:
			break
	return _hdist(release_pos, _pos())


func _m_roll_jump() -> Dictionary:
	yield(_frames(10), "completed")
	Input.action_press("run")
	Input.action_press("move_forward", 1.0)
	yield(_frames(25), "completed")
	Input.action_press("jump", 1.0)
	var airborne := false
	for _i in range(30):
		yield(get_tree(), "physics_frame")
		if not _pilot.is_on_floor():
			airborne = true
			break
	Input.action_release("jump")
	if not airborne:
		_release_all()
		return {"distance": -1.0, "roll_speed": -1.0}
	# Sostener crouch en el descenso: al aterrizar con impacto fuerte dispara el roll.
	Input.action_press("crouch")
	for _i in range(300):
		yield(get_tree(), "physics_frame")
		if _pilot.is_on_floor():
			break
	# El roll arranca en el frame de aterrizaje: dar margen.
	var rolling := false
	for _i in range(15):
		if _move.is_rolling():
			rolling = true
			break
		yield(get_tree(), "physics_frame")
	if not rolling:
		_release_all()
		return {"distance": -1.0, "roll_speed": -1.0}
	var roll_speed: float = _speed()
	var roll_start := _pos()
	Input.action_release("crouch")
	Input.action_press("jump", 1.0)
	var airborne2 := false
	for _i in range(30):
		yield(get_tree(), "physics_frame")
		if not _pilot.is_on_floor():
			airborne2 = true
			break
	var d := -1.0
	if airborne2:
		for _i in range(300):
			yield(get_tree(), "physics_frame")
			if _pilot.is_on_floor():
				break
		d = _hdist(roll_start, _pos())
	_release_all()
	return {"distance": d, "roll_speed": roll_speed}


# ---------------------------------------------------------------------------
# Cornisa: banda de agarre + mantle (frames reales del motor por el InteractArea)
# ---------------------------------------------------------------------------

func _build_ledge_wall() -> Array:
	var wall := StaticBody.new()
	var col := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = Vector3(WALL_WIDTH * 0.5, LEDGE_ANCHOR_Y * 0.5 + 0.1, WALL_THICKNESS * 0.5)
	col.shape = box
	wall.add_child(col)
	wall.translation = Vector3(0.0, LEDGE_ANCHOR_Y * 0.5 + 0.1, LEDGE_ANCHOR_Z + WALL_THICKNESS * 0.5)
	wall.collision_layer = 1
	_root.add_child(wall)
	var ledge = LedgeV2Script.new()
	ledge.name = "TestLedge"
	ledge.ledge_width = 4.0
	ledge.translation = Vector3(0.0, LEDGE_ANCHOR_Y, LEDGE_ANCHOR_Z)
	_root.add_child(ledge)
	return [wall, ledge]


func _try_ledge_offset(offset: float) -> Dictionary:
	var nodes := _build_ledge_wall()
	if is_instance_valid(_pilot):
		_pilot.queue_free()
	_pilot = null
	yield(get_tree(), "idle_frame")
	_pilot = PILOT_SCENE.instance()
	_pilot.name = "Pilot"
	_pilot.translation = Vector3(0.0, LEDGE_ANCHOR_Y - offset, LEDGE_PLAYER_Z)
	_root.add_child(_pilot)
	_traversal = _pilot.get_node("Logic/Traversal")
	var hung := false
	var mantled := false
	for _i in range(10):
		yield(get_tree(), "physics_frame")
		if _traversal.is_hanging:
			hung = true
			break
	if hung:
		Input.action_press("move_forward", 1.0)
		for _i in range(120):
			yield(get_tree(), "physics_frame")
			if _pos().y > LEDGE_ANCHOR_Y + 0.2:
				mantled = true
				break
		Input.action_release("move_forward")
	if is_instance_valid(_pilot):
		_pilot.queue_free()
	_pilot = null
	nodes[0].queue_free()
	nodes[1].queue_free()
	yield(get_tree(), "idle_frame")
	return {"hang": hung, "mantle": mantled}


func _m_ledge_band() -> Dictionary:
	var min_off := -1.0
	var max_off := -1.0
	var max_mantle := -1.0
	var off := 0.30
	while off <= 2.6:
		var r: Dictionary = yield(_try_ledge_offset(off), "completed")
		if r.get("hang", false):
			if min_off < 0.0:
				min_off = off
			max_off = off
			if r.get("mantle", false):
				max_mantle = off
		off += 0.15
	return {"min_offset": min_off, "max_offset": max_off, "max_mantle_offset": max_mantle}


# ---------------------------------------------------------------------------
# Suite por tick
# ---------------------------------------------------------------------------

func _measure_tick(hz: int) -> Dictionary:
	_use_tick(hz)
	var out := {}
	yield(_spawn_pilot(), "completed")
	out["h_max"] = yield(_m_h_max(), "completed")
	yield(_respawn(), "completed")
	out["h_tap"] = yield(_m_h_tap(), "completed")
	yield(_respawn(), "completed")
	out["t_air"] = yield(_m_t_air(), "completed")
	yield(_respawn(), "completed")
	out["d_max_run"] = yield(_run_jump_distance(true), "completed")
	yield(_respawn(), "completed")
	out["d_max_walk"] = yield(_run_jump_distance(false), "completed")
	yield(_respawn(), "completed")
	out["start_distance"] = yield(_m_start_distance(), "completed")
	yield(_respawn(), "completed")
	out["stop_distance"] = yield(_m_stop_distance(), "completed")
	yield(_respawn(), "completed")
	var roll: Dictionary = yield(_m_roll_jump(), "completed")
	out["roll_jump_distance"] = roll.get("distance", -1.0)
	out["roll_speed"] = roll.get("roll_speed", -1.0)
	if is_instance_valid(_pilot):
		_pilot.queue_free()
	_pilot = null
	yield(get_tree(), "idle_frame")
	var band: Dictionary = yield(_m_ledge_band(), "completed")
	out["ledge_hang_min_offset"] = band.get("min_offset", -1.0)
	out["ledge_hang_max_offset"] = band.get("max_offset", -1.0)
	out["ledge_mantle_max_offset"] = band.get("max_mantle_offset", -1.0)
	var reach: float = -1.0
	if band.get("max_mantle_offset", -1.0) > 0.0:
		reach = out["h_max"] + band["max_mantle_offset"]
	out["ledge_mantle_max_height"] = reach
	return out


# ---------------------------------------------------------------------------
# Test principal
# ---------------------------------------------------------------------------

func test_flow_metrics_measure_and_match_doc() -> void:
	var measured := {}
	for hz in TICKS:
		var m: Dictionary = yield(_measure_tick(hz), "completed")
		measured[str(hz)] = m
		prints("[flow_metrics] tick", hz, m)

	_use_tick(60)
	yield(_spawn_pilot(), "completed")
	var fm = FlowMetricsScript.from_pilot_node(_pilot)
	prints("[flow_metrics] constants", fm.metrics())
	_write_json(measured, fm)

	var m60: Dictionary = measured["60"]
	assert_float(m60["h_max"]).is_between(2.0, 5.0)
	assert_float(m60["h_tap"]).is_between(1.0, 3.0)
	assert_float(m60["t_air"]).is_greater(1.0)
	assert_float(m60["roll_jump_distance"]).is_greater(m60["d_max_run"])
	assert_float(m60["ledge_mantle_max_height"]).is_greater(m60["h_max"])
	var m30: Dictionary = measured["30"]
	assert_float(abs(m30["h_max"] - m60["h_max"]) / m60["h_max"]).is_less(0.25)

	_verify_doc(measured, fm)


func _verify_doc(measured: Dictionary, fm) -> void:
	var f := File.new()
	if not f.file_exists(DOC_PATH):
		print("[flow_metrics] doc no existe todavia: ", DOC_PATH)
		return
	f.open(DOC_PATH, File.READ)
	var text := f.get_as_text()
	f.close()
	var doc := _extract_doc_metrics(text)
	if doc.empty():
		print("[flow_metrics] doc sin bloque de metricas legible")
		return
	var m60: Dictionary = measured["60"]
	for key in doc.keys():
		if key == "note":
			continue
		if not m60.has(key):
			continue
		var doc_val := float(doc[key])
		var got := float(m60[key])
		var tol: float = max(TOL_ABS, abs(doc_val) * TOL_REL)
		var diff := abs(got - doc_val)
		assert_float(diff).override_failure_message(
			"[flow_metrics] doc %s: doc=%.3f medido=%.3f (tol=%.3f)" % [key, doc_val, got, tol]
		).is_less_equal(tol)


func _extract_doc_metrics(text: String) -> Dictionary:
	var marker := "```json"
	var start := text.find(marker)
	while start != -1:
		var body_start := start + marker.length()
		var end := text.find("```", body_start)
		if end == -1:
			return {}
		var body := text.substr(body_start, end - body_start)
		var parsed = JSON.parse(body)
		if parsed.error == OK and typeof(parsed.result) == TYPE_DICTIONARY and parsed.result.has("flow_metrics"):
			var d = parsed.result["flow_metrics"]
			if typeof(d) == TYPE_DICTIONARY:
				return d
		start = text.find(marker, end + 3)
	return {}


func _write_json(measured: Dictionary, fm) -> void:
	var payload := {
		"schema": "odisea.flow_metrics.v1",
		"generated_by": "core_v2/tests/test_flow_metrics.gd",
		"constants": fm.metrics() if fm != null else {},
		"measured": measured
	}
	var f := File.new()
	if f.open(OUT_JSON, File.WRITE) == OK:
		f.store_string(JSON.print(payload, "  "))
		f.close()
	var rf := File.new()
	if rf.open("res://reports/flow_metrics.json", File.WRITE) == OK:
		rf.store_string(JSON.print(payload, "  "))
		rf.close()
