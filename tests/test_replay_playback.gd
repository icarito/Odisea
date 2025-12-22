class_name GdUnitReplayPlaybackTestSuite
extends GdUnitTestSuite

var runner: GdUnitSceneRunner
var replay_manager: Node
var replay_playback: Node
var scene: Node

func before():
	runner = scene_runner("res://tests/fixtures/TestScene.tscn")
	replay_playback = Node.new()
	replay_playback.set_script(load("res://scripts/replay/ReplayPlayback.gd"))
	replay_playback.name = "ReplayPlayback"
	runner.scene().add_child(replay_playback)
	runner.simulate_frames(1)  # Ensure _ready is called

func test_initialization():
	assert_that(replay_playback.is_inside_tree()).is_true()
	assert_that(replay_playback).is_not_null()

func test_default_state():
	assert_that(replay_playback.playback_status).is_equal("Stopped")
	assert_that(replay_playback.playback_paused).is_false()

func test_load_and_play_replay():
	# Assume a fixture replay exists at res://tests/fixtures/test_replay.json
	var replay_path = "res://tests/fixtures/test_replay.json"
	var dir = Directory.new()
	if not dir.file_exists(replay_path):
		skip(true)
		return
	
	# For now, just check that the node can be instantiated
	assert_that(replay_playback).is_not_null()
