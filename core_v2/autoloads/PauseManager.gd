extends Node

var pause_menu_scene_path = "res://core_v2/ui/PauseMenu.tscn"
var pause_menu_instance = null

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	# La setting config/quit_on_go_back de project.godot no siempre basta para que
	# el SceneTree propague WM_GO_BACK_REQUEST a los nodos en 3.6; lo forzamos en
	# runtime (mismo patrón que SessionManager con set_auto_accept_quit para
	# WM_QUIT_REQUEST). Sin esto, en Android el back no cerraba la app pero tampoco
	# llegaba el notification -> no se abría la pausa.
	get_tree().set_quit_on_go_back(false)

func _notification(what: int) -> void:
	# En Android el botón "back" envía WM_GO_BACK_REQUEST. Lo interceptamos para
	# abrir/cerrar el menú de pausa en vez de salir de la app.
	if what == MainLoop.NOTIFICATION_WM_GO_BACK_REQUEST:
		print("[PauseManager] WM_GO_BACK_REQUEST -> toggle pause")
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
