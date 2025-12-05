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

# ===== CONFIG =====
export var level_scene_path := "res://scenes/multiplayer/CoopLevel.tscn"
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
	_setup_level()
	_setup_players()
	_setup_cameras()
	_setup_ui()

	is_running = true
	print("[LocalMultiplayerManager] Listo")

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
		player1.global_transform.origin = spawn_p1.global_transform.origin
	else:
		player1.global_transform.origin = Vector3(0, 2, 0)  # Fallback

	if player1.has_method("set_player_id"):
		player1.set_player_id(1)

	var input1 = player1.get_node_or_null("PlayerInput")
	if input1:
		input1.player_id = 1
	else:
		push_error("Player 1 is missing PlayerInput node!")


	# Player 2 (derecha)
	player2 = player_res.instance()
	player2.name = "Player_2"
	viewport_p2.add_child(player2)
	
	# Posicionar en SpawnPoint2 si existe
	var spawn_p2 = level.get_node_or_null("SpawnPoint2")
	if spawn_p2:
		player2.global_transform.origin = spawn_p2.global_transform.origin
	else:
		player2.global_transform.origin = Vector3(spawn_distance, 2, 0)  # Fallback

	if player2.has_method("set_player_id"):
		player2.set_player_id(2)

	var input2 = player2.get_node_or_null("PlayerInput")
	if input2:
		input2.player_id = 2
	else:
		push_error("Player 2 is missing PlayerInput node!")

	print("[LocalMultiplayerManager] Jugadores instanciados")

func _setup_cameras() -> void:
	"""Crear cámaras independientes para cada jugador."""
	# Camera P1
	camera_p1 = Camera.new()
	camera_p1.name = "Camera_P1"
	player1.add_child(camera_p1)
	camera_p1.make_current()

	# Camera P2
	camera_p2 = Camera.new()
	camera_p2.name = "Camera_P2"
	player2.add_child(camera_p2)

	# Offset de cámara (3ª persona)
	var cam_offset = Vector3(0, 2, 5)
	camera_p1.transform.origin = cam_offset
	camera_p2.transform.origin = cam_offset

	print("[LocalMultiplayerManager] Cámaras configuradas")

func _setup_ui() -> void:
	"""Conectar UI."""
	var exit_btn = get_node("CanvasLayer_UI/UI_Container/Button_Exit")
	exit_btn.connect("pressed", self, "_on_exit_pressed")

func _process(delta: float) -> void:
	"""Actualizar cámaras cada frame."""
	if not is_running or not player1 or not player2:
		return

	# Actualizar posición de cámaras (follow players)
	var p1_pos = player1.global_transform.origin
	var p2_pos = player2.global_transform.origin

	camera_p1.global_transform.origin = p1_pos + Vector3(0, 2, 5)
	camera_p1.look_at(p1_pos, Vector3.UP)

	camera_p2.global_transform.origin = p2_pos + Vector3(0, 2, 5)
	camera_p2.look_at(p2_pos, Vector3.UP)

	# Actualizar UI
	_update_ui()

func _update_ui() -> void:
	"""Actualizar labels de estado."""
	var label_p1 = get_node("CanvasLayer_UI/UI_Container/Label_P1_Status")
	var label_p2 = get_node("CanvasLayer_UI/UI_Container/Label_P2_Status")

	var status_p1 = "Vivo" if player_stats[1]["alive"] else "Muerto"
	var status_p2 = "Vivo" if player_stats[2]["alive"] else "Muerto"

	label_p1.text = "P1: %s | Score: %d" % [status_p1, player_stats[1]["score"]]
	label_p2.text = "P2: %s | Score: %d" % [status_p2, player_stats[2]["score"]]

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
