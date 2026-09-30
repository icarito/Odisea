extends GdUnitTestSuite

# test_playback_probes.gd - FD-316 (tarea FF): sondas A/B del costo fijo de render del
# playback de snapshots (ODISEA_PLAYBACK_PROBES). Lo critico es que cada sonda se aplique
# durante su ventana y que el estado exacto se restaure SIEMPRE al cerrarla.

const PlaybackProbesScript = preload("res://core_v2/net/PlaybackProbes.gd")
const PROBES_ENV := PlaybackProbesScript.PROBES_ENV

# El etiquetado avanza una sonda por ventana y el resumen trae la mediana por sonda.
func test_probes_label_windows_and_report_median():
	var probes = PlaybackProbesScript.new(get_tree(), true)
	probes.window_frames = 2
	probes.include_subtrees = false
	probes.sequence = ["base", "3d"]

	assert_str(probes.step(10.0, 5.0)).is_equal("base")
	assert_str(probes.step(10.0, 5.0)).is_equal("base")
	assert_str(probes.step(20.0, 6.0)).is_equal("3d")
	assert_str(probes.step(20.0, 6.0)).is_equal("3d")
	# Agotada la secuencia: todo restaurado y las muestras salen sin etiqueta.
	assert_str(probes.step(30.0, 7.0)).is_equal("")

	var summary: Dictionary = probes.finish()
	assert_bool(summary.has("probes")).is_true()
	var probes_dict: Dictionary = summary["probes"]
	assert_int(int(probes_dict["base"]["n"])).is_equal(2)
	assert_int(int(probes_dict["3d"]["n"])).is_equal(2)
	assert_float(float(probes_dict["base"]["frame_ms_p50"])).is_equal_approx(10.0, 0.001)
	assert_float(float(probes_dict["3d"]["frame_ms_p50"])).is_equal_approx(20.0, 0.001)
	assert_float(float(probes_dict["3d"]["render_ms_p50_delta"])).is_equal_approx(1.0, 0.001)

# Sin ODISEA_PLAYBACK_PROBES=1 las sondas no tocan nada ni etiquetan muestras.
func test_probes_disabled_without_env():
	var prev := OS.get_environment(PROBES_ENV)
	OS.set_environment(PROBES_ENV, "")
	var probes = PlaybackProbesScript.new(get_tree())
	assert_bool(probes.is_enabled()).is_false()
	assert_str(probes.step(1.0, 1.0)).is_equal("")
	assert_bool(probes.finish().empty()).is_true()
	OS.set_environment(PROBES_ENV, prev)

# Cada sonda muta lo suyo durante la ventana y restaura el valor EXACTO al cerrar:
# cull_mask de la camara, visible de CanvasLayer/Control, Environment, render_scale y vsync.
func test_probes_restore_exact_state():
	var world := Spatial.new()
	add_child(world)
	var cam := Camera.new()
	world.add_child(cam)
	cam.cull_mask = 0xABCD

	var layer := CanvasLayer.new()
	world.add_child(layer)
	var control := Control.new()
	layer.add_child(control)
	control.visible = true
	var oculto := Control.new()
	layer.add_child(oculto)
	oculto.visible = false

	var wenv := WorldEnvironment.new()
	var env := Environment.new()
	wenv.environment = env
	world.add_child(wenv)

	var sm = get_node_or_null("/root/SettingsManager")
	var prev_scale := 1.0
	if sm != null:
		prev_scale = sm.render_scale
		sm.render_scale = 0.6
	var prev_vsync := OS.vsync_enabled
	OS.vsync_enabled = true

	# 3d: cull_mask=0 y vuelve el valor original. El suite corre en un viewport donde
	# get_camera() no resuelve, asi que se usa el seam camera_override.
	var p3 = PlaybackProbesScript.new(get_tree(), true)
	p3.include_subtrees = false
	p3.sequence = ["3d"]
	p3.camera_override = cam
	p3.step(1.0, 1.0)
	assert_int(cam.cull_mask).is_equal(0)
	p3.finish()
	assert_int(cam.cull_mask).is_equal(0xABCD)

	# ui: se ocultan CanvasLayer y Controls; los ya ocultos siguen ocultos.
	var pu = PlaybackProbesScript.new(get_tree(), true)
	pu.include_subtrees = false
	pu.sequence = ["ui"]
	pu.step(1.0, 1.0)
	assert_bool(layer.visible).is_false()
	assert_bool(control.visible).is_false()
	pu.finish()
	assert_bool(layer.visible).is_true()
	assert_bool(control.visible).is_true()
	assert_bool(oculto.visible).is_false()

	# env: se quita el Environment y vuelve el mismo recurso.
	var pe = PlaybackProbesScript.new(get_tree(), true)
	pe.include_subtrees = false
	pe.sequence = ["env"]
	pe.step(1.0, 1.0)
	assert_bool(wenv.environment == null).is_true()
	pe.finish()
	assert_bool(wenv.environment == env).is_true()

	# scale: render_scale pasa a 1.0 y vuelve al valor previo.
	if sm != null:
		var ps = PlaybackProbesScript.new(get_tree(), true)
		ps.include_subtrees = false
		ps.sequence = ["scale"]
		ps.step(1.0, 1.0)
		assert_float(sm.render_scale).is_equal_approx(1.0, 0.001)
		ps.finish()
		assert_float(sm.render_scale).is_equal_approx(0.6, 0.001)

	# vsync: se apaga y vuelve el valor previo.
	var pv = PlaybackProbesScript.new(get_tree(), true)
	pv.include_subtrees = false
	pv.sequence = ["vsync"]
	pv.step(1.0, 1.0)
	assert_bool(OS.vsync_enabled).is_false()
	pv.finish()
	assert_bool(OS.vsync_enabled).is_true()

	# restore_all es idempotente y no deja nada aplicado si el playback se corta a mitad.
	p3.restore_all()
	p3.restore_all()
	assert_int(cam.cull_mask).is_equal(0xABCD)

	if sm != null:
		sm.render_scale = prev_scale
		if sm.has_method("apply_render_resolution"):
			sm.call("apply_render_resolution")
	OS.vsync_enabled = prev_vsync
	world.queue_free()

# Tarea GG: una sonda de subarbol oculta SOLO ese subarbol, la etiqueta entra al resumen y la
# visibilidad exacta vuelve al cerrar la ventana.
func test_subtree_probe_hides_and_restores():
	var world := Spatial.new()
	add_child(world)
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var control := Control.new()
	layer.add_child(control)
	control.visible = true

	var probes = PlaybackProbesScript.new(get_tree(), true)
	probes.window_frames = 1
	probes.include_subtrees = false
	probes.sequence = ["base"]
	probes.add_subtree_probe("subtree:test", control)

	assert_str(probes.step(10.0, 5.0)).is_equal("base")
	assert_bool(control.visible).is_true()
	assert_str(probes.step(20.0, 6.0)).is_equal("subtree:test")
	assert_bool(control.visible).is_false()
	# Agotada la secuencia: todo restaurado y las muestras salen sin etiqueta.
	assert_str(probes.step(30.0, 7.0)).is_equal("")
	assert_bool(control.visible).is_true()

	var summary: Dictionary = probes.finish()
	var p: Dictionary = summary["probes"]
	assert_bool(p.has("subtree:test")).is_true()
	assert_float(float(p["base"]["frame_ms_p50"])).is_equal_approx(10.0, 0.001)
	assert_float(float(p["subtree:test"]["frame_ms_p50"])).is_equal_approx(20.0, 0.001)
	assert_float(float(p["subtree:test"]["frame_ms_p50_delta"])).is_equal_approx(10.0, 0.001)
	world.queue_free()

# Tarea GG: la sonda vpalways apaga TODOS los Viewports en UPDATE_ALWAYS (comparten el World)
# dentro de su ventana y restaura el modo exacto al cerrarla.
func test_subtree_probe_disables_always_viewports():
	var world := Spatial.new()
	add_child(world)
	var vp := Viewport.new()
	world.add_child(vp)
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS

	var probes = PlaybackProbesScript.new(get_tree(), true)
	probes.window_frames = 1
	probes.include_subtrees = false
	probes.sequence = []
	probes.add_subtree_probe(PlaybackProbesScript.VP_ALWAYS_LABEL, null)

	assert_str(probes.step(10.0, 5.0)).is_equal(PlaybackProbesScript.VP_ALWAYS_LABEL)
	assert_int(vp.render_target_update_mode).is_equal(Viewport.UPDATE_DISABLED)
	probes.finish()
	assert_int(vp.render_target_update_mode).is_equal(Viewport.UPDATE_ALWAYS)
	world.queue_free()

# Tarea GG: un CanvasLayer (MobileUI/VirtualMouse) tambien se oculta; en Godot 3 no es
# CanvasItem pero tiene `visible`.
func test_subtree_probe_hides_canvas_layer():
	var layer := CanvasLayer.new()
	add_child(layer)
	var probes = PlaybackProbesScript.new(get_tree(), true)
	probes.window_frames = 1
	probes.include_subtrees = false
	probes.sequence = []
	probes.add_subtree_probe("subtree:layertest", layer)

	assert_str(probes.step(1.0, 1.0)).is_equal("subtree:layertest")
	assert_bool(layer.visible).is_false()
	probes.finish()
	assert_bool(layer.visible).is_true()
	layer.queue_free()

# Tarea GG: el descubrimiento etiqueta los subarboles con el prefijo "subtree:".
func test_discover_subtrees_labels():
	var probes = PlaybackProbesScript.new(get_tree(), true)
	probes.include_subtrees = false
	var labels: Array = probes.discover_subtrees()
	assert_bool(labels.empty()).is_false()
	for label in labels:
		assert_bool(String(label).begins_with("subtree:")).is_true()
