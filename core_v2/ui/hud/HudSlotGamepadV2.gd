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

# Fallback cuando el backend no expone is_hold_gameplay_app (p.ej. el control remoto):
# apps cuyo hold acciona la app y nunca abre el radial. Debe coincidir con SuitOS.
const HOLD_GAMEPLAY_APP_IDS := ["player:autonav", "player:thrusters", "player:rope"]

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
	# FD-324 F4: en un slot de una app de "mantener" de gameplay un tap abre su pantalla;
	# el hold acciona la app (nav assist / propulsores / cuerda) y no abre el radial.
	if _is_hold_gameplay_app_slot(slot):
		_open_screen(slot)
		return
	var screen = _screen(slot)
	if screen == null or not screen.has_method("hud_gamepad_actions"):
		# Slot vacio: abrir el radial fijado a ese slot para elegir que fijar.
		# Es la misma ruta que el hold del hombro; con un tap se llega en dos pasos
		# (elegir tool -> equiparlo). Igual en touch (botones de slot).
		_open_radial(slot)
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
	# El hold de una app de gameplay no abre el radial: acciona la app (FD-324 F4).
	if _is_hold_gameplay_app_slot(slot):
		return
	backend.open_hud_mode(true, "", slot)


func _is_hold_gameplay_app_slot(slot: int) -> bool:
	if slot < 0 or backend == null or not backend.has_method("slot_screen_id"):
		return false
	var screen_id: String = String(backend.slot_screen_id(slot))
	if screen_id.empty():
		return false
	if backend.has_method("is_hold_gameplay_app"):
		return bool(backend.is_hold_gameplay_app(screen_id))
	return screen_id in HOLD_GAMEPLAY_APP_IDS


func _open_screen(slot: int) -> void:
	if slot < 0 or backend == null or not backend.has_method("open_hud_mode"):
		return
	backend.open_hud_mode(false, String(backend.slot_screen_id(slot)), slot)
