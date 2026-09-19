extends PanelContainer
class_name CryoPodsWidget

# CryoPodsWidget.gd - El roster de la bahia de criocapsulas (FD-304 §10).
# Sin logica propia: solo dibuja widget_snapshot(). Lo mismo se ve en el HUD local y en el
# control remoto, que es de donde salen los datos cuando la bahia esta en el otro dispositivo.

const HudWidgetAction = preload("res://core_v2/ui/hud/HudWidgetAction.gd")

onready var _title_label: Label = get_node_or_null("Margin/VBox/Header/TitleLabel")
onready var _status_dot: ColorRect = get_node_or_null("Margin/VBox/Header/StatusDot")
onready var _summary_label: Label = get_node_or_null("Margin/VBox/SummaryLabel")
onready var _pod_label: Label = get_node_or_null("Margin/VBox/PodRow/PodLabel")
onready var _scan_button: Button = get_node_or_null("Margin/VBox/PodRow/ScanButton")

func _ready() -> void:
	if _scan_button != null and not _scan_button.is_connected("pressed", self, "_on_scan_pressed"):
		_scan_button.connect("pressed", self, "_on_scan_pressed")

func update_snapshot(snapshot: Dictionary) -> void:
	set_snapshot(snapshot)

func set_snapshot(snapshot: Dictionary) -> void:
	if _title_label != null:
		_title_label.text = tr(String(snapshot.get("title", "Criocápsulas")))
	var pods: Array = snapshot.get("pods", []) if typeof(snapshot.get("pods", [])) == TYPE_ARRAY else []
	var alarms: int = int(snapshot.get("alarms", 0))
	var offline: bool = String(snapshot.get("source", "online")) == "offline"

	if _status_dot != null:
		if offline:
			_status_dot.color = Color(0.5, 0.5, 0.5, 0.8)
		else:
			_status_dot.color = Color(1.0, 0.35, 0.2, 1.0) if alarms > 0 else Color(0.18, 0.88, 0.78, 0.9)
	if _scan_button != null:
		_scan_button.disabled = offline or pods.empty()

	if offline:
		if _summary_label != null:
			_summary_label.text = tr("OFFLINE")
		if _pod_label != null:
			_pod_label.text = "--"
		return

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
	HudWidgetAction.perform(self, "ship:cryopods", "scan")
