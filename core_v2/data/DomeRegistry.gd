extends Node
#class_name DomeRegistry

# Registro declarativo: dome_id -> config
var _registry := {
	"dome_01": {
		"interior_scene": "res://core_v2/levels/interiors/Dome_01.tscn",
		"facade_scene": "res://core_v2/levels/facades/DomeFacade_01.tscn",
		"spiral_index": 0,
		"plate_index": 42,
		"display_name": "Laboratorio Biológico",
		"spawn_id_from_exterior": "from_dome_01",
		"spawn_id_from_interior": "from_exterior_dome_01"
	},
	"dome_02": {
		"interior_scene": "res://core_v2/levels/interiors/Dome_02.tscn",
		"facade_scene": "res://core_v2/levels/facades/DomeFacade_02.tscn",
		"spiral_index": 0,
		"plate_index": 86,
		"display_name": "Bahía de Ingeniería",
		"spawn_id_from_exterior": "from_dome_02",
		"spawn_id_from_interior": "from_exterior_dome_02"
	}
}

func get_dome(dome_id: String) -> Dictionary:
	return _registry.get(dome_id, {})

func get_interior_scene(dome_id: String) -> String:
	return _registry.get(dome_id, {}).get("interior_scene", "")

func get_all_dome_ids() -> Array:
	return _registry.keys()
