extends Node
class_name BeatSyncTrigger

# FD-245: BeatSyncTrigger
# Listens to AudioManager beat signals and triggers target node.

export(NodePath) var target_path: NodePath
export(String, "activate", "deactivate", "toggle", "call") var trigger_mode: String = "activate"
export(String) var method_name: String = "activate"

export(Array, int) var beat_pattern: Array = []
export(Array, int) var measure_pattern: Array = []
export(int, 0, 64) var every_n_beats: int = 0
export(int, 0, 64) var every_n_measures: int = 0

export(bool) var repeat: bool = true
export(int, -1, 999) var max_triggers: int = -1
export(bool) var wait_for_runtime_startup: bool = true

var _trigger_count: int = 0
var _target: Node = null
var _method_not_found_warned: bool = false
var _signals_connected: bool = false
var _last_trigger_frame: int = -1

func _ready() -> void:
	if Engine.editor_hint:
		return
	
	_target = get_node_or_null(target_path)
	
	if wait_for_runtime_startup:
		_wait_for_startup()
	else:
		_connect_signals()

func _wait_for_startup() -> void:
	var session = get_node_or_null("/root/SessionManager")
	if session and session.has_method("is_startup_gate_open"):
		if not session.is_startup_gate_open():
			if session.has_method("wait_until_startup_gate_open"):
				var wait_state = session.wait_until_startup_gate_open()
				if wait_state is GDScriptFunctionState:
					yield(wait_state, "completed")
	_connect_signals()

func _connect_signals() -> void:
	if _signals_connected:
		return
	
	var am = get_node_or_null("/root/AudioManager")
	if not am:
		return
	
	if not beat_pattern.empty() or every_n_beats > 0:
		am.connect("beat", self, "_on_beat")
	
	if not measure_pattern.empty() or every_n_measures > 0:
		am.connect("measure", self, "_on_measure")
	
	_signals_connected = true

func _on_beat(beat_number: int) -> void:
	if not repeat and _trigger_count > 0:
		return
	
	if max_triggers > 0 and _trigger_count >= max_triggers:
		_disconnect_signals()
		return
	
	var should_trigger = false
	
	if not beat_pattern.empty():
		if beat_number in beat_pattern:
			should_trigger = true
	
	if every_n_beats > 0:
		if beat_number % every_n_beats == 0:
			should_trigger = true
			
	if should_trigger:
		_trigger()

func _on_measure(measure_number: int) -> void:
	if not repeat and _trigger_count > 0:
		return
	
	if max_triggers > 0 and _trigger_count >= max_triggers:
		_disconnect_signals()
		return
		
	var should_trigger = false
	
	if not measure_pattern.empty():
		if measure_number in measure_pattern:
			should_trigger = true
			
	if every_n_measures > 0:
		if measure_number % every_n_measures == 0:
			should_trigger = true
			
	if should_trigger:
		_trigger()

func _trigger() -> void:
	if not _target:
		return
	
	# Prevent double-triggering in the same frame (e.g. beat and measure match)
	var current_frame = Engine.get_frames_drawn()
	if current_frame == _last_trigger_frame:
		return
	_last_trigger_frame = current_frame
		
	_trigger_count += 1
	
	match trigger_mode:
		"activate":
			_call_target("activate")
		"deactivate":
			_call_target("deactivate")
		"toggle":
			_call_target("toggle")
		"call":
			_call_target(method_name)
			
	if max_triggers > 0 and _trigger_count >= max_triggers:
		_disconnect_signals()

func _call_target(method: String) -> void:
	if _target.has_method(method):
		_target.call(method)
	elif not _method_not_found_warned:
		print("[BeatSyncTrigger] Warning: Target %s does not have method %s" % [_target.name, method])
		_method_not_found_warned = true

func _disconnect_signals() -> void:
	if not _signals_connected:
		return
		
	var am = get_node_or_null("/root/AudioManager")
	if not am:
		return
		
	if am.is_connected("beat", self, "_on_beat"):
		am.disconnect("beat", self, "_on_beat")
	if am.is_connected("measure", self, "_on_measure"):
		am.disconnect("measure", self, "_on_measure")
		
	_signals_connected = false
