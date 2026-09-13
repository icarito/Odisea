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

# El punto (en coordenadas de pantalla) cae sobre un boton visible y habilitado del widget: ese
# toque es del boton y no del widget. Hace falta porque la GUI de Godot 3 corta la propagacion en
# un control STOP solo para eventos de MOUSE: un ScreenTouch sobre el boton sigue hasta el widget.
static func pointer_on_button(widget: Node, point: Vector2) -> bool:
	for button in buttons_in(widget):
		if not button.is_visible_in_tree() or button.disabled:
			continue
		# El rect dibujado, con la escala del slot y la del contenedor, no el de layout.
		var xf: Transform2D = button.get_global_transform_with_canvas()
		if Rect2(xf.origin, button.rect_size * xf.get_scale()).has_point(point):
			return true
	return false

static func buttons_in(node: Node) -> Array:
	var found: Array = []
	for child in node.get_children():
		if child is BaseButton:
			found.append(child)
		found += buttons_in(child)
	return found

# Widget en modo pantalla, sin mouse: se navega entre sus botones con la navegacion de foco de la
# GUI (cruceta o flechas). Arranca en el primero que se pueda usar. true si enfoco alguno.
static func focus_first_button(widget: Node) -> bool:
	for button in buttons_in(widget):
		if button.is_visible_in_tree() and not button.disabled and button.focus_mode != Control.FOCUS_NONE:
			button.grab_focus()
			return true
	return false

# Oprime el boton enfocado del widget, como un clic (el toggle de la linterna).
static func press_focused_button(widget: Control) -> void:
	if not is_instance_valid(widget) or not widget.is_inside_tree():
		return
	var focused = widget.get_focus_owner()
	if not (focused is BaseButton) or not widget.is_a_parent_of(focused) or focused.disabled:
		return
	if focused.toggle_mode:
		focused.pressed = not focused.pressed
	focused.emit_signal("pressed")
