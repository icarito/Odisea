extends GdUnitTestSuite

const PersistenceManagerScript = preload("res://core_v2/autoloads/PersistenceManager.gd")
const MenuScript = preload("res://core_v2/ui/Menu.gd")
const DOME_INTRO := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const TEST_DIRECTORY_WITH_LAST := "user://test_menu_checkpoint_flow_last"
const TEST_DIRECTORY_WITHOUT_LAST := "user://test_menu_checkpoint_flow_empty"

func before_test() -> void:
	_cleanup_test_directories()

func after_test() -> void:
	_cleanup_test_directories()

func test_new_game_targets_dome_intro() -> void:
	assert_str(MenuScript.FIRST_GAME_SCENE).is_equal(DOME_INTRO)
	var dome_scene := load(DOME_INTRO) as PackedScene
	assert_object(dome_scene).is_not_null()
	var dome: Node = auto_free(dome_scene.instance())
	assert_object(dome.get_node_or_null("Pilot_v2")).is_not_null()
	assert_object(dome.get_node_or_null("Pilot_v2/CameraRig/Yaw/Pitch/OTS_Offset/SpringArm/Camera")).is_not_null()

func test_continue_requires_a_real_last_checkpoint() -> void:
	var persistence = auto_free(PersistenceManagerScript.new())
	persistence.checkpoint_directory = TEST_DIRECTORY_WITH_LAST

	var resource = persistence.get_checkpoint_resource(DOME_INTRO)
	assert_str(persistence.get_continue_scene_path()).is_empty()

	resource.slots["last"] = {
		"transform": Transform(Basis.IDENTITY, Vector3(1.0, 2.0, 3.0)),
		"yaw": 0.5,
		"pitch": -0.1
	}
	persistence.save_checkpoint_resource(DOME_INTRO)

	assert_str(persistence.get_continue_scene_path()).is_equal(DOME_INTRO)
	assert_bool(persistence.request_continue()).is_true()
	var checkpoint = persistence.consume_continue_checkpoint(DOME_INTRO)
	assert_dict(checkpoint).contains_keys(["transform", "yaw", "pitch"])
	assert_vector3(checkpoint["transform"].origin).is_equal(Vector3(1.0, 2.0, 3.0))
	assert_object(persistence.consume_continue_checkpoint(DOME_INTRO)).is_null()

func test_checkpoint_file_without_last_does_not_enable_continue() -> void:
	var persistence = auto_free(PersistenceManagerScript.new())
	persistence.checkpoint_directory = TEST_DIRECTORY_WITHOUT_LAST
	var resource = persistence.get_checkpoint_resource(DOME_INTRO)
	resource.slots["1"] = Transform.IDENTITY
	persistence.save_checkpoint_resource(DOME_INTRO)
	assert_str(persistence.get_continue_scene_path()).is_empty()

func _cleanup_test_directories() -> void:
	_cleanup_directory(TEST_DIRECTORY_WITH_LAST)
	_cleanup_directory(TEST_DIRECTORY_WITHOUT_LAST)

func _cleanup_directory(path: String) -> void:
	var dir := Directory.new()
	if not dir.dir_exists(path):
		return
	if dir.open(path) != OK:
		return
	dir.list_dir_begin(true, true)
	var file_name := dir.get_next()
	while file_name != "":
		dir.remove(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	dir.change_dir("user://")
	dir.remove(path)
