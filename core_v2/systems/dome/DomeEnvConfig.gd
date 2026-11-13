extends Resource
class_name DomeEnvConfigV2

# DomeEnvConfig.gd — declaración plana de un domo criogénico (FD-289 §7.2, T1).
#
# Recurso leído por DomeSystemDirector (T2) para saber qué redes, qué eventos de
# timeline y qué escenas tiene este domo. Es un `.tres` a mano: no hay editor visual
# (FD-289 §8). El template de sistemas (redes + timeline + blast door) es compartido
# entre domos; lo que varía por domo es el hangar, apuntado por hangar_scene.

# Identificador del domo (p. ej. "intro", "prologue").
export(String) var dome_id: String = ""
# Redes que participan del equilibrio, en orden canónico de restauración.
export(PoolStringArray) var networks: PoolStringArray = PoolStringArray()
# Lista de beats guionizados: cada entrada es un Dictionary {beat:int, event:String,
# action:String}. El director (T2) dispara `action` cuando ocurre `event`.
export(Array) var timeline: Array = []
# Escena del hangar/sótano (res://...) a la que baja el jugador tras el blast door.
export(String) var hangar_scene: String = ""
# Id del spawn de llegada al hangar (uno por domo).
export(String) var hangar_spawn_id: String = ""
# Escena de la esclusa al exterior (res://...) que cierra el vertical slice.
export(String) var exterior_airlock_scene: String = ""
# Ruta relativa al nodo del blast door dentro de la escena del domo.
export(NodePath) var blast_door_path: NodePath = NodePath()


func network_count() -> int:
	return networks.size()


func has_network(network_id: String) -> bool:
	return networks.has(network_id)


# Devuelve la acción del timeline disparada por `event`, o "" si no hay ninguna.
func get_timeline_action(event: String) -> String:
	for entry in timeline:
		if entry is Dictionary and String(entry.get("event", "")) == event:
			return String(entry.get("action", ""))
	return ""
