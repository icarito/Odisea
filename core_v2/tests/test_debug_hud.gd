extends GdUnitTestSuite

# test_debug_hud.gd - Cobertura del port de gdtk addons/debug_hud/ a Odisea:
# - el colector (DebugMetrics) funciona sin ImGui.
# - la politica render_local de DebugHud.gd (low_tier + flat -> false, env gana).
# - el snapshot de la pantalla HUDable "system:performance" (DebugHudScreen).

const DebugMetricsScript = preload("res://addons/debug_hud/debug_metrics.gd")
const GateScript = preload("res://core_v2/autoloads/GLES3VendorGate.gd")
const DebugHudWidgetScene = preload("res://core_v2/ui/hud/DebugHudWidget.tscn")

const ENV_OVERRIDE := "ODISEA_DEBUG_HUD_LOCAL"

var _gate # /root/GLES3VendorGate real: se restaura en after_test
var _saved_force_gate := false
var _saved_unshaded_mode := ""
var _saved_env := ""
var _had_env := false


func before_test() -> void:
	_gate = get_node_or_null("/root/GLES3VendorGate")
	if _gate != null:
		_saved_force_gate = bool(_gate.force_gate)
		_saved_unshaded_mode = String(_gate.get("_unshaded_mode"))
	_had_env = OS.has_environment(ENV_OVERRIDE)
	_saved_env = OS.get_environment(ENV_OVERRIDE)
	OS.set_environment(ENV_OVERRIDE, "")


func after_test() -> void:
	if _gate != null:
		_gate.force_gate = _saved_force_gate
		_gate.set("_unshaded_mode", _saved_unshaded_mode)
	OS.set_environment(ENV_OVERRIDE, _saved_env if _had_env else "")


# --- Colector sin ImGui --------------------------------------------------------

func test_debug_metrics_samples_and_snapshots_without_imgui() -> void:
	var metrics = auto_free(DebugMetricsScript.new())
	metrics.sample()
	metrics.sample()

	var snap: Dictionary = metrics.snapshot()
	assert_dict(snap).contains_keys(["frame", "time", "series", "latest", "logs", "profile"])
	assert_int(int(snap["frame"])).is_equal(2)
	assert_bool(snap["latest"].has("TIME_FPS")).is_true()
	assert_bool(snap["latest"].has("RENDER_DRAW_CALLS_IN_FRAME")).is_true()

	# JSON-safety: esto es lo que viajaria si algo lo mandara por un canal serializado.
	var json_text := JSON.print(snap)
	assert_bool(json_text.empty()).is_false()
	assert_int(JSON.parse(json_text).error).is_equal(OK)


func test_debug_metrics_tail_returns_last_n_samples() -> void:
	var metrics = auto_free(DebugMetricsScript.new())
	for i in range(5):
		metrics.sample()
	var tail: Array = metrics.tail("TIME_FPS", 3)
	assert_int(tail.size()).is_equal(3)
	var full: Array = metrics.tail("TIME_FPS", 100)
	assert_int(full.size()).is_equal(5)


# --- Politica render_local ------------------------------------------------------

func test_render_local_false_when_low_tier_and_flat() -> void:
	if _gate == null:
		return # entorno sin GLES3VendorGate (no deberia pasar en Odisea, pero no romper el runner)
	_gate.force_gate = true
	_gate.set("_unshaded_mode", "1")

	var hud = get_node_or_null("/root/DebugHud")
	assert_object(hud).is_not_null()
	hud._policy_resolved = false
	hud._resolve_render_local()

	assert_bool(hud.render_local).is_false()


func test_render_local_true_when_not_low_tier_or_not_flat() -> void:
	if _gate == null:
		return
	_gate.force_gate = false
	_gate.set("_unshaded_mode", "")

	var hud = get_node_or_null("/root/DebugHud")
	assert_object(hud).is_not_null()
	hud._policy_resolved = false
	hud._resolve_render_local()

	assert_bool(hud.render_local).is_true()


func test_env_override_wins_over_gate() -> void:
	if _gate == null:
		return
	_gate.force_gate = true
	_gate.set("_unshaded_mode", "1") # gate diria "false"

	var hud = get_node_or_null("/root/DebugHud")
	assert_object(hud).is_not_null()

	OS.set_environment(ENV_OVERRIDE, "1")
	hud._policy_resolved = false
	hud._resolve_render_local()
	assert_bool(hud.render_local).is_true()

	OS.set_environment(ENV_OVERRIDE, "0")
	hud._policy_resolved = false
	hud._resolve_render_local()
	assert_bool(hud.render_local).is_false()


# --- Pantalla HUDable "system:performance" --------------------------------------

func test_debug_hud_screen_registers_and_snapshots() -> void:
	var hud = get_node_or_null("/root/DebugHud")
	assert_object(hud).is_not_null()
	if hud.metrics == null:
		return # DebugHud deshabilitado (release sin opt-in): nada que probar

	var screen = hud.get_node_or_null("DebugHudScreen")
	assert_object(screen).is_not_null()

	# Sin jugador (menú principal) no se registra: si no, enciende el overlay de SuitOS.
	if get_tree().get_nodes_in_group("player").empty():
		screen._sync_registration()
		assert_bool(SuitOS.has_screen("system:performance")).is_false()

	# Con un jugador en la escena sí.
	var fake_player := Node.new()
	fake_player.add_to_group("player")
	add_child(fake_player)
	screen._sync_registration()
	assert_bool(SuitOS.has_screen("system:performance")).is_true()

	hud.metrics.sample()
	hud.metrics.sample()
	var snap: Dictionary = screen.widget_snapshot()

	assert_dict(snap).contains_keys(["proto", "id", "title", "source",
		"fps", "frame_ms", "draw_calls", "vertices", "memory_mb", "nodes",
		"fps_series", "frame_ms_series"])
	assert_str(String(snap["id"])).is_equal("system:performance")
	assert_bool((snap["fps_series"] as Array).size() <= 20).is_true()

	# JSON-safety y tamano: el resumen tiene que ser chico, no el buffer de 600 muestras.
	var json_text := JSON.print(snap)
	assert_int(JSON.parse(json_text).error).is_equal(OK)
	assert_bool(json_text.length() < 2000).is_true()

	remove_child(fake_player)
	fake_player.free()
	screen._sync_registration()


# --- Paso "Rendimiento diegetico" ------------------------------------------------

# La pantalla propia (view_scene) solo existe con el modulo ImGui; sin el, sigue sin vista
# propia como antes de este paso (widget ampliado, sin regresion).
func test_debug_hud_screen_view_gated_by_imgui() -> void:
	var hud = get_node_or_null("/root/DebugHud")
	assert_object(hud).is_not_null()
	var screen = hud.get_node_or_null("DebugHudScreen")
	assert_object(screen).is_not_null()

	if ClassDB.class_exists("ImGuiCanvas"):
		assert_object(screen.view_scene()).override_failure_message(
			"con ImGuiCanvas disponible DebugHudScreen deberia declarar su vista propia").is_not_null()
	else:
		assert_object(screen.view_scene()).override_failure_message(
			"sin ImGuiCanvas no deberia haber vista propia: cae al widget ampliado").is_null()
	assert_vector2(screen.view_size()).is_equal(Vector2(640.0, 460.0))


# El widget de slot monta DebugHudWidgetImGui solo si el modulo esta disponible, y esconde
# los Label viejos para no duplicar; el widget_snapshot que llega al telefono no cambia.
func test_debug_hud_widget_imgui_child_gated_by_module() -> void:
	var widget = DebugHudWidgetScene.instance()
	add_child(widget)
	auto_free(widget)
	yield(get_tree(), "idle_frame")

	var imgui_child = widget.get_node_or_null("DebugHudWidgetImGui")
	if ClassDB.class_exists("ImGuiCanvas"):
		assert_object(imgui_child).override_failure_message(
			"con ImGuiCanvas disponible el widget deberia montar DebugHudWidgetImGui").is_not_null()
		var margin = widget.get_node_or_null("Margin")
		assert_bool(margin.visible).override_failure_message(
			"los Label viejos deberian esconderse en modo ImGui").is_false()
	else:
		assert_object(imgui_child).override_failure_message(
			"sin ImGuiCanvas no deberia existir DebugHudWidgetImGui: cae a los Label").is_null()

	widget.update_snapshot({"fps": 58.0, "frame_ms": 17.2, "draw_calls": 120.0,
		"vertices": 4000.0, "memory_mb": 210.0, "nodes": 640.0, "source": "online",
		"fps_series": [58.0, 59.0, 60.0]})
	assert_float(float(widget.snapshot().get("fps", 0.0))).is_equal(58.0)
