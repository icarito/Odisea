extends Spatial

# HangarMagRailConnector.gd
# Enruta la esclusa de salida del hangar hacia el tramo MagRail cuando el flag
# esta activo; si se desactiva o falta la escena, restaura el airlock directo
# hacia RingHub_Level sin bloquear la linea principal.

export(bool) var magrail_hangar_connector_enabled := true
export(String, FILE, "*.tscn") var magrail_scene := "res://core_v2/levels/MagRailHangarToRingHub.tscn"
export(String) var magrail_spawn_id := "from_hangar"
export(NodePath) var magrail_airlock_path := NodePath("Airlock_FromHangar")

export(String, FILE, "*.tscn") var fallback_target_scene := "res://core_v2/levels/RingHub_Level.tscn"
export(String) var fallback_target_spawn_id := "from_dome_intro_hangar"
export(NodePath) var fallback_target_airlock_path := NodePath("Hub/Airlock_FromHangar")
export(NodePath) var airlock_zone_path := NodePath("Airlock_Exit/AirlockZoneV2")


func _ready() -> void:
	apply_route()


func apply_route() -> void:
	var zone := get_node_or_null(airlock_zone_path)
	if zone == null:
		return
	if magrail_hangar_connector_enabled and magrail_scene != "" and ResourceLoader.exists(magrail_scene):
		zone.set("target_scene", magrail_scene)
		zone.set("target_spawn_id", magrail_spawn_id)
		zone.set("target_airlock_path", magrail_airlock_path)
	else:
		zone.set("target_scene", fallback_target_scene)
		zone.set("target_spawn_id", fallback_target_spawn_id)
		zone.set("target_airlock_path", fallback_target_airlock_path)
