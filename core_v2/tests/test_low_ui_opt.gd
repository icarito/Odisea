extends GdUnitTestSuite

# FD-316 (tarea GG): ahorros de UI del tier LOW, con A/B por ODISEA_LOW_UI_OPT.
# Lo critico: fuera de LOW (o con el A/B en 0) NADA cambia; en LOW, la UI animada se
# refresca a 10 Hz, los controles tactiles no se dibujan sin pantalla tactil y los
# subtitulos no pagan sombra.

const LowUiOptScript = preload("res://core_v2/systems/LowUiOpt.gd")
const LowHzTickScript = preload("res://core_v2/systems/LowHzTick.gd")
const SubtitlesOverlayScript = preload("res://core_v2/ui/retro/SubtitlesOverlay.gd")
const HudViewMountScript = preload("res://core_v2/ui/hud/HudViewMount.gd")
# Tarea KK: politica LOW de los Viewports de UI en UPDATE_ALWAYS.
const LowViewportOptimizerScript = preload("res://core_v2/ui/hud/LowViewportOptimizer.gd")
# Tarea MM: pantalla de terminal (HoloTerminalV2) con resolucion reducida y refresco visible
# espaciado en tier LOW.
const WallTerminalScene = preload("res://core_v2/props/controls/WallTerminal.tscn")
# Tarea NN: el panel de la criocapsula (CryoPodUI) en LOW usa el camino clasico de _draw en
# vez del canvas ImGui.
const CryoPodUIScene = preload("res://core_v2/props/criopod/CryoPodUI.tscn")

var _gate_prev := {}
var _sm_prev := false
var _env_prev := ""


func before() -> void:
	var gate = get_node_or_null("/root/GLES3VendorGate")
	if gate:
		_gate_prev = {
			"force_gate": gate.force_gate,
			"gated": gate._gated_active,
			"env": gate._env_forced_low_tier,
		}
	var sm = get_node_or_null("/root/SettingsManager")
	if sm and "low_end_forced" in sm:
		_sm_prev = bool(sm.get("low_end_forced"))
	_env_prev = OS.get_environment(LowUiOptScript.ENV)
	OS.set_environment(LowUiOptScript.ENV, "")


func after() -> void:
	var gate = get_node_or_null("/root/GLES3VendorGate")
	if gate and not _gate_prev.empty():
		gate.force_gate = _gate_prev["force_gate"]
		gate._gated_active = _gate_prev["gated"]
		gate._env_forced_low_tier = _gate_prev["env"]
	var sm = get_node_or_null("/root/SettingsManager")
	if sm and "low_end_forced" in sm:
		sm.set("low_end_forced", _sm_prev)
	OS.set_environment(LowUiOptScript.ENV, _env_prev)


func _set_low(active: bool) -> void:
	var gate = get_node_or_null("/root/GLES3VendorGate")
	assert_object(gate).is_not_null()
	if gate == null:
		return
	gate.force_gate = active
	gate._gated_active = false
	gate._env_forced_low_tier = false
	var sm = get_node_or_null("/root/SettingsManager")
	if sm and "low_end_forced" in sm:
		sm.set("low_end_forced", false)


# El interruptor es "tier LOW y ODISEA_LOW_UI_OPT != 0".
func test_low_ui_opt_gate_and_env() -> void:
	_set_low(true)
	assert_bool(LowUiOptScript.enabled()).is_true()
	OS.set_environment(LowUiOptScript.ENV, "0")
	assert_bool(LowUiOptScript.enabled()).is_false()
	OS.set_environment(LowUiOptScript.ENV, "")
	_set_low(false)
	assert_bool(LowUiOptScript.enabled()).is_false()


# En LOW el delta se acumula y solo sale cada ~0.1 s; fuera de LOW (o con el A/B en 0)
# pasa el mismo delta en cada llamada, sin cambiar el comportamiento.
func test_low_hz_tick_throttles_only_in_low() -> void:
	_set_low(true)
	var low_tick = LowHzTickScript.new(LowUiOptScript.HZ)
	assert_float(low_tick.step(0.03)).is_equal(-1.0)
	assert_float(low_tick.step(0.03)).is_equal(-1.0)
	assert_float(low_tick.step(0.05)).is_equal_approx(0.11, 0.0001)

	_set_low(false)
	var desktop_tick = LowHzTickScript.new(LowUiOptScript.HZ)
	assert_float(desktop_tick.step(0.016)).is_equal_approx(0.016, 0.0001)

	_set_low(true)
	OS.set_environment(LowUiOptScript.ENV, "0")
	var ab_off_tick = LowHzTickScript.new(LowUiOptScript.HZ)
	assert_float(ab_off_tick.step(0.016)).is_equal_approx(0.016, 0.0001)
	OS.set_environment(LowUiOptScript.ENV, "")


# En LOW sin un touch real visto la UI tactil queda suprimida; con el A/B en 0 no se suprime.
# Tarea HH: el gate ya no es OS.has_touchscreen_ui_hint() (mentia en el Anbernic) sino el
# primer InputEventScreenTouch real (`_touch_seen`).
func test_mobile_ui_suppressed_without_touchscreen_in_low() -> void:
	var mobile = get_node_or_null("/root/MobileUIManager")
	assert_object(mobile).is_not_null()
	if mobile == null:
		return
	var prev_touch_seen = mobile._touch_seen
	var prev_mobile: bool = mobile._is_mobile
	mobile._touch_seen = false
	mobile._is_mobile = false

	_set_low(true)
	assert_bool(mobile._touch_ui_suppressed()).is_true()
	mobile._activate_touch()
	assert_bool(mobile.is_touch_active()).is_false()
	# Un touch real visto la desuprime aunque la plataforma no se declare tactil.
	mobile._touch_seen = true
	assert_bool(mobile._touch_ui_suppressed()).is_false()
	mobile._touch_seen = false

	OS.set_environment(LowUiOptScript.ENV, "0")
	assert_bool(mobile._touch_ui_suppressed()).is_false()

	OS.set_environment(LowUiOptScript.ENV, "")
	_set_low(false)
	assert_bool(mobile._touch_ui_suppressed()).is_false()

	mobile._touch_seen = prev_touch_seen
	mobile._is_mobile = prev_mobile


# Los subtitulos pierden la sombra dinamica en LOW y la conservan fuera de LOW / con el A/B en 0.
func test_subtitles_shadow_disabled_in_low() -> void:
	var sub = SubtitlesOverlayScript.new()
	_set_low(true)
	assert_int(sub._build_stylebox(false).shadow_size).is_equal(0)
	OS.set_environment(LowUiOptScript.ENV, "0")
	assert_int(sub._build_stylebox(false).shadow_size).is_equal(4)
	OS.set_environment(LowUiOptScript.ENV, "")
	_set_low(false)
	assert_int(sub._build_stylebox(false).shadow_size).is_equal(4)
	sub.free()


# El Viewport animado del HUD pasa a UPDATE_DISABLED + driver de 10 Hz en LOW, y a
# UPDATE_ALWAYS sin driver fuera del tier.
func test_viewport_animation_is_10hz_in_low() -> void:
	var host = HudViewMountScript.new()
	var vp = Viewport.new()
	_set_low(true)
	host._enable_viewport_animation(vp)
	assert_int(vp.render_target_update_mode).is_equal(Viewport.UPDATE_DISABLED)
	assert_object(vp.get_node_or_null("LowHzRedraw")).is_not_null()

	_set_low(false)
	var vp_desktop = Viewport.new()
	host._enable_viewport_animation(vp_desktop)
	assert_int(vp_desktop.render_target_update_mode).is_equal(Viewport.UPDATE_ALWAYS)
	assert_object(vp_desktop.get_node_or_null("LowHzRedraw")).is_null()

	vp.free()
	vp_desktop.free()


# Tarea KK: en LOW un Viewport UPDATE_ALWAYS sin textura visible queda DISABLED, y uno que SI
# se muestra (ViewportContainer) queda con el driver de 10 Hz. El modo EXACTO vuelve al
# restaurar (salir del rol o apagar el A/B).
func test_viewport_optimizer_low_policy() -> void:
	_set_low(true)
	var world := Spatial.new()
	add_child(world)
	var offscreen := Viewport.new()
	offscreen.name = "Offscreen"
	world.add_child(offscreen)
	offscreen.render_target_update_mode = Viewport.UPDATE_ALWAYS
	var container := ViewportContainer.new()
	container.name = "Container"
	world.add_child(container)
	var visible_vp := Viewport.new()
	visible_vp.name = "Visible"
	container.add_child(visible_vp)
	visible_vp.render_target_update_mode = Viewport.UPDATE_ALWAYS

	var optimizer = LowViewportOptimizerScript.new()
	optimizer.tree = get_tree()
	add_child(optimizer)
	assert_bool(optimizer.scan_now()).is_true()

	assert_int(offscreen.render_target_update_mode).is_equal(Viewport.UPDATE_DISABLED)
	assert_object(offscreen.get_node_or_null("LowHzRedraw")).is_null()
	assert_int(visible_vp.render_target_update_mode).is_equal(Viewport.UPDATE_DISABLED)
	var driver = visible_vp.get_node_or_null("LowHzRedraw")
	assert_object(driver).is_not_null()
	# El driver despierta el Viewport a ~10 Hz, no en cada frame.
	if driver != null:
		visible_vp.render_target_update_mode = Viewport.UPDATE_DISABLED
		driver.call("_process", 0.03)
		assert_int(visible_vp.render_target_update_mode).is_equal(Viewport.UPDATE_DISABLED)
		driver.call("_process", 0.03)
		assert_int(visible_vp.render_target_update_mode).is_equal(Viewport.UPDATE_DISABLED)
		driver.call("_process", 0.05)
		assert_int(visible_vp.render_target_update_mode).is_equal(Viewport.UPDATE_ONCE)

	# El censo lista los dos con su veredicto.
	var censo: Array = optimizer.report()
	assert_int(censo.size()).is_equal(2)

	optimizer.restore_all()
	assert_int(offscreen.render_target_update_mode).is_equal(Viewport.UPDATE_ALWAYS)
	assert_int(visible_vp.render_target_update_mode).is_equal(Viewport.UPDATE_ALWAYS)
	assert_object(visible_vp.get_node_or_null("LowHzRedraw")).is_null()

	optimizer.queue_free()
	world.queue_free()


# Tarea KK: si un dueno externo (terminal con foco) vuelve a pedir UPDATE_ALWAYS, el
# optimizador cede: le saca su driver y no vuelve a pisarlo en la sesion.
func test_viewport_optimizer_yields_to_external_always() -> void:
	_set_low(true)
	var world := Spatial.new()
	add_child(world)
	var container := ViewportContainer.new()
	world.add_child(container)
	var vp := Viewport.new()
	container.add_child(vp)
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS

	var optimizer = LowViewportOptimizerScript.new()
	optimizer.tree = get_tree()
	add_child(optimizer)
	optimizer.scan_now()
	assert_object(vp.get_node_or_null("LowHzRedraw")).is_not_null()

	# El dueno externo lo vuelve a poner en ALWAYS (cursor suave del terminal con foco).
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	optimizer.scan_now()
	assert_object(vp.get_node_or_null("LowHzRedraw")).is_null()
	assert_int(vp.render_target_update_mode).is_equal(Viewport.UPDATE_ALWAYS)
	# Y no se re-gestiona en el barrido siguiente.
	optimizer.scan_now()
	assert_object(vp.get_node_or_null("LowHzRedraw")).is_null()
	assert_int(vp.render_target_update_mode).is_equal(Viewport.UPDATE_ALWAYS)

	optimizer.queue_free()
	world.queue_free()


# Tarea KK: fuera del tier LOW (o con el A/B en 0) el optimizador no toca NADA: los Viewports
# siguen en UPDATE_ALWAYS y sin driver.
func test_viewport_optimizer_noop_outside_low() -> void:
	_set_low(false)
	var world := Spatial.new()
	add_child(world)
	var vp := Viewport.new()
	world.add_child(vp)
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS

	var optimizer = LowViewportOptimizerScript.new()
	optimizer.tree = get_tree()
	add_child(optimizer)
	assert_bool(optimizer.scan_now()).is_false()
	assert_int(vp.render_target_update_mode).is_equal(Viewport.UPDATE_ALWAYS)
	assert_object(vp.get_node_or_null("LowHzRedraw")).is_null()

	# Con el tier LOW pero el A/B en 0 tampoco.
	_set_low(true)
	OS.set_environment(LowUiOptScript.ENV, "0")
	assert_bool(optimizer.scan_now()).is_false()
	assert_int(vp.render_target_update_mode).is_equal(Viewport.UPDATE_ALWAYS)
	OS.set_environment(LowUiOptScript.ENV, "")

	optimizer.queue_free()
	world.queue_free()


# Tarea MM: un Viewport que un dueno dejo en UPDATE_WHEN_VISIBLE (la pantalla de un terminal
# visible fuera de foco) tambien entra en la politica LOW: DISABLED + driver de 10 Hz, y si el
# dueno lo vuelve a poner en WHEN_VISIBLE el optimizador lo re-coerciona en vez de dejarlo al
# refresco por frame. Fuera de LOW se respeta el modo original.
func test_viewport_optimizer_spaces_when_visible_in_low() -> void:
	_set_low(true)
	var world := Spatial.new()
	add_child(world)
	var container := ViewportContainer.new()
	world.add_child(container)
	var vp := Viewport.new()
	container.add_child(vp)
	vp.render_target_update_mode = Viewport.UPDATE_WHEN_VISIBLE

	var optimizer = LowViewportOptimizerScript.new()
	optimizer.tree = get_tree()
	add_child(optimizer)
	optimizer.scan_now()
	assert_int(vp.render_target_update_mode).is_equal(Viewport.UPDATE_DISABLED)
	assert_object(vp.get_node_or_null("LowHzRedraw")).is_not_null()

	# El dueno lo devuelve a WHEN_VISIBLE: el optimizador no lo deja al refresco por frame.
	vp.render_target_update_mode = Viewport.UPDATE_WHEN_VISIBLE
	optimizer.scan_now()
	assert_int(vp.render_target_update_mode).is_equal(Viewport.UPDATE_DISABLED)
	assert_object(vp.get_node_or_null("LowHzRedraw")).is_not_null()

	# Restaurar devuelve el modo EXACTO con el que entro (WHEN_VISIBLE).
	optimizer.restore_all()
	assert_int(vp.render_target_update_mode).is_equal(Viewport.UPDATE_WHEN_VISIBLE)
	assert_object(vp.get_node_or_null("LowHzRedraw")).is_null()

	# Fuera de LOW no se toca.
	_set_low(false)
	vp.render_target_update_mode = Viewport.UPDATE_WHEN_VISIBLE
	assert_bool(optimizer.scan_now()).is_false()
	assert_int(vp.render_target_update_mode).is_equal(Viewport.UPDATE_WHEN_VISIBLE)

	optimizer.queue_free()
	world.queue_free()


# Tarea MM: en LOW la pantalla del terminal (HoloTerminalV2) baja la resolucion de su Viewport
# y, visible fuera de foco, no se redibuja en frames consecutivos: solo pulsa UPDATE_ONCE cada
# ~0.1 s. Con foco vuelve a tasa completa (UPDATE_ALWAYS) y fuera de LOW queda como siempre.
func test_terminal_viewport_reduced_and_spaced_in_low() -> void:
	_set_low(true)
	var terminal = WallTerminalScene.instance()
	add_child(terminal)
	yield(get_tree(), "idle_frame")
	var vp: Viewport = terminal.get_node("Viewport")
	assert_object(vp).is_not_null()
	var nominal: Vector2 = terminal.screen_resolution
	terminal._apply_viewport_settings()
	assert_float(vp.size.x).is_less(nominal.x)
	assert_float(vp.size.y).is_less(nominal.y)
	assert_float(vp.size.x).is_less_equal(ceil(nominal.x * 0.5))
	# El cursor vive en pixeles del Viewport: quedo reencuadrado al tamaño reducido.
	if vp.has_method("get_cursor_position"):
		var cursor: Vector2 = vp.get_cursor_position()
		assert_float(cursor.x).is_less_equal(vp.size.x)
		assert_float(cursor.y).is_less_equal(vp.size.y)

	# Visible fuera de foco en LOW: un pulso y despues no vuelve a redibujar solo.
	terminal.is_active = true
	terminal.anim_progress = 1.0
	terminal.target_progress = 1.0
	terminal._is_focused = false
	terminal._visual_delta = 0.0
	terminal._update_visuals()
	assert_int(vp.render_target_update_mode).is_equal(Viewport.UPDATE_ONCE)
	terminal._update_visuals()
	assert_int(vp.render_target_update_mode).is_equal(Viewport.UPDATE_ONCE)
	# Pasado el intervalo, el proximo tick vuelve a pedir un unico render.
	terminal._visual_delta = 0.2
	terminal._update_visuals()
	assert_int(vp.render_target_update_mode).is_equal(Viewport.UPDATE_ONCE)

	# Con foco: tasa completa.
	terminal._is_focused = true
	terminal._visual_delta = 0.0
	terminal._update_visuals()
	assert_int(vp.render_target_update_mode).is_equal(Viewport.UPDATE_ALWAYS)

	# Fuera de LOW vuelve el refresco por frame y la resolucion nominal.
	terminal._is_focused = false
	_set_low(false)
	terminal._update_visuals()
	assert_int(vp.render_target_update_mode).is_equal(Viewport.UPDATE_WHEN_VISIBLE)
	terminal._apply_viewport_settings()
	assert_vector2(vp.size).is_equal(nominal)

	terminal.queue_free()


# Tarea NN: en LOW la criocapsula no monta el canvas ImGui: queda el camino clasico de
# _draw a 10 Hz (mismo contenido, sin el frame de ImGui por tick). Fuera de LOW se monta
# CryoPodImGui como siempre (con ImGuiCanvas en el motor).
func test_cryopod_ui_uses_classic_path_in_low() -> void:
	_set_low(true)
	var ui = CryoPodUIScene.instance()
	add_child(ui)
	yield(get_tree(), "idle_frame")
	assert_object(ui.get("_imgui_screen")).is_null()
	assert_object(get_node_or_null("CryoPodImGui")).is_null()
	assert_bool(ui.get_node("HatchButton").visible).is_true()
	ui.free()

	if not ClassDB.class_exists("ImGuiCanvas"):
		_set_low(false)
		return

	_set_low(false)
	var ui_imgui = CryoPodUIScene.instance()
	add_child(ui_imgui)
	yield(get_tree(), "idle_frame")
	var canvas = get_node_or_null("CryoPodImGui")
	assert_object(ui_imgui.get("_imgui_screen")).is_not_null()
	assert_object(canvas).is_not_null()
	assert_bool(ui_imgui.get_node("HatchButton").visible).is_false()
	if canvas != null:
		canvas.free()
	ui_imgui.free()


# Tarea NN: el input deja de rearmar el frame de ImGui en LOW (lo unico que lo arma es
# update_hz); fuera de LOW conserva la tasa pedida.
func test_imgui_input_hz_throttled_in_low() -> void:
	_set_low(true)
	assert_float(LowUiOptScript.imgui_input_hz()).is_equal(0.0)
	assert_float(LowUiOptScript.imgui_input_hz(15.0)).is_equal(0.0)
	OS.set_environment(LowUiOptScript.ENV, "0")
	assert_float(LowUiOptScript.imgui_input_hz()).is_equal(30.0)
	OS.set_environment(LowUiOptScript.ENV, "")
	_set_low(false)
	assert_float(LowUiOptScript.imgui_input_hz()).is_equal(30.0)
	assert_float(LowUiOptScript.imgui_input_hz(15.0)).is_equal(15.0)
