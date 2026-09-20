extends Node

# HudSlotGamepadV2.gd - Hombros como slots de OdiseaOS tambien en gameplay (FD-304 revision
# 2026-09-19). Tap = accion principal del widget del slot; hold = radial fijado a ese slot.
#
# Determinista: se alimenta con UNA muestra de InputDataV2 por tick de fisica (InputDataV2.hud_slot,
# que sale de las acciones hud_slot_1..4 via InputProviderV2). No lee botones crudos ni relojes: el
# replay re-deriva el mismo tap/hold. El mismo nodo se cuelga del backend local (SuitOS) y del
# control remoto (RemoteHudBackend), asi el cableado es identico en los dos.

const HudTabGestureScript = preload("res://core_v2/ui/hud/HudTabGesture.gd")
const HudWidgetActionScript = preload("res://core_v2/ui/hud/HudWidgetAction.gd")

# Backend con la interfaz de SuitOS/RemoteHudBackend: slot_screen_id, has_screen, get_screen,
# is_hud_mode_active y open_hud_mode.
var backend: Node = null

var _gesture = HudTabGestureScript.new()
var _slot: int = -1
var _down: bool = false


func reset() -> void:
	_gesture = HudTabGestureScript.new()
	_slot = -1
	_down = false
	_show_hold(-1, 0.0)


# Una muestra del stream por tick de fisica. Devuelve el gesto decidido (HudTabGesture.*): NONE,
# TAP u HOLD. En modo HUD el input es del overlay, asi que aca solo se reinicia.
func tick(input) -> int:
	if backend == null or input == null:
		return HudTabGestureScript.NONE
	if backend.has_method("is_hud_mode_active") and backend.is_hud_mode_active():
		if _slot >= 0 or _down:
			reset()
		return HudTabGestureScript.NONE
	var pressed_slot: int = int(input.hud_slot) - 1
	var down: bool = pressed_slot >= 0 and pressed_slot == _slot
	if pressed_slot >= 0 and not _down:
		_slot = pressed_slot
		down = true
	var gesture: int = _gesture.feed(down)
	_down = down
	# El hold no puede ser invisible: barra al pie del slot, proporcional al tiempo (FD-304 §3.1).
	_show_hold(_slot if down else -1, _gesture.progress() if down else 0.0)
	if gesture == HudTabGestureScript.TAP:
		_show_hold(-1, 0.0)
		_run_primary(_slot)
	elif gesture == HudTabGestureScript.HOLD:
		_show_hold(-1, 0.0)
		_open_radial(_slot)
	return gesture


func _show_hold(slot: int, progress: float) -> void:
	var host = _widget_host()
	if host != null and host.has_method("set_hold_progress"):
		host.set_hold_progress(slot, progress)


func _widget_host():
	if backend != null and backend.has_method("get_widget_host"):
		return backend.get_widget_host()
	return null


func _screen(slot: int):
	if slot < 0 or backend == null or not backend.has_method("slot_screen_id"):
		return null
	var id: String = String(backend.slot_screen_id(slot))
	if not backend.has_screen(id):
		return null
	return backend.get_screen(id)


# La misma ruta que el boton del widget: HudWidgetAction.perform resuelve si la accion se ejecuta
# local (SuitOS) o viaja por el canal (RemoteControlHome.perform_hud_widget_action).
func _run_primary(slot: int) -> void:
	var screen = _screen(slot)
	if screen == null or not screen.has_method("hud_gamepad_actions"):
		return
	var id: String = String(backend.slot_screen_id(slot))
	for action in screen.hud_gamepad_actions():
		if not bool(action.get("confirm", false)) or not bool(action.get("enabled", true)):
			continue
		HudWidgetActionScript.perform(self, id, String(action.get("op", "")), {})
		return


func _open_radial(slot: int) -> void:
	if slot < 0 or backend == null or not backend.has_method("open_hud_mode"):
		return
	backend.open_hud_mode(true, "", slot)
