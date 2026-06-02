extends Reference
class_name ScaffoldMSTGenerator

# FD-050.3: MST-based Scaffold Generator (Performance Refactor)
# Objective: Fast, connected scaffolds using MST + room-based seeding.

enum Direction { NORTH = 0, EAST = 1, SOUTH = 2, WEST = 3 }
const DIR_VEC = { 0: Vector2(0, -1), 1: Vector2(1, 0), 2: Vector2(0, 1), 3: Vector2(-1, 0) }
const OPPOSITE = { 0: 2, 1: 3, 2: 0, 3: 1 }
const HEIGHT_STEP = 2.0
const MAX_HEIGHT_STEPS = 5

class ModuleVariant:
	var id: String
	var rotation: int
	var connections: Array
	var port_heights: Array
	var weight: float
	func _init(p_id, p_rot, p_conn, p_heights, p_weight):
		id = p_id; rotation = p_rot; connections = p_conn; port_heights = p_heights; weight = p_weight

class CellState:
	var variant
	var base_height: float
	func _init(v, h):
		variant = v
		base_height = h

var grid_width := 8
var grid_depth := 12
var cell_size := 6.0
var rng = RandomNumberGenerator.new()

func apply_params(params: Dictionary):
	grid_width = params.get("grid_width", 8)
	grid_depth = params.get("grid_depth", 12)
	cell_size = params.get("cell_size", 6.0)

func generate_grid_data(seed_val: int = -1) -> Array:
	if seed_val == -1: rng.randomize()
	else: rng.seed = seed_val
	
	var rooms = []
	var room_count = rng.randi_range(5, 8)
	var grid = []
	grid.resize(grid_width * grid_depth)
	var connections = []
	var heights = []
	for i in range(grid_width * grid_depth):
		connections.append([false, false, false, false])
		heights.append(-1.0)

	# 1. Room Placement
	for i in range(room_count):
		var rx = rng.randi() % grid_width
		var ry = rng.randi() % grid_depth
		var rh = float(rng.randi_range(1, MAX_HEIGHT_STEPS)) * HEIGHT_STEP
		rooms.append({"pos": Vector2(rx, ry), "h": rh})
		heights[ry * grid_width + rx] = rh

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
	for i in range(2):
		var e = edges[rng.randi() % edges.size()]
		if not mst_edges.has(e): mst_edges.append(e)

	# 3. Edge Filling (L-shape)
	for e in mst_edges:
		_trace_path(rooms[e.u], rooms[e.v], connections, heights)

	# 5. BFS for unassigned heights & Module Selection
	_fill_missing_heights(heights, connections)
	
	var result = []
	for i in range(grid_width * grid_depth):
		var conn = connections[i]
		var h = heights[i]
		if h < 0: result.append(null); continue
		
		var variant = _select_variant(conn, i, heights)
		result.append({
			"variant": {
				"id": variant.id, "rotation": variant.rotation, "connections": variant.connections,
				"port_heights": variant.port_heights, "weight": 1.0
			},
			"base_height": h
		})
	return result

func _sort_edges(a, b): return a.w < b.w
func _find(parent, i):
	if parent[i] == i: return i
	parent[i] = _find(parent, parent[i])
	return parent[i]
func _union(parent, i, j): parent[_find(parent, i)] = _find(parent, j)

func _trace_path(u, v, connections, heights):
	var curr = u.pos
	var target = v.pos
	while curr.x != target.x:
		var next_x = curr.x + (1 if target.x > curr.x else -1)
		_connect(curr, next_x, curr.y, connections, heights)
		curr.x = next_x
		if heights[curr.y * grid_width + curr.x] < 0: heights[curr.y * grid_width + curr.x] = u.h
	while curr.y != target.y:
		var next_y = curr.y + (1 if target.y > curr.y else -1)
		_connect(curr, curr.x, next_y, connections, heights)
		curr.y = next_y
		if heights[curr.y * grid_width + curr.x] < 0: heights[curr.y * grid_width + curr.x] = v.h

func _connect(p1, x2, y2, connections, heights):
	var d1 = _get_dir(p1, Vector2(x2, y2))
	connections[int(p1.y * grid_width + p1.x)][d1] = true
	connections[int(y2 * grid_width + x2)][OPPOSITE[d1]] = true

func _get_dir(p1, p2):
	if p2.x > p1.x: return Direction.EAST
	if p2.x < p1.x: return Direction.WEST
	if p2.y > p1.y: return Direction.SOUTH
	return Direction.NORTH

func _fill_missing_heights(heights, connections):
	var q = []
	for i in range(heights.size()): if heights[i] > 0: q.append(i)
	while not q.empty():
		var curr = q.pop_front()
		var cx = curr % grid_width; var cy = curr / grid_width
		for d in range(4):
			if not connections[curr][d]: continue
			var nv = DIR_VEC[d]; var nx = cx + nv.x; var ny = cy + nv.y
			if nx < 0 or nx >= grid_width or ny < 0 or ny >= grid_depth: continue
			var ni = int(ny * grid_width + nx)
			if heights[ni] < 0:
				heights[ni] = heights[curr]
				q.append(ni)

func _select_variant(conn, idx, heights):
	var c_count = 0
	for c in conn: if c: c_count += 1
	if c_count == 0: return ModuleVariant.new("EMPTY", 0, [false,false,false,false], [0,0,0,0], 0)
	
	var h = heights[idx]
	var ph = [0.0, 0.0, 0.0, 0.0]
	var cx = idx % grid_width; var cy = idx / grid_width
	for d in range(4):
		if not conn[d]: continue
		var nv = DIR_VEC[d]; var ni = int((cy + nv.y) * grid_width + (cx + nv.x))
		if ni >= 0 and ni < heights.size(): ph[d] = heights[ni] - h
	
	var is_stair = false
	for p in ph: if abs(p) > 0.001: is_stair = true; break
	
	if is_stair:
		if conn[Direction.NORTH] and conn[Direction.SOUTH]:
			return ModuleVariant.new("S", 0 if ph[Direction.SOUTH] > 0 else 180, [true, false, true, false], ph, 1)
		if conn[Direction.EAST] and conn[Direction.WEST]:
			return ModuleVariant.new("S", 90 if ph[Direction.WEST] > 0 else 270, [false, true, false, true], ph, 1)

	if c_count == 1:
		for d in range(4): if conn[d]: return ModuleVariant.new("E", d * 90, [d==0, d==1, d==2, d==3], ph, 1)
	if c_count == 2:
		if conn[0] and conn[2]: return ModuleVariant.new("W", 0, [true, false, true, false], ph, 1)
		if conn[1] and conn[3]: return ModuleVariant.new("W", 90, [false, true, false, true], ph, 1)
		if conn[0] and conn[1]: return ModuleVariant.new("C", 0, [true, true, false, false], ph, 1)
		if conn[1] and conn[2]: return ModuleVariant.new("C", 90, [false, true, true, false], ph, 1)
		if conn[2] and conn[3]: return ModuleVariant.new("C", 180, [false, false, true, true], ph, 1)
		if conn[3] and conn[0]: return ModuleVariant.new("C", 270, [true, false, false, true], ph, 1)
	if c_count == 3:
		for d in range(4):
			if not conn[d]:
				var rot = (d + 2) % 4
				var c = [true, true, true, true]; c[d] = false
				return ModuleVariant.new("T", rot * 90, c, ph, 1)
	return ModuleVariant.new("X", 0, [true, true, true, true], ph, 1)
