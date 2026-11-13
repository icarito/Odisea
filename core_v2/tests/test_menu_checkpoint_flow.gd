extends GdUnitTestSuite

const PersistenceManagerScript = preload("res://core_v2/autoloads/PersistenceManager.gd")
const MenuScript = preload("res://core_v2/ui/Menu.gd")
const DOME_INTRO := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const RING_HUB := "res://core_v2/levels/RingHub_Level.tscn"
const TEST_DIRECTORY_WITH_LAST := "user://test_menu_checkpoint_flow_last"
const TEST_DIRECTORY_WITHOUT_LAST := "user://test_menu_checkpoint_flow_empty"
const TeleportSystemScript = preload("res://core_v2/systems/TeleportSystem.gd")

class SnapshotValve extends Spatial:
	var is_open: bool = false

	func get_snapshot() -> Dictionary:
		return {"is_open": is_open}

	func restore_snapshot(data: Dictionary) -> void:
		is_open = bool(data["is_open"])

class ContinuePlayer extends Spatial:
	var yaw: float = 0.0
	var pitch: float = 0.0
	var valve: SnapshotValve
	var valve_open_at_teleport: bool = false
	var camera_yaw: float = 0.0
	var camera_pitch: float = 0.0

	func teleport_to(target: Transform) -> void:
		valve_open_at_teleport = valve.is_open
		global_transform = target

	func get_snapshot() -> Dictionary:
		return {"transform": global_transform, "yaw": yaw, "pitch": pitch}

	func restore_snapshot(data: Dictionary) -> void:
		global_transform = data["transform"]
		yaw = float(data["yaw"])
		pitch = float(data["pitch"])

	func snap_camera_to_current_state() -> void:
		camera_yaw = yaw
		camera_pitch = pitch

class NewGameMenu extends MenuScript:
	var started_scene: String = ""

	func _ready() -> void:
		pass # Solo flujo del menú, sin música, preload ni transición real.

	func _start_game(scene_path) -> void:
		started_scene = String(scene_path)

func before_test() -> void:
	_cleanup_test_directories()

func after_test() -> void:
	_cleanup_test_directories()

func test_first_game_scene_loads_and_instances() -> void:
	assert_str(MenuScript.FIRST_GAME_SCENE).is_equal(RING_HUB)
	var hub_scene := load(RING_HUB) as PackedScene
	assert_object(hub_scene).is_not_null()
	var hub: Node = auto_free(hub_scene.instance())
	assert_object(hub.get_node_or_null("Pilot")).is_not_null()
	assert_object(hub.get_node_or_null("Criopod_Vert")).is_not_null()

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

func test_continue_restores_mutated_world_before_applying_player_pose() -> void:
	var persistence: Node = get_node("/root/PersistenceManager")
	var previous_directory: String = persistence.checkpoint_directory
	var previous_resource: Resource = persistence.checkpoint_resource
	var previous_request: bool = persistence._continue_requested
	var previous_scene: Node = get_tree().current_scene
	var scene: Spatial = auto_free(Spatial.new())
	scene.filename = DOME_INTRO
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	persistence.checkpoint_directory = TEST_DIRECTORY_WITH_LAST

	var valve: SnapshotValve = SnapshotValve.new()
	valve.add_to_group("replay_sync")
	scene.add_child(valve)
	var player: ContinuePlayer = ContinuePlayer.new()
	player.valve = valve
	player.add_to_group("replay_sync")
	scene.add_child(player)
	# Deliberately different snapshot pose: the explicit checkpoint pose must win.
	player.global_transform.origin = Vector3(9.0, 8.0, 7.0)
	player.yaw = -0.7
	player.pitch = 0.3
	valve.is_open = true
	var resource: Resource = persistence.get_checkpoint_resource(DOME_INTRO)
	var target := Transform(Basis.IDENTITY, Vector3(1.0, 2.0, 3.0))
	resource.slots["last"] = {
		"transform": target, "yaw": 0.5, "pitch": -0.1,
		"replay_snapshot": {
			String(valve.get_path()): valve.get_snapshot(),
			String(player.get_path()): player.get_snapshot()
		}
	}
	persistence.save_checkpoint_resource(DOME_INTRO)
	valve.is_open = false
	player.global_transform = Transform.IDENTITY
	assert_bool(persistence.request_continue()).is_true()

	var teleport: Node = TeleportSystemScript.new()
	teleport.player_controller = player
	scene.add_child(teleport)
	# Exercise the real _ready -> deferred Continue entry point, not just the slot.
	yield(get_tree(), "idle_frame")
	assert_bool(valve.is_open).is_true()
	assert_bool(player.valve_open_at_teleport).is_true()
	assert_vector3(player.global_transform.origin).is_equal(target.origin)
	assert_float(player.yaw).is_equal(0.5)
	assert_float(player.pitch).is_equal(-0.1)
	assert_float(player.camera_yaw).is_equal(0.5)
	assert_float(player.camera_pitch).is_equal(-0.1)
	assert_object(persistence.consume_continue_checkpoint(DOME_INTRO)).is_null()

	get_tree().current_scene = previous_scene
	persistence.checkpoint_directory = previous_directory
	persistence.checkpoint_resource = previous_resource
	persistence._continue_requested = previous_request

func test_checkpoint_file_without_last_does_not_enable_continue() -> void:
	var persistence = auto_free(PersistenceManagerScript.new())
	persistence.checkpoint_directory = TEST_DIRECTORY_WITHOUT_LAST
	var resource = persistence.get_checkpoint_resource(DOME_INTRO)
	resource.slots["1"] = Transform.IDENTITY
	persistence.save_checkpoint_resource(DOME_INTRO)
	assert_str(persistence.get_continue_scene_path()).is_empty()

func test_new_game_clears_all_campaign_checkpoints_but_preserves_configuration() -> void:
	var persistence: Node = auto_free(PersistenceManagerScript.new())
	persistence.checkpoint_directory = TEST_DIRECTORY_WITH_LAST
	for scene_path in [DOME_INTRO, RING_HUB]:
		var resource: Resource = persistence.get_checkpoint_resource(scene_path)
		resource.slots["last"] = {"transform": Transform.IDENTITY}
		persistence.save_checkpoint_resource(scene_path)
	var config := ConfigFile.new()
	config.set_value("settings", "volume", 0.35)
	config.set_value("privacy", "consent", false)
	var config_path: String = TEST_DIRECTORY_WITH_LAST + "/settings.cfg"
	assert_int(config.save(config_path)).is_equal(OK)
	assert_bool(persistence.request_continue()).is_true()

	assert_bool(persistence.clear_campaign_progress()).is_true()
	assert_bool(persistence.has_campaign_progress()).is_false()
	assert_str(persistence.get_continue_scene_path()).is_empty()
	assert_bool(persistence._continue_requested).is_false()
	assert_object(persistence.checkpoint_resource).is_null()
	var dir := Directory.new()
	for scene_path in [DOME_INTRO, RING_HUB]:
		assert_bool(dir.file_exists("%s/%s.tres" % [TEST_DIRECTORY_WITH_LAST, persistence.hash_scene_path(scene_path)])).is_false()
	assert_bool(dir.file_exists(TEST_DIRECTORY_WITH_LAST + "/continue.cfg")).is_false()
	assert_int(config.load(config_path)).is_equal(OK)
	assert_float(config.get_value("settings", "volume")).is_equal(0.35)
	assert_bool(config.get_value("privacy", "consent")).is_false()
	assert_dict(persistence.get_checkpoint_resource(DOME_INTRO).slots).is_empty()

func test_cancel_new_game_preserves_save_and_confirm_starts_fresh() -> void:
	var persistence: Node = get_node("/root/PersistenceManager")
	var previous_directory: String = persistence.checkpoint_directory
	var previous_resource: Resource = persistence.checkpoint_resource
	var previous_request: bool = persistence._continue_requested
	persistence.checkpoint_directory = TEST_DIRECTORY_WITH_LAST
	var resource: Resource = persistence.get_checkpoint_resource(DOME_INTRO)
	resource.slots["last"] = {"transform": Transform.IDENTITY}
	persistence.save_checkpoint_resource(DOME_INTRO)
	assert_bool(persistence.request_continue()).is_true()

	var menu: Control = auto_free(Control.new())
	get_tree().root.add_child(menu)
	# Colgar el script después del ready evita el arranque real del menú base.
	menu.set_script(NewGameMenu)
	menu.new_game_button = Button.new()
	menu.continue_button = Button.new()
	menu.add_child(menu.new_game_button)
	menu.add_child(menu.continue_button)
	menu._check_save_game()
	menu._on_NewGame_pressed()
	assert_bool(menu._new_game_confirm.visible).is_true()
	assert_str(menu.started_scene).is_empty()
	# Cancelar usa el mismo hide que el botón Cancelar/Escape de ConfirmationDialog.
	menu._new_game_confirm.get_cancel().emit_signal("pressed")
	assert_bool(menu._new_game_confirm.visible).is_false()
	assert_str(persistence.get_continue_scene_path()).is_equal(DOME_INTRO)
	assert_bool(persistence._continue_requested).is_true()
	assert_str(menu.started_scene).is_empty()
	menu._on_NewGame_pressed()
	menu._new_game_confirm.emit_signal("confirmed")
	menu._new_game_confirm.hide()
	assert_str(menu.started_scene).is_equal(MenuScript.FIRST_GAME_SCENE)
	assert_bool(persistence.has_campaign_progress()).is_false()
	assert_bool(persistence._continue_requested).is_false()
	assert_bool(menu.continue_button.disabled).is_true()
	# Sin progreso no vuelve a preguntar y también cancela un Continue obsoleto.
	menu.started_scene = ""
	persistence._continue_requested = true
	menu._on_NewGame_pressed()
	assert_bool(menu._new_game_confirm.visible).is_false()
	assert_str(menu.started_scene).is_equal(MenuScript.FIRST_GAME_SCENE)
	assert_bool(persistence._continue_requested).is_false()

	persistence.checkpoint_directory = previous_directory
	persistence.checkpoint_resource = previous_resource
	persistence._continue_requested = previous_request

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
