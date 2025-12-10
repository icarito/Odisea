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
var death_screen_p1: CanvasLayer
var death_screen_p2: CanvasLayer
var initial_transform_p1: Transform
var initial_transform_p2: Transform

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

	death_screen_p1 = preload("res://scenes/ui/DeathScreen.tscn").instance()
	viewport_p1.add_child(death_screen_p1)

	death_screen_p2 = preload("res://scenes/ui/DeathScreen.tscn").instance()
	viewport_p2.add_child(death_screen_p2)

	is_running = true
	
	call_deferred("_connect_killzones")
	
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
	
	# La conexión de killzones se hará al final de _ready

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
	var spawn_p1 = level.find_node("SpawnPoint")
	if spawn_p1:
		player1.global_transform = spawn_p1.global_transform
		initial_transform_p1 = spawn_p1.global_transform
		# Alinear el propio jugador ANTES de instanciar la cámara
		var yaw = spawn_p1.global_transform.basis.get_euler().y
		player1.rotation.y = yaw
		# Alinear la cámara después de agregar al árbol
		var cam_rig_p1 = player1.get_node_or_null("CameraRig")
		if cam_rig_p1 and cam_rig_p1.has_method("sync_to_body_yaw"):
			cam_rig_p1.call_deferred("sync_to_body_yaw", yaw, PI)
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
	var spawn_p2 = level.find_node("SpawnPoint2")
	if spawn_p2:
		player2.global_transform = spawn_p2.global_transform
		initial_transform_p2 = spawn_p2.global_transform
		var yaw2 = spawn_p2.global_transform.basis.get_euler().y
		player2.rotation.y = yaw2
		var cam_rig_p2 = player2.get_node_or_null("CameraRig")
		if cam_rig_p2 and cam_rig_p2.has_method("sync_to_body_yaw"):
			cam_rig_p2.call_deferred("sync_to_body_yaw", yaw2, PI)
	else:
		push_error("No se encontró SpawnPoint2; Necesario para posicionar Player 2.")

	if player2.has_method("set_player_id"):
		player2.set_player_id(2)

	_configure_player_inputs()
	_set_player2_color()

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
		# Asegurar que use el environment global y clear_mode SKY
		camera_p2_proxy.environment = null
		# La hacemos la cámara activa para el viewport_p2.
		camera_p2_proxy.current = true
		viewport_p2.add_child(camera_p2_proxy)
	else:
		push_error("Player 2 is missing its camera at 'CameraRig/Yaw/Pitch/SpringArm/Camera'")

	print("[LocalMultiplayerManager] Cámaras configuradas")

func _connect_killzones():
	"""Conectar killzones después de que se hayan agregado al grupo."""
	var killzones = level.get_tree().get_nodes_in_group("killzones")
	print("[LocalMultiplayerManager] Found killzones: ", killzones)
	for kz in killzones:
		print("[LocalMultiplayerManager] Connecting kz: ", kz)
		if kz.has_signal("player_killed"):
			kz.connect("player_killed", self, "_on_player_killed")
			print("[LocalMultiplayerManager] Connected player_killed")

func set_player_alive(player_id: int, alive: bool) -> void:
	"""Marcar jugador como vivo/muerto (respawn)."""
	if player_id in player_stats:
		player_stats[player_id]["alive"] = alive
		print("[LocalMultiplayerManager] P%d: %s" % [player_id, "Vivo" if alive else "Muerto"])

func add_player_score(player_id: int, points: int) -> void:
	"""Añadir puntos a un jugador."""
	if player_id in player_stats:
		player_stats[player_id]["score"] += points


func _on_player_killed(player: Node) -> void:
	"""Manejador para señal player_killed de KillZone."""
	print("[LocalMultiplayerManager] _on_player_killed called with player:", player)
	# Identificar al jugador por su nodo
	var player_id_to_kill = -1
	if player == player1:
		player_id_to_kill = 1
	elif player == player2:
		player_id_to_kill = 2

	print("[LocalMultiplayerManager] Identified player ID to kill: ", player_id_to_kill)
	if player_id_to_kill != -1 and player_stats[player_id_to_kill]["alive"]:
		print("[LocalMultiplayerManager] Killing player ", player_id_to_kill)
		set_player_alive(player_id_to_kill, false)
		
		# Mostrar death screen solo en el viewport del jugador correspondiente
		if player_id_to_kill == 1:
			death_screen_p1.show_death_screen()
		elif player_id_to_kill == 2:
			death_screen_p2.show_death_screen()

func _input(event):
	# Solo permitir respawn si el evento corresponde al botón Jump de cada jugador
	var jump_p1 = Input.is_action_pressed("jump")
	var jump_p2 = Input.is_action_pressed("jump_2")
	# Respawn P1
	if death_screen_p1.is_showing and jump_p1:
		print("[Respawn] Intentando respawn P1...")
		if not player_stats[1]["alive"]:
			var spawn_point = level.find_node("SpawnPoint", true, false)
			print("[Respawn] SpawnPoint P1:", spawn_point)
			player1.connect("tree_exited", self, "_on_player1_freed", [spawn_point])
			player1.queue_free()
		else:
			print("[Respawn] P1 ya está vivo, no respawnea")
		death_screen_p1.hide_death_screen()
	# Respawn P2
	if death_screen_p2.is_showing and jump_p2:
		print("[Respawn] Intentando respawn P2...")
		if not player_stats[2]["alive"]:
			var spawn_point2 = level.find_node("SpawnPoint2", true, false)
			print("[Respawn] SpawnPoint2:", spawn_point2)
			if not spawn_point2:
				spawn_point2 = level.find_node("SpawnPoint", true, false)
				print("[Respawn] Fallback a SpawnPoint:", spawn_point2)
			player2.connect("tree_exited", self, "_on_player2_freed", [spawn_point2])
			player2.queue_free()
		else:
			print("[Respawn] P2 ya está vivo, no respawnea")
		death_screen_p2.hide_death_screen()

func _on_player1_freed(spawn_point):
	var player_res = load(player_scene_path)
	player1 = player_res.instance()
	player1.name = "Player_1"
	viewport_p1.add_child(player1)
	if spawn_point:
		player1.global_transform = spawn_point.global_transform
	if player1.has_method("set_player_id"):
		player1.set_player_id(1)
	_configure_player_inputs()
	set_player_alive(1, true)
	player1.set_physics_process(true)
	_setup_cameras()


func _on_player2_freed(spawn_point2):
	var player_res2 = load(player_scene_path)
	player2 = player_res2.instance()
	player2.name = "Player_2"
	viewport_p1.add_child(player2)
	if spawn_point2:
		player2.global_transform = spawn_point2.global_transform
	if player2.has_method("set_player_id"):
		player2.set_player_id(2)
	_set_player2_color()
	_configure_player_inputs()
	set_player_alive(2, true)
	player2.set_physics_process(true)
	_setup_cameras()

func _set_player2_color():
	# Cambiar color del Player 2: usar path exacto y asignar a material/0
	if not player2:
		return
	var mesh_instance = player2.get_node_or_null("PilotMesh/Node_40/Skinned_Mesh_0/Skeleton/Mesh_0001")
	if mesh_instance and mesh_instance is MeshInstance:
		var mat = SpatialMaterial.new()
		mat.albedo_color = Color.cyan
		mat.emission = Color.darkslateblue
		mat.emission_enabled = true
		mesh_instance.set_surface_material(0, mat)
