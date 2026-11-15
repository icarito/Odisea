extends Spatial
class_name BayVerticalWell

# Pozo radial vertical de 3 niveles (FD-322): generador sembrado + instanciación
# + streaming por cercanía + atajos + peligro sincronizado con el ciclo global.
#
# Reusa `ScaffoldMSTGenerator` y los módulos de `core_v2/props/scaffold/` con
# proyección polar (mismo principio que FD-052 v3 y `ScaffoldOrbit`):
#   Grid X → ángulo θ (circunferencial, wrap_x)
#   Grid Y → radio r
#   base_height → altitud Y (vertical)
#
# Determinismo: toda la salida deriva de `generation_seed` (RandomNumberGenerator
# sembrado por el generador MST; sin randf global ni frames_drawn). El estado es
# serializable (`get_snapshot`/`restore_snapshot`) para replay y save: la semilla
# se guarda en el save y se reintroduce con `set_seed_from_save`.
#
# Streaming: los chunks se agrupan por cuadrante angular × nivel. El activador por
# cercanía es LOCAL y deliberadamente mínimo; el punto de enganche para el
# activador genérico de src-51 es `_call_proximity_activator` (TODO src-51).

const MSTGeneratorScript := preload("res://core_v2/systems/ScaffoldMSTGenerator.gd")
const CycleScript := preload("res://core_v2/levels/bay_vertical/BayProtocolCycle.gd")
const TransitionBufferScript := preload("res://core_v2/levels/bay_vertical/BayTransitionBuffer.gd")
const ModeConsoleScript := preload("res://core_v2/levels/bay_vertical/BayModeConsole.gd")
# Modos de gravedad (GravityModes.Mode): 0 STANDARD_1G (propulsión), 1 SPIN_WALKABLE
# (centrífugo), 2 ZERO_G. No importamos el script para no acoplar; se leen/escriben
# por GravityWorld y por int.
const GRAVITY_MODE_THRUST := 0
const GRAVITY_MODE_SPIN := 1
const ConveyorScene := preload("res://core_v2/props/machinery/Conveyor.tscn")
const LaserGateScript := preload("res://core_v2/levels/bay_vertical/LaserGate.gd")
const GlooSpanScript := preload("res://core_v2/levels/bay_vertical/GlooSpan.gd")
const PushableBoxScene := preload("res://core_v2/components/PushableBoxV2.tscn")

const MODULES := {
	"W": preload("res://core_v2/props/scaffold/ScaffoldWalkway.tscn"),
	"R": preload("res://core_v2/props/scaffold/ScaffoldRailing.tscn"),
	"P": preload("res://core_v2/props/scaffold/ScaffoldPlatform.tscn"),
	"S": preload("res://core_v2/props/scaffold/ScaffoldStairs.tscn"),
	"C": preload("res://core_v2/props/scaffold/ScaffoldCurve.tscn"),
	"G": preload("res://core_v2/props/scaffold/ScaffoldGap.tscn"),
	"X": preload("res://core_v2/props/scaffold/ScaffoldCross.tscn"),
	"T": preload("res://core_v2/props/scaffold/ScaffoldTJunction.tscn"),
	"E": preload("res://core_v2/props/scaffold/ScaffoldEnd.tscn"),
}

enum Direction { NORTH = 0, EAST = 1, SOUTH = 2, WEST = 3 }
const DIR_VEC := {
	Direction.NORTH: Vector2(0, -1),
	Direction.EAST: Vector2(1, 0),
	Direction.SOUTH: Vector2(0, 1),
	Direction.WEST: Vector2(-1, 0),
}
const OPPOSITE := {
	Direction.NORTH: Direction.SOUTH,
	Direction.SOUTH: Direction.NORTH,
	Direction.EAST: Direction.WEST,
	Direction.WEST: Direction.EAST,
}

const HEIGHT_STEP := 2.0
# Bandas de altitud para los 3 niveles.
const LEVEL_BAND_0 := 4.0
const LEVEL_BAND_1 := 8.0
const PROP_COLLISION_LAYER := 64
const PROP_COLLISION_MASK := 255

# ── Exports ──────────────────────────────────────────────────────────────────

export(int) var generation_seed := 20261114
export(int, 6, 32) var sectors := 16
export(int, 2, 8) var rings := 3
export(float, 2.0, 8.0) var cell_size := 4.5
export(float, 2.0, 20.0) var inner_radius := 6.0
export(float, 1.0, 8.0) var ring_step := 3.0
export(int, 1, 6) var max_height_steps := 6
export(int, 0, 6) var extra_cycles := 2
export(int, 2, 12) var room_count := 6

export(bool) var enable_streaming := true
export(float, 2.0, 40.0) var load_radius := 12.0
export(float, 8.0, 60.0) var unload_radius := 22.0
export(float, 2.0, 30.0) var collision_radius := 9.0
export(int, 1, 64) var max_cells_per_frame := 8

export(bool) var enable_conveyor_shortcut := true
export(bool) var enable_laser_gate := true
export(bool) var enable_gloo_span := true
export(bool) var enable_hazard_rotor := true
export(bool) var enable_mode_console := true
export(int) var initial_gravity_mode := GRAVITY_MODE_SPIN

export(float) var conveyor_speed := 4.0
export(float) var laser_gate_cut_time := 2.5
export(int) var gloo_span_required_blobs := 2
export(float) var rotor_angular_speed := 1.8

export(bool) var debug_verbose := false

# ── Estado ───────────────────────────────────────────────────────────────────

var _generated := false
var _layout: Dictionary = {}          # salida de _generate_layout
var _chunks: Dictionary = {}          # "q_b" -> Spatial
var _chunk_meta: Dictionary = {}      # "q_b" -> {center: Vector3, cells: Array}
var _pending_chunks: Dictionary = {}  # "q_b" -> true
var _pending_cells: Array = []        # celdas por instanciar (streaming)
var _cycle: Node = null                # BayProtocolCycle
var _shortcuts: Array = []            # nodos de atajo
var _rotor: Spatial = null            # peligro (rotor)
var _rotor_angle := 0.0
var _rotor_active := false
var _entry_cell_idx := -1
var _summit_cell_idx := -1
var _summit_world := Vector3.ZERO
var _entry_world := Vector3.ZERO
var _host_world := {}                 # "ca", "cb0", "cb1", "cg0", "cg1" -> Vector3
var _gravity_mode := GRAVITY_MODE_SPIN
var _gravity_blend := 1.0
var _mode_consoles: Array = []
var _mode_bridge: StaticBody = null
var _gravity_world: Node = null

func _init() -> void:
	add_to_group("replay_sync")

func _ready() -> void:
	if Engine.editor_hint:
		return
	_ensure_cycle()
	_regen()
	_cycle.connect("phase_changed", self, "_on_phase_changed")

# ── Ciclo global (se asegura uno propio) ─────────────────────────────────────

func _ensure_cycle() -> void:
	for child in get_children():
		if child.get_script() == CycleScript:
			_cycle = child
			return
	var cycle := CycleScript.new()
	cycle.name = "BayProtocolCycle"
	add_child(cycle)
	_cycle = cycle

func get_cycle() -> Node:
	return _cycle

func _on_phase_changed(phase: int) -> void:
	_apply_phase_to_shortcuts(phase)

# ── Regeneración ─────────────────────────────────────────────────────────────

func _regen() -> void:
	if _generated and not _chunks.empty():
		_clear_instances()
	_layout = generate_layout(generation_seed)
	if _layout.empty():
		push_error("[BayVerticalWell] layout vacío (seed=%d)" % generation_seed)
		return
	_entry_cell_idx = int(_layout.get("entry_idx", -1))
	_summit_cell_idx = int(_layout.get("summit_idx", -1))
	_entry_world = _layout.get("entry_world", Vector3.ZERO)
	_summit_world = _layout.get("summit_world", Vector3.ZERO)
	_host_world = _layout.get("host_world", {})
	_build_fall_floor()
	_build_summit_beacon()
	_build_control_room()
	_build_transition_buffers()
	_reposition_spawn_point()
	if enable_streaming:
		# Los chunks entran por cercanía (ver _physics_process).
		pass
	else:
		_instance_all_chunks()
	_spawn_shortcuts()
	_spawn_mode_gate()
	_spawn_mode_consoles()
	_spawn_hazard()
	_apply_gravity_mode(false)
	_generated = true

func _clear_instances() -> void:
	for key in _chunks.keys():
		var c: Spatial = _chunks[key]
		if is_instance_valid(c):
			c.queue_free()
	_chunks.clear()
	_chunk_meta.clear()
	_pending_chunks.clear()
	_pending_cells.clear()
	for shortcut in _shortcuts:
		if is_instance_valid(shortcut):
			shortcut.queue_free()
	_shortcuts.clear()
	if is_instance_valid(_rotor):
		_rotor.queue_free()
	_rotor = null
	# Anclas dependientes de la semilla (entrada/cima) se reconstruyen.
	for n in ["SummitBeacon", "ControlRoom", "EntryBuffer", "ExitBuffer", "ModeBridge"]:
		var node = get_node_or_null(n)
		if node and is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	_mode_bridge = null
	for console in _mode_consoles:
		if is_instance_valid(console):
			console.queue_free()
	_mode_consoles.clear()

# ── Generación de layout (pura, sin nodos) ───────────────────────────────────

func _stable_hash(sd: int, a: int, b: int, c: int) -> int:
	# Mezcla determinista (GDScript 1 no tiene operador ^ / XOR).
	var h: int = sd * 1000003 + a * 73856093 + b * 19349663 + c * 83492791
	h = (h * (h + 17)) & 0x7fffffff
	return h

func _host_seams(seed_val: int) -> Dictionary:
	var seams := {}
	# Sector de entrada (hash estable de la semilla). Los anclajes de atajos y la
	# cima son OFFSETS fijos desde la entrada: sectores siempre distintos y
	# deterministas por semilla.
	var cx_e: int = _stable_hash(seed_val, 1, 101, 0) % sectors
	seams["%d,0" % cx_e] = {"id": "W", "rotation": 0, "height": 0.0}
	var ca: int = (cx_e + 4) % sectors
	seams["%d,0" % ca] = {"id": "W", "rotation": 0, "height": 0.0}
	seams["%d,2" % ca] = {"id": "W", "rotation": 0, "height": 4.0}
	var cb: int = (cx_e + 8) % sectors
	seams["%d,1" % cb] = {"id": "W", "rotation": 0, "height": 6.0}
	seams["%d,1" % ((cb + 1) % sectors)] = {"id": "W", "rotation": 0, "height": 6.0}
	var cg: int = (cx_e + 12) % sectors
	seams["%d,1" % cg] = {"id": "W", "rotation": 0, "height": 2.0}
	seams["%d,1" % ((cg + 1) % sectors)] = {"id": "W", "rotation": 0, "height": 2.0}
	var cs: int = (cx_e + 2) % sectors
	seams["%d,2" % cs] = {"id": "W", "rotation": 0, "height": 8.0}
	return seams

func generate_layout(seed_val: int) -> Dictionary:
	var gen = MSTGeneratorScript.new()
	var seams := _host_seams(seed_val)
	gen.apply_params({
		"grid_width": sectors,
		"grid_depth": rings,
		"cell_size": cell_size,
		"wrap_x": true,
		"mst_max_height_steps": max_height_steps,
		"mst_min_height_steps": 1,
		"room_count": room_count,
		"extra_cycles": extra_cycles,
		"fixed_border_tiles": seams,
	})
	var data: Array = gen.generate_grid_data(seed_val)
	if data.empty():
		push_warning("[BayVerticalWell] generación vacía (seed=%d)" % seed_val)
		return {}

	var cells := []
	var idx_data := {}
	var summit_h := -1.0
	var natural_summit_idx := -1

	for i in range(data.size()):
		var state = data[i]
		if state == null:
			continue
		var cx: int = i % sectors
		var cy: int = i / sectors
		var v = state.get("variant", null)
		if v == null:
			continue
		var vid: String = _variant_id(v)
		if vid == "" or vid == "EMPTY":
			continue
		var h: float = float(state.get("base_height", 0.0))
		var xf: Transform = _cell_world_transform(cx, cy, h)
		var lvl: int = level_of(h)
		var cell := {
			"idx": i,
			"cx": cx,
			"cy": cy,
			"vid": vid,
			"rotation": _variant_rotation(v),
			"connections": _variant_connections(v),
			"port_heights": _variant_port_heights(v),
			"base_height": h,
			"world": xf,
			"level": lvl,
		}
		cells.append(cell)
		idx_data[i] = cell
		if h > summit_h + 0.001:
			summit_h = h
			natural_summit_idx = i

	# Forzar las anclas pinnadas (atajos y cima) sobre el layout generado: el MST
	# puede elegir otra variante/altura local; acá garantizamos la celda plana
	# W a la altura pedida, que es lo que consumen los atajos y la cima.
	for key in seams.keys():
		var parts: Array = String(key).split(",")
		if parts.size() < 2:
			continue
		var cx := int(parts[0])
		var cy := int(parts[1])
		var idx := cy * sectors + cx
		var h: float = float(seams[key].get("height", 0.0))
		if idx_data.has(idx):
			var cell: Dictionary = idx_data[idx]
			cell["vid"] = "W"
			cell["rotation"] = 0
			# Conservamos las conexiones originales del MST (reflejan la adyacencia
			# real y preservan la conectividad del grafo de caminata).
			cell["base_height"] = h
			cell["world"] = _cell_world_transform(cx, cy, h)
			cell["level"] = level_of(h)

	# Resolver entrada, hosts y cima sobre las celdas ya forzadas.
	var cx_e: int = _stable_hash(seed_val, 1, 101, 0) % sectors
	var entry_idx := -1
	var summit_idx := -1
	var entry_world := Vector3.ZERO
	var summit_world := Vector3.ZERO
	var host_world := {}
	for key in seams.keys():
		var parts: Array = String(key).split(",")
		if parts.size() < 2:
			continue
		var cx := int(parts[0])
		var cy := int(parts[1])
		var idx := cy * sectors + cx
		var h: float = float(seams[key].get("height", 0.0))
		var origin := _cell_world_transform(cx, cy, h).origin
		if cy == 0 and cx == cx_e:
			entry_idx = idx
			entry_world = origin
		elif cy == 0 and cx == (cx_e + 4) % sectors:
			host_world["ca0"] = origin
		elif cy == 2 and cx == (cx_e + 4) % sectors:
			host_world["ca2"] = origin
		elif cy == 1 and cx == (cx_e + 8) % sectors:
			host_world["cb0"] = origin
		elif cy == 1 and cx == (cx_e + 9) % sectors:
			host_world["cb1"] = origin
		elif cy == 1 and cx == (cx_e + 12) % sectors:
			host_world["cg0"] = origin
		elif cy == 1 and cx == (cx_e + 13) % sectors:
			host_world["cg1"] = origin
		elif cy == 2 and cx == (cx_e + 2) % sectors:
			summit_idx = idx
			summit_world = origin

	if summit_idx < 0:
		# Fallback: cima natural (máxima altura) si la ancla pinnada no existiera.
		summit_idx = natural_summit_idx
		if idx_data.has(summit_idx):
			summit_world = idx_data[summit_idx]["world"].origin

	return {
		"seed": seed_val,
		"sectors": sectors,
		"rings": rings,
		"cells": cells,
		"entry_idx": entry_idx,
		"summit_idx": summit_idx,
		"entry_world": entry_world,
		"summit_world": summit_world,
		"host_world": host_world,
	}

func level_of(h: float) -> int:
	if h < LEVEL_BAND_0:
		return 0
	if h < LEVEL_BAND_1:
		return 1
	return 2

func _cell_world_transform(cx: int, cy: int, base_height: float) -> Transform:
	var angle: float = TAU * float(cx) / float(sectors)
	var radius: float = inner_radius + float(cy) * ring_step
	var pos := Vector3(radius * cos(angle), base_height, radius * sin(angle))
	var tangent := Vector3(-sin(angle), 0.0, cos(angle))
	var radial := Vector3(cos(angle), 0.0, sin(angle))
	return Transform(Basis(tangent, Vector3.UP, radial), pos)

# ── Instanciación de módulos ────────────────────────────────────────────────

func _instance_all_chunks() -> void:
	# Agrupar celdas por chunk y crear cada chunk de una vez.
	var groups := {}
	for cell in _layout.get("cells", []):
		var key := _chunk_key(cell)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(cell)
	for key in groups.keys():
		var chunk := _make_chunk_node(key)
		for cell in groups[key]:
			_instance_cell_into(chunk, cell)
		_finalize_chunk(chunk, key)

func _chunk_key(cell: Dictionary) -> String:
	var q: int = int(cell["cx"]) * 4 / int(_layout.get("sectors", sectors))
	q = clamp(q, 0, 3)
	var b: int = int(cell["level"])
	return "%d_%d" % [q, b]

func _make_chunk_node(key: String) -> Spatial:
	if _chunks.has(key) and is_instance_valid(_chunks[key]):
		return _chunks[key]
	var chunk := Spatial.new()
	chunk.name = "WellChunk_%s" % key
	add_child(chunk)
	_chunks[key] = chunk
	_chunk_meta[key] = {"center": Vector3.ZERO, "cells": []}
	return chunk

func _instance_cell_into(chunk: Spatial, cell: Dictionary) -> void:
	var vid: String = cell["vid"]
	if not MODULES.has(vid):
		return
	var inst = MODULES[vid].instance()
	chunk.add_child(inst)
	var xf: Transform = cell["world"]
	var deck_local_y: float = float(inst.platform_height) if "platform_height" in inst else 0.0
	var base_height: float = cell["base_height"]
	var t := xf
	t.origin.y = base_height - deck_local_y
	inst.transform = t
	inst.rotate_object_local(Vector3.UP, deg2rad(-float(cell["rotation"])))
	inst.set("support_base_local_y", deck_local_y - base_height)
	_apply_module_dims(inst, cell)
	if inst.has_method("_rebuild"):
		inst.call("_rebuild")

func _apply_module_dims(inst, cell: Dictionary) -> void:
	var vid: String = cell["vid"]
	var v := {
		"id": vid,
		"rotation": cell["rotation"],
		"connections": cell["connections"],
		"port_heights": cell["port_heights"],
	}
	var lane: float = _lane_width()
	match vid:
		"W", "R", "G":
			_apply_local_dims(inst, lane, cell_size)
			_apply_rails_from_connections(inst, v)
			_apply_opening_widths_from_connections(inst, v)
		"P":
			_apply_local_dims(inst, cell_size, cell_size)
			_apply_rails_from_connections(inst, v)
			_apply_opening_widths_from_connections(inst, v)
		"S":
			_apply_local_dims(inst, lane, cell_size)
			_apply_port_heights_to_front_back(inst, v)
			_apply_rails_from_connections(inst, v)
			_apply_opening_widths_from_connections(inst, v)
		_:
			_apply_local_dims(inst, cell_size, cell_size)
			_apply_rails_from_connections(inst, v)
			_apply_opening_widths_from_connections(inst, v)

func _lane_width() -> float:
	return clamp(cell_size * 0.32, 2.5, 4.5)

func _finalize_chunk(chunk: Spatial, key: String) -> void:
	var cells: Array = _chunk_meta[key]["cells"] if _chunk_meta.has(key) else []
	var center := Vector3.ZERO
	if not cells.empty():
		for c in cells:
			center += c["world"].origin
		center /= float(cells.size())
	_chunk_meta[key] = {"center": center, "cells": cells}

# ── Streaming por cercanía (mínimo local; gancho para src-51) ────────────────

func _physics_process(delta: float) -> void:
	if Engine.editor_hint or not _generated:
		return
	if enable_streaming:
		var player := _get_player()
		if is_instance_valid(player):
			_update_streaming(player.global_transform.origin)
	_update_hazard(delta)

func _get_player() -> Spatial:
	var session = get_node_or_null("/root/SessionManager")
	if session and "player" in session and is_instance_valid(session.player):
		return session.player as Spatial
	var pilot = get_tree().get_root().find_node("Pilot", true, false)
	if pilot is Spatial:
		return pilot
	return null

# Punto de enganche para el activador genérico por cercanía de src-51:
# TODO(src-51): cuando aterrice en core_v2/props/machines o
# core_v2/levels/machines, delegar la decisión de activar/liberar chunks acá en
# vez de usar _update_streaming local. No duplicar esa lógica.
func _call_proximity_activator(player_pos: Vector3) -> void:
	_update_streaming(player_pos)

func _update_streaming(player_pos: Vector3) -> void:
	# Unificar celdas pendientes agrupadas por chunk.
	if _pending_cells.empty():
		_collect_pending_chunk_cells(player_pos)
	_budget_instancing()
	_sync_collisions(player_pos)

func _collect_pending_chunk_cells(player_pos: Vector3) -> void:
	var groups := {}
	for cell in _layout.get("cells", []):
		var key := _chunk_key(cell)
		var center := _chunk_center_for_cell(cell, key)
		if center.distance_to(player_pos) <= load_radius:
			if not groups.has(key):
				groups[key] = []
			groups[key].append(cell)
	for key in groups.keys():
		if _chunks.has(key) or _pending_chunks.has(key):
			continue
		_pending_chunks[key] = true
		_make_chunk_node(key)
		_pending_cells.append_array(groups[key])

func _chunk_center_for_cell(cell: Dictionary, key: String) -> Vector3:
	if _chunk_meta.has(key):
		return _chunk_meta[key]["center"]
	# Centro aproximado por el cuartil del chunk (sin instanciar aún).
	var q: int = int(cell["cx"]) * 4 / int(_layout.get("sectors", sectors))
	q = clamp(q, 0, 3)
	var b: int = int(cell["level"])
	var angle: float = TAU * (float(q) * 0.25 + 0.125)
	var radius: float = inner_radius + (float(rings) - 1.0) * ring_step * 0.5
	var h: float = LEVEL_BAND_0 * (b + 0.5)
	return Vector3(radius * cos(angle), h, radius * sin(angle))

func _budget_instancing() -> void:
	var budget := max_cells_per_frame
	while budget > 0 and not _pending_cells.empty():
		var cell: Dictionary = _pending_cells.pop_front()
		var key := _chunk_key(cell)
		if not _chunks.has(key) or not is_instance_valid(_chunks[key]):
			continue
		_instance_cell_into(_chunks[key], cell)
		_chunk_meta[key]["cells"].append(cell)
		budget -= 1
	var done: Array = []
	for key in _pending_chunks.keys():
		if _chunk_meta.has(key) and _chunk_meta[key]["cells"].size() > 0:
			_finalize_chunk(_chunks[key], key)
			done.append(key)
	for key in done:
		_pending_chunks.erase(key)

func _sync_collisions(player_pos: Vector3) -> void:
	for key in _chunks.keys():
		var chunk: Spatial = _chunks[key]
		if not is_instance_valid(chunk):
			continue
		var center: Vector3 = _chunk_meta.get(key, {}).get("center", Vector3.ZERO)
		var dist: float = center.distance_to(player_pos)
		_set_collision_enabled(chunk, dist <= collision_radius)
		if dist > unload_radius and enable_streaming:
			chunk.queue_free()
			_chunks.erase(key)
			_chunk_meta.erase(key)

func _set_collision_enabled(node: Node, enabled: bool) -> void:
	var layer: int = PROP_COLLISION_LAYER if enabled else 0
	var mask: int = PROP_COLLISION_MASK if enabled else 0
	if node is CollisionObject:
		node.collision_layer = layer
		node.collision_mask = mask
	for child in node.get_children():
		_set_collision_enabled(child, enabled)

func force_request_all_chunks() -> void:
	# Para tests/capturas: instancia todo sin depender del jugador.
	for cell in _layout.get("cells", []):
		var key := _chunk_key(cell)
		var chunk := _make_chunk_node(key)
		_instance_cell_into(chunk, cell)
		_chunk_meta[key]["cells"].append(cell)
	for key in _chunks.keys():
		_finalize_chunk(_chunks[key], key)

func debug_update_streaming_at(world_pos: Vector3) -> void:
	_update_streaming(world_pos)

func get_active_chunk_keys() -> Array:
	var out: Array = []
	for key in _chunks.keys():
		out.append(key)
	return out

# ── Helpers de variantes (espejo de LabyrinthSection) ────────────────────────

func _variant_id(v) -> String:
	if v == null:
		return ""
	if typeof(v) == TYPE_DICTIONARY:
		return String(v.get("id", ""))
	return v.id

func _variant_rotation(v) -> int:
	if typeof(v) == TYPE_DICTIONARY:
		return int(v.get("rotation", 0))
	return v.rotation

func _variant_connections(v) -> Array:
	if v == null:
		return []
	if typeof(v) == TYPE_DICTIONARY:
		return v.get("connections", [])
	return v.connections

func _variant_port_heights(v) -> Array:
	if v == null:
		return []
	if typeof(v) == TYPE_DICTIONARY:
		return v.get("port_heights", [])
	return v.port_heights

func _dir_from_local_side(rot: int, side: String) -> int:
	var r: int = int(posmod(rot, 360))
	match side:
		"front":
			if r == 0:
				return Direction.NORTH
			if r == 90:
				return Direction.EAST
			if r == 180:
				return Direction.SOUTH
			return Direction.WEST
		"back":
			return OPPOSITE[_dir_from_local_side(rot, "front")]
		"left":
			if r == 0:
				return Direction.WEST
			if r == 90:
				return Direction.NORTH
			if r == 180:
				return Direction.EAST
			return Direction.SOUTH
		"right":
			return OPPOSITE[_dir_from_local_side(rot, "left")]
	return Direction.NORTH

func _apply_port_heights_to_front_back(inst, v) -> void:
	if v == null:
		return
	var rotation: int = _variant_rotation(v)
	var heights: Array = _variant_port_heights(v)
	if heights.size() < 4:
		return
	inst.set("front_height_offset", heights[_dir_from_local_side(rotation, "front")])
	inst.set("back_height_offset", heights[_dir_from_local_side(rotation, "back")])

func _apply_rails_from_connections(inst, v) -> void:
	if v == null:
		return
	var rotation: int = _variant_rotation(v)
	var connections: Array = _variant_connections(v)
	# Invariante FD-050.1: rails en TODOS los bordes; el opening se abre solo en
	# lados conectados.
	inst.set("rail_front", true)
	inst.set("rail_back", true)
	inst.set("rail_left", true)
	inst.set("rail_right", true)

func _apply_local_dims(inst, w: float, d: float) -> void:
	inst.set("platform_width", w)
	inst.set("platform_depth", d)

func _apply_opening_widths_from_connections(inst, v) -> void:
	if v == null:
		return
	var rotation: int = _variant_rotation(v)
	var connections: Array = _variant_connections(v)
	var pw: float = _lane_width()
	var front_dir: int = _dir_from_local_side(rotation, "front")
	var back_dir: int = _dir_from_local_side(rotation, "back")
	var left_dir: int = _dir_from_local_side(rotation, "left")
	var right_dir: int = _dir_from_local_side(rotation, "right")
	if connections.size() > front_dir and connections[front_dir]:
		inst.set("rail_front_opening_width", pw)
	if connections.size() > back_dir and connections[back_dir]:
		inst.set("rail_back_opening_width", pw)
	if connections.size() > left_dir and connections[left_dir]:
		inst.set("rail_left_opening_width", pw)
	if connections.size() > right_dir and connections[right_dir]:
		inst.set("rail_right_opening_width", pw)

# ── Entorno: piso de caída + baliza de cima ──────────────────────────────────

func _build_fall_floor() -> void:
	if has_node("FallFloor"):
		return
	var floor_node := StaticBody.new()
	floor_node.name = "FallFloor"
	var mesh := MeshInstance.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = inner_radius + float(rings - 1) * ring_step + 2.0
	cyl.bottom_radius = cyl.top_radius
	cyl.height = 0.3
	mesh.mesh = cyl
	var mat := SpatialMaterial.new()
	mat.albedo_color = Color(0.12, 0.14, 0.16, 1.0)
	mat.roughness = 0.85
	mesh.material_override = mat
	floor_node.add_child(mesh)
	var shape := CollisionShape.new()
	var box := BoxShape.new()
	var half := cyl.top_radius + 0.5
	box.extents = Vector3(half, 0.2, half)
	shape.shape = box
	floor_node.add_child(shape)
	floor_node.translation = Vector3(0.0, -0.2, 0.0)
	floor_node.collision_layer = 1
	add_child(floor_node)

func _build_summit_beacon() -> void:
	if has_node("SummitBeacon"):
		return
	var beacon := Spatial.new()
	beacon.name = "SummitBeacon"
	beacon.translation = _summit_world + Vector3(0.0, 2.0, 0.0)
	var pillar := MeshInstance.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.18
	cyl.height = 6.0
	pillar.mesh = cyl
	var mat := SpatialMaterial.new()
	mat.albedo_color = Color(1.0, 0.82, 0.5, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.78, 0.4, 1.0)
	mat.emission_energy = 2.4
	mat.flags_unshaded = true
	pillar.material_override = mat
	pillar.add_to_group("no_occlusion")
	beacon.add_child(pillar)
	var light := OmniLight.new()
	light.omni_range = 8.0
	light.light_color = Color(1.0, 0.82, 0.5, 1.0)
	light.light_energy = 1.6
	light.shadow_enabled = false
	beacon.add_child(light)
	add_child(beacon)

# ── Entrada / salida como BUFFER FÍSICO (seamless, sin fade) ──────────────────
# Requisito de Sebastián: la entrada (planta) y la salida (cima) son un espacio
# buffer físico compatible con la API que src-54 generaliza en SceneManager. Acá
# solo se construye el espacio y se deja el gancho; NO se usa goto_scene con fade.

func _build_transition_buffers() -> void:
	if has_node("EntryBuffer"):
		return
	var entry := TransitionBufferScript.new()
	entry.name = "EntryBuffer"
	entry.kind = TransitionBufferScript.Kind.ENTRY
	entry.buffer_id = "bay_vertical_entry"
	entry.target_scene = "res://core_v2/levels/RingHub_Level.tscn"
	entry.translation = _entry_world + Vector3(0.0, 1.2, 0.0)
	add_child(entry)

	var exit_buf = TransitionBufferScript.new()
	exit_buf.name = "ExitBuffer"
	exit_buf.kind = TransitionBufferScript.Kind.EXIT
	exit_buf.buffer_id = "bay_vertical_control_room"
	exit_buf.translation = _summit_world + Vector3(0.0, 1.4, 0.0)
	add_child(exit_buf)

func _build_control_room() -> void:
	# Sala de control mínima sobre la cima: piso propio + consola, para que la
	# llegada se lea como destino (y no solo una plataforma más) sin texto.
	if has_node("ControlRoom"):
		return
	var room := Spatial.new()
	room.name = "ControlRoom"
	room.translation = _summit_world
	var floor_body := StaticBody.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 255
	var floor_mesh := MeshInstance.new()
	var cube := CubeMesh.new()
	cube.size = Vector3(5.0, 0.3, 5.0)
	floor_mesh.mesh = cube
	var mat := SpatialMaterial.new()
	mat.albedo_color = Color(0.2, 0.23, 0.28, 1.0)
	mat.metallic = 0.4
	mat.roughness = 0.6
	floor_mesh.material_override = mat
	floor_body.add_child(floor_mesh)
	var col := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = Vector3(2.5, 0.15, 2.5)
	col.shape = box
	floor_body.add_child(col)
	room.add_child(floor_body)
	# Consola frente a la salida.
	var console := MeshInstance.new()
	var cbox := CubeMesh.new()
	cbox.size = Vector3(1.8, 0.9, 0.6)
	console.mesh = cbox
	var cmat := SpatialMaterial.new()
	cmat.albedo_color = Color(0.22, 0.26, 0.32, 1.0)
	cmat.emission_enabled = true
	cmat.emission = Color(0.3, 0.7, 0.95, 1.0)
	cmat.emission_energy = 0.5
	console.material_override = cmat
	console.translation = Vector3(0.0, 0.5, -1.6)
	room.add_child(console)
	add_child(room)

# ── Cambio de modo de gravedad (puzle activado por el jugador) ────────────────
# Sebastián: centrífugo <-> propulsión lo activa el jugador desde consolas. Es un
# puzle que reconfigura rutas, no un reloj. El modo y el blend son estado
# serializable (save + replay). La dirección de gravedad SIEMPRE se lee de
# GravityWorld, nunca se hardcodea.

func _get_gravity_world() -> Node:
	if _gravity_world and is_instance_valid(_gravity_world):
		return _gravity_world
	var tree = get_tree()
	if tree == null:
		return null
	_gravity_world = tree.get_root().get_node_or_null("GravityWorld")
	return _gravity_world

func get_gravity_mode() -> int:
	return _gravity_mode

func get_gravity_blend() -> float:
	return _gravity_blend

# Vector de gravedad FÍSICO en un punto del mundo, agnóstico al modo: sale de
# GravityWorld. Fallback (sin GravityWorld) = radial hacia afuera para SPIN.
func get_gravity_vector_at(world_pos: Vector3) -> Vector3:
	var gw := _get_gravity_world()
	if gw and gw.has_method("get_physical_gravity"):
		return gw.get_physical_gravity(world_pos)
	if _gravity_mode == 1:
		var radial := Vector3(world_pos.x, 0.0, world_pos.z)
		if radial.length_squared() > 0.001:
			return radial.normalized() * 9.81
	return Vector3.DOWN * 9.81

# Alterna el modo. Devuelve true si cambió. Determinista (lo dispara la consola).
func toggle_gravity_mode() -> bool:
	var next := GRAVITY_MODE_SPIN if _gravity_mode == GRAVITY_MODE_THRUST else GRAVITY_MODE_THRUST
	return set_gravity_mode_mode(next)

func set_gravity_mode_mode(mode: int) -> bool:
	if mode == _gravity_mode:
		return false
	_gravity_mode = mode
	_apply_gravity_mode(true)
	return true

func _apply_gravity_mode(notify: bool) -> void:
	# En propulsión "abajo" = a lo largo del eje (modo STANDARD_1G); en centrífugo
	# "abajo" = hacia el anillo (SPIN). El blend visual reencuadra los chunks igual
	# que TerraceSpiral/Platforms (manual_blend axial<->centrífugo).
	_gravity_blend = 1.0 if _gravity_mode == GRAVITY_MODE_SPIN else 0.0
	var gw := _get_gravity_world()
	if gw:
		if gw.has_method("set_gravity_mode"):
			gw.set_gravity_mode(_gravity_mode)
		if gw.has_method("set_gravity_blend"):
			gw.set_gravity_blend(_gravity_blend)
		if gw.has_method("set_spiral_blend"):
			gw.set_spiral_blend(_gravity_blend)
	# La puerta/bridge mode-gated: sólida solo en propulsión.
	if is_instance_valid(_mode_bridge):
		var thrust: bool = _gravity_mode == GRAVITY_MODE_THRUST
		_mode_bridge.collision_layer = 1 if thrust else 0
		_mode_bridge.visible = thrust
	for console in _mode_consoles:
		if is_instance_valid(console) and console.has_method("set_mode"):
			console.set_mode(_gravity_mode)
	if notify:
		emit_signal("gravity_mode_changed", _gravity_mode)

signal gravity_mode_changed(mode)

func _spawn_mode_consoles() -> void:
	if not enable_mode_console:
		return
	# Una consola en la entrada (anillo exterior) y otra en la sala de control (cima).
	_add_mode_console(_entry_world + Vector3(1.6, 0.0, 0.0))
	_add_mode_console(_summit_world + Vector3(1.6, 0.0, 0.0))

func _add_mode_console(pos: Vector3) -> void:
	var console = ModeConsoleScript.new()
	console.name = "ModeConsole%d" % _mode_consoles.size()
	console.translation = pos
	console.set("well_path", NodePath(""))
	add_child(console)
	# El console cuelga del pozo: resuelve el pozo por get_parent() en _ready.
	_mode_consoles.append(console)

func _spawn_mode_gate() -> void:
	# Atajo que SÓLO existe en propulsión: un puente axial (a lo largo del eje) que
	# conecta dos costuras de la cima. En centrífugo se desolidifica (no hay ruta).
	if has_node("ModeBridge"):
		return
	var bridge := StaticBody.new()
	bridge.name = "ModeBridge"
	bridge.translation = (_entry_world + _summit_world) * 0.5
	var mesh := MeshInstance.new()
	var cube := CubeMesh.new()
	cube.size = Vector3(1.6, 0.2, 8.0)
	mesh.mesh = cube
	var mat := SpatialMaterial.new()
	mat.albedo_color = Color(0.55, 0.5, 0.2, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.75, 0.3, 1.0)
	mat.emission_energy = 0.6
	mesh.material_override = mat
	bridge.add_child(mesh)
	var col := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = Vector3(0.8, 0.1, 4.0)
	col.shape = box
	bridge.add_child(col)
	bridge.collision_mask = 255
	add_child(bridge)
	_mode_bridge = bridge

func _reposition_spawn_point() -> void:
	var spawn = get_node_or_null("../SpawnPointV2")
	if spawn is Spatial:
		spawn.global_transform = Transform(Basis.IDENTITY, _entry_world + Vector3(0.0, 0.6, 0.0))

# ── Atajos ───────────────────────────────────────────────────────────────────

func _spawn_shortcuts() -> void:
	if enable_conveyor_shortcut and _host_world.has("ca0") and _host_world.has("ca2"):
		_spawn_conveyor_shortcut()
	if enable_laser_gate and _host_world.has("cb0") and _host_world.has("cb1"):
		_spawn_laser_gate()
	if enable_gloo_span and _host_world.has("cg0") and _host_world.has("cg1"):
		_spawn_gloo_span()

func _spawn_conveyor_shortcut() -> void:
	var a: Vector3 = _host_world["ca0"]
	var b: Vector3 = _host_world["ca2"]
	var mid: Vector3 = (a + b) * 0.5
	mid.y = max(a.y, b.y) + 0.4
	var dir: Vector3 = (b - a).normalized()
	var x: Vector3 = dir
	var z: Vector3 = x.cross(Vector3.UP).normalized()
	var y: Vector3 = z.cross(x)
	var conveyor = ConveyorScene.instance()
	conveyor.name = "ShortcutConveyor"
	conveyor.global_transform = Transform(Basis(x, y, z), mid)
	conveyor.length = (b - a).length()
	conveyor.starts_active = true
	conveyor.speed_x = conveyor_speed
	conveyor.occupancy_detection = false
	add_child(conveyor)
	_shortcuts.append(conveyor)
	# Caja para el rol "traen cajas para trepar".
	var box = PushableBoxScene.instance()
	box.name = "ShortcutBox"
	box.global_transform = Transform(Basis.IDENTITY, a + Vector3(0.0, 1.0, 0.0))
	add_child(box)
	_shortcuts.append(box)

func _spawn_laser_gate() -> void:
	var a: Vector3 = _host_world["cb0"]
	var b: Vector3 = _host_world["cb1"]
	var mid: Vector3 = (a + b) * 0.5
	mid.y = max(a.y, b.y) + 0.6
	var gate = LaserGateScript.new()
	gate.name = "ShortcutLaserGate"
	gate.translation = mid
	gate.cut_time = laser_gate_cut_time
	add_child(gate)
	_shortcuts.append(gate)

func _spawn_gloo_span() -> void:
	var a: Vector3 = _host_world["cg0"]
	var b: Vector3 = _host_world["cg1"]
	var mid: Vector3 = (a + b) * 0.5
	var span = GlooSpanScript.new()
	span.name = "ShortcutGlooSpan"
	span.translation = mid
	span.required_blobs = gloo_span_required_blobs
	span.span_from = a
	span.span_to = b
	add_child(span)
	_shortcuts.append(span)

# ── Peligro: rotor sincronizado con el ciclo ────────────────────────────────

func _spawn_hazard() -> void:
	if not enable_hazard_rotor or not _host_world.has("ca0"):
		return
	var center: Vector3 = (_host_world["ca0"] + _host_world["ca2"]) * 0.5
	var rotor := StaticBody.new()
	rotor.name = "HazardRotor"
	rotor.translation = center + Vector3(0.0, 1.2, 0.0)
	var arm := MeshInstance.new()
	var box := CubeMesh.new()
	box.size = Vector3(0.25, 0.18, 3.6)
	arm.mesh = box
	var mat := SpatialMaterial.new()
	mat.albedo_color = Color(0.85, 0.2, 0.12, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.25, 0.15, 1.0)
	mat.emission_energy = 1.4
	arm.material_override = mat
	arm.translation = Vector3(0.0, 0.0, -1.2)
	rotor.add_child(arm)
	var col := CollisionShape.new()
	var colbox := BoxShape.new()
	colbox.extents = Vector3(0.18, 0.15, 1.8)
	col.shape = colbox
	col.translation = Vector3(0.0, 0.0, -1.2)
	rotor.add_child(col)
	add_child(rotor)
	_rotor = rotor
	_rotor_angle = 0.0
	_rotor_active = false

func _update_hazard(delta: float) -> void:
	if not is_instance_valid(_rotor):
		return
	var danger: bool = _cycle != null and _cycle.get_phase() == CycleScript.Phase.DANGER
	if danger:
		_rotor_angle += rotor_angular_speed * delta
		_rotor.rotation_degrees.y = rad2deg(_rotor_angle)
	_rotor_active = danger

func _apply_phase_to_shortcuts(phase: int) -> void:
	# Las luces de atajo frías/parpadeantes se actualizan aquí; los módulos de
	# danger propio hacen su trabajo en _update_hazard.
	for shortcut in _shortcuts:
		if not is_instance_valid(shortcut):
			continue
		if shortcut.has_method("set_phase"):
			shortcut.set_phase(phase)

# ── Estado serializable (replay + save) ──────────────────────────────────────

func set_seed_from_save(seed_val: int) -> void:
	if seed_val != generation_seed:
		generation_seed = seed_val
		if _generated:
			_regen()

func get_state() -> Dictionary:
	var states := []
	for shortcut in _shortcuts:
		if is_instance_valid(shortcut) and shortcut.has_method("get_state"):
			states.append({
				"name": shortcut.name,
				"state": shortcut.get_state(),
			})
	return {
		"seed": generation_seed,
		"rotor_angle": _rotor_angle,
		"gravity_mode": _gravity_mode,
		"gravity_blend": _gravity_blend,
		"shortcuts": states,
	}

func get_snapshot() -> Dictionary:
	return get_state()

func restore_snapshot(data: Dictionary) -> void:
	if data.has("seed"):
		set_seed_from_save(int(data["seed"]))
	_rotor_angle = float(data.get("rotor_angle", 0.0))
	if is_instance_valid(_rotor):
		_rotor.rotation_degrees.y = rad2deg(_rotor_angle)
	if data.has("gravity_mode"):
		_gravity_mode = int(data["gravity_mode"])
		_gravity_blend = float(data.get("gravity_blend", _gravity_blend))
		_apply_gravity_mode(false)
	var states: Array = data.get("shortcuts", [])
	for entry in states:
		var n: String = entry.get("name", "")
		var st = entry.get("state", {})
		for shortcut in _shortcuts:
			if is_instance_valid(shortcut) and shortcut.name == n and shortcut.has_method("restore_state"):
				shortcut.restore_state(st)

# ── Acceso para tests / depuración ───────────────────────────────────────────

func get_layout() -> Dictionary:
	return _layout

func get_entry_world_position() -> Vector3:
	return _entry_world

func get_summit_world_position() -> Vector3:
	return _summit_world

func get_shortcuts() -> Array:
	return _shortcuts

func get_rotor() -> Spatial:
	return _rotor
