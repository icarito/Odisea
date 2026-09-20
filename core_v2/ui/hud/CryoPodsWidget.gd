extends "res://core_v2/ui/hud/HudWidget.gd"
class_name CryoPodsWidget

# CryoPodsWidget.gd - El roster de la bahia de criocapsulas (FD-304 §10).
# Sin logica propia: solo dibuja widget_snapshot(). Lo mismo se ve en el HUD local y en el
# control remoto, que es de donde salen los datos cuando la bahia esta en el otro dispositivo.

onready var _summary_label: Label = get_node_or_null("Margin/VBox/SummaryLabel")
onready var _pod_label: Label = get_node_or_null("Margin/VBox/PodRow/PodLabel")
onready var _scan_button: Button = get_node_or_null("Margin/VBox/PodRow/ScanButton")

func _ready() -> void:
	_bind_button(_scan_button, "_on_scan_pressed")

func default_title() -> String:
	return tr("Criocápsulas")

func default_screen_id() -> String:
	return "ship:cryopods"

func _render(snapshot: Dictionary) -> void:
	var pods: Array = snapshot.get("pods", []) if typeof(snapshot.get("pods", [])) == TYPE_ARRAY else []
	var alarms: int = int(snapshot.get("alarms", 0))

	_set_dot(OdiseaOSTheme.STATE_ALARM if alarms > 0 else OdiseaOSTheme.STATE_ACTIVE)
	if _scan_button != null:
		_scan_button.disabled = pods.empty()

	var occupied: int = 0
	for pod in pods:
		if not String(pod.get("occupant", "")).empty():
			occupied += 1
	if _summary_label != null:
		# Sin roster declarado no se afirma ocupacion: decir "0/28 OCUP" en un arca de criogenia
		# seria decir algo falso. Se informa lo que se sabe, que es cuantas capsulas hay.
		var head: String = tr("%d/%d OCUP") % [occupied, pods.size()] if occupied > 0 \
			else tr("%d CÁPSULAS") % pods.size()
		_summary_label.text = tr("%s · %d ALERTA") % [head, alarms] if alarms > 0 else tr("%s · NOMINAL") % head
	if _pod_label != null:
		_pod_label.text = _format_pod(pods, int(snapshot.get("focused", 0)))

func _render_offline() -> void:
	if _scan_button != null:
		_scan_button.disabled = true
	if _summary_label != null:
		_summary_label.text = tr("OFFLINE")
	if _pod_label != null:
		_pod_label.text = "--"

func _format_pod(pods: Array, focused: int) -> String:
	if pods.empty():
		return "--"
	var pod: Dictionary = pods[int(clamp(focused, 0, pods.size() - 1))]
	var occupant: String = String(pod.get("occupant", ""))
	return "%s  %s  %s" % [
		String(pod.get("id", "?")),
		occupant if not occupant.empty() else tr("VACÍA"),
		tr(String(pod.get("status", "NOMINAL")))]

func _on_scan_pressed() -> void:
	_perform("scan")
