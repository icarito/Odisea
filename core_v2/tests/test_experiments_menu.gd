extends GdUnitTestSuite

# Submenu "Experimentos": cada episodio existe, esta declarado como raiz de exportacion (los
# globs del export no caminan dependencias) y el submenu lo ofrece.

const Experiments = preload("res://core_v2/levels/Experiments.gd")
const MenuScript = preload("res://core_v2/ui/ExperimentsMenu.gd")

var _chosen := ""


func _on_chosen(scene_path: String) -> void:
	_chosen = scene_path


func test_every_experiment_scene_exists_and_is_an_export_root() -> void:
	var f := File.new()
	assert_int(f.open("res://export_presets.cfg", File.READ)).is_equal(OK)
	var presets: String = f.get_as_text()
	f.close()
	var ids := {}
	for entry in Experiments.LIST:
		assert_bool(ids.has(entry["id"])).is_false()
		ids[entry["id"]] = true
		assert_bool(ResourceLoader.exists(str(entry["scene"]))) \
			.override_failure_message("no existe %s" % entry["scene"]).is_true()
		assert_bool(presets.find("\"%s\"" % entry["scene"]) >= 0) \
			.override_failure_message("%s no es raiz de export_files" % entry["scene"]).is_true()


func test_menu_offers_every_experiment_and_emits_its_scene() -> void:
	var menu: PopupPanel = auto_free(MenuScript.new())
	add_child(menu)
	menu.connect("experiment_chosen", self, "_on_chosen")
	var list: Node = menu.get_child(menu.get_child_count() - 1)
	for child in menu.get_children():
		if child is VBoxContainer:
			list = child
	assert_int(list.get_child_count()).is_equal(Experiments.LIST.size())
	var last: Dictionary = Experiments.LIST[-1]
	(list.get_node(str(last["id"])) as Button).emit_signal("pressed")
	assert_str(_chosen).is_equal(str(last["scene"]))
