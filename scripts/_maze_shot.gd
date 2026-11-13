extends SceneTree

# Captura de la bahía + laberinto industrial streamed (MachineBayLabyrinthStreamer).
# Uso:  DISPLAY=:0 tools/godot --path . -s scripts/_maze_shot.gd
# Genera PNGs en test_output/maze/ (puente de entrada + interior del laberinto).

var _frames := 0
var _shot_frames := -1
var _shot_tag := ""
var _shot_eye := Vector3.ZERO
var _shot_target := Vector3.ZERO
var _shot_fov := 70.0
var _cam: Camera = null
var _bay: Node = null
var _dummy: Node = null
var _out_dir := "res://test_output/maze"

func _init() -> void:
	var dir := Directory.new()
	dir.make_dir_recursive(_out_dir)
	_bay = load("res://core_v2/levels/machines/MachineBay.tscn").instance()
	root.add_child(_bay)
	current_scene = _bay
	_dummy = KinematicBody.new()
	_dummy.name = "MazeShotDummy"
	root.add_child(_dummy)
	var streamer: Node = _bay.get_node("MachineBayLabyrinthStreamer")
	streamer.player_path = streamer.get_path_to(_dummy)
	streamer.activate_now()
	var cinematics = _bay.get_node_or_null("Cinematics")
	if cinematics != null:
		cinematics.queue_free()
	var pilot = _bay.get_node_or_null("Pilot")
	if pilot != null:
		pilot.queue_free()
	connect("physics_frame", self, "_tick")

func _tick() -> void:
	if _shot_frames >= 0:
		_shot_frames += 1
		if _shot_frames == 16:
			_capture()
		return
	_frames += 1
	match _frames:
		150:
			_start_shot("bay_bridge", Vector3(27.0, 7.0, 23.0), Vector3(27.0, 1.5, 32.0), 66.0)
		180:
			_dummy.global_transform.origin = Vector3(36.0, 0.0, 40.0)
			var st: Node = _bay.get_node("MachineBayLabyrinthStreamer")
			st.force_request_keys([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1), Vector2(2, 0), Vector2(0, 2)])
		700:
			var st2: Node = _bay.get_node("MachineBayLabyrinthStreamer")
			print("[maze_shot] active=", st2.get_active_chunk_keys(), " touched=", st2.get("_chunk_touched").size())
			_start_shot("maze_interior", Vector3(30.0, 4.4, 44.0), Vector3(40.0, 1.8, 40.0), 68.0)

func _start_shot(tag: String, eye: Vector3, target: Vector3, fov: float) -> void:
	_shot_tag = tag
	_shot_eye = eye
	_shot_target = target
	_shot_fov = fov
	_shot_frames = 0
	_cam = Camera.new()
	_cam.name = "ShotCam_" + tag
	_look_at(_cam, eye, target)
	_cam.fov = fov
	_cam.far = 400.0
	root.add_child(_cam)
	_cam.current = true

func _capture() -> void:
	var img = root.get_texture().get_data()
	img.flip_y()
	var path := "%s/%s.png" % [_out_dir, _shot_tag]
	var err: int = img.save_png(path)
	print("[maze_shot] saved=", path, " err=", err)
	if _cam != null:
		_cam.queue_free()
	_shot_frames = -1
	if _shot_tag == "maze_interior":
		quit(0)

func _look_at(cam: Camera, eye: Vector3, target: Vector3) -> void:
	var dir := (target - eye).normalized()
	var z_axis := -dir
	var x_axis := Vector3.UP.cross(z_axis).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis)
	cam.global_transform = Transform(basis, eye)
