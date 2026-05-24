extends Node
#class_name DomeRegistry

# Registro declarativo: dome_id -> config
var _registry := {
	"dome_01": {
		"interior_scene": "res://core_v2/levels/interiors/Dome_01.tscn",
		"facade_scene": "res://core_v2/levels/facades/DomeFacade_01.tscn",
		"facade_spawn_offset": Vector3(0, 0.3, 0),
		"spiral_index": 0,
		"plate_index": 0,
		"display_name": "Laboratorio Biológico",
		"spawn_id_from_exterior": "from_dome_01",
		"spawn_id_from_interior": "from_exterior_dome_01"
	},
	"dome_02": {
		"interior_scene": "res://core_v2/levels/interiors/Dome_01.tscn",
		"facade_scene": "res://core_v2/levels/facades/DomeFacade_01.tscn",
		"spiral_index": 0,
		"plate_index": 1,
		"display_name": "Bahía de Ingeniería",
		"spawn_id_from_exterior": "from_dome_02",
		"spawn_id_from_interior": "from_exterior_dome_02"
	},
	"dome_03": {
		"interior_scene": "res://core_v2/levels/interiors/Dome_01.tscn",
		"facade_scene": "res://core_v2/levels/facades/DomeFacade_01.tscn",
		"spiral_index": 2,
		"plate_index": 5,
		"display_name": "Criogenia",
		"spawn_id_from_exterior": "from_dome_03",
		"spawn_id_from_interior": "from_exterior_dome_03"
	}
}

func get_dome(dome_id: String) -> Dictionary:
	return _registry.get(dome_id, {})

func get_interior_scene(dome_id: String) -> String:
	return _registry.get(dome_id, {}).get("interior_scene", "")

func get_all_dome_ids() -> Array:
	return _registry.keys()
