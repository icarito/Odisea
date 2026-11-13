extends SceneTree

# Captura de la bahía + laberinto industrial streamed (MachineBayLabyrinthStreamer).
# Uso:  DISPLAY=:0 tools/godot --path . -s scripts/_maze_shot.gd
# Genera PNGs en test_output/maze/.

var _frames := 0
var _phase := 0
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
	streamer.debug_verbose = true
	connect("physics_frame", self, "_tick")

func _move_dummy(pos: Vector3) -> void:
	_dummy.global_transform.origin = pos

func _tick() -> void:
	_frames += 1
	match _phase:
		0:
			if _frames < 150:
				return
			_shoot("bay_entry", Vector3(20.0, 6.5, 10.0), Vector3(33.0, 0.5, 29.0))
			_phase = 1
			_frames = 0
		1:
			if _frames < 30:
				return
			_move_dummy(Vector3(36.0, 0.0, 40.0))
			var st0: Node = _bay.get_node("MachineBayLabyrinthStreamer")
			st0.force_request_keys([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1), Vector2(2, 0), Vector2(0, 2)])
			_phase = 2
			_frames = 0
		2:
			if _frames < 500:
				return
			var st: Node = _bay.get_node("MachineBayLabyrinthStreamer")
			print("[maze_shot] active=", st.get_active_chunk_keys(), " touched=", st.get("_chunk_touched").size(), " pending=", st.get("_pending_chunks").size())
			_shoot("maze_interior", Vector3(27.0, 4.5, 45.0), Vector3(41.0, 0.5, 40.0))
			_phase = 3
			_frames = 0
		3:
			if _frames < 30:
				return
			_move_dummy(Vector3(58.0, 0.0, 72.0))
			var st1: Node = _bay.get_node("MachineBayLabyrinthStreamer")
			st1.force_request_keys([Vector2(1, 1), Vector2(2, 1), Vector2(1, 2), Vector2(2, 2), Vector2(3, 1), Vector2(1, 3)])
			_phase = 4
			_frames = 0
		4:
			if _frames < 500:
				return
			var st2: Node = _bay.get_node("MachineBayLabyrinthStreamer")
			print("[maze_shot] deep active=", st2.get_active_chunk_keys().size(), " touched=", st2.get("_chunk_touched").size())
			_shoot("maze_deep", Vector3(52.0, 6.0, 82.0), Vector3(66.0, 0.5, 74.0))
			_phase = 5
			_frames = 0
		5:
			if _frames < 20:
				return
			quit(0)

func _shoot(tag: String, eye: Vector3, target: Vector3) -> void:
	var cam := Camera.new()
	cam.name = "ShotCam_" + tag
	_look_at(cam, eye, target)
	cam.fov = 70.0
	cam.far = 400.0
	root.add_child(cam)
	cam.current = true
	for _i in range(12):
		yield(self, "idle_frame")
	var img = root.get_texture().get_data()
	img.flip_y()
	var path := "%s/%s.png" % [_out_dir, tag]
	var err: int = img.save_png(path)
	print("[maze_shot] saved=", path, " err=", err)
	cam.queue_free()

func _look_at(cam: Camera, eye: Vector3, target: Vector3) -> void:
	var dir := (target - eye).normalized()
	var z_axis := -dir
	var x_axis := Vector3.UP.cross(z_axis).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis)
	cam.global_transform = Transform(basis, eye)
