extends SceneTree

# shot_scaffold_rev.gd — Dibuja los andamios de Dome_Intro tal como quedaron en UN
# commit cualquiera, para poder recorrer el historial y ver en que revision el
# encastre spoke <-> rampa estaba bien.
#
# No abre la escena del commit (haria falta un worktree entero y reimportar todo).
# Toma solo las tres mallas horneadas, que es donde vive la geometria, y las monta
# con los mismos transforms de grupo que usa Dome_Intro (constantes en todo el
# historial, verificado commit por commit).
#
# El wrapper tools/scaffold_rev.sh extrae las mallas de un commit y llama a esto.
#
# Uso: ODISEA_REV_DIR=res://core_v2/levels/interiors/_rev ODISEA_REV_OUT=/tmp/x \
#        godot3-bin --no-window -s tools/shot_scaffold_rev.gd

# Transform del nodo SpiralStairs / SpiralWalkways en Dome_Intro (rotacion en Y).
# HubSpokes va en identidad.
const SPIRAL_BASIS := [-0.965926, 0.0, 0.258819, 0.0, 1.0, 0.0, -0.258819, 0.0, -0.965926]
const GROUPS := ["SpiralStairs", "HubSpokes", "SpiralWalkways"]
# Un color por grupo, para que se lea de un vistazo cual es cual en la planta.
const COLORS := {
	"SpiralStairs": Color(0.95, 0.55, 0.20),
	"HubSpokes": Color(0.30, 0.85, 0.95),
	"SpiralWalkways": Color(0.60, 0.65, 0.72),
}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var dir: String = OS.get_environment("ODISEA_REV_DIR")
	if dir.empty():
		dir = "res://core_v2/levels/interiors/_rev"
	var out_prefix: String = OS.get_environment("ODISEA_REV_OUT")
	if out_prefix.empty():
		out_prefix = "user://rev"
	var label: String = OS.get_environment("ODISEA_REV_LABEL")

	var root := Spatial.new()
	get_root().add_child(root)

	var spiral := Transform(
		Basis(Vector3(SPIRAL_BASIS[0], SPIRAL_BASIS[1], SPIRAL_BASIS[2]),
			Vector3(SPIRAL_BASIS[3], SPIRAL_BASIS[4], SPIRAL_BASIS[5]),
			Vector3(SPIRAL_BASIS[6], SPIRAL_BASIS[7], SPIRAL_BASIS[8])),
		Vector3.ZERO)

	var boxes := []
	for group_name in GROUPS:
		# Plano y sin textura: el damero de la reja y el grate del piso tapan
		# completamente el borde de cada cubierta en una planta.
		var mat := SpatialMaterial.new()
		mat.flags_unshaded = true
		mat.albedo_color = COLORS[group_name]
		mat.params_cull_mode = SpatialMaterial.CULL_DISABLED

		# Lo que la escena dibuja son los sectores, no la malla combinada: si un
		# horneado dejo las dos desincronizadas, mirar la combinada mentiria.
		var meshes := []
		var file := File.new()
		for sector in range(8):
			var sector_path: String = "%s/DomeIntro_%s_sector_%02d.mesh" % [dir, group_name, sector]
			if file.file_exists(sector_path):
				meshes.append(load(sector_path))
		if meshes.empty():
			var combined_path: String = "%s/DomeIntro_%s_baked.mesh" % [dir, group_name]
			if not file.file_exists(combined_path):
				printerr("REV: falta %s" % combined_path)
				continue
			meshes.append(load(combined_path))

		for i in range(meshes.size()):
			if meshes[i] == null:
				continue
			var mi := MeshInstance.new()
			mi.name = "%s_%d" % [group_name, i]
			mi.mesh = meshes[i]
			mi.transform = Transform.IDENTITY if group_name == "HubSpokes" else spiral
			mi.material_override = mat
			root.add_child(mi)
			boxes.append(mi.global_transform.xform(mi.get_aabb()))

	if boxes.empty():
		printerr("REV: no se cargo ninguna malla")
		quit(1)
		return
	var bounds: AABB = boxes[0]
	for i in range(1, boxes.size()):
		bounds = bounds.merge(boxes[i])

	var vp := Viewport.new()
	vp.size = Vector2(1280, 1280)
	vp.own_world = false
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var cam := Camera.new()
	vp.add_child(cam)
	cam.current = true
	cam.far = 500.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.14)
	cam.environment = env

	var center: Vector3 = bounds.position + bounds.size * 0.5
	cam.projection = Camera.PROJECTION_ORTHOGONAL
	cam.size = max(bounds.size.x, bounds.size.z) * 1.02
	cam.look_at_from_position(
		Vector3(center.x, bounds.position.y + bounds.size.y + 40.0, center.z + 0.01),
		Vector3(center.x, center.y, center.z), Vector3.UP)
	for _i in range(4):
		yield(self, "idle_frame")
	yield(VisualServer, "frame_post_draw")
	var img: Image = vp.get_texture().get_data()
	img.flip_y()
	var path: String = "%s.png" % out_prefix
	var err: int = img.save_png(path)
	print("REV:%s saved=%s path=%s" % [label, str(err == OK), path])
	quit(0)
