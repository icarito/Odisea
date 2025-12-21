extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

var runner: GdUnitSceneRunner
var replay_manager: Node
var replay_playback: Node
var scene: Node

func before_each():
	runner = scene_runner("res://tests/fixtures/TestScene.tscn")
	replay_playback = Node.new()
	replay_playback.set_script(preload("res://scripts/replay/ReplayPlayback.gd"))
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
	
	replay_playback.load_replay(replay_path)
	assert_that(replay_playback.current_replay).is_not_null()
	
	replay_playback.start_playback()
	assert_that(replay_playback.playback_status).is_equal("Playing")
	
	# Simulate some frames
	for i in range(10):
		runner.simulate_frames(1)
	
	# Test stop
	replay_playback.stop_playback()
	assert_that(replay_playback.playback_status).is_equal("Stopped")
	
	# Test step forward
	replay_playback.step_forward()
	assert_that(replay_playback.current_frame).is_greater(0)
	
	# Test step back
	replay_playback.step_back()
	assert_that(replay_playback.current_frame).is_equal(0)
	
	# Test seek
	replay_playback.seek_to_frame(5)
	assert_that(replay_playback.current_frame).is_equal(5)
