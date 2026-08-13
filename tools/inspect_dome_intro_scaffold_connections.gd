extends SceneTree

# Lista los bordes (front/back) de las fuentes de rampa y spokes. Sirve para
# autorizar strips sólo sobre la unión compartida, nunca por aproximación visual.
const SOURCE_PATH := "res://core_v2/levels/interiors/DomeIntro_ScaffoldSource.tscn"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(SOURCE_PATH) as PackedScene
	var root := packed.instance()
	var radial := root.get_node_or_null("SpiralWalkways")
	if radial != null:
		radial.rebuild_baked_items = false
	get_root().add_child(root)
	yield(self, "idle_frame")
	var entries := []
	for group_name in ["SpiralStairs", "SpiralWalkways", "HubSpokes"]:
		var group := root.get_node_or_null(group_name)
		for child in group.get_children():
			if not child.has_method("_deck_point"):
				continue
			var platform := child as Spatial
			entries.append({
				"name": "%s/%s" % [group_name, child.name],
				"front": _edge_center(platform, -1.0), "back": _edge_center(platform, 1.0),
				"left": _side_center(platform, -1.0), "right": _side_center(platform, 1.0)
			})
	for entry in entries:
		var nearest := _nearest_edge(entry, entries)
		print("[scaffold_connection] %s -> %s %.3fm" % [entry["name"], nearest["label"], nearest["distance"]])
	quit(0)

func _edge_center(platform: Spatial, edge_sign: float) -> Vector3:
	var half_width: float = float(platform.get("platform_width")) * 0.5
	var left: Vector3 = platform.call("_deck_point", -half_width, edge_sign)
	var right: Vector3 = platform.call("_deck_point", half_width, edge_sign)
	return platform.global_transform.xform((left + right) * 0.5)

func _side_center(platform: Spatial, side_sign: float) -> Vector3:
	var half_width: float = float(platform.get("platform_width")) * 0.5
	var front: Vector3 = platform.call("_deck_point", half_width * side_sign, -1.0)
	var back: Vector3 = platform.call("_deck_point", half_width * side_sign, 1.0)
	return platform.global_transform.xform((front + back) * 0.5)

func _nearest_edge(entry: Dictionary, all_entries: Array) -> Dictionary:
	var best := {"label": "none", "distance": INF}
	for edge_name in ["front", "back", "left", "right"]:
		for other in all_entries:
			if other["name"] == entry["name"]:
				continue
			for other_edge in ["front", "back", "left", "right"]:
				var distance: float = (entry[edge_name] as Vector3).distance_to(other[other_edge] as Vector3)
				if distance < best["distance"]:
					best = {"label": "%s.%s <- %s" % [edge_name, other["name"], other_edge], "distance": distance}
	return best
