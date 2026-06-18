extends SceneTree


func _init() -> void:
	var args: PoolStringArray = OS.get_cmdline_args()
	if args.size() < 5:
		printerr("Usage: <scene_path> <mesh_node_path> <output_shape_path>")
		quit(2)
		return

	var scene_path: String = args[2]
	var mesh_path: NodePath = NodePath(args[3])
	var output_path: String = args[4]
	var packed: PackedScene = load(scene_path)
	if not packed:
		printerr("Unable to load scene: " + scene_path)
		quit(3)
		return

	var root: Node = packed.instance()
	var mesh_instance: MeshInstance = root.get_node_or_null(mesh_path) as MeshInstance
	if not mesh_instance or not mesh_instance.mesh:
		printerr("Unable to find mesh: " + String(mesh_path))
		root.free()
		quit(4)
		return

	var shape: Shape = mesh_instance.mesh.create_trimesh_shape()
	var error: int = ResourceSaver.save(output_path, shape)
	root.free()
	if error != OK:
		printerr("Unable to save shape: %s (%d)" % [output_path, error])
		quit(error)
		return

	print("Saved static trimesh collision: " + output_path)
	quit(0)
