extends Control

# HotzonePlayer.gd
# Tool scene for playing back binary hotzone captures.

const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")
const InputProviderV2 = preload("res://core_v2/input/InputProviderV2.gd")
const BINARY_MAGIC := 0x485a4e32 # "HZN2"

onready var status_label = $Overlay/Status
onready var metadata_label = $Overlay/Metadata
onready var progress_bar = $Overlay/ProgressBar
onready var frame_label = $Overlay/FrameInfo
onready var speed_label = $Overlay/SpeedInfo
onready var icon_auto = $Overlay/IconAuto
onready var icon_manual = $Overlay/IconManual

var replay_data := {}
var frames := []
var current_frame_idx := 0
var playback_speed := 1.0
var is_paused := true setget _set_paused
var player_node = null
var player_animator = null
# Let the scene settle (physics/animation tree warm up, first frames render)
# before we start stepping inputs, so the measured replay isn't penalised by
# load-tail jank. Configurable via --replay-warmup <seconds>.
var warmup_sec := 1.5
var _warmup_remaining := 0.0
var _is_warming_up := false
var initial_scene_path := ""
var loaded_scene_node = null
var scene_override := ""

func _ready():
	# Parse command line: --replay-file (required), --replay-scene (override the
	# scene baked in the .bin), --replay-speed (initial 1/2/4x playback speed).
	var replay_path = ""

	if OS.has_feature("web"):
		var js = JavaScript.get_interface("OdiseaShell")
		if js != null and js.pendingRunbin != null:
			print("[HotzonePlayer] Binary data found in OdiseaShell.pendingRunbin")
			# The shell hands us the .bin as a base64 string: Godot 3's JS bridge
			# can't marshal an ArrayBuffer into a PoolByteArray, so we decode here.
			var b64 = String(js.pendingRunbin)
			var buf = Marshalls.base64_to_raw(b64)
			js.pendingRunbin = null

			if buf.size() == 0:
				printerr("[HotzonePlayer] Decoded remote binary is empty (bad base64?)")
			else:
				var dir = Directory.new()
				if not dir.dir_exists("user://hotzones"):
					dir.make_dir_recursive("user://hotzones")

				var f = File.new()
				if f.open("user://hotzones/remote.bin", File.WRITE) == OK:
					f.store_buffer(buf)
					f.close()
					replay_path = "user://hotzones/remote.bin"
					print("[HotzonePlayer] Persisted %d bytes to user://hotzones/remote.bin" % buf.size())
				else:
					printerr("[HotzonePlayer] Failed to write remote binary to user://hotzones/remote.bin")

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

	if replay_path == "":
		_show_error("No replay file specified. Use --replay-file <path>")
		return

	if not _load_binary(replay_path):
		return

	_prepare_scene()

func _load_binary(path: String) -> bool:
	var f = File.new()
	if f.open(path, File.READ) != OK:
		_show_error("Could not open file: " + path)
		return false

	var magic = f.get_32()
	if magic != BINARY_MAGIC:
		_show_error("Invalid file magic. Expected HZN2 (0x485a4e32)")
		f.close()
		return false

	var data_blob = f.get_buffer(f.get_len() - 4)
	f.close()

	var data = bytes2var(data_blob)
	if typeof(data) != TYPE_DICTIONARY:
		_show_error("Failed to parse replay data from binary.")
		return false

	replay_data = data
	frames = data.get("frames", [])

	if frames.empty():
		_show_error("Replay file contains no frames.")
		return false

	print("[HotzonePlayer] Loaded %d frames for scene %s" % [frames.size(), replay_data.get("scene")])
	return true

func _show_error(msg: String):
	printerr("[HotzonePlayer] ERROR: ", msg)
	if has_node("Overlay/Status"):
		status_label.text = "ERROR: " + msg
		status_label.modulate = Color(1, 0.3, 0.3)

func _prepare_scene():
	# --replay-scene lets us test a hotzone captured in scene X against scene Y.
	var scene_name = scene_override if scene_override != "" else replay_data.get("scene", "")
	if scene_override != "":
		print("[HotzonePlayer] Overriding captured scene with: ", scene_override)
	var scene_path = _resolve_scene_path(scene_name)
	if scene_path == "":
		_show_error("Unrecognized scene: " + scene_name)
		return

	initial_scene_path = scene_path
	print("[HotzonePlayer] Loading scene: ", scene_path)

	var packed = load(scene_path)
	if not packed or not (packed is PackedScene):
		_show_error("Failed to load scene: " + scene_path)
		return

	loaded_scene_node = packed.instance()
	call_deferred("_attach_loaded_scene")

func _attach_loaded_scene():
	get_tree().root.add_child(loaded_scene_node)
	# When playback pauses we flip get_tree().paused, which stops all physics and
	# _process across the loaded scene. The scene must STOP under that flag while
	# this player keeps PROCESSing so its UI and unpause/seek input stay alive.
	loaded_scene_node.pause_mode = Node.PAUSE_MODE_STOP
	pause_mode = Node.PAUSE_MODE_PROCESS
	# Let the scene's own startup run (player _ready, TeleportSystem.force_initial_spawn,
	# deferred spawn placement) before we take over, otherwise those would overwrite
	# the captured position right after we restore it.
	for _i in range(4):
		yield(get_tree(), "physics_frame")
	_start_replay()

func _resolve_scene_path(scene_name: String) -> String:
	var known = {
		"Dome_Crio": "res://core_v2/levels/interiors/Dome_Crio.tscn",
		"OdiseaExterior": "res://core_v2/levels/OdiseaExterior.tscn",
		"ScaffoldOrbit": "res://core_v2/components/ScaffoldOrbit.tscn",
		"TestScene_v2": "res://core_v2/levels/TestScene_v2.tscn"
	}
	if known.has(scene_name):
		return known[scene_name]
	if scene_name.begins_with("res://") and ResourceLoader.exists(scene_name):
		return scene_name
	if scene_name.find("/") != -1 or scene_name.ends_with(".tscn"):
		return scene_name if ResourceLoader.exists(scene_name) else ""
	return ""

func _start_replay():
	# Find player
	var pilots = get_tree().get_nodes_in_group("player")
	if pilots.size() > 0:
		player_node = pilots[0]

	if not is_instance_valid(player_node):
		_show_error("Could not find player node in scene.")
		return

	print("[HotzonePlayer] Player found. Initializing replay provider.")

	# Silence the global HotzoneRecorder autoload for the whole replay session. The
	# loaded scene drives the same low-FPS conditions that produced this capture, so a
	# live recorder would detect the playback as a fresh hotzone and record/upload it
	# — replaying a hotzone must never spawn another. (The recorder's own
	# SessionManager.is_replaying guard doesn't cover this tool, which steps the player
	# directly instead of going through SessionManager.)
	if has_node("/root/HotzoneRecorder"):
		get_node("/root/HotzoneRecorder").hotzone_enabled = false
		print("[HotzonePlayer] Disabled HotzoneRecorder for replay session.")

	# Cache the player's animator so we can freeze it whenever playback pauses.
	if "animator" in player_node:
		player_animator = player_node.animator

	# Setup InputProvider
	if not ("input_provider" in player_node):
		_show_error("Player node lacks input_provider.")
		return

	var provider = InputProviderV2.new()
	var inputs = []
	for f in frames:
		inputs.append(f.get("input", {}))
	provider.set_replay_data(inputs)
	player_node.input_provider = provider
	player_node.is_replay_mode = true
	player_node.set_physics_process(false) # We will step manually

	# Update HUD
	_set_speed(playback_speed)
	_update_ui_metadata()
	_update_ui_frame()

	# Initial positioning
	_restore_frame_state(0)

	# Warm up before stepping inputs so the replay is judged on steady-state perf.
	if warmup_sec > 0.0:
		_is_warming_up = true
		_warmup_remaining = warmup_sec
		# Plain (self-access) assignment intentionally bypasses the setget: we want
		# the playback gate up WITHOUT freezing the tree, so the scene keeps settling
		# (physics/animators run) during warmup. The setter (get_tree().paused) only
		# fires on real user pauses via self.is_paused.
		is_paused = true
		_set_animator_active(true)
		status_label.text = "Calentando... %.1fs" % _warmup_remaining
		status_label.modulate = Color(1, 1, 0.3)
	else:
		is_paused = false
		status_label.text = "Reproduciendo..."
		status_label.modulate = Color(0.3, 1, 0.3)

func _update_ui_metadata():
	var trigger = replay_data.get("trigger", "auto")
	var min_fps = 999.0
	for f in frames:
		var f_fps = f.get("fps", 60.0)
		if f_fps < min_fps: min_fps = f_fps

	metadata_label.text = "Scene: %s | Trigger: %s | Min FPS: %.1f" % [
		replay_data.get("scene", "Unknown"),
		trigger,
		min_fps
	]

	icon_auto.visible = (trigger == "auto")
	icon_manual.visible = (trigger == "manual")

func _update_ui_frame():
	frame_label.text = "Frame: %d/%d" % [current_frame_idx + 1, frames.size()]
	progress_bar.value = float(current_frame_idx + 1) / float(frames.size()) * 100.0

	if current_frame_idx < frames.size():
		var f = frames[current_frame_idx]
		var actual_fps = Performance.get_monitor(Performance.TIME_FPS)
		status_label.text = "Replay FPS: %.1f | Source FPS: %.1f" % [actual_fps, f.get("fps", 0.0)]

func _process(delta):
	if _is_warming_up:
		_warmup_remaining -= delta
		if _warmup_remaining <= 0.0:
			_is_warming_up = false
			is_paused = false
			status_label.text = "Reproduciendo..."
			status_label.modulate = Color(0.3, 1, 0.3)
		else:
			status_label.text = "Calentando... %.1fs" % _warmup_remaining
		return

	if is_instance_valid(player_node) and not is_paused:
		# Handle speed-scaled playback
		var frames_to_step = int(playback_speed)
		if playback_speed < 1.0:
			# TODO: Slow motion interpolation? For now just skip frames
			pass

		for _i in range(frames_to_step):
			if current_frame_idx < frames.size():
				_step_forward()
			else:
				_on_replay_finished()
				break

func _unhandled_input(event):
	if event.is_action_pressed("ui_accept"): # Space
		# Use self. so the setget setter fires (plain assignment self-access skips it).
		self.is_paused = not is_paused
		status_label.text = "Pausado" if is_paused else "Reproduciendo..."
	elif event.is_action_pressed("ui_right"): # Right Arrow
		_seek_relative(_seek_step_for(event))
		self.is_paused = true
	elif event.is_action_pressed("ui_left"): # Left Arrow
		_seek_relative(-_seek_step_for(event))
		self.is_paused = true
	elif event is InputEventKey and event.pressed:
		if event.scancode == KEY_1: _set_speed(1.0)
		elif event.scancode == KEY_2: _set_speed(2.0)
		elif event.scancode == KEY_4: _set_speed(4.0)
		elif event.scancode == KEY_ESCAPE:
			get_tree().quit() # or return to menu

# Arrow = 1 frame, Ctrl+Arrow = 10, Ctrl+Shift+Arrow = 30.
func _seek_step_for(event) -> int:
	if event is InputEventWithModifiers and event.control:
		return 30 if event.shift else 10
	return 1

func _seek_relative(delta_frames: int) -> void:
	var target = clamp(current_frame_idx + delta_frames, 0, frames.size() - 1)
	# _restore_frame_state replays from the nearest snapshot, so it handles both
	# forward and backward jumps correctly regardless of magnitude.
	_restore_frame_state(target)
	_update_ui_frame()

func _set_paused(value: bool) -> void:
	is_paused = value
	# Freeze the whole loaded scene when playback halts: get_tree().paused stops all
	# physics and _process (the scene is PAUSE_MODE_STOP). The player itself isn't
	# physics-processed by the engine here, so we still step it manually on seek.
	get_tree().paused = value
	# Animators are frozen separately: AnimationPlayer/AnimationTree nodes left at
	# PAUSE_MODE_PROCESS would keep advancing through the tree pause, so a paused
	# frame isn't a true still otherwise.
	_set_animators_active(not value)
	_set_animator_active(not value)

func _set_animator_active(active: bool) -> void:
	if player_animator == null or not is_instance_valid(player_animator):
		return
	if "animation_tree" in player_animator and player_animator.animation_tree:
		player_animator.animation_tree.active = active

# Walk the loaded scene and freeze/unfreeze every AnimationPlayer and AnimationTree,
# so pausing yields a real still frame regardless of each animator's pause_mode.
func _set_animators_active(active: bool) -> void:
	if not is_instance_valid(loaded_scene_node):
		return
	_walk_animators(loaded_scene_node, active)

func _walk_animators(node: Node, active: bool) -> void:
	if node is AnimationPlayer:
		node.playback_active = active
	elif node is AnimationTree:
		node.active = active
	for child in node.get_children():
		_walk_animators(child, active)

func _set_speed(s: float):
	playback_speed = s
	speed_label.text = "Speed: %dx" % int(s)

func _step_forward():
	if current_frame_idx >= frames.size() - 1:
		return

	current_frame_idx += 1
	var f = frames[current_frame_idx]

	# Restore snapshot if present
	if f.has("snapshot"):
		player_node.restore_snapshot(f["snapshot"])
	_restore_prop_snapshots(f)

	var input = InputDataV2.new()
	input.from_dict(f.get("input", {}))

	# Step the player
	if SessionManager and SessionManager.has_method("is_recording"):
		# If SessionManager exists, use its synchronized stepping if possible
		# but for hotzone playback we usually want direct control.
		player_node.step(f.get("dt", 0.016), input)
	else:
		player_node.step(f.get("dt", 0.016), input)

	_update_ui_frame()

func _step_backward():
	if current_frame_idx <= 0:
		return

	current_frame_idx -= 1
	# Re-seek to current_frame_idx
	_restore_frame_state(current_frame_idx)
	_update_ui_frame()

func _restore_frame_state(idx: int):
	current_frame_idx = idx
	var f = frames[idx]

	# We must find the nearest snapshot BEFORE or AT idx to restore state
	var snapshot_idx = -1
	for i in range(idx, -1, -1):
		if frames[i].has("snapshot"):
			snapshot_idx = i
			break

	if snapshot_idx != -1:
		player_node.restore_snapshot(frames[snapshot_idx]["snapshot"])
		_restore_prop_snapshots(frames[snapshot_idx])
		# Play back inputs from snapshot_idx to current_frame_idx
		player_node.input_provider.playback_index = snapshot_idx
		for i in range(snapshot_idx, idx):
			var step_f = frames[i]
			var input = InputDataV2.new()
			input.from_dict(step_f.get("input", {}))
			player_node.step(step_f.get("dt", 0.016), input)
	else:
		# Fallback: just teleport to pos
		var pos_arr = f.get("pos", [0, 0, 0])
		var t = player_node.global_transform
		t.origin = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
		player_node.global_transform = t
		if "velocity" in player_node: player_node.velocity = Vector3.ZERO
		player_node.input_provider.playback_index = idx

var _prop_node_cache := {}
func _restore_prop_snapshots(f: Dictionary) -> void:
	# Mirror of the recorder's _capture_prop_snapshots: each entry is keyed by the
	# node's path relative to the scene root. Resolve against loaded_scene_node and
	# call restore_snapshot so seeking rewinds the whole world, not just the player.
	var props = f.get("props", {})
	if props.empty() or not is_instance_valid(loaded_scene_node):
		return
	for rel_path in props:
		var node = _prop_node_cache.get(rel_path)
		if not is_instance_valid(node):
			node = loaded_scene_node.get_node_or_null(rel_path)
			if node != null:
				_prop_node_cache[rel_path] = node
		if is_instance_valid(node) and node.has_method("restore_snapshot"):
			node.restore_snapshot(props[rel_path])

func _on_replay_finished():
	# Loop: rewind to the start and keep playing so the hotzone repeats.
	print("[HotzonePlayer] Replay finished, looping.")
	_restore_frame_state(0)
	_update_ui_frame()

func _exit_tree():
	# Restore the recorder we silenced in _start_replay, in case this tool ever runs
	# inside a longer-lived session rather than its own throwaway process.
	if has_node("/root/HotzoneRecorder"):
		get_node("/root/HotzoneRecorder").hotzone_enabled = true
	if is_instance_valid(loaded_scene_node):
		loaded_scene_node.queue_free()
