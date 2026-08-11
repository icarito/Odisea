extends SceneTree

# measure_fill.gd — A/B de costo por pixel en un nivel (GLES2).
#
# Mide fps real (tiempo de N frames, no el promedio del engine) apagando una capa
# de render por vez y restaurandola despues, para atribuir el fill rate a algo
# concreto: resolucion, luces, post-proceso, transparencias, sombras.
#
#   ODISEA_DISABLE_VSYNC=1 godot3-bin --path . -s res://tools/measure_fill.gd
#   ODISEA_DISABLE_VSYNC=1 godot3-bin --path . -s res://tools/measure_fill.gd res://otra/escena.tscn
#
# Sin vsync los numeros son comparables; con vsync todo se aplasta contra el
# refresco del monitor y el A/B no dice nada.
#
# Cada variante se compara contra un baseline medido JUSTO ANTES, no contra uno
# tomado al principio: la iGPU baja de frecuencia despues de unos minutos a full
# (medido: el baseline cae de 111 a ~75 fps a lo largo de una corrida), y con un
# baseline unico esa deriva termica se le acredita a la ultima capa que se toco.

const DEFAULT_SCENE := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const WARMUP_FRAMES := 40
const MEASURE_FRAMES := 120

var _scene: Node = null
var _env: Environment = null
var _pairs := []

func _init():
	call_deferred("_run")

func _run():
	var scene_path := DEFAULT_SCENE
	for arg in OS.get_cmdline_args():
		if arg.begins_with("res://") and arg.ends_with(".tscn"):
			scene_path = arg

	print("[fill] escena: ", scene_path)
	print("[fill] vsync: ", OS.is_vsync_enabled())

	var packed = load(scene_path)
	if packed == null:
		printerr("[fill] no se pudo cargar ", scene_path)
		quit(1)
		return
	_scene = packed.instance()
	root.add_child(_scene)
	current_scene = _scene

	# Dejar que arranquen los builds diferidos y el spawn antes de medir.
	var settle = _wait(120)
	if settle is GDScriptFunctionState:
		yield(settle, "completed")

	_env = _find_environment()
	print("[fill] viewport: ", root.size, "  environment: ", "si" if _env != null else "no")
	_describe_scene()

	var step = _variant_half_resolution()
	if step is GDScriptFunctionState:
		yield(step, "completed")
	step = _variant_lights()
	if step is GDScriptFunctionState:
		yield(step, "completed")
	step = _variant_light_range()
	if step is GDScriptFunctionState:
		yield(step, "completed")
	step = _variant_resolution_scale(0.75)
	if step is GDScriptFunctionState:
		yield(step, "completed")
	step = _variant_post_all()
	if step is GDScriptFunctionState:
		yield(step, "completed")
	step = _variant_post_each()
	if step is GDScriptFunctionState:
		yield(step, "completed")
	step = _variant_transparent()
	if step is GDScriptFunctionState:
		yield(step, "completed")
	step = _variant_shadows()
	if step is GDScriptFunctionState:
		yield(step, "completed")

	_report()
	quit(0)

# --- variantes -----------------------------------------------------------------

# Referencia de cuanto del frame depende de la cantidad de pixeles.
func _variant_half_resolution():
	var base = _measure("ref")
	if base is GDScriptFunctionState:
		base = yield(base, "completed")
	var full: Vector2 = root.size
	set_screen_stretch(SceneTree.STRETCH_MODE_VIEWPORT, SceneTree.STRETCH_ASPECT_EXPAND, full * 0.5)
	var variant = _measure("media resolucion (%dx%d)" % [int(full.x * 0.5), int(full.y * 0.5)])
	if variant is GDScriptFunctionState:
		variant = yield(variant, "completed")
	set_screen_stretch(SceneTree.STRETCH_MODE_VIEWPORT, SceneTree.STRETCH_ASPECT_EXPAND, full)
	_pairs.append({"base": base, "variant": variant})

func _variant_lights():
	var base = _measure("ref")
	if base is GDScriptFunctionState:
		base = yield(base, "completed")
	var hidden := _hide_lights()
	var variant = _measure("sin luces (%d)" % hidden.size())
	if variant is GDScriptFunctionState:
		variant = yield(variant, "completed")
	for light in hidden:
		light.visible = true
	_pairs.append({"base": base, "variant": variant})

# Una omni cuesta por los pixeles que cubre: la mitad de rango es un cuarto del area
# afectada, sin apagar ninguna luz (el look se mantiene, cambia el alcance).
func _variant_light_range():
	var base = _measure("ref")
	if base is GDScriptFunctionState:
		base = yield(base, "completed")
	var lights := []
	_collect(_scene, "Light", lights)
	var saved := {}
	for light in lights:
		if light.visible and light is OmniLight:
			saved[light] = light.omni_range
			light.omni_range = light.omni_range * 0.5
	var variant = _measure("omnis con la mitad de rango (%d)" % saved.size())
	if variant is GDScriptFunctionState:
		variant = yield(variant, "completed")
	for light in saved:
		light.omni_range = saved[light]
	_pairs.append({"base": base, "variant": variant})

# La palanca que ya existe en el juego (render_scale): cuanto compra bajar un poco
# la resolucion interna sin llegar a la mitad.
func _variant_resolution_scale(scale: float):
	var base = _measure("ref")
	if base is GDScriptFunctionState:
		base = yield(base, "completed")
	var full: Vector2 = root.size
	set_screen_stretch(SceneTree.STRETCH_MODE_VIEWPORT, SceneTree.STRETCH_ASPECT_EXPAND, full * scale)
	var variant = _measure("resolucion x%.2f (%dx%d)" % [scale, int(full.x * scale), int(full.y * scale)])
	if variant is GDScriptFunctionState:
		variant = yield(variant, "completed")
	set_screen_stretch(SceneTree.STRETCH_MODE_VIEWPORT, SceneTree.STRETCH_ASPECT_EXPAND, full)
	_pairs.append({"base": base, "variant": variant})

func _variant_post_all():
	if _env == null:
		return
	var base = _measure("ref")
	if base is GDScriptFunctionState:
		base = yield(base, "completed")
	var saved := _set_post({"glow_enabled": false, "ssao_enabled": false, "fog_enabled": false,
		"dof_blur_far_enabled": false, "dof_blur_near_enabled": false})
	var variant = _measure("sin post completo")
	if variant is GDScriptFunctionState:
		variant = yield(variant, "completed")
	_restore_post(saved)
	_pairs.append({"base": base, "variant": variant})

# En GLES2 el glow son varios blits a media/cuarta resolucion y se paga aunque no
# haya nada brillante en cuadro; conviene saber cual de los efectos manda.
func _variant_post_each():
	if _env == null:
		return
	var props := ["glow_enabled", "ssao_enabled", "fog_enabled", "dof_blur_far_enabled"]
	for prop in props:
		if not bool(_env.get(prop)):
			continue
		var base = _measure("ref")
		if base is GDScriptFunctionState:
			base = yield(base, "completed")
		_env.set(prop, false)
		var variant = _measure("  sin %s" % prop.replace("_enabled", ""))
		if variant is GDScriptFunctionState:
			variant = yield(variant, "completed")
		_env.set(prop, true)
		_pairs.append({"base": base, "variant": variant})

func _variant_transparent():
	var base = _measure("ref")
	if base is GDScriptFunctionState:
		base = yield(base, "completed")
	var hidden := _hide_transparent()
	var variant = _measure("sin transparencias (%d mallas)" % hidden.size())
	if variant is GDScriptFunctionState:
		variant = yield(variant, "completed")
	for mesh in hidden:
		mesh.visible = true
	_pairs.append({"base": base, "variant": variant})

func _variant_shadows():
	var base = _measure("ref")
	if base is GDScriptFunctionState:
		base = yield(base, "completed")
	var lights := []
	_collect(_scene, "Light", lights)
	var touched := []
	for light in lights:
		if light.shadow_enabled:
			light.shadow_enabled = false
			touched.append(light)
	var variant = _measure("sin sombras (%d luces)" % touched.size())
	if variant is GDScriptFunctionState:
		variant = yield(variant, "completed")
	for light in touched:
		light.shadow_enabled = true
	_pairs.append({"base": base, "variant": variant})

# --- medicion ------------------------------------------------------------------

func _measure(label: String):
	var warm = _wait(WARMUP_FRAMES)
	if warm is GDScriptFunctionState:
		yield(warm, "completed")
	var t0 := OS.get_ticks_usec()
	var run = _wait(MEASURE_FRAMES)
	if run is GDScriptFunctionState:
		yield(run, "completed")
	var elapsed := float(OS.get_ticks_usec() - t0) / 1000000.0
	var fps := MEASURE_FRAMES / max(elapsed, 0.000001)
	var sample := {
		"label": label,
		"fps": fps,
		"ms": 1000.0 / max(fps, 0.001),
		"dc": Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME),
		"verts": Performance.get_monitor(Performance.RENDER_VERTICES_IN_FRAME),
	}
	print("[fill] %-34s %7.1f fps  %6.2f ms  dc=%4d verts=%d" % [label, fps, sample["ms"], sample["dc"], sample["verts"]])
	return sample

func _wait(frames: int):
	var i := 0
	while i < frames:
		yield(self, "idle_frame")
		i += 1

func _report() -> void:
	print("\n[fill] === ahorro por capa (cada una contra su propia referencia) ===")
	for pair in _pairs:
		var base = pair["base"]
		var variant = pair["variant"]
		var saved_ms: float = base["ms"] - variant["ms"]
		print("[fill] %-34s  -%5.2f ms de %5.2f  (%+.0f%% fps, ref %.0f fps)" % [
			variant["label"], saved_ms, base["ms"],
			100.0 * (variant["fps"] / base["fps"] - 1.0), base["fps"]
		])

# --- helpers -------------------------------------------------------------------

func _describe_scene() -> void:
	var lights := []
	_collect(_scene, "Light", lights)
	var visible_count := 0
	for light in lights:
		if light.visible:
			visible_count += 1
	print("[fill] luces: %d en la escena, %d visibles" % [lights.size(), visible_count])
	for light in lights:
		if light.visible:
			print("[fill]    %-16s %-16s shadow=%s" % [light.name, light.get_class(), light.shadow_enabled])

func _hide_lights() -> Array:
	var lights := []
	_collect(_scene, "Light", lights)
	var hidden := []
	for light in lights:
		if light.visible:
			light.visible = false
			hidden.append(light)
	return hidden

func _hide_transparent() -> Array:
	var meshes := []
	_collect(_scene, "GeometryInstance", meshes)
	var hidden := []
	for mesh in meshes:
		if mesh.visible and _is_transparent(mesh):
			mesh.visible = false
			hidden.append(mesh)
	return hidden

func _set_post(values: Dictionary) -> Dictionary:
	var saved := {}
	for prop in values:
		saved[prop] = _env.get(prop)
		_env.set(prop, values[prop])
	return saved

func _restore_post(saved: Dictionary) -> void:
	for prop in saved:
		_env.set(prop, saved[prop])

func _collect(node: Node, type_name: String, out: Array) -> void:
	if node.is_class(type_name):
		out.append(node)
	for child in node.get_children():
		_collect(child, type_name, out)

func _is_transparent(mesh: GeometryInstance) -> bool:
	var material = mesh.material_override
	if material == null and mesh is MeshInstance and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
		material = mesh.get_surface_material(0)
		if material == null:
			material = mesh.mesh.surface_get_material(0)
	if material is SpatialMaterial:
		return material.flags_transparent
	if material is ShaderMaterial:
		var shader = material.shader
		if shader != null:
			return "blend_mix" in shader.code or "blend_add" in shader.code
	return false

func _find_environment() -> Environment:
	var envs := []
	_collect(_scene, "WorldEnvironment", envs)
	for we in envs:
		if we.environment != null:
			return we.environment
	var camera := root.get_camera()
	if camera != null and camera.environment != null:
		return camera.environment
	return null
