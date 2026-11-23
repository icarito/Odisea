extends Reference

# FD-324 F3 — catálogo de chunks industriales provisionales del Ark-Run.
#
# Sin class_name: se consume con preload() (mismo criterio que ScaffoldChunkRegistry).
# Datos puros, sin escena: cada chunk es un conjunto de piezas low-poly en su marco
# local (x radial, y tangencial, z axial) con conectores explícitos. El generador
# ensambla racimos casando conectores; el streamer dibuja las piezas provisionales.
#
# Tabla de reemplazo: MESH_REPLACEMENTS permite que el kit final de Blender sustituya
# cada pieza (mesh o escena) sin tocar la lógica de ensamblado ni los conectores.

const ScaffoldChunkRegistry = preload("res://core_v2/systems/scaffold/ScaffoldChunkRegistry.gd")

const GRAVITY_CENTRIFUGAL := "CENTRIFUGAL"
const GRAVITY_AXIAL := "AXIAL"
const GRAVITY_BOTH := "BOTH"
const ALL_GRAVITY_MODES := [GRAVITY_CENTRIFUGAL, GRAVITY_AXIAL, GRAVITY_BOTH]

# Métricas reusadas del catálogo de andamios (sin modificarlo). Los literales de
# abajo espejan estos valores; los helpers los exponen en runtime.
const CHUNK_LENGTH := ScaffoldChunkRegistry.CHUNK_LENGTH
const WALKWAY_WIDTH := ScaffoldChunkRegistry.WALKWAY_WIDTH
const RAIL_HEIGHT := ScaffoldChunkRegistry.RAIL_HEIGHT

# Clave provisional -> override del kit final de Blender. Vacío = primitiva low-poly.
const MESH_REPLACEMENTS := {
	"frame": {"scene": "", "mesh": ""},
	"deck": {"scene": "", "mesh": ""},
	"machine": {"scene": "", "mesh": ""},
	"pipe": {"scene": "", "mesh": ""},
	"rail": {"scene": "", "mesh": ""},
	"girder": {"scene": "", "mesh": ""},
}

const VISUALS := {
	"frame": {"mesh": "box", "color": Color(0.18, 0.52, 0.58)},
	"deck": {"mesh": "box", "color": Color(0.10, 0.32, 0.36)},
	"machine": {"mesh": "box", "color": Color(0.58, 0.34, 0.12)},
	"pipe": {"mesh": "box", "color": Color(0.24, 0.62, 0.66)},
	"rail": {"mesh": "box", "color": Color(0.42, 0.78, 0.82)},
	"girder": {"mesh": "box", "color": Color(0.22, 0.28, 0.32)},
}

# [id] -> {family, size, pieces[], connectors[]}. Las piezas usan pos/size locales.
const CHUNKS := {
	"industry_gantry": {
		"family": "scaffold",
		"size": Vector3(WALKWAY_WIDTH, 3.2, CHUNK_LENGTH),
		"pieces": [
			{"key": "deck", "visual": "deck", "pos": Vector3(0, 0, 0), "size": Vector3(WALKWAY_WIDTH, 0.3, CHUNK_LENGTH)},
			{"key": "post_a", "visual": "frame", "pos": Vector3(-1.05, 1.5, -5.4), "size": Vector3(0.18, 3.0, 0.18)},
			{"key": "post_b", "visual": "frame", "pos": Vector3(1.05, 1.5, -5.4), "size": Vector3(0.18, 3.0, 0.18)},
			{"key": "post_c", "visual": "frame", "pos": Vector3(-1.05, 1.5, 5.4), "size": Vector3(0.18, 3.0, 0.18)},
			{"key": "post_d", "visual": "frame", "pos": Vector3(1.05, 1.5, 5.4), "size": Vector3(0.18, 3.0, 0.18)},
			{"key": "rail_l", "visual": "rail", "pos": Vector3(-1.2, 2.4, 0), "size": Vector3(0.12, 0.12, CHUNK_LENGTH)},
			{"key": "rail_r", "visual": "rail", "pos": Vector3(1.2, 2.4, 0), "size": Vector3(0.12, 0.12, CHUNK_LENGTH)},
		],
		"connectors": [
			{"id": "in", "local_pos": Vector3(0, 0, -6), "local_dir": Vector3(0, 0, -1), "gravity_modes": [GRAVITY_BOTH]},
			{"id": "out", "local_pos": Vector3(0, 0, 6), "local_dir": Vector3(0, 0, 1), "gravity_modes": [GRAVITY_BOTH]},
			{"id": "side", "local_pos": Vector3(1.25, 0, 0), "local_dir": Vector3(1, 0, 0), "gravity_modes": [GRAVITY_CENTRIFUGAL]},
		],
	},
	"industry_machine": {
		"family": "machinery",
		"size": Vector3(6.4, 6.4, 6.4),
		"pieces": [
			{"key": "body", "visual": "machine", "pos": Vector3(0, 0, 0), "size": Vector3(5.0, 5.0, 5.0)},
			{"key": "pipe_a", "visual": "pipe", "pos": Vector3(0, 0, 0), "size": Vector3(5.4, 0.8, 0.8)},
			{"key": "girder_top", "visual": "girder", "pos": Vector3(0, 2.9, 0), "size": Vector3(5.4, 0.3, 5.4)},
		],
		"connectors": [
			{"id": "in", "local_pos": Vector3(-3.2, 0, 0), "local_dir": Vector3(-1, 0, 0), "gravity_modes": [GRAVITY_CENTRIFUGAL]},
			{"id": "out", "local_pos": Vector3(3.2, 0, 0), "local_dir": Vector3(1, 0, 0), "gravity_modes": [GRAVITY_CENTRIFUGAL]},
			{"id": "z_in", "local_pos": Vector3(0, 0, -3.2), "local_dir": Vector3(0, 0, -1), "gravity_modes": [GRAVITY_AXIAL]},
			{"id": "z_out", "local_pos": Vector3(0, 0, 3.2), "local_dir": Vector3(0, 0, 1), "gravity_modes": [GRAVITY_AXIAL]},
		],
	},
	"industry_bridge": {
		"family": "bridge",
		"size": Vector3(CHUNK_LENGTH, 2.4, WALKWAY_WIDTH),
		"pieces": [
			{"key": "span", "visual": "deck", "pos": Vector3(0, 0, 0), "size": Vector3(CHUNK_LENGTH, 0.4, WALKWAY_WIDTH)},
			{"key": "rail_f", "visual": "rail", "pos": Vector3(0, 0.9, -1.2), "size": Vector3(CHUNK_LENGTH, 0.12, 0.12)},
			{"key": "rail_b", "visual": "rail", "pos": Vector3(0, 0.9, 1.2), "size": Vector3(CHUNK_LENGTH, 0.12, 0.12)},
		],
		"connectors": [
			{"id": "a", "local_pos": Vector3(-6, 0, 0), "local_dir": Vector3(-1, 0, 0), "gravity_modes": [GRAVITY_BOTH]},
			{"id": "b", "local_pos": Vector3(6, 0, 0), "local_dir": Vector3(1, 0, 0), "gravity_modes": [GRAVITY_BOTH]},
		],
	},
	"industry_catwalk": {
		"family": "scaffold",
		"size": Vector3(WALKWAY_WIDTH, 1.8, CHUNK_LENGTH),
		"pieces": [
			{"key": "deck", "visual": "deck", "pos": Vector3(0, 0, 0), "size": Vector3(WALKWAY_WIDTH, 0.3, CHUNK_LENGTH)},
			{"key": "rail_l", "visual": "rail", "pos": Vector3(-1.15, 0.8, 0), "size": Vector3(0.1, 0.1, CHUNK_LENGTH)},
			{"key": "rail_r", "visual": "rail", "pos": Vector3(1.15, 0.8, 0), "size": Vector3(0.1, 0.1, CHUNK_LENGTH)},
		],
		"connectors": [
			{"id": "in", "local_pos": Vector3(0, 0, -6), "local_dir": Vector3(0, 0, -1), "gravity_modes": [GRAVITY_BOTH]},
			{"id": "out", "local_pos": Vector3(0, 0, 6), "local_dir": Vector3(0, 0, 1), "gravity_modes": [GRAVITY_BOTH]},
		],
	},
	"industry_tower": {
		"family": "scaffold",
		"size": Vector3(4.0, 4.0, CHUNK_LENGTH),
		"pieces": [
			{"key": "spine", "visual": "girder", "pos": Vector3(0, 0, 0), "size": Vector3(1.2, 1.2, CHUNK_LENGTH)},
			{"key": "ring_a", "visual": "frame", "pos": Vector3(0, 0, -4), "size": Vector3(4.0, 4.0, 0.3)},
			{"key": "ring_b", "visual": "frame", "pos": Vector3(0, 0, 4), "size": Vector3(4.0, 4.0, 0.3)},
		],
		"connectors": [
			{"id": "in", "local_pos": Vector3(0, 0, -6), "local_dir": Vector3(0, 0, -1), "gravity_modes": [GRAVITY_BOTH]},
			{"id": "out", "local_pos": Vector3(0, 0, 6), "local_dir": Vector3(0, 0, 1), "gravity_modes": [GRAVITY_BOTH]},
			{"id": "radial", "local_pos": Vector3(2.0, 0, 0), "local_dir": Vector3(1, 0, 0), "gravity_modes": [GRAVITY_CENTRIFUGAL]},
		],
	},
	"industry_pump": {
		"family": "machinery",
		"size": Vector3(3.8, 3.8, 3.8),
		"pieces": [
			{"key": "body", "visual": "machine", "pos": Vector3(0, 0, 0), "size": Vector3(3.0, 3.0, 3.0)},
			{"key": "pipe_x", "visual": "pipe", "pos": Vector3(0, 0, 0), "size": Vector3(3.6, 0.6, 0.6)},
			{"key": "pipe_z", "visual": "pipe", "pos": Vector3(0, 0.9, 0), "size": Vector3(0.6, 0.6, 3.6)},
		],
		"connectors": [
			{"id": "radial", "local_pos": Vector3(-1.8, 0, 0), "local_dir": Vector3(-1, 0, 0), "gravity_modes": [GRAVITY_CENTRIFUGAL]},
			{"id": "z", "local_pos": Vector3(0, 0, 1.8), "local_dir": Vector3(0, 0, 1), "gravity_modes": [GRAVITY_AXIAL]},
			{"id": "both", "local_pos": Vector3(1.8, 0, 0), "local_dir": Vector3(1, 0, 0), "gravity_modes": [GRAVITY_BOTH]},
		],
	},
	"industry_junction": {
		"family": "bridge",
		"size": Vector3(6.0, 3.0, 6.0),
		"pieces": [
			{"key": "deck", "visual": "deck", "pos": Vector3(0, 0, 0), "size": Vector3(6.0, 0.4, 6.0)},
			{"key": "frame", "visual": "frame", "pos": Vector3(0, 1.5, 0), "size": Vector3(0.2, 3.0, 0.2)},
		],
		"connectors": [
			{"id": "x_in", "local_pos": Vector3(-3, 0, 0), "local_dir": Vector3(-1, 0, 0), "gravity_modes": [GRAVITY_CENTRIFUGAL]},
			{"id": "x_out", "local_pos": Vector3(3, 0, 0), "local_dir": Vector3(1, 0, 0), "gravity_modes": [GRAVITY_CENTRIFUGAL]},
			{"id": "z_in", "local_pos": Vector3(0, 0, -3), "local_dir": Vector3(0, 0, -1), "gravity_modes": [GRAVITY_AXIAL]},
			{"id": "z_out", "local_pos": Vector3(0, 0, 3), "local_dir": Vector3(0, 0, 1), "gravity_modes": [GRAVITY_BOTH]},
		],
	},
}

static func chunk_ids() -> Array:
	return CHUNKS.keys()

static func get_chunk(chunk_id: String) -> Dictionary:
	return CHUNKS.get(chunk_id, {})

static func find_connector(chunk_id: String, connector_id: String) -> Dictionary:
	var chunk := get_chunk(chunk_id)
	for conn in chunk.get("connectors", []):
		if str(conn["id"]) == connector_id:
			return conn
	return {}

static func connector_supports_modes(modes: Array, mode: String) -> bool:
	if modes.has(GRAVITY_BOTH):
		return true
	if mode == GRAVITY_BOTH:
		return modes.has(GRAVITY_CENTRIFUGAL) and modes.has(GRAVITY_AXIAL)
	return modes.has(mode)

# Devuelve la pieza resuelta contra la tabla de reemplazo del kit final. `mesh_path`
# o `scene_path` no vacíos sustituyen la primitiva provisional en el streamer.
static func resolve_piece_visual(visual_key: String) -> Dictionary:
	var base: Dictionary = VISUALS.get(visual_key, VISUALS["frame"])
	var replacement: Dictionary = MESH_REPLACEMENTS.get(visual_key, {})
	return {
		"key": visual_key,
		"mesh_type": str(base["mesh"]),
		"color": base["color"],
		"scene_path": str(replacement.get("scene", "")),
		"mesh_path": str(replacement.get("mesh", "")),
	}

# Métricas reusadas (runtime) del registro de andamios.
static func scaffold_chunk_length() -> float:
	return float(ScaffoldChunkRegistry.CHUNK_LENGTH)

static func scaffold_walkway_width() -> float:
	return float(ScaffoldChunkRegistry.WALKWAY_WIDTH)

static func scaffold_rail_height() -> float:
	return float(ScaffoldChunkRegistry.RAIL_HEIGHT)
