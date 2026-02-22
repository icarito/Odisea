extends Spatial

export(String, FILE, "*.tscn,*.scn") var shader_cache_scene_path := "res://core_v2/levels/shader_cache/BaseTerraceShaderCache.tscn"
export(bool) var run_in_tests := false

var _started := false

func _ready() -> void:
	if Engine.editor_hint:
		return
	if not run_in_tests and _is_test_suite():
		return
	call_deferred("_start_shader_warmup")

func _start_shader_warmup() -> void:
	if _started:
		return
	_started = true

	var manager := get_node_or_null("/root/ShaderCacheManager")
	if manager == null:
		printerr("[ShaderWarmupTrigger] ShaderCacheManager autoload not found.")
		return

	if not manager.is_connected("compiled", self, "_on_shader_cache_compiled"):
		manager.connect("compiled", self, "_on_shader_cache_compiled")

	print("[ShaderWarmupTrigger] Requesting shader cache compile: ", shader_cache_scene_path)
	manager.load_and_compile(shader_cache_scene_path)

func _on_shader_cache_compiled(cache_path: String) -> void:
	if cache_path != shader_cache_scene_path:
		return
	print("[ShaderWarmupTrigger] Shader cache compiled OK: ", cache_path)
	if is_instance_valid(self):
		queue_free()

func _is_test_suite() -> bool:
	if Engine.has_singleton("GdUnit3"):
		return Engine.get_singleton("GdUnit3").is_test_suite()
	return false
