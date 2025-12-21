extends Node

signal mode_changed(new_mode)
signal recording_stopped(frame_count)
signal replay_failed

const ReplayRecorderScript = preload("res://scripts/replay/ReplayRecorder.gd")
const ReplayPlaybackScript = preload("res://scripts/replay/ReplayPlayback.gd")
const ReplayScript = preload("res://scripts/replay/Replay.gd")


enum ReplayMode {
	NONE,
	RECORDING,
	PLAYBACK,
	STOPPED
}

enum CameraMode { FOLLOW_REPLAY, FREE_LOOK }

var mode: int = ReplayMode.NONE
var current_camera_mode = CameraMode.FOLLOW_REPLAY
var recorder: Node = null
var playback: Node = null

var _saved_player_transform: Transform = Transform.IDENTITY
var _saved_player_velocity: Vector3 = Vector3.ZERO
var player_state_saved: bool = false
var last_replay_path: String = ""

const REPLAYS_DIR = "user://replays/"

func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	print("ReplayManager _ready called")

	recorder = ReplayRecorderScript.new()
	recorder.name = "ReplayRecorder"
	add_child(recorder)
	recorder.connect("recording_stopped", self, "_on_recording_stopped")

	playback = ReplayPlaybackScript.new()
	playback.name = "ReplayPlayback"
	add_child(playback)
	playback.connect("playback_stopped", self, "_on_playback_stopped")
	playback.connect("playback_failed", self, "_on_playback_failed")


func get_available_replays() -> Array:
	var dir = Directory.new()
	var replays = []
	if dir.open(REPLAYS_DIR) == OK:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".json"):
				replays.append(file_name)
			file_name = dir.get_next()
	return replays

func _unhandled_input(event):
	if mode == ReplayMode.PLAYBACK and event.is_action_pressed("ui_focus_next"): # Using 'ui_focus_next' which is TAB by default, can be changed to a dedicated action
		if current_camera_mode == CameraMode.FOLLOW_REPLAY:
			current_camera_mode = CameraMode.FREE_LOOK
			print("Camera mode: FREE LOOK")
		else:
			current_camera_mode = CameraMode.FOLLOW_REPLAY
			print("Camera mode: FOLLOW REPLAY")
		get_tree().set_input_as_handled()
		
	if mode == ReplayMode.STOPPED and event.is_action_pressed("ui_cancel"):
		eject_playback()
		get_tree().set_input_as_handled()

func reset_replay() -> void:
	eject_playback()

func eject_playback() -> void:
	var previous_mode = mode
	mode = ReplayMode.NONE # Set mode to NONE first to avoid _on_playback_stopped logic
	
	if previous_mode == ReplayMode.PLAYBACK:
		playback.stop_playback()

	restore_player_state()
	GameGlobals.is_replaying = false
	MouseCapture.set_capture(false)
	emit_signal("mode_changed", ReplayMode.NONE)

# Recording API
func start_recording() -> void:
	if mode != ReplayMode.NONE:
		return
	mode = ReplayMode.RECORDING
	emit_signal("mode_changed", mode)
	recorder.start_recording()


func stop_recording() -> String:
	if mode != ReplayMode.RECORDING:
		return ""
	recorder.stop_recording()
	return last_replay_path

# Playback API
func start_playback(replay_path: String, is_headless: bool = false) -> void:
	if mode != ReplayMode.NONE:
		return

	save_player_state()

	var replay_resource = ReplayScript.new()
	if replay_resource.load_from_json(replay_path) != OK:
		print("Failed to load replay: " + replay_path)
		return

	GameGlobals.is_replaying = true

	if get_tree().current_scene.filename != replay_resource.scene_path:
		get_tree().change_scene(replay_resource.scene_path)
		yield(get_tree(), "idle_frame")
	
	MouseCapture.set_capture(true)
	mode = ReplayMode.PLAYBACK
	emit_signal("mode_changed", mode)
	playback.start_playback(replay_path, is_headless)

func stop_playback() -> void:
	if mode != ReplayMode.PLAYBACK:
		return
	playback.stop_playback()
	# The playback node will emit a signal when it's done, see _on_playback_stopped

func get_playback_node():
	return playback

# Player state management
func save_player_state() -> void:
	var player = PlayerManager.get_player()
	if player and player is KinematicBody:
		_saved_player_transform = player.global_transform
		if player.has_method("get_horizontal_velocity"):
			_saved_player_velocity = player.get_horizontal_velocity()
		player_state_saved = true

func restore_player_state() -> void:
	if not player_state_saved:
		return
	var player = PlayerManager.get_player()
	if player and player is KinematicBody:
		player.global_transform = _saved_player_transform
		if player.has_method("set_horizontal_velocity"):
			player.set_horizontal_velocity(_saved_player_velocity)
	player_state_saved = false


# Signal Handlers
func _on_recording_stopped(frame_count, _replay_path):
	mode = ReplayMode.NONE
	last_replay_path = _replay_path
	MouseCapture.set_capture(false)
	emit_signal("mode_changed", mode)
	emit_signal("recording_stopped", frame_count)

func _on_playback_stopped():
	if mode == ReplayMode.PLAYBACK:
		mode = ReplayMode.STOPPED
		GameGlobals.is_replaying = false
		emit_signal("mode_changed", mode)

func _on_playback_failed():
	emit_signal("replay_failed")
	mode = ReplayMode.NONE
	MouseCapture.set_capture(false)
	emit_signal("mode_changed", mode)
