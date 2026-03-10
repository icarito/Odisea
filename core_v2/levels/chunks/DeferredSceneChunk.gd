extends Spatial

export(PackedScene) var chunk_scene
export(bool) var wait_for_startup_gate := true
export(int, 0, 1200) var startup_wait_max_frames := 720
export(String) var startup_trace_label := ""

var _loaded := false

func _ready() -> void:
	if Engine.editor_hint:
		return
	if chunk_scene == null:
		return
	_mark_trace("deferred_chunk_ready")
	call_deferred("_load_chunk_when_ready")

func _load_chunk_when_ready() -> void:
	if _loaded or chunk_scene == null:
		return
	_mark_trace("deferred_chunk_load_requested")
	if wait_for_startup_gate:
		var session = get_node_or_null("/root/SessionManager")
		if session and session.has_method("is_startup_gate_open") and not bool(session.is_startup_gate_open()):
			_mark_trace("deferred_chunk_waiting_for_gate")
			if session.has_method("wait_until_startup_gate_open"):
				var wait_state = session.wait_until_startup_gate_open(startup_wait_max_frames)
				if wait_state is GDScriptFunctionState:
					yield(wait_state, "completed")
	if _loaded or not is_instance_valid(self):
		return
	var instance = chunk_scene.instance()
	if instance == null:
		return
	_loaded = true
	add_child(instance)
	_mark_trace("deferred_chunk_loaded")

func _mark_trace(event_name: String) -> void:
	var startup_trace = get_node_or_null("/root/StartupTrace")
	if startup_trace == null or not startup_trace.has_method("mark"):
		return
	var label := startup_trace_label if startup_trace_label != "" else name
	startup_trace.mark(event_name, {
		"label": label,
		"chunk_scene": chunk_scene.resource_path if chunk_scene != null else "",
		"node_path": String(get_path())
	})
