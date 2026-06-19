extends SceneTree

# bake_airlock_chamber.gd — Bakes the AirlockChamber CSG nodes into static ArrayMeshes.
#
# AirlockChamber.tscn builds its hull, ribs, floor, light strips and conduits from
# 9 runtime CSG nodes (a CSGCombiner boolean + CSGTorus/CSGBox/CSGCylinder). On
# GLES2 the CSG boolean rebuild fires every frame the chamber is in view and is
# the leading suspect for the Dome_Crio hotzone cell (0,24) @ 16 fps / 72 % low
# (see docs/performance/project_airlock_exterior_hotzone.md). None of these
# meshes deform, so we bake each once to a saved ArrayMesh and keep its
# ShaderMaterial/SpatialMaterial — the shaders still run per-pixel, but the
# geometry rebuild cost is paid once at bake time, not every frame.
#
# Run: godot3-bin --no-window -s tools/bake_airlock_chamber.gd
# Output: core_v2/props/doors/airlock_baked/<NodeName>.mesh

const SCENE_PATH := "res://core_v2/props/doors/AirlockChamber.tscn"
const OUT_DIR := "res://core_v2/props/doors/airlock_baked/"

# CSG nodes to bake. CylindricalShell is a CSGCombiner (boolean); the rest are
# leaf CSG shapes. Each is baked individually so the static scene can keep the
# per-node materials and transforms without re-running CSG.
const NODES_TO_BAKE := [
	"CylindricalShell",
	"Rib_Front",
	"Rib_Center",
	"Rib_Back",
	"Floor",
	"LightStripLeft",
	"LightStripRight",
	"LightStripTop",
	"ConduitLeft",
	"ConduitRight",
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var dir := Directory.new()
	if dir.make_dir_recursive(OUT_DIR) != OK:
		push_error("Could not create output dir: %s" % OUT_DIR)
		quit(1)
		return

	var scene: PackedScene = load(SCENE_PATH)
	if scene == null:
		push_error("Could not load %s" % SCENE_PATH)
		quit(1)
		return

	var root: Node = scene.instance()
	get_root().add_child(root)

	# CSG only builds its mesh once inside the tree and processed for a few frames.
	# The CSGCombiner boolean (OuterTube minus InnerVoid) needs a couple extra
	# frames to settle its subtraction before get_meshes() returns a valid mesh.
	for _i in range(12):
		yield(self, "idle_frame")

	var baked := 0
	var skipped := 0
	for node_name in NODES_TO_BAKE:
		var csg: Node = root.get_node_or_null(node_name)
		if csg == null:
			print("[bake_airlock_chamber] SKIP %s (not found)" % node_name)
			skipped += 1
			continue
		if not (csg is CSGShape):
			print("[bake_airlock_chamber] SKIP %s (not a CSGShape: %s)" % [node_name, csg.get_class()])
			skipped += 1
			continue
		var csg_shape: CSGShape = csg

		var meshes: Array = csg_shape.get_meshes()
		if meshes.size() < 2 or meshes[1] == null:
			print("[bake_airlock_chamber] SKIP %s (CSG produced no mesh: %s)" % [node_name, meshes])
			skipped += 1
			continue

		var mesh: Mesh = meshes[1]
		var out_path: String = OUT_DIR + node_name + ".mesh"
		var err: int = ResourceSaver.save(out_path, mesh)
		if err != OK:
			push_error("Failed saving %s: %d" % [out_path, err])
			quit(1)
			return

		# Bake a trimesh collision shape for the shell (the only one with
		# use_collision semantics that matter for blocking the player). The
		# ribs/strips are decorative; skip shape gen for them to keep bake fast.
		if node_name == "CylindricalShell":
			var shape: Shape = mesh.create_trimesh_shape() as Shape
			if shape != null:
				var serr: int = ResourceSaver.save(OUT_DIR + node_name + ".shape", shape)
				if serr != OK:
					push_error("Failed saving shape %s: %d" % [node_name, serr])
					quit(1)
					return

		print("[bake_airlock_chamber] BAKED %s -> %s (surfaces=%d, aabb=%s)" % [
			node_name, out_path, mesh.get_surface_count(), mesh.get_aabb()])
		baked += 1

	print("[bake_airlock_chamber] Done. Baked=%d Skipped=%d" % [baked, skipped])
	root.free()
	quit(0 if baked > 0 else 1)
