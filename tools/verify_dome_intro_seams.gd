extends SceneTree

const SCENE_PATH := "res://core_v2/levels/interiors/DomeIntro_Seams.tscn"
const SEAM_COUNT := 5

func _init() -> void:
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		push_error("[verify_seams] missing %s" % SCENE_PATH)
		quit(1)
		return
	var seams := scene.instance()
	var mesh_count := 0
	for child in seams.get_children():
		if not (child is MeshInstance):
			continue
		var mesh_instance := child as MeshInstance
		if mesh_instance.mesh == null or not mesh_instance.use_in_baked_light:
			push_error("[verify_seams] invalid seam mesh %s" % mesh_instance.name)
			quit(1)
			return
		mesh_count += 1
	if mesh_count != SEAM_COUNT * 2:
		push_error("[verify_seams] expected %d meshes, found %d" % [SEAM_COUNT * 2, mesh_count])
		quit(1)
		return
	print("[verify_seams] PASS %d seams / %d bake meshes" % [SEAM_COUNT, mesh_count])
	quit(0)
