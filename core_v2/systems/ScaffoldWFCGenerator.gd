tool
extends Spatial

# FD-050 Procedural Scaffolds and Walkways (WFC)

export(int) var map_seed = -1
export(bool) var trigger_generate = false setget set_trigger_generate

const GRID_WIDTH = 20
const GRID_DEPTH = 6
const CELL_SIZE = 10.0

const WEIGHTS = {
	"W": 4.0, "R": 3.0, "P": 2.0,
	"S": 1.5, "C": 1.5,
	"G": 0.5,
	"X": 1.0, "T": 1.5,
	"E": 2.5,
}

enum Direction { NORTH = 0, EAST = 1, SOUTH = 2, WEST = 3 }

const DIR_VEC = {
	Direction.NORTH: Vector2(0, -1),
	Direction.EAST: Vector2(1, 0),
	Direction.SOUTH: Vector2(0, 1),
	Direction.WEST: Vector2(-1, 0)
}

const OPPOSITE = {
	Direction.NORTH: Direction.SOUTH,
	Direction.SOUTH: Direction.NORTH,
	Direction.EAST: Direction.WEST,
	Direction.WEST: Direction.EAST
}

var modules = {
	"W": preload("res://core_v2/props/scaffold/ScaffoldWalkway.tscn"),
	"R": preload("res://core_v2/props/scaffold/ScaffoldRailing.tscn"),
	"P": preload("res://core_v2/props/scaffold/ScaffoldPlatform.tscn"),
	"S": preload("res://core_v2/props/scaffold/ScaffoldStairs.tscn"),
	"C": preload("res://core_v2/props/scaffold/ScaffoldCurve.tscn"),
	"G": preload("res://core_v2/props/scaffold/ScaffoldGap.tscn"),
	"X": preload("res://core_v2/props/scaffold/ScaffoldCross.tscn"),
	"T": preload("res://core_v2/props/scaffold/ScaffoldTJunction.tscn"),
	"E": preload("res://core_v2/props/scaffold/ScaffoldEnd.tscn"),
	"EMPTY": null
}

class ModuleVariant:
	var id: String
	var rotation: int
	var connections: Array
	var port_heights: Array
	var weight: float

	func _init(p_id: String, p_rot: int, p_conn: Array, p_heights: Array, p_weight: float):
		id = p_id
		rotation = p_rot
		connections = p_conn
		port_heights = p_heights
		weight = p_weight

var all_variants = []
const HEIGHT_STEP = 2.0
const MAX_HEIGHT_STEPS = 5

class CellState:
	var variant: ModuleVariant
	var base_height: float

	func _init(v: ModuleVariant, h: float):
		variant = v
		base_height = h

func _ready():
	_setup_variants()
	if not Engine.editor_hint:
		generate(map_seed)

func set_trigger_generate(v):
	if v:
		_setup_variants()
		generate(map_seed)

func _setup_variants():
	all_variants = []
	var fpts = [0.0, 0.0, 0.0, 0.0]
	for id in ["W", "R", "G"]:
		var w = WEIGHTS[id] / 2.0
		all_variants.append(ModuleVariant.new(id, 0, [true, false, true, false], fpts, w))
		all_variants.append(ModuleVariant.new(id, 90, [false, true, false, true], fpts, w))
	var sw = WEIGHTS["S"] / 4.0
	all_variants.append(ModuleVariant.new("S", 0, [true, false, true, false], [0.0, 0.0, 2.0, 0.0], sw))
	all_variants.append(ModuleVariant.new("S", 180, [true, false, true, false], [2.0, 0.0, 0.0, 0.0], sw))
	all_variants.append(ModuleVariant.new("S", 90, [false, true, false, true], [0.0, 0.0, 0.0, 2.0], sw))
	all_variants.append(ModuleVariant.new("S", 270, [false, true, false, true], [0.0, 2.0, 0.0, 0.0], sw))
	all_variants.append(ModuleVariant.new("P", 0, [true, true, true, true], fpts, WEIGHTS["P"]))
	all_variants.append(ModuleVariant.new("X", 0, [true, true, true, true], fpts, WEIGHTS["X"]))
	var cw = WEIGHTS["C"] / 4.0
	all_variants.append(ModuleVariant.new("C", 0, [true, true, false, false], fpts, cw))
	all_variants.append(ModuleVariant.new("C", 90, [false, true, true, false], fpts, cw))
	all_variants.append(ModuleVariant.new("C", 180, [false, false, true, true], fpts, cw))
	all_variants.append(ModuleVariant.new("C", 270, [true, false, false, true], fpts, cw))
	var tw = WEIGHTS["T"] / 4.0
	all_variants.append(ModuleVariant.new("T", 0, [true, true, false, true], fpts, tw))
	all_variants.append(ModuleVariant.new("T", 90, [true, true, true, false], fpts, tw))
	all_variants.append(ModuleVariant.new("T", 180, [false, true, true, true], fpts, tw))
	all_variants.append(ModuleVariant.new("T", 270, [true, false, true, true], fpts, tw))
	var ew = WEIGHTS["E"] / 4.0
	all_variants.append(ModuleVariant.new("E", 0, [true, false, false, false], fpts, ew))
	all_variants.append(ModuleVariant.new("E", 90, [false, true, false, false], fpts, ew))
	all_variants.append(ModuleVariant.new("E", 180, [false, false, true, false], fpts, ew))
	all_variants.append(ModuleVariant.new("E", 270, [false, false, false, true], fpts, ew))
	all_variants.append(ModuleVariant.new("EMPTY", 0, [false, false, false, false], fpts, 2.0))

func generate(seed_val: int = -1):
	if seed_val == -1: randomize()
	else: seed(seed_val)
	for child in get_children():
		child.queue_free()
	var grid = _wfc_generate()
	if not grid.empty():
		_instance_grid(grid)

func _wfc_generate() -> Array:
	for retry in range(40):
		var res = _wfc_attempt()
		if not res.empty():
			if _is_single_component(res):
				print("[ScaffoldWFC] Success on retry ", retry)
				return res
	return []

func _idx(x: int, y: int) -> int:
	return y * GRID_WIDTH + x

func _wfc_attempt() -> Array:
	var gs = GRID_WIDTH * GRID_DEPTH
	var ds = []
	var hds = []
	var collapsed = []
	collapsed.resize(gs)
	var phs = []
	for i in range(-MAX_HEIGHT_STEPS, MAX_HEIGHT_STEPS + 1):
		phs.append(float(i) * HEIGHT_STEP)
	for i in range(gs):
		ds.append(all_variants.duplicate())
		hds.append(phs.duplicate())
		collapsed[i] = null
	_apply_boundary_constraints(ds, hds)
	for x in range(0, GRID_WIDTH, 5):
		var idx = _idx(x, 0)
		var edom = []
		for v in ds[idx]:
			if v.id == "E":
				edom.append(v)
		if not edom.empty():
			ds[idx] = edom
			hds[idx] = [0.0]
			if not _propagate(ds, hds, collapsed, idx):
				return []
	var stp = 0
	while stp < gs:
		var me = 1000000
		var mi = -1
		for i in range(gs):
			if collapsed[i] != null:
				continue
			var e = ds[i].size()
			if e == 0:
				return []
			if e < me:
				me = e
				mi = i
		if mi == -1:
			break
		var cv = _weighted_pick(ds[mi])
		var ho = hds[mi]
		var ch = ho[randi() % ho.size()]
		collapsed[mi] = CellState.new(cv, ch)
		ds[mi] = [cv]
		hds[mi] = [ch]
		if not _propagate(ds, hds, collapsed, mi):
			return []
		stp += 1
	return collapsed

func _apply_boundary_constraints(ds: Array, hds: Array):
	for y in range(GRID_DEPTH):
		for x in range(GRID_WIDTH):
			var idx = _idx(x, y)
			var filtered = []
			for v in ds[idx]:
				var ok = true
				if y == 0:
					if v.connections[Direction.NORTH]:
						ok = false
					elif v.id != "EMPTY":
						if v.id == "E":
							if not v.connections[Direction.SOUTH]:
								ok = false
						else:
							ok = false
				elif y == GRID_DEPTH - 1:
					if v.connections[Direction.SOUTH]:
						ok = false
					elif v.id != "EMPTY":
						if v.id == "E":
							if not v.connections[Direction.NORTH]:
								ok = false
						elif v.id == "P":
							pass
						else:
							ok = false

				if x == 0 and v.connections[Direction.WEST]:
					ok = false
				if x == GRID_WIDTH - 1 and v.connections[Direction.EAST]:
					ok = false

				if ok:
					filtered.append(v)
			ds[idx] = filtered
			if y == 0:
				hds[idx] = [0.0]

func _propagate(ds: Array, hds: Array, collapsed: Array, start_idx: int) -> bool:
	var stack = [start_idx]
	while not stack.empty():
		var ci = stack.pop_back()
		var cx = ci % GRID_WIDTH
		var cy = ci / GRID_WIDTH
		for dir in Direction.values():
			var vec = DIR_VEC[dir]
			var nx = cx + vec.x
			var ny = cy + vec.y
			if nx < 0 or nx >= GRID_WIDTH or ny < 0 or ny >= GRID_DEPTH:
				continue
			var ni = _idx(nx, ny)
			if collapsed[ni] != null:
				continue
			var fv = []
			var fh = []
			var nhd = hds[ni]
			for nv in ds[ni]:
				var p = false
				for cv in ds[ci]:
					for ch in hds[ci]:
						var res = _check_pair(cv, ch, nv, dir)
						if res.valid:
							p = true
							if res.has("h"):
								if res.h in nhd and not res.h in fh:
									fh.append(res.h)
					if p: break
				if p:
					fv.append(nv)
			if fv.empty():
				return false
			var hc = false
			for cv in ds[ci]:
				if cv.connections[dir]:
					hc = true
					break
			if not hc:
				fh = nhd
			if fh.empty():
				return false
			var chg = false
			if fv.size() < ds[ni].size():
				ds[ni] = fv
				chg = true
			if fh.size() < hds[ni].size():
				hds[ni] = fh
				chg = true
			if chg:
				stack.append(ni)
	return true

func _check_pair(v_curr, h_curr, v_next, dir) -> Dictionary:
	var opp = OPPOSITE[dir]
	if v_curr.connections[dir] != v_next.connections[opp]:
		return {"valid": false}
	var res = {"valid": true}
	if v_curr.connections[dir]:
		res.h = h_curr + v_curr.port_heights[dir] - v_next.port_heights[opp]
		if abs(res.h) > MAX_HEIGHT_STEPS * HEIGHT_STEP:
			return {"valid": false}
	if v_curr.id == "G" and (dir == Direction.NORTH or dir == Direction.SOUTH):
		if not (v_next.id in ["R", "P", "C"]):
			return {"valid": false}
	if v_next.id == "G" and (opp == Direction.NORTH or opp == Direction.SOUTH):
		if not (v_curr.id in ["R", "P", "C"]):
			return {"valid": false}
	return res

func _weighted_pick(domain: Array) -> ModuleVariant:
	var t = 0.0
	for v in domain:
		t += v.weight
	var r = randf() * t
	var c = 0.0
	for v in domain:
		c += v.weight
		if r <= c:
			return v
	return domain[0]

func _is_single_component(collapsed: Array) -> bool:
	var start = -1
	for i in range(collapsed.size()):
		if collapsed[i] != null and collapsed[i].variant.id != "EMPTY":
			start = i
			break
	if start == -1:
		return true
	var vstd = {}
	var q = [start]
	vstd[start] = true
	var count = 0
	while not q.empty():
		var curr = q.pop_front()
		count += 1
		var cx = curr % GRID_WIDTH
		var cy = curr / GRID_WIDTH
		var cv = collapsed[curr].variant
		for dir in Direction.values():
			if not cv.connections[dir]:
				continue
			var vec = DIR_VEC[dir]
			var nx = cx + vec.x
			var ny = cy + vec.y
			if nx >= 0 and nx < GRID_WIDTH and ny >= 0 and ny < GRID_DEPTH:
				var ni = _idx(nx, ny)
				if collapsed[ni] != null and collapsed[ni].variant.id != "EMPTY" and not vstd.has(ni):
					if collapsed[ni].variant.connections[OPPOSITE[dir]]:
						vstd[ni] = true
						q.push_back(ni)
	var t = 0
	for v in collapsed:
		if v != null and v.variant.id != "EMPTY":
			t += 1
	return count == t

func _instance_grid(grid: Array):
	for y in range(GRID_DEPTH):
		for x in range(GRID_WIDTH):
			var state = grid[_idx(x, y)]
			if state == null or state.variant.id == "EMPTY":
				continue
			var v = state.variant
			var inst = modules[v.id].instance()
			add_child(inst)
			inst.translation = Vector3(x * CELL_SIZE, state.base_height, y * CELL_SIZE)
			inst.rotation_degrees.y = -v.rotation
			var vid = v.id
			if vid == "W" or vid == "R" or vid == "G":
				_apply_dims(inst, v.rotation, 3.0, 10.0)
				if vid != "W":
					_apply_rails(inst, v.rotation, false, false, true, true)
				if vid == "G":
					inst.set("rail_front_opening_width", 3.0)
					inst.set("rail_back_opening_width", 3.0)
			elif vid == "P":
				inst.set("platform_width", 15.0)
				inst.set("platform_depth", 6.0)
			elif vid == "S":
				_apply_dims(inst, v.rotation, 4.0, 10.0)
				inst.set("back_height_offset", 2.0)
				_apply_rails(inst, v.rotation, false, false, true, true)
			elif vid == "C":
				_apply_dims(inst, v.rotation, 3.0, 12.0)
				_apply_rails(inst, v.rotation, false, false, true, true)
			elif vid == "X" or vid == "T":
				inst.set("platform_width", 6.0)
				inst.set("platform_depth", 6.0)
				if vid == "T":
					_apply_rails(inst, v.rotation, false, false, false, true)
			elif vid == "E":
				inst.set("platform_width", 4.0)
				inst.set("platform_depth", 4.0)
				_apply_rails(inst, v.rotation, true, false, true, true)
			if inst.has_method("_rebuild"):
				inst.call("_rebuild")

func _apply_dims(inst, rot, w, d):
	if rot == 90 or rot == 270:
		inst.set("platform_width", d)
		inst.set("platform_depth", w)
	else:
		inst.set("platform_width", w)
		inst.set("platform_depth", d)

func _apply_rails(inst, rot, f, b, l, r):
	if rot == 90:
		inst.set("rail_front", l)
		inst.set("rail_back", r)
		inst.set("rail_left", b)
		inst.set("rail_right", f)
	elif rot == 180:
		inst.set("rail_front", b)
		inst.set("rail_back", f)
		inst.set("rail_left", r)
		inst.set("rail_right", l)
	elif rot == 270:
		inst.set("rail_front", r)
		inst.set("rail_back", l)
		inst.set("rail_left", f)
		inst.set("rail_right", b)
	else:
		inst.set("rail_front", f)
		inst.set("rail_back", b)
		inst.set("rail_left", l)
		inst.set("rail_right", r)
