extends Node

var pause_menu_scene_path = "res://core_v2/ui/PauseMenu.tscn"
var pause_menu_instance = null

func _ready():
	pause_mode = PAUSE_MODE_PROCESS

func _notification(what: int) -> void:
	# En Android el botón "back" envía WM_GO_BACK_REQUEST y por defecto cierra la
	# app (quit_on_go_back). Lo interceptamos para abrir/cerrar el menú de pausa en
	# vez de salir. quit_on_go_back está desactivado en project.godot para que este
	# notification llegue sin que el motor cierre la app antes.
	if what == MainLoop.NOTIFICATION_WM_GO_BACK_REQUEST:
		_toggle_pause()

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()

func _toggle_pause() -> void:
	var current_scene = get_tree().current_scene
	if current_scene and (current_scene.filename.find("Menu.tscn") != -1 or current_scene.filename.find("Boot.tscn") != -1):
		return # No pausar en el menú principal ni en el boot

	if get_tree().paused:
		resume()
	else:
		# FD-234: Si no está pausado, pausar sin importar el modo del mouse.
		# Esto permite pausar si el mouse se liberó por otra UI o si el
		# jugador simplemente quiere pausar en cualquier momento.
		pause()

func pause():
	if pause_menu_instance == null:
		var scene = load(pause_menu_scene_path)
		if scene:
			pause_menu_instance = scene.instance()
			get_tree().root.add_child(pause_menu_instance)
		else:
			printerr("[PauseManager] No se pudo cargar PauseMenu.tscn")
			return

	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	pause_menu_instance.show()
	if pause_menu_instance.has_method("on_show"):
		pause_menu_instance.on_show()

func resume():
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if pause_menu_instance:
		pause_menu_instance.hide()
