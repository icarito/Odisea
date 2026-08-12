extends SceneTree

# Verifica que una UI mantenga su tamaño relativo a la pantalla cuando baja la escala
# de render (UIScaleCompensator). Uso:
#   godot3-bin --path . -s res://tools/check_ui_scale.gd

func _init():
	call_deferred("_run")

func _run():
	var settings = root.get_node_or_null("SettingsManager")
	if settings == null:
		printerr("[ui] SettingsManager no disponible")
		quit(1)
		return
	settings.render_resolution = Vector2(640, 480)

	var menu = load("res://scenes/Menu.tscn").instance()
	root.add_child(menu)
	current_scene = menu
	var settle = _wait(30)
	if settle is GDScriptFunctionState:
		yield(settle, "completed")

	var boton = menu.find_node("NewGame")
	if boton == null:
		printerr("[ui] no se encontro el boton NewGame")
		quit(1)
		return

	for scale in [1.0, 0.75, 0.6]:
		settings.render_scale = scale
		settings.apply_render_resolution()
		var step = _wait(20)
		if step is GDScriptFunctionState:
			yield(step, "completed")
		var vp: Vector2 = root.get_visible_rect().size
		var en_pantalla: Vector2 = boton.rect_size * boton.get_global_transform_with_canvas().get_scale()
		print("[ui] scale=%.2f  viewport=%s  menu=%s x%s  boton=%s  fraccion_alto=%.3f" % [
			scale, str(vp), str(menu.rect_size), str(menu.rect_scale),
			str(en_pantalla), en_pantalla.y / vp.y
		])
	quit(0)

func _wait(frames: int):
	var i := 0
	while i < frames:
		yield(self, "idle_frame")
		i += 1
