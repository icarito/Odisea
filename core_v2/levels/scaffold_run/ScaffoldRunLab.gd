extends Spatial

# Escena de prueba de Transit-Run: arma un tramo de chunks de andamio por semilla
# (ScaffoldChunkRegistry) con las escenas horneadas y suelta al piloto al inicio. Con
# `autopilot_enabled`, tras 0.5 s sin tocar los controles el modo asistido recorre la ruta
# principal; cualquier input lo interrumpe.
#
#   tools/launch_game.sh --scene res://core_v2/levels/scaffold_run/ScaffoldRunLab.tscn
#
# Capturas (requiere display): SCAFFOLD_LAB_SHOTS=1 guarda test_output/scaffold_run/*.png
# desde la camara del jugador mientras el modo asistido corre, y cierra.

const Registry := preload("res://core_v2/systems/scaffold/ScaffoldChunkRegistry.gd")
const AutopilotScript := preload("res://core_v2/input/AutopilotInputV2.gd")
const FlowMetricsScript := preload("res://core_v2/systems/flow/FlowMetrics.gd")
const Validator := preload("res://core_v2/systems/flow/FlowRouteValidator.gd")
const OrbitScript := preload("res://core_v2/systems/scaffold/ScaffoldChunkOrbit.gd")
const PILOT_SCENE := preload("res://core_v2/actors/Pilot_v2.tscn")
const CHUNK_DIR := "res://core_v2/props/scaffold/chunks/"
const SHOT_DIR := "res://test_output/scaffold_run/"
const SHOT_SIZE := Vector2(960.0, 540.0)
const SHOT_EVERY_TICKS := 200
const SPAWN := Vector3(0.0, 0.1, 1.0)
const FALL_LIMIT := 25.0

export(int) var seed_value := 1018
export(int, 3, 64) var chunk_count := 12
export(bool) var autopilot_enabled := true
# 0 = tramo plano. > 0 = proyectado sobre el interior de un cilindro de ese radio (m).
export(float) var orbit_radius := 0.0

var _pilot: KinematicBody = null
var _orbit = null
var _autopilot = null
var _route := []
var _lowest := 0.0
var _ticks := 0
var _shots := 0
var _capturing := false


func _ready() -> void:
	if OS.get_environment("SCAFFOLD_LAB_RADIUS") != "":
		orbit_radius = float(OS.get_environment("SCAFFOLD_LAB_RADIUS"))
	_capturing = OS.get_environment("SCAFFOLD_LAB_SHOTS") != "" and get_tree().current_scene == self
	if _capturing:
		get_viewport().set_size_override(true, SHOT_SIZE)
		OS.window_size = SHOT_SIZE
		Directory.new().make_dir_recursive(ProjectSettings.globalize_path(SHOT_DIR))
	_build_stage()
	_build_stretch()
	_pilot = PILOT_SCENE.instance()
	_pilot.name = "Pilot"
	_pilot.translation = SPAWN
	add_child(_pilot)
	if _orbit != null:
		_orbit.set_player(_pilot)
	call_deferred("_arm_autopilot")


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.13, 0.18)
	env.ambient_light_color = Color(0.75, 0.82, 0.92)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_color = Color(0.10, 0.13, 0.18)
	env.fog_depth_begin = 60.0
	env.fog_depth_end = 220.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# Sol de tres cuartos + relleno desde el lado opuesto, para leer el volumen del andamio.
	for cfg in [[Vector3(-50.0, 150.0, 0.0), 1.0], [Vector3(-25.0, -40.0, 0.0), 0.35]]:
		var light := DirectionalLight.new()
		light.rotation_degrees = cfg[0]
		light.light_energy = cfg[1]
		add_child(light)


func _build_stretch() -> void:
	var fm = FlowMetricsScript.from_scene()
	var m := {"g": fm.gravity, "v_run": fm.run_speed(), "v_jump": fm.jump_force, "tick": 1.0 / 60.0}
	var graph: Dictionary = Registry.generate(seed_value, chunk_count, m)
	if orbit_radius > 0.0:
		_orbit = OrbitScript.new()
		_orbit.name = "Orbit"
		_orbit.base_radius = orbit_radius
		add_child(_orbit)
	for p in graph["placements"]:
		var chunk: Spatial = load(CHUNK_DIR + str(p["id"]) + ".tscn").instance()
		chunk.name = "Chunk_%02d_%s" % [int(p["index"]), str(p["id"])]
		if _orbit != null:
			_orbit.add_chunk(chunk, p["origin"])
		else:
			chunk.translation = p["origin"]
			add_child(chunk)
	var by_id := {}
	for n in graph["nodes"]:
		by_id[n["id"]] = n
		_lowest = min(_lowest, n["position"].y)
	_route = []
	for wp in Validator.extract_main_waypoints(graph, m):
		_route.append(by_id[wp["id"]])


func _arm_autopilot() -> void:
	_autopilot = AutopilotScript.new()
	_autopilot.setup(_pilot)
	_autopilot.set_route(_route)
	_autopilot.frame = _orbit
	_autopilot.enabled = autopilot_enabled
	_pilot.input_provider.autopilot = _autopilot


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_pilot) or _autopilot == null:
		return
	# Caida al vacio: vuelve al inicio con la ruta rearmada (escena de prueba, sin KillZone).
	if _pilot.global_transform.origin.y < _lowest - FALL_LIMIT:
		_pilot.global_transform.origin = global_transform.xform(SPAWN)
		_pilot.velocity = Vector3.ZERO
		_pilot.movement_logic.horizontal_velocity = Vector3.ZERO
		_pilot.jump_logic.internal_velocity = 0.0
		_autopilot.set_route(_route)
	_ticks += 1
	if OS.get_environment("SCAFFOLD_LAB_TRACE") != "" and _ticks % 6 == 0:
		prints("[lab]", _ticks, _pilot.global_transform.origin, _pilot.is_on_floor(), _pilot.velocity,
			_autopilot.next_waypoint(), _pilot.input_provider.last_input.jump, _pilot.input_provider.last_input.move_vec)
	if not _capturing:
		return
	if _ticks % SHOT_EVERY_TICKS == 0:
		var img: Image = get_viewport().get_texture().get_data()
		img.flip_y()
		img.save_png(ProjectSettings.globalize_path(SHOT_DIR + "run_%02d.png" % _shots))
		_shots += 1
		if _autopilot.is_finished() or _shots >= 14:
			print("[scaffold_lab] %d capturas, terminado=%s" % [_shots, str(_autopilot.is_finished())])
			get_tree().quit()
