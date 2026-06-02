extends Node
# Test 1: port height alignment between every pair of connected adjacent cells.
# base_height + port_heights[dir] == neighbor.base_height + neighbor.port_heights[OPPOSITE[dir]]

const GEN_SCRIPT = preload("res://core_v2/systems/ScaffoldWFCGenerator.gd")

const OPPOSITE = {0: 2, 1: 3, 2: 0, 3: 1}
const DIR_VEC = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]

var _passed := 0
var _failed := 0

func _ready():
	for s in [42, 99, 777]:
		_run(s)
	print("[T1:HeightAlignment] passed=%d failed=%d" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _run(seed_val: int) -> void:
	var gen = GEN_SCRIPT.new()
	gen.map_seed = seed_val
	gen.max_wfc_retries = 400
	gen.debug_verbose = false
	add_child(gen)
	var grid = gen.call("_wfc_generate")

	if grid.empty():
		print("[T1] FAIL seed=%d: grid empty" % seed_val)
		_failed += 1
		gen.queue_free()
		return

	var gw = gen.grid_width
	var gd = gen.grid_depth
	var mismatches = []

	for i in range(grid.size()):
		var state = grid[i]
		if state == null or state.variant.id == "EMPTY":
			continue
		var cx = i % gw
		var cy = i / gw
		for dir in [0, 1, 2, 3]:
			if not state.variant.connections[dir]:
				continue
			var dv = DIR_VEC[dir]
			var nx = cx + int(dv.x)
			var ny = cy + int(dv.y)
			if nx < 0 or nx >= gw or ny < 0 or ny >= gd:
				continue
			var ni = ny * gw + nx
			var nb = grid[ni]
			if nb == null or nb.variant.id == "EMPTY":
				continue
			if not nb.variant.connections[OPPOSITE[dir]]:
				continue
			var my_port = state.base_height + state.variant.port_heights[dir]
			var their_port = nb.base_height + nb.variant.port_heights[OPPOSITE[dir]]
			if abs(my_port - their_port) > 0.01:
				mismatches.append("  [%d,%d]%s h=%.1f+ph=%.1f=%.1f <-> [%d,%d]%s h=%.1f+ph=%.1f=%.1f dir=%d" % [
					cx, cy, state.variant.id, state.base_height, state.variant.port_heights[dir], my_port,
					nx, ny, nb.variant.id, nb.base_height, nb.variant.port_heights[OPPOSITE[dir]], their_port, dir
				])

	if mismatches.empty():
		print("[T1] PASS seed=%d" % seed_val)
		_passed += 1
	else:
		print("[T1] FAIL seed=%d — %d mismatch(es):" % [seed_val, mismatches.size()])
		for m in mismatches:
			print(m)
		_failed += 1

	gen.queue_free()
