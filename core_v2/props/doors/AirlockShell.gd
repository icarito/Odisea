extends Spatial
class_name AirlockShell

# Reemplazo liviano de AirlockChamber: solo el cilindro exterior y la colision.
#
# Un AirlockChamber completo son ~27 MeshInstance (nueve del interior y dieciocho de las dos
# puertas iris), dos Area, un EmergencyBeacon con luz, un AudioStreamPlayer3D y cuatro
# scripts (AirlockControllerV2, AirlockTransitionFX y las dos puertas). Dome_Intro tiene
# CUATRO, y como el domo es un anillo se ven casi todos a la vez. Medido en un Redmi Note 9
# Pro, dejar solo el cilindro baja 12% las draw calls y sube 3.4% los fps.
#
# El shell NO tiene mecanica: no abre, no presuriza, no transiciona. Guarda la CONFIGURACION
# del destino (a donde lleva este airlock) para que AirlockPool se la aplique al unico
# AirlockChamber completo que existe en la escena cuando lo monta aca.
#
# --- COMO VOLVER AL AIRLOCK COMPLETO ---
# En Dome_Intro.tscn, cada airlock es una instancia de AirlockShell.tscn. Para devolver el
# original basta con reemplazar el ext_resource:
#     [ext_resource path="res://core_v2/props/doors/AirlockShell.tscn" ... id=2]
#   ->[ext_resource path="res://core_v2/props/doors/AirlockChamber.tscn" ... id=2]
# y devolverle a cada nodo su bloque de override de AirlockZoneV2, que quedo guardado aca
# abajo en cada instancia (target_scene / target_spawn_id / zone_dir). El AirlockChamber
# completo trae su propio AirlockZoneV2 en el indice 14. Sacar tambien el nodo AirlockPool
# de la escena, que si no montaria un airlock encima de otro.

# Nombre logico del airlock. Es el que espera AirlockZoneV2 en target_airlock_path.
export(String) var airlock_name := ""
# A donde lleva este airlock. Lo consume AirlockPool al montar el chamber completo.
export(String, FILE, "*.tscn") var target_scene := ""
export(String) var target_spawn_id := ""
export(Vector3) var zone_dir := Vector3(0, 0, 1)


func get_zone_config() -> Dictionary:
	return {
		"target_scene": target_scene,
		"target_spawn_id": target_spawn_id,
		"target_airlock_path": NodePath(airlock_name if airlock_name != "" else name),
		"zone_dir": zone_dir,
	}


# El shell trae los dos SELLOS de puerta (OuterSeal / InnerSeal) con la misma geometria de
# colision que el Frame y el DoorBlocker del iris original. Sin ellos el tubo queda abierto
# de punta a punta y el jugador atraviesa la pared del domo; ademas cambia la fisica respecto
# del original, que en Dome_Intro tiene las puertas cerradas (medido: 0.12 m de drift en un
# replay que con los sellos da 0.0000 m).
#
# Las mallas se ocultan cuando el pool monta el chamber completo encima: los dos traen la
# misma silueta y se verian superpuestos. La COLISION del shell no se toca nunca — apagar y
# prender formas las re-registra en el espacio de fisica y perturba el orden de resolucion
# de contactos, y esta es la colision que sostiene al jugador contra la pared del domo. Por
# eso es el CHAMBER el que renuncia a su colision al montarse, no el shell.
func set_shell_visible(visible_: bool) -> void:
	for ruta in ["CylindricalShell/ShellMesh", "OuterSeal/Frame/FrameMesh", "InnerSeal/Frame/FrameMesh"]:
		var m := get_node_or_null(ruta)
		if m != null:
			(m as Spatial).visible = visible_
