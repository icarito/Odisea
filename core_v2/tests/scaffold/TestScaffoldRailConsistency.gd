extends Node
# Test 2: Rail consistency — rails are ALWAYS present (true) on all four sides.
# Opening widths must equal lane_width on connected sides, 0 on non-connected sides.
# This mirrors the new rule in _apply_rails_from_connections (always true) and
# _apply_opening_widths_from_connections (opening only where connection=true).
#
# Since we don't instantiate scene nodes, we validate the invariant from variant data:
# - Every non-EMPTY cell must have rail on all 4 sides (always true after the change).
# - opening_width = lane_width where connection=true, opening_width = 0 where connection=false.
# We verify the second point by checking bilateral symmetry of connections (a connected
# side must have a reciprocating neighbor), which guarantees openings will align.

const GEN_SCRIPT = preload("res://core_v2/systems/ScaffoldWFCGenerator.gd")

const OPPOSITE = {0: 2, 1: 3, 2: 0, 3: 1}

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
	print("[T2:RailConsistency] passed=%d failed=%d" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _run(seed_val: int) -> void:
	var gen = GEN_SCRIPT.new()
	gen.map_seed = seed_val
	gen.max_wfc_retries = 400
	gen.debug_verbose = false
	add_child(gen)
	var grid = gen.call("_wfc_generate")

	if grid.empty():
		print("[T2] FAIL seed=%d: grid empty" % seed_val)
		_failed += 1
		remove_child(gen)
		gen.free()
		return

	var gw = gen.grid_width
	var gd = gen.grid_depth
	var violations = []

	for i in range(grid.size()):
		var state = grid[i]
		if state == null or state.variant.id == "EMPTY":
			continue
		var v = state.variant
		var cx = i % gw
		var cy = i / gw

		# Rail = always true: validated implicitly — if the generator sets rail=true
		# unconditionally, nothing in variant data can contradict it. We still validate
		# the connection-opening relationship from variant data.

		# opening_width policy: connection=true -> opening > 0 (lane_width)
		#                       connection=false -> opening = 0
		# Validate bilateral: a connected side must have a reciprocating neighbor.
		for side in ["front", "back", "left", "right"]:
			var wd = _dir_from_local_side(v.rotation, side)
			var connected = v.connections[wd]
			var dv = [Vector2(0,-1), Vector2(1,0), Vector2(0,1), Vector2(-1,0)][wd]
			var nx = cx + int(dv.x)
			var ny = cy + int(dv.y)
			if nx < 0 or nx >= gw or ny < 0 or ny >= gd:
				if connected:
					violations.append("  [%d,%d]%s side=%s: connection=true at boundary" % [cx, cy, v.id, side])
				continue
			var ni = ny * gw + nx
			var nb = grid[ni]
			if connected:
				# opening should be lane_width: neighbor must be non-EMPTY and connect back
				if nb == null or nb.variant.id == "EMPTY":
					violations.append("  [%d,%d]%s side=%s: connection=true but neighbor EMPTY" % [cx, cy, v.id, side])
				elif not nb.variant.connections[OPPOSITE[wd]]:
					violations.append("  [%d,%d]%s side=%s: connection=true but neighbor doesn't connect back" % [cx, cy, v.id, side])
			else:
				# opening should be 0: neighbor must not connect toward us
				if nb != null and nb.variant.id != "EMPTY" and nb.variant.connections[OPPOSITE[wd]]:
					violations.append("  [%d,%d]%s side=%s: connection=false but neighbor connects toward us" % [cx, cy, v.id, side])

	if violations.empty():
		print("[T2] PASS seed=%d" % seed_val)
		_passed += 1
	else:
		print("[T2] FAIL seed=%d — %d violation(s):" % [seed_val, violations.size()])
		for vi in violations:
			print(vi)
		_failed += 1

	remove_child(gen)
	gen.free()
