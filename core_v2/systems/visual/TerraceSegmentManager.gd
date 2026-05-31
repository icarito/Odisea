extends Spatial
class_name TerraceSegmentManager

# FD-041: segmenta las terrazas en arcos lógicos y decide qué plates deben
# mantenerse en full detail alrededor del jugador/streaming activo.

export(int, 1, 64) var segment_count := 12
export(int, 0, 16) var full_detail_plate_radius := 2
export(int, 0, 64) var full_detail_nearest_count := 9
export(bool) var html5_force_lod_only := true

var _rotator: Spatial = null
var _active_stream_plates := {}
var _last_stats := {}

func register_rotator(rotator: Spatial) -> void:
	_rotator = rotator


func set_active_stream_plates(plates: Array) -> void:
	_active_stream_plates.clear()
	for plate in plates:
		if typeof(plate) != TYPE_DICTIONARY:
			continue
		var spiral_idx := int(plate.get("spiral_index", plate.get("spiral_idx", -1)))
		var plate_idx := int(plate.get("plate_index", plate.get("plate_idx", -1)))
		if spiral_idx < 0 or plate_idx < 0:
			continue
		_active_stream_plates[_make_key(spiral_idx, plate_idx)] = true


func get_full_detail_plate_keys(selected_spiral: int, selected_plate: int, plate_count: int) -> Dictionary:
	var result := {}
	if selected_spiral < 0 or selected_plate < 0 or plate_count <= 0:
		return result
	for offset in range(-full_detail_plate_radius, full_detail_plate_radius + 1):
		var plate_idx := _wrap_index(selected_plate + offset, plate_count)
		result[_make_key(selected_spiral, plate_idx)] = true
	for key in _active_stream_plates.keys():
		result[key] = true
	if OS.has_feature("HTML5") and html5_force_lod_only:
		result.clear()
	return result


func get_nearest_full_detail_plate_keys(candidates: Array, center: Vector3, nearest_count: int = -1) -> Dictionary:
	var result := {}
	if OS.has_feature("HTML5") and html5_force_lod_only:
		return result
	var count := full_detail_nearest_count if nearest_count < 0 else nearest_count
	if count <= 0:
		return result
	var ranked := []
	for candidate in candidates:
		if typeof(candidate) != TYPE_DICTIONARY:
			continue
		var spiral_idx := int(candidate.get("spiral_index", candidate.get("spiral_idx", -1)))
		var plate_idx := int(candidate.get("plate_index", candidate.get("plate_idx", -1)))
		if spiral_idx < 0 or plate_idx < 0:
			continue
		var origin := Vector3.ZERO
		if candidate.has("origin") and candidate["origin"] is Vector3:
			origin = candidate["origin"]
		elif candidate.has("canonical_tx") and candidate["canonical_tx"] is Transform:
			origin = (candidate["canonical_tx"] as Transform).origin
		ranked.append({
			"key": _make_key(spiral_idx, plate_idx),
			"dist_sq": origin.distance_squared_to(center)
		})
	ranked.sort_custom(self, "_sort_ranked_candidate")
	for i in range(min(count, ranked.size())):
		result[String(ranked[i].get("key", ""))] = true
	for key in _active_stream_plates.keys():
		result[key] = true
	return result


func get_plate_segment(spiral: Spatial, plate_index: int) -> int:
	var count := _get_plate_count(spiral)
	if count <= 0:
		return 0
	var turns := 1.0
	if spiral != null and spiral.get("turns") != null:
		turns = float(spiral.get("turns"))
	var angle_per_plate := 360.0 * turns / float(count)
	var normalized_angle := fposmod(float(plate_index) * angle_per_plate, 360.0)
	var segment_size := 360.0 / float(max(1, segment_count))
	return int(clamp(floor(normalized_angle / segment_size), 0, segment_count - 1))


func classify_plate_lod(spiral_idx: int, plate_idx: int, selected_spiral: int, selected_plate: int, plate_count: int) -> int:
	if OS.has_feature("HTML5") and html5_force_lod_only:
		return 1
	var full_detail := get_full_detail_plate_keys(selected_spiral, selected_plate, plate_count)
	if full_detail.has(_make_key(spiral_idx, plate_idx)):
		return 2
	return 1


func build_stats(assignments: Array, full_detail_keys: Dictionary, overlay_part_count: int, shell_visible: bool) -> Dictionary:
	var total := assignments.size()
	var full_detail := 0
	for assignment in assignments:
		var spiral_idx := int(assignment.get("spiral_index", -1))
		var plate_idx := int(assignment.get("plate_index", -1))
		if full_detail_keys.has(_make_key(spiral_idx, plate_idx)):
			full_detail += 1
	var lod_instances := max(0, total - full_detail)
	var stats := {
		"segments": segment_count,
		"total_assignments": total,
		"lod0_shell_draw_calls": 1 if shell_visible else 0,
		"lod1_overlay_draw_calls": overlay_part_count,
		"lod1_instances": lod_instances,
		"lod2_full_detail_plates": full_detail,
		"estimated_full_detail_without_lod": total,
		"estimated_lod_draw_surfaces": overlay_part_count + (1 if shell_visible else 0)
	}
	_last_stats = stats
	return stats


func get_lod_stats() -> Dictionary:
	return _last_stats.duplicate(true)


func _get_plate_count(spiral: Spatial) -> int:
	if _rotator != null and is_instance_valid(_rotator) and _rotator.has_method("get_plate_count"):
		return int(_rotator.get_plate_count(spiral))
	if spiral != null and spiral.get("multimesh") != null and spiral.multimesh != null:
		return int(spiral.multimesh.instance_count)
	return 0


func _make_key(spiral_idx: int, plate_idx: int) -> String:
	return "%d:%d" % [spiral_idx, plate_idx]


func _sort_ranked_candidate(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("dist_sq", INF)) < float(b.get("dist_sq", INF))


func _wrap_index(value: int, size: int) -> int:
	if size <= 0:
		return 0
	var wrapped := value % size
	if wrapped < 0:
		wrapped += size
	return wrapped
