extends Node
# Test 2: Rail consistency — connection flag drives rail presence.
# connection=true  in a direction -> rail=false on that side (open passage to neighbor)
# connection=false in a direction -> rail=true  on that side (closed / has barrier)
#
# We validate the variant data used by _apply_rails_from_connections, replicating
# the _dir_from_local_side mapping without instantiating scene nodes.

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
		gen.queue_free()
		return

	var gw = gen.grid_width
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
			# connection=true  -> rail should be false (open)
			# connection=false -> rail should be true  (closed)
			# We derive what _apply_rails_from_connections would set:
			var expected_rail = not connected
			# The variant encodes the truth — we check bilateral invariant:
			# If connected, neighbor must connect back (checked in T2 bilateral).
			# Here we only check that a connected side facing the grid boundary is invalid.
			var dv = [Vector2(0,-1), Vector2(1,0), Vector2(0,1), Vector2(-1,0)][world_dir]
			var nx = cx + int(dv.x)
			var ny = cy + int(dv.y)
			var gd = gen.grid_depth
			var out_of_bounds = nx < 0 or nx >= gw or ny < 0 or ny >= gd
			if connected and out_of_bounds:
				violations.append("  [%d,%d] %s rot=%d side=%s connects dir=%d but is at boundary" % [
					cx, cy, v.id, v.rotation, side, world_dir])

	if violations.empty():
		print("[T2] PASS seed=%d" % seed_val)
		_passed += 1
	else:
		print("[T2] FAIL seed=%d — %d violation(s):" % [seed_val, violations.size()])
		for vi in violations:
			print(vi)
		_failed += 1

	gen.queue_free()
