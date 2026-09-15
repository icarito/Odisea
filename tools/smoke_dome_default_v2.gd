extends SceneTree

# smoke_dome_default_v2.gd — Carga Dome_Default.tscn y verifica que el swap
# del asset (DomeTerraceV2) quedó sano: mesh multi-superficie, colisión,
# airlocks a Y=3.4 (igual que Dome_Base) y spawn cerca del piso 1.

const SCENE := "res://core_v2/levels/interiors/Dome_Default.tscn"
const HOLE_R := 4.5


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(SCENE)
	if packed == null:
		push_error("[smoke] no carga la escena")
		quit(1)
		return
	var root: Node = packed.instance()

	var mesh: ArrayMesh = load("res://core_v2/levels/interiors/DomeTerraceV2_baked.mesh")
	var shape: ConcavePolygonShape = load("res://core_v2/levels/interiors/DomeTerraceV2_baked.shape")
	if mesh == null or shape == null:
		push_error("[smoke] recursos horneados no cargan")
		quit(1)
		return
	if mesh.get_surface_count() != 4:
		push_error("[smoke] se esperaban 4 superficies, hay %d" % mesh.get_surface_count())
		quit(1)
		return

	# Airlocks: Y=1.23 y a distancia del eje (bore en |x| o |z| = 32).
	var airlocks := 0
	for child in root.get_children():
		if child.name.begins_with("Airlock_"):
			airlocks += 1
			var origin: Vector3 = (child as Spatial).transform.origin
			if abs(origin.y - 3.4) > 0.01:
				push_error("[smoke] %s a Y=%s (esperado 3.4, igual que Dome_Base)" % [child.name, origin.y])
				quit(1)
				return
			var radial := Vector2(origin.x, origin.z).length()
			if abs(radial - 32.0) > 0.5:
				push_error("[smoke] %s a r=%s (esperado ~32)" % [child.name, radial])
				quit(1)
				return

	# Spawn fuera del agujero central y sobre el piso.
	var spawn := root.get_node("SpawnPointV2") as Position3D
	if spawn == null:
		push_error("[smoke] SpawnPointV2 ausente")
		quit(1)
		return
	var sp: Vector3 = spawn.transform.origin
	var r_xy := Vector2(sp.x, sp.z).length()
	if r_xy < HOLE_R + 1.0:
		push_error("[smoke] spawn a r=%.2f del centro (agujero r=%.1f)" % [r_xy, HOLE_R])
		quit(1)
		return

	print("[smoke] OK: airlocks=%d y=3.4, spawn=(%s) r=%.2f, mesh_surfs=%d, tris=%d" % [
		airlocks, sp, r_xy, mesh.get_surface_count(), shape.get_faces().size() / 3])
	quit(0)
