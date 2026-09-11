extends TouchActionButton

# TouchHudButton.gd - Boton tactil del modo HUD de OdiseaOS (FD-296 F3): en el telefono no
# hay TAB. Abre al SOLTAR y llama a SuitOS directo, sin accion de input. Si abriera al
# presionar, la pausa congela el _input del boton antes del release y queda trabado (lo
# mismo que MobileUIManager resuelve a mano para el joystick). Sale con el back de Android.
# Tap = ultima pantalla, hold (>= 0.4 s, el umbral de TAB) = radial.
# ponytail: el hold se mide con el reloj, no con el stream: el boton no aprieta ninguna accion
# (por eso no se traba) y no hay muestra grabada que contar. Si el modo HUD entra alguna vez
# al replay, el boton tendria que empujar hud_mode al stream como TAB.

const HOLD_MSEC := 400

var _pressed_at: int = 0

func _press() -> void:
	._press()
	_pressed_at = OS.get_ticks_msec()

func _release() -> void:
	._release()
	var suit_os: Node = get_node_or_null("/root/SuitOS")
	if suit_os != null:
		suit_os.open_hud_mode(OS.get_ticks_msec() - _pressed_at >= HOLD_MSEC)
