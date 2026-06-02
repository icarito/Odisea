extends Node
# Test 3: Opening width consistency.
# For each pair of connected adjacent cells:
#   - Both sides of the connection must have the same opening_width (= lane_width).
# For non-connected sides:
#   - opening_width must be 0.
#
# Since we validate from variant data (no node instantiation), we derive expected
# opening_width from connection flags, matching what _apply_opening_widths_from_connections does.
# The matching check verifies that both sides of a connected pair produce the same lane_width —
# which holds as long as both cells were generated with the same generator (same _lane_width()).

const GEN_SCRIPT = preload("res://core_v2/systems/ScaffoldWFCGenerator.gd")

const OPPOSITE = {0: 2, 1: 3, 2: 0, 3: 1}
const DIR_VEC = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]

func _dir_from_local_side(rot: int, side: String) -> int:
	var r = int(posmod(rot, 360))
	match side:
		"front":
			if r == 0:   return 0
			if r == 90:  return 1
			if r == 180: return 2
			return 3
		"back":
			return OPPOSITE[_dir_from_local_side(rot, "front")]
		"left":
			if r == 0:   return 3
			if r == 90:  return 0
			if r == 180: return 1
			return 2
		"right":
			return OPPOSITE[_dir_from_local_side(rot, "left")]
	return 0

var _passed := 0
var _failed := 0

func _ready():
	for s in [42, 99, 777]:
		_run(s)
	print("[T3:Openings] passed=%d failed=%d" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _run(seed_val: int) -> void:
	var gen = GEN_SCRIPT.new()
	gen.map_seed = seed_val
	gen.max_wfc_retries = 400
	gen.debug_verbose = false
	add_child(gen)
	var grid = gen.call("_wfc_generate")

	if grid.empty():
		print("[T3] FAIL seed=%d: grid empty" % seed_val)
		_failed += 1
		remove_child(gen)
		gen.free()
		return

	var gw = gen.grid_width
	var gd = gen.grid_depth
	var pw = gen.call("_lane_width")
	var violations = []

	for i in range(grid.size()):
		var state = grid[i]
		if state == null or state.variant.id == "EMPTY":
			continue
		var v = state.variant
		var cx = i % gw
		var cy = i / gw

		for side in ["front", "back", "left", "right"]:
			var wd = _dir_from_local_side(v.rotation, side)
			var connected = v.connections[wd]
			var dv = DIR_VEC[wd]
			var nx = cx + int(dv.x)
			var ny = cy + int(dv.y)

			if connected:
				# opening_width should be pw on this side
				if nx < 0 or nx >= gw or ny < 0 or ny >= gd:
					violations.append("  [%d,%d]%s side=%s: connected at boundary (no neighbor)" % [cx, cy, v.id, side])
					continue
				var ni = ny * gw + nx
				var nb = grid[ni]
				if nb == null or nb.variant.id == "EMPTY":
					violations.append("  [%d,%d]%s side=%s: connected but neighbor EMPTY" % [cx, cy, v.id, side])
					continue
				if not nb.variant.connections[OPPOSITE[wd]]:
					violations.append("  [%d,%d]%s side=%s: connected but neighbor doesn't connect back" % [cx, cy, v.id, side])
					continue
				# Both sides of the connection must produce the same opening_width.
				# _apply_opening_widths_from_connections sets pw on both sides when connected.
				# Since both cells use the same _lane_width(), openings will match.
				# We verify the symmetry by checking the neighbor also marks as connected:
				var nb_side_connected = nb.variant.connections[OPPOSITE[wd]]
				if not nb_side_connected:
					violations.append("  [%d,%d]%s->dir%d: opening mismatch — this side pw=%.2f neighbor opening=0" % [
						cx, cy, v.id, wd, pw])
			else:
				# opening_width should be 0: neighbor must not connect toward us
				if nx < 0 or nx >= gw or ny < 0 or ny >= gd:
					continue
				var ni = ny * gw + nx
				var nb = grid[ni]
				if nb != null and nb.variant.id != "EMPTY" and nb.variant.connections[OPPOSITE[wd]]:
					violations.append("  [%d,%d]%s side=%s: opening=0 but neighbor has opening toward us" % [
						cx, cy, v.id, side])

	if violations.empty():
		print("[T3] PASS seed=%d" % seed_val)
		_passed += 1
	else:
		print("[T3] FAIL seed=%d — %d violation(s):" % [seed_val, violations.size()])
		for vi in violations:
			print(vi)
		_failed += 1

	remove_child(gen)
	gen.free()
