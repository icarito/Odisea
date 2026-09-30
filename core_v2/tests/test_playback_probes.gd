extends GdUnitTestSuite

# test_playback_probes.gd - FD-316 (tareas FF/GG/JJ): sondas A/B del costo fijo de render del
# playback de snapshots (ODISEA_PLAYBACK_PROBES). Lo critico es que las sondas se INTERCALEN en
# bloques base/sonda (descartando los frames de transicion), que cada bloque de sonda se mida
# contra los bloques base ADYACENTES, que el estado exacto se restaure SIEMPRE al cerrar, y que
# los toggles de corrida completa (ODISEA_BENCH_*) se apliquen y no dejen estado al salir.

const PlaybackProbesScript = preload("res://core_v2/net/PlaybackProbes.gd")
const HudRedrawMeterScript = preload("res://core_v2/net/HudRedrawMeter.gd")
const PROBES_ENV := PlaybackProbesScript.PROBES_ENV
const REFERENCE_LABEL := PlaybackProbesScript.REFERENCE_LABEL

# El intercalado etiqueta bloques base/sonda, descarta los frames de transicion y reporta el
# delta PAREADO contra las bases adyacentes (mediana y p25-p75).
func test_interleave_blocks_and_paired_delta():
	var probes = PlaybackProbesScript.new(get_tree(), true)
	probes.block_frames = 2
	probes.discard_frames = 1
	probes.loop_schedule = false
	probes.include_subtrees = false
	probes.sequence = ["base", "3d"]

	# Bloque base: 1 frame de descarte + 2 medidos.
	assert_str(probes.step(1.0, 1.0)).is_equal("")
	assert_str(probes.step(10.0, 5.0)).is_equal("base")
	assert_str(probes.step(10.0, 5.0)).is_equal("base")
	# Bloque 3d: descarte + 2 medidos.
	assert_str(probes.step(1.0, 1.0)).is_equal("")
	assert_str(probes.step(20.0, 6.0)).is_equal("3d")
	assert_str(probes.step(20.0, 6.0)).is_equal("3d")
	# Bloque base de cierre (adorno del 3d): descarte + 2 medidos.
	assert_str(probes.step(1.0, 1.0)).is_equal("")
	assert_str(probes.step(12.0, 7.0)).is_equal("base")
	assert_str(probes.step(12.0, 7.0)).is_equal("base")
	# Agotada la secuencia: todo restaurado y las muestras salen sin etiqueta.
	assert_str(probes.step(30.0, 8.0)).is_equal("")

	var summary: Dictionary = probes.finish()
	assert_bool(summary.has("probes")).is_true()
	assert_bool(summary.has("redraw")).is_true()
	assert_int(int(summary["block_frames"])).is_equal(2)
	assert_int(int(summary["discard_frames"])).is_equal(1)
	var probes_dict: Dictionary = summary["probes"]
	# Los frames de descarte no se cuentan (6 frames alimentados, 4 base + 2 de la sonda).
	assert_int(int(probes_dict["base"]["n"])).is_equal(4)
	assert_int(int(probes_dict["3d"]["n"])).is_equal(2)
	assert_int(int(probes_dict["3d"]["blocks"])).is_equal(1)
	# Base cruda: mediana de [10, 10, 12, 12] = 11.
	assert_float(float(probes_dict["base"]["frame_ms_p50"])).is_equal_approx(11.0, 0.001)
	assert_float(float(probes_dict["3d"]["frame_ms_p50"])).is_equal_approx(20.0, 0.001)
	# Delta pareado: 20 - promedio de bases adyacentes (10, 12) = 20 - 11 = 9.
	assert_float(float(probes_dict["3d"]["frame_ms_p50_delta"])).is_equal_approx(9.0, 0.001)
	assert_float(float(probes_dict["3d"]["frame_ms_delta_p25"])).is_equal_approx(9.0, 0.001)
	assert_float(float(probes_dict["3d"]["frame_ms_delta_p75"])).is_equal_approx(9.0, 0.001)
	# La base es la referencia: su delta contra si misma es cero.
	assert_float(float(probes_dict["base"]["frame_ms_p50_delta"])).is_equal_approx(0.0, 0.001)

# Los frames de descarte no llevan etiqueta ni entran a las muestras; el bloque "activo" recien
# aparece despues del descarte.
func test_interleave_discards_transition_frames():
	var probes = PlaybackProbesScript.new(get_tree(), true)
	probes.block_frames = 3
	probes.discard_frames = 2
	probes.include_subtrees = false
	probes.sequence = ["3d"]

	# Primer bloque (base): 2 descartes sin etiqueta.
	assert_str(probes.step(1.0, 1.0)).is_equal("")
	assert_str(probes.step(1.0, 1.0)).is_equal("")
	assert_str(probes.active_probe()).is_equal("")
	assert_str(probes.step(10.0, 5.0)).is_equal("base")
	assert_str(probes.step(10.0, 5.0)).is_equal("base")
	assert_str(probes.step(10.0, 5.0)).is_equal("base")
	# Bloque 3d: otros 2 descartes que no se cuentan.
	assert_str(probes.step(1.0, 1.0)).is_equal("")
	assert_str(probes.step(1.0, 1.0)).is_equal("")
	assert_str(probes.active_probe()).is_equal("")
	assert_str(probes.step(20.0, 6.0)).is_equal("3d")
	assert_str(probes.step(20.0, 6.0)).is_equal("3d")
	assert_str(probes.step(20.0, 6.0)).is_equal("3d")

	var probes_dict: Dictionary = probes.finish()["probes"]
	assert_int(int(probes_dict["base"]["n"])).is_equal(3)
	assert_int(int(probes_dict["3d"]["n"])).is_equal(3)

# La rotacion recorre TODO el playback: con loop la secuencia se repite y cada sonda junta
# varios bloques (distribucion para la mediana y el p25-p75).
func test_interleave_rotates_over_route():
	var probes = PlaybackProbesScript.new(get_tree(), true)
	probes.block_frames = 1
	probes.discard_frames = 0
	probes.loop_schedule = true
	probes.include_subtrees = false
	probes.sequence = ["3d", "ui"]
	# Secuencia: base, 3d, base, ui, base (+ loop). Dos ciclos completos.
	for i in range(10):
		probes.step(float(i), float(i))
	var probes_dict: Dictionary = probes.finish()["probes"]
	assert_int(int(probes_dict["3d"]["blocks"])).is_greater_equal(2)
	assert_int(int(probes_dict["ui"]["blocks"])).is_greater_equal(2)

# Sin ODISEA_PLAYBACK_PROBES=1 las sondas no tocan nada ni etiquetan muestras.
func test_probes_disabled_without_env():
	var prev := OS.get_environment(PROBES_ENV)
	OS.set_environment(PROBES_ENV, "")
	var probes = PlaybackProbesScript.new(get_tree())
	assert_bool(probes.is_enabled()).is_false()
	assert_str(probes.step(1.0, 1.0)).is_equal("")
	assert_bool(probes.finish().empty()).is_true()
	OS.set_environment(PROBES_ENV, prev)

# Avanza un probes hasta que la sonda pedida quede aplicada (bloque abierto). Devuelve false si
# no la alcanza en `max_steps`.
func _advance_to(probes, label: String, max_steps: int = 64) -> bool:
	for i in range(max_steps):
		probes.step(1.0, 1.0)
		if probes.active_probe() == label:
			return true
	return false

# Cada sonda muta lo suyo durante su bloque y restaura el valor EXACTO al cerrar/cortar:
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
	p3.block_frames = 2
	p3.discard_frames = 0
	p3.include_subtrees = false
	p3.sequence = ["3d"]
	p3.camera_override = cam
	assert_bool(_advance_to(p3, "3d")).is_true()
	assert_int(cam.cull_mask).is_equal(0)
	p3.finish()
	assert_int(cam.cull_mask).is_equal(0xABCD)

	# ui: se ocultan CanvasLayer y Controls; los ya ocultos siguen ocultos.
	var pu = PlaybackProbesScript.new(get_tree(), true)
	pu.block_frames = 2
	pu.discard_frames = 0
	pu.include_subtrees = false
	pu.sequence = ["ui"]
	assert_bool(_advance_to(pu, "ui")).is_true()
	assert_bool(layer.visible).is_false()
	assert_bool(control.visible).is_false()
	pu.finish()
	assert_bool(layer.visible).is_true()
	assert_bool(control.visible).is_true()
	assert_bool(oculto.visible).is_false()

	# env: se quita el Environment y vuelve el mismo recurso.
	var pe = PlaybackProbesScript.new(get_tree(), true)
	pe.block_frames = 2
	pe.discard_frames = 0
	pe.include_subtrees = false
	pe.sequence = ["env"]
	assert_bool(_advance_to(pe, "env")).is_true()
	assert_bool(wenv.environment == null).is_true()
	pe.finish()
	assert_bool(wenv.environment == env).is_true()

	# scale: render_scale pasa a 1.0 y vuelve al valor previo.
	if sm != null:
		var ps = PlaybackProbesScript.new(get_tree(), true)
		ps.block_frames = 2
		ps.discard_frames = 0
		ps.include_subtrees = false
		ps.sequence = ["scale"]
		assert_bool(_advance_to(ps, "scale")).is_true()
		assert_float(sm.render_scale).is_equal_approx(1.0, 0.001)
		ps.finish()
		assert_float(sm.render_scale).is_equal_approx(0.6, 0.001)

	# vsync: se apaga y vuelve el valor previo.
	var pv = PlaybackProbesScript.new(get_tree(), true)
	pv.block_frames = 2
	pv.discard_frames = 0
	pv.include_subtrees = false
	pv.sequence = ["vsync"]
	assert_bool(_advance_to(pv, "vsync")).is_true()
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
# visibilidad exacta vuelve al cerrar el bloque.
func test_subtree_probe_hides_and_restores():
	var world := Spatial.new()
	add_child(world)
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var control := Control.new()
	layer.add_child(control)
	control.visible = true

	var probes = PlaybackProbesScript.new(get_tree(), true)
	probes.block_frames = 2
	probes.discard_frames = 0
	probes.include_subtrees = false
	probes.sequence = ["base"]
	probes.add_subtree_probe("subtree:test", control)

	# Bloque base (descarte/base) y luego el bloque de la sonda.
	assert_bool(_advance_to(probes, "subtree:test")).is_true()
	assert_bool(control.visible).is_false()

	# Se completa el bloque y la visibilidad vuelve exacta.
	assert_str(probes.step(20.0, 6.0)).is_equal("subtree:test")
	assert_bool(control.visible).is_true()

	var p: Dictionary = probes.finish()["probes"]
	assert_bool(p.has("subtree:test")).is_true()
	assert_int(int(p["subtree:test"]["blocks"])).is_equal(1)
	world.queue_free()

# Tarea GG: la sonda vpalways apaga TODOS los Viewports en UPDATE_ALWAYS (comparten el World)
# dentro de su bloque y restaura el modo exacto al cerrarla.
func test_subtree_probe_disables_always_viewports():
	var world := Spatial.new()
	add_child(world)
	var vp := Viewport.new()
	world.add_child(vp)
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS

	var probes = PlaybackProbesScript.new(get_tree(), true)
	probes.block_frames = 3
	probes.discard_frames = 0
	probes.include_subtrees = false
	probes.sequence = []
	probes.add_subtree_probe(PlaybackProbesScript.VP_ALWAYS_LABEL, null)

	assert_bool(_advance_to(probes, PlaybackProbesScript.VP_ALWAYS_LABEL)).is_true()
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
	probes.block_frames = 3
	probes.discard_frames = 0
	probes.include_subtrees = false
	probes.sequence = []
	probes.add_subtree_probe("subtree:layertest", layer)

	assert_bool(_advance_to(probes, "subtree:layertest")).is_true()
	assert_bool(layer.visible).is_false()
	probes.finish()
	assert_bool(layer.visible).is_true()
	layer.queue_free()

# Tarea GG/KK: el descubrimiento etiqueta los subarboles con el prefijo "subtree:" y, en la
# tarea KK, agrega una sonda por CanvasLayer ("layer:") y por overlay con shader ("overlay:").
func test_discover_subtrees_labels():
	var probes = PlaybackProbesScript.new(get_tree(), true)
	probes.include_subtrees = false
	var labels: Array = probes.discover_subtrees()
	assert_bool(labels.empty()).is_false()
	for label in labels:
		var l := String(label)
		assert_bool(l.begins_with("subtree:") or l.begins_with("layer:") \
			or l.begins_with("overlay:")).is_true()


# Tarea KK: cada CanvasLayer del arbol entra como "layer:<ruta>" (etiqueta = ruta) y ocultarlo
# durante su bloque lo restaura exacto. Los CanvasLayer ya cubiertos por una sonda nombrada
# (MobileUIManager, OverlayUIManager...) no se duplican.
func test_discover_canvas_layer_probe_and_restore():
	var world := Spatial.new()
	add_child(world)
	var layer := CanvasLayer.new()
	layer.name = "TestCanvasLayer"
	world.add_child(layer)
	var control := Control.new()
	layer.add_child(control)

	var probes = PlaybackProbesScript.new(get_tree(), true)
	probes.block_frames = 2
	probes.discard_frames = 0
	probes.include_subtrees = false
	probes.sequence = []
	var label := PlaybackProbesScript.LAYER_PREFIX + String(layer.get_path())
	probes.add_subtree_probe(label, layer)

	assert_bool(_advance_to(probes, label)).is_true()
	assert_bool(layer.visible).is_false()
	probes.finish()
	assert_bool(layer.visible).is_true()
	world.queue_free()


# Tarea KK: un overlay a pantalla completa con shader entra como "overlay:<ruta>" y se mide
# ocultandolo (mismo mecanismo que una sonda de subarbol).
func test_overlay_probe_hides_and_restores():
	var probe_scene = load("res://core_v2/ui/overlay/FrostVignette.tscn")
	assert_object(probe_scene).is_not_null()
	if probe_scene == null:
		return
	var overlay = probe_scene.instance()
	add_child(overlay)
	assert_bool(_overlay_script_matches(overlay)).is_true()

	var probes = PlaybackProbesScript.new(get_tree(), true)
	probes.block_frames = 2
	probes.discard_frames = 0
	probes.include_subtrees = false
	probes.sequence = []
	var label := PlaybackProbesScript.OVERLAY_PREFIX + String(overlay.get_path())
	probes.add_subtree_probe(label, overlay)

	assert_bool(_advance_to(probes, label)).is_true()
	assert_bool(overlay.visible).is_false()
	probes.finish()
	assert_bool(overlay.visible).is_true()
	overlay.queue_free()

# Helper del test: la misma condicion de script que usa PlaybackProbes._is_overlay_script.
func _overlay_script_matches(node) -> bool:
	var script = node.get_script()
	if script == null:
		return false
	var path := String(script.resource_path)
	for name in PlaybackProbesScript.OVERLAY_SCRIPTS:
		if path.ends_with(String(name)):
			return true
	return false


# Tarea JJ: los toggles de corrida completa apagan UI/3D/Environment por TODA la corrida, aun
# sin ODISEA_PLAYBACK_PROBES, y restore_all (o finish) devuelve el estado EXACTO.
func test_full_run_toggles_apply_and_restore():
	var prev_ui := OS.get_environment(PlaybackProbesScript.BENCH_NO_UI_ENV)
	var prev_3d := OS.get_environment(PlaybackProbesScript.BENCH_NO_3D_ENV)
	var prev_env := OS.get_environment(PlaybackProbesScript.BENCH_NO_ENV_ENV)
	var prev_probes := OS.get_environment(PROBES_ENV)
	OS.set_environment(PROBES_ENV, "")
	OS.set_environment(PlaybackProbesScript.BENCH_NO_UI_ENV, "1")
	OS.set_environment(PlaybackProbesScript.BENCH_NO_3D_ENV, "1")
	OS.set_environment(PlaybackProbesScript.BENCH_NO_ENV_ENV, "1")

	var world := Spatial.new()
	add_child(world)
	var cam := Camera.new()
	world.add_child(cam)
	cam.cull_mask = 0x1234
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var control := Control.new()
	layer.add_child(control)
	control.visible = true
	var wenv := WorldEnvironment.new()
	var env := Environment.new()
	wenv.environment = env
	world.add_child(wenv)

	var probes = PlaybackProbesScript.new(get_tree(), false)
	probes.camera_override = cam
	assert_bool(probes.is_enabled()).is_false()
	probes.apply_full_run_toggles()
	assert_bool(layer.visible).is_false()
	assert_bool(control.visible).is_false()
	assert_int(cam.cull_mask).is_equal(0)
	assert_bool(wenv.environment == null).is_true()
	assert_int(probes.full_run_labels().size()).is_equal(3)

	probes.restore_all()
	assert_bool(layer.visible).is_true()
	assert_bool(control.visible).is_true()
	assert_int(cam.cull_mask).is_equal(0x1234)
	assert_bool(wenv.environment == env).is_true()
	# Idempotente: no queda nada aplicado.
	probes.restore_all()
	assert_int(cam.cull_mask).is_equal(0x1234)

	# finish() tambien restaura los toggles aunque las sondas intercaladas esten apagadas.
	var probes2 = PlaybackProbesScript.new(get_tree(), false)
	probes2.camera_override = cam
	probes2.apply_full_run_toggles()
	assert_int(cam.cull_mask).is_equal(0)
	assert_bool(probes2.finish().empty()).is_true()
	assert_int(cam.cull_mask).is_equal(0x1234)

	OS.set_environment(PlaybackProbesScript.BENCH_NO_UI_ENV, prev_ui)
	OS.set_environment(PlaybackProbesScript.BENCH_NO_3D_ENV, prev_3d)
	OS.set_environment(PlaybackProbesScript.BENCH_NO_ENV_ENV, prev_env)
	OS.set_environment(PROBES_ENV, prev_probes)
	world.queue_free()


# Tarea LL: ODISEA_BENCH_HIDE oculta SOLO lo que matchea el patron (y su subarbol), deja el
# resto intacto, tambien oculta los nodos que entran despues (node_added) y restaura la
# visibilidad exacta al salir.
func test_bench_hide_pattern_hides_only_matches():
	var prev := OS.get_environment(PlaybackProbesScript.BENCH_HIDE_ENV)
	OS.set_environment(PlaybackProbesScript.BENCH_HIDE_ENV, "Banner")

	var world := Spatial.new()
	add_child(world)
	var layer := CanvasLayer.new()
	layer.name = "BannerLayer"
	world.add_child(layer)
	var banner_child := Control.new()
	layer.add_child(banner_child)
	banner_child.visible = true

	var keep_layer := CanvasLayer.new()
	keep_layer.name = "KeepLayer"
	world.add_child(keep_layer)
	var keep_child := Control.new()
	keep_layer.add_child(keep_child)
	keep_child.visible = true

	var probes = PlaybackProbesScript.new(get_tree(), false)
	probes.apply_full_run_toggles()
	assert_bool(layer.visible).is_false()
	assert_bool(keep_layer.visible).is_true()
	assert_bool(keep_child.visible).is_true()
	# Solo la capa que matchea quedo registrada (el subarbol no se recorre de nuevo).
	assert_int(probes.bench_hide_paths().size()).is_equal(1)

	# Nodos que entran DESPUES del arranque: solo se oculta el que matchea.
	var late_match := CanvasLayer.new()
	late_match.name = "LateBanner"
	world.add_child(late_match)
	assert_bool(late_match.visible).is_false()
	var late_keep := CanvasLayer.new()
	late_keep.name = "LateKeep"
	world.add_child(late_keep)
	assert_bool(late_keep.visible).is_true()
	assert_int(probes.bench_hide_paths().size()).is_equal(2)

	# El resumen trae las rutas ocultadas aunque las sondas intercaladas esten apagadas.
	assert_bool(probes.finish().has("bench_hide")).is_true()
	assert_bool(layer.visible).is_true()
	assert_bool(late_match.visible).is_true()
	assert_bool(keep_layer.visible).is_true()

	OS.set_environment(PlaybackProbesScript.BENCH_HIDE_ENV, prev)
	world.queue_free()

# Tarea LL: el inventario lista los CanvasLayer y los CanvasItem fullscreen/con material, y
# queda guardado con las claves que viajan a la traza.
func test_ui_inventory_lists_layers_and_overlays():
	var world := Spatial.new()
	add_child(world)
	var layer := CanvasLayer.new()
	layer.name = "InventoryLayer"
	world.add_child(layer)
	var control := Control.new()
	layer.add_child(control)
	control.visible = true

	var probes = PlaybackProbesScript.new(get_tree(), false)
	var inventory: Dictionary = probes.capture_ui_inventory()
	assert_bool(inventory.has("canvas_layers")).is_true()
	assert_bool(inventory.has("canvas_items")).is_true()
	assert_bool(probes.summary().has("ui_inventario")).is_true()
	world.queue_free()


# Tarea HH: el medidor cuenta UPDATE_ALWAYS por frame y los PULSOS de UPDATE_ONCE una sola vez
# por flag (asi el driver de 10 Hz se lee como ~10/s y un Viewport en ALWAYS como ~60/s).
func test_redraw_meter_counts_always_and_pulses():
	var meter = HudRedrawMeterScript.new()
	meter.tree = get_tree()
	var vp_once := Viewport.new()
	add_child(vp_once)
	vp_once.render_target_update_mode = Viewport.UPDATE_ONCE
	meter._viewports.append({
		"node": vp_once, "path": "once", "always": 0, "pulses": 0, "disabled": 0, "last_mode": -1,
	})
	var vp_always := Viewport.new()
	add_child(vp_always)
	vp_always.render_target_update_mode = Viewport.UPDATE_ALWAYS
	meter._viewports.append({
		"node": vp_always, "path": "always", "always": 0, "pulses": 0, "disabled": 0, "last_mode": -1,
	})

	meter.sample(100.0)
	meter.sample(100.0)

	var views: Dictionary = meter.report()["viewports"]
	assert_float(float(views["once"]["pulses_per_s"])).is_equal_approx(5.0, 0.001)
	assert_float(float(views["once"]["always_per_s"])).is_equal_approx(0.0, 0.001)
	assert_float(float(views["always"]["always_per_s"])).is_equal_approx(10.0, 0.001)
	vp_once.queue_free()
	vp_always.queue_free()


# Tarea HH: capture recorre el subarbol del widget host y registra Viewports, CanvasItem y el
# driver de 10 Hz (LowHzRedraw).
func test_redraw_meter_capture_subtree():
	var meter = HudRedrawMeterScript.new()
	meter.tree = get_tree()
	var root := Control.new()
	add_child(root)
	var vp := Viewport.new()
	root.add_child(vp)
	var driver := Node.new()
	driver.name = "LowHzRedraw"
	root.add_child(driver)
	var child := Control.new()
	root.add_child(child)

	meter._capture_subtree(root)
	assert_int(meter._viewports.size()).is_equal(1)
	assert_int(meter._low_hz_drivers).is_equal(1)
	assert_int(meter._canvas_items.size()).is_greater_equal(2)
	root.queue_free()
