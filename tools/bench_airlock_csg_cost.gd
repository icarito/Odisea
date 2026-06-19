extends SceneTree

# bench_airlock_csg_cost.gd — Microbenchmark of AirlockChamber CSG build cost.
#
# Measures the runtime cost the baked-mesh fix eliminates: the time to build the
# CSG geometry (the CSGCombiner boolean + leaf CSG shapes). The baked version
# replaces these with pre-built ArrayMesh resources, so this cost becomes zero.
#
# We instantiate the chamber, force the CSG build via get_meshes(), and time it.
# Run twice: once with the CSG .tscn, once with the baked .tscn (swap the file).
#
# Run: godot3-bin --no-window -s tools/bench_airlock_csg_cost.gd

const SCENE_PATH := "res://core_v2/props/doors/AirlockChamber.tscn"
const CSG_NODE_NAMES := ["CylindricalShell", "Rib_Front", "Rib_Center", "Rib_Back",
	"Floor", "LightStripLeft", "LightStripRight", "LightStripTop",
	"ConduitLeft", "ConduitRight"]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load(SCENE_PATH)
	if scene == null:
		push_error("Could not load %s" % SCENE_PATH)
		quit(1)
		return

	var root: Node = scene.instance()
	get_root().add_child(root)
	# Let the tree settle one frame so nodes are ready.
	yield(self, "idle_frame")

	# Force CSG build on every CSG node and time the total. For the baked version
	# there are no CSGShape nodes, so this loop is a no-op (cost ~0) — that IS the
	# win we are measuring.
	var total_usec: int = 0
	var csg_count: int = 0
	for name in CSG_NODE_NAMES:
		var n: Node = root.get_node_or_null(name)
		if n == null:
			continue
		if not (n is CSGShape):
			# Baked version: node is a MeshInstance, not a CSGShape — skip.
			continue
		csg_count += 1
		var t0: int = OS.get_ticks_usec()
		var csg: CSGShape = n
		var _meshes: Array = csg.get_meshes()  # forces the CSG boolean rebuild
		var t1: int = OS.get_ticks_usec()
		total_usec += (t1 - t0)

	# Also measure full-scene instantiation cost (includes CSG subtree build).
	var inst_t0: int = OS.get_ticks_usec()
	var _inst2: Node = scene.instance()
	var inst_t1: int = OS.get_ticks_usec()
	_inst2.free()

	var result := {
		"scene": "AirlockChamber",
		"csg_nodes_built": csg_count,
		"csg_build_total_usec": total_usec,
		"csg_build_total_ms": stepify(total_usec / 1000.0, 0.001),
		"instantiate_usec": inst_t1 - inst_t0,
		"instantiate_ms": stepify((inst_t1 - inst_t0) / 1000.0, 0.001),
	}
	print("BENCH:" + to_json(result))
	root.free()
	quit(0)
