extends SceneTree

# inspect_dome_v2.gd — imprime AABB, superficies y materiales del mesh horneado.
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var mesh: ArrayMesh = load("res://core_v2/levels/interiors/DomeTerraceV2_baked.mesh")
	if mesh == null:
		print("[inspect] mesh NULO")
		quit(1)
		return
	print("[inspect] aabb=", mesh.get_aabb())
	print("[inspect] surfaces=", mesh.get_surface_count())
	for s in range(mesh.get_surface_count()):
		var mat: Material = mesh.surface_get_material(s)
		print("[inspect] surf %d material=%s arrays_v=%s" % [s, mat.resource_name if mat != null else "NULL", mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()])
	var shape: ConcavePolygonShape = load("res://core_v2/levels/interiors/DomeTerraceV2_baked.shape")
	print("[inspect] shape_faces=", shape.get_faces().size() / 3 if shape != null else -1)
	quit(0)
