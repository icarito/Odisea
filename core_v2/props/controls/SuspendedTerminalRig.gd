extends Spatial
tool

# Keeps the diagnostic carriage near the active maintenance worker. The whole
# suspended assembly turns on yaw so its overhead beam, cables, lamp, and
# terminal face together.

export(float) var follow_height_offset: float = 1.6
export(float) var min_carriage_y: float = 4.2
export(float) var max_carriage_y: float = 23.8
# follow_speed y rotation_speed son TASAS de un suavizado exponencial, no factores lineales.
# Más alto = más ágil. Ver _ease() para por qué importa la diferencia.
export(float) var follow_speed: float = 4.5
export(float) var rotation_speed: float = 3.2
export(float) var carriage_radial_distance: float = 3.5
# Distancia horizontal que el carro le respeta al jugador. Sin esto el carro viajaba
# EXACTAMENTE al XZ del jugador y le quedaba colgando sobre la cabeza.
export(float) var min_player_distance: float = 2.2
# Cuánto baja de más en el piso de abajo y sube de más en el de arriba. El recorrido se
# estira hacia los extremos para que el carro acompañe el piso en el que está el jugador.
export(float) var floor_reach_down: float = 1.4
export(float) var floor_reach_up: float = 1.4
# Cabeceo máximo cuando el jugador está por debajo, para que la pantalla lo mire.
export(float) var max_pitch_degrees: float = 22.0
export(float) var pitch_speed: float = 3.0
export(float) var cable_anchor_y: float = 26.55
export(float) var carriage_beam_y: float = 2.35

onready var _carriage: Spatial = get_node_or_null("Carriage")
onready var _left_cable: CSGBox = get_node_or_null("DropLineLeft")
onready var _right_cable: CSGBox = get_node_or_null("DropLineRight")
onready var _central_cable: CSGBox = get_node_or_null("CentralDropLine")
onready var _movement_sfx: AudioStreamPlayer3D = get_node_or_null("Carriage/MovementSFX")
onready var _display: Spatial = get_node_or_null("Carriage/HangingDisplay")
# Rotación X de fábrica del display. En Dome_Intro viene con 180° sobre X (su transform
# tiene Y y Z negadas), asi que el cabeceo se le SUMA: asignar rotation.x directamente
# borraba ese giro y la pantalla quedaba dada vuelta.
var _display_base_pitch: float = 0.0

var _player: Spatial = null

func _ready() -> void:
	if _display != null:
		_display_base_pitch = _display.rotation.x
	_player = _find_player()
	_update_cables()
	_invert_hanging_display_image()

func _physics_process(delta: float) -> void:
	if Engine.editor_hint or _carriage == null:
		return
	if not is_instance_valid(_player):
		_player = _find_player()
	if _player == null:
		return

	var follow_weight: float = _ease(follow_speed, delta)
	var previous_position: Vector3 = _carriage.translation
	var previous_yaw: float = rotation.y
	_face_player(delta)
	var target_y: float = _target_carriage_y()
	var target_horizontal: Vector3 = _target_carriage_horizontal()
	_carriage.translation.y = lerp(_carriage.translation.y, target_y, follow_weight)
	_carriage.translation.x = lerp(_carriage.translation.x, target_horizontal.x, follow_weight)
	_carriage.translation.z = lerp(_carriage.translation.z, target_horizontal.z, follow_weight)
	_update_pitch(delta)
	_update_cables()
	_update_movement_sound(previous_position, previous_yaw)

func _ease(rate: float, delta: float) -> float:
	"""Suavizado exponencial: peso = 1 - e^(-tasa*dt).

	El lerp de antes usaba min(velocidad*dt, 1), que depende de los fps —a 30 el carro se
	movía la mitad de rápido que a 60— y además arranca y frena con un corte seco. Esto
	converge igual a cualquier framerate y tiene entrada y salida suaves.
	"""
	return 1.0 - exp(-max(rate, 0.0) * delta)

func _target_carriage_y() -> float:
	var player_y: float = _player.global_transform.origin.y
	# En qué punto del recorrido está el jugador, de 0 abajo a 1 arriba. Con eso el carro
	# baja de más en el primer piso y sube de más en el último, en vez de quedarse siempre
	# a la misma altura sobre la cabeza.
	var span: float = 0.0
	if max_carriage_y > min_carriage_y:
		span = clamp((player_y - min_carriage_y) / (max_carriage_y - min_carriage_y), 0.0, 1.0)
	var reach: float = lerp(-floor_reach_down, floor_reach_up, span)
	return clamp(player_y + follow_height_offset + reach,
		min_carriage_y - floor_reach_down, max_carriage_y + floor_reach_up)

func _update_pitch(delta: float) -> void:
	if _display == null:
		return
	var to_player: Vector3 = _player.global_transform.origin - _display.global_transform.origin
	var horizontal: float = max(Vector2(to_player.x, to_player.z).length(), 0.5)
	# Cuánto MÁS abajo está el jugador de lo que el carro ya lo sobrevuela. Con el desnivel
	# crudo el cabeceo quedaba clavado en el tope, porque el carro siempre va por encima:
	# midiendo el exceso, al mismo piso da ~0 y solo se inclina si el jugador está un piso
	# abajo de verdad.
	var drop: float = -to_player.y - follow_height_offset
	var pitch: float = 0.0
	if drop > 0.0:
		pitch = clamp(atan2(drop, horizontal), 0.0, deg2rad(max_pitch_degrees))
	# El signo va RESTANDO: el display cuelga con 180° de fábrica sobre X, así que su eje
	# local X apunta al revés y sumar el cabeceo lo hacía mirar hacia ARRIBA.
	_display.rotation.x = lerp_angle(_display.rotation.x, _display_base_pitch - pitch,
		_ease(pitch_speed, delta))

func _find_player() -> Spatial:
	var players: Array = get_tree().get_nodes_in_group("player")
	for candidate in players:
		if candidate is Spatial:
			return candidate as Spatial
	return null

func _face_player(delta: float) -> void:
	var target: Vector3 = _player.global_transform.origin
	target.y = global_transform.origin.y
	var direction: Vector3 = target - global_transform.origin
	if direction.length_squared() <= 0.01:
		return
	var target_yaw: float = atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, _ease(rotation_speed, delta))

func _target_carriage_horizontal() -> Vector3:
	var local_player: Vector3 = to_local(_player.global_transform.origin)
	var horizontal: Vector3 = Vector3(local_player.x, 0.0, local_player.z)
	var distance: float = horizontal.length()
	if distance <= 0.01:
		return Vector3.ZERO
	# El carro se detiene min_player_distance ANTES del jugador, sobre la recta que va del
	# eje del riel hasta él. Antes viajaba hasta su XZ exacto: dentro del radio terminaba
	# colgado sobre su cabeza, que es justo lo que no tiene que pasar.
	var radial: float = clamp(distance - min_player_distance, 0.0, carriage_radial_distance)
	return horizontal.normalized() * radial

func _update_cables() -> void:
	if _carriage == null:
		return
	var cable_end_y: float = _carriage.translation.y + carriage_beam_y
	_update_cable(_left_cable, cable_end_y, Vector3(-2.35, 0.0, 0.0))
	_update_cable(_right_cable, cable_end_y, Vector3(2.35, 0.0, 0.0))
	_update_cable(_central_cable, cable_end_y, Vector3.ZERO)

func _update_cable(cable: CSGBox, cable_end_y: float, horizontal_offset: Vector3) -> void:
	if cable == null:
		return
	var cable_height: float = max(cable_anchor_y - cable_end_y, 0.1)
	cable.height = cable_height
	cable.translation.x = _carriage.translation.x + horizontal_offset.x
	cable.translation.y = cable_end_y + cable_height * 0.5
	cable.translation.z = _carriage.translation.z + horizontal_offset.z

func _update_movement_sound(previous_position: Vector3, previous_yaw: float) -> void:
	if _movement_sfx == null:
		return
	var moved: bool = _carriage.translation.distance_squared_to(previous_position) > 0.000004
	var turned: bool = abs(rotation.y - previous_yaw) > 0.00005
	if moved or turned:
		if not _movement_sfx.playing:
			_movement_sfx.play()
	elif _movement_sfx.playing:
		_movement_sfx.stop()

func _invert_hanging_display_image() -> void:
	var screen: CSGBox = get_node_or_null("Carriage/HangingDisplay/ScreenContainer/ScreenMesh")
	if screen == null or not screen.material is ShaderMaterial:
		return
	var material: ShaderMaterial = (screen.material as ShaderMaterial).duplicate() as ShaderMaterial
	material.render_priority = 100
	material.set_shader_param("aligned_flip_v", false)
	screen.material = material
	screen.visible = true
	var experimental_surface: Node = screen.get_parent().get_node_or_null("ProjectionSurface")
	if experimental_surface != null:
		experimental_surface.queue_free()
