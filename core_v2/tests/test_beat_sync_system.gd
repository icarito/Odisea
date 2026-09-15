extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

const AudioManagerScript = preload("res://core_v2/autoloads/AudioManager.gd")
const BeatSyncTriggerScript = preload("res://core_v2/components/BeatSyncTrigger.gd")

var _received_beats = []
var _received_measures = []

func _on_test_beat(n):
	_received_beats.append(n)

func _on_test_measure(m):
	_received_measures.append(m)

func test_beat_tracking_logic():
	var am = AudioManagerScript.new()
	am.bpm = 120.0
	am.time_signature = 4
	am.beat_offset = 0.0
	
	var mock_player = AudioStreamPlayer.new()
	am.add_child(mock_player)
	am.set("_active_player", mock_player)
	
	am.connect("beat", self, "_on_test_beat")
	am.connect("measure", self, "_on_test_measure")
	
	_received_beats = []
	_received_measures = []
	
	# Simulate 0.0s -> beat 0
	# Implementation now initializes and emits the current beat.
	_simulate_track(am, mock_player, 0.0)
	assert_array(_received_beats).contains_exactly([0])
	assert_array(_received_measures).contains_exactly([0])
	
	# Simulate 0.6s -> (0.6 * 120/60) = 1.2 beats
	# Should emit beat 1 (crossing from 0.0 to 1.2)
	_simulate_track(am, mock_player, 0.6)
	assert_array(_received_beats).contains_exactly([1])
	
	_received_beats = []
	_received_measures = []
	# Simulate 1.1s -> 2.2 beats
	# Should emit beat 2
	_simulate_track(am, mock_player, 1.1)
	assert_array(_received_beats).contains_exactly([2])
	
	_received_beats = []
	_received_measures = []
	# Simulate 2.1s -> 4.2 beats
	# Should emit beat 3 and 4
	_simulate_track(am, mock_player, 2.1)
	assert_array(_received_beats).contains_exactly([3, 4])
	assert_array(_received_measures).contains_exactly([1])
	
	# Loop detection: 0.1s
	_received_beats = []
	_simulate_track(am, mock_player, 0.1)
	# Should NOT emit intermediate beats, just reset and start from new position.
	# Actually, in the current implementation, it snaps to 0.1s which is beat 0.
	assert_array(_received_beats).contains_exactly([]) # Corrected: first beat after loop should be emitted on NEXT crossing or if we want it immediate.
	# In our new implementation, backward jumps just snap.
	
	# Test large forward jump (seek)
	_received_beats = []
	_simulate_track(am, mock_player, 10.0) # Jump to 10s (beat 20)
	assert_array(_received_beats).is_empty() # Should snap without emitting 1 to 19
	
	_simulate_track(am, mock_player, 10.6) # Next crossing (beat 21)
	assert_array(_received_beats).contains_exactly([21])
	
	mock_player.free()
	am.free()

func _simulate_track(am, player, pos):
	if not player.get_script():
		var script = GDScript.new()
		script.set_source_code("extends AudioStreamPlayer\nvar _mock_pos = 0.0\nfunc get_playback_position(): return _mock_pos\nfunc is_playing(): return true")
		script.reload()
		player.set_script(script)
	
	player.set("_mock_pos", pos)
	player.set("playing", true)
	am._track_beat()

func test_beat_sync_trigger_logic():
	var target = Node.new()
	target.name = "TargetNode"
	var trigger = BeatSyncTriggerScript.new()
	trigger.name = "TriggerNode"
	
	# Mock method on target
	var target_script = GDScript.new()
	target_script.set_source_code("extends Node\nvar activated_count = 0\nfunc activate(): activated_count += 1")
	target_script.reload()
	target.set_script(target_script)
	
	trigger.target_path = ".."
	trigger.trigger_mode = "activate"
	trigger.wait_for_runtime_startup = false
	
	target.add_child(trigger)
	trigger.set("_target", target)
	
	trigger._on_beat(8)
	assert_int(target.get("activated_count")).is_equal(0)
	
	trigger.every_n_beats = 8
	trigger.set("_last_trigger_frame", -1)
	trigger._on_beat(8)
	assert_int(target.get("activated_count")).is_equal(1)
	
	trigger.beat_pattern = [1, 3, 5]
	trigger.set("_last_trigger_frame", -1)
	trigger._on_beat(3)
	assert_int(target.get("activated_count")).is_equal(2)
	
	trigger.max_triggers = 4
	trigger.set("_last_trigger_frame", -1)
	trigger._on_beat(5)
	assert_int(target.get("activated_count")).is_equal(3)
	
	trigger.max_triggers = 3
	# Need to bypass Engine.get_frames_drawn() check for different signals in same frame
	# or just wait for next frame if possible. 
	# In unit tests, we can just manually reset _last_trigger_frame
	trigger.set("_last_trigger_frame", -1)
	trigger._on_beat(1) # should NOT trigger because _trigger_count is 3
	assert_int(target.get("activated_count")).is_equal(3)
	
	trigger.free()
	target.free()
