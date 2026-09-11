extends TouchActionButton

# TouchHudButton.gd - Boton tactil del modo HUD de OdiseaOS (FD-296 F3): en el telefono no
# hay TAB. Abre al SOLTAR y llama a SuitOS directo, sin accion de input. Si abriera al
# presionar, la pausa congela el _input del boton antes del release y queda trabado (lo
# mismo que MobileUIManager resuelve a mano para el joystick). Sale con el back de Android.

func _release() -> void:
	._release()
	var suit_os: Node = get_node_or_null("/root/SuitOS")
	if suit_os != null:
		suit_os.open_hud_mode()
