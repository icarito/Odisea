extends Reference

# HudWidgetAction.gd - A donde manda su accion un widget del HUD (FD-296 F4).
#
# El widget no sabe si lo monto el HUD local o el control remoto. En el control la
# pantalla vive en el otro dispositivo: llamar al SuitOS de aca no hacia nada (no tiene
# ninguna pantalla registrada), y por eso el boton de la linterna no encendia nada.
# Se le pregunta al arbol: si algun ancestro sabe despachar la accion (el control remoto,
# que la manda por el canal), va por ahi; si no, al SuitOS local, como siempre.

static func perform(from: Node, screen_id: String, op: String, args: Dictionary = {}) -> void:
	var node: Node = from
	while is_instance_valid(node):
		if node.has_method("perform_hud_widget_action"):
			node.perform_hud_widget_action(screen_id, op, args)
			return
		node = node.get_parent()

	if from.has_node("/root/SuitOS"):
		var suit_os = from.get_node("/root/SuitOS")
		if suit_os.has_method("perform_action"):
			suit_os.perform_action(screen_id, op, args)
