extends Reference

# Presupuesto de FLOW del Transit-Run aplicado al anillo radial (FD-322).
#
# El juego pasó a parkour cinético ("Transit-Run") y la bahía radial es su banco
# de pruebas. El contrato de métricas vive en `docs/canon/WFC_FLOW_METRICS.md`
# (src-59): alcances y umbrales MEDIDOS en el motor, en función de `g`, que en
# este anillo es CENTRÍFUGA e igual a `g(r) = ω² · r` (ω = giro del anillo,
# `GravityWorld.ship_angular_velocity_rad_s`).
#
# Este nodo NO hardcodea el nivel: expone el presupuesto (h_max, d_max, huecos de
# ruta principal vs. opcionales, escalón cómodo) y lo LEE del contrato cuando el
# doc aterriza. Sin doc, usa los fallbacks documentados abajo, que son los mismos
# números de referencia (g=14, v_jump=10, v_run=7 → h_max≈3.57 m, d_max≈10 m).
#
# Reglas del contrato que el nivel debe respetar:
#   - la ruta PRINCIPAL se calibra a `v_run` y nunca se bloquea con un puzle;
#   - los huecos principales quedan al 70-80 % del alcance (siempre saltables);
#   - los atajos curados son Side Sockets OPCIONALES (90-100 % del alcance);
#   - el roll-jump es técnica de habilidad, no requisito.

const CANON_PATH := "res://docs/canon/WFC_FLOW_METRICS.md"

# Fallbacks: valores de referencia del contrato hasta que el doc esté en el repo.
const FALLBACK_G := 14.0
const FALLBACK_V_JUMP := 10.0
const FALLBACK_V_RUN := 7.0
const FALLBACK_MAIN_FRACTION := 0.75
const FALLBACK_OPTIONAL_FRACTION := 0.95
# Fracción de h_max usada como escalón cómodo de una "RhythmSteps".
const STEP_FRACTION := 0.5
# Cada cuántos tramos aparece un SprintGap en la ruta principal (ritmo).
const SPRINT_GAP_EVERY := 5

# Etiquetas de chunk del contrato.
const LABEL_SPRINT_GAP := "SprintGap"
const LABEL_RHYTHM_STEPS := "RhythmSteps"
const LABEL_GLOO_CLIMB := "GlooClimb"
const LABEL_MAG_RAIL := "MagRail"
const LABEL_CURATED_SOCKET := "CuratedSocket"

var g := FALLBACK_G
var v_jump := FALLBACK_V_JUMP
var v_run := FALLBACK_V_RUN
var main_fraction := FALLBACK_MAIN_FRACTION
var optional_fraction := FALLBACK_OPTIONAL_FRACTION
# "fallback" | "canon" | "gravity_world"
var source := "fallback"

func _init() -> void:
	load_contract()

# Carga el contrato si está en el repo. Devuelve true si encontró el archivo y
# pudo leer al menos un valor.
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

# Parser tolerante: acepta `clave: valor`, `clave = valor` y filas de tabla
# `| clave | valor |`. Ignora el resto (prosa, encabezados, bloques de código).
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
			"main_fraction", "main fraction", "ruta_principal", "main_route_fraction":
				main_fraction = v
				found += 1
			"optional_fraction", "optional fraction", "opcional", "optional_route_fraction":
				optional_fraction = v
				found += 1
	return found > 0

# g del anillo en `radius`: g(r) = ω² r con el giro real de GravityWorld. Si el
# anillo no declara giro (>0), se conserva el g del contrato.
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

# ── Alcances derivados de g ──────────────────────────────────────────────────

# Altura máxima de salto: v_jump² / (2g).
func h_max() -> float:
	return (v_jump * v_jump) / (2.0 * max(g, 0.001))

# Alcance horizontal máximo a v_run en un salto (vuelo 2·v_jump/g).
func d_max() -> float:
	return v_run * (2.0 * v_jump / max(g, 0.001))

# Hueco de la RUTA PRINCIPAL (70-80 % del alcance): siempre saltable corriendo.
func main_route_gap() -> float:
	return main_fraction * d_max()

# Hueco de un Side Socket OPCIONAL (90-100 % del alcance).
func optional_gap() -> float:
	return optional_fraction * d_max()

# Caída que la ruta principal puede exigir sin matar (70-80 % de h_max).
func main_route_drop() -> float:
	return main_fraction * h_max()

# Escalón cómodo al correr (RhythmSteps).
func step_rise() -> float:
	return STEP_FRACTION * h_max()

# Etiquetas del contrato.
func labels() -> Array:
	return [LABEL_SPRINT_GAP, LABEL_RHYTHM_STEPS, LABEL_GLOO_CLIMB, LABEL_MAG_RAIL, LABEL_CURATED_SOCKET]

func describe() -> Dictionary:
	return {
		"source": source,
		"g": g,
		"v_jump": v_jump,
		"v_run": v_run,
		"h_max": h_max(),
		"d_max": d_max(),
		"main_route_gap": main_route_gap(),
		"optional_gap": optional_gap(),
		"step_rise": step_rise(),
	}

func _normalize_key(key: String) -> String:
	var k := key.strip_edges()
	# Quita marcadores de lista/negrita/backticks y numeración.
	for ch in ["-", "*", "•", "`", "#"]:
		while k.begins_with(ch):
			k = k.substr(1).strip_edges()
	k = k.replace("`", "").replace("**", "").strip_edges()
	k = k.to_lower()
	return k

func _to_float(text: String) -> float:
	var cleaned := text
	for ch in ["m/s²", "m/s", "m", "%", "*", " ", "\t"]:
		cleaned = cleaned.replace(ch, "")
	if cleaned.ends_with(","):
		cleaned = cleaned.substr(0, cleaned.length() - 1)
	return float(cleaned)
