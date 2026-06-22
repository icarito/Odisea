extends SceneTree

# bake_airlock_container_chamber.gd — Bakes the AirlockContainerChamber CSG nodes into static ArrayMeshes.

const SCENE_PATH := "res://core_v2/props/doors/AirlockContainerChamber.tscn"
const OUT_DIR := "res://core_v2/props/doors/airlock_container_baked/"

const NODES_TO_BAKE := [
	"ContainerShell",
	"FloorPad",
	"LightStrip"
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

	for _i in range(15):
		yield(self, "idle_frame")

	var baked := 0
	for node_name in NODES_TO_BAKE:
		var csg: Node = root.get_node_or_null(node_name)
		if csg == null or not (csg is CSGShape):
			continue
		
		var meshes: Array = csg.get_meshes()
		if meshes.size() < 2 or meshes[1] == null:
			continue

		var mesh: Mesh = meshes[1]
		var out_path: String = OUT_DIR + node_name + ".mesh"
		ResourceSaver.save(out_path, mesh)

		if node_name == "ContainerShell" or node_name == "FloorPad":
			var shape: Shape = mesh.create_trimesh_shape()
			ResourceSaver.save(OUT_DIR + node_name + ".shape", shape)

		print("[bake_airlock_container] BAKED %s" % node_name)
		baked += 1

	root.free()
	quit(0 if baked > 0 else 1)
