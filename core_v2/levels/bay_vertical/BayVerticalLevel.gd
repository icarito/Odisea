extends Spatial

# Estado de NIVEL de la bahía radial (FD-322). Dueño de:
#   - el payload de retorno a RingHub capturado al entrar (pose del hub a
#     restaurar al salir), por el mismo contrato que `MachineLevel.gd:53`;
#   - los parámetros de la salida seamless (sin fade) hacia RingHub.
#
# La ENTRADA a esta escena la abre `BayVerticalEntryTrigger` (desde RingHub) con
# `target_spawn_id = "bay_vertical_entry"`; este nodo conserva el estado del hub
# para el camino de vuelta, así los buffers de la bahía no dependen de IDs
# inventados en RingHub.

export(String) var ringhub_scene_path := "res://core_v2/levels/RingHub_Level.tscn"
# Anchor de destino en RingHub (el tramo físico del conectador de la bahía). La
# salida transfiere pose/velocidad RELATIVAS a este airlock — no restaura el
# snapshot viejo del jugador.
export(String) var ringhub_airlock_path := "Hub/BayConnector"
export(NodePath) var content_path := NodePath("")
export(NodePath) var entry_buffer_path := NodePath("")
export(NodePath) var exit_buffer_path := NodePath("")
export(NodePath) var mode_console_path := NodePath("")

var _ringhub_return_state: Dictionary = {}

func _init() -> void:
	add_to_group("replay_sync")

func _ready() -> void:
	var sm = get_node_or_null("/root/SceneManager")
	if sm != null and "_transition_params" in sm:
		var params = sm._transition_params
		if typeof(params) == TYPE_DICTIONARY:
			_ringhub_return_state = params.get("ringhub_return_state", {}).duplicate(true)
	# Diferido: la capa de contenido aún no construyó su geometría.
	call_deferred("_wire_buffers")

# Los buffers son el espacio físico de entrada/salida; se anclan a la
# proyección del contenido (entrada en el arranque del recorrido, salida en la
# cima) para que viajen con el cilindro y con el modo.
func _wire_buffers() -> void:
	var content = get_node_or_null(content_path)
	if content == null or not content.has_method("place_projected"):
		return
	var entry = get_node_or_null(entry_buffer_path)
	if entry is Spatial:
		content.call("place_projected", entry, Vector3(0.0, 0.0, 6.0))
	var exit_buf = get_node_or_null(exit_buffer_path)
	if exit_buf is Spatial and content.has_method("get_summit_flat"):
		content.call("place_projected", exit_buf, content.call("get_summit_flat"))
	var console = get_node_or_null(mode_console_path)
	if console is Spatial:
		content.call("place_projected", console, Vector3(0.0, 0.0, -6.0))

func get_ringhub_return_state() -> Dictionary:
	return _ringhub_return_state.duplicate(true)

func has_return_state() -> bool:
	return not _ringhub_return_state.empty()

# Parámetros de salida hacia RingHub. CONSERVA el estado actual del jugador
# (`preserve_player_state = true`: modo, velocidad y orientación de AHORA, no los
# de la entrada) y transfiere pose/velocidad RELATIVAS al buffer de destino
# (`airlock_relative_transform`/`_velocity`, que el buffer completa) contra el
# airlock real del hub. NO restaura el snapshot viejo capturado al entrar.
func build_ringhub_params() -> Dictionary:
	return {
		"preserve_player_state": true,
		"transition": "seamless",
		"fade_out": 0.0,
		"fade_in": 0.0,
		"show_loading": false,
		"wait_for_fade_out": false,
		# El hub no debe repetir el despertar; el resto del estado es el actual.
		"ringhub_return_state": {"wakeup": _ringhub_return_state.get("wakeup", {}).duplicate(true),
			"light_state": _ringhub_return_state.get("light_state", {}).duplicate(true)},
		"state_data": {
			"target_airlock_path": ringhub_airlock_path,
			# Conservar la orientación relativa del jugador (sin re-encarar): la
			# pose relativa ya la aporta el buffer.
			"target_airlock_exit_door": "none",
		},
	}

# ── Replay / save ────────────────────────────────────────────────────────────

func get_snapshot() -> Dictionary:
	return {"ringhub_return_state": _ringhub_return_state.duplicate(true)}

func restore_snapshot(data: Dictionary) -> void:
	if data.has("ringhub_return_state"):
		_ringhub_return_state = data.get("ringhub_return_state", {}).duplicate(true)
