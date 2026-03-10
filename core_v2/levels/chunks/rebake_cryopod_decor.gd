extends SceneTree

const SOURCE_SCENE_PATH := "res://core_v2/levels/chunks/BaseTerraceCryopodDecor.tscn"

func _init() -> void:
	var source_scene = load(SOURCE_SCENE_PATH)
	if source_scene == null:
		printerr("[rebake_cryopod_decor] Could not load %s" % SOURCE_SCENE_PATH)
		quit(1)
		return

	var source_root = source_scene.instance()
	get_root().add_child(source_root)

	if not source_root.has_method("bake_baked_scene_copy"):
		printerr("[rebake_cryopod_decor] Source scene has no bake_baked_scene_copy().")
		quit(1)
		return

	var ok_layout = bool(source_root.call("bake_layout_resource"))
	var ok_scene = bool(source_root.call("bake_baked_scene_copy"))
	quit(0 if ok_layout and ok_scene else 1)
