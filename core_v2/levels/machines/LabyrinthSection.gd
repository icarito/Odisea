extends Spatial
class_name LabyrinthSection

# Sección laberíntica procedural para la bahía de máquinas (spike 2026-11-13).
#
# Genera UN laberinto con `ScaffoldMSTGenerator` (semilla fija, sin randf en
# runtime) en el bolsillo lateral entre Estación 1 y 2, reutilizando los módulos
# de scaffold existentes, y le añade hazards de fuego y gas con sabor "mente de
# Odisea": un ciclo de PROTOCOLO determinista alterna fuego/gas en ventanas
# acotadas (presión de tiempo), con aviso por luz de estado, arranque en SAFE y
# margen honesto. Determinismo: todo deriva de `generation_seed` y de la
# acumulación de `_elapsed`; nada de RNG en runtime.

const MSTGeneratorScript := preload("res://core_v2/systems/ScaffoldMSTGenerator.gd")
const FireHazardScript := preload("res://core_v2/systems/fire/LabyrinthFireHazard.gd")
const FireVisualBandScene := preload("res://core_v2/systems/fire/FireVisualBand.tscn")
const GasAreaScene := preload("res://core_v2/systems/gas/GasArea3D.tscn")

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

enum HazardPhase { SAFE = 0, WARNING_FIRE = 1, FIRE = 2, WARNING_GAS = 3, GAS = 4 }

export(int) var generation_seed := 20261113
export(int, 2, 12) var grid_width := 4
export(int, 2, 16) var grid_depth := 8
export(float, 2.0, 8.0) var cell_size := 3.0
export(Vector2) var entry_cell := Vector2(0, 2)
export(float) var entry_height := 0.0
# Salida opcional hacia el laberinto streamed (FD-320+): fija una celda
# "W" plana en el borde este para conectarse con el puente de entrada.
export(bool) var exit_use := false
export(Vector2) var exit_cell := Vector2(-1, -1)
export(bool) var enable_fire_hazard := true
export(bool) var enable_gas_hazard := true
export(bool) var enable_fire_visual := true
export(bool) var enable_protocol_cycle := true
export(float) var fire_heat_band := 2.5
export(float) var fire_damage_per_second := 18.0
export(float) var gas_damage_per_second := 15.0
export(float) var protocol_safe_duration := 4.0
export(float) var protocol_warning_duration := 2.0
export(float) var protocol_hazard_duration := 5.0

var _grid: Array = []
var _fire_hazard: Node = null
var _fire_visual: Node = null
var _gas_hazard: Node = null
var _status_light: OmniLight = null
var _elapsed: float = 0.0
var _phase: int = HazardPhase.SAFE

func _ready() -> void:
	if Engine.editor_hint:
		return
	_build()

func _build() -> void:
	for child in get_children():
		child.queue_free()
	_grid = _generate_grid_data()
	_instance_grid(_grid)
	_spawn_hazards()
	if enable_protocol_cycle:
		_elapsed = 0.0
		_phase = HazardPhase.SAFE
		_apply_phase_to_hazards()

# ── Generación (MST, semilla fija) ────────────────────────────────────────────

func _generate_grid_data() -> Array:
	var gen = MSTGeneratorScript.new()
	var seam := {
		"%d,%d" % [int(entry_cell.x), int(entry_cell.y)]: {
			"id": "E",
			"rotation": 270,
			"height": entry_height
		}
	}
	if exit_use and exit_cell.x >= 0.0 and exit_cell.y >= 0.0:
		seam["%d,%d" % [int(exit_cell.x), int(exit_cell.y)]] = {
			"id": "W",
			"rotation": 0,
			"height": entry_height
		}
	gen.apply_params({
		"grid_width": grid_width,
		"grid_depth": grid_depth,
		"cell_size": cell_size,
		"mst_max_height_steps": 3,
		"mst_min_height_steps": 1,
		"room_count": 6,
		"extra_cycles": 2,
		"fixed_border_tiles": seam
	})
	var data: Array = gen.generate_grid_data(generation_seed)
	if data.empty():
		push_error("[LabyrinthSection] generación MST vacía (seed=%d)" % generation_seed)
	return data

func _cell_empty(state) -> bool:
	if state == null:
		return true
	if typeof(state) == TYPE_DICTIONARY:
		var v = state.get("variant", null)
		if v == null:
			return true
		return String(v.get("id", "")) == "EMPTY"
	return true

func _state_variant(state):
	if typeof(state) == TYPE_DICTIONARY:
		return state.get("variant", null)
	return null

func _state_base_height(state) -> float:
	if typeof(state) == TYPE_DICTIONARY:
		return float(state.get("base_height", 0.0))
	return 0.0

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

# ── Instanciación de módulos (espejo de ScaffoldWFCGenerator._instance_grid) ──

func _instance_grid(grid: Array) -> void:
	for x in range(grid_width):
		for y in range(grid_depth):
			var state = grid[y * grid_width + x]
			if _cell_empty(state):
				continue
			var v = _state_variant(state)
			var vid: String = _variant_id(v)
			if vid == "" or vid == "EMPTY":
				continue
			var inst = MODULES[vid].instance()
			add_child(inst)
			var deck_local_y: float = float(inst.platform_height)
			var base_height: float = _state_base_height(state)
			inst.translation = Vector3(x * cell_size, base_height - deck_local_y, y * cell_size)
			inst.rotation_degrees.y = -_variant_rotation(v)
			inst.set("support_base_local_y", deck_local_y - base_height)
			if vid == "W" or vid == "R" or vid == "G":
				_apply_local_dims(inst, _lane_width(), cell_size)
				_apply_rails_from_connections(inst, v)
				_apply_opening_widths_from_connections(inst, v)
			elif vid == "P":
				_apply_local_dims(inst, cell_size, cell_size)
				_apply_rails_from_connections(inst, v)
				_apply_opening_widths_from_connections(inst, v)
			elif vid == "S":
				_apply_local_dims(inst, _lane_width(), cell_size)
				_apply_port_heights_to_front_back(inst, v)
				_apply_rails_from_connections(inst, v)
				_apply_opening_widths_from_connections(inst, v)
			else:
				_apply_local_dims(inst, cell_size, cell_size)
				_apply_rails_from_connections(inst, v)
				_apply_opening_widths_from_connections(inst, v)
			if inst.has_method("_rebuild"):
				inst.call("_rebuild")

func _lane_width() -> float:
	return clamp(cell_size * 0.32, 2.5, 4.5)

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
	inst.set("front_height_offset", heights[_dir_from_local_side(rotation, "front")])
	inst.set("back_height_offset", heights[_dir_from_local_side(rotation, "back")])

func _apply_rails_from_connections(inst, v) -> void:
	if v == null:
		return
	var rotation: int = _variant_rotation(v)
	var connections: Array = _variant_connections(v)
	var front_dir: int = _dir_from_local_side(rotation, "front")
	var back_dir: int = _dir_from_local_side(rotation, "back")
	var left_dir: int = _dir_from_local_side(rotation, "left")
	var right_dir: int = _dir_from_local_side(rotation, "right")
	inst.set("rail_front", not (connections.size() > front_dir and connections[front_dir]))
	inst.set("rail_back", not (connections.size() > back_dir and connections[back_dir]))
	inst.set("rail_left", not (connections.size() > left_dir and connections[left_dir]))
	inst.set("rail_right", not (connections.size() > right_dir and connections[right_dir]))

func _apply_local_dims(inst, w: float, d: float) -> void:
	inst.set("platform_width", w)
	inst.set("platform_depth", d)

func _apply_opening_widths_from_connections(inst, v) -> void:
	if v == null:
		return
	var rotation: int = _variant_rotation(v)
	var connections: Array = _variant_connections(v)
	var front_dir: int = _dir_from_local_side(rotation, "front")
	var back_dir: int = _dir_from_local_side(rotation, "back")
	var left_dir: int = _dir_from_local_side(rotation, "left")
	var right_dir: int = _dir_from_local_side(rotation, "right")
	var pw: float = _lane_width()
	if connections.size() > front_dir and connections[front_dir]:
		inst.set("rail_front_opening_width", pw)
	if connections.size() > back_dir and connections[back_dir]:
		inst.set("rail_back_opening_width", pw)
	if connections.size() > left_dir and connections[left_dir]:
		inst.set("rail_left_opening_width", pw)
	if connections.size() > right_dir and connections[right_dir]:
		inst.set("rail_right_opening_width", pw)

# ── Hazards ──────────────────────────────────────────────────────────────────

func _spawn_hazards() -> void:
	var min_h: float = INF
	for i in range(_grid.size()):
		if _cell_empty(_grid[i]):
			continue
		min_h = min(min_h, _state_base_height(_grid[i]))
	if min_h == INF:
		min_h = entry_height
	var fire_line_y: float = min_h + 0.3

	if enable_fire_hazard:
		var fire = FireHazardScript.new()
		fire.name = "LabyrinthFire"
		fire.base_speed = 0.0
		fire.accel = 0.0
		fire.start_height = fire_line_y
		fire.max_height = fire_line_y
		fire.auto_start = true
		fire.heat_band = fire_heat_band
		fire.damage_per_second = fire_damage_per_second
		fire.debug_draw = false
		var hw: float = grid_width * cell_size * 0.5 + 1.5
		var hd: float = grid_depth * cell_size * 0.5 + 1.5
		fire.gate_local_center = Vector3(grid_width * cell_size * 0.5, 0.0, grid_depth * cell_size * 0.5)
		fire.gate_local_half_extents = Vector3(hw, 100.0, hd)
		add_child(fire)
		_fire_hazard = fire
		if enable_fire_visual:
			var band = FireVisualBandScene.instance()
			band.name = "LabyrinthFireVisual"
			band.ring_radius = max(hw, hd) * 1.05
			band.particles_per_second = 60.0
			band.visible_arc_deg = 360.0
			band.translation = Vector3(fire.gate_local_center.x, 0.0, fire.gate_local_center.z)
			add_child(band)
			_fire_visual = band

	if enable_gas_hazard:
		var gas_i: int = _pick_gas_cell()
		if gas_i >= 0:
			var gas = GasAreaScene.instance()
			gas.name = "LabyrinthGas"
			gas.gas_type = GasArea3D.GasType.TOXIC
			gas.damage_per_second = gas_damage_per_second
			gas.initial_particle_count = 96
			gas.initial_respect_world_collision = true
			var gx: int = gas_i % grid_width
			var gz: int = gas_i / grid_width
			gas.translation = Vector3(gx * cell_size, _state_base_height(_grid[gas_i]) + 0.7, gz * cell_size)
			add_child(gas)
			_gas_hazard = gas

	if enable_protocol_cycle:
		_status_light = _make_status_light()

func _pick_gas_cell() -> int:
	var best := -1
	var best_dist := -1.0
	for i in range(_grid.size()):
		if _cell_empty(_grid[i]):
			continue
		var x: int = i % grid_width
		var y: int = i / grid_width
		if x == int(entry_cell.x) and y == int(entry_cell.y):
			continue
		var d: float = Vector2(float(x) - float(grid_width - 1) * 0.5, float(y) - float(grid_depth - 1) * 0.5).length()
		if d > best_dist:
			best_dist = d
			best = i
	return best

func _make_status_light() -> OmniLight:
	var light := OmniLight.new()
	light.name = "ProtocolStatusLight"
	light.translation = Vector3(entry_cell.x * cell_size, entry_height + 3.5, entry_cell.y * cell_size)
	light.omni_range = 7.0
	light.shadow_enabled = false
	light.light_color = Color(0.25, 1.0, 0.35)
	add_child(light)
	return light

# ── Ciclo de protocolo (determinista) ────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if Engine.editor_hint or not enable_protocol_cycle:
		return
	_elapsed += delta
	var new_phase: int = _phase_for_time(_elapsed)
	if new_phase != _phase:
		_phase = new_phase
		_apply_phase_to_hazards()

func _phase_for_time(t: float) -> int:
	var cycle: float = (protocol_safe_duration + protocol_warning_duration + protocol_hazard_duration) * 2.0
	var tt: float = fmod(t, cycle)
	var safe: float = protocol_safe_duration
	var warn: float = protocol_warning_duration
	var haz: float = protocol_hazard_duration
	if tt < safe:
		return HazardPhase.SAFE
	if tt < safe + warn:
		return HazardPhase.WARNING_FIRE
	if tt < safe + warn + haz:
		return HazardPhase.FIRE
	if tt < safe * 2.0 + warn:
		return HazardPhase.SAFE
	if tt < safe * 2.0 + warn * 2.0:
		return HazardPhase.WARNING_GAS
	return HazardPhase.GAS

func _apply_phase_to_hazards() -> void:
	if _fire_hazard:
		_fire_hazard.stop()
		if _phase == HazardPhase.FIRE:
			_fire_hazard.start()
	if _fire_visual:
		_fire_visual.visible = (_phase == HazardPhase.FIRE)
	if _gas_hazard:
		if _phase == HazardPhase.GAS:
			_gas_hazard.set("damage_per_second", gas_damage_per_second)
		else:
			_gas_hazard.set("damage_per_second", 0.0)
	if _status_light:
		match _phase:
			HazardPhase.SAFE:
				_status_light.light_color = Color(0.25, 1.0, 0.35)
			HazardPhase.WARNING_FIRE, HazardPhase.WARNING_GAS:
				_status_light.light_color = Color(1.0, 0.72, 0.12)
			HazardPhase.FIRE:
				_status_light.light_color = Color(1.0, 0.22, 0.08)
			HazardPhase.GAS:
				_status_light.light_color = Color(0.35, 0.85, 1.0)

# ── Acceso para tests / depuración ────────────────────────────────────────────

func get_fire_hazard() -> Node:
	return _fire_hazard

func get_gas_hazard() -> Node:
	return _gas_hazard

func get_hazard_phase() -> int:
	return _phase

func get_generation_grid() -> Array:
	return _grid

func get_entry_world_position() -> Vector3:
	return global_transform.xform(Vector3(entry_cell.x * cell_size, entry_height, entry_cell.y * cell_size))

func get_exit_world_position() -> Vector3:
	return global_transform.xform(Vector3(exit_cell.x * cell_size, entry_height, exit_cell.y * cell_size))
