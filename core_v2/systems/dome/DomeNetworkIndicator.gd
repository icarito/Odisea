extends Spatial
class_name DomeNetworkIndicator

# DomeNetworkIndicator.gd — indicador de estado de una red del domo (FD-289 §3.2, §6).
#
# Vestido del nodo lógico de red: la FORMA es una lámpara/barra de estado montada en el prop
# de la red (nunca un cartel explicativo, §3.2 "la forma del prop identifica la acción"),
# y el COLOR identifica la red con la paleta canónica:
#   criocoolant cian #00E5FF · plasma ámbar #FF8F00 · aire rojo #FF5252 · energía verde #00FF88.
#
# Estado: cuando la red llega a HEALTHY, la emisión de la red se enciende con su color; mientras
# no, queda apagada (la forma sigue leyéndose, apagada). Maneja la lámpara Y los elementos
# emisivos del prop listados en `emissive_paths` (collar de color, conductos, barra de bus),
# para que el estado se lea de un vistazo y no sólo en un LED.
#
# No simula nada ni guarda estado propio — LEE `DomeNetworkStatus.is_healthy()` (que sí es
# snapshot-able), así que no rompe el replay (AGENTS.md §5.3). No es gameplay: sólo cambia la
# emisión de mallas, no mueve ni altera estado físico.
#
# Resolución del DomeNetworkStatus: si `status_path` está vacío, camina hacia arriba por el
# árbol buscando el registro del domo. Así el indicador funciona instanciado a cualquier
# profundidad dentro de la escena del domo (prop vestido -> DomeMachineLevel -> Dome_Base).

# Identificador de red (mismo string que usa DomeNetworkStatus: criocoolant/plasma/aire/energia).
export(String) var network_id := ""
# NodePath explícito al DomeNetworkStatus. Vacío = se resuelve caminando hacia arriba.
export(NodePath) var status_path := NodePath("")
# Color canónico de la red (emisión cuando HEALTHY). Ver cabecera.
export(Color) var healthy_color := Color(0.0, 0.898, 1.0, 1.0)
# Energía de emisión cuando la red está HEALTHY. 0 = apagado.
export(float) var healthy_energy := 2.6
# Meshes/CSG que encienden con la red (paths relativos a este nodo). Vacío = sólo `lamp_path`.
export(Array, NodePath) var emissive_paths := []
# Nodo con la malla de la lámpara (por defecto "Lamp").
export(NodePath) var lamp_path := NodePath("Lamp")
# Cada cuántos segundos re-leer el estado (recupera el color tras un restore de snapshot que
# no re-emite señales). Es decorativo: no altera estado de juego ni determinismo.
export(float) var refresh_interval := 0.25

var _status: Node = null
var _material: SpatialMaterial = null
var _targets := []
var _healthy := false
var _refresh_accum := 0.0

# Gris neutro cuando la red no está sana: la forma queda legible pero "muerta", sin tinte de red.
const _OFF_ALBEDO := Color(0.085, 0.095, 0.105, 1.0)


func _ready() -> void:
	# Visual puro: no guarda estado propio (re-deriva del DomeNetworkStatus, que sí tiene
	# snapshot), pero se une al grupo para que el audit de replay no lo lea como "invisible".
	add_to_group("replay_sync")
	_resolve()
	_refresh()


func get_snapshot() -> Dictionary:
	return {}


func restore_snapshot(_data: Dictionary) -> void:
	# Sin estado propio: al restaurar, re-lee el estado de la red (que es quien se snapshot-ea).
	_refresh()


func _process(delta: float) -> void:
	if _status == null:
		_resolve()
		return
	_refresh_accum += delta
	if _refresh_accum < refresh_interval:
		return
	_refresh_accum = 0.0
	_refresh()


func _resolve() -> void:
	if _status == null:
		_status = _resolve_status()
		if _status != null:
			if _status.has_signal("network_healthy") and not _status.is_connected("network_healthy", self, "_on_network_healthy"):
				_status.connect("network_healthy", self, "_on_network_healthy")
			if _status.has_signal("all_healthy") and not _status.is_connected("all_healthy", self, "_on_network_healthy"):
				_status.connect("all_healthy", self, "_on_network_healthy")
	if _material == null:
		_build_targets()
		_build_material()
		_apply()


func _build_targets() -> void:
	if _targets.size() > 0:
		return
	var paths := emissive_paths
	if paths.empty() and lamp_path != null and not lamp_path.is_empty():
		paths = [lamp_path]
	for p in paths:
		var node := get_node_or_null(p)
		if node != null:
			_targets.append(node)


func _build_material() -> void:
	_material = SpatialMaterial.new()
	_material.emission_enabled = true
	_material.emission = healthy_color
	_material.emission_energy = 0.0
	_material.albedo_color = _OFF_ALBEDO
	_material.roughness = 0.4
	_material.metallic = 0.2
	for node in _targets:
		if node is CSGShape:
			node.material = _material
		elif node is MeshInstance:
			node.material_override = _material


func _resolve_status() -> Node:
	if status_path != null and not status_path.is_empty():
		var explicit := get_node_or_null(status_path)
		if explicit != null:
			return explicit
	# Fallback: subir por el árbol buscando el registro de redes del domo. Se identifica por
	# su contrato (is_healthy + mark_healthy + señal network_healthy), no por nombre.
	var node: Node = get_parent()
	while node != null:
		for child in node.get_children():
			if child.has_method("is_healthy") and child.has_method("mark_healthy") \
					and child.has_signal("network_healthy"):
				return child
		node = node.get_parent()
	return null


func _on_network_healthy(id = null) -> void:
	if _status == null:
		return
	if id == null or String(id) == network_id or network_id == "":
		_refresh()


func _refresh() -> void:
	if _status != null and _status.has_method("is_healthy"):
		_healthy = bool(_status.call("is_healthy", network_id))
	_apply()


func _apply() -> void:
	if _material == null:
		return
	_material.emission = healthy_color
	_material.emission_energy = healthy_energy if _healthy else 0.0
	_material.albedo_color = (healthy_color * 0.9) if _healthy else _OFF_ALBEDO


# API para que el cableado pueda empujar el estado si algún día se prefiere señal explícita.
func set_healthy(value: bool) -> void:
	_healthy = value
	_apply()


func is_healthy() -> bool:
	return _healthy
