## Ajustes específicos para la exportación Web.
## Ubicación: scenes/scripts/system/ (utilitarios de plataforma)
## Coloca este script en el nodo raíz de tu escena principal (ether.tscn).

extends Node

func _ready() -> void:
	# Solo ejecutar en exportaciones Web
	if OS.has_feature("web"):
		# Fix: Forzar que el canvas use el tamaño completo de la ventana del navegador
		get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		
		# Esperar frames para que el DOM esté listo
		await get_tree().process_frame
		await get_tree().process_frame
		
		# Usar el tamaño de la ventana actual (que en Web es el tamaño del canvas HTML)
		var window_size = DisplayServer.window_get_size()
		get_tree().root.size = window_size
		
		print("[Web] Viewport configured: ", window_size)
		
		# Escuchar cambios de tamaño de ventana para ajustar dinámicamente
		get_tree().root.size_changed.connect(_on_window_resized)
		
		# Conectar señal de clic para intentar captura del cursor
		if not get_tree().root.gui_focus_changed.is_connected(_on_focus_changed):
			get_tree().root.gui_focus_changed.connect(_on_focus_changed)

func _on_window_resized() -> void:
	if OS.has_feature("web"):
		var new_size = DisplayServer.window_get_size()
		get_tree().root.size = new_size
		print("[Web] Window resized to: ", new_size)

func _on_focus_changed(_control) -> void:
	# Intentar capturar cursor cuando el juego tiene foco
	if OS.has_feature("web") and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	# Capturar cursor en primer clic/interacción
	if OS.has_feature("web"):
		if event is InputEventMouseButton and event.pressed:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event is InputEventKey and event.pressed:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
