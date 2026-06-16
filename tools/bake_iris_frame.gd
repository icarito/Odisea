extends SceneTree

# bake_iris_frame.gd — Bakes the IrisDoorV2 CSG "Frame" into a static ArrayMesh.
#
# The Frame is a CSGCombiner (OuterShell 24-sided cylinder MINUS InnerHole 32-sided
# cylinder) with use_collision=true. On GLES2 the boolean rebuild + trimesh collider
# generation cause a frame hitch when the door comes into view / the player approaches.
# Since the frame never deforms, we bake it once to a MeshInstance + saved mesh resource.
#
# Run: godot3-bin --no-window -s tools/bake_iris_frame.gd
# Output: core_v2/props/doors/IrisFrameBaked.mesh

const OUT_MESH := "res://core_v2/props/doors/IrisFrameBaked.mesh"
const OUT_SHAPE := "res://core_v2/props/doors/IrisFrameBaked.shape"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load("res://core_v2/props/doors/IrisDoorV2.tscn")
	if scene == null:
		push_error("Could not load IrisDoorV2.tscn")
		quit(1)
		return

	var root: Node = scene.instance()
	get_root().add_child(root)

	# CSG only builds its mesh once inside the tree and processed for a few frames.
	for _i in range(10):
		yield(self, "idle_frame")

	var frame := root.get_node_or_null("Frame")
	if frame == null or not (frame is CSGShape):
		push_error("Frame CSGShape not found")
		quit(1)
		return

	# get_meshes() returns [Transform, Mesh, Transform, Mesh, ...] in Godot 3.x.
	var meshes: Array = frame.get_meshes()
	if meshes.size() < 2 or meshes[1] == null:
		push_error("CSG produced no mesh — meshes=%s" % [meshes])
		quit(1)
		return

	var mesh: Mesh = meshes[1]
	var err := ResourceSaver.save(OUT_MESH, mesh)
	if err != OK:
		push_error("Failed saving baked mesh: %d" % err)
		quit(1)
		return

	# Bake the same boolean geometry into a static trimesh collision shape. Once
	# saved, loading it costs nothing — the expensive part was the CSG rebuild.
	var shape: Shape = mesh.create_trimesh_shape()
	if shape != null:
		var serr := ResourceSaver.save(OUT_SHAPE, shape)
		if serr != OK:
			push_error("Failed saving baked shape: %d" % serr)
			quit(1)
			return
		print("[bake_iris_frame] Saved baked collision shape to %s" % OUT_SHAPE)

	print("[bake_iris_frame] Saved baked frame mesh to %s (surfaces=%d, aabb=%s)" % [OUT_MESH, mesh.get_surface_count(), mesh.get_aabb()])
	root.free()
	quit(0)
