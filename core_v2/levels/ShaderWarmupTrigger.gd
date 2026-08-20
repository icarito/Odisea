extends Spatial

export(String, FILE, "*.tscn,*.scn") var shader_cache_scene_path := "res://core_v2/levels/shader_cache/DomeCrioShaderCache.tscn"
export(bool) var run_in_tests := false
export(bool) var wait_for_startup_gate := true
export(int, 0, 1200) var startup_wait_max_frames := 720

var _started := false

func _ready() -> void:
	if Engine.editor_hint:
		return
	if _is_disabled_in_runtime():
		queue_free()
		return
	if not run_in_tests and _is_test_suite():
		return
	call_deferred("_start_shader_warmup_when_ready")

func _start_shader_warmup_when_ready() -> void:
	if _started or not is_instance_valid(self):
		return
	if wait_for_startup_gate:
		var session = get_node_or_null("/root/SessionManager")
		if session and session.has_method("is_startup_gate_open") and not bool(session.is_startup_gate_open()):
			if session.has_method("wait_until_startup_gate_open"):
				var wait_state = session.wait_until_startup_gate_open(startup_wait_max_frames)
				if wait_state is GDScriptFunctionState:
					yield(wait_state, "completed")
	if is_instance_valid(self):
		_start_shader_warmup()

func _start_shader_warmup() -> void:
	if _started:
		return
	_started = true

	# El .tscn del cache (shader_cache_scene_path) trae su propio campo scene_path
	# (ver ShaderCache.gd) apuntando al .tscn REAL que va a instanciar de nuevo para
	# forzar la compilacion de sus shaders. Si ese .tscn real es la escena YA activa
	# ahora mismo (el gate de arranque puede tardar tanto que el jugador salte del
	# Menu a esa escena antes de que este trigger dispare), el load() sincronico del
	# cache choca con la carga en curso de esa misma escena ("Cyclic reference?"),
	# devuelve null, y el add_child(null) siguiente crashea con SIGSEGV en release
	# (en debug solo tira el error y sigue). La escena real ya va a compilar sus
	# propios shaders al renderizarse, asi que el warmup es puramente redundante en
	# ese caso — no hace falta reintentar, solo saltarlo.
	var cache_packed = load(shader_cache_scene_path)
	var target_scene_path: String = ""
	if cache_packed != null:
		var cache_state = cache_packed.get_state()
		for i in cache_state.get_node_property_count(0):
			if cache_state.get_node_property_name(0, i) == "scene_path":
				target_scene_path = String(cache_state.get_node_property_value(0, i))
				break
	var current_scene = get_tree().current_scene
	var current_scene_path: String = current_scene.filename if is_instance_valid(current_scene) else ""
	# Ademas de "ya es la escena activa", Menu._ready() dispara SceneManager.
	# request_scene_preload() de esta MISMA escena en su propio call_deferred, en
	# paralelo a este trigger (los dos nacen de Menu._ready()). Un load() sincronico
	# acá mientras ese preload asincronico esta a mitad de camino pisa la misma
	# carrera ("Cyclic reference?" -> null -> SIGSEGV). SceneManager ya va a dejar
	# la escena precargada o en curso de estarlo: cachear shaders de nuevo ahi es
	# tan redundante como en el caso de la escena activa.
	var scene_manager = get_node_or_null("/root/SceneManager")
	var preload_conflict := false
	if target_scene_path != "" and is_instance_valid(scene_manager):
		if scene_manager.has_method("is_scene_preloading") and scene_manager.is_scene_preloading(target_scene_path):
			preload_conflict = true
		elif scene_manager.has_method("has_preloaded_scene") and scene_manager.has_preloaded_scene(target_scene_path):
			preload_conflict = true
	if target_scene_path != "" and (target_scene_path == current_scene_path or preload_conflict):
		var startup_trace_skip = get_node_or_null("/root/StartupTrace")
		if startup_trace_skip and startup_trace_skip.has_method("mark"):
			startup_trace_skip.mark("shader_warmup_skipped_active_scene", {
				"path": shader_cache_scene_path,
				"target": target_scene_path,
				"reason": "preload_conflict" if preload_conflict else "current_scene"
			})
		queue_free()
		return

	var startup_trace = get_node_or_null("/root/StartupTrace")
	if startup_trace and startup_trace.has_method("mark"):
		startup_trace.mark("shader_warmup_started", {
			"path": shader_cache_scene_path
		})

	var manager := get_node_or_null("/root/ShaderCacheManager")
	if manager == null:
		printerr("[ShaderWarmupTrigger] ShaderCacheManager autoload not found.")
		return

	if not manager.is_connected("compiled", self, "_on_shader_cache_compiled"):
		manager.connect("compiled", self, "_on_shader_cache_compiled")

	manager.load_and_compile(shader_cache_scene_path)

func _on_shader_cache_compiled(cache_path: String) -> void:
	if cache_path != shader_cache_scene_path:
		return
	var startup_trace = get_node_or_null("/root/StartupTrace")
	if startup_trace and startup_trace.has_method("mark"):
		startup_trace.mark("shader_warmup_compiled", {
			"path": cache_path
		})
	if is_instance_valid(self):
		queue_free()

func _is_test_suite() -> bool:
	if Engine.has_singleton("GdUnit3"):
		return Engine.get_singleton("GdUnit3").is_test_suite()
	return false

func _is_disabled_in_runtime() -> bool:
	var hard_disable = OS.get_environment("ODISEA_DISABLE_SHADER_WARMUP").to_lower()
	if hard_disable in ["1", "true", "yes", "on"]:
		return true
	var in_rl = OS.get_environment("ANNA_RL_MODE").to_lower() in ["1", "true", "yes", "on"]
	var disable_in_rl = OS.get_environment("ODISEA_DISABLE_SHADER_WARMUP_IN_RL")
	if disable_in_rl == "":
		disable_in_rl = "1"
	var disable_rl = disable_in_rl.to_lower() in ["1", "true", "yes", "on"]
	return in_rl and disable_rl
