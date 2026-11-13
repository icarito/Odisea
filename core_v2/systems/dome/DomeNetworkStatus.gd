extends Node
class_name DomeNetworkStatus

# DomeNetworkStatus.gd — registro de redes HEALTHY de un domo (FD-289 §7.3, T1).
#
# Componente ligero: cada red del domo (criocoolant, plasma, aire, energia) llama
# mark_healthy() cuando llega a su estado sano. El director del domo (T2) lo consulta
# para disparar el timeline. No simula nada por cuadro: es un contador de estado puro,
# así que no corre _process ni _physics_process (FD-289 §7.3: "componente ligero").
#
# Vive en Dome_Base y entra a replay_sync con get_snapshot/restore_snapshot para
# sobrevivir un replay determinista (AGENTS.md §5.3); el estado es lo único replicable.

# Cantidad de redes que deben llegar a HEALTHY para considerar el domo en equilibrio
# (4 en el MVP: criocoolant, plasma, aire, energia). Documentado en el Inspector.
export(int) var total_networks: int = 4

signal network_healthy(network_id)
signal all_healthy()

var _healthy_networks: Dictionary = {}
var _all_healthy_emitted: bool = false


func _ready() -> void:
	add_to_group("replay_sync")
	# Estado puro: no necesita ticks. Desactivar explícitamente deja claro que el culling
	# de FD-224 no tiene nada que apagar acá.
	set_process(false)
	set_physics_process(false)


# Marca una red como HEALTHY. Idempotente: re-notificar la misma red no re-emite la
# señal ni altera el conteo, para que un evento duplicado no dispare two veces el
# timeline. Emite all_healthy() una sola vez, al alcanzar total_networks.
func mark_healthy(network_id: String) -> void:
	if network_id == "":
		return
	if _healthy_networks.has(network_id):
		return
	_healthy_networks[network_id] = true
	emit_signal("network_healthy", network_id)
	if not _all_healthy_emitted and is_all_healthy():
		_all_healthy_emitted = true
		emit_signal("all_healthy")


# Revierte una red a no sana (p. ej. una fuga nueva tumba el coolant). Vuelve a armar
# all_healthy() para que el equilibrio pueda re-alcanzarse.
func mark_unhealthy(network_id: String) -> void:
	if _healthy_networks.erase(network_id):
		_all_healthy_emitted = false


func is_healthy(network_id: String) -> bool:
	return _healthy_networks.has(network_id)


func is_all_healthy() -> bool:
	return total_networks > 0 and _healthy_networks.size() >= total_networks


func healthy_count() -> int:
	return _healthy_networks.size()


func get_healthy_networks() -> Array:
	return _healthy_networks.keys()


func clear() -> void:
	_healthy_networks.clear()
	_all_healthy_emitted = false


func get_snapshot() -> Dictionary:
	return {
		"healthy": _healthy_networks.keys(),
		"all_healthy_emitted": _all_healthy_emitted,
	}


func restore_snapshot(data: Dictionary) -> void:
	_healthy_networks.clear()
	var healthy = data.get("healthy", [])
	for network_id in healthy:
		_healthy_networks[String(network_id)] = true
	_all_healthy_emitted = bool(data.get("all_healthy_emitted", false))
