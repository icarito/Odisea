tool
extends Spatial

# FD-050 Procedural Scaffolds and Walkways (WFC)

export(int) var map_seed = -1
export(bool) var trigger_generate = false setget set_trigger_generate
export(bool) var debug_verbose = false
export(int, 4, 32) var grid_width = 6
export(int, 2, 12) var grid_depth = 4
export(float, 4.0, 30.0) var cell_size = 10.0
export(float) var weight_W = 6.0
export(float) var weight_R = 5.0
export(float) var weight_P = 3.0
export(float) var weight_S = 8.0
export(float) var weight_C = 3.0
export(float) var weight_G = 0.5
export(float) var weight_X = 1.0
export(float) var weight_T = 2.0
export(float) var weight_E = 1.8
export(float) var weight_empty = 0.18
export(int, 10, 2000) var max_wfc_retries = 400
export(bool) var require_single_component = true
export(int, 0, 32) var min_stairs_per_map = 2
export(int, 0, 32) var min_elevated_cells = 3
export(int, 0, 32) var min_empty_cells = 2
export(float, 0.0, 20.0) var min_height_span = 2.0
export(bool) var constrain_border_heights = false
export(int, -1, 9999) var debug_seed_override = -1

const WEIGHTS_DICT = {
	"W": 6.0, "R": 5.0, "P": 3.0,
	"S": 3.0, "C": 2.0,
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
		var w = _weight_for_id(id) / 2.0
		all_variants.append(ModuleVariant.new(id, 0, [true, false, true, false], fpts, w))
		all_variants.append(ModuleVariant.new(id, 90, [false, true, false, true], fpts, w))
	var sw = _weight_for_id("S") / 4.0
	all_variants.append(ModuleVariant.new("S", 0, [true, false, true, false], [0.0, 0.0, 2.0, 0.0], sw))
	all_variants.append(ModuleVariant.new("S", 180, [true, false, true, false], [2.0, 0.0, 0.0, 0.0], sw))
	all_variants.append(ModuleVariant.new("S", 90, [false, true, false, true], [0.0, 0.0, 0.0, 2.0], sw))
	all_variants.append(ModuleVariant.new("S", 270, [false, true, false, true], [0.0, 2.0, 0.0, 0.0], sw))
	all_variants.append(ModuleVariant.new("P", 0, [true, true, true, true], fpts, _weight_for_id("P")))
	all_variants.append(ModuleVariant.new("X", 0, [true, true, true, true], fpts, _weight_for_id("X")))
	var cw = _weight_for_id("C") / 4.0
	all_variants.append(ModuleVariant.new("C", 0, [true, true, false, false], fpts, cw))
	all_variants.append(ModuleVariant.new("C", 90, [false, true, true, false], fpts, cw))
	all_variants.append(ModuleVariant.new("C", 180, [false, false, true, true], fpts, cw))
	all_variants.append(ModuleVariant.new("C", 270, [true, false, false, true], fpts, cw))

	var tw = _weight_for_id("T") / 4.0
	all_variants.append(ModuleVariant.new("T", 0, [true, true, false, true], fpts, tw))
	all_variants.append(ModuleVariant.new("T", 90, [true, true, true, false], fpts, tw))
	all_variants.append(ModuleVariant.new("T", 180, [false, true, true, true], fpts, tw))
	all_variants.append(ModuleVariant.new("T", 270, [true, false, true, true], fpts, tw))
	var ew = _weight_for_id("E") / 4.0
	all_variants.append(ModuleVariant.new("E", 0, [true, false, false, false], fpts, ew))
	all_variants.append(ModuleVariant.new("E", 90, [false, true, false, false], fpts, ew))
	all_variants.append(ModuleVariant.new("E", 180, [false, false, true, false], fpts, ew))
	all_variants.append(ModuleVariant.new("E", 270, [false, false, false, true], fpts, ew))
	all_variants.append(ModuleVariant.new("EMPTY", 0, [false, false, false, false], fpts, max(weight_empty, 0.0)))

func generate(seed_val: int = -1):
	if seed_val == -1: randomize()
	else: seed(seed_val)
	for child in get_children():
		child.queue_free()
	var grid = _wfc_generate()
	if not grid.empty():
		var counts = {}
		for s in grid:
			if s != null:
				var k = s.variant.id
				counts[k] = counts.get(k, 0) + 1
		print("[ScaffoldWFC] Module counts: ", counts)
		_instance_grid(grid)
	else:
		push_error("[ScaffoldWFC] generate() failed")

func _wfc_generate() -> Array:
	var best = []
	var best_score = -1.0
	for retry in range(max_wfc_retries):
		var res = _prune_disconnected_components(_validate_height_alignment(_wfc_attempt()))
		if not res.empty():
			var score = _connectivity_score(res)
			if score > best_score:
				best_score = score
				best = res
			var stairs_ok = _count_variant(res, "S") >= min_stairs_per_map
			var heights_ok = _height_span(res) >= min_height_span and _count_elevated_cells(res) >= min_elevated_cells
			var empties_ok = _count_variant(res, "EMPTY") >= min_empty_cells
			if _is_single_component(res) and stairs_ok and heights_ok and empties_ok:
				print("[ScaffoldWFC] Success on retry ", retry)
				return res
	if not best.empty():
		print("[ScaffoldWFC] Fallback best-effort map used (score=", best_score, ").")
		return best
	print("[ScaffoldWFC] FAILED after ", max_wfc_retries, " retries — grid unresolvable with current seed")
	return []

func _idx(x: int, y: int) -> int:
	return y * grid_width + x

func _wfc_attempt() -> Array:
	var gs = grid_width * grid_depth
	var ds = []
	var hds = []
	var collapsed = []
	collapsed.resize(gs)
	var phs = []
	for i in range(1, MAX_HEIGHT_STEPS + 1):
		phs.append(float(i) * HEIGHT_STEP)
	for i in range(gs):
		ds.append(all_variants.duplicate())
		hds.append(phs.duplicate())
		collapsed[i] = null
	# DEBUG: always include EMPTY in every cell domain to prevent contradictions
	for i in range(gs):
		var has_empty = false
		for v in ds[i]:
			if v.id == "EMPTY": has_empty = true
		if not has_empty:
			for v in all_variants:
				if v.id == "EMPTY": ds[i].append(v)
	_apply_boundary_constraints(ds, hds)
	var stp = 0
	while stp < gs:
		var me = 1000000
		var mi = -1
		for i in range(gs):
			if collapsed[i] != null:
				continue
			var e = ds[i].size()
			if e == 0:
				ds[i] = [_empty_variant()]
				hds[i] = [0.0]
				collapsed[i] = CellState.new(ds[i][0], 0.0)
				continue
			if e < me:
				me = e
				mi = i
		if mi == -1:
			break
		var _cx = mi % grid_width
		var _cy = mi / grid_width
		# Filter variant AND height together against collapsed neighbors.
		# Picking variant first then filtering heights (old approach) allowed a silent
		# fallback to an incompatible height when ho_f was empty. Instead, exclude any
		# variant that has no valid height given the current collapsed neighbors.
		var _valid_domains = []
		for _v in ds[mi]:
			var _vhs = []
			for _h in hds[mi]:
				var _ok = true
				for _dir in Direction.values():
					if not _v.connections[_dir]:
						continue
					var _dv = DIR_VEC[_dir]
					var _nx = _cx + int(_dv.x)
					var _ny = _cy + int(_dv.y)
					if _nx < 0 or _nx >= grid_width or _ny < 0 or _ny >= grid_depth:
						continue
					var _ni = _idx(_nx, _ny)
					if collapsed[_ni] == null:
						continue
					var _nc = collapsed[_ni]
					if not _nc.variant.connections[OPPOSITE[_dir]]:
						continue
					var _req = _nc.base_height + _nc.variant.port_heights[OPPOSITE[_dir]] - _v.port_heights[_dir]
					if abs(_h - _req) > 0.001:
						_ok = false
						break
				if _ok:
					_vhs.append(_h)
			if not _vhs.empty():
				_valid_domains.append({"variant": _v, "heights": _vhs})
		if _valid_domains.empty():
			var ev = _empty_variant()
			collapsed[mi] = CellState.new(ev, 0.0)
			ds[mi] = [ev]
			hds[mi] = [0.0]
			_propagate(ds, hds, collapsed, mi)
		else:
			var _vtotal = 0.0
			for _vd in _valid_domains:
				_vtotal += _vd.variant.weight
			var _vr = randf() * _vtotal
			var _vacc = 0.0
			var _picked = _valid_domains[0]
			for _vd in _valid_domains:
				_vacc += _vd.variant.weight
				if _vr <= _vacc:
					_picked = _vd
					break
			var cv = _picked.variant
			var ch = _picked.heights[randi() % _picked.heights.size()]
			collapsed[mi] = CellState.new(cv, ch)
			ds[mi] = [cv]
			hds[mi] = [ch]
			if not _propagate(ds, hds, collapsed, mi):
				var ev = _empty_variant()
				collapsed[mi] = CellState.new(ev, 0.0)
				ds[mi] = [ev]
				hds[mi] = [0.0]
				_propagate(ds, hds, collapsed, mi)
		stp += 1
	return collapsed

func _apply_boundary_constraints(ds: Array, hds: Array):
	var idx = 0
	for y in range(grid_depth):
		for x in range(grid_width):
			idx = _idx(x, y)
			var filtered = []
			for v in ds[idx]:
				var ok = true
				if y == 0:
					if v.connections[Direction.NORTH]: ok = false
				if y == grid_depth - 1:
					if v.connections[Direction.SOUTH]: ok = false
				if x == 0:
					if v.connections[Direction.WEST]: ok = false
				if x == grid_width - 1:
					if v.connections[Direction.EAST]: ok = false
				if ok:
					filtered.append(v)
			ds[idx] = filtered
		if constrain_border_heights:
			for x2 in range(grid_width):
				if y == 0:
					hds[_idx(x2, y)] = [HEIGHT_STEP]
				if y == grid_depth - 1:
					hds[_idx(x2, y)] = [4.0]

func _propagate(ds: Array, hds: Array, collapsed: Array, start_idx: int) -> bool:
	var stack = [start_idx]
	while not stack.empty():
		var ci = stack.pop_back()
		var cx = ci % grid_width
		var cy = ci / grid_width
		for dir in Direction.values():
			var vec = DIR_VEC[dir]
			var nx = cx + vec.x
			var ny = cy + vec.y
			if nx < 0 or nx >= grid_width or ny < 0 or ny >= grid_depth:
				continue
			var ni = _idx(nx, ny)
			if collapsed[ni] != null:
				# Exact height alignment check: for each variant in current domain that
				# connects to the already-collapsed neighbor, verify that at least one
				# height in the current domain produces the exact required neighbor height.
				# If a connecting variant has no valid height, it is removed from the domain.
				var next_state = collapsed[ni]
				var opp = OPPOSITE[dir]
				if next_state.variant.id != "EMPTY":
					var fv_ci = []
					var fh_ci = []
					for cv in ds[ci]:
						if cv.id == "EMPTY" or not cv.connections[dir] or not next_state.variant.connections[opp]:
							if not fv_ci.has(cv):
								fv_ci.append(cv)
							continue
						# Connecting pair — at least one height must match exactly.
						for ch in hds[ci]:
							var req = ch + cv.port_heights[dir] - next_state.variant.port_heights[opp]
							if abs(req - next_state.base_height) < 0.001:
								if not fv_ci.has(cv):
									fv_ci.append(cv)
								if not fh_ci.has(ch):
									fh_ci.append(ch)
					# Preserve heights that belong to non-connecting variants.
					for cv in ds[ci]:
						if cv.id == "EMPTY" or not cv.connections[dir] or not next_state.variant.connections[opp]:
							for ch in hds[ci]:
								if not fh_ci.has(ch):
									fh_ci.append(ch)
					if fv_ci.empty():
						return false
					var chg = false
					if fv_ci.size() < ds[ci].size():
						ds[ci] = fv_ci
						chg = true
					if not fh_ci.empty() and fh_ci.size() < hds[ci].size():
						hds[ci] = fh_ci
						chg = true
					if chg:
						stack.append(ci)
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
				if p:
					fv.append(nv)
			if fv.empty():
				var ev = _empty_variant()
				ds[ni] = [ev]
				hds[ni] = [HEIGHT_STEP]
				stack.append(ni)
				continue
			var hc = false
			for cv in ds[ci]:
				if cv.connections[dir]:
					hc = true
					break
			if not hc:
				fh = nhd
			if fh.empty():
				hds[ni] = [HEIGHT_STEP]
				stack.append(ni)
				continue
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

func _empty_variant() -> ModuleVariant:
	for v in all_variants:
		if v.id == "EMPTY":
			return v
	return ModuleVariant.new("EMPTY", 0, [false, false, false, false], [0.0, 0.0, 0.0, 0.0], max(weight_empty, 0.0))

func _check_pair(v_curr, h_curr, v_next, dir) -> Dictionary:
	var opp = OPPOSITE[dir]
	if v_curr.id == "EMPTY" or v_next.id == "EMPTY":
		return {"valid": true}
	if v_curr.connections[dir] != v_next.connections[opp]:
		return {"valid": false}
	var res = {"valid": true}
	if v_curr.connections[dir]:
		res.h = h_curr + v_curr.port_heights[dir] - v_next.port_heights[opp]
		if res.h < HEIGHT_STEP or res.h > MAX_HEIGHT_STEPS * HEIGHT_STEP:
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
	var main_component = _largest_connected_component(collapsed)
	var total = 0
	for i in range(collapsed.size()):
		if collapsed[i] != null and collapsed[i].variant.id != "EMPTY":
			total += 1
	return main_component.size() == total

func _connectivity_score(collapsed: Array) -> float:
	var non_empty = 0
	for i in range(collapsed.size()):
		if collapsed[i] != null and collapsed[i].variant.id != "EMPTY":
			non_empty += 1
	if non_empty == 0:
		return 0.0
	return float(_largest_connected_component(collapsed).size()) / float(non_empty)

func _count_variant(collapsed: Array, variant_id: String) -> int:
	var count = 0
	for s in collapsed:
		if s != null and s.variant.id == variant_id:
			count += 1
	return count

func _height_span(collapsed: Array) -> float:
	var found = false
	var min_h = 0.0
	var max_h = 0.0
	for s in collapsed:
		if s == null or s.variant.id == "EMPTY":
			continue
		if not found:
			min_h = s.base_height
			max_h = s.base_height
			found = true
			continue
		min_h = min(min_h, s.base_height)
		max_h = max(max_h, s.base_height)
	return 0.0 if not found else max_h - min_h

func _count_elevated_cells(collapsed: Array) -> int:
	var count = 0
	var min_h = INF
	for s in collapsed:
		if s == null or s.variant.id == "EMPTY":
			continue
		min_h = min(min_h, s.base_height)
	if min_h == INF:
		return 0
	for s in collapsed:
		if s == null or s.variant.id == "EMPTY":
			continue
		if s.base_height > min_h:
			count += 1
	return count

func _largest_connected_component(collapsed: Array) -> Dictionary:
	var visited = {}
	var best = {}
	for i in range(collapsed.size()):
		if visited.has(i):
			continue
		if collapsed[i] == null or collapsed[i].variant.id == "EMPTY":
			continue
		var component = _collect_connected_component(collapsed, i, visited)
		if component.size() > best.size():
			best = component
	return best

func _collect_connected_component(collapsed: Array, start: int, visited: Dictionary) -> Dictionary:
	var component = {}
	var q = [start]
	visited[start] = true
	component[start] = true
	while not q.empty():
		var curr = q.pop_front()
		var cx = curr % grid_width
		var cy = curr / grid_width
		var cv = collapsed[curr].variant
		for dir in Direction.values():
			if not cv.connections[dir]:
				continue
			var vec = DIR_VEC[dir]
			var nx = cx + vec.x
			var ny = cy + vec.y
			if nx < 0 or nx >= grid_width or ny < 0 or ny >= grid_depth:
				continue
			var ni = _idx(nx, ny)
			if visited.has(ni):
				continue
			if collapsed[ni] == null or collapsed[ni].variant.id == "EMPTY":
				continue
			if not collapsed[ni].variant.connections[OPPOSITE[dir]]:
				continue
			visited[ni] = true
			component[ni] = true
			q.push_back(ni)
	return component

func _prune_disconnected_components(collapsed: Array) -> Array:
	if collapsed.empty():
		return collapsed
	var main_component = _largest_connected_component(collapsed)
	if main_component.empty():
		return collapsed
	var ev = _empty_variant()
	for i in range(collapsed.size()):
		if collapsed[i] == null or collapsed[i].variant.id == "EMPTY":
			continue
		if not main_component.has(i):
			collapsed[i] = CellState.new(ev, 0.0)
	return collapsed

func _validate_height_alignment(collapsed: Array) -> Array:
	var ev = _empty_variant()
	var changed = true
	var total_removed = 0
	while changed:
		changed = false
		for i in range(collapsed.size()):
			if collapsed[i] == null or collapsed[i].variant.id == "EMPTY":
				continue
			var cx = i % grid_width
			var cy = i / grid_width
			var state = collapsed[i]
			for dir in Direction.values():
				if not state.variant.connections[dir]:
					continue
				var dv = DIR_VEC[dir]
				var nx = cx + int(dv.x)
				var ny = cy + int(dv.y)
				if nx < 0 or nx >= grid_width or ny < 0 or ny >= grid_depth:
					continue
				var ni = _idx(nx, ny)
				if collapsed[ni] == null or collapsed[ni].variant.id == "EMPTY":
					# Cell connects toward an EMPTY/null neighbor -- invalid.
					collapsed[i] = CellState.new(ev, 0.0)
					total_removed += 1
					changed = true
					break
				if not collapsed[ni].variant.connections[OPPOSITE[dir]]:
					collapsed[i] = CellState.new(ev, 0.0)
					total_removed += 1
					changed = true
					break
				var my_port = state.base_height + state.variant.port_heights[dir]
				var their_port = collapsed[ni].base_height + collapsed[ni].variant.port_heights[OPPOSITE[dir]]
				if abs(my_port - their_port) > 0.001:
					if debug_verbose:
						print("[ScaffoldWFC] validate: remove [%d,%d] %s h=%.1f port=%.1f mismatch neighbor h=%.1f port=%.1f dir=%d" % [cx, cy, state.variant.id, state.base_height, my_port, collapsed[ni].base_height, their_port, dir])
					collapsed[i] = CellState.new(ev, 0.0)
					total_removed += 1
					changed = true
					break
	print("[ScaffoldWFC] _validate_height_alignment removed %d cells" % total_removed)
	return collapsed

func _instance_grid(grid: Array):
	# Final guard: eliminate any height/connectivity mismatches before instancing.
	grid = _validate_height_alignment(grid)
	for y in range(grid_depth):
		for x in range(grid_width):
			var state = grid[_idx(x, y)]
			if state == null or state.variant.id == "EMPTY":
				continue
			var v = state.variant
			var inst = modules[v.id].instance()
			add_child(inst)
			# SteelGratePlatform builds the deck at local y = platform_height (default 1.6).
			# Compensate so the walkable surface lands at the WFC height in world space.
			var deck_local_y = inst.platform_height
			inst.translation = Vector3(x * cell_size, state.base_height - deck_local_y, y * cell_size)
			inst.rotation_degrees.y = -v.rotation
			# Legs must reach world y=0 (ground), accounting for the adjusted translation.
			inst.set("support_base_local_y", deck_local_y - state.base_height)
			var vid = v.id
			if vid == "W" or vid == "R" or vid == "G":
				_apply_local_dims(inst, _lane_width(), cell_size)
				if vid != "W":
					_apply_rails_from_connections(inst, v)
					_apply_opening_widths_from_connections(inst, v)
			elif vid == "P":
				_apply_local_dims(inst, cell_size, cell_size)
			elif vid == "S":
				_apply_local_dims(inst, _lane_width(), cell_size)
				_apply_port_heights_to_front_back(inst, v)
				_apply_rails_from_connections(inst, v)
				_apply_opening_widths_from_connections(inst, v)
			elif vid == "C":
				_apply_local_dims(inst, cell_size, cell_size)
				_apply_rails_from_connections(inst, v)
				_apply_opening_widths_from_connections(inst, v)
			elif vid == "X" or vid == "T":
				_apply_local_dims(inst, cell_size, cell_size)
				_apply_rails_from_connections(inst, v)
				_apply_opening_widths_from_connections(inst, v)
			elif vid == "E":
				_apply_local_dims(inst, cell_size, cell_size)
				_apply_rails_from_connections(inst, v)
				_apply_opening_widths_from_connections(inst, v)
			if inst.has_method("_rebuild"):
				inst.call("_rebuild")
			if debug_verbose:
				var conn_str = ""
				for d in Direction.values():
					conn_str += ("1" if v.connections[d] else "0")
				print("[ScaffoldWFC] [%d,%d] %s rot=%d conn=[%s] h=%.1f rail_f=%s b=%s l=%s r=%s ofw_f=%.1f ofw_b=%.1f ofw_l=%.1f ofw_r=%.1f" % [
					x, y, v.id, v.rotation, conn_str, state.base_height,
					inst.get("rail_front"), inst.get("rail_back"), inst.get("rail_left"), inst.get("rail_right"),
					inst.get("rail_front_opening_width"), inst.get("rail_back_opening_width"),
					inst.get("rail_left_opening_width"), inst.get("rail_right_opening_width")
				])

func _lane_width() -> float:
	return clamp(cell_size * 0.32, 2.5, 4.5)

func _weight_for_id(id: String) -> float:
	match id:
		"W":
			return weight_W
		"R":
			return weight_R
		"P":
			return weight_P
		"S":
			return weight_S
		"C":
			return weight_C
		"G":
			return weight_G
		"X":
			return weight_X
		"T":
			return weight_T
		"E":
			return weight_E
	return 1.0

func _dir_from_local_side(rot: int, side: String) -> int:
	# Map local scaffold sides to logical world ports using the variant rotation.
	# SteelGratePlatform: front = local -Z, back = local +Z, left = local -X, right = local +X.
	# Instance rotation: rotation_degrees.y = -rot.
	# Y-rotation by theta=-rot transforms local direction (lx,lz) to world via:
	#   wx = lx*cos(-rot) + lz*sin(-rot)
	#   wz = -lx*sin(-rot) + lz*cos(-rot)
	# Verified mappings:
	#   rot=0:   front→NORTH, left→WEST
	#   rot=90:  front→EAST,  left→NORTH
	#   rot=180: front→SOUTH, left→EAST
	#   rot=270: front→WEST,  left→SOUTH
	var r = int(posmod(rot, 360))
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

func _apply_port_heights_to_front_back(inst, v: ModuleVariant) -> void:
	var front_dir = _dir_from_local_side(v.rotation, "front")
	var back_dir = _dir_from_local_side(v.rotation, "back")
	inst.set("front_height_offset", v.port_heights[front_dir])
	inst.set("back_height_offset", v.port_heights[back_dir])

func _apply_rails_from_connections(inst, v: ModuleVariant) -> void:
	var front_dir = _dir_from_local_side(v.rotation, "front")
	var back_dir = _dir_from_local_side(v.rotation, "back")
	var left_dir = _dir_from_local_side(v.rotation, "left")
	var right_dir = _dir_from_local_side(v.rotation, "right")
	inst.set("rail_front", not v.connections[front_dir])
	inst.set("rail_back", not v.connections[back_dir])
	inst.set("rail_left", not v.connections[left_dir])
	inst.set("rail_right", not v.connections[right_dir])

func _apply_local_dims(inst, w: float, d: float):
	inst.set("platform_width", w)
	inst.set("platform_depth", d)

func _apply_opening_widths_from_connections(inst, v: ModuleVariant) -> void:
	var front_dir = _dir_from_local_side(v.rotation, "front")
	var back_dir = _dir_from_local_side(v.rotation, "back")
	var left_dir = _dir_from_local_side(v.rotation, "left")
	var right_dir = _dir_from_local_side(v.rotation, "right")
	var pw = _lane_width()
	if v.connections[front_dir]:
		inst.set("rail_front_opening_width", pw)
	if v.connections[back_dir]:
		inst.set("rail_back_opening_width", pw)
	if v.connections[left_dir]:
		inst.set("rail_left_opening_width", pw)
	if v.connections[right_dir]:
		inst.set("rail_right_opening_width", pw)
