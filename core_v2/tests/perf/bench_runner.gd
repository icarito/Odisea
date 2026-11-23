extends SceneTree

# bench_runner.gd - CLI benchmark runner
# Usage: godot3-bin --no-window -s core_v2/tests/perf/bench_runner.gd scene_path seconds

var _target_scene := ""
var _capture_sec := 5.0
var _warmup_sec := 2.0
var _start_time := 0.0
var _fps_samples := []
var _physics_ms_samples := []
var _draw_samples := []
var _capturing := false
var _scene_loaded := false
var _initialized := false

func _init():
	# OS.get_cmdline_args() incluye flags del motor y sus valores (--path, -s, script...);
	# sólo aceptamos un scene_path res:// y un segundo argumento numérico (segundos).
	_target_scene = "res://core_v2/levels/OdiseaExterior.tscn"
	for a in OS.get_cmdline_args():
		var arg := String(a)
		if arg.begins_with("res://") and arg.ends_with(".tscn"):
			_target_scene = arg
		elif arg.is_valid_float() and float(arg) > 0.0 and float(arg) <= 120.0:
			_capture_sec = float(arg)

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
	_physics_ms_samples.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)))
	_draw_samples.append(float(Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME)))

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
	# ms de física por frame (promedio sobre las muestras capturadas; renderer headless ~= null).
	var physics_ms = 0.0
	var peak_physics_ms = 0.0
	var avg_draws = 0.0
	for i in range(_physics_ms_samples.size()):
		physics_ms += _physics_ms_samples[i]
		peak_physics_ms = max(peak_physics_ms, _physics_ms_samples[i])
		avg_draws += _draw_samples[i]
	if _physics_ms_samples.size() > 0:
		physics_ms /= _physics_ms_samples.size()
		avg_draws /= _physics_ms_samples.size()
	var result = {
		"scene": _target_scene.get_file().replace(".tscn", ""),
		"avg_fps": stepify(avg, 0.1),
		"min_fps": stepify(mn, 0.1),
		"max_fps": stepify(mx, 0.1),
		"frames_lt30": lt30,
		"draw_calls": dc,
		"avg_draw_calls": stepify(avg_draws, 0.1),
		"physics_ms": stepify(physics_ms, 0.01),
		"peak_physics_ms": stepify(peak_physics_ms, 0.01),
		"node_count": nodes,
		"samples": _fps_samples.size()
	}
	print("CAPTURE:" + to_json(result))
	quit(0)
