extends "res://core_v2/ui/hud/HudWidget.gd"
class_name DebugHudWidget

# DebugHudWidget.gd - Widget de slot para DebugHudScreen ("system:performance").
#
# Controls simples (Label), no ImGui: este widget viaja tal cual al telefono
# (RemoteHudBackend.resolve_widget_scene carga la misma .tscn), y el HUD del control
# remoto ya es 100% Control -- meter ImGui aca solo complicaria sin ganar nada
# (rung "Controls simples como los otros widgets" de la tarea).

onready var _metrics_label: Label = get_node_or_null("Margin/VBox/MetricsLabel")
onready var _extra_label: Label = get_node_or_null("Margin/VBox/ExtraLabel")

func default_title() -> String:
	return tr("Rendimiento")

func default_screen_id() -> String:
	return "system:performance"

func _render(snapshot: Dictionary) -> void:
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
	if _metrics_label != null:
		_metrics_label.text = "-- FPS  -- ms"
	if _extra_label != null:
		_extra_label.text = tr("OFFLINE")
