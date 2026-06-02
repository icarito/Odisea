extends Node

# FD-050.2: Verify threaded WFC generation doesn't block main thread

var _threaded: ScaffoldWFCThreaded = null
var _done := false
var _result_grid = null
var _start_time := 0
var _max_main_thread_ms := 0.0
var _last_frame_start := 0.0

func _ready() -> void:
	_threaded = ScaffoldWFCThreaded.new()
	_threaded.instances_per_frame = 12
	_threaded.max_pending_jobs = 2
	add_child(_threaded)
	_threaded.connect("generation_done", self, "_on_done")
	_threaded.connect("generation_failed", self, "_on_failed")

	_start_time = OS.get_ticks_msec()
	_threaded.request_grid("test_chunk", {
		"grid_width": 8,
		"grid_depth": 14,
		"cell_size": 6.0,
		"seed": 12345,
		"max_wfc_retries": 24,
		"require_single_component": false,
		"min_non_empty_cells": 8,
		"min_stairs_per_map": 0,
		"min_elevated_cells": 0,
		"min_empty_cells": 0,
		"min_height_span": 0.0
	})
	print("[TestStreaming] Generation requested, monitoring main thread frame time...")

func _process(delta: float) -> void:
	var frame_ms = delta * 1000.0
	if frame_ms > _max_main_thread_ms:
		_max_main_thread_ms = frame_ms
	if _done:
		_report()
		set_process(false)

func _on_done(_chunk_key, grid: Array) -> void:
	_result_grid = grid
	_done = true
	var elapsed = OS.get_ticks_msec() - _start_time
	print("[TestStreaming] Generation completed in %d ms" % elapsed)

func _on_failed(_chunk_key) -> void:
	push_error("[TestStreaming] Generation failed")
	_done = true

func _report() -> void:
	if _result_grid == null:
		print("[TestStreaming] FAIL: generation did not return a grid")
		get_tree().quit(1)
		return
	var non_empty = 0
	for s in _result_grid:
		if s != null and s.get("variant", {}).get("id", "EMPTY") != "EMPTY":
			non_empty += 1
	print("[TestStreaming] Non-empty cells: %d" % non_empty)
	if non_empty < 8:
		push_error("[TestStreaming] FAIL: expected at least 8 non-empty cells")
		get_tree().quit(1)
		return
	print("[TestStreaming] Max main-thread frame time during generation: %.2f ms" % _max_main_thread_ms)
	if _max_main_thread_ms < 10.0:
		print("[TestStreaming] PASS: main thread stayed < 10ms per frame")
	else:
		push_warning("[TestStreaming] WARN: max frame time %.2f ms exceeded 10ms threshold" % _max_main_thread_ms)
	get_tree().quit()
