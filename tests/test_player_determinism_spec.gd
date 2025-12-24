# /tests/test_player_determinism_spec.gd
extends GdUnitTestSuite

const TEST_REPLAY_PATH = "res://tests/fixtures/reference.json"
const FIXED_DELTA = 1.0 / 60.0

var player: KinematicBody
var replay_data: Dictionary

func before():
	# 1. Cargar el archivo de referencia
	var file = File.new()
	if file.open(TEST_REPLAY_PATH, File.READ) == OK:
		var json_result = JSON.parse(file.get_as_text())
		if json_result.error == OK:
			replay_data = json_result.result
		file.close()
	
	if replay_data.empty():
		print("Error: El archivo JSON está vacío o no se cargó correctamente.")
		return
	
	assert_bool(replay_data.empty()).is_false()

	print("Contenido de replay_data:", replay_data) # Imprimir el contenido de replay_data para verificar su estructura

	# Asegurarse de que las claves final_states y player existen en replay_data
	assert_bool(replay_data.has("final_states")).is_true()
	assert_bool(replay_data.final_states.has("player")).is_true()

	# 2. Instanciar al jugador para el test
	# El Agente debe asegurar que esta ruta es correcta según tu proyecto
	var scene = load("res://players/elias/Pilot.tscn")
	player = scene.instance()
	add_child(player)

func test_determinism_live_vs_replay():
	# Extraer el SpawnPoint real del JSON
	var spawn_pos = ReplayUtils.dict_to_vector3(replay_data.final_states.player.player_position)
	var spawn_rot = ReplayUtils.dict_to_vector3(replay_data.final_states.player.rotation)
	
	# --- PASO 1: SIMULACIÓN MODO LIVE (Física Normal) ---
	player.global_transform.origin = spawn_pos
	player.rotation = spawn_rot
	player.set_is_replaying(false) # IMPORTANTE: Aquí probamos tu gameplay real
	
	for frame in replay_data.frames:
		player.get_node("PlayerInput").inject_input(frame.inputs)
		# Ejecutamos la física manualmente frame a frame
		player._physics_process(FIXED_DELTA)
	
	var final_pos_live = player.global_transform.origin
	var final_rot_live = player.rotation
	
	# --- PASO 2: SIMULACIÓN MODO REPLAY (Física Reproducida) ---
	# Reset total
	player.global_transform.origin = spawn_pos
	player.rotation = spawn_rot
	if player.has_method("reset_physics_state"):
		player.reset_physics_state()
		
	player.set_is_replaying(true) # Cambiamos al modo que el Agente "limpió"
	
	for frame in replay_data.frames:
		player.get_node("PlayerInput").inject_input(frame.inputs)
		player._physics_process(FIXED_DELTA)
		
	var final_pos_replay = player.global_transform.origin
	var final_rot_replay = player.rotation
	
	# --- PASO 3: MEDICIÓN DEL DESASTRE ---
	var drift = final_pos_live.distance_to(final_pos_replay)
	
	print("--- REPORTE DE DETERMINISMO ---")
	print("Posición Final Live: ", final_pos_live)
	print("Posición Final Replay: ", final_pos_replay)
	print("Drift detectado: ", drift, " metros")
	# Rotation drift (Euclidean distance in radians between Euler vectors)
	var rot_drift = final_rot_live.distance_to(final_rot_replay)
	print("Drift rotación: ", rot_drift, " rad")
	
	# Comparar el drift directamente con un operador de GDScript
	assert_float(drift).is_less_equal(0.05)
	# Asert para rotación (tolerancia angular similar)
	assert_float(rot_drift).is_less_equal(0.05)

func after():
	if is_instance_valid(player):
		player.free()

# Prefijar variables no utilizadas con un guion bajo
var _mouse_motion = Vector2.ZERO
var _replay_manager = null
var _h_rot = 0.0
var _game_globals = null
var _scaled_motion = Vector3.ZERO
var _recorded_state = {}
var _vertical_divergence = 0.0
var _on_floor = false

# Resolver conflictos de nombres
var player_instance = player

# Corregir tipos de datos
export(float) var example_float = 0.0
export(float) var another_float = 0.0

# Prefijar argumentos no utilizados con un guion bajo
func _on_capture_changed(_is_captured):
	pass

func _on_replay_mode_changed(_new_mode):
	pass

func _apply_rotation(_delta):
	pass

func spawn_network_player(_spawn_point):
	pass

func record_frame(_delta):
	pass

func check_for_drift(_frame_data):
	pass

func _apply_velocity_drift_correction(_frame_data):
	pass
