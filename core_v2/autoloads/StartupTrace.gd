extends Node

signal trace_saved(path, report)

const TRACE_PATH := "user://startup_trace.json"
const DISABLE_ENV := "ODISEA_DISABLE_STARTUP_TRACE"
const FINALIZE_TIMEOUT_MS := 30000.0

var _enabled := true
var _start_usec := 0
var _events := []
var _completed := false
var _scene_manager_connected := false
var _session_manager_connected := false

func _enter_tree() -> void:
	_enabled = not _is_disabled()
	if not _enabled:
		return
	_start_usec = OS.get_ticks_usec()
	_append_event("startup_trace_enter_tree", {})

func _ready() -> void:
	if not _enabled:
		return
	_append_event("startup_trace_ready", {})
	call_deferred("_connect_runtime_signals")
	set_process(true)

func _process(_delta: float) -> void:
	if not _enabled:
		set_process(false)
		return
	if _completed:
		set_process(false)
		return
	_connect_runtime_signals()
	if _elapsed_ms() >= FINALIZE_TIMEOUT_MS:
		finalize("timeout")

func mark(name: String, data: Dictionary = {}) -> void:
	if not _enabled or _completed:
		return
	_append_event(name, data)

func finalize(reason: String = "manual") -> Dictionary:
	if not _enabled:
		return {}
	if _completed:
		return _build_report(reason)
	_append_event("startup_trace_finalize", {"reason": reason})
	_completed = true
	set_process(false)
	var report := _build_report(reason)
	_save_report(report)
	return report

func _connect_runtime_signals() -> void:
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager and not _scene_manager_connected:
		if not scene_manager.is_connected("transition_started", self, "_on_scene_transition_started"):
			scene_manager.connect("transition_started", self, "_on_scene_transition_started")
		if not scene_manager.is_connected("scene_ready", self, "_on_scene_ready"):
			scene_manager.connect("scene_ready", self, "_on_scene_ready")
		if not scene_manager.is_connected("transition_completed", self, "_on_scene_transition_completed"):
			scene_manager.connect("transition_completed", self, "_on_scene_transition_completed")
		_scene_manager_connected = true
		_append_event("startup_trace_scene_manager_connected", {})

	var session = get_node_or_null("/root/SessionManager")
	if session and not _session_manager_connected:
		if not session.is_connected("startup_gate_opened", self, "_on_startup_gate_opened"):
			session.connect("startup_gate_opened", self, "_on_startup_gate_opened")
		_session_manager_connected = true
		_append_event("startup_trace_session_manager_connected", {})

func _on_scene_transition_started(path: String, params: Dictionary) -> void:
	mark("scene_manager_transition_started", {
		"path": path,
		"show_loading": bool(params.get("show_loading", false)),
		"transition": String(params.get("transition", "fade"))
	})

func _on_scene_ready(path: String, scene_root: Node, _params: Dictionary) -> void:
	mark("scene_manager_scene_ready", {
		"path": path,
		"scene_name": scene_root.name if is_instance_valid(scene_root) else ""
	})

func _on_scene_transition_completed(path: String, scene_root: Node, _params: Dictionary) -> void:
	mark("scene_manager_transition_completed", {
		"path": path,
		"scene_name": scene_root.name if is_instance_valid(scene_root) else ""
	})

func _on_startup_gate_opened(reason: String, waited_frames: int) -> void:
	mark("session_manager_startup_gate_opened", {
		"reason": reason,
		"waited_frames": waited_frames
	})
	finalize("startup_gate_opened")

func _append_event(name: String, data: Dictionary) -> void:
	var payload := data.duplicate(true)
	_events.append({
		"name": String(name),
		"ms": _elapsed_ms(),
		"frame": Engine.get_frames_drawn(),
		"physics_frame": Engine.get_physics_frames(),
		"data": payload
	})

func _build_report(reason: String) -> Dictionary:
	return {
		"version": 1,
		"trace_path": TRACE_PATH,
		"finalize_reason": reason,
		"total_ms": _elapsed_ms(),
		"event_count": _events.size(),
		"events": _events.duplicate(true),
		"summary": {
			"boot_scene_ready_ms": _find_first_ms("boot_scene_ready"),
			"boot_loader_scene_request_ms": _find_first_ms("boot_loader_scene_request"),
			"session_manager_ready_ms": _find_first_ms("session_manager_ready"),
			"hardware_profile_ready_ms": _find_first_ms("hardware_profile_ready"),
			"optional_node_manager_ready_ms": _find_first_ms("optional_node_manager_ready"),
			"scene_manager_transition_started_ms": _find_first_ms("scene_manager_transition_started"),
			"scene_manager_scene_ready_ms": _find_first_ms("scene_manager_scene_ready"),
			"scene_manager_transition_completed_ms": _find_first_ms("scene_manager_transition_completed"),
			"startup_gate_opened_ms": _find_first_ms("session_manager_startup_gate_opened"),
			"shader_warmup_started_ms": _find_first_ms("shader_warmup_started"),
			"shader_warmup_compiled_ms": _find_first_ms("shader_warmup_compiled")
		}
	}

func _find_first_ms(name: String):
	for event in _events:
		if String(event.get("name", "")) == name:
			return event.get("ms", null)
	return null

func _elapsed_ms() -> float:
	if _start_usec <= 0:
		return 0.0
	return float(OS.get_ticks_usec() - _start_usec) / 1000.0

func _save_report(report: Dictionary) -> void:
	var file := File.new()
	var err := file.open(TRACE_PATH, File.WRITE)
	if err != OK:
		printerr("[StartupTrace] Could not write trace report: %s (err=%d)" % [TRACE_PATH, err])
		return
	file.store_string(JSON.print(report, "  "))
	file.close()
	emit_signal("trace_saved", TRACE_PATH, report)

func _is_disabled() -> bool:
	if Engine.editor_hint:
		return true
	var value = OS.get_environment(DISABLE_ENV).to_lower()
	return value in ["1", "true", "yes", "on"]
