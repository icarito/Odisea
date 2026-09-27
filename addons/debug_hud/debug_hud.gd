extends Node

# debug_hud.gd - Autoload "DebugHud": integra el HUD de debug de gdtk en Odisea
# (colector de metricas + vista ImGui opcional). Port de gdtk/addons/debug_hud/
# (ver SPEC-hud.md y SPEC-hud-remote.md en /run/media/.../gdtk), adaptado a:
#
# - El colector (DebugMetrics, debug_metrics.gd) corre siempre que el HUD este
#   habilitado, SIN depender de ImGui: funciona igual en el binario pinneado de
#   Odisea (v0.5.3, sin modulo imgui) que en el del fork con gdtk.
# - La vista ImGui (debug_hud_view.gd, `extends ImGuiCanvas`) solo se instancia si
#   `ClassDB.class_exists("ImGuiCanvas")` Y la politica render_local lo permite. Sin
#   preload (rompe la compilacion del .gd en el binario sin el modulo, ver la nota de
#   CryoPodUI.gd._build_imgui_screen): `load()` diferido, dentro de _build_view().
# - Politica render_local (pedida por la tarea):
#     not (GLES3VendorGate.is_low_tier() and GLES3VendorGate.is_flat_mode())
#   con override por env ODISEA_DEBUG_HUD_LOCAL=0|1 (gana sobre el gate).
# - Todo el sistema (colector incluido) apagado en builds release salvo
#   OS.is_debug_build() o ProjectSettings "debug_hud/enabled_in_release" = true.
# - Tecla: F1 (accion de input "toggle_debug_hud"), NO backtick: Odisea ya usa
#   backtick para "toggle_debug_console" (OYS_Console, consola diegetica in-world).
#   Este HUD es un overlay de ingenieria (FPS/frame time/draw calls/memoria), no
#   reemplaza ni duplica esa consola de comandos: solo expone Graficas y Monitores,
#   sin linea de comando propia.
# - El resumen para el telefono NO pasa por aca: lo arma
#   core_v2/things/DebugHudScreen.gd (HUDableComponent) leyendo metrics.latest/tail(),
#   y viaja por el canal HUDable/SuitOS existente (no por el transporte TCP propio de
#   gdtk, que Odisea no necesita: ya tiene su propio control remoto).

const DebugMetrics = preload("res://addons/debug_hud/debug_metrics.gd")
const DebugHudScreen = preload("res://core_v2/things/DebugHudScreen.gd")
const ViewScriptPath := "res://addons/debug_hud/debug_hud_view.gd"

var enabled := false
var visible := false setget _set_visible
var render_local := true

var metrics = null # DebugMetrics local; nunca null si enabled == true

var _view: Node = null
var _policy_resolved := false


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	enabled = _resolve_enabled()
	if not enabled:
		set_process(false)
		return
	metrics = DebugMetrics.new()
	_build_screen()


func _process(_delta: float) -> void:
	if metrics == null:
		return
	metrics.sample()
	if not _policy_resolved:
		_resolve_render_local()
	if render_local and _view == null and ClassDB.class_exists("ImGuiCanvas"):
		_build_view()


# --- politica de habilitado / vista local -----------------------------------------

func _resolve_enabled() -> bool:
	if OS.is_debug_build():
		return true
	if ProjectSettings.has_setting("debug_hud/enabled_in_release"):
		return bool(ProjectSettings.get_setting("debug_hud/enabled_in_release"))
	return false


func _resolve_render_local() -> void:
	var value := true
	var gate = get_node_or_null("/root/GLES3VendorGate")
	if gate != null and gate.has_method("is_low_tier") and gate.has_method("is_flat_mode"):
		value = not (bool(gate.is_low_tier()) and bool(gate.is_flat_mode()))
	var env: String = OS.get_environment("ODISEA_DEBUG_HUD_LOCAL")
	if env == "0":
		value = false
	elif env == "1":
		value = true
	render_local = value
	_policy_resolved = true
	print("DebugHud: render_local=", value)


func _build_screen() -> void:
	var screen := DebugHudScreen.new()
	screen.name = "DebugHudScreen"
	screen.hud = self
	add_child(screen)


func _build_view() -> void:
	var script = load(ViewScriptPath)
	if script == null:
		return
	var view = script.new()
	view.name = "DebugHudView"
	view.hud = self
	get_tree().root.add_child(view)
	_view = view


func _set_visible(value: bool) -> void:
	visible = value
	if _view != null:
		_view.visible = value


# --- API para la pantalla HUDable / tests -----------------------------------------

func snapshot(since_frame: int = -1) -> Dictionary:
	if metrics == null:
		return {}
	return metrics.snapshot(since_frame)


# Resumen chico (no el snapshot completo) para widget_snapshot() de DebugHudScreen.
func summary() -> Dictionary:
	if metrics == null:
		return {}
	var latest: Dictionary = metrics.latest
	return {
		"fps": latest.get("TIME_FPS", 0.0),
		"frame_ms": latest.get("TIME_PROCESS", 0.0),
		"draw_calls": latest.get("RENDER_DRAW_CALLS_IN_FRAME", 0.0),
		"vertices": latest.get("RENDER_VERTICES_IN_FRAME", 0.0),
		"memory_mb": latest.get("MEMORY_STATIC", 0.0),
		"nodes": latest.get("OBJECT_NODE_COUNT", 0.0),
	}


# Series cortas (para un sparkline chico, no el buffer de 600 muestras completo).
func series_tail(name: String, n: int = 20) -> Array:
	if metrics == null:
		return []
	return metrics.tail(name, n)
