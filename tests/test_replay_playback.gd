extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

var ReplayPlayback

func before_each():
	ReplayPlayback = preload("res://scripts/replay/ReplayPlayback.gd").new()
	add_child(ReplayPlayback)

func test_initialization():
	assert_that(ReplayPlayback.is_inside_tree()).is_true()
	assert_that(ReplayPlayback).is_not_null()

func test_default_state():
	assert_that(ReplayPlayback.playback_status).is_equal("Stopped")
	assert_that(ReplayPlayback.playback_paused).is_false()

# Puedes agregar más tests específicos según la lógica de ReplayPlayback aquí.
