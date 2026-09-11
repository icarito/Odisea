extends ConfirmationDialog

# RemotePairingDialog.gd - Confirmation dialog shown on the host when a phone attempts to pair.

signal pairing_completed(accepted)

onready var device_label: Label = $VBoxContainer/DeviceLabel
onready var pin_label: Label = $VBoxContainer/PinLabel
onready var timer_label: Label = $VBoxContainer/TimerLabel

var _callback: FuncRef = null
var _time_left: float = 30.0
var _active: bool = false

func _ready():
	window_title = "Control remoto"
	get_ok().text = "Permitir"
	get_cancel().text = "Rechazar"
	preload("res://core_v2/ui/DialogButtons.gd").fit_for_touch(self)
	connect("confirmed", self, "_on_confirmed")
	connect("popup_hide", self, "_on_popup_hide")

func prompt_pairing(device_name: String, pin: String, callback: FuncRef = null) -> void:
	_callback = callback
	_time_left = 30.0
	_active = true

	if device_label:
		device_label.text = "«%s» quiere controlar esta partida. Permita solo si muestra este mismo PIN:" % device_name
	if pin_label:
		pin_label.text = "PIN: %s" % pin
	if timer_label:
		timer_label.text = "Se rechaza sola en 30 s."

	popup_centered(Vector2(450, 220))

func _process(delta: float) -> void:
	if not _active:
		return
	_time_left -= delta
	if timer_label:
		timer_label.text = "Se rechaza sola en %d s." % int(max(0, ceil(_time_left)))

	if _time_left <= 0.0:
		_finish(false)

func _on_confirmed() -> void:
	_finish(true)

func _on_popup_hide() -> void:
	if _active:
		call_deferred("_reject_if_still_active")

func _reject_if_still_active() -> void:
	if _active:
		_finish(false)

func _finish(accepted: bool) -> void:
	if not _active:
		return
	_active = false
	hide()
	if _callback and _callback.is_valid():
		_callback.call_func(accepted)
	emit_signal("pairing_completed", accepted)
