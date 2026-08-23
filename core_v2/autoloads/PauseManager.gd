extends Node

var pause_menu_scene_path = "res://core_v2/ui/PauseMenu.tscn"
var pause_menu_instance = null
var _uptime_frames: int = 0
var _paused_by_focus: bool = false

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	get_tree().set_quit_on_go_back(false)

func _process(_delta: float) -> void:
	if _uptime_frames < 120:
		_uptime_frames += 1

func _notification(what: int) -> void:
	# En Android el botón "back" envía WM_GO_BACK_REQUEST. Lo interceptamos para
	# abrir/cerrar el menú de pausa en vez de salir de la app.
	if what == MainLoop.NOTIFICATION_WM_GO_BACK_REQUEST:
		print("[PauseManager] WM_GO_BACK_REQUEST -> toggle pause")
		_toggle_pause()
	# Al perder el foco de la ventana (alt-tab, cambio de app, etc.) pausamos el
	# juego en vez de solo silenciar el audio. El AudioManager ya silencia con su
	# propio handler de foco; aquí detenemos la simulación. No reanudamos solo con
	# FOCUS_IN: el jugador decide cuándo continuar desde el menú de pausa, evitando
	# reanudar por un rebote de foco del compositor.
	elif what == MainLoop.NOTIFICATION_WM_FOCUS_OUT:
		_pause_on_focus_loss()
	elif what == MainLoop.NOTIFICATION_WM_FOCUS_IN:
		_on_focus_in()

func _can_pause_in_current_scene() -> bool:
	var current_scene = get_tree().current_scene
	if current_scene == null:
		return false
	var fname := String(current_scene.filename)
	# No pausar en el menú principal ni en el boot.
	return fname.find("Menu.tscn") == -1 and fname.find("Boot.tscn") == -1

func _pause_on_focus_loss() -> void:
	if get_tree().paused:
		return
	if _uptime_frames < 120:
		return
	if _is_automated_run():
		return
	if not _can_pause_in_current_scene():
		return
	_paused_by_focus = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh_mobile_ui()

func _on_focus_in() -> void:
	if _paused_by_focus:
		pause()

func _is_automated_run() -> bool:
	if OS.has_feature("Server"):
		return true
	if Engine.has_singleton("GdUnit3") and Engine.get_singleton("GdUnit3").is_test_suite():
		return true
	if OS.get_environment("ANNA_RL_MODE").to_lower() in ["1", "true", "yes", "on"]:
		return true
	return false

func _input(event):
	if not event.is_action_pressed("ui_cancel"):
		return
	if not _can_pause_in_current_scene():
		return
	if get_tree().paused:
		call_deferred("_toggle_pause")
		get_tree().set_input_as_handled()
		return
	call_deferred("_toggle_pause")
	get_tree().set_input_as_handled()

func _toggle_pause() -> void:
	if not _can_pause_in_current_scene():
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
			var canvas = CanvasLayer.new()
			canvas.layer = 50
			canvas.name = "PauseMenuLayer"
			get_tree().root.call_deferred("add_child", canvas)
			canvas.call_deferred("add_child", pause_menu_instance)
			# Defer the rest until the child is added
			call_deferred("_finish_pause")
			return
		else:
			printerr("[PauseManager] No se pudo cargar PauseMenu.tscn")
			return

	_finish_pause()

func _finish_pause() -> void:
	if pause_menu_instance == null:
		return
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	pause_menu_instance.show()
	if pause_menu_instance.has_method("on_show"):
		pause_menu_instance.on_show()
	_refresh_mobile_ui()

func resume():
	_paused_by_focus = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if pause_menu_instance:
		pause_menu_instance.hide()
	_refresh_mobile_ui()

func _refresh_mobile_ui() -> void:
	# Show/hide the on-screen touch controls in sync with pause state. They live on
	# a high CanvasLayer and would intercept the touches meant for the pause menu.
	var mobile = get_node_or_null("/root/MobileUIManager")
	if mobile and mobile.has_method("refresh_for_pause"):
		mobile.refresh_for_pause()
