extends SceneTree

# bench_runner.gd - CLI benchmark runner
# Usage: godot3-bin --no-window -s core_v2/tests/perf/bench_runner.gd scene_path seconds

var _target_scene := ""
var _capture_sec := 5.0
var _warmup_sec := 2.0
var _start_time := 0.0
var _fps_samples := []
var _capturing := false
var _scene_loaded := false
var _initialized := false

func _init():
	var args = OS.get_cmdline_args()
	_target_scene = "res://core_v2/levels/OdiseaExterior.tscn"
	if args.size() >= 3:
		_target_scene = args[2]
	if args.size() >= 4:
		_capture_sec = float(args[3])

func _idle(_delta):
	if not _initialized:
		_initialized = true
		print("CAPTURE:{\"status\":\"loading\",\"scene\":\"%s\",\"seconds\":%.0f}" % [_target_scene, _capture_sec])
		var err = change_scene(_target_scene)
		if err != OK:
			print("CAPTURE:{\"status\":\"error\",\"error\":\"scene_load_failed\",\"err_code\":%d}" % err)
			quit(1)
		return

	if not _scene_loaded:
		var cs = get_current_scene()
		if cs and cs.filename == _target_scene:
			_scene_loaded = true
			_start_time = OS.get_ticks_msec() / 1000.0
		return

	var elapsed = OS.get_ticks_msec() / 1000.0 - _start_time
	if not _capturing:
		if elapsed >= _warmup_sec:
			_capturing = true
			_fps_samples = []
		return

	var fps = float(Performance.get_monitor(Performance.TIME_FPS))
	_fps_samples.append(fps)

	if elapsed >= _warmup_sec + _capture_sec:
		_finish()

func _finish():
	var avg = 0.0
	var mn = 999.0
	var mx = 0.0
	var lt30 = 0
	for f in _fps_samples:
		avg += f
		mn = min(mn, f)
		mx = max(mx, f)
		if f < 30:
			lt30 += 1
	if _fps_samples.size() > 0:
		avg /= _fps_samples.size()

	var dc = int(Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME))
	var nodes = int(get_node_count())
	var result = {
		"scene": _target_scene.get_file().replace(".tscn", ""),
		"avg_fps": stepify(avg, 0.1),
		"min_fps": stepify(mn, 0.1),
		"max_fps": stepify(mx, 0.1),
		"frames_lt30": lt30,
		"draw_calls": dc,
		"node_count": nodes,
		"samples": _fps_samples.size()
	}
	print("CAPTURE:" + to_json(result))
	quit(0)
