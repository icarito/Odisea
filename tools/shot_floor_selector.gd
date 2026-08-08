extends SceneTree

# shot_floor_selector.gd — render ElevatorFloorSelector by aiming a camera at it,
# which is exactly how the dial is driven in game. Three captures: the dial with
# the aim on nothing, the dial with the aim on a stop, and the prop in 3D.
#
#   godot3-bin -s tools/shot_floor_selector.gd --no-window

const PROP := "res://core_v2/props/elevator/ElevatorFloorSelector.tscn"
const LABELS := ["1", "2", "3", "4", "5", "6"]
const OUT_DIR := "res://test_output/props/"
const AIMED_OPTION := 3
const SHOWN_LEVEL := 2.45  # Car between the third and fourth stop.

var _prop: Spatial = null
var _selector: Control = null
var _camera: Camera = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Spatial.new()
	get_root().add_child(world)

	var light := DirectionalLight.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	world.add_child(light)

	_prop = load(PROP).instance()
	world.add_child(_prop)
	_prop.floor_labels = PoolStringArray(LABELS)
	_prop.elevator_path = NodePath("")

	# Roughly where the player's head would be.
	_camera = Camera.new()
	_camera.translation = Vector3(0, 1.7, 2.4)
	_camera.fov = 55.0
	_camera.current = true
	world.add_child(_camera)

	for _i in range(10):
		yield(self, "idle_frame")

	_prop.call("_rebuild_options")
	_prop.set_active(true)
	_selector = _prop.get_node("Viewport/RadialSelector")

	for _i in range(30):
		yield(self, "idle_frame")

	var dir := Directory.new()
	dir.make_dir_recursive(OUT_DIR)

	# The prop drives the needle off a live elevator; standalone there is none, so
	# it is set here to show the car partway between two stops.
	_selector.set_level(SHOWN_LEVEL)
	_selector.set_readout_text(LABELS[int(round(SHOWN_LEVEL))])

	# 1. Look away from the panel. This is now the only way to focus nothing:
	# anywhere on the projection focuses some stop, by design.
	_camera.look_at(Vector3(6, 1.7, 3), Vector3.UP)
	yield(_settle(), "completed")
	print("IDLE:", _save(_dial_image(), OUT_DIR + "FloorSelector_idle.png"))
	print("     selected=", _selector.get_hovered_index())

	# 2. Aim at a stop.
	_camera.look_at(_dial_point(AIMED_OPTION), Vector3.UP)
	yield(_settle(), "completed")
	_selector.set_level(SHOWN_LEVEL)
	print("UI:", _save(_dial_image(), OUT_DIR + "FloorSelector_ui.png"))
	print("    selected=", _selector.get_hovered_index(), " expected=", AIMED_OPTION)

	# 3. The prop in 3D. The root viewport is blank under --no-window, so render
	# through a child Viewport sharing the world (see docs: headless 3D capture).
	var shot := Viewport.new()
	shot.size = Vector2(960, 720)
	shot.own_world = false
	shot.render_target_update_mode = Viewport.UPDATE_ALWAYS
	shot.render_target_v_flip = true
	get_root().add_child(shot)
	var shot_cam := Camera.new()
	shot_cam.translation = _camera.translation
	shot_cam.fov = _camera.fov
	shot.add_child(shot_cam)
	shot_cam.global_transform = _camera.global_transform
	shot_cam.current = true

	yield(_settle(), "completed")
	print("3D:", _save(shot.get_texture().get_data(), OUT_DIR + "FloorSelector_world.png"))
	quit(0)


func _settle():
	for _i in range(6):
		yield(self, "idle_frame")
	yield(VisualServer, "frame_post_draw")


func _dial_point(option_index: int) -> Vector3:
	"""World point on the projection: an option's seat, or its hub for index < 0."""
	var mesh := _prop.get_node("ScreenContainer/ScreenMesh") as MeshInstance
	var quad_size: Vector2 = (mesh.mesh as QuadMesh).size
	var local := Vector3(0, 0, 0)
	if option_index >= 0:
		var angle: float = _selector._index_to_screen_angle(option_index)
		var radius: float = min(quad_size.x, quad_size.y) / 2.0 * _selector.option_radius
		# Screen Y is down, world Y is up.
		local = Vector3(cos(angle) * radius, -sin(angle) * radius, 0)
	return mesh.global_transform.xform(local)


func _dial_image() -> Image:
	var img: Image = _prop.get_node("Viewport").get_texture().get_data()
	img.flip_y()
	return img


func _save(img: Image, path: String) -> String:
	var err = img.save_png(path)
	return "%s ok=%s size=%s" % [path, err == OK, img.get_size()]
