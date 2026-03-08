extends Spatial

export(String, FILE, "*.tscn,*.scn") var shader_cache_scene_path := "res://core_v2/levels/shader_cache/BaseTerraceShaderCache.tscn"
export(bool) var run_in_tests := false

var _started := false

func _ready() -> void:
	if Engine.editor_hint:
		return
	if _is_disabled_in_runtime():
		queue_free()
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

	manager.load_and_compile(shader_cache_scene_path)

func _on_shader_cache_compiled(cache_path: String) -> void:
	if cache_path != shader_cache_scene_path:
		return
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
	var hardware_profile = get_node_or_null("/root/HardwareProfile")
	if hardware_profile != null:
		if hardware_profile.has_method("get_platform") and hardware_profile.get_platform() == hardware_profile.PlatformType.SWITCH:
			return true
		if hardware_profile.has_method("is_weak_hardware") and hardware_profile.is_weak_hardware():
			return true
	var in_rl = OS.get_environment("ANNA_RL_MODE").to_lower() in ["1", "true", "yes", "on"]
	var disable_in_rl = OS.get_environment("ODISEA_DISABLE_SHADER_WARMUP_IN_RL")
	if disable_in_rl == "":
		disable_in_rl = "1"
	var disable_rl = disable_in_rl.to_lower() in ["1", "true", "yes", "on"]
	return in_rl and disable_rl
