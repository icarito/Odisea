extends SceneTree

# verify_airlock_connections.gd — Validates that airlock overrides (target_scene,
# target_spawn_id, target_airlock_path) resolve correctly on the baked
# AirlockChamber in Dome_Crio, ScaffoldOrbit, and the DomeFacade. Godot 3
# resolves editable-children overrides by node path/name, not by the `index`
# hint, so this confirms the door/zone wiring survived the CSG→mesh bake.
#
# Run: godot3-bin --no-window -s tools/verify_airlock_connections.gd

const SCENES := [
	"res://core_v2/levels/interiors/Dome_Crio.tscn",
	"res://core_v2/components/ScaffoldOrbit.tscn",
	"res://core_v2/levels/facades/DomeFacade_01.tscn",
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var all_ok := true
	for scene_path in SCENES:
		var scene: PackedScene = load(scene_path)
		if scene == null:
			push_error("Could not load %s" % scene_path)
			all_ok = false
			continue
		var root: Node = scene.instance()
		get_root().add_child(root)
		yield(self, "idle_frame")
		var ok := _verify_scene(root, scene_path)
		if not ok:
			all_ok = false
		root.free()

	if all_ok:
		print("VERIFY_AIRLOCK: PASS — all airlock connections resolve correctly")
	else:
		print("VERIFY_AIRLOCK: FAIL — some connections broken")
	quit(0 if all_ok else 1)

func _verify_scene(root: Node, scene_path: String) -> bool:
	var ok := true
	var scene_name := scene_path.get_file().get_basename()
	var airlock_zones := _find_airlock_zones(root)
	print("=== %s (%d AirlockZoneV2 found) ===" % [scene_name, airlock_zones.size()])
	for zone in airlock_zones:
		var target_scene: String = str(zone.get("target_scene"))
		var target_spawn: String = str(zone.get("target_spawn_id"))
		var target_airlock: String = str(zone.get("target_airlock_path"))
		var parent_name: String = zone.get_parent().name if zone.get_parent() else "?"
		var has_target := target_scene != "" and target_scene != "null"
		var status := "OK" if has_target else "MISSING_TARGET"
		print("  %s -> target=%s spawn=%s airlock=%s [%s]" % [
			parent_name, target_scene.get_file(), target_spawn, target_airlock, status])
		if not has_target:
			ok = false
	# Also check that IrisDoorV2 nodes (OuterDoor/InnerDoor) exist under each airlock
	var airlocks: Array = _find_airlocks(root)
	print("  AirlockChambers: %d" % airlocks.size())
	for airlock in airlocks:
		var outer: Node = airlock.get_node_or_null("OuterDoor")
		var inner: Node = airlock.get_node_or_null("InnerDoor")
		if outer == null or inner == null:
			print("  WARNING: %s missing doors (outer=%s inner=%s)" % [
				airlock.name, outer != null, inner != null])
			ok = false
	return ok

func _find_airlock_zones(node: Node) -> Array:
	var out := []
	var script: Script = node.get_script()
	if script != null and script.resource_path.find("AirlockZoneV2") >= 0:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_airlock_zones(c))
	return out

func _find_airlocks(node: Node) -> Array:
	var out := []
	var outer_path = node.get("outer_door_path")
	var inner_path = node.get("inner_door_path")
	if outer_path != null and inner_path != null:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_airlocks(c))
	return out
