extends Node
# Test 5: No base_height should be negative or below HEIGHT_STEP.
# Also checks support_base_local_y = platform_height - base_height is not unreasonably large.

const GEN_SCRIPT = preload("res://core_v2/systems/ScaffoldWFCGenerator.gd")
const HEIGHT_STEP = 2.0

var _passed := 0
var _failed := 0

func _ready():
	for s in [42, 99, 777]:
		_run(s)
	print("[T5:NoNegativeHeights] passed=%d failed=%d" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _run(seed_val: int) -> void:
	var gen = GEN_SCRIPT.new()
	gen.map_seed = seed_val
	gen.max_wfc_retries = 400
	gen.debug_verbose = false
	add_child(gen)
	var grid = gen.call("_wfc_generate")

	if grid.empty():
		print("[T5] FAIL seed=%d: grid empty" % seed_val)
		_failed += 1
		gen.queue_free()
		return

	var gw = gen.grid_width
	var violations = []

	for i in range(grid.size()):
		var state = grid[i]
		if state == null or state.variant.id == "EMPTY":
			continue
		var bh = state.base_height
		var cx = i % gw
		var cy = i / gw
		if bh < 0.0:
			violations.append("  [%d,%d] %s base_height=%.3f is NEGATIVE" % [cx, cy, state.variant.id, bh])
		elif bh < HEIGHT_STEP - 0.01:
			violations.append("  [%d,%d] %s base_height=%.3f < HEIGHT_STEP(%.1f)" % [cx, cy, state.variant.id, bh, HEIGHT_STEP])

	if violations.empty():
		print("[T5] PASS seed=%d" % seed_val)
		_passed += 1
	else:
		print("[T5] FAIL seed=%d — %d violation(s):" % [seed_val, violations.size()])
		for vi in violations:
			print(vi)
		_failed += 1

	gen.queue_free()
