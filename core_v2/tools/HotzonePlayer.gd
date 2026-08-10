extends Control

# HotzonePlayer.gd
# Tool scene for playing back binary hotzone captures with enhanced UX.

const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")
const InputProviderV2 = preload("res://core_v2/input/InputProviderV2.gd")
const BINARY_MAGIC := 0x485a4e32 # "HZN2"

onready var status_label = $Overlay/Status
onready var metadata_label = $Overlay/Metadata
onready var metadata_extra_label = $Overlay/MetadataExtra
onready var frame_label = $Overlay/FrameInfo
onready var speed_label = $Overlay/SpeedInfo
onready var icon_auto = $Overlay/IconAuto
onready var icon_manual = $Overlay/IconManual
onready var fps_chart = $Overlay/FPSChart
onready var progress_container = $Overlay/ProgressContainer
onready var progress_fill = $Overlay/ProgressContainer/Fill
onready var btn_play = $Overlay/Controls/BtnPlay
onready var btn_restart = $Overlay/Controls/BtnRestart
onready var overlay = $Overlay
onready var btn_collapse = $BtnCollapse

var replay_data := {}
var frames := []
# Traza de rendimiento de la reproduccion. La telemetria esta apagada a proposito durante
# un replay (ANNAV2.set_replay_mode corta el hilo de red para no crear sesiones fantasma),
# asi que no hay heartbeats que muestrear desde afuera. Como el replay SI da entrada
# determinista, es el unico contexto donde dos corridas son comparables: se vuelca la traza
# a disco al terminar y se recoge con `adb pull`.
const PERF_TRACE_PATH := "user://replay_perf.json"
var _perf_trace := []
var current_frame_idx := 0
var playback_speed := 1.0
var is_paused := true setget _set_paused
var player_node = null
var player_animator = null
var warmup_sec := 1.5
var _warmup_remaining := 0.0
var _is_warming_up := false
var initial_scene_path := ""
var loaded_scene_node = null
var scene_override := ""

var _is_scrubbing := false
var _chart_points := PoolVector2Array()
var _chart_colors := PoolColorArray()

func _ready():
	# Playback pauses the SceneTree (get_tree().paused). Without PAUSE_MODE_PROCESS
	# this Control and its buttons (transport, collapse) stop receiving GUI input
	# while paused — so nothing is clickable. Set it here, in _ready, so it holds
	# even if the scene fails to load (then _attach_loaded_scene never runs).
	pause_mode = Node.PAUSE_MODE_PROCESS

	# Enter replay mode immediately, before any gameplay scene mounts: this scene
	# IS the player, the user never controls the avatar here. Setting it now (not
	# in _start_replay, which runs much later and not at all if loading fails)
	# keeps the gameplay touch UI hidden from the very first frame.
	var session_node = get_node_or_null("/root/SessionManager")
	if session_node:
		session_node.is_replaying = true
	var mobile_ui = get_node_or_null("/root/MobileUIManager")
	if mobile_ui:
		mobile_ui.set_replay_mode(true)

	# Silence telemetry for the whole playback: a replay viewer must not appear on
	# the dashboard as a phantom session nor feed playback FPS into the stats. ANNA
	# auto-detects replay from the cmdline (native/web), but the Android deep link
	# change_scene()s here after ANNA already booted, so tell it explicitly. Also
	# stop the recorder now (not later in _start_replay, which is skipped if the
	# scene fails to load) so we never record over a playback.
	var anna_node = get_node_or_null("/root/ANNAV2")
	if anna_node and anna_node.has_method("set_replay_mode"):
		anna_node.set_replay_mode(true)
	var recorder_node = get_node_or_null("/root/HotzoneRecorder")
	if recorder_node:
		recorder_node.hotzone_enabled = false

	# UI Connections
	progress_container.connect("gui_input", self, "_on_progress_gui_input")
	fps_chart.connect("gui_input", self, "_on_progress_gui_input")
	fps_chart.connect("draw", self, "_on_fps_chart_draw")

	$Overlay/Controls/BtnStart.connect("pressed", self, "seek_to_frame", [0])
	$Overlay/Controls/BtnEnd.connect("pressed", self, "seek_to_frame", [-1])
	$Overlay/Controls/BtnBack.connect("pressed", self, "_seek_relative_time", [-1.0])
	$Overlay/Controls/BtnForward.connect("pressed", self, "_seek_relative_time", [1.0])
	btn_play.connect("toggled", self, "_on_play_toggled")
	$Overlay/Controls/Btn1x.connect("pressed", self, "_set_speed", [1.0])
	$Overlay/Controls/Btn2x.connect("pressed", self, "_set_speed", [2.0])
	$Overlay/Controls/Btn4x.connect("pressed", self, "_set_speed", [4.0])
	btn_restart.connect("pressed", self, "restart_replay")
	btn_collapse.connect("toggled", self, "_on_collapse_toggled")

	# Parse command line
	var replay_path = ""

	if OS.has_feature("web"):
		var js = JavaScript.get_interface("OdiseaShell")
		if js != null and js.pendingRunbin != null:
			print("[HotzonePlayer] Binary data found in OdiseaShell.pendingRunbin")
			var b64 = String(js.pendingRunbin)
			var buf = Marshalls.base64_to_raw(b64)
			js.pendingRunbin = null

			if buf.size() > 0:
				var dir = Directory.new()
				if not dir.dir_exists("user://hotzones"):
					dir.make_dir_recursive("user://hotzones")

				var f = File.new()
				if f.open("user://hotzones/remote.bin", File.WRITE) == OK:
					f.store_buffer(buf)
					f.close()
					replay_path = "user://hotzones/remote.bin"

	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--replay-file" and i + 1 < args.size():
			replay_path = args[i + 1]
		elif args[i] == "--replay-scene" and i + 1 < args.size():
			scene_override = args[i + 1]
		elif args[i] == "--replay-speed" and i + 1 < args.size():
			playback_speed = max(1.0, float(args[i + 1]))
		elif args[i] == "--replay-warmup" and i + 1 < args.size():
			warmup_sec = max(0.0, float(args[i + 1]))

	# Android deep link (odisea://replay): Boot stashed the signed download URL
	# on SessionManager. Fetch the .bin asynchronously, then play it.
	if replay_path == "":
		var session = get_node_or_null("/root/SessionManager")
		if session and typeof(session.replay_meta) == TYPE_DICTIONARY:
			var dl_url := String(session.replay_meta.get("deep_link_url", ""))
			if dl_url != "":
				session.replay_meta = {}
				_fetch_remote_replay(dl_url)
				return

	if replay_path == "":
		_show_error("No replay file specified. Use --replay-file <path>")
		return

	if not _load_binary(replay_path):
		return

	_prepare_scene()

# Downloads a signed hotzone .bin from central (Android deep link path) to a
# local file, then loads + plays it. Async via HTTPRequest.
func _fetch_remote_replay(url: String) -> void:
	status_label.text = "Descargando captura..."
	var http := HTTPRequest.new()
	add_child(http)
	http.connect("request_completed", self, "_on_remote_replay_completed")
	var err := http.request(url)
	if err != OK:
		_show_error("No se pudo iniciar la descarga (err=%d)" % err)

func _on_remote_replay_completed(result: int, response_code: int, _headers: PoolStringArray, body: PoolByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_show_error("Descarga fallida (HTTP %d)" % response_code)
		return
	var dir := Directory.new()
	if not dir.dir_exists("user://hotzones"):
		dir.make_dir_recursive("user://hotzones")
	var f := File.new()
	if f.open("user://hotzones/remote.bin", File.WRITE) != OK:
		_show_error("No se pudo guardar la captura descargada.")
		return
	f.store_buffer(body)
	f.close()
	if _load_binary("user://hotzones/remote.bin"):
		_prepare_scene()

func _load_binary(path: String) -> bool:
	var f = File.new()
	if f.open(path, File.READ) != OK:
		_show_error("Could not open file: " + path)
		return false

	var magic = f.get_32()
	if magic != BINARY_MAGIC:
		_show_error("Invalid file magic. Expected HZN2")
		f.close()
		return false

	var data_blob = f.get_buffer(f.get_len() - 4)
	f.close()

	var data = bytes2var(data_blob)
	if typeof(data) != TYPE_DICTIONARY:
		_show_error("Failed to parse replay data.")
		return false

	replay_data = data
	frames = data.get("frames", [])

	if frames.empty():
		_show_error("Replay file contains no frames.")
		return false

	print("[HotzonePlayer] Loaded %d frames" % frames.size())
	_precalculate_chart_data()
	return true

func _precalculate_chart_data():
	_chart_points = PoolVector2Array()
	_chart_colors = PoolColorArray()
	var count = frames.size()
	if count < 2: return

	# Sample every 5 frames as requested
	var step = 5
	for i in range(0, count, step):
		var f = frames[i]
		var fps = f.get("fps", 60.0)
		var x = float(i) / float(max(1, count - 1))
		var y = clamp(fps / 60.0, 0.0, 1.0)
		_chart_points.append(Vector2(x, 1.0 - y))

		if fps > 45: _chart_colors.append(Color(0.3, 1.0, 0.3, 0.5))
		elif fps > 30: _chart_colors.append(Color(1.0, 1.0, 0.3, 0.5))
		else: _chart_colors.append(Color(1.0, 0.3, 0.3, 0.5))

	# Ensure the last frame is included if not already
	var last_idx = count - 1
	if last_idx % step != 0:
		var f = frames[last_idx]
		var fps = f.get("fps", 60.0)
		var x = 1.0
		var y = clamp(fps / 60.0, 0.0, 1.0)
		_chart_points.append(Vector2(x, 1.0 - y))
		if fps > 45: _chart_colors.append(Color(0.3, 1.0, 0.3, 0.5))
		elif fps > 30: _chart_colors.append(Color(1.0, 1.0, 0.3, 0.5))
		else: _chart_colors.append(Color(1.0, 0.3, 0.3, 0.5))

func _show_error(msg: String):
	printerr("[HotzonePlayer] ERROR: ", msg)
	if is_instance_valid(status_label):
		status_label.text = "ERROR: " + msg
		status_label.modulate = Color(1, 0.3, 0.3)

func _prepare_scene():
	# Mark replay mode before the gameplay scene mounts so UI that keys off it
	# (e.g. MobileUIManager hiding touch controls) is correct from the first
	# frame — _start_replay() runs several physics frames later, too late to
	# avoid a flash of on-screen controls.
	if SessionManager:
		SessionManager.is_replaying = true
		# Este reproductor aplica transforms grabados; no hay buffer de inputs que
		# SessionManager pueda reproducir. Ver is_hotzone_playback en SessionManager.
		SessionManager.is_hotzone_playback = true

	var scene_name = scene_override if scene_override != "" else replay_data.get("scene", "")
	var scene_path = _resolve_scene_path(scene_name)
	if scene_path == "":
		_show_error("Unrecognized scene: " + scene_name)
		return

	initial_scene_path = scene_path
	var packed = load(scene_path)
	if not packed or not (packed is PackedScene):
		_show_error("Failed to load scene: " + scene_path)
		return

	loaded_scene_node = packed.instance()
	call_deferred("_attach_loaded_scene")

func _attach_loaded_scene():
	get_tree().root.add_child(loaded_scene_node)
	loaded_scene_node.pause_mode = Node.PAUSE_MODE_STOP
	pause_mode = Node.PAUSE_MODE_PROCESS
	for _i in range(4):
		yield(get_tree(), "physics_frame")
	_start_replay()

func _resolve_scene_path(scene_name: String) -> String:
	var known = {
		"Dome_Crio": "res://core_v2/levels/interiors/Dome_Crio.tscn",
		"Dome_Intro": "res://core_v2/levels/interiors/Dome_Intro.tscn",
		"OdiseaExterior": "res://core_v2/levels/OdiseaExterior.tscn",
		"ScaffoldOrbit": "res://core_v2/components/ScaffoldOrbit.tscn",
		"TestScene_v2": "res://core_v2/levels/TestScene_v2.tscn"
	}
	if known.has(scene_name): return known[scene_name]
	if scene_name.begins_with("res://") and ResourceLoader.exists(scene_name): return scene_name

	# El mapa de arriba quedaba desactualizado en silencio: el grabador captura hotzones de
	# cualquier escena (hay decenas de Dome_Intro en el central) pero el reproductor solo
	# conocia cuatro, y fallaba con "Unrecognized scene". Este fallback resuelve por
	# convencion de ruta, asi que una escena nueva no necesita tocar el mapa.
	for base in ["res://core_v2/levels/interiors/", "res://core_v2/levels/",
			"res://scenes/levels/", "res://core_v2/components/"]:
		var candidate: String = base + scene_name + ".tscn"
		if ResourceLoader.exists(candidate):
			return candidate
	return ""

func _start_replay():
	var pilots = get_tree().get_nodes_in_group("player")
	if pilots.size() > 0: player_node = pilots[0]

	if not is_instance_valid(player_node):
		_show_error("Could not find player node.")
		return

	# Replay Inhibition
	if SessionManager:
		SessionManager.is_replaying = true
		print("[HotzonePlayer] Set SessionManager.is_replaying = true")

	if has_node("/root/HotzoneRecorder"):
		get_node("/root/HotzoneRecorder").hotzone_enabled = false
		print("[HotzonePlayer] Disabled HotzoneRecorder.")

	# Hide the gameplay touch UI: the replay drives the player from the .bin, so
	# on-screen controls must not appear. Direct call (not just is_replaying +
	# per-frame refresh) because the player pauses the tree, which stops
	# MobileUIManager._process.
	if has_node("/root/MobileUIManager"):
		get_node("/root/MobileUIManager").set_replay_mode(true)

	if OS.has_feature("web"):
		var js = JavaScript.get_interface("OdiseaShell")
		if js: js.is_replaying = true

	if "animator" in player_node:
		player_animator = player_node.animator

	var provider = InputProviderV2.new()
	var inputs = []
	for f in frames:
		inputs.append(f.get("input", {}))
	provider.set_replay_data(inputs)
	player_node.input_provider = provider
	player_node.is_replay_mode = true
	player_node.set_physics_process(false)

	_update_ui_metadata()
	_update_ui_frame()
	_restore_frame_state(0)

	if warmup_sec > 0.0:
		_is_warming_up = true
		_warmup_remaining = warmup_sec
		# Direct access to bypass setter (avoids get_tree().paused = true)
		# so the scene can settle/warm up while playback is technically gated.
		is_paused = true
		_set_animator_active(true)
		status_label.text = "Calentando... %.1fs" % _warmup_remaining
		status_label.modulate = Color(1, 1, 0.3)
	else:
		self.is_paused = false

func _update_ui_metadata():
	var trigger = replay_data.get("trigger", "auto")
	var min_fps = 999.0
	var sum_fps = 0.0
	for f in frames:
		var f_fps = f.get("fps", 60.0)
		if f_fps < min_fps: min_fps = f_fps
		sum_fps += f_fps
	var avg_fps = sum_fps / max(1, frames.size())

	metadata_label.text = "Escena: %s | Disparador: %s | FPS mín: %.1f | FPS med: %.1f" % [
		replay_data.get("scene", "Unknown"),
		trigger,
		min_fps,
		avg_fps
	]

	var timestamp = replay_data.get("timestamp", 0)
	var date_str = "unknown"
	if timestamp > 0:
		var dt = OS.get_datetime_from_unix_time(timestamp)
		date_str = "%04d-%02d-%02d %02d:%02d:%02d UTC" % [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]

	var duration = replay_data.get("capture_duration", frames.size() * 0.016)
	var player_id = replay_data.get("player_id", "unknown")
	var build = ProjectSettings.get_setting("application/config/version")
	var platform = OS.get_name()

	metadata_extra_label.text = "Capturado: %s | Duración: %.1fs\nBuild: %s | Plataforma: %s | Tripulante: %s" % [
		date_str, duration, build, platform, player_id
	]

	icon_auto.visible = (trigger == "auto")
	icon_manual.visible = (trigger == "manual")
	fps_chart.update()

func _update_ui_frame():
	# Bottom strip shows, always (playing, paused, scrubbing): the frame index,
	# the original FPS of the frame we're parked on, and the live replay FPS.
	# Keeping these here means the original FPS is never hidden behind transient
	# status messages.
	var src_fps := -1.0
	if current_frame_idx < frames.size():
		src_fps = float(frames[current_frame_idx].get("fps", -1.0))

	var line := "Frame: %d/%d" % [current_frame_idx + 1, frames.size()]
	if src_fps >= 0.0:
		# "Source" = the original recorded FPS of this frame; "Replay" = the FPS
		# the player itself is currently rendering at.
		var replay_fps := Performance.get_monitor(Performance.TIME_FPS)
		_perf_trace.append({
			"frame": current_frame_idx,
			"src_fps": src_fps,
			"replay_fps": replay_fps,
			"ms_process": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"ms_physics": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			"vertices": Performance.get_monitor(Performance.RENDER_VERTICES_IN_FRAME),
			"draw_calls": Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME),
			"memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		})
		line += " | Source FPS: %.1f | Replay FPS: %.1f" % [src_fps, replay_fps]
		frame_label.modulate = _fps_color(src_fps)
	else:
		frame_label.modulate = Color(1, 1, 1)
	frame_label.text = line

	var pct = float(current_frame_idx) / float(max(1, frames.size() - 1))
	progress_fill.rect_size.x = progress_container.rect_size.x * pct

	if current_frame_idx < frames.size():
		var elapsed = current_frame_idx * 0.016 # Default 60fps
		var total_dur = frames.size() * 0.016
		progress_container.hint_tooltip = "Frame %d/%d — T: %.1fs / %.1fs" % [current_frame_idx + 1, frames.size(), elapsed, total_dur]

	fps_chart.update()

# Collapse/expand the bottom overlay (panel, controls, chart, metadata) so the
# replay can be watched unobstructed; the small toggle button stays visible.
func _on_collapse_toggled(pressed: bool) -> void:
	if is_instance_valid(overlay):
		overlay.visible = not pressed
	if is_instance_valid(btn_collapse):
		btn_collapse.text = "▲" if pressed else "▼"

# Green/yellow/red by the same thresholds the chart and recorder use.
func _fps_color(fps: float) -> Color:
	if fps > 45.0: return Color(0.3, 1.0, 0.3)
	elif fps > 30.0: return Color(1.0, 1.0, 0.3)
	return Color(1.0, 0.4, 0.4)

func _process(delta):
	if _is_warming_up:
		_warmup_remaining -= delta
		if _warmup_remaining <= 0.0:
			_is_warming_up = false
			# Re-anclar antes del primer paso: _start_replay() restauro el frame 0, pero
			# durante el calentamiento la escena sigue viva y ese estado queda viejo. Sin
			# esto la reproduccion arranca desde un estado que no es el grabado.
			_restore_frame_state(0)
			self.is_paused = false
		else:
			status_label.text = "Calentando... %.1fs" % _warmup_remaining
		return

	if is_instance_valid(player_node) and not is_paused:
		var frames_to_step = int(playback_speed)
		for _i in range(frames_to_step):
			if current_frame_idx < frames.size() - 1:
				_step_forward()
			else:
				_on_replay_finished()
				break

func _unhandled_input(event):
	if event is InputEventKey and event.pressed:
		if event.scancode == KEY_SPACE:
			self.is_paused = not is_paused
			get_tree().set_input_as_handled()
		elif event.scancode == KEY_RIGHT:
			var step = 1
			if event.control: step = 60 # ~1s
			_seek_relative(step)
			self.is_paused = true
			get_tree().set_input_as_handled()
		elif event.scancode == KEY_LEFT:
			var step = -1
			if event.control: step = -60 # ~1s
			_seek_relative(step)
			self.is_paused = true
			get_tree().set_input_as_handled()
		elif event.scancode == KEY_1: _set_speed(1.0)
		elif event.scancode == KEY_2: _set_speed(2.0)
		elif event.scancode == KEY_4: _set_speed(4.0)
		elif event.scancode == KEY_R:
			restart_replay()
		elif event.scancode == KEY_HOME:
			seek_to_frame(0)
		elif event.scancode == KEY_END:
			seek_to_frame(frames.size() - 1)
		elif event.scancode == KEY_ESCAPE:
			if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			get_tree().set_input_as_handled()

func _seek_relative(delta_frames: int) -> void:
	var target = clamp(current_frame_idx + delta_frames, 0, frames.size() - 1)
	_restore_frame_state(target)
	_update_ui_frame()

func _seek_relative_time(delta_sec: float) -> void:
	var delta_frames = int(delta_sec * 60.0)
	_seek_relative(delta_frames)
	self.is_paused = true

func seek_to_frame(idx: int):
	if idx < 0: idx = frames.size() - 1
	var target = clamp(idx, 0, frames.size() - 1)
	_restore_frame_state(target)
	_update_ui_frame()

func _set_paused(value: bool) -> void:
	is_paused = value
	get_tree().paused = value
	_set_animators_active(not value)
	_set_animator_active(not value)

	if btn_play.pressed != value:
		btn_play.set_pressed_no_signal(value)
	btn_play.text = "RESUME" if value else "PAUSE"

	if value:
		if status_label.text != "REGISTRO COMPLETADO — Pausado":
			status_label.text = "Pausado"
			status_label.modulate = Color(1, 1, 1)
	else:
		status_label.text = "Reproduciendo..."
		status_label.modulate = Color(0.3, 1, 0.3)

func _on_play_toggled(pressed: bool):
	self.is_paused = pressed

func _set_animator_active(active: bool) -> void:
	if player_animator == null or not is_instance_valid(player_animator): return
	if "animation_tree" in player_animator and player_animator.animation_tree:
		player_animator.animation_tree.active = active

func _set_animators_active(active: bool) -> void:
	if not is_instance_valid(loaded_scene_node): return
	_walk_animators(loaded_scene_node, active)

func _walk_animators(node: Node, active: bool) -> void:
	if node is AnimationPlayer: node.playback_active = active
	elif node is AnimationTree: node.active = active
	for child in node.get_children(): _walk_animators(child, active)

func _set_speed(s: float):
	playback_speed = s
	speed_label.text = "Speed: %dx" % int(s)

func _step_forward():
	if current_frame_idx >= frames.size() - 1: return
	current_frame_idx += 1
	var f = frames[current_frame_idx]
	if f.has("snapshot"): player_node.restore_snapshot(f["snapshot"])
	_restore_prop_snapshots(f)
	var input = InputDataV2.new()
	input.from_dict(f.get("input", {}))
	var dt: float = f.get("dt", 0.016)
	player_node.step(dt, input)
	# El mundo tiene que avanzar EN LOCKSTEP con el jugador y con el delta grabado. Si cada
	# nodo avanza por su cuenta en su _physics_process, lo hace al ritmo del dispositivo que
	# reproduce y no al de la grabacion: entre snapshots eso diverge y se ve como drift.
	_step_world(dt)
	_update_ui_frame()

func _restore_frame_state(idx: int):
	current_frame_idx = idx
	var f = frames[idx]
	var snapshot_idx = -1
	for i in range(idx, -1, -1):
		if frames[i].has("snapshot"):
			snapshot_idx = i
			break
	if snapshot_idx != -1:
		player_node.restore_snapshot(frames[snapshot_idx]["snapshot"])
		_restore_prop_snapshots(frames[snapshot_idx])
		player_node.input_provider.playback_index = snapshot_idx
		for i in range(snapshot_idx, idx):
			var step_f = frames[i]
			var input = InputDataV2.new()
			input.from_dict(step_f.get("input", {}))
			player_node.step(step_f.get("dt", 0.016), input)
	else:
		var pos_arr = f.get("pos", [0, 0, 0])
		var t = player_node.global_transform
		t.origin = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
		player_node.global_transform = t
		if "velocity" in player_node: player_node.velocity = Vector3.ZERO
		player_node.input_provider.playback_index = idx

var _prop_node_cache := {}
# Avanza los nodos del grupo replay_sync con el delta grabado. Solo los que exponen
# step(): los que no, dependen de sus snapshots periodicos.
func _step_world(dt: float) -> void:
	for node in get_tree().get_nodes_in_group("replay_sync"):
		if node == player_node or not is_instance_valid(node):
			continue
		if is_instance_valid(player_node) and player_node.is_a_parent_of(node):
			continue
		if node.has_method("step"):
			node.step(dt)


func _restore_prop_snapshots(f: Dictionary) -> void:
	var props = f.get("props", {})
	if props.empty() or not is_instance_valid(loaded_scene_node): return
	for rel_path in props:
		var node = _prop_node_cache.get(rel_path)
		if not is_instance_valid(node):
			node = loaded_scene_node.get_node_or_null(rel_path)
			if node != null: _prop_node_cache[rel_path] = node
		if is_instance_valid(node) and node.has_method("restore_snapshot"):
			node.restore_snapshot(props[rel_path])

func _on_replay_finished():
	self.is_paused = true
	status_label.text = "REGISTRO COMPLETADO — Pausado"
	status_label.modulate = Color(0.3, 1, 1)

# Vuelca la traza a user://replay_perf.json. En Android eso cae en el sandbox de la app,
# recuperable con: adb exec-out run-as org.odisea.game cat files/replay_perf.json
func _dump_perf_trace() -> void:
	if _perf_trace.empty():
		return
	var f := File.new()
	if f.open(PERF_TRACE_PATH, File.WRITE) != OK:
		printerr("[HotzonePlayer] No se pudo escribir ", PERF_TRACE_PATH)
		return
	f.store_string(JSON.print({
		"scene": replay_data.get("scene", ""),
		"frames_reproducidos": _perf_trace.size(),
		"muestras": _perf_trace,
	}))
	f.close()
	print("[HotzonePlayer] Traza de rendimiento escrita: %s (%d muestras)" % [PERF_TRACE_PATH, _perf_trace.size()])


func restart_replay():
	_restore_frame_state(0)
	_update_ui_frame()
	self.is_paused = false

func _exit_tree():
	_dump_perf_trace()
	if SessionManager:
		SessionManager.is_replaying = false
		SessionManager.is_hotzone_playback = false

	if OS.has_feature("web"):
		var js = JavaScript.get_interface("OdiseaShell")
		if js: js.is_replaying = false

	if has_node("/root/HotzoneRecorder"):
		get_node("/root/HotzoneRecorder").hotzone_enabled = true
	if is_instance_valid(loaded_scene_node):
		loaded_scene_node.queue_free()

func _on_progress_gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == BUTTON_LEFT:
			if event.pressed:
				_is_scrubbing = true
				_seek_to_mouse_pos(event.position.x)
			else:
				_is_scrubbing = false
	elif event is InputEventMouseMotion:
		if _is_scrubbing:
			_seek_to_mouse_pos(event.position.x)
		_update_hover_tooltip(event.position.x)

func _seek_to_mouse_pos(x_pos):
	var w = progress_container.rect_size.x
	var pct = clamp(x_pos / w, 0.0, 1.0)
	var target_frame = int(round(pct * (frames.size() - 1)))
	seek_to_frame(target_frame)
	self.is_paused = true

func _update_hover_tooltip(x_pos):
	var w = progress_container.rect_size.x
	var pct = clamp(x_pos / w, 0.0, 1.0)
	var frame_idx = int(round(pct * (frames.size() - 1)))
	if frame_idx < 0 or frame_idx >= frames.size(): return

	var f = frames[frame_idx]
	var elapsed = frame_idx * 0.016
	var fps = f.get("fps", 0.0)
	var msg = "Frame %d/%d — T: %.1fs — FPS: %.1f" % [frame_idx + 1, frames.size(), elapsed, fps]
	progress_container.hint_tooltip = msg
	fps_chart.hint_tooltip = msg

func _on_fps_chart_draw():
	if _chart_points.empty(): return
	var rect = fps_chart.rect_size
	var count = _chart_points.size()
	var font = fps_chart.get_font("font")

	# Reference gridlines so the curve is readable: the chart maps y = fps/60,
	# drawn top-down, so a line at F fps sits at (1 - F/60) * height.
	for ref_fps in [60, 45, 30]:
		var gy = (1.0 - float(ref_fps) / 60.0) * rect.y
		fps_chart.draw_line(Vector2(0, gy), Vector2(rect.x, gy), Color(1, 1, 1, 0.12), 1.0)
		if font:
			fps_chart.draw_string(font, Vector2(2, max(8, gy - 2)), "%d" % ref_fps, Color(1, 1, 1, 0.4))

	for i in range(count - 1):
		var p1 = _chart_points[i] * rect
		var p2 = _chart_points[i+1] * rect
		fps_chart.draw_line(p1, p2, _chart_colors[i], 2.0, true)

	# Current position marker + the original FPS value at that frame.
	var cur_x = float(current_frame_idx) / float(max(1, frames.size() - 1)) * rect.x
	fps_chart.draw_line(Vector2(cur_x, 0), Vector2(cur_x, rect.y), Color(1, 1, 1, 0.8), 2.0)
	if font and current_frame_idx < frames.size():
		var cur_fps = float(frames[current_frame_idx].get("fps", -1.0))
		if cur_fps >= 0.0:
			var cur_y = (1.0 - clamp(cur_fps / 60.0, 0.0, 1.0)) * rect.y
			fps_chart.draw_circle(Vector2(cur_x, cur_y), 3.0, _fps_color(cur_fps))
			# Keep the label on-screen near the right edge.
			var label = "%.0f fps" % cur_fps
			var lx = cur_x + 4
			if lx > rect.x - 48: lx = cur_x - 48
			fps_chart.draw_string(font, Vector2(lx, max(10, cur_y - 4)), label, _fps_color(cur_fps))
