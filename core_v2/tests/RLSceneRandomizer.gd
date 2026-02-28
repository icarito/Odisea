extends Reference

class_name RLSceneRandomizer

const FLOOR_SNAP_UP = 4.0
const FLOOR_SNAP_DOWN = 18.0
const FLOOR_CLEARANCE_UP = 0.32
const FLOOR_MIN_NORMAL_Y = 0.55
const HEADROOM_CHECK_HEIGHT = 1.8

var _scene: Spatial = null
var _pools := {}

func configure(scene: Spatial) -> void:
	_scene = scene
	_pools.clear()

func clear() -> void:
	_pools.clear()

func has_pool(name: String) -> bool:
	return _pools.has(name) and (_pools[name] is Array) and (_pools[name].size() > 0)

func get_pool(name: String) -> Array:
	if not _pools.has(name):
		return []
	var src = _pools[name]
	if src is Array:
		return src.duplicate()
	return []

func add_box_pool(name: String, min_v: Vector3, max_v: Vector3, sample_count := 180, floor_hint := 0.0, clearance := 0.45) -> int:
	var pool := []
	var min_x = min(min_v.x, max_v.x)
	var max_x = max(min_v.x, max_v.x)
	var min_y = min(min_v.y, max_v.y)
	var max_y = max(min_v.y, max_v.y)
	var min_z = min(min_v.z, max_v.z)
	var max_z = max(min_v.z, max_v.z)
	var target = max(6, int(sample_count))
	var max_tries = max(32, target * 10)
	for _i in range(max_tries):
		if pool.size() >= target:
			break
		var candidate = Vector3(
			rand_range(min_x, max_x),
			rand_range(min_y, max_y),
			rand_range(min_z, max_z)
		)
		var snapped = _snap_to_floor(candidate, floor_hint)
		if not bool(snapped.get("ok", false)):
			continue
		var p: Vector3 = snapped.get("pos", candidate)
		if not _has_headroom(p):
			continue
		if not _has_radial_clearance(p, float(clearance)):
			continue
		pool.append(p)
	if pool.empty():
		var fallback_target = max(8, int(sample_count / 3))
		for _i in range(fallback_target):
			var candidate = Vector3(
				rand_range(min_x, max_x),
				rand_range(min_y, max_y),
				rand_range(min_z, max_z)
			)
			var snapped = _snap_to_floor(candidate, floor_hint)
			var p = candidate
			if bool(snapped.get("ok", false)):
				p = snapped.get("pos", candidate)
			pool.append(p)
	if pool.empty():
		var center = Vector3(
			(min_x + max_x) * 0.5,
			(min_y + max_y) * 0.5,
			(min_z + max_z) * 0.5
		)
		var center_snap = _snap_to_floor(center, floor_hint)
		if bool(center_snap.get("ok", false)):
			center = center_snap.get("pos", center)
		pool.append(center)
	_pools[name] = pool
	return pool.size()

func add_points_pool(name: String, points: Array, jitter := 0.0, duplicates := 2, floor_hint := 0.0, clearance := 0.45) -> int:
	var pool := []
	var rep = max(1, int(duplicates))
	for raw_point in points:
		if not (raw_point is Vector3):
			continue
		for _i in range(rep):
			var p = raw_point
			if float(jitter) > 0.0:
				p.x += rand_range(-float(jitter), float(jitter))
				p.z += rand_range(-float(jitter), float(jitter))
			var snapped = _snap_to_floor(p, floor_hint)
			if not bool(snapped.get("ok", false)):
				continue
			var s: Vector3 = snapped.get("pos", p)
			if not _has_headroom(s):
				continue
			if not _has_radial_clearance(s, float(clearance)):
				continue
			pool.append(s)
	if pool.empty():
		for raw_point in points:
			if not (raw_point is Vector3):
				continue
			var p = raw_point
			if float(jitter) > 0.0:
				p.x += rand_range(-float(jitter), float(jitter))
				p.z += rand_range(-float(jitter), float(jitter))
			var snapped = _snap_to_floor(p, floor_hint)
			if bool(snapped.get("ok", false)):
				p = snapped.get("pos", p)
			pool.append(p)
	_pools[name] = pool
	return pool.size()

func choose_episode(spawn_pool_names: Array, target_pool_names: Array, min_dist := 4.0, max_dist := 9999.0, tries := 80) -> Dictionary:
	var spawn_pool = _collect_pool_points(spawn_pool_names)
	var target_pool = _collect_pool_points(target_pool_names)
	if spawn_pool.empty() or target_pool.empty():
		return {}

	var min_d = max(0.1, float(min_dist))
	var max_d = max(min_d, float(max_dist))
	for _i in range(max(8, int(tries))):
		var spawn = spawn_pool[randi() % spawn_pool.size()]
		var target = target_pool[randi() % target_pool.size()]
		var d = _horizontal_distance(spawn, target)
		if d < min_d or d > max_d:
			continue
		return {
			"spawn": spawn,
			"target": target
		}

	for spawn in spawn_pool:
		for target in target_pool:
			var d = _horizontal_distance(spawn, target)
			if d >= min_d and d <= max_d:
				return {
					"spawn": spawn,
					"target": target
				}
	return {
		"spawn": spawn_pool[0],
		"target": target_pool[0]
	}

func _collect_pool_points(names: Array) -> Array:
	var out := []
	for name in names:
		if not (name is String):
			continue
		if not _pools.has(name):
			continue
		var pool = _pools[name]
		if not (pool is Array):
			continue
		for p in pool:
			if p is Vector3:
				out.append(p)
	return out

func _get_space_state():
	if not is_instance_valid(_scene):
		return null
	var viewport = _scene.get_viewport()
	if viewport == null or viewport.world == null:
		return null
	return viewport.world.direct_space_state

func _snap_to_floor(point: Vector3, floor_hint := 0.0) -> Dictionary:
	var dss = _get_space_state()
	if dss == null:
		return {"ok": true, "pos": point}
	var from = Vector3(point.x, max(point.y, float(floor_hint)) + FLOOR_SNAP_UP, point.z)
	var to = Vector3(point.x, point.y - FLOOR_SNAP_DOWN, point.z)
	var hit = dss.intersect_ray(from, to, [], 0x7FFFFFFF, true, false)
	if typeof(hit) != TYPE_DICTIONARY:
		return {"ok": false}
	if not hit.has("position"):
		return {"ok": false}
	var normal = hit.get("normal", Vector3.UP)
	if normal is Vector3 and normal.y < FLOOR_MIN_NORMAL_Y:
		return {"ok": false}
	var pos: Vector3 = hit["position"]
	pos += Vector3.UP * FLOOR_CLEARANCE_UP
	return {"ok": true, "pos": pos}

func _has_headroom(point: Vector3) -> bool:
	var dss = _get_space_state()
	if dss == null:
		return true
	var from = point + Vector3.UP * 0.05
	var to = point + Vector3.UP * HEADROOM_CHECK_HEIGHT
	var hit = dss.intersect_ray(from, to, [], 0x7FFFFFFF, true, false)
	return typeof(hit) != TYPE_DICTIONARY

func _has_radial_clearance(point: Vector3, radius: float) -> bool:
	var dss = _get_space_state()
	if dss == null:
		return true
	var r = max(0.15, radius)
	var origin = point + Vector3.UP * 0.75
	var dirs = [
		Vector3(r, 0.0, 0.0),
		Vector3(-r, 0.0, 0.0),
		Vector3(0.0, 0.0, r),
		Vector3(0.0, 0.0, -r)
	]
	for d in dirs:
		var hit = dss.intersect_ray(origin, origin + d, [], 0x7FFFFFFF, true, false)
		if typeof(hit) == TYPE_DICTIONARY:
			return false
	return true

func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var d = a - b
	d.y = 0.0
	return d.length()
