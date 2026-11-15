extends GdUnitTestSuite

# Las 10 escenas horneadas de chunks de andamio coinciden con ScaffoldChunkRegistry: la
# colision y los sockets salen del registro, asi que una escena desfasada significa que
# falta rehornear (tools/scaffold_chunks/build.sh).

const Registry = preload("res://core_v2/systems/scaffold/ScaffoldChunkRegistry.gd")
const FlowMetricsScript = preload("res://core_v2/systems/flow/FlowMetrics.gd")
const DIR := "res://core_v2/props/scaffold/chunks/"
const TOL := 0.01


func _metrics() -> Dictionary:
	var fm = FlowMetricsScript.from_scene()
	return {"g": fm.gravity, "v_run": fm.run_speed(), "v_jump": fm.jump_force, "tick": 1.0 / 60.0}


func test_every_chunk_scene_matches_the_registry() -> void:
	var m := _metrics()
	for id in Registry.chunk_ids():
		var chunk: Dictionary = Registry.build_chunk(id, m)
		var packed: PackedScene = load(DIR + id + ".tscn")
		assert_object(packed).override_failure_message("falta la escena de %s" % id).is_not_null()
		if packed == null:
			continue
		var scene: Spatial = auto_free(packed.instance())
		assert_object(scene.get_node_or_null("Mesh")).is_not_null()
		assert_object((scene.get_node("Mesh") as MeshInstance).mesh).is_not_null()

		# Superficie caminable: la tapa de cada caja es la del nodo del registro.
		for n in chunk["nodes"]:
			var col: CollisionShape = scene.get_node_or_null("Collision/Col_" + str(n["id"]))
			assert_object(col).override_failure_message("%s: falta Col_%s" % [id, n["id"]]).is_not_null()
			if col == null:
				continue
			var box: BoxShape = col.shape
			var top: Vector3 = col.transform.origin + col.transform.basis.y * box.extents.y
			assert_float(top.distance_to(n["position"])) \
				.override_failure_message("%s/%s: tapa en %s, registro %s" % [id, n["id"], top, n["position"]]).is_less(TOL)
			assert_float(abs(box.extents.x * 2.0 - n["size"].x)).is_less(TOL)
			var rise: float = float(n.get("rise", 0.0))
			assert_float(abs(box.extents.z * 2.0 - Vector2(n["size"].z, rise).length())).is_less(TOL)
			# Una rampa sube exactamente `rise` de punta a punta.
			var run: Vector3 = col.transform.basis.z * box.extents.z * 2.0
			assert_float(abs(run.y - rise)).is_less(TOL)
		for b in chunk["blockers"]:
			assert_object(scene.get_node_or_null("Blocker_%s/Col" % b["id"])).is_not_null()

		# Sockets: marcador + metadata, con la salida principal desplazada (dy) a 12 m.
		var sockets: Dictionary = scene.get_meta("sockets")
		assert_bool(sockets.has("In_A")).is_true()
		var out_name := "Out_" + str(chunk["out_socket"])
		assert_bool(sockets.has(out_name)).override_failure_message("%s sin %s" % [id, out_name]).is_true()
		var out_marker: Position3D = scene.get_node_or_null("Socket_" + out_name)
		assert_object(out_marker).is_not_null()
		assert_float(out_marker.translation.distance_to(
			Vector3(0.0, float(chunk["dy"]), Registry.CHUNK_LENGTH))).is_less(TOL)
		for side_type in chunk["side_outs"]:
			assert_object(scene.get_node_or_null("Socket_Out_" + side_type)).is_not_null()
