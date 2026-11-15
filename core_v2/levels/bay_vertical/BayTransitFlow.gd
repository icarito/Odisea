extends Reference

# Presupuesto de FLOW del Transit-Run aplicado al anillo radial (FD-322).
#
# El juego pasó a parkour cinético ("Transit-Run") y la bahía radial es su banco
# de pruebas. Las MÉTRICAS no se duplican acá: se delegan al validador puro y
# determinista `core_v2/systems/flow/FlowRouteValidator.gd` (#422), que modela
# `h_max` y `d_max` con corrección por tick y los umbrales main/opcional.
#
# Este nodo aporta lo que el validador no sabe: el `g` del anillo, que es
# CENTRÍFUGO e igual a `g(r) = ω² · r` (ω = `GravityWorld.ship_angular_velocity_rad_s`),
# y el parser del contrato `docs/canon/WFC_FLOW_METRICS.md` (src-59) cuando el
# doc aterrice. Sin doc usa los fallbacks documentados, que son los valores
# medidos en el motor (H_max ≈ 3.66 m a 60 Hz, D_max corriendo ≈ 10.0 m,
# escalón ≤ 2.9 m sin cornisa, umbral main ≤ 80 %).
#
# Reglas del contrato que el nivel respeta:
#   - la ruta PRINCIPAL se calibra a `v_run` y nunca se bloquea con un puzle;
#   - huecos principales al 70-80 % del alcance (siempre saltables al mismo nivel);
#   - los atajos curados son Side Sockets OPCIONALES (90-100 % del alcance);
#   - el roll-jump es técnica de habilidad, no requisito.

const ValidatorScript := preload("res://core_v2/systems/flow/FlowRouteValidator.gd")

const CANON_PATH := "res://docs/canon/WFC_FLOW_METRICS.md"

# Fallbacks: valores medidos en el motor (docs/canon/WFC_FLOW_METRICS.md, src-59).
const FALLBACK_G := 14.0
const FALLBACK_V_JUMP := 10.0
const FALLBACK_V_RUN := 7.0
const FALLBACK_TICK := 1.0 / 60.0
const FALLBACK_MAIN_THRESHOLD := 0.80
const FALLBACK_OPTIONAL_MIN := 0.90
const FALLBACK_OPTIONAL_MAX := 1.00
# Fracción usada para DIMENSIONAR (dentro de la banda 70-80 % del contrato), con
# margen respecto del umbral de 80 % que evalúa el validador.
const FALLBACK_MAIN_SIZING := 0.75
# Escalón cómodo al correr: min(0.5·h_max, step_limit) y el límite medido.
const FALLBACK_STEP_LIMIT := 2.9
const STEP_FRACTION := 0.5

var g := FALLBACK_G
var v_jump := FALLBACK_V_JUMP
var v_run := FALLBACK_V_RUN
var tick := FALLBACK_TICK
var main_threshold := FALLBACK_MAIN_THRESHOLD
var optional_min := FALLBACK_OPTIONAL_MIN
var optional_max := FALLBACK_OPTIONAL_MAX
var main_sizing := FALLBACK_MAIN_SIZING
var step_limit := FALLBACK_STEP_LIMIT
# "fallback" | "canon" | "gravity_world"
var source := "fallback"

func _init() -> void:
	load_contract()

func load_contract(path: String = CANON_PATH) -> bool:
	var f := File.new()
	if not f.file_exists(path):
		source = "fallback"
		return false
	if f.open(path, File.READ) != OK:
		source = "fallback"
		return false
	var text := f.get_as_text()
	f.close()
	var ok := parse_contract(text)
	if ok:
		source = "canon"
	return ok

# Parser tolerante: acepta `clave: valor`, `clave = valor` y filas de tabla.
func parse_contract(text: String) -> bool:
	var found := 0
	for raw_line in text.split("\n"):
		var line := String(raw_line).strip_edges()
		if line.empty() or line.begins_with("#"):
			continue
		var key := ""
		var value := ""
		if line.begins_with("|"):
			var cells := line.split("|")
			if cells.size() >= 3:
				key = String(cells[1]).strip_edges()
				value = String(cells[2]).strip_edges()
		elif line.find(":") >= 0:
			var parts := line.split(":", true, 1)
			key = String(parts[0]).strip_edges()
			value = String(parts[1]).strip_edges()
		elif line.find("=") >= 0:
			var parts2 := line.split("=", true, 1)
			key = String(parts2[0]).strip_edges()
			value = String(parts2[1]).strip_edges()
		if key.empty():
			continue
		# Sólo se asigna con un valor NUMÉRICO. La tabla del contrato pone el
		# SÍMBOLO en la columna de valor (`| Gravedad | `g` | 14.0 m/s² |`), y sin
		# este guard el parser pisaba `g` con 0.0, dejando `d_max = -1` y el
		# límite de ruta principal en negativo.
		if not _is_numeric(value):
			continue
		var k := _normalize_key(key)
		var v := _to_float(value)
		match k:
			"g", "gravedad", "gravity":
				g = v
				found += 1
			"v_jump", "v jump", "v_salto", "jump_speed", "velocidad de salto":
				v_jump = v
				found += 1
			"v_run", "v run", "v_correr", "run_speed", "velocidad de carrera":
				v_run = v
				found += 1
			"tick", "dt":
				tick = v
				found += 1
			"main_threshold", "main threshold", "umbral_principal":
				main_threshold = v
				found += 1
			"main_sizing", "main fraction", "main_fraction", "ruta_principal":
				main_sizing = v
				found += 1
			"optional_min", "optional min":
				optional_min = v
				found += 1
			"optional_max", "optional max", "opcional":
				optional_max = v
				found += 1
			"step_limit", "escalon", "escalón", "step":
				step_limit = v
				found += 1
	return found > 0

# g del anillo en `radius`: g(r) = ω² r con el giro real del barco.
func configure_gravity_from_world(world: Node, radius: float) -> bool:
	if world == null or not ("ship_angular_velocity_rad_s" in world):
		return false
	var omega: float = float(world.ship_angular_velocity_rad_s)
	if omega <= 0.0 or radius <= 0.0:
		return false
	g = omega * omega * radius
	if source == "fallback":
		source = "gravity_world"
	return true

# ── Métricas (delegadas al validador puro) ───────────────────────────────────

# Diccionario de métricas del contrato, para `FlowRouteValidator.validate()`.
func metrics() -> Dictionary:
	var m := ValidatorScript.default_metrics()
	m["g"] = g
	m["v_jump"] = v_jump
	m["v_run"] = v_run
	m["tick"] = tick
	m["main_threshold"] = main_threshold
	m["optional_min"] = optional_min
	m["optional_max"] = optional_max
	return m

func h_max() -> float:
	return ValidatorScript.compute_h_max(v_jump, g, tick)

func d_max(delta_h: float = 0.0) -> float:
	return ValidatorScript.compute_d_max(v_run, v_jump, g, delta_h, tick)

# Hueco de la RUTA PRINCIPAL al mismo nivel (delta_h = 0): siempre saltable.
func main_route_gap() -> float:
	return main_sizing * d_max(0.0)

# Hueco de un Side Socket OPCIONAL (banda 90-100 %).
func optional_gap() -> float:
	return optional_max * d_max(0.0)

# Escalón cómodo al correr.
func step_rise() -> float:
	return min(STEP_FRACTION * h_max(), step_limit)

func labels() -> Array:
	return [ValidatorScript.TAG_SPRINT_GAP, ValidatorScript.TAG_RHYTHM_STEPS,
		ValidatorScript.TAG_GLOO_CLIMB, ValidatorScript.TAG_MAG_RAIL,
		ValidatorScript.TAG_CURATED_SOCKET]

func describe() -> Dictionary:
	return {
		"source": source,
		"g": g,
		"v_jump": v_jump,
		"v_run": v_run,
		"tick": tick,
		"h_max": h_max(),
		"d_max": d_max(0.0),
		"main_route_gap": main_route_gap(),
		"optional_gap": optional_gap(),
		"step_rise": step_rise(),
		"main_threshold": main_threshold,
	}

func _normalize_key(key: String) -> String:
	var k := key.strip_edges()
	for ch in ["-", "*", "•", "`", "#"]:
		while k.begins_with(ch):
			k = k.substr(1).strip_edges()
	k = k.replace("`", "").replace("**", "").strip_edges()
	return k.to_lower()

func _strip_units(text: String) -> String:
	var cleaned := text
	for ch in ["m/s²", "m/s", "m", "%", "*", " ", "\t", ","]:
		cleaned = cleaned.replace(ch, "")
	return cleaned.strip_edges()

# ¿El valor de la celda es un número (con unidades opcionales)?
func _is_numeric(text: String) -> bool:
	var cleaned := _strip_units(text)
	if cleaned == "":
		return false
	return cleaned.is_valid_float() or cleaned.is_valid_integer()

func _to_float(text: String) -> float:
	return float(_strip_units(text))
