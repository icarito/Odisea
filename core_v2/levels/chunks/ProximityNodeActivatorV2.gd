extends Spatial
# Sin class_name: registrarlo exige que el editor reescriba project.godot.

# FD-320 pulido — activador de cercanía genérico, EN EL LUGAR.
#
# A diferencia de `StreamedSceneChunkV2` (que instancia/libera una escena por
# chunk), este nodo NO crea ni destruye nada: recibe grupos de nodos ya
# construidos ("chunks") con un centro/radio y los activa o desactiva según la
# distancia al jugador. Pensado para contenido que no se puede sacar del árbol
# (máquinas con joints, props con señales ya conectadas, resets de estación).
#
# Desactivar un chunk apaga lo que cuesta: `visible`, colisión y
# process/physics_process de todo su subárbol. Los cuerpos rígidos quedan en
# MODE_STATIC y dormidos, así el solver no los integra. Al reactivar se restaura
# exactamente el estado guardado (ver `_walk` / `_restore`).
#
# Es la pieza reusable que consume la bahía vertical (src-53) y cualquier nivel
# por áreas: la clave de agrupación (station/área) es del llamador, no de este
# nodo.
#
# Uso:
#   var act = ProximityNodeActivatorV2.new()
#   act.player = player
#   parent.add_child(act)
#   act.register_nodes([node_a, node_b], center, radius, margin)
#   ...
#   act.set_enabled(false)  # reactiva todo y deja de vigilar

export(bool) var enabled := true
export(float) var default_radius := 24.0
export(float) var default_release_margin := 8.0
export(NodePath) var player_path := NodePath("")

# Jugador explícito (tests / previews). Si es null se resuelve por grupo/sesión.
var player: Spatial = null

# chunk = {
#   "nodes": Array, "center": Vector3, "radius": float, "margin": float,
#   "active": bool, "saved": {instance_id: {prop: val}}
# }
var _chunks := []


func _ready() -> void:
	set_physics_process(enabled)


func register_nodes(nodes: Array, center: Vector3, radius: float = -1.0, margin: float = -1.0) -> void:
	var clean := []
	for node in nodes:
		if is_instance_valid(node):
			clean.append(node)
	if clean.empty():
		return
	var r := radius if radius > 0.0 else default_radius
	var m := margin if margin >= 0.0 else default_release_margin
	_chunks.append({
		"nodes": clean,
		"center": center,
		"radius": r,
		"margin": m,
		"active": true,
		"saved": {},
	})


func clear_chunks() -> void:
	for chunk in _chunks:
		_activate(chunk, true)
	_chunks.clear()


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		for chunk in _chunks:
			_activate(chunk, true)
	set_physics_process(enabled)


func is_enabled() -> bool:
	return enabled


func get_chunk_count() -> int:
	return _chunks.size()


func get_active_chunk_count() -> int:
	var n := 0
	for chunk in _chunks:
		if bool(chunk["active"]):
			n += 1
	return n


func is_chunk_active(index: int) -> bool:
	if index < 0 or index >= _chunks.size():
		return false
	return bool(_chunks[index]["active"])


# Fuerza un recálculo inmediato (tests / cambio de escena).
func refresh() -> void:
	if not enabled:
		return
	var p := _get_player()
	if p == null:
		return
	_apply_distance(p.global_transform.origin)


func _physics_process(_delta: float) -> void:
	if not enabled or _chunks.empty():
		return
	var p := _get_player()
	if p == null:
		return
	_apply_distance(p.global_transform.origin)


func _apply_distance(pos: Vector3) -> void:
	for chunk in _chunks:
		var dist: float = pos.distance_to(chunk["center"])
		if bool(chunk["active"]):
			if dist > float(chunk["radius"]) + float(chunk["margin"]):
				_activate(chunk, false)
		elif dist <= float(chunk["radius"]):
			_activate(chunk, true)


func _activate(chunk: Dictionary, active: bool) -> void:
	if bool(chunk["active"]) == active:
		return
	if active:
		var saved: Dictionary = chunk["saved"]
		for node in chunk["nodes"]:
			_restore(node, saved)
		chunk["saved"] = {}
	else:
		var saved := {}
		for node in chunk["nodes"]:
			_walk_disable(node, saved)
		chunk["saved"] = saved
	chunk["active"] = active


# Guarda el estado original y apaga. Un nodo que expone `set_stream_active` se
# encarga solo (p. ej. MachinePart respeta su estado de corte); el resto usa el
# criterio genérico.
func _walk_disable(node: Node, saved: Dictionary) -> void:
	if node.has_method("set_stream_active"):
		node.call("set_stream_active", false)
		return
	_save_and_disable(node, saved)
	for child in node.get_children():
		_walk_disable(child, saved)


func _restore(node: Node, saved: Dictionary) -> void:
	if node.has_method("set_stream_active"):
		node.call("set_stream_active", true)
		return
	_restore_node(node, saved)
	for child in node.get_children():
		_restore(child, saved)


func _save_and_disable(node: Node, saved: Dictionary) -> void:
	var key := int(node.get_instance_id())
	var entry := {}
	if node is Spatial:
		entry["visible"] = (node as Spatial).visible
		(node as Spatial).visible = false
	if node is CollisionObject:
		entry["layer"] = node.collision_layer
		entry["mask"] = node.collision_mask
		node.collision_layer = 0
		node.collision_mask = 0
		if node is RigidBody:
			entry["mode"] = node.mode
			node.mode = RigidBody.MODE_STATIC
			node.sleeping = true
	if node is Node:
		entry["p"] = node.is_processing()
		entry["pp"] = node.is_physics_processing()
		if node.is_processing():
			node.set_process(false)
		if node.is_physics_processing():
			node.set_physics_process(false)
	if not entry.empty():
		saved[key] = entry


func _restore_node(node: Node, saved: Dictionary) -> void:
	var key := int(node.get_instance_id())
	if not saved.has(key):
		return
	var entry: Dictionary = saved[key]
	if entry.has("visible"):
		(node as Spatial).visible = bool(entry["visible"])
	if entry.has("layer"):
		node.collision_layer = int(entry["layer"])
		node.collision_mask = int(entry["mask"])
	if entry.has("mode"):
		node.mode = int(entry["mode"])
		node.sleeping = false
	if entry.has("p") and bool(entry["p"]):
		node.set_process(true)
	if entry.has("pp") and bool(entry["pp"]):
		node.set_physics_process(true)


func _get_player() -> Spatial:
	if player != null and is_instance_valid(player):
		return player
	if player_path != NodePath(""):
		player = get_node_or_null(player_path) as Spatial
		return player
	var session = get_node_or_null("/root/SessionManager")
	if session != null and "player" in session and is_instance_valid(session.player):
		player = session.player as Spatial
		return player
	if is_inside_tree():
		var players := get_tree().get_nodes_in_group("player")
		if not players.empty() and is_instance_valid(players[0]):
			player = players[0] as Spatial
	return player
