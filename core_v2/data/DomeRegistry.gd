extends Node
#class_name DomeRegistry

const DEFAULT_INTERIOR_SCENE := "res://core_v2/levels/interiors/Dome_01.tscn"
const DEFAULT_FACADE_SCENE := "res://core_v2/levels/facades/DomeFacade_01.tscn"
const DEFAULT_FACADE_LOD_SCENE := "res://models/lod/DomeFacade_01_LOD.glb"
const DEFAULT_FACADE_LOD_MESH_NODE := "DomeLOD"
const DEFAULT_FACADE_SPAWN_OFFSET := Vector3(0, 0.3, 0)
const DEFAULT_FACADE_LOD_SPAWN_OFFSET := Vector3(0, 0.3, 0)
const DEFAULT_FACADE_LOD_SCALE := Vector3(1.0, 1.0, 1.0)

# Registro declarativo: dome_id -> config
# Claves opcionales para LOD de fachadas:
# - facade_lod_scene: escena importada (por ejemplo un .glb) con una MeshInstance reutilizable.
# - facade_lod_mesh_node: NodePath relativo dentro de facade_lod_scene para elegir la MeshInstance correcta.
# - facade_lod_mesh: recurso Mesh directo si ya existe como .mesh/.tres.
# - facade_lod_spawn_offset: ajuste posicional adicional para el LOD.
# - facade_lod_scale: escala adicional para el LOD extraido.
var _registry := {
	"dome_intro": {
		"interior_scene": "res://core_v2/levels/interiors/Dome_Intro.tscn",
		"facade_scene": "res://core_v2/levels/facades/DomeFacade_01.tscn",
		"facade_lod_scene": "res://models/lod/DomeFacade_01_LOD.glb",
		"facade_lod_mesh_node": "DomeLOD",
		"facade_lod_scale": DEFAULT_FACADE_LOD_SCALE,
		"facade_lod_spawn_offset": Vector3(0, 0.3, 0),
		"facade_spawn_offset": Vector3(0, 0.3, 0),
		"spiral_index": 0,
		"plate_index": 8,
		"display_name": "Domo de Entrada",
		"spawn_id_from_exterior": "from_dome_intro",
		"spawn_id_from_interior": "from_exterior_dome_intro"
	},
	"dome_01": {
		"interior_scene": "res://core_v2/levels/interiors/Dome_Crio.tscn",
		"facade_scene": "res://core_v2/levels/facades/DomeFacade_01.tscn",
		"facade_lod_scene": "res://models/lod/DomeFacade_01_LOD.glb",
		"facade_lod_mesh_node": "DomeLOD",
		"facade_lod_scale": DEFAULT_FACADE_LOD_SCALE,
		"facade_lod_spawn_offset": Vector3(0, 0.3, 0),
		"facade_spawn_offset": Vector3(0, 0.3, 0),
		"spiral_index": 0,
		"plate_index": 15,
		"display_name": "Laboratorio Biológico",
		"spawn_id_from_exterior": "from_dome_01",
		"spawn_id_from_interior": "from_exterior_dome_01"
	},
	"dome_02": {
		"interior_scene": "res://core_v2/levels/interiors/Dome_01.tscn",
		"facade_scene": "res://core_v2/levels/facades/DomeFacade_01.tscn",
		"facade_lod_scene": "res://models/lod/DomeFacade_01_LOD.glb",
		"facade_lod_mesh_node": "DomeLOD",
		"facade_lod_scale": DEFAULT_FACADE_LOD_SCALE,
		"facade_lod_spawn_offset": Vector3(0, 0.3, 0),
		"facade_spawn_offset": Vector3(0, 0.3, 0),
		"spiral_index": 0,
		"plate_index": 1,
		"display_name": "Bahía de Ingeniería",
		"spawn_id_from_exterior": "from_dome_02",
		"spawn_id_from_interior": "from_exterior_dome_02"
	},
	"dome_03": {
		"interior_scene": "res://core_v2/levels/interiors/Dome_01.tscn",
		"facade_scene": "res://core_v2/levels/facades/DomeFacade_01.tscn",
		"facade_lod_scene": "res://models/lod/DomeFacade_01_LOD.glb",
		"facade_lod_mesh_node": "DomeLOD",
		"facade_lod_scale": DEFAULT_FACADE_LOD_SCALE,
		"facade_lod_spawn_offset": Vector3(0, 0.3, 0),
		"facade_spawn_offset": Vector3(0, 0.3, 0),
		"spiral_index": 2,
		"plate_index": 5,
		"display_name": "Criogenia",
		"spawn_id_from_exterior": "from_dome_03",
		"spawn_id_from_interior": "from_exterior_dome_03"
	}
}

func get_dome(dome_id: String) -> Dictionary:
	var normalized := String(dome_id).strip_edges()
	if normalized == "":
		return {}
	if _registry.has(normalized):
		return _merge_with_default_config(normalized, _registry[normalized])
	var synthetic_slot := _parse_synthetic_dome_id(normalized)
	if synthetic_slot.empty():
		return {}
	return _build_default_dome_config(normalized, int(synthetic_slot["spiral_index"]), int(synthetic_slot["plate_index"]))

func get_interior_scene(dome_id: String) -> String:
	return _registry.get(dome_id, {}).get("interior_scene", "")

func get_facade_scene(dome_id: String) -> String:
	return String(_registry.get(dome_id, {}).get("facade_scene", ""))

func get_facade_lod_config(dome_id: String) -> Dictionary:
	var info: Dictionary = get_dome(dome_id)
	return {
		"scene": String(info.get("facade_lod_scene", "")),
		"mesh_node": String(info.get("facade_lod_mesh_node", "")),
		"mesh": String(info.get("facade_lod_mesh", "")),
		"spawn_offset": info.get("facade_lod_spawn_offset", Vector3.ZERO),
		"scale": info.get("facade_lod_scale", Vector3.ONE)
	}

func get_dome_id_for_plate(spiral_index: int, plate_index: int) -> String:
	var explicit_id := _find_explicit_dome_id_by_plate(spiral_index, plate_index)
	if explicit_id != "":
		return explicit_id
	return _build_synthetic_dome_id(spiral_index, plate_index)

func get_spawn_id_from_exterior(dome_id: String) -> String:
	return String(get_dome(dome_id).get("spawn_id_from_exterior", ""))

func get_spawn_id_from_interior(dome_id: String) -> String:
	return String(get_dome(dome_id).get("spawn_id_from_interior", ""))

func find_dome_id_by_interior_spawn(spawn_id: String) -> String:
	var normalized := String(spawn_id).strip_edges()
	if normalized == "":
		return ""
	for dome_id in _registry.keys():
		if String(_registry[dome_id].get("spawn_id_from_interior", "")).strip_edges() == normalized:
			return String(dome_id)
	var synthetic_slot := _parse_synthetic_interior_spawn_id(normalized)
	if not synthetic_slot.empty():
		return _build_synthetic_dome_id(int(synthetic_slot["spiral_index"]), int(synthetic_slot["plate_index"]))
	return ""

func find_dome_id_by_exterior_spawn(spawn_id: String) -> String:
	var normalized := String(spawn_id).strip_edges()
	if normalized == "":
		return ""
	for dome_id in _registry.keys():
		if String(_registry[dome_id].get("spawn_id_from_exterior", "")).strip_edges() == normalized:
			return String(dome_id)
	var synthetic_slot := _parse_synthetic_exterior_spawn_id(normalized)
	if not synthetic_slot.empty():
		return _build_synthetic_dome_id(int(synthetic_slot["spiral_index"]), int(synthetic_slot["plate_index"]))
	return ""

func get_all_dome_ids() -> Array:
	return _registry.keys()

func get_spawn_transform(spawn_id: String) -> Transform:
	var dome_id := find_dome_id_by_exterior_spawn(spawn_id)
	if dome_id == "":
		dome_id = find_dome_id_by_interior_spawn(spawn_id)
	if dome_id == "":
		return Transform.IDENTITY
	var info: Dictionary = get_dome(dome_id)
	var spiral_index := int(info.get("spiral_index", 0))
	var plate_index := int(info.get("plate_index", 0))
	var exterior = _get_exterior_scene()
	if exterior and exterior.has_method("get_selected_plate_global_transform"):
		# Ask the exterior to select that plate's transform
		var rotator = exterior.get_node_or_null("WorldRotator")
		if rotator and rotator.has_method("get_plate_canonical_transform"):
			var spirals := []
			for spiral_name in ["TerraceSpiral", "TerraceSpiral2", "TerraceSpiral3", "TerraceSpiral4"]:
				var s = rotator.get_node_or_null(spiral_name)
				if s:
					spirals.append(s)
			if spiral_index < spirals.size():
				var canonical: Transform = rotator.get_plate_canonical_transform(spirals[spiral_index], plate_index)
				var world_tx: Transform = rotator.global_transform * canonical
				var spawn_offset: Vector3 = info.get("facade_spawn_offset", Vector3.ZERO)
				return Transform(world_tx.basis, world_tx.origin + spawn_offset)
	return Transform.IDENTITY

func _get_exterior_scene() -> Node:
	var tree := Engine.get_main_loop()
	if not tree:
		return null
	var current = tree.current_scene if tree.has_method("get") else null
	# tree is SceneTree
	if tree is SceneTree:
		current = (tree as SceneTree).current_scene
	if is_instance_valid(current) and "OdiseaExterior" in current.filename:
		return current
	# Also check if AirlockManager has a cached exterior
	var airlock_manager = Engine.get_main_loop().root.get_node_or_null("AirlockManager")
	if airlock_manager and is_instance_valid(airlock_manager.get("_exterior_scene")):
		return airlock_manager._exterior_scene
	return null

func _merge_with_default_config(dome_id: String, config: Dictionary) -> Dictionary:
	var merged := _build_default_dome_config(dome_id, int(config.get("spiral_index", 0)), int(config.get("plate_index", 0)))
	for key in config.keys():
		merged[key] = config[key]
	return merged

func _build_default_dome_config(dome_id: String, spiral_index: int, plate_index: int) -> Dictionary:
	return {
		"dome_id": dome_id,
		"interior_scene": DEFAULT_INTERIOR_SCENE,
		"facade_scene": DEFAULT_FACADE_SCENE,
		"facade_lod_scene": DEFAULT_FACADE_LOD_SCENE,
		"facade_lod_mesh_node": DEFAULT_FACADE_LOD_MESH_NODE,
		"facade_lod_scale": DEFAULT_FACADE_LOD_SCALE,
		"facade_lod_spawn_offset": DEFAULT_FACADE_LOD_SPAWN_OFFSET,
		"facade_spawn_offset": DEFAULT_FACADE_SPAWN_OFFSET,
		"spiral_index": spiral_index,
		"plate_index": plate_index,
		"display_name": "Domo %d-%d" % [spiral_index + 1, plate_index + 1],
		"spawn_id_from_exterior": _build_synthetic_exterior_spawn_id(spiral_index, plate_index),
		"spawn_id_from_interior": _build_synthetic_interior_spawn_id(spiral_index, plate_index)
	}

func _find_explicit_dome_id_by_plate(spiral_index: int, plate_index: int) -> String:
	for dome_id in _registry.keys():
		var info: Dictionary = _registry[dome_id]
		if int(info.get("spiral_index", -1)) == spiral_index and int(info.get("plate_index", -1)) == plate_index:
			return String(dome_id)
	return ""

func _build_synthetic_dome_id(spiral_index: int, plate_index: int) -> String:
	return "dome_s%02d_p%03d" % [spiral_index, plate_index]

func _build_synthetic_exterior_spawn_id(spiral_index: int, plate_index: int) -> String:
	return "from_dome_s%02d_p%03d" % [spiral_index, plate_index]

func _build_synthetic_interior_spawn_id(spiral_index: int, plate_index: int) -> String:
	return "from_exterior_dome_s%02d_p%03d" % [spiral_index, plate_index]

func _parse_synthetic_dome_id(dome_id: String) -> Dictionary:
	var parts := String(dome_id).split("_")
	if parts.size() != 3:
		return {}
	if parts[0] != "dome" or not String(parts[1]).begins_with("s") or not String(parts[2]).begins_with("p"):
		return {}
	return {
		"spiral_index": int(String(parts[1]).substr(1, String(parts[1]).length() - 1)),
		"plate_index": int(String(parts[2]).substr(1, String(parts[2]).length() - 1))
	}

func _parse_synthetic_exterior_spawn_id(spawn_id: String) -> Dictionary:
	if not String(spawn_id).begins_with("from_dome_s"):
		return {}
	return _parse_synthetic_dome_id(String(spawn_id).trim_prefix("from_"))

func _parse_synthetic_interior_spawn_id(spawn_id: String) -> Dictionary:
	if not String(spawn_id).begins_with("from_exterior_dome_s"):
		return {}
	return _parse_synthetic_dome_id(String(spawn_id).trim_prefix("from_exterior_"))
