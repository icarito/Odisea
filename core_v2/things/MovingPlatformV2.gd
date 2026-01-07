extends KinematicBody

# MovingPlatformV2.gd

enum EaseType { LINEAR, SINE, CUSTOM_CURVE }

# --- Parámetros Exportables ---
# El vector de desplazamiento relativo a la posición inicial en el editor.
export var movement_vector: Vector3 = Vector3.RIGHT * 10.0
# Tiempo en segundos para un ciclo completo (ida y vuelta).
export var cycle_duration: float = 4.0
# Retraso antes de iniciar el movimiento.
export var start_delay: float = 0.0
export(EaseType) var ease_type = EaseType.SINE
export(Curve) var custom_curve: Curve # Arrastra tus archivos .tres aquí
export(NodePath) var passenger_area_path
export(bool) var debug_passengers := false

# --- Estado Interno ---
var time_accumulator: float = 0.0
var linear_velocity: Vector3 = Vector3.ZERO
var start_position: Vector3
var end_position: Vector3
var _pending_snapshot = null
var passengers := []
onready var passenger_area: Area = null
var _debug_accum := 0.0
 

func _ready():
	add_to_group("replay_sync")
	# Resolver PassengerArea para propagar velocidad a pasajeros.
	if passenger_area_path and has_node(passenger_area_path):
		passenger_area = get_node(passenger_area_path)
	else:
		passenger_area = get_node_or_null("PassengerArea")
	if passenger_area:
		if not passenger_area.is_connected("body_entered", self, "_on_passenger_entered"):
			passenger_area.connect("body_entered", self, "_on_passenger_entered")
		if not passenger_area.is_connected("body_exited", self, "_on_passenger_exited"):
			passenger_area.connect("body_exited", self, "_on_passenger_exited")
		if debug_passengers:
			print("[MP2] passenger area ready mask=", passenger_area.collision_mask, " layer=", passenger_area.collision_layer)


	# Capturar posición inicial ya con el transform instanciado aplicado.
	start_position = global_transform.origin
	end_position = start_position + movement_vector

	time_accumulator = -start_delay

	# Aplicar snapshot pendiente si existiera.
	if _pending_snapshot != null:
		_apply_snapshot(_pending_snapshot)
		_pending_snapshot = null

 

func _apply_snapshot(data: Dictionary) -> void:
	# Aplica snapshot suponiendo que ya estamos dentro del árbol.
	if data.has("time"):
		time_accumulator = data.time
	if data.has("start_pos"):
		var sp = data["start_pos"]
		start_position = Vector3(sp[0], sp[1], sp[2])
		end_position = start_position + movement_vector
	if data.has("pos"):
		var p = data["pos"]
		global_transform = Transform(global_transform.basis, Vector3(p[0], p[1], p[2]))
	if data.has("vel"):
		var v = data["vel"]
		linear_velocity = Vector3(v[0], v[1], v[2])

func _physics_process(delta: float):
	var previous_position = global_transform.origin
	time_accumulator += delta

	# Si estamos en el periodo de delay, mantenemos la posición inicial.
	if time_accumulator < 0:
		global_transform.origin = start_position
		linear_velocity = Vector3.ZERO
		return

	# 1. Cálculo de progreso normalizado (0.0 a 1.0)
	# Definimos el progreso en un viaje de ida y vuelta (ping-pong).
	var half_cycle = cycle_duration / 2.0
	var raw_progress = pingpong_logic(time_accumulator, half_cycle) / half_cycle
	
	# 2. Aplicación de la "Curva" (Game Feel)
	var cooked_progress = apply_easing(raw_progress)

	# 3. Cálculo de la nueva posición global mediante interpolación.
	var new_position = start_position.linear_interpolate(end_position, cooked_progress)

	# 4. Actualización de posición global y cálculo de velocidad para el Player.
	global_transform.origin = new_position
	
	if delta > 0:
		# Esta velocidad es vital para que move_and_slide detecte el movimiento del suelo.
		linear_velocity = (new_position - previous_position) / delta

	# Propagar velocidad a cuerpos pasajeros (jugador, etc.).
	if passengers.size() > 0:
		for i in range(passengers.size() - 1, -1, -1):
			var body = passengers[i]
			if not is_instance_valid(body):
				passengers.remove(i)
				continue
			if body.has_method("set_external_velocity"):
				body.set_external_velocity(linear_velocity)
				if body.has_method("set_external_source_is_static"):
					body.set_external_source_is_static(false)

	# Debug periódico
	if debug_passengers:
		_debug_accum += delta
		if _debug_accum >= 0.5:
			_debug_accum = 0.0
			print("[MP2] passengers=", passengers.size(), " vel=", linear_velocity, " pos=", global_transform.origin)

func apply_easing(t: float) -> float:
	match ease_type:
		EaseType.SINE:
			# Suavizado Senoidal matemático (aceleración y frenado suave).
			return 0.5 - cos(t * PI) * 0.5
		EaseType.CUSTOM_CURVE:
			if custom_curve:
				# Uso de tus recursos .tres (Exponential, Inverse_S, etc).
				return custom_curve.interpolate(t)
			return t
		_:
			return t

func pingpong_logic(value: float, length: float) -> float:
	if length == 0: return 0.0
	# Implementación manual de pingpong para asegurar comportamiento determinista.
	return length - abs(fmod(value, 2.0 * length) - length)

# --- Sistema de Replay (SessionManager) ---

func get_snapshot() -> Dictionary:
	return {
		"time": time_accumulator,
		"start_pos": [start_position.x, start_position.y, start_position.z],
		"pos": [global_transform.origin.x, global_transform.origin.y, global_transform.origin.z],
		"vel": [linear_velocity.x, linear_velocity.y, linear_velocity.z]
	}

func restore_snapshot(data: Dictionary):
	# Puede que el SessionManager intente restaurar el snapshot antes de que
	# el nodo esté dentro del árbol (ej. reproducción desde CLI). En ese caso
	# guardamos el snapshot y lo aplicamos cuando estemos listos.
	if not is_inside_tree():
		_pending_snapshot = data.duplicate(true)
		return

	# Si estamos en el árbol, aplicar inmediatamente.
	_apply_snapshot(data)


func _on_passenger_entered(body):
	if body and not passengers.has(body):
		# Evitar contarnos a nosotros mismos o hijos.
		if body == self or body.get_parent() == self:
			return
		passengers.append(body)
		if debug_passengers:
			print("[MP2] enter:", body)


func _on_passenger_exited(body):
	if body:
		passengers.erase(body)
		if debug_passengers:
			print("[MP2] exit:", body)
