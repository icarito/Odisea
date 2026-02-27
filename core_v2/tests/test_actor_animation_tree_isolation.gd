extends GdUnitTestSuite

const PILOT_SCENE = preload("res://core_v2/actors/Pilot_v2.tscn")
const PROGRAMMER_SCENE = preload("res://core_v2/actors/Programmer_v2.tscn")

func _setup_scene_root() -> Node:
	var scene := Node.new()
	scene.name = "ActorTreeIsolationRoot"
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	return scene

func _teardown_scene_root(scene: Node) -> void:
	if scene and is_instance_valid(scene):
		scene.queue_free()
	yield (get_tree(), "idle_frame")

func test_pilot_and_programmer_use_different_animation_trees() -> void:
	var scene = _setup_scene_root()

	var pilot = PILOT_SCENE.instance()
	var programmer = PROGRAMMER_SCENE.instance()
	scene.add_child(pilot)
	scene.add_child(programmer)
	yield (get_tree(), "idle_frame")

	var pilot_tree: AnimationTree = pilot.get_node_or_null("Visual/Pivot/AnimationTree")
	var programmer_tree: AnimationTree = programmer.get_node_or_null("Visual/Pivot/AnimationTree")
	assert_object(pilot_tree).is_not_null()
	assert_object(programmer_tree).is_not_null()

	var pilot_tree_path := String(pilot_tree.tree_root.resource_path)
	var programmer_tree_path := String(programmer_tree.tree_root.resource_path)

	assert_str(pilot_tree_path).is_equal("res://core_v2/actors/AnimationTree_Pilot.tres")
	assert_str(programmer_tree_path).is_equal("res://core_v2/actors/AnimationTree_Programmer.tres")
	assert_bool(pilot_tree_path != programmer_tree_path).is_true()

	var pilot_anim_player: AnimationPlayer = pilot.get_node_or_null("Visual/Pivot/Skeleton/AnimationPlayer")
	var programmer_anim_player: AnimationPlayer = programmer.get_node_or_null("Visual/Pivot/Skeleton/AnimationPlayer")
	assert_object(pilot_anim_player).is_not_null()
	assert_object(programmer_anim_player).is_not_null()

	# Pilot-specific legacy locomotion states must remain available.
	assert_bool(pilot_anim_player.has_animation("Backflip001")).is_true()
	assert_bool(pilot_anim_player.has_animation("Run")).is_true()

	# Programmer-specific locomotion states must remain available.
	assert_bool(programmer_anim_player.has_animation("Levitate Entrance")).is_true()
	assert_bool(programmer_anim_player.has_animation("Sprint_Loop")).is_true()

	yield (_teardown_scene_root(scene), "completed")
