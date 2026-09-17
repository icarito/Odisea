extends SceneTree

# Screenshot de la sombra del piloto: corre el mismo frame en modo blob (fork)
# y legacy (ODISEA_DISABLE_BLOB_SHADOW=1), para comparar a ojo.
#   godot --path src -s scripts/_blob_shot.gd

var _frames := 0
var _mode := "blob"
var _out_dir := "res://test_output/blob_shadow"

func _init():
	_mode = "legacy" if OS.get_environment("ODISEA_DISABLE_BLOB_SHADOW").to_lower() in ["1", "true", "yes", "on"] else "blob"

	var root3d := Spatial.new()
	root3d.name = "BlobShotRoot"
	root.add_child(root3d)
	current_scene = root3d

	var floor_mi := MeshInstance.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mi.mesh = pm
	var mat := SpatialMaterial.new()
	mat.albedo_color = Color(0.55, 0.55, 0.55)
	mat.roughness = 0.95
	floor_mi.material_override = mat
	root3d.add_child(floor_mi)

	var floor_body := StaticBody.new()
	var floor_shape := CollisionShape.new()
	var box := BoxShape.new()
	# Box3D no soporta PlaneShape; caja fina como piso.
	box.extents = Vector3(15, 0.1, 15)
	floor_shape.shape = box
	floor_shape.translation = Vector3(0, -0.1, 0)
	floor_body.add_child(floor_shape)
	floor_body.collision_layer = 1
	root3d.add_child(floor_body)

	var sun := DirectionalLight.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = false
	root3d.add_child(sun)

	var pilot = load("res://core_v2/actors/Pilot_v2.tscn").instance()
	root3d.add_child(pilot)
	pilot.translation = Vector3(0, 0.1, 0)

	var cam := Camera.new()
	cam.translation = Vector3(0, 2.0, 4.2)
	cam.rotation_degrees = Vector3(-22, 0, 0)
	cam.current = true
	root3d.add_child(cam)

	print("BLOB_SHOT mode=", _mode, " engine_blob=", ClassDB.class_exists("BlobShadow"))
	connect("idle_frame", self, "_tick")

func _tick():
	_frames += 1
	if _frames < 120:
		return
	var dir := Directory.new()
	dir.make_dir_recursive(_out_dir)
	var img = root.get_texture().get_data()
	img.flip_y()
	var path := "%s/pilot_%s.png" % [_out_dir, _mode]
	print("BLOB_SHOT saved=", path, " err=", img.save_png(path))
	quit(0)
