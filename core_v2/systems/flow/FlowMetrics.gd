extends Reference

# core_v2/systems/flow/FlowMetrics.gd
#
# Transit-Run / WFC — FUENTE UNICA de constantes y funciones de alcance del jugador.
#
# Por que existe: los niveles generados por WFC (laberinto de MachineBay via
# MachineBayLabyrinthStreamer y el anillo centrifugo de bay_vertical) se derivan de las
# constantes fisicas REALES del jugador. Definirlas en mas de un lugar garantiza que el
# generador y el test se desincronicen. Aca viven una sola vez y se LEEN de la escena
# canónica (Pilot_v2.tscn), nunca se hardcodean.
#
# Toda metrica de distancia/altura se expresa como funcion de g, porque en el anillo
# centrifugo la gravedad efectiva es g_eff = omega^2 * r, no 9.8 ni 14. La ruta principal
# se calibra contra el PEOR caso: el tick mas bajo (30 Hz, handheld) y el g efectivo mas
# bajo de la zona.
#
# Sin `class_name` a proposito (registrar una clase nueva obliga al editor a reescribir
# project.godot): consumir con preload.
#
# Contratos:
#   - `run_speed()` / `walk_speed()`: velocidad horizontal objetivo.
#   - `h_max(g)`, `h_tap(g)`, `t_air(g, dh)`, `d_max(g, v, dh)`: alcance continuo analitico.
#   - `main_gap_limit()`, `optional_gap_limit()`: umbrales de flow por defecto.
#   - `metrics()`: diccionario plano (lo consume FlowRouteValidator).
#
# Unidades: metros, segundos, m/s, m/s^2. g se toma positiva (magnitud).

const PILOT_SCENE_PATH := "res://core_v2/actors/Pilot_v2.tscn"

# --- Constantes fisicas (defaults del script; se sobreescriben al leer la escena) ---
var gravity := 14.0                 # magnitud de Jump.gravity
var jump_force := 10.0              # Jump.jump_force
var min_jump_intensity := 0.6       # Jump.min_jump_intensity (corte del salto variable)
var min_jump_time := 0.08           # Jump.MIN_JUMP_TIME (const del script)
var acrobatic_jump_force := 14.0    # Jump.acrobatic_jump_force
var coyote_time := 0.15             # Jump.COYOTE_TIME (const del script)
var jump_buffer_time := 0.15        # Jump.JUMP_BUFFER_TIME

var move_speed := 2.0               # Movement.move_speed (caminar)
var run_speed_multiplier := 3.5      # Movement.run_speed_multiplier
var acceleration := 30.0            # Movement.acceleration
var ground_friction := 30.0         # Movement.ground_friction
var air_friction := 5.0             # Movement.air_friction
var air_control_multiplier := 0.7    # Movement.air_control_multiplier

var roll_duration := 0.48           # Movement.landing_roll_duration
var roll_min_speed := 8.5           # Movement.landing_roll_min_speed
var roll_max_speed := 13.5          # Movement.landing_roll_max_speed
var roll_friction := 3.5            # Movement.landing_roll_friction
var roll_min_fall_vy := -6.0        # Movement.landing_roll_min_fall_vy
var roll_vertical_conversion := 0.45 # Movement.landing_roll_vertical_conversion

# Cornisa (TraversalLogicV2)
var hang_min_height := 0.75         # ledge_auto_hang_min_height
var hang_max_height := 1.6          # ledge_auto_hang_max_height
var hang_min_height_ratio := 0.42   # ledge_auto_hang_min_height_ratio
var hang_max_height_ratio := 0.9    # ledge_auto_hang_max_height_ratio
var hang_band_padding := 0.2        # ledge_auto_hang_band_padding
var mantle_up_offset := 0.95        # mantle_up_offset
var capsule_height := 1.0           # CapsuleShape.height (parte cilindrica)
var capsule_radius := 0.5           # CapsuleShape.radius

# Tick de simulacion (afecta la discretizacion, no la fisica continua).
var tick_hz := 60.0

# Valores medidos en el motor (los llena el test; el generador solo necesita los analiticos).
var _measured := {}

# ---------------------------------------------------------------------------
# Carga desde la escena canónica
# ---------------------------------------------------------------------------

static func from_pilot_node(pilot: Node) -> Reference:
	var fm = load("res://core_v2/systems/flow/FlowMetrics.gd").new()
	fm._read_from(pilot)
	return fm

static func from_scene(path: String = PILOT_SCENE_PATH) -> Reference:
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("[FlowMetrics] no se pudo cargar la escena: %s" % path)
		return null
	var pilot: Node = packed.instance()
	var fm = load("res://core_v2/systems/flow/FlowMetrics.gd").new()
	fm._read_from(pilot)
	pilot.free()
	return fm

func _read_from(pilot: Node) -> void:
	var jump: Node = pilot.get_node_or_null("Logic/Jump")
	if jump != null:
		gravity = abs(float(jump.get("gravity")))
		jump_force = float(jump.get("jump_force"))
		min_jump_intensity = float(jump.get("min_jump_intensity"))
		acrobatic_jump_force = float(jump.get("acrobatic_jump_force"))
		jump_buffer_time = float(jump.get("JUMP_BUFFER_TIME"))
		var js = jump.get_script()
		if js != null:
			if "MIN_JUMP_TIME" in js:
				min_jump_time = float(js.MIN_JUMP_TIME)
			if "COYOTE_TIME" in js:
				coyote_time = float(js.COYOTE_TIME)
	var move: Node = pilot.get_node_or_null("Logic/Movement")
	if move != null:
		move_speed = float(move.get("move_speed"))
		run_speed_multiplier = float(move.get("run_speed_multiplier"))
		acceleration = float(move.get("acceleration"))
		ground_friction = float(move.get("ground_friction"))
		air_friction = float(move.get("air_friction"))
		air_control_multiplier = float(move.get("air_control_multiplier"))
		roll_duration = float(move.get("landing_roll_duration"))
		roll_min_speed = float(move.get("landing_roll_min_speed"))
		roll_max_speed = float(move.get("landing_roll_max_speed"))
		roll_friction = float(move.get("landing_roll_friction"))
		roll_min_fall_vy = float(move.get("landing_roll_min_fall_vy"))
		roll_vertical_conversion = float(move.get("landing_roll_vertical_conversion"))
	var traversal: Node = pilot.get_node_or_null("Logic/Traversal")
	if traversal != null:
		hang_min_height = float(traversal.get("ledge_auto_hang_min_height"))
		hang_max_height = float(traversal.get("ledge_auto_hang_max_height"))
		hang_min_height_ratio = float(traversal.get("ledge_auto_hang_min_height_ratio"))
		hang_max_height_ratio = float(traversal.get("ledge_auto_hang_max_height_ratio"))
		hang_band_padding = float(traversal.get("ledge_auto_hang_band_padding"))
		mantle_up_offset = float(traversal.get("mantle_up_offset"))
	var capsule: Node = pilot.get_node_or_null("CollisionShape")
	if capsule != null and capsule is CollisionShape and capsule.shape is CapsuleShape:
		capsule_height = float(capsule.shape.height)
		capsule_radius = float(capsule.shape.radius)

# ---------------------------------------------------------------------------
# Velocidades objetivo
# ---------------------------------------------------------------------------

func run_speed() -> float:
	return move_speed * run_speed_multiplier

func walk_speed() -> float:
	return move_speed

# ---------------------------------------------------------------------------
# Analiticos de alcance (continuos; g en magnitud, positiva)
# ---------------------------------------------------------------------------

func _g(g_override: float) -> float:
	return gravity if g_override <= 0.0 else g_override

# Altura maxima de un salto completo (manteniendo el boton).
func h_max(g_override: float = -1.0) -> float:
	return (jump_force * jump_force) / (2.0 * _g(g_override))

# Altura maxima de un "tap" (soltar tras MIN_JUMP_TIME, corte a min_jump_intensity * jump_force).
func h_tap(g_override: float = -1.0) -> float:
	var g := _g(g_override)
	var tau := min_jump_time
	var v_at_cut := jump_force - g * tau
	var h_rise := 0.5 * (jump_force + v_at_cut) * tau
	var v_cut := jump_force * min_jump_intensity
	return h_rise + (v_cut * v_cut) / (2.0 * g)

# Tiempo en el aire de un salto con velocidad vertical inicial v0 que aterriza dh arriba (dh>0)
# o abajo (dh<0) del punto de despegue.
func t_air_v0(v0: float, g_override: float = -1.0, dh: float = 0.0) -> float:
	var g := _g(g_override)
	var disc := v0 * v0 - 2.0 * g * dh
	if disc < 0.0:
		return 0.0
	return (v0 + sqrt(disc)) / g

func t_air(g_override: float = -1.0, dh: float = 0.0) -> float:
	return t_air_v0(jump_force, g_override, dh)

# Alcance horizontal de un salto con velocidad horizontal v constante durante t_air.
func d_max_v(v: float, g_override: float = -1.0, dh: float = 0.0) -> float:
	return v * t_air(g_override, dh)

func d_max(g_override: float = -1.0, dh: float = 0.0) -> float:
	return d_max_v(run_speed(), g_override, dh)

# Distancia de arranque (0 -> v) y de frenado (v -> 0) por aceleracion/friccion constante.
func start_distance(v: float = -1.0) -> float:
	var vv := run_speed() if v < 0.0 else v
	return (vv * vv) / (2.0 * acceleration)

func stop_distance(v: float = -1.0) -> float:
	var vv := run_speed() if v < 0.0 else v
	return (vv * vv) / (2.0 * ground_friction)

# --- Cornisa ---
func capsule_total_height() -> float:
	return capsule_height + capsule_radius * 2.0

func hang_min_grab() -> float:
	return max(hang_min_height, capsule_total_height() * hang_min_height_ratio)

func hang_max_grab() -> float:
	return max(
		hang_min_grab() + hang_band_padding,
		min(hang_max_height, capsule_total_height() * hang_max_height_ratio)
	)

# ---------------------------------------------------------------------------
# Umbrales de flow (fraccion del alcance maximo)
# ---------------------------------------------------------------------------

# Ruta principal: nunca exige mas del 80% del alcance (banda 70-80%).
const MAIN_MIN_RATIO := 0.70
const MAIN_MAX_RATIO := 0.80
# Desvios opcionales de habilidad: 90-100% del alcance.
const OPTIONAL_MIN_RATIO := 0.90
const OPTIONAL_MAX_RATIO := 1.00

func main_gap_limit(g_override: float = -1.0, dh: float = 0.0) -> float:
	return d_max(g_override, dh) * MAIN_MAX_RATIO

func optional_gap_limit(g_override: float = -1.0, dh: float = 0.0) -> float:
	return d_max(g_override, dh) * OPTIONAL_MAX_RATIO

func flow_thresholds() -> Dictionary:
	return {
		"main_min_ratio": MAIN_MIN_RATIO,
		"main_max_ratio": MAIN_MAX_RATIO,
		"optional_min_ratio": OPTIONAL_MIN_RATIO,
		"optional_max_ratio": OPTIONAL_MAX_RATIO,
		"main_gap_limit": main_gap_limit(),
		"optional_gap_limit": optional_gap_limit(),
		"requires_tool_beyond": optional_gap_limit()
	}

# ---------------------------------------------------------------------------
# Diccionario de metricas (lo consume FlowRouteValidator)
# ---------------------------------------------------------------------------

func set_tick(hz: float) -> void:
	tick_hz = hz

func set_measured(m: Dictionary) -> void:
	_measured = m

func measured() -> Dictionary:
	return _measured

func metrics() -> Dictionary:
	var d := {
		"tick_hz": tick_hz,
		"gravity": gravity,
		"jump_force": jump_force,
		"jump_cut_velocity": jump_force * min_jump_intensity,
		"min_jump_time": min_jump_time,
		"min_jump_intensity": min_jump_intensity,
		"acrobatic_jump_force": acrobatic_jump_force,
		"coyote_time": coyote_time,
		"jump_buffer_time": jump_buffer_time,
		"move_speed": move_speed,
		"run_speed_multiplier": run_speed_multiplier,
		"run_speed": run_speed(),
		"walk_speed": walk_speed(),
		"acceleration": acceleration,
		"ground_friction": ground_friction,
		"air_friction": air_friction,
		"air_control_multiplier": air_control_multiplier,
		"roll_min_speed": roll_min_speed,
		"roll_max_speed": roll_max_speed,
		"roll_duration": roll_duration,
		"h_max": h_max(),
		"h_tap": h_tap(),
		"t_air": t_air(),
		"d_max_run": d_max(),
		"d_max_walk": d_max_v(walk_speed()),
		"start_distance": start_distance(),
		"stop_distance": stop_distance(),
		"hang_min_grab": hang_min_grab(),
		"hang_max_grab": hang_max_grab(),
		"ledge_mantle_max_height": h_max() + hang_max_grab()
	}
	for t in flow_thresholds():
		d["thr_" + t] = flow_thresholds()[t]
	d["measured"] = _measured
	return d
