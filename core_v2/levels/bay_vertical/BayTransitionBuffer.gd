extends Spatial

# Buffer de transición FÍSICO de la bahía radial (FD-322).
#
# Requisito de Sebastián (2026-11-14): las transiciones deben ser completamente
# seamless, sin fade a negro; la referencia es el airlock. La entrada (planta) y
# la salida (sala de control, cima) de la bahía son un ESPACIO BUFFER FÍSICO
# (airlock/ascensor) que USA la API seamless de `SceneManager`/`AirlockManager`
# (`.operator-shared/specs/seamless-transitions.md`): arma el lift
# (`notify_transition`), pide `transition: "seamless"` y dispara el swap.
#
# El destino es un destino REAL: la SALIDA hacia RingHub restaura la pose del hub
# capturada al entrar (`BayVerticalLevel.build_ringhub_params`), por el mismo
# camino sin airlock que RingHub <-> MachineBay. No hay IDs de spawn inventados.

enum Kind { ENTRY = 0, EXIT = 1, ELEVATOR = 2 }

export(Kind) var kind := Kind.ENTRY
export(String) var target_scene := ""
export(String) var buffer_id := ""
export(bool) var exchange_zone := true
export(Vector3) var chamber_size := Vector3(3.0, 3.0, 3.0)
# Opcional: nodo de nivel que aporta los parámetros de salida reales
# (`build_ringhub_params()`); si está, se usa ese camino.
export(NodePath) var level_path := NodePath("")

var _zone: Area = null
var _level: Node = null

signal transition_requested(buffer_id, target_scene)

var _transitioning := false

func _ready() -> void:
	_build_chamber()
	if exchange_zone:
		_build_exchange_zone()

func _build_chamber() -> void:
	# Carcasa física: piso, paredes y techo con un vano. Es el "espacio buffer" real
	# por el que entra y sale el jugador, no un fade.
	var shell := StaticBody.new()
	shell.name = "Chamber"
	shell.collision_layer = 1
	shell.collision_mask = 255
	add_child(shell)

	var half := chamber_size * 0.5
	var wall_mat := SpatialMaterial.new()
	wall_mat.albedo_color = Color(0.16, 0.19, 0.23, 1.0)
	wall_mat.metallic = 0.4
	wall_mat.roughness = 0.6

	_add_wall(shell, wall_mat, Vector3(half.x, half.y, 0.0), Vector3(0.15, half.y, half.z))
	_add_wall(shell, wall_mat, Vector3(-half.x, half.y, 0.0), Vector3(0.15, half.y, half.z))
	_add_wall(shell, wall_mat, Vector3(0.0, half.y, half.z), Vector3(half.x, half.y, 0.15))
	_add_wall(shell, wall_mat, Vector3(0.0, 0.0, -half.z), Vector3(half.x, 0.15, 0.15))
	_add_wall(shell, wall_mat, Vector3(0.0, chamber_size.y, 0.0), Vector3(half.x, 0.15, half.z))
	# Piso (el jugador ya llega por el scaffold, pero el buffer tiene piso propio).
	_add_wall(shell, wall_mat, Vector3(0.0, 0.0, 0.0), Vector3(half.x, 0.1, half.z))

func _add_wall(parent: Node, mat: SpatialMaterial, pos: Vector3, extents: Vector3) -> void:
	var mi := MeshInstance.new()
	var cube := CubeMesh.new()
	cube.size = extents * 2.0
	mi.mesh = cube
	mi.translation = pos
	mi.material_override = mat
	parent.add_child(mi)
	var col := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = extents
	col.shape = box
	col.translation = pos
	parent.add_child(col)

func _build_exchange_zone() -> void:
	_zone = Area.new()
	_zone.name = "ExchangeZone"
	_zone.collision_layer = 0
	_zone.collision_mask = 2  # jugador
	_zone.monitoring = true
	var col := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = Vector3(chamber_size.x * 0.45, chamber_size.y * 0.45, chamber_size.z * 0.45)
	col.shape = box
	_zone.add_child(col)
	add_child(_zone)
	_zone.connect("body_entered", self, "_on_body_entered")

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	request_seamless_transition(body)

# Transición SEAMLESS real (sin fade): mismo camino que `AirlockZoneV2` —
# `AirlockManager.notify_transition()` levanta al jugador antes del swap y
# SceneManager hace add-before-free. NO se usa un fade a negro.
func request_seamless_transition(player: Node) -> void:
	if _transitioning:
		return
	if target_scene.strip_edges() == "":
		printerr("[BayTransitionBuffer:%s] target_scene vacío; no hay destino de %s" % [buffer_id, ("salida" if kind == Kind.EXIT else "entrada")])
		return
	_transitioning = true
	emit_signal("transition_requested", buffer_id, target_scene)

	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager == null or not scene_manager.has_method("goto_scene"):
		printerr("[BayTransitionBuffer:%s] SceneManager ausente" % buffer_id)
		_transitioning = false
		return

	var params := {}
	var state_data := _build_state_data(player)
	if _has_level_return_target():
		# Destino REAL (hub): conserva el estado ACTUAL y transfiere pose/velocidad
		# RELATIVAS al airlock de destino; no se restaura ningún snapshot viejo.
		params = _level.call("build_ringhub_params")
		var merged: Dictionary = params.get("state_data", {})
		for key in state_data.keys():
			merged[key] = state_data[key]
		params["state_data"] = merged
	else:
		# Fallback relativo (destino con airlock espejo): conserva pose/velocidad
		# relativas al buffer como AirlockZoneV2.
		params = {
			"transition": "seamless",
			"transition_style": "airlock",
			"preserve_player_state": true,
			"fade_out": 0.0,
			"fade_in": 0.0,
			"show_loading": false,
			"wait_for_fade_out": false,
			"spawn_id": buffer_id,
			"target_spawn_id": buffer_id,
		}
		if not state_data.empty():
			params["state_data"] = state_data

	var airlock_manager = get_node_or_null("/root/AirlockManager")
	if airlock_manager != null and airlock_manager.has_method("notify_transition"):
		airlock_manager.notify_transition(target_scene)

	if OS.is_debug_build():
		print("[BayTransitionBuffer:%s] seamless -> %s" % [buffer_id, target_scene])
	scene_manager.goto_scene(target_scene, params)

func _has_level_return_target() -> bool:
	if _level == null or not is_instance_valid(_level):
		_level = get_node_or_null(level_path) if not level_path.is_empty() else null
	return _level != null and _level.has_method("build_ringhub_params") \
		and (not _level.has_method("has_return_state") or bool(_level.call("has_return_state")))

func _build_state_data(player: Node) -> Dictionary:
	var state_data := {}
	if not is_instance_valid(player):
		return state_data
	if player.has_method("get_full_snapshot"):
		var snapshot = player.get_full_snapshot()
		if typeof(snapshot) == TYPE_DICTIONARY:
			var clean: Dictionary = snapshot.duplicate(true)
			for key in ["pos", "position", "global_position", "origin"]:
				if clean.has(key):
					clean[key] = Vector3.ZERO
			for key in ["vel", "velocity", "linear_velocity"]:
				if clean.has(key):
					clean[key] = Vector3.ZERO
			state_data["player_snapshot"] = clean
	if player is Spatial:
		# Marco del buffer: mismas claves que AirlockZoneV2 para que SceneManager
		# restaure posición/velocidad relativas y el jugador NO pierda el movimiento.
		var frame: Transform = global_transform
		var player_xf: Transform = (player as Spatial).global_transform
		var relative: Transform = frame.affine_inverse() * player_xf
		state_data["airlock_relative_position"] = relative.origin
		state_data["airlock_relative_transform"] = relative
		if "yaw" in player:
			state_data["camera_yaw"] = float(player.yaw)
			state_data["camera_body_yaw_offset"] = float(player.yaw) - player_xf.basis.get_euler().y
		if "pitch" in player:
			state_data["camera_pitch"] = float(player.pitch)
		# Velocidad RELATIVA preservada (el snapshot base la cero para que el spawn
		# la aplique; el momentum viaja por acá, como en AirlockZoneV2).
		if "velocity" in player:
			var velocity: Vector3 = player.velocity
			var relative_velocity: Vector3 = frame.basis.xform_inv(velocity)
			if float(velocity.y) < -1.0:
				relative_velocity.y = 0.0
			state_data["airlock_relative_velocity"] = relative_velocity
	return state_data

func is_buffer() -> bool:
	return true

func get_kind() -> int:
	return kind
