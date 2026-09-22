# Hornea las escenas de warmup de shaders (addons/gd-shader-cache).
#
# Sin hornear, ShaderCache.cache_scene() corre EN RUNTIME: instancia el nivel
# entero dentro de un SceneTree virtual y le corre _ready() a todo (medido en
# RingHub: 1.1 s de UN frame bloqueado en desktop nativo; en wasm es el cuelgue
# del navegador que se ve despues de "[ShaderCacheManager] compiling:").
# Horneado, el .tscn ya trae las quads y el runtime solo las revela por lotes.
#
# Uso: tools/godot --path . -s tools/bake_shader_cache.gd
extends SceneTree

# Solo los caches de escenas que el build realmente carga. Hornear uno de un nivel
# al que hoy no se llega no acelera nada y ademas lo vuelve dependencia REAL del
# export (114 ext_resource de Dome_Intro): peso muerto en el pck que despues no se
# puede podar. Al reconectar un nivel, agregarlo aca y rehornear.
#   parqueados: DomeIntroShaderCache, DomeCrioShaderCache, ExteriorShaderCache
const CACHES := [
	"res://core_v2/levels/shader_cache/RingHubShaderCache.tscn",
]

func _init():
	# spawn_cache() no corre aca, pero ShaderCache y el nivel esperan una camara viva.
	var cam := Camera.new()
	get_root().add_child(cam)
	for path in CACHES:
		var state = _bake(path)
		if state is GDScriptFunctionState:
			yield(state, "completed")
	quit()

func _bake(path: String):
	var packed = load(path)
	if packed == null:
		printerr("[bake] no se pudo cargar ", path)
		return
	var node = packed.instance()
	get_root().add_child(node)
	var t0 := OS.get_ticks_msec()
	var state = node.cache_scene()
	if state is GDScriptFunctionState:
		yield(state, "completed")
	var quads := 0
	for container in ["Materials", "LocalToSceneMaterials", "ParticlesMaterials"]:
		var c = node.get_node_or_null(container)
		if c:
			quads += c.get_child_count()
	node.active = false
	var out := PackedScene.new()
	var err = out.pack(node)
	if err != OK:
		printerr("[bake] pack fallo en ", path, " err=", err)
	else:
		err = ResourceSaver.save(path, out)
		if err != OK:
			printerr("[bake] save fallo en ", path, " err=", err)
	print("[bake] ", path, " quads=", quads, " ms=", OS.get_ticks_msec() - t0)
	node.queue_free()
	yield(self, "idle_frame")
