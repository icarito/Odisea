extends SceneTree

# bench_dome_collision_load.gd — Measures how many PlateContentStream slots have
# physics active and how often the "normal path" (_refresh_active_slots) runs vs
# the direct path in OdiseaExterior. Headless, no GPU.
#
# This tells us whether the +X hotzone is driven by dome collision broadphase
# (many slots with trimesh StaticBodies) or by something else.
#
# Run: godot3-bin --no-window -s tools/bench_dome_collision_load.gd

const SCENE_PATH := "res://core_v2/levels/OdiseaExterior.tscn"

var _stream: Node = null
var _samples := []
var _frames := 0
var _warmup := 60  # 1s at 60fps to let the scene settle + cache build
var _capture := 180  # 3s of capture

func _init() -> void:
	print("BENCH:loading")
	var err = change_scene(SCENE_PATH)
	if err != OK:
		print("BENCH:load_failed:%d" % err)
		quit(1)

func _idle(_delta: float) -> bool:
	var cs = get_current_scene()
	if cs == null or cs.filename != SCENE_PATH:
		return false
	if _stream == null:
		_stream = _find_stream(cs)
		if _stream == null:
			return false
	_frames += 1
	if _frames < _warmup:
		return false
	if _frames > _warmup + _capture:
		_finish()
		return false
	_sample()
	return false

func _sample() -> void:
	var slots_active := 0
	var slots_with_physics := 0
	var slots_with_collision := 0
	var direct := bool(_stream.get("_direct_active_assignments"))
	var slots: Array = _stream.get("_slots")
	var phys_enabled: Array = _stream.get("_slot_physics_enabled")
	for i in range(slots.size()):
		var slot: Spatial = slots[i]
		if not is_instance_valid(slot):
			continue
		var assignment: Dictionary = _stream.get("_slot_assignments")[i]
		if assignment.empty():
			continue
		slots_active += 1
		var pe: bool = bool(phys_enabled[i]) if i < phys_enabled.size() else true
		if pe:
			slots_with_physics += 1
		# Count CollisionObjects under the slot (the dome trimesh)
		var n_col := _count_collision_objects(slot)
		slots_with_collision += n_col
	_samples.append({
		"frame": _frames,
		"direct": direct,
		"slots_active": slots_active,
		"slots_with_physics": slots_with_physics,
		"collision_objects_in_slots": slots_with_collision,
	})

func _count_collision_objects(node: Node) -> int:
	var n := 0
	for c in node.get_children():
		if c is CollisionObject:
			n += 1
		n += _count_collision_objects(c)
	return n

func _find_stream(root: Node) -> Node:
	for c in root.get_children():
		if c.name == "PlateContentRoot":
			return c
		var sub := _find_stream(c)
		if sub != null:
			return sub
	return null

func _finish() -> void:
	# Aggregate: how often was direct mode on, avg active slots, avg physics slots
	var direct_frames := 0
	var total_active := 0
	var total_phys := 0
	var total_col := 0
	for s in _samples:
		if bool(s["direct"]):
			direct_frames += 1
		total_active += int(s["slots_active"])
		total_phys += int(s["slots_with_physics"])
		total_col += int(s["collision_objects_in_slots"])
	var n := _samples.size()
	var result := {
		"scene": "OdiseaExterior",
		"samples": n,
		"direct_mode_frames": direct_frames,
		"direct_mode_pct": stepify(100.0 * direct_frames / max(1, n), 0.1),
		"avg_slots_active": stepify(float(total_active) / max(1, n), 0.1),
		"avg_slots_with_physics": stepify(float(total_phys) / max(1, n), 0.1),
		"avg_collision_objects_in_slots": stepify(float(total_col) / max(1, n), 0.1),
	}
	print("BENCH:" + to_json(result))
	quit(0)
