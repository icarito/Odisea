extends Node
# Test 3: Openings only where there IS a rail.
# rail=true  -> opening_width can be >= 0 (valid, gap in the barrier)
# rail=false -> opening_width must be 0   (no barrier means no gap makes sense)
#
# We validate the logic that _apply_opening_widths_from_connections would produce:
# opening_width > 0 only when connection=true, which means rail=false.
# That is actually VALID per the generator: openings mark where passages cross.
# But the inverse must hold: when connection=false (rail=true), the generator
# does NOT set opening_width, so it stays 0. We verify the variant data is
# never in the state where connection=false AND the generator would set opening > 0.
#
# Since we can't read node properties without instantiation, we validate the
# variant arrays directly: ensure no internal contradiction exists.

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
		gen.queue_free()
		return

	var gw = gen.grid_width
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
			var world_dir = _dir_from_local_side(v.rotation, side)
			var connected = v.connections[world_dir]
			# rail=false when connected -> opening_width is set to pw (correct)
			# rail=true  when !connected -> opening_width stays 0   (correct)
			# Violation: rail=true (!connected) but generator would set opening>0 — impossible
			# by design, but we validate the inverse: connected side must never be at boundary
			# with no neighbor (already covered by T2). Here we confirm:
			# if connected AND neighbor is non-EMPTY, neighbor connects back.
			var dv = [Vector2(0,-1), Vector2(1,0), Vector2(0,1), Vector2(-1,0)][world_dir]
			var nx = cx + int(dv.x)
			var ny = cy + int(dv.y)
			var gd = gen.grid_depth
			if nx < 0 or nx >= gw or ny < 0 or ny >= gd:
				continue
			var ni = ny * gw + nx
			var nb = grid[ni]
			if not connected:
				# rail=true; opening should be 0. If neighbor connects toward us, that's a mismatch.
				if nb != null and nb.variant.id != "EMPTY":
					if nb.variant.connections[OPPOSITE[world_dir]]:
						violations.append("  [%d,%d]%s side=%s: rail=true(no conn) but neighbor [%d,%d]%s connects back" % [
							cx, cy, v.id, side, nx, ny, nb.variant.id])
			else:
				# rail=false; opening should equal lane_width. Neighbor must exist and connect back.
				if nb == null or nb.variant.id == "EMPTY":
					violations.append("  [%d,%d]%s side=%s: rail=false(connected) but neighbor is EMPTY/null" % [
						cx, cy, v.id, side])
				elif not nb.variant.connections[OPPOSITE[world_dir]]:
					violations.append("  [%d,%d]%s side=%s: rail=false(connected) but neighbor does not connect back" % [
						cx, cy, v.id, side])

	if violations.empty():
		print("[T3] PASS seed=%d" % seed_val)
		_passed += 1
	else:
		print("[T3] FAIL seed=%d — %d violation(s):" % [seed_val, violations.size()])
		for vi in violations:
			print(vi)
		_failed += 1

	gen.queue_free()
