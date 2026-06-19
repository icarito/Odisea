extends SceneTree

# verify_domefacade_overrides.gd — Checks that the collision_layer=0/mask=0
# overrides on ChamberZone/AirlockSafetyFloor/CameraWalls in DomeFacade_01
# actually applied to the right nodes after the CSG→mesh bake. Godot 3
# resolves editable-children overrides by node path; this confirms the overrides
# landed on the intended CollisionObjects, not on the wrong node.
#
# Run: godot3-bin --no-window -s tools/verify_domefacade_overrides.gd

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load("res://core_v2/levels/facades/DomeFacade_01.tscn")
	if scene == null:
		push_error("Could not load DomeFacade_01")
		quit(1)
		return
	var root: Node = scene.instance()
	get_root().add_child(root)
	yield(self, "idle_frame")

	var ok := true
	var names := ["Airlock_North", "Airlock_South", "Airlock_East", "Airlock_West"]
	for airlock_name in names:
		var airlock: Node = root.get_node_or_null(airlock_name)
		if airlock == null:
			print("MISSING: %s" % airlock_name)
			ok = false
			continue
		# ChamberZone is an Area used by AirlockController for body_entered
		# detection — it must stay INTACT (layer=0, mask=all). Do NOT neutralize.
		var cz: Node = airlock.get_node_or_null("ChamberZone")
		if cz == null:
			print("MISSING: %s/ChamberZone" % airlock_name)
			ok = false
		else:
			var cz_layer: int = int(cz.get("collision_layer"))
			var cz_mask: int = int(cz.get("collision_mask"))
			var cz_ok: bool = cz_layer == 0 and cz_mask == 2147483647
			print("%s/ChamberZone: layer=%d mask=%d %s" % [
				airlock_name, cz_layer, cz_mask,
				"INTACT" if cz_ok else "WRONG (!)"])
			if not cz_ok:
				ok = false
		# AirlockSafetyFloor + CameraWalls are StaticBodies redundant with the
		# WorldRotator pool — they MUST be neutralized (layer=0, mask=0).
		for node_name in ["AirlockSafetyFloor", "CameraWalls"]:
			var node: Node = airlock.get_node_or_null(node_name)
			if node == null:
				print("MISSING: %s/%s" % [airlock_name, node_name])
				ok = false
				continue
			var layer: int = int(node.get("collision_layer"))
			var mask: int = int(node.get("collision_mask"))
			var neutralized: bool = layer == 0 and mask == 0
			print("%s/%s: layer=%d mask=%d %s" % [
				airlock_name, node_name, layer, mask,
				"NEUTRALIZED" if neutralized else "ACTIVE (!)"])
			if not neutralized:
				ok = false
		# Verify AirlockZoneV2 still has its target_scene (not neutralized)
		var zone: Node = airlock.get_node_or_null("AirlockZoneV2")
		if zone == null:
			print("MISSING: %s/AirlockZoneV2" % airlock_name)
			ok = false
		else:
			var ts: String = str(zone.get("target_scene"))
			print("%s/AirlockZoneV2: target=%s %s" % [
				airlock_name, ts.get_file(),
				"OK" if ts != "" and ts != "null" else "MISSING (!)"])
			if ts == "" or ts == "null":
				ok = false

	if ok:
		print("VERIFY_FACADE: PASS — all overrides applied correctly")
	else:
		print("VERIFY_FACADE: FAIL — some overrides missing/wrong")
	root.free()
	quit(0 if ok else 1)
