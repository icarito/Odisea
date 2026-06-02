extends Reference
class_name WFCSolverCore

# Pure WFC solver — no scene tree, safe to run in a background thread.
# All scaffold instancing logic lives in ScaffoldWFCGenerator/_instance_grid.
#
# Performance notes:
#   - OS.delay_msec(0) is called periodically inside heavy loops to release the
#     GDScript thread lock so the Godot main thread can run its frames.
#   - _compat precomputes variant-pair compatibility so _propagate uses O(1) lookups.

enum Direction { NORTH = 0, EAST = 1, SOUTH = 2, WEST = 3 }

const DIR_VEC = {
	0: Vector2(0, -1),
	1: Vector2(1, 0),
	2: Vector2(0, 1),
	3: Vector2(-1, 0)
}

const OPPOSITE = { 0: 2, 1: 3, 2: 0, 3: 1 }

const HEIGHT_STEP = 2.0
const MAX_HEIGHT_STEPS = 5

# --- Params ---
var grid_width := 6
var grid_depth := 4
var cell_size := 10.0
var max_wfc_retries := 400
var require_single_component := true
var min_non_empty_cells := 8
var min_stairs_per_map := 2
var min_elevated_cells := 3
var min_empty_cells := 2
var min_height_span := 2.0
var constrain_border_heights := false

var weight_W := 6.0
var weight_R := 5.0
var weight_P := 3.0
var weight_S := 8.0
var weight_C := 3.0
var weight_G := 0.5
var weight_X := 1.0
var weight_T := 2.0
var weight_E := 1.8
var weight_empty := 0.18

var all_variants := []
var _variant_index := {}  # variant object -> index in all_variants

# _compat[dir][i][j] = true if variant i can have variant j in direction dir
var _compat := []

# --- Data classes ---
class ModuleVariant:
	var id: String
	var rotation: int
	var connections: Array
	var port_heights: Array
	var weight: float

	func _init(p_id, p_rot, p_conn, p_heights, p_weight):
		id = p_id
		rotation = p_rot
		connections = p_conn
		port_heights = p_heights
		weight = p_weight

class CellState:
	var variant  # ModuleVariant
	var base_height: float

	func _init(v, h):
		variant = v
		base_height = h

func apply_params(params: Dictionary) -> void:
	grid_width = params.get("grid_width", 6)
	grid_depth = params.get("grid_depth", 4)
	cell_size = params.get("cell_size", 10.0)
	max_wfc_retries = params.get("max_wfc_retries", 400)
	require_single_component = params.get("require_single_component", true)
	min_non_empty_cells = params.get("min_non_empty_cells", 8)
	min_stairs_per_map = params.get("min_stairs_per_map", 2)
	min_elevated_cells = params.get("min_elevated_cells", 3)
	min_empty_cells = params.get("min_empty_cells", 2)
	min_height_span = params.get("min_height_span", 2.0)
	constrain_border_heights = params.get("constrain_border_heights", false)
	weight_W = params.get("weight_W", 6.0)
	weight_R = params.get("weight_R", 5.0)
	weight_P = params.get("weight_P", 3.0)
	weight_S = params.get("weight_S", 8.0)
	weight_C = params.get("weight_C", 3.0)
	weight_G = params.get("weight_G", 0.5)
	weight_X = params.get("weight_X", 1.0)
	weight_T = params.get("weight_T", 2.0)
	weight_E = params.get("weight_E", 1.8)
	weight_empty = params.get("weight_empty", 0.18)
	_setup_variants()

func _weight_for_id(id: String) -> float:
	match id:
		"W": return weight_W
		"R": return weight_R
		"P": return weight_P
		"S": return weight_S
		"C": return weight_C
		"G": return weight_G
		"X": return weight_X
		"T": return weight_T
		"E": return weight_E
	return 1.0

func _setup_variants() -> void:
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
	_variant_index = {}
	_empty_variant_idx_cached = 0
	for i in range(all_variants.size()):
		_variant_index[all_variants[i]] = i
		if all_variants[i].id == "EMPTY":
			_empty_variant_idx_cached = i
	_build_compat_table()

func _build_compat_table() -> void:
	var n = all_variants.size()
	_compat = []
	for _dir in range(4):
		var mat = []
		mat.resize(n)
		for i in range(n):
			var row = []
			row.resize(n)
			var vi = all_variants[i]
			for j in range(n):
				var vj = all_variants[j]
				# EMPTY is compatible with everything.
				if vi.id == "EMPTY" or vj.id == "EMPTY":
					row[j] = true
				else:
					var opp = OPPOSITE[_dir]
					var ok = (vi.connections[_dir] == vj.connections[opp])
					if ok and vi.id == "G" and (_dir == 0 or _dir == 2):
						ok = (vj.id in ["R", "P", "C"])
					if ok and vj.id == "G" and (opp == 0 or opp == 2):
						ok = (vi.id in ["R", "P", "C"])
					row[j] = ok
			mat[i] = row
		_compat.append(mat)

func generate_grid_data(seed_val: int = -1) -> Array:
	if seed_val == -1: randomize()
	else: seed(seed_val)
	var raw = _wfc_generate()
	# Serialize to plain Dicts so inner-class instances don't dangle after solver is freed.
	var result = []
	result.resize(raw.size())
	for i in range(raw.size()):
		var s = raw[i]
		if s == null:
			result[i] = null
		else:
			result[i] = {
				"variant": {
					"id": s.variant.id,
					"rotation": s.variant.rotation,
					"connections": s.variant.connections.duplicate(),
					"port_heights": s.variant.port_heights.duplicate(),
					"weight": s.variant.weight,
				},
				"base_height": s.base_height,
			}
	return result

func _idx(x: int, y: int) -> int:
	return y * grid_width + x

func _empty_variant():
	for v in all_variants:
		if v.id == "EMPTY":
			return v
	return ModuleVariant.new("EMPTY", 0, [false, false, false, false], [0.0, 0.0, 0.0, 0.0], max(weight_empty, 0.0))

func _wfc_generate() -> Array:
	var best = []
	var best_score = -1.0
	for _retry in range(max_wfc_retries):
		OS.delay_msec(0)  # yield GDScript lock between retries
		var res = _prune_disconnected_components(_validate_height_alignment(_wfc_attempt()))
		if not res.empty():
			var score = _connectivity_score(res)
			if score > best_score:
				best_score = score
				best = res
			var non_empty_ok = _count_non_empty(res) >= min_non_empty_cells
			var stairs_ok = _count_variant(res, "S") >= min_stairs_per_map
			var heights_ok = _height_span(res) >= min_height_span and _count_elevated_cells(res) >= min_elevated_cells
			var empties_ok = _count_variant(res, "EMPTY") >= min_empty_cells
			var connectivity_ok = (not require_single_component) or _is_single_component(res)
			if connectivity_ok and non_empty_ok and stairs_ok and heights_ok and empties_ok:
				return res
	if not best.empty():
		return best
	return []

func _wfc_attempt() -> Array:
	OS.delay_msec(1)
	var gs = grid_width * grid_depth
	var n = all_variants.size()
	var ev_idx = _empty_variant_idx_cached

	# ds[i] = bool array of size n (domain mask — true = variant still possible)
	# hds[i] = Array of possible heights
	var ds = []
	var hds = []
	var collapsed = []
	collapsed.resize(gs)
	var phs = []
	for i in range(1, MAX_HEIGHT_STEPS + 1):
		phs.append(float(i) * HEIGHT_STEP)
	for i in range(gs):
		var d = []
		d.resize(n)
		for j in range(n): d[j] = true
		ds.append(d)
		hds.append(phs.duplicate())
		collapsed[i] = null

	_apply_boundary_constraints_idx(ds, hds)

	var stp = 0
	while stp < gs:
		if stp % 8 == 0:
			OS.delay_msec(0)
		# Find minimum-entropy uncollapsed cell
		var me = n + 1
		var mi = -1
		for i in range(gs):
			if collapsed[i] != null: continue
			var e = 0
			for j in range(n):
				if ds[i][j]: e += 1
			if e == 0:
				# Contradiction — collapse to EMPTY
				for j in range(n): ds[i][j] = false
				ds[i][ev_idx] = true
				collapsed[i] = CellState.new(all_variants[ev_idx], 0.0)
				continue
			if e < me:
				me = e
				mi = i
		if mi == -1:
			break

		# Check height constraints against already-collapsed neighbors
		var _cx = mi % grid_width
		var _cy = mi / grid_width
		var valid_vi = []   # indices of variants still valid given collapsed neighbors
		var valid_vh = []   # corresponding height arrays
		for vi in range(n):
			if not ds[mi][vi]: continue
			var v = all_variants[vi]
			var vhs = []
			for _h in hds[mi]:
				var _ok = true
				for _dir in [0, 1, 2, 3]:
					if not v.connections[_dir]: continue
					var _dv = DIR_VEC[_dir]
					var _nx = _cx + int(_dv.x)
					var _ny = _cy + int(_dv.y)
					if _nx < 0 or _nx >= grid_width or _ny < 0 or _ny >= grid_depth: continue
					var _ni = _idx(_nx, _ny)
					if collapsed[_ni] == null: continue
					var _nc = collapsed[_ni]
					if not _nc.variant.connections[OPPOSITE[_dir]]: continue
					var _req = _nc.base_height + _nc.variant.port_heights[OPPOSITE[_dir]] - v.port_heights[_dir]
					if abs(_h - _req) > 0.001:
						_ok = false
						break
				if _ok: vhs.append(_h)
			if not vhs.empty():
				valid_vi.append(vi)
				valid_vh.append(vhs)

		if valid_vi.empty():
			for j in range(n): ds[mi][j] = false
			ds[mi][ev_idx] = true
			hds[mi] = [0.0]
			collapsed[mi] = CellState.new(all_variants[ev_idx], 0.0)
			_propagate_idx(ds, hds, collapsed, mi)
		else:
			# Weighted random pick
			var total_w = 0.0
			for vi in valid_vi: total_w += all_variants[vi].weight
			var r = randf() * total_w
			var acc = 0.0
			var picked_vi = valid_vi[0]
			var picked_vhs = valid_vh[0]
			for k in range(valid_vi.size()):
				acc += all_variants[valid_vi[k]].weight
				if r <= acc:
					picked_vi = valid_vi[k]
					picked_vhs = valid_vh[k]
					break
			var ch = picked_vhs[randi() % picked_vhs.size()]
			for j in range(n): ds[mi][j] = false
			ds[mi][picked_vi] = true
			hds[mi] = [ch]
			collapsed[mi] = CellState.new(all_variants[picked_vi], ch)
			if not _propagate_idx(ds, hds, collapsed, mi):
				for j in range(n): ds[mi][j] = false
				ds[mi][ev_idx] = true
				hds[mi] = [0.0]
				collapsed[mi] = CellState.new(all_variants[ev_idx], 0.0)
				_propagate_idx(ds, hds, collapsed, mi)
		stp += 1
	return collapsed

var _empty_variant_idx_cached := 0

func _apply_boundary_constraints_idx(ds: Array, hds: Array) -> void:
	var n = all_variants.size()
	for y in range(grid_depth):
		for x in range(grid_width):
			var idx = _idx(x, y)
			for j in range(n):
				if not ds[idx][j]: continue
				var v = all_variants[j]
				if y == 0 and v.connections[0]: ds[idx][j] = false; continue
				if y == grid_depth - 1 and v.connections[2]: ds[idx][j] = false; continue
				if x == 0 and v.connections[3]: ds[idx][j] = false; continue
				if x == grid_width - 1 and v.connections[1]: ds[idx][j] = false
		if constrain_border_heights:
			for x2 in range(grid_width):
				if y == 0:   hds[_idx(x2, y)] = [HEIGHT_STEP]
				if y == grid_depth - 1: hds[_idx(x2, y)] = [4.0]

func _propagate_idx(ds: Array, hds: Array, collapsed: Array, start_idx: int) -> bool:
	# Arc-consistency propagation using precomputed _compat table.
	# Eliminates variants from uncollapsed neighbors that have no support in ci's domain.
	# Heights in hds are narrowed when a connection is confirmed.
	var stack = [start_idx]
	var in_stack = {}
	in_stack[start_idx] = true
	var n = all_variants.size()
	var ev_idx = _empty_variant_idx_cached
	var step = 0
	while not stack.empty():
		step += 1
		if step % 32 == 0:
			OS.delay_msec(0)
		var ci = stack.pop_back()
		in_stack.erase(ci)
		var cx = ci % grid_width
		var cy = ci / grid_width
		for dir in [0, 1, 2, 3]:
			var vec = DIR_VEC[dir]
			var nx = cx + int(vec.x)
			var ny = cy + int(vec.y)
			if nx < 0 or nx >= grid_width or ny < 0 or ny >= grid_depth: continue
			var ni = _idx(nx, ny)
			if collapsed[ni] != null: continue
			var compat_row = _compat[dir]
			var opp = OPPOSITE[dir]
			var changed = false
			var fh = []
			var nhd = hds[ni]
			for nj in range(n):
				if not ds[ni][nj]: continue
				var nv = all_variants[nj]
				var supported = false
				for cj in range(n):
					if not ds[ci][cj]: continue
					if not compat_row[cj][nj]: continue
					supported = true
					# Propagate heights for connected pairs
					var cv = all_variants[cj]
					if cv.connections[dir] and nv.connections[opp]:
						for ch in hds[ci]:
							var hn = ch + cv.port_heights[dir] - nv.port_heights[opp]
							if hn in nhd and not hn in fh:
								fh.append(hn)
					else:
						for hh in hds[ci]:
							if hh in nhd and not hh in fh:
								fh.append(hh)
					break  # found a supporter, no need to check more
				if not supported:
					ds[ni][nj] = false
					changed = true
			if not changed: continue
			var any_ni = false
			for j in range(n):
				if ds[ni][j]: any_ni = true; break
			if not any_ni:
				ds[ni][ev_idx] = true
			if not fh.empty() and fh.size() < nhd.size():
				hds[ni] = fh
			if not in_stack.has(ni):
				stack.append(ni)
				in_stack[ni] = true
	return true

func _variant_idx(v) -> int:
	return _variant_index.get(v, 0)

func _validate_height_alignment(collapsed: Array) -> Array:
	var ev = _empty_variant()
	# Pass 1: BFS-correct heights component by component.
	# Each connected component gets a random seed height; heights propagate
	# outward along open connections, correcting mismatches instead of pruning.
	var assigned = []
	assigned.resize(collapsed.size())
	for i in range(collapsed.size()): assigned[i] = false

	for root in range(collapsed.size()):
		if assigned[root]: continue
		if collapsed[root] == null or collapsed[root].variant.id == "EMPTY": continue
		# Seed this component at a random valid height
		var seed_h = float(1 + randi() % (MAX_HEIGHT_STEPS - 1)) * HEIGHT_STEP
		collapsed[root] = CellState.new(collapsed[root].variant, seed_h)
		assigned[root] = true
		var queue = [root]
		while not queue.empty():
			var ci = queue.pop_front()
			var state = collapsed[ci]
			if state == null or state.variant.id == "EMPTY": continue
			var cx = ci % grid_width
			var cy = ci / grid_width
			for dir in [0, 1, 2, 3]:
				if not state.variant.connections[dir]: continue
				var dv = DIR_VEC[dir]
				var nx = cx + int(dv.x)
				var ny = cy + int(dv.y)
				if nx < 0 or nx >= grid_width or ny < 0 or ny >= grid_depth: continue
				var ni = _idx(nx, ny)
				var ns = collapsed[ni]
				if ns == null or ns.variant.id == "EMPTY": continue
				if not ns.variant.connections[OPPOSITE[dir]]: continue
				var expected = state.base_height + state.variant.port_heights[dir] - ns.variant.port_heights[OPPOSITE[dir]]
				expected = clamp(expected, HEIGHT_STEP, MAX_HEIGHT_STEPS * HEIGHT_STEP)
				if not assigned[ni]:
					collapsed[ni] = CellState.new(ns.variant, expected)
					assigned[ni] = true
					queue.push_back(ni)

	# Cells not reached by any BFS (no open connections to neighbors) keep their attempt height
	for i in range(collapsed.size()):
		if collapsed[i] == null or collapsed[i].variant.id == "EMPTY": continue
		if not assigned[i]:
			var h = clamp(collapsed[i].base_height, HEIGHT_STEP, MAX_HEIGHT_STEPS * HEIGHT_STEP)
			collapsed[i] = CellState.new(collapsed[i].variant, h)
	# Pass 2: only prune cells with height conflicts on real (bidirectional) connections.
	# Open connections toward EMPTY are left as-is — the mesh handles them visually.
	var changed = true
	while changed:
		changed = false
		for i in range(collapsed.size()):
			if collapsed[i] == null or collapsed[i].variant.id == "EMPTY": continue
			var cx = i % grid_width
			var cy = i / grid_width
			var state = collapsed[i]
			for dir in [0, 1, 2, 3]:
				if not state.variant.connections[dir]: continue
				var dv = DIR_VEC[dir]
				var nx = cx + int(dv.x)
				var ny = cy + int(dv.y)
				if nx < 0 or nx >= grid_width or ny < 0 or ny >= grid_depth: continue
				var ni = _idx(nx, ny)
				var ns = collapsed[ni]
				if ns == null or ns.variant.id == "EMPTY": continue
				if not ns.variant.connections[OPPOSITE[dir]]: continue
				# Both sides open — check height consistency
				var my_port = state.base_height + state.variant.port_heights[dir]
				var their_port = ns.base_height + ns.variant.port_heights[OPPOSITE[dir]]
				if abs(my_port - their_port) > 0.001:
					collapsed[i] = CellState.new(ev, 0.0)
					changed = true
					break
	return collapsed

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
		for dir in [0, 1, 2, 3]:
			if not cv.connections[dir]:
				continue
			var vec = DIR_VEC[dir]
			var nx = cx + int(vec.x)
			var ny = cy + int(vec.y)
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

func _connectivity_score(collapsed: Array) -> float:
	var non_empty = 0
	for i in range(collapsed.size()):
		if collapsed[i] != null and collapsed[i].variant.id != "EMPTY":
			non_empty += 1
	if non_empty == 0:
		return 0.0
	return float(_largest_connected_component(collapsed).size()) / float(non_empty)

func _is_single_component(collapsed: Array) -> bool:
	var main_component = _largest_connected_component(collapsed)
	var total = 0
	for i in range(collapsed.size()):
		if collapsed[i] != null and collapsed[i].variant.id != "EMPTY":
			total += 1
	return main_component.size() == total

func _count_variant(collapsed: Array, variant_id: String) -> int:
	var count = 0
	for s in collapsed:
		if s != null and s.variant.id == variant_id:
			count += 1
	return count

func _count_non_empty(collapsed: Array) -> int:
	var count = 0
	for s in collapsed:
		if s != null and s.variant.id != "EMPTY":
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
