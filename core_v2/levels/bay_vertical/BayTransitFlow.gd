extends Reference

# Presupuesto de FLOW del Transit-Run para el anillo centrífugo (FD-322 / pista E).
#
# Fuente ÚNICA de física: `core_v2/systems/flow/FlowMetrics.gd` (#423), que lee las
# constantes REALES del jugador de `Pilot_v2.tscn`. Fuente única de validación:
# `core_v2/systems/flow/FlowRouteValidator.gd` (#422). Acá solo se aporta lo que
# ninguno de los dos sabe: el `g` del anillo, que es CENTRÍFUGO e igual a
#
#     g_eff(r) = ω² · r          (ω = GravityWorld.ship_angular_velocity_rad_s)
#
# y los tamaños derivados por radio (huecos y escalones del contrato
# `docs/canon/WFC_FLOW_METRICS.md` §4-§6).
#
# INV-4 del contrato: todo se evalúa con el TICK MÁS BAJO soportado (peor caso,
# 30 Hz handheld) y con el `g_eff` LOCAL del tramo. Los tamaños se calculan con
# las mismas funciones del validador, así dimensionar y validar no divergen.

const FlowMetricsScript := preload("res://core_v2/systems/flow/FlowMetrics.gd")
const ValidatorScript := preload("res://core_v2/systems/flow/FlowRouteValidator.gd")

# Tick más bajo soportado (handheld Anbernic): peor caso del contrato.
const LOWEST_TICK_HZ := 30.0

# Se dimensiona por debajo del techo del contrato (80 %) para dejar margen.
const MAIN_SIZING_RATIO := 0.75
# RhythmSteps: `step_gap ≤ 0.55·D(0)` y `rise ≤ 0.80·H_max` (§5). Se usa menos.
const RHYTHM_GAP_RATIO := 0.52
const RHYTHM_RISE_RATIO := 0.70

var fm = null                      # instancia de FlowMetrics (lee Pilot_v2)
var ring_omega := 0.0
var ring_reference_radius := 48.0
var source := "flow_metrics"

func _init() -> void:
	fm = FlowMetricsScript.from_scene()
	if fm == null:
		fm = FlowMetricsScript.new()
		source = "defaults"

# ω del anillo (giro del barco). Sin giro se cae al g del piloto.
func configure_ring(omega: float, reference_radius: float) -> void:
	ring_omega = max(omega, 0.0)
	ring_reference_radius = max(reference_radius, 0.001)

# g efectiva a radio `r` (distancia al eje).
func g_eff(radius: float) -> float:
	var r: float = max(radius, 0.001)
	if ring_omega > 0.0:
		return ring_omega * ring_omega * r
	return fm.gravity

# Radio del punto a `radial_height` sobre la superficie del anillo.
func radius_at(radial_height: float) -> float:
	return max(0.5, ring_reference_radius - radial_height)

# ── Alcance por radio (mismas funciones que el validador) ────────────────────

func v_run() -> float:
	return fm.run_speed()

func h_max(radius: float) -> float:
	return ValidatorScript.compute_h_max(fm.jump_force, g_eff(radius), 1.0 / LOWEST_TICK_HZ)

func d_max(radius: float, dh: float = 0.0) -> float:
	return ValidatorScript.compute_d_max(fm.run_speed(), fm.jump_force, g_eff(radius), dh, 1.0 / LOWEST_TICK_HZ)

# Hueco de la ruta principal a `dh` local (dentro de la banda 70-80 %).
func main_gap(radius: float, dh: float = 0.0) -> float:
	return MAIN_SIZING_RATIO * d_max(radius, dh)

# Hueco de un desvío opcional (banda 90-100 %).
func optional_gap(radius: float, dh: float = 0.0) -> float:
	return 0.97 * d_max(radius, dh)

# RhythmSteps: escalón cómodo y paso corto de cadencia.
func rhythm_rise(radius: float) -> float:
	return RHYTHM_RISE_RATIO * h_max(radius)

func rhythm_gap(radius: float, rise: float) -> float:
	return min(RHYTHM_GAP_RATIO * d_max(radius, 0.0), MAIN_SIZING_RATIO * d_max(radius, rise))

# Cornisa: borde máximo alcanzable con mantle (§2).
func ledge_mantle_max_height(radius: float) -> float:
	return h_max(radius) + fm.hang_max_grab()

# ── Métricas para FlowRouteValidator ─────────────────────────────────────────

func metrics_for_g(g_value: float) -> Dictionary:
	var m := ValidatorScript.default_metrics()
	m["g"] = g_value
	m["v_run"] = fm.run_speed()
	m["v_jump"] = fm.jump_force
	m["tick"] = 1.0 / LOWEST_TICK_HZ
	m["main_threshold"] = FlowMetricsScript.MAIN_MAX_RATIO if "MAIN_MAX_RATIO" in FlowMetricsScript else 0.80
	m["optional_min"] = 0.90
	m["optional_max"] = 1.00
	return m

func describe() -> Dictionary:
	var r0: float = ring_reference_radius
	return {
		"source": source,
		"ring_omega": ring_omega,
		"ring_reference_radius": ring_reference_radius,
		"g_eff_surface": g_eff(r0),
		"v_run": v_run(),
		"v_jump": fm.jump_force,
		"tick_hz": LOWEST_TICK_HZ,
		"h_max_surface": h_max(r0),
		"d_max_surface": d_max(r0, 0.0),
		"main_gap_surface": main_gap(r0, 0.0),
	}
