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
	PLAYBACK
}

var mode: int = ReplayMode.NONE
var recorder: Node = null
var playback: Node = null

var _saved_player_transform: Transform = Transform.IDENTITY
var _saved_player_velocity: Vector3 = Vector3.ZERO
var player_state_saved: bool = false

const REPLAYS_DIR = "res://replays/"

func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS

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

func reset_replay() -> void:
	if mode == ReplayMode.PLAYBACK:
		stop_playback()
	
	mode = ReplayMode.NONE
	emit_signal("mode_changed", mode)

# Recording API
func start_recording() -> void:
	if mode != ReplayMode.NONE:
		return
	mode = ReplayMode.RECORDING
	emit_signal("mode_changed", mode)
	# Yield to the recorder's start_recording function, which is a coroutine.
	# This ensures we wait for the 'idle_frame' yield within it to complete,
	# guaranteeing all Autoloads are ready before proceeding.
	yield(recorder.start_recording(), "completed")
	MouseCapture.capture_mouse(true)


func stop_recording() -> void:
	if mode != ReplayMode.RECORDING:
		return
	recorder.stop_recording()

# Playback API
func start_playback(replay_path: String, is_headless: bool = false) -> void:
	if mode != ReplayMode.NONE:
		return

	save_player_state()

	var replay_resource = ReplayScript.new()
	if replay_resource.load_from_json(replay_path) != OK:
		print("Failed to load replay: " + replay_path)
		return

	# Change scene and then start playback
	get_tree().change_scene(replay_resource.scene_path)
	yield(get_tree(), "idle_frame")
	
	mode = ReplayMode.PLAYBACK
	emit_signal("mode_changed", mode)
	playback.start_playback(replay_path, is_headless)

func stop_playback() -> void:
	if mode != ReplayMode.PLAYBACK:
		return
	playback.stop_playback()
	restore_player_state()
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
	MouseCapture.capture_mouse(false)
	emit_signal("mode_changed", mode)
	emit_signal("recording_stopped", frame_count)

func _on_playback_stopped():
	mode = ReplayMode.NONE
	emit_signal("mode_changed", mode)

func _on_playback_failed():
	emit_signal("replay_failed")
	mode = ReplayMode.NONE
	emit_signal("mode_changed", mode)
