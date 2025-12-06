# scripts/multiplayer/LocalMultiplayerManager.gd

extends Node

class_name LocalMultiplayerManager

# ===== NODOS =====
var level: Node
var viewport_p1: Viewport
var viewport_p2: Viewport
var player1: Node
var player2: Node
var camera_p1: Camera
var camera_p2: Camera
var camera_p2_proxy: Camera # Cámara proxy para el viewport del Jugador 2

# ===== CONFIG =====
export var level_scene_path := "res://scenes/levels/act1/Criogenia.tscn"
export var player_scene_path := "res://players/elias/Pilot.tscn"
export var shared_world := true
export var spawn_distance := 5.0

# ===== STATE =====
var is_running := false
var player_stats = {
	1: {"alive": true, "score": 0},
	2: {"alive": true, "score": 0}
}

func _ready() -> void:
	"""Inicializar copilot mode."""
	print("[LocalMultiplayerManager] Inicializando split-screen...")

	_setup_viewports()
	# El nivel y los jugadores se configuran en las siguientes funciones
	_setup_level()
	_setup_players()
	_setup_cameras()

	is_running = true
	
	var fps_label = Label.new()
	fps_label.name = "FPSLabel"
	add_child(fps_label)

func _process(_delta: float) -> void:
	# Sincronizar la cámara proxy del Jugador 2 con la cámara real en cada frame.
	# Esto es necesario porque la cámara real está en el árbol de escena de viewport_p1,
	# pero necesitamos que viewport_p2 renderice desde su perspectiva.
	if is_running and camera_p2 and camera_p2_proxy:
		camera_p2_proxy.global_transform = camera_p2.global_transform

func _setup_viewports() -> void:
	"""Configurar viewports para split-screen."""
	# Obtener referencias
	var vp_container_p1 = get_node("ViewportContainer/GridContainer/VP_Container_P1")
	var vp_container_p2 = get_node("ViewportContainer/GridContainer/VP_Container_P2")

	viewport_p1 = vp_container_p1.get_node("Viewport_P1")
	viewport_p2 = vp_container_p2.get_node("Viewport_P2")

	# Ajustar tamaño
	var screen_size = OS.get_screen_size()
	var half_width = int(screen_size.x / 2)
	var height = int(screen_size.y)

	viewport_p1.size = Vector2(half_width, height)
	viewport_p2.size = Vector2(half_width, height)

	# CRÍTICO: Habilitar el input del mouse para el viewport del Jugador 1.
	viewport_p1.handle_input_locally = true

	# Compartir mundo
	if shared_world:
		viewport_p2.world = viewport_p1.world

	print("[LocalMultiplayerManager] Viewports: %dx%d cada uno" % [half_width, height])

func _setup_level() -> void:
	"""Instanciar nivel compartido."""
	var level_res = load(level_scene_path)
	if not level_res:
		push_error("No se pudo cargar: %s" % level_scene_path)
		return

	level = level_res.instance()
	viewport_p1.add_child(level)
	print("[LocalMultiplayerManager] Nivel cargado")
	
	# Conectar las killzones del nivel al manager
	var killzones = level.get_tree().get_nodes_in_group("killzones")
	for kz in killzones:
		# Asumimos que la killzone es un Area que emite "body_entered"
		if kz.has_signal("body_entered"):
			kz.connect("body_entered", self, "_on_player_entered_killzone")

func _setup_players() -> void:
	"""Instanciar ambos jugadores."""
	var player_res = load(player_scene_path)
	if not player_res:
		push_error("No se pudo cargar: %s" % player_scene_path)
		return

	# Player 1 (izquierda)
	player1 = player_res.instance()
	player1.name = "Player_1"
	viewport_p1.add_child(player1)
	
	# Posicionar en SpawnPoint si existe
	var spawn_p1 = level.get_node_or_null("SpawnPoint")
	if spawn_p1:
		player1.global_transform = spawn_p1.global_transform
		var cam_rig_p1 = player1.get_node_or_null("CameraRig")
		if cam_rig_p1 and cam_rig_p1.has_method("sync_to_body_yaw"):
			cam_rig_p1.call_deferred("sync_to_body_yaw", spawn_p1.global_transform.basis.get_euler().y, 0)
	else:
		player1.global_transform.origin = Vector3(0, 2, 0)  # Fallback

	if player1.has_method("set_player_id"):
		player1.set_player_id(1)

	# Player 2 (derecha)
	player2 = player_res.instance()
	player2.name = "Player_2"
	# CRÍTICO: Añadir P2 al viewport de P1 para que ambos existan en el mismo World.
	# El viewport_p2 solo se usará para renderizar la vista de la cámara de P2,
	# pero el nodo del jugador debe vivir en el mundo principal.
	viewport_p1.add_child(player2)
	
	# Posicionar en SpawnPoint2 si existe
	var spawn_p2 = level.get_node_or_null("SpawnPoint2")
	if spawn_p2:
		player2.global_transform = spawn_p2.global_transform
		var cam_rig_p2 = player2.get_node_or_null("CameraRig")
		if cam_rig_p2 and cam_rig_p2.has_method("sync_to_body_yaw"):
			cam_rig_p2.call_deferred("sync_to_body_yaw", spawn_p2.global_transform.basis.get_euler().y, 0)
	else:
		player2.global_transform.origin = Vector3(spawn_distance, 2, 0)  # Fallback

	if player2.has_method("set_player_id"):
		player2.set_player_id(2)

	_configure_player_inputs()
	# Cambiar color del Player 2: usar path exacto y asignar a material/0
	var mesh_instance = player2.get_node_or_null("PilotMesh/Node_40/Skinned_Mesh_0/Skeleton/Mesh_0001")
	if mesh_instance and mesh_instance is MeshInstance:
		var mat = SpatialMaterial.new()
		mat.albedo_color = Color.cyan
		mat.emission = Color.darkslateblue
		mat.emission_enabled = true
		mesh_instance.set_surface_material(0, mat)

	print("[LocalMultiplayerManager] Jugadores instanciados")

func _configure_player_inputs():
	"""Detecta dispositivos y asigna la configuración de input a cada jugador."""
	var joypads = Input.get_connected_joypads()
	var joy_count = joypads.size()
	
	var input1 = player1.get_node_or_null("PlayerInput")
	var input2 = player2.get_node_or_null("PlayerInput")

	if not input1 or not input2:
		push_error("Falta el nodo PlayerInput en uno de los jugadores.")
		return

	# Asignar IDs de jugador
	input1.player_id = 1
	input2.player_id = 2

	if joy_count == 0:
		# --- Caso 0 Joysticks: Ambos usan teclado ---
		print("[LocalMultiplayerManager] No se detectaron joysticks. Ambos jugadores usarán teclado.")
		input1.initialize( true, 0 )
		input2.initialize( false, -1 ) # Deshabilitar joystick para P2
		
	elif joy_count == 1:
		# --- Caso especial: 1 Joystick + Teclado/Mouse ---
		print("[LocalMultiplayerManager] Detectado 1 joystick. P1 -> KB/Mouse, P2 -> Joy 0")
		# Player 1: Usa teclado y mouse, no fuerza ningún joystick.
		input1.initialize( true, -1 ) # -1 para deshabilitar joystick
		input2.initialize( false, 0)
	else:
		# --- Caso estándar: 2+ Joysticks ---
		print("[LocalMultiplayerManager] Detectados %d joysticks. P1 -> Joy 0, P2 -> Joy 1" % joy_count)
		input1.initialize( true, 0 )
		input2.initialize( false, 1 )



func _setup_cameras() -> void:
	"""Asignar cámaras existentes de los jugadores a sus viewports."""
	# Camera P1
	camera_p1 = player1.get_node_or_null("CameraRig/Yaw/Pitch/SpringArm/Camera")
	if camera_p1:
		camera_p1.current = true
	else:
		push_error("Player 1 is missing its camera at 'CameraRig/Yaw/Pitch/SpringArm/Camera'")

	# Camera P2
	camera_p2 = player2.get_node_or_null("CameraRig/Yaw/Pitch/SpringArm/Camera")
	if camera_p2:
		# Creamos una cámara "proxy" que vivirá dentro del viewport_p2.
		camera_p2_proxy = Camera.new()
		camera_p2_proxy.name = "Camera_P2_Proxy"
		
		# CRÍTICO: Copiar las propiedades de la cámara original a la proxy.
		# Esto asegura que el FOV, el clipping (near/far), etc., sean idénticos.
		camera_p2_proxy.fov = camera_p2.fov
		camera_p2_proxy.near = camera_p2.near
		camera_p2_proxy.far = camera_p2.far
		camera_p2_proxy.cull_mask = camera_p2.cull_mask
		
		# La hacemos la cámara activa para el viewport_p2.
		camera_p2_proxy.current = true
		viewport_p2.add_child(camera_p2_proxy)
	else:
		push_error("Player 2 is missing its camera at 'CameraRig/Yaw/Pitch/SpringArm/Camera'")

	print("[LocalMultiplayerManager] Cámaras configuradas")

func _on_exit_pressed() -> void:
	"""Volver al menú."""
	get_tree().change_scene("res://scenes/ui/Menu.tscn")

func set_player_alive(player_id: int, alive: bool) -> void:
	"""Marcar jugador como vivo/muerto (respawn)."""
	if player_id in player_stats:
		player_stats[player_id]["alive"] = alive
		print("[LocalMultiplayerManager] P%d: %s" % [player_id, "Vivo" if alive else "Muerto"])

func add_player_score(player_id: int, points: int) -> void:
	"""Añadir puntos a un jugador."""
	if player_id in player_stats:
		player_stats[player_id]["score"] += points

func _on_player_entered_killzone(body: Node) -> void:
	"""Manejador para cuando un jugador entra en una killzone."""
	if not body.has_method("set_player_id"):
		# El cuerpo que entró no es un jugador, ignorar.
		return

	# Identificar al jugador por su nodo
	var player_id_to_respawn = -1
	if body == player1:
		player_id_to_respawn = 1
	elif body == player2:
		player_id_to_respawn = 2

	if player_id_to_respawn != -1 and player_stats[player_id_to_respawn]["alive"]:
		set_player_alive(player_id_to_respawn, false)
		
	# Lógica de respawn
	var spawn_point = level.get_node_or_null("SpawnPoint" + ("" if player_id_to_respawn == 1 else "2"))
	if not spawn_point:
		spawn_point = level.get_node_or_null("SpawnPoint")  # Fallback
	if spawn_point:
		body.call_deferred("reset_state_for_respawn", spawn_point.global_transform)
		set_player_alive(player_id_to_respawn, true)
