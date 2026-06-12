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
var is_paused := true
var player_node = null
var initial_scene_path := ""

func _ready():
	# Get replay file from command line
	var replay_path = ""
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--replay-file" and i + 1 < args.size():
			replay_path = args[i + 1]
			break

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
	var scene_name = replay_data.get("scene", "")
	var scene_path = ""

	match scene_name:
		"Dome_Crio": scene_path = "res://core_v2/levels/Dome_Crio.tscn"
		"OdiseaExterior": scene_path = "res://core_v2/levels/OdiseaExterior.tscn"
		"ScaffoldOrbit": scene_path = "res://core_v2/levels/ScaffoldOrbit.tscn"
		_:
			if scene_name.find("/") != -1 or scene_name.ends_with(".tscn"):
				scene_path = scene_name
			else:
				_show_error("Unrecognized scene: " + scene_name)
				# TODO: Allow user to select scene?
				return

	initial_scene_path = scene_path
	print("[HotzonePlayer] Switching to scene: ", scene_path)

	# Load scene
	var err = get_tree().change_scene(scene_path)
	if err != OK:
		_show_error("Failed to load scene: " + scene_path)
		return

	# Wait for scene to be ready
	call_deferred("_start_replay")

func _start_replay():
	# Find player
	var pilots = get_tree().get_nodes_in_group("player")
	if pilots.size() > 0:
		player_node = pilots[0]

	if not is_instance_valid(player_node):
		_show_error("Could not find player node in scene.")
		return

	print("[HotzonePlayer] Player found. Initializing replay provider.")

	# Setup InputProvider
	if not "input_provider" in player_node:
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
	_update_ui_metadata()
	_update_ui_frame()

	# Initial positioning
	_restore_frame_state(0)

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
		is_paused = !is_paused
		status_label.text = "Pausado" if is_paused else "Reproduciendo..."
	elif event.is_action_pressed("ui_right"): # Right Arrow
		_step_forward()
		is_paused = true
	elif event.is_action_pressed("ui_left"): # Left Arrow
		_step_backward()
		is_paused = true
	elif event is InputEventKey and event.pressed:
		if event.scancode == KEY_1: _set_speed(1.0)
		elif event.scancode == KEY_2: _set_speed(2.0)
		elif event.scancode == KEY_4: _set_speed(4.0)
		elif event.scancode == KEY_ESCAPE:
			get_tree().quit() # or return to menu

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

func _on_replay_finished():
	is_paused = true
	status_label.text = "Replay completo"
	status_label.modulate = Color(1, 1, 0.3)
