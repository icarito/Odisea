extends Spatial

signal compiled(cache_path)

var _compiled_cache_paths = []


func _ready():
	pass

func load_and_compile(cache_path):
	var cache_packed_scene = load(cache_path)
	if cache_packed_scene == null:
		printerr("[ShaderCacheManager] Failed to load cache scene: ", cache_path)
		return
	compile(cache_packed_scene)

func compile(cache_packed_scene):
	if cache_packed_scene == null:
		printerr("[ShaderCacheManager] compile() received null PackedScene.")
		return
	var cache_path = cache_packed_scene.resource_path
	if is_compiled(cache_path):
		print("[ShaderCacheManager] Cache already compiled: ", cache_path)
		return
	
	var cache_scene = spawn_cache(cache_packed_scene)
	if cache_scene == null:
		printerr("[ShaderCacheManager] Failed to instance cache scene: ", cache_path)
		return
	if not cache_scene.has_signal("compiled"):
		printerr("[ShaderCacheManager] Cache scene does not expose 'compiled' signal: ", cache_path)
		cache_scene.queue_free()
		return

	cache_scene.connect("compiled", self, "_on_cache_compiled", [cache_path, cache_scene], CONNECT_ONESHOT)
	_prepare_cache_scene(cache_scene, cache_path)

func _prepare_cache_scene(cache_scene, cache_path: String) -> void:
	if cache_scene.has_method("cache_scene"):
		var state = cache_scene.cache_scene()
		if state is GDScriptFunctionState:
			state.connect("completed", self, "_on_cache_scene_built", [cache_scene, cache_path], CONNECT_ONESHOT)
			return
	_on_cache_scene_built(cache_scene, cache_path)

func _on_cache_scene_built(cache_scene, cache_path: String) -> void:
	if not is_instance_valid(cache_scene):
		return
	if cache_scene.has_method("set_active"):
		cache_scene.set_active(true)

func _on_cache_compiled(cache_path, cache_scene):
	_compiled_cache_paths.append(cache_path)
	cache_scene.queue_free()
	emit_signal("compiled", cache_path)

func spawn_cache(cache_packed_scene):
	var cache_scene = cache_packed_scene.instance()
	if cache_scene == null:
		return null
	var active_camera = get_active_camera()
	if active_camera == null:
		return null
	active_camera.add_child(cache_scene)
	cache_scene.scale = Vector3.ONE * 0.001
	cache_scene.global_transform.origin = -active_camera.global_transform.basis.z * 5

	return cache_scene

func is_compiled(cache_path):
	return cache_path in _compiled_cache_paths

func get_active_camera():
	var active_camera = get_viewport().get_camera()
	if active_camera:
		return active_camera
	var scene_root = get_tree().current_scene
	if scene_root:
		return _find_first_camera(scene_root)
	return null

func _find_first_camera(node):
	if node is Camera:
		return node
	for child in node.get_children():
		var cam = _find_first_camera(child)
		if cam:
			return cam
	return null
