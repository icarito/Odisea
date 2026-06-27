extends Reference
class_name ScaffoldMSTGenerator

# FD-050.3: MST-based Scaffold Generator (Performance Refactor)
# Objective: Fast, connected scaffolds using MST + room-based seeding.

enum Direction { NORTH = 0, EAST = 1, SOUTH = 2, WEST = 3 }
const DIR_VEC = { 0: Vector2(0, -1), 1: Vector2(1, 0), 2: Vector2(0, 1), 3: Vector2(-1, 0) }
const OPPOSITE = { 0: 2, 1: 3, 2: 0, 3: 1 }
const HEIGHT_STEP = 2.0
const MAX_HEIGHT_STEPS = 6

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
	var variant
	var base_height: float
	func _init(v, h):
		variant = v
		base_height = h

var grid_width := 8
var grid_depth := 12
var cell_size := 6.0
var wrap_x := false
var rng = RandomNumberGenerator.new()
# Height range, configurable so the MST scaffold can be constrained to fit the
# surrounding level geometry. WFC and MST are different algorithms; with the full
# MAX_HEIGHT_STEPS range the MST scaffold climbs higher than the WFC layout the
# level was built around and intersects the static geometry (the Basement). Clamping
# the number of height steps keeps the generated scaffold inside the playable band.
var max_height_steps := MAX_HEIGHT_STEPS
var min_height_steps := 1
var requested_room_count := -1
var requested_extra_cycles := 2
# Deterministic seam tiles shared with neighbouring chunks. Keyed "x,y" -> {id,
# rotation, height}. When present, these cells are pinned to the given height so the
# scaffold joins continuously across chunk borders on the centrifugal axis (the same
# constraint the WFC path applies). Without it MST chunks generate independent border
# heights and clip through each other / the level.
var fixed_border_tiles := {}
var _pinned_indices := {}  # cell index -> true, never moved by smoothing
var _last_stair_base_shift := 0.0  # set by _select_variant; applied to base_height for stairs

func apply_params(params: Dictionary):
	grid_width = params.get("grid_width", 8)
	grid_depth = params.get("grid_depth", 12)
	cell_size = params.get("cell_size", 6.0)
	max_height_steps = int(clamp(params.get("mst_max_height_steps", MAX_HEIGHT_STEPS), 1, MAX_HEIGHT_STEPS))
	min_height_steps = int(clamp(params.get("mst_min_height_steps", 1), 1, max_height_steps))
	requested_room_count = int(params.get("room_count", -1))
	requested_extra_cycles = int(max(0, params.get("extra_cycles", 2)))
	var fb = params.get("fixed_border_tiles", {})
	fixed_border_tiles = fb if typeof(fb) == TYPE_DICTIONARY else {}
	wrap_x = params.get("wrap_x", false)
	# Cache pinned cell indices (border seams) so the smoothing passes never move them,
	# preserving cross-chunk continuity.
	_pinned_indices = {}
	for key in fixed_border_tiles.keys():
		var parts: Array = String(key).split(",")
		if parts.size() >= 2:
			var px := int(parts[0])
			var py := int(parts[1])
			if px >= 0 and px < grid_width and py >= 0 and py < grid_depth:
				_pinned_indices[py * grid_width + px] = true

# Returns the index of the neighbour cell in direction d, or -1 if out of grid.
# When wrap_x, the X (angular) axis is cyclic: x=-1 wraps to grid_width-1, x=grid_width wraps to 0.
func _neighbor(x: int, y: int, d: int) -> int:
	var nv = DIR_VEC[d]
	var nx: int = x + int(nv.x)
	var ny: int = y + int(nv.y)
	if wrap_x:
		nx = int(posmod(nx, grid_width))
	elif nx < 0 or nx >= grid_width:
		return -1
	if ny < 0 or ny >= grid_depth:
		return -1
	return ny * grid_width + nx

func generate_grid_data(seed_val: int = -1) -> Array:
	if seed_val == -1: rng.randomize()
	else: rng.seed = seed_val

	var rooms = []
	var room_indices := {}
	var target_room_count = requested_room_count if requested_room_count > 0 else rng.randi_range(5, 8)
	target_room_count = int(clamp(target_room_count, 1, max(1, grid_width * grid_depth)))
	var grid = []
	grid.resize(grid_width * grid_depth)
	var connections = []
	var heights = []
	for i in range(grid_width * grid_depth):
		connections.append([false, false, false, false])
		heights.append(-1.0)

	# 0. Pin shared border seam tiles first so adjacent chunks join continuously.
	# These come from the stream's deterministic per-border hash, so this chunk and
	# its neighbour agree on the seam height. They act as fixed rooms the MST must
	# connect to, keeping the generated scaffold aligned across the centrifugal axis.
	for key in fixed_border_tiles.keys():
		var parts: Array = String(key).split(",")
		if parts.size() < 2:
			continue
		var cx := int(parts[0])
		var cy := int(parts[1])
		if cx < 0 or cx >= grid_width or cy < 0 or cy >= grid_depth:
			continue
		var spec = fixed_border_tiles[key]
		var bh := float(spec.get("height", HEIGHT_STEP)) if typeof(spec) == TYPE_DICTIONARY else HEIGHT_STEP
		var bi := cy * grid_width + cx
		heights[bi] = bh
		rooms.append({"pos": Vector2(cx, cy), "h": bh})
		room_indices[bi] = true
		# Open the seam tile's OUTWARD side toward the neighbouring chunk so the two
		# chunks actually bridge. Without this the seam heights match but no walkable
		# connection crosses the boundary — chunks look connectable but aren't. (The
		# stream's hash makes this chunk's outward port and the neighbour's coincide.)
		if cx == 0:
			connections[bi][Direction.WEST] = true
		elif cx == grid_width - 1:
			connections[bi][Direction.EAST] = true
		if cy == 0:
			connections[bi][Direction.NORTH] = true
		elif cy == grid_depth - 1:
			connections[bi][Direction.SOUTH] = true

	# 1. Room Placement
	var room_attempts := 0
	while rooms.size() < target_room_count and room_attempts < target_room_count * 8:
		room_attempts += 1
		var rx = rng.randi() % grid_width
		var ry = rng.randi() % grid_depth
		# Don't overwrite a pinned border seam tile.
		if heights[ry * grid_width + rx] >= 0.0:
			continue
		var rh = float(rng.randi_range(min_height_steps, max_height_steps)) * HEIGHT_STEP
		rooms.append({"pos": Vector2(rx, ry), "h": rh})
		var ri: int = int(ry * grid_width + rx)
		heights[ri] = rh
		room_indices[ri] = true

	# 2. MST Construction (Kruskal's)
	var edges = []
	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			var dist = abs(rooms[i].pos.x - rooms[j].pos.x) + abs(rooms[i].pos.y - rooms[j].pos.y)
			edges.append({"u": i, "v": j, "w": dist})
	edges.sort_custom(self, "_sort_edges")

	var parent = []
	for i in range(rooms.size()): parent.append(i)

	var mst_edges = []
	for e in edges:
		if _find(parent, e.u) != _find(parent, e.v):
			_union(parent, e.u, e.v)
			mst_edges.append(e)

	# 4. Cycles
	for i in range(requested_extra_cycles):
		if edges.empty():
			break
		var e = edges[rng.randi() % edges.size()]
		if not mst_edges.has(e): mst_edges.append(e)

	# 3. Edge Filling (L-shape)
	for e in mst_edges:
		_trace_path(rooms[e.u], rooms[e.v], connections, heights)

	# 5. BFS for unassigned heights & Module Selection
	_fill_missing_heights(heights, connections)
	_connect_adjacent_equal_height_cells(heights, connections)
	# Limit slope FIRST: WFC stairs only span one HEIGHT_STEP (2m) per cell, so its ramps
	# are gentle. The MST connects rooms of arbitrary height, producing multi-step drops
	# across a single edge — very steep ramps. Clamp every connected edge to at most one
	# step. Then flatten any residual height differences that land on cells which can't
	# host a stair (corners/junctions): a stair tile is only emitted for a straight
	# through-cell (two opposite connections), so a delta on a corner would otherwise
	# leave a visual gap where the ramp doesn't reach the neighbour's height. Iterate the
	# two passes until stable so lowering a cell never reintroduces an un-hostable delta.
	var pass_guard := 0
	while pass_guard < 8:
		pass_guard += 1
		_limit_slope_to_one_step(heights, connections)
		if not _flatten_invalid_height_edges(heights, connections):
			break

	# Guarantee every border seam port is reachable from the rest of the chunk, so the
	# scaffold connects across chunk boundaries — like the WFC backbone does. A seam tile
	# that ended up isolated (its MST path pinched off by flattening) gets a cheap direct
	# L-path traced to the nearest connected cell. Re-running slope/flatten can re-pinch
	# the new path, so iterate reconnect→smooth until every port is connected (or we hit
	# the guard).
	var connect_guard := 0
	while connect_guard < 6 and _ensure_border_ports_connected(heights, connections):
		connect_guard += 1
		_limit_slope_to_one_step(heights, connections)
		_flatten_invalid_height_edges(heights, connections)

	# Finalize railings/edges:
	#  - Merge half-open edges: if a populated cell connects to a populated neighbour at
	#    the same height but the neighbour doesn't connect back, make it mutual so the
	#    two platforms join instead of showing two adjacent railing gaps.
	#  - Prune connections that point at an empty cell or a neighbour more than one step
	#    away: those render as a railing opening onto the void. Closing the side draws a
	#    railing there instead.
	_finalize_edges(heights, connections)

	# Break chained ramps: every stair must rise toward a FLAT deck, never toward
	# another stair. Two adjacent cells that both change height along the same axis
	# render as ramp-into-ramp where the upper ramp's foot meets the lower ramp's rail
	# instead of a floor. Insert a flat landing by levelling one cell of each such pair
	# to its lower neighbour, so the climb becomes deck → ramp → deck → ramp → deck.
	_break_stair_chains(heights, connections)
	# A seam tile must be FLAT across the chunk boundary: the height change has to
	# happen one cell inward, never on the border cell itself. Otherwise the border
	# stair ramps toward the neighbouring chunk / the void and reads as a misplaced
	# ramp. Pull the inner neighbour of each seam tile to the seam height so the ramp
	# sits at least one cell in, then re-finalize.
	_flatten_seam_tiles(heights, connections)
	# Levelling may have reopened over-steep or void edges; re-finalize once.
	_finalize_edges(heights, connections)

	var result = []
	for i in range(grid_width * grid_depth):
		var conn = connections[i]
		var h = heights[i]
		if h < 0:
			result.append(null)
			continue

		_last_stair_base_shift = 0.0
		var variant = _select_variant(conn, i, heights)
		# For a stair whose ports were normalized to non-negative, lower base_height by
		# the same amount so the ramp's low end stays on the lower deck's floor.
		result.append({
			"variant": {
				"id": variant.id, "rotation": variant.rotation, "connections": variant.connections,
				"port_heights": variant.port_heights, "weight": 1.0
			},
			"base_height": h + _last_stair_base_shift,
			"is_room": room_indices.has(i)
		})
	return result

# Pulls connected cells together so no edge spans more than one HEIGHT_STEP. The
# higher side of an over-steep edge is lowered toward the lower side, in steps,
# until every connected pair differs by at most HEIGHT_STEP. Pinned border seam
# cells are never moved so chunks stay aligned across the centrifugal axis.
func _limit_slope_to_one_step(heights, connections) -> void:
	var pinned := {}
	for key in fixed_border_tiles.keys():
		var parts: Array = String(key).split(",")
		if parts.size() >= 2:
			pinned[int(parts[1]) * grid_width + int(parts[0])] = true
	var changed := true
	var guard := 0
	while changed and guard < 64:
		changed = false
		guard += 1
		for y in range(grid_depth):
			for x in range(grid_width):
				var i := int(y * grid_width + x)
				if heights[i] < 0:
					continue
				for d in range(4):
					if not connections[i][d]:
						continue
					var ni := _neighbor(x, y, d)
					if ni < 0:
						continue
					if heights[ni] < 0:
						continue
					var diff: float = heights[i] - heights[ni]
					if abs(diff) <= HEIGHT_STEP + 0.001:
						continue
					# Lower the higher of the two by one step (skip pinned cells).
					if diff > 0.0 and not pinned.has(i):
						heights[i] -= HEIGHT_STEP
						changed = true
					elif diff < 0.0 and not pinned.has(ni):
						heights[ni] -= HEIGHT_STEP
						changed = true

# Ensures each pinned border seam tile is mutually connected to the main component.
# Returns true if it added any path. Cheap reconnect: BFS the largest connected
# component, then for each unreachable border tile trace a straight L-path to the
# nearest reachable cell.
func _ensure_border_ports_connected(heights, connections) -> bool:
	if fixed_border_tiles.empty():
		return false
	var reachable := _compute_reachable_set(connections, heights)
	if reachable.empty():
		return false
	var added := false
	for key in fixed_border_tiles.keys():
		var parts: Array = String(key).split(",")
		if parts.size() < 2:
			continue
		var bx := int(parts[0])
		var by := int(parts[1])
		if bx < 0 or bx >= grid_width or by < 0 or by >= grid_depth:
			continue
		var bi := by * grid_width + bx
		if heights[bi] < 0 or reachable.has(bi):
			continue
		# Find nearest reachable cell (Manhattan) and trace an L-path to it.
		var best := -1
		var best_dist := 1 << 30
		for ri in reachable.keys():
			var rxi := int(ri)
			var rx := rxi % grid_width
			var ry := rxi / grid_width
			var dist_x: int = abs(rx - bx)
			if wrap_x:
				dist_x = min(dist_x, grid_width - dist_x)
			var dist: int = dist_x + abs(ry - by)
			if dist < best_dist:
				best_dist = dist
				best = ri
		if best < 0:
			continue
		var src := {"pos": Vector2(bx, by), "h": heights[bi]}
		var dst := {"pos": Vector2(best % grid_width, best / grid_width), "h": heights[best]}
		_trace_path(src, dst, connections, heights)
		added = true
	return added

# BFS over mutually-connected cells, returning the set (Dictionary as set) of the
# component reachable from the first non-empty cell.
func _compute_reachable_set(connections, heights) -> Dictionary:
	var start := -1
	for i in range(grid_width * grid_depth):
		if heights[i] >= 0:
			start = i
			break
	var seen := {}
	if start < 0:
		return seen
	seen[start] = true
	var q := [start]
	while not q.empty():
		var c: int = q.pop_front()
		var cx := c % grid_width
		var cy := c / grid_width
		for d in range(4):
			if not connections[c][d]:
				continue
			var ni := _neighbor(cx, cy, d)
			if ni < 0:
				continue
			if heights[ni] < 0 or seen.has(ni):
				continue
			if connections[ni][OPPOSITE[d]]:
				seen[ni] = true
				q.append(ni)
	return seen

# Forces the inner neighbour of each pinned seam tile to the seam height, so the
# border cell is flat across the boundary and any ramp sits at least one cell inward.
func _flatten_seam_tiles(heights, connections) -> void:
	for key in fixed_border_tiles.keys():
		var parts: Array = String(key).split(",")
		if parts.size() < 2:
			continue
		var bx := int(parts[0])
		var by := int(parts[1])
		if bx < 0 or bx >= grid_width or by < 0 or by >= grid_depth:
			continue
		var bi := by * grid_width + bx
		if heights[bi] < 0:
			continue
		# The inward direction is opposite the chunk edge this tile sits on.
		var ix := bx
		var iy := by
		if bx == 0:
			ix = 1
		elif bx == grid_width - 1:
			ix = grid_width - 2
		if by == 0:
			iy = 1
		elif by == grid_depth - 1:
			iy = grid_depth - 2
		if ix == bx and iy == by:
			continue  # not actually on an edge
		var ii := iy * grid_width + ix
		if ii < 0 or ii >= heights.size() or heights[ii] < 0:
			continue
		# Only flatten if a small (one-step) seam-to-inner delta would otherwise put
		# the ramp on the border cell; leave larger interior terrain alone.
		if abs(heights[ii] - heights[bi]) <= HEIGHT_STEP + 0.001 and not _pinned_indices.has(ii):
			heights[ii] = heights[bi]

# A cell "is a stair" if any connected neighbour sits at a different height.
func _cell_is_stair(heights, connections, i: int) -> bool:
	if heights[i] < 0:
		return false
	var cx := i % grid_width
	var cy := i / grid_width
	for d in range(4):
		if not connections[i][d]:
			continue
		var ni := _neighbor(cx, cy, d)
		if ni < 0:
			continue
		if heights[ni] >= 0 and abs(heights[i] - heights[ni]) > 0.001:
			return true
	return false

# Levels cells so no two adjacent stairs sit in a row: when a stair connects to a
# neighbour that is also a stair at a different height, drop the higher of the pair
# to the lower's height (creating a flat landing). Pinned seam cells are never moved.
# Iterates until stable.
func _break_stair_chains(heights, connections) -> void:
	var guard := 0
	var changed := true
	while changed and guard < 32:
		changed = false
		guard += 1
		for y in range(grid_depth):
			for x in range(grid_width):
				var i := int(y * grid_width + x)
				if heights[i] < 0 or not _cell_is_stair(heights, connections, i):
					continue
				for d in range(4):
					if not connections[i][d]:
						continue
					var ni := _neighbor(x, y, d)
					if ni < 0:
						continue
					if heights[ni] < 0:
						continue
					if abs(heights[i] - heights[ni]) <= 0.001:
						continue
					if not _cell_is_stair(heights, connections, ni):
						continue
					# Both i and ni are stairs at different heights → level the higher
					# to the lower to form a landing (never move a pinned seam).
					if heights[i] > heights[ni] and not _pinned_indices.has(i):
						heights[i] = heights[ni]
						changed = true
					elif heights[ni] > heights[i] and not _pinned_indices.has(ni):
						heights[ni] = heights[i]
						changed = true

# Final edge cleanup so railings close on the void and adjacent platforms join.
func _finalize_edges(heights, connections) -> void:
	# Pass A: make same-height adjacencies mutual (join touching platforms).
	for y in range(grid_depth):
		for x in range(grid_width):
			var i := int(y * grid_width + x)
			if heights[i] < 0:
				continue
			for d in range(4):
				var ni := _neighbor(x, y, d)
				if ni < 0:
					continue
				if heights[ni] < 0:
					continue
				# Either side already open at the same height → make it mutual.
				if (connections[i][d] or connections[ni][OPPOSITE[d]]) \
						and abs(heights[i] - heights[ni]) <= 0.001:
					connections[i][d] = true
					connections[ni][OPPOSITE[d]] = true
	# Pass B: prune connections that open onto emptiness or an unreachable step gap,
	# so a railing is drawn there instead of a hole.
	for y in range(grid_depth):
		for x in range(grid_width):
			var i := int(y * grid_width + x)
			if heights[i] < 0:
				continue
			for d in range(4):
				if not connections[i][d]:
					continue
				var ni := _neighbor(x, y, d)
				if ni < 0:
					# Out of grid: keep only if it's a pinned seam tile's outward port.
					if not _pinned_indices.has(i):
						connections[i][d] = false
					continue
				# Neighbour empty, or height gap too large to host a stair → close side.
				if heights[ni] < 0 or abs(heights[i] - heights[ni]) > HEIGHT_STEP + 0.001:
					connections[i][d] = false

func _sort_edges(a, b): return a.w < b.w
func _find(parent, i):
	if parent[i] == i: return i
	parent[i] = _find(parent, parent[i])
	return parent[i]
func _union(parent, i, j): parent[_find(parent, i)] = _find(parent, j)

func _trace_path(u, v, connections, heights):
	var curr = u.pos
	var target = v.pos
	# When wrapping, take the shorter angular path around the cylinder.
	var dx: float = target.x - curr.x
	if wrap_x:
		if dx > float(grid_width) * 0.5:
			dx -= float(grid_width)
		elif dx < -float(grid_width) * 0.5:
			dx += float(grid_width)
	while int(curr.x) != int(target.x) and abs(dx) > 0.001:
		var step := 1 if dx > 0 else -1
		var next_x = int(posmod(curr.x + step, grid_width)) if wrap_x else int(curr.x + step)
		_connect_wrap(curr, next_x, curr.y, connections, heights)
		curr.x = next_x
		if heights[int(curr.y) * grid_width + int(curr.x)] < 0: heights[int(curr.y) * grid_width + int(curr.x)] = u.h
		dx -= step
	while curr.y != target.y:
		var next_y = curr.y + (1 if target.y > curr.y else -1)
		_connect_wrap(curr, curr.x, next_y, connections, heights)
		curr.y = next_y
		if heights[int(curr.y) * grid_width + int(curr.x)] < 0: heights[int(curr.y) * grid_width + int(curr.x)] = v.h

func _connect_wrap(p1, x2, y2, connections, heights):
	var d1 = _get_dir_wrap(p1, Vector2(x2, y2))
	var i1 := int(int(p1.y) * grid_width + int(p1.x))
	var i2 := int(int(y2) * grid_width + int(x2))
	connections[i1][d1] = true
	connections[i2][OPPOSITE[d1]] = true

func _get_dir_wrap(p1, p2):
	var dx: float = p2.x - p1.x
	if wrap_x:
		if dx > float(grid_width) * 0.5: dx -= float(grid_width)
		elif dx < -float(grid_width) * 0.5: dx += float(grid_width)
	if dx > 0.001: return Direction.EAST
	if dx < -0.001: return Direction.WEST
	if p2.y > p1.y: return Direction.SOUTH
	return Direction.NORTH

func _fill_missing_heights(heights, connections):
	var q = []
	for i in range(heights.size()): if heights[i] > 0: q.append(i)
	while not q.empty():
		var curr = q.pop_front()
		var cx = curr % grid_width
		var cy = curr / grid_width
		for d in range(4):
			if not connections[curr][d]: continue
			var ni := _neighbor(int(cx), int(cy), d)
			if ni < 0: continue
			if heights[ni] < 0:
				heights[ni] = heights[curr]
				q.append(ni)

func _connect_adjacent_equal_height_cells(heights, connections) -> void:
	for y in range(grid_depth):
		for x in range(grid_width):
			var i = int(y * grid_width + x)
			if heights[i] < 0:
				continue
			for d in [Direction.EAST, Direction.SOUTH]:
				var ni := _neighbor(x, y, d)
				if ni < 0:
					continue
				if heights[ni] < 0:
					continue
				if abs(heights[i] - heights[ni]) <= 0.001:
					connections[i][d] = true
					connections[ni][OPPOSITE[d]] = true

func _flatten_invalid_height_edges(heights, connections) -> bool:
	var changed = true
	var guard = 0
	var any_change := false
	while changed and guard < 16:
		changed = false
		guard += 1
		for y in range(grid_depth):
			for x in range(grid_width):
				var i = int(y * grid_width + x)
				if heights[i] < 0:
					continue
				for d in range(4):
					if not connections[i][d]:
						continue
					var ni := _neighbor(x, y, d)
					if ni < 0:
						continue
					if heights[ni] < 0:
						continue
					if abs(heights[i] - heights[ni]) <= 0.001:
						continue
					if _edge_can_host_stair(connections, i, ni, d):
						continue
					# Flatten by matching one cell to the other, but never move a pinned
					# seam cell (that would break cross-chunk continuity). Prefer moving
					# the non-pinned side; if both are pinned, leave it (can't flatten).
					if not _pinned_indices.has(ni):
						heights[ni] = heights[i]
						changed = true
						any_change = true
					elif not _pinned_indices.has(i):
						heights[i] = heights[ni]
						changed = true
						any_change = true
	return any_change

func _edge_can_host_stair(connections, i: int, ni: int, d: int) -> bool:
	return _cell_can_host_stair_axis(connections[i], d) or _cell_can_host_stair_axis(connections[ni], OPPOSITE[d])

func _cell_can_host_stair_axis(conn: Array, d: int) -> bool:
	if not conn[d] or not conn[OPPOSITE[d]]:
		return false
	var count = 0
	for c in conn:
		if c:
			count += 1
	return count == 2

func _select_variant(conn, idx, heights):
	var c_count = 0
	for c in conn: if c: c_count += 1
	if c_count == 0: return ModuleVariant.new("EMPTY", 0, [false,false,false,false], [0,0,0,0], 0)

	var h = heights[idx]
	var ph = [0.0, 0.0, 0.0, 0.0]
	var cx = idx % grid_width
	var cy = idx / grid_width
	for d in range(4):
		if not conn[d]: continue
		var ni := _neighbor(cx, cy, d)
		if ni < 0:
			continue
		ph[d] = heights[ni] - h

	var is_stair = false
	for p in ph:
		if abs(p) > 0.001:
			is_stair = true
			break

	if is_stair:
		# Normalize stair ports to the WFC convention: NON-NEGATIVE deltas with the low
		# side at 0. The ramp mesh is built from base_height + low_h .. base_height +
		# high_h; if a port were negative (a neighbour lower than this cell) the ramp
		# would start below this cell's floor and visually meet the railing height of
		# the lower deck instead of its floor — the "stairs point at the railing, don't
		# connect to the floor" bug. base_height is shifted down by the same min so the
		# low end still sits on the lower deck's floor.
		var min_delta := 0.0
		for d in range(4):
			if conn[d] and ph[d] < min_delta:
				min_delta = ph[d]
		if min_delta < 0.0:
			for d in range(4):
				if conn[d]:
					ph[d] -= min_delta
			# Record the base shift so the result loop can lower base_height to match.
			_last_stair_base_shift = min_delta
		else:
			_last_stair_base_shift = 0.0
		if conn[Direction.NORTH] and conn[Direction.SOUTH]:
			return ModuleVariant.new("S", 0 if ph[Direction.SOUTH] > ph[Direction.NORTH] else 180, [true, false, true, false], ph, 1)
		if conn[Direction.EAST] and conn[Direction.WEST]:
			return ModuleVariant.new("S", 90 if ph[Direction.WEST] > ph[Direction.EAST] else 270, [false, true, false, true], ph, 1)
	_last_stair_base_shift = 0.0

	# Non-stair variants use flat port_heights — their height is encoded in base_height.
	# Only stairs need the relative delta to drive the slope mesh.
	var flat = [0.0, 0.0, 0.0, 0.0]
	if c_count == 1:
		for d in range(4): if conn[d]: return ModuleVariant.new("E", d * 90, [d==0, d==1, d==2, d==3], flat, 1)
	if c_count == 2:
		if conn[0] and conn[2]: return ModuleVariant.new("W", 0, [true, false, true, false], flat, 1)
		if conn[1] and conn[3]: return ModuleVariant.new("W", 90, [false, true, false, true], flat, 1)
		if conn[0] and conn[1]: return ModuleVariant.new("C", 0, [true, true, false, false], flat, 1)
		if conn[1] and conn[2]: return ModuleVariant.new("C", 90, [false, true, true, false], flat, 1)
		if conn[2] and conn[3]: return ModuleVariant.new("C", 180, [false, false, true, true], flat, 1)
		if conn[3] and conn[0]: return ModuleVariant.new("C", 270, [true, false, false, true], flat, 1)
	if c_count == 3:
		for d in range(4):
			if not conn[d]:
				var rot = (d + 2) % 4
				var c = [true, true, true, true]
				c[d] = false
				return ModuleVariant.new("T", rot * 90, c, flat, 1)
	return ModuleVariant.new("X", 0, [true, true, true, true], flat, 1)
