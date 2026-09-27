extends "res://core_v2/ui/hud/HudWidget.gd"
class_name DebugHudWidget

# DebugHudWidget.gd - Widget de slot para DebugHudScreen ("system:performance").
#
# Diegetico (Paso "Rendimiento diegetico"): con ImGui disponible dibuja el mismo panel
# que los demas widgets de SuitOS (marco, Silkscreen, paleta de OdiseaOSTheme) en vez de
# los Label sueltos de Godot, con una mini curva de FPS (ImPlot, sin decoraciones,
# autofit) ademas de FPS/frame ms/draw calls. La lectura del telefono no cambia: sigue
# siendo el mismo widget_snapshot() chico (fps/frame_ms/draw_calls/memory_mb +
# fps_series de 20 puntos, ver DebugHudScreen.gd), asi que el control remoto -- que no
# trae el modulo -- sigue viendo los Label de siempre (ClassDB.class_exists da false
# ahi). load() diferido: precompilar DebugHudWidgetImGui.gd (extends ImGuiCanvas) rompe
# la compilacion del .gd en el binario sin el modulo, igual que CryoPodUI.
const DebugHudWidgetImGuiPath := "res://core_v2/ui/hud/DebugHudWidgetImGui.gd"

onready var _metrics_label: Label = get_node_or_null("Margin/VBox/MetricsLabel")
onready var _extra_label: Label = get_node_or_null("Margin/VBox/ExtraLabel")
onready var _margin: Control = get_node_or_null("Margin")

var _last_snapshot := {}
var _imgui_widget = null

func _ready() -> void:
	if ClassDB.class_exists("ImGuiCanvas"):
		call_deferred("_build_imgui_widget")

func _build_imgui_widget() -> void:
	var canvas_script = load(DebugHudWidgetImGuiPath)
	if canvas_script == null:
		return
	var canvas = canvas_script.new()
	canvas.name = "DebugHudWidgetImGui"
	canvas.widget = self
	add_child(canvas)
	if _margin != null:
		_margin.visible = false
	add_stylebox_override("panel", StyleBoxEmpty.new())
	_imgui_widget = canvas

func snapshot() -> Dictionary:
	return _last_snapshot

func default_title() -> String:
	return tr("Rendimiento")

func default_screen_id() -> String:
	return "system:performance"

func _render(snapshot: Dictionary) -> void:
	_last_snapshot = snapshot
	var fps: float = float(snapshot.get("fps", 0.0))
	var frame_ms: float = float(snapshot.get("frame_ms", 0.0))
	var draw_calls: float = float(snapshot.get("draw_calls", 0.0))
	var memory_mb: float = float(snapshot.get("memory_mb", 0.0))

	_set_dot(OdiseaOSTheme.STATE_ALARM if fps < 30.0 else OdiseaOSTheme.STATE_ACTIVE)
	if _metrics_label != null:
		_metrics_label.text = "%.0f FPS  %.1f ms" % [fps, frame_ms]
	if _extra_label != null:
		_extra_label.text = "draws %.0f  mem %.0f MB" % [draw_calls, memory_mb]

func _render_offline() -> void:
	_last_snapshot = {"source": "offline"}
	if _metrics_label != null:
		_metrics_label.text = "-- FPS  -- ms"
	if _extra_label != null:
		_extra_label.text = tr("OFFLINE")
