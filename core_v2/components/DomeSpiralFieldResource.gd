extends Resource
class_name DomeSpiralFieldResource

# Configuración declarativa del campo de espirales del cilindro (FD-321, Fase 0 B).
# Cada espiral comparte los defaults de TerraceSpiral.gd pero con el eje del
# cilindro en Z y el origen en el centro de la nave (ver DomeSpiralField.gd).

const DEFAULT_TURNS := 8.0
const DEFAULT_TOTAL_HEIGHT := 8000.0
const DEFAULT_PLATE_STEP := 40.0
const DEFAULT_R_MIN := 220.0
const DEFAULT_R_MAX := 260.0
const DEFAULT_PHASE := 0.0

# Coherente con el CubeMesh real de TerraceSpiral.tscn: size = Vector3(200, 2, 200).
const DEFAULT_PLATE_SIZE := Vector3(200.0, 2.0, 200.0)

# Array de Dictionary con las claves: turns, total_height, plate_step,
# r_min, r_max, phase. Claves faltantes o inválidas se normalizan a defaults.
export(Array, Dictionary) var spirals: Array = []

export var plate_size: Vector3 = DEFAULT_PLATE_SIZE

static func default_spiral_config() -> Dictionary:
	return {
		"turns": DEFAULT_TURNS,
		"total_height": DEFAULT_TOTAL_HEIGHT,
		"plate_step": DEFAULT_PLATE_STEP,
		"r_min": DEFAULT_R_MIN,
		"r_max": DEFAULT_R_MAX,
		"phase": DEFAULT_PHASE
	}

# Devuelve una copia normalizada: sólo claves conocidas, siempre floats.
static func normalize_spiral_config(raw) -> Dictionary:
	var config: Dictionary = default_spiral_config()
	if typeof(raw) != TYPE_DICTIONARY:
		return config
	var source: Dictionary = raw
	for key in config.keys():
		if source.has(key):
			config[key] = float(source[key])
	return config

# Determinista: sin espirales declaradas devuelve una única espiral default.
func get_spiral_configs() -> Array:
	if spirals.empty():
		return [default_spiral_config()]
	var configs: Array = []
	for raw in spirals:
		configs.append(normalize_spiral_config(raw))
	return configs
