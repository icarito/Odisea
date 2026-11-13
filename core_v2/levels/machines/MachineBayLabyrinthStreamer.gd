extends Spatial
class_name MachineBayLabyrinthStreamer

# Laberinto industrial procedural STREAMED para la bahía de máquinas (FD-320+).
#
# Genera un campo de scaffold al este de la bahía (fuera del corredor de las 4
# estaciones) en CHUNKS de coordenadas absolutas, usando el generador WFC del repo
# (ScaffoldWFCGenerator / WFCSolverCore vía ScaffoldWFCThreaded) con semilla fija.
#
# Optimización / streaming:
#  - Los chunks se generan e instancian de a poco (presupuesto por frame del worker
#    threaded), solo alrededor del jugador cuando entra a la zona del laberinto.
#  - Costuras deterministas: cada borde compartido fuerza una celda "W" calculada
#    con el mismo hash desde ambos lados, así chunks vecinos siempre coinciden.
#  - Colisiones solo cerca del jugador (capa Prop 64); el resto queda solo visual.
#  - Balizas emisivas en celdas de cruce (T/X/P) para navegación industrial barata
#    (sin OmniLights por celda).
#
# Determinismo: toda la salida deriva de `seed_base` y de la coordenada de chunk;
# no hay RNG en runtime.

const WFC_GENERATOR_SCRIPT := preload("res://core_v2/systems/ScaffoldWFCGenerator.gd")
const THREADED_SCRIPT := preload("res://core_v2/systems/ScaffoldWFCThreaded.gd")

const PROP_COLLISION_LAYER := 64
const PROP_VISUAL_LAYER := 64
const PROP_COLLISION_MASK := 255

const DIR_NORTH := 0
const DIR_EAST := 1
const DIR_SOUTH := 2
const DIR_WEST := 3

const SEAM_ROT_0 := 0
const SEAM_HEIGHT := 0.0

# ── Exports (configurables desde el editor) ──────────────────────────────────

export(int, 4, 16) var chunk_cells := 8
export(float, 2.0, 6.0) var cell_size := 3.0
export(Vector3) var region_origin := Vector3(22.0, 0.0, 26.0)
export(NodePath) var player_path: NodePath = NodePath("")
export(int) var seed_base := 20261114

export(float, 20.0, 200.0) var load_radius := 56.0
export(float, 24.0, 240.0) var unload_radius := 80.0
export(float, 10.0, 60.0) var collision_radius := 26.0
export(float, 0.0, 60.0) var activation_x_min := 18.0
export(int, 1, 16) var max_chunk_requests_per_frame := 2
export(int, 1, 32) var max_pending_jobs := 6

export(bool) var enable_guide_beacons := true
export(bool) var debug_verbose := false

# Pesos WFC (mismos defaults que ScaffoldWFCGenerator)
export(float) var weight_W := 6.0
export(float) var weight_R := 5.0
export(float) var weight_P := 3.0
export(float) var weight_S := 8.0
export(float) var weight_C := 3.0
export(float) var weight_G := 0.5
export(float) var weight_X := 1.0
export(float) var weight_T := 2.0
export(float) var weight_E := 1.8
export(float) var weight_empty := 0.18
export(int, 10, 2000) var max_wfc_retries := 240
export(bool) var require_single_component := true
export(int, 0, 128) var min_non_empty_cells := 8
export(int, 0, 32) var min_stairs_per_map := 0
export(int, 0, 32) var min_elevated_cells := 0
export(int, 0, 32) var min_empty_cells := 0
export(float, 0.0, 20.0) var min_height_span := 0.0
export(bool) var constrain_border_heights := true

# ── Estado ───────────────────────────────────────────────────────────────────

var _threaded: Node = null
var _gen_ref = null
var _active_chunks: Dictionary = {}
var _pending_chunks: Dictionary = {}
var _grid_cache: Dictionary = {}
var _chunk_touched: Dictionary = {}
var _failed_retries: Dictionary = {}
var _last_player_key: Vector2 = Vector2(INF, INF)
var _activated := false

# ── Helpers de coordenadas ───────────────────────────────────────────────────

func _chunk_world_step() -> float:
	return float(chunk_cells) * cell_size

func _key_to_local_origin(key: Vector2) -> Vector3:
	return Vector3(key.x * _chunk_world_step(), 0.0, key.y * _chunk_world_step())

func _key_to_world_center(key: Vector2) -> Vector3:
	return region_origin + _key_to_local_origin(key) + Vector3(_chunk_world_step() * 0.5, 0.0, _chunk_world_step() * 0.5)

func _world_to_key(world_pos: Vector3) -> Vector2:
	var local: Vector3 = world_pos - region_origin
	return Vector2(floor(local.x / _chunk_world_step()), floor(local.z / _chunk_world_step()))

func _stable_hash(a: int, b: int, c: int = 0) -> int:
	var h: int = (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h ^= seed_base * 12345
	return int(h) & 0x7fffffff

func _chunk_seed(key: Vector2) -> int:
	return _stable_hash(int(key.x), int(key.y), 777)

# ── Costuras deterministas ───────────────────────────────────────────────────

# Fuerza una celda "W" plana en cada borde compartido. El índice de la celda se
# deriva de (coordenadas del borde, salt), así los dos chunks vecinos calculan el
# mismo índice y la misma altura.
func _fixed_border_tiles(key: Vector2) -> Dictionary:
	var fixed := {}
	var last: int = chunk_cells - 1
	# NORTH (y=0) del chunk key == SOUTH del chunk (x, y-1)
	var north_x: int = _stable_hash(int(key.x), int(key.y), 101) % chunk_cells
	fixed["%d,0" % north_x] = {"id": "W", "rotation": SEAM_ROT_0, "height": SEAM_HEIGHT}
	# SOUTH (y=last) del chunk key == NORTH del chunk (x, y+1)
	var south_x: int = _stable_hash(int(key.x), int(key.y) + 1, 101) % chunk_cells
	fixed["%d,%d" % [south_x, last]] = {"id": "W", "rotation": SEAM_ROT_0, "height": SEAM_HEIGHT}
	# WEST (x=0) del chunk key == EAST del chunk (x-1, y)
	var west_z: int = _stable_hash(int(key.x), int(key.y), 202) % chunk_cells
	fixed["0,%d" % west_z] = {"id": "W", "rotation": SEAM_ROT_0, "height": SEAM_HEIGHT}
	# EAST (x=last) del chunk key == WEST del chunk (x+1, y)
	var east_z: int = _stable_hash(int(key.x) + 1, int(key.y), 202) % chunk_cells
	fixed["%d,%d" % [last, east_z]] = {"id": "W", "rotation": SEAM_ROT_0, "height": SEAM_HEIGHT}
	return fixed

# ── Ciclo de vida ────────────────────────────────────────────────────────────

func _ready() -> void:
	if Engine.editor_hint:
		return
	_gen_ref = WFC_GENERATOR_SCRIPT.new()
	_gen_ref.grid_width = chunk_cells
	_gen_ref.grid_depth = chunk_cells
	_gen_ref.cell_size = cell_size
	_gen_ref._setup_variants()
	_threaded = THREADED_SCRIPT.new()
	_threaded.instances_per_frame = 8
	_threaded.rebuilds_per_frame = 2
	_threaded.max_pending_jobs = max_pending_jobs
	add_child(_threaded)
	_threaded.connect("generation_done", self, "_on_generation_done")
	_threaded.connect("generation_failed", self, "_on_generation_failed")
	_threaded.connect("instancing_done", self, "_on_instancing_done")
	if debug_verbose:
		print("[MachineBayLabyrinth] ready threads=", _threaded.has_working_threads(), " player=", _get_player())

func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return
	var player := _get_player()
	if debug_verbose:
		print("[MachineBayLabyrinth] phys player=", player, " activated=", _activated)
	if not is_instance_valid(player):
		return
	var world_pos: Vector3 = player.global_transform.origin
	if not _activated:
		if world_pos.x < activation_x_min:
			return
		_activated = true
		if debug_verbose:
			print("[MachineBayLabyrinth] activated at ", world_pos)
	var player_key: Vector2 = _world_to_key(world_pos)
	if player_key != _last_player_key:
		_last_player_key = player_key
		_request_nearby_chunks(player_key)
	_update_collisions_and_unload(world_pos)

func _get_player() -> Spatial:
	if debug_verbose:
		print("[MachineBayLabyrinth] _get_player path=", player_path)
	# player_path opcional (patrón StreamedSceneChunkV2): útil para previews y
	# capturas que quieren dirigir el streaming sin tocar el jugador real.
	if player_path != NodePath(""):
		var target = get_node_or_null(player_path) as Spatial
		if is_instance_valid(target):
			return target
	var session = get_node_or_null("/root/SessionManager")
	if session and "player" in session and is_instance_valid(session.player):
		return session.player as Spatial
	var pilot = get_tree().get_root().find_node("Pilot", true, false)
	if pilot is Spatial:
		return pilot
	return null

func activate_now() -> void:
	_activated = true

# Helper de tooling / capturas: fuerza generación alrededor de un punto del mundo
# sin depender del jugador real (útil para screenshots de iteración visual).
func force_request_around(world_pos: Vector3) -> void:
	_activated = true
	var key := _world_to_key(world_pos)
	_last_player_key = key
	_request_nearby_chunks(key)

# Pre-warm directo de un conjunto de chunks (sin filtro de distancia), útil para
# capturas y para arranque cercano a la entrada del laberinto.
func force_request_keys(keys: Array) -> void:
	_activated = true
	for key in keys:
		if _active_chunks.has(key) or _pending_chunks.has(key):
			continue
		_pending_chunks[key] = true
		_request_chunk(key)

# ── Streaming ────────────────────────────────────────────────────────────────

func _request_nearby_chunks(player_key: Vector2) -> void:
	var radius: int = int(ceil(load_radius / _chunk_world_step())) + 1
	var requested := 0
	var min_key := Vector2(int(player_key.x) - radius, int(player_key.y) - radius)
	var max_key := Vector2(int(player_key.x) + radius, int(player_key.y) + radius)
	for cx in range(int(min_key.x), int(max_key.x) + 1):
		for cz in range(int(min_key.y), int(max_key.y) + 1):
			if requested >= max_chunk_requests_per_frame:
				return
			var key := Vector2(cx, cz)
			if _active_chunks.has(key) or _pending_chunks.has(key):
				continue
			var center: Vector3 = _key_to_world_center(key)
			var dist: float = center.distance_to(_get_player().global_transform.origin)
			if dist > load_radius + _chunk_world_step():
				continue
			_pending_chunks[key] = true
			_request_chunk(key)
			requested += 1
			if debug_verbose:
				print("[MachineBayLabyrinth] req key=", key, " dist=", dist, " pending=", _pending_chunks.size())

func _request_chunk(key: Vector2) -> void:
	var params := _chunk_params(key)
	_threaded.request_grid(key, params)

func _chunk_params(key: Vector2) -> Dictionary:
	return {
		"grid_width": chunk_cells,
		"grid_depth": chunk_cells,
		"cell_size": cell_size,
		"seed": _chunk_seed(key),
		"max_wfc_retries": max_wfc_retries,
		"require_single_component": require_single_component,
		"min_non_empty_cells": min_non_empty_cells,
		"min_stairs_per_map": min_stairs_per_map,
		"min_elevated_cells": min_elevated_cells,
		"min_empty_cells": min_empty_cells,
		"min_height_span": min_height_span,
		"constrain_border_heights": constrain_border_heights,
		"border_presets": {},
		"fixed_border_tiles": _fixed_border_tiles(key),
		"weight_W": weight_W,
		"weight_R": weight_R,
		"weight_P": weight_P,
		"weight_S": weight_S,
		"weight_C": weight_C,
		"weight_G": weight_G,
		"weight_X": weight_X,
		"weight_T": weight_T,
		"weight_E": weight_E,
		"weight_empty": weight_empty,
	}

func _on_generation_done(key, grid: Array) -> void:
	if debug_verbose:
		print("[MachineBayLabyrinth] gen_done key=", key, " cells=", grid.size())
	if not _pending_chunks.has(key):
		return
	_pending_chunks.erase(key)
	if grid.empty():
		return
	if not _active_chunks.has(key):
		var chunk := Spatial.new()
		chunk.name = "MazeChunk_%d_%d" % [int(key.x), int(key.y)]
		chunk.transform = Transform(Basis.IDENTITY, _key_to_local_origin(key))
		add_child(chunk)
		_active_chunks[key] = chunk
	_grid_cache[key] = grid
	var chunk_node: Spatial = _active_chunks[key]
	_threaded.enqueue_grid_for_instancing(chunk_node, grid, chunk_cells, chunk_cells, cell_size, _gen_ref, Vector3.ZERO)

func _on_generation_failed(key) -> void:
	_pending_chunks.erase(key)
	var n: int = int(_failed_retries.get(key, 0))
	if n < 1:
		# Un solo reintento por chunk (la falla suele ser transitoria por
		# restricciones WFC ajustadas; evita huecos permanentes).
		_failed_retries[key] = n + 1
		_pending_chunks[key] = true
		_request_chunk(key)
	else:
		_failed_retries.erase(key)
	if debug_verbose:
		push_warning("[MachineBayLabyrinth] chunk failed: %s (retry=%d)" % [str(key), n])

func _on_instancing_done(parent_node: Spatial) -> void:
	if debug_verbose:
		print("[MachineBayLabyrinth] inst_done key=", _key_for_chunk_node(parent_node))
	if not is_instance_valid(parent_node):
		return
	var key: Vector2 = _key_for_chunk_node(parent_node)
	if key == Vector2(INF, INF):
		return
	_chunk_touched[key] = true
	if _grid_cache.has(key):
		var grid: Array = _grid_cache[key]
		if enable_guide_beacons:
			_add_guide_beacons(parent_node, grid)
		_add_contact_pads(parent_node, grid)
	_grid_cache.erase(key)
	_sync_chunk_collision(parent_node, key)

func _key_for_chunk_node(node: Node) -> Vector2:
	for key in _active_chunks.keys():
		if _active_chunks[key] == node:
			return key
	return Vector2(INF, INF)

func _update_collisions_and_unload(world_pos: Vector3) -> void:
	var to_unload: Array = []
	for key in _active_chunks.keys():
		var chunk_node: Spatial = _active_chunks[key]
		var dist: float = _key_to_world_center(key).distance_to(world_pos)
		if dist > unload_radius:
			to_unload.append(key)
			continue
		_sync_chunk_collision(chunk_node, key)
	for key in to_unload:
		_unload_chunk(key)

func _sync_chunk_collision(chunk_node: Spatial, key: Vector2) -> void:
	if not is_instance_valid(chunk_node):
		return
	# Después de instanciar no hay colisión (los módulos llegan con su capa por
	# defecto); acá la normalizamos a Prop y la apagamos/encendemos según distancia.
	var player := _get_player()
	if not is_instance_valid(player):
		return
	var dist: float = _key_to_world_center(key).distance_to(player.global_transform.origin)
	var enabled: bool = dist <= collision_radius
	_set_collision_enabled(chunk_node, enabled)

func _set_collision_enabled(node: Node, enabled: bool) -> void:
	var layer: int = PROP_COLLISION_LAYER if enabled else 0
	var mask: int = PROP_COLLISION_MASK if enabled else 0
	if node is CollisionObject:
		node.collision_layer = layer
		node.collision_mask = mask
	for child in node.get_children():
		_set_collision_enabled(child, enabled)

func _unload_chunk(key: Vector2) -> void:
	var chunk_node = _active_chunks.get(key)
	if chunk_node != null and is_instance_valid(chunk_node):
		chunk_node.queue_free()
	_active_chunks.erase(key)
	_pending_chunks.erase(key)
	_grid_cache.erase(key)
	_chunk_touched.erase(key)

# ── Balizas emisivas (navegación industrial barata) ──────────────────────────

var _beacon_mat_cache: Dictionary = {}

func _beacon_material(color: Color) -> SpatialMaterial:
	var key: String = "b_%d_%d_%d" % [int(color.r * 255), int(color.g * 255), int(color.b * 255)]
	if _beacon_mat_cache.has(key):
		return _beacon_mat_cache[key]
	var mat := SpatialMaterial.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy = 2.0
	mat.flags_unshaded = true
	_beacon_mat_cache[key] = mat
	return mat

func _add_guide_beacons(chunk_node: Spatial, grid: Array) -> void:
	# Barra vertical delgada + tapa, en vez del bloque chato: se lee como
	# señalización integrada y no como placeholder flotante.
	var bar_mesh := CubeMesh.new()
	bar_mesh.size = Vector3(0.12, 1.6, 0.12)
	var cap_mesh := CubeMesh.new()
	cap_mesh.size = Vector3(0.18, 0.18, 0.18)
	# Rampas: tira baja sobre el suelo en vez de barra alta (no "clavada" en
	# la escalera).
	var strip_mesh := CubeMesh.new()
	strip_mesh.size = Vector3(1.2, 0.06, 0.12)
	# Ámbar de mantenimiento desaturado (no compite con el piso rojo).
	var amber := _beacon_material(Color(1.0, 0.74, 0.38))
	var cool := _beacon_material(Color(0.25, 0.8, 0.95))
	for i in range(grid.size()):
		var state = grid[i]
		if state == null:
			continue
		var v = _state_variant(state)
		var vid: String = _variant_id(v)
		if vid != "X" and vid != "T" and vid != "P" and vid != "S":
			continue
		var x: int = i % chunk_cells
		var z: int = i / chunk_cells
		var alt: bool = (int(x) + int(z)) % 4 == 0 and vid != "S"
		var mat: SpatialMaterial = cool if alt else amber
		var base_y: float = _state_base_height(state)
		var cx: float = x * cell_size
		var cz: float = z * cell_size
		if vid == "S":
			var strip := MeshInstance.new()
			strip.mesh = strip_mesh
			strip.material_override = mat
			strip.translation = Vector3(cx, base_y + 0.1, cz)
			strip.rotation_degrees.y = float(_variant_rotation(v))
			strip.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
			strip.add_to_group("no_occlusion")
			chunk_node.add_child(strip)
			continue
		var mi := MeshInstance.new()
		mi.mesh = bar_mesh
		mi.material_override = mat
		mi.translation = Vector3(cx, base_y + 0.9, cz)
		mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		mi.add_to_group("no_occlusion")
		chunk_node.add_child(mi)
		var cap := MeshInstance.new()
		cap.mesh = cap_mesh
		cap.material_override = mat
		cap.translation = mi.translation + Vector3(0.0, 0.9, 0.0)
		cap.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		cap.add_to_group("no_occlusion")
		chunk_node.add_child(cap)

# ── Zapatas de contacto (anclaje visual al piso) ──────────────────────────────

var _pad_mat_cache: Dictionary = {}

func _pad_material() -> SpatialMaterial:
	if _pad_mat_cache.has("pad"):
		return _pad_mat_cache["pad"]
	var mat := SpatialMaterial.new()
	mat.albedo_color = Color(0.1, 0.12, 0.14, 1.0)
	mat.roughness = 0.5
	mat.metallic = 0.6
	_pad_mat_cache["pad"] = mat
	return mat

func _add_contact_pads(chunk_node: Spatial, grid: Array) -> void:
	# Zapatas oscuras en las 4 esquinas de cada celda ocupada (donde apoyan las
	# patas del scaffold): dan peso visual y disimulan el corte contra el piso
	# sin costar luces ni sombras reales (low-cost).
	var pad_half := cell_size * 0.34
	var pad_size := pad_half * 2.0
	var pad_mesh := CubeMesh.new()
	pad_mesh.size = Vector3(pad_size, 0.05, pad_size)
	var mat := _pad_material()
	var transforms: Array = []
	var offs: Array = [
		Vector3(-pad_half, 0.0, -pad_half),
		Vector3(pad_half, 0.0, -pad_half),
		Vector3(-pad_half, 0.0, pad_half),
		Vector3(pad_half, 0.0, pad_half)
	]
	for i in range(grid.size()):
		var state = grid[i]
		if state == null:
			continue
		var v = _state_variant(state)
		var vid: String = _variant_id(v)
		if vid == "" or vid == "EMPTY":
			continue
		var x: int = i % chunk_cells
		var z: int = i / chunk_cells
		var cx: float = x * cell_size
		var cz: float = z * cell_size
		for off in offs:
			transforms.append(Transform(Basis.IDENTITY, Vector3(cx + off.x, 0.06, cz + off.z)))
	if transforms.empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = pad_mesh
	mm.instance_count = transforms.size()
	var buf := PoolRealArray()
	buf.resize(transforms.size() * 12)
	var idx := 0
	for xf in transforms:
		buf[idx]     = 1.0; buf[idx+1]  = 0.0; buf[idx+2]  = 0.0; buf[idx+3]  = xf.origin.x
		buf[idx+4]   = 0.0; buf[idx+5]  = 1.0; buf[idx+6]  = 0.0; buf[idx+7]  = xf.origin.y
		buf[idx+8]   = 0.0; buf[idx+9]  = 0.0; buf[idx+10] = 1.0; buf[idx+11] = xf.origin.z
		idx += 12
	mm.set_as_bulk_array(buf)
	var inst := MultiMeshInstance.new()
	inst.name = "ContactPads"
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	inst.add_to_group("no_occlusion")
	chunk_node.add_child(inst)

func _state_variant(state):
	if typeof(state) == TYPE_DICTIONARY:
		return state.get("variant", null)
	if state == null:
		return null
	return state.variant

func _variant_id(v) -> String:
	if v == null:
		return ""
	if typeof(v) == TYPE_DICTIONARY:
		return String(v.get("id", ""))
	return v.id

func _variant_rotation(v) -> int:
	if v == null:
		return 0
	if typeof(v) == TYPE_DICTIONARY:
		return int(v.get("rotation", 0))
	return v.rotation

func _state_base_height(state) -> float:
	if typeof(state) == TYPE_DICTIONARY:
		return float(state.get("base_height", 0.0))
	return 0.0

# ── Getters para tests / depuración ──────────────────────────────────────────

func get_active_chunk_keys() -> Array:
	var out: Array = []
	for key in _active_chunks.keys():
		out.append(key)
	return out

func get_pending_chunk_keys() -> Array:
	var out: Array = []
	for key in _pending_chunks.keys():
		out.append(key)
	return out

func is_activated() -> bool:
	return _activated

func get_entry_world_position() -> Vector3:
	# Celda de entrada: primera celda del chunk (0,0) en su borde oeste.
	var origin: Vector3 = region_origin
	return origin + Vector3(cell_size * 0.5, 0.0, cell_size * 0.5)

func get_chunk_grid(key: Vector2) -> Array:
	return _grid_cache.get(key, [])

func get_fixed_border_tiles(key: Vector2) -> Dictionary:
	return _fixed_border_tiles(key)

# Devuelve la celda fija de un borde concreto, sin ambigüedad (filas/columnas
# pueden coincidir entre bordes). side: "n"|"s"|"e"|"w".
func get_boundary_tile(key: Vector2, side: String) -> Dictionary:
	var last: int = chunk_cells - 1
	match side:
		"n":
			var nx: int = _stable_hash(int(key.x), int(key.y), 101) % chunk_cells
			return {"col": nx, "row": 0, "spec": {"id": "W", "rotation": SEAM_ROT_0, "height": SEAM_HEIGHT}}
		"s":
			var sx: int = _stable_hash(int(key.x), int(key.y) + 1, 101) % chunk_cells
			return {"col": sx, "row": last, "spec": {"id": "W", "rotation": SEAM_ROT_0, "height": SEAM_HEIGHT}}
		"w":
			var wz: int = _stable_hash(int(key.x), int(key.y), 202) % chunk_cells
			return {"col": 0, "row": wz, "spec": {"id": "W", "rotation": SEAM_ROT_0, "height": SEAM_HEIGHT}}
		"e":
			var ez: int = _stable_hash(int(key.x) + 1, int(key.y), 202) % chunk_cells
			return {"col": last, "row": ez, "spec": {"id": "W", "rotation": SEAM_ROT_0, "height": SEAM_HEIGHT}}
	return {}
