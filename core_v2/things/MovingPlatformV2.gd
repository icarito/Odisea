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
var passengers := []
onready var passenger_area: Area = null
var _debug_accum := 0.0
var _pending_snapshot = null
 

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

	# Capturar posición inicial con global_transform.origin (única fuente de verdad).
	start_position = global_transform.origin
	end_position = start_position + movement_vector
	time_accumulator = -start_delay

	# Aplicar snapshot pendiente si existiera (replay puede llamar restore antes de _ready).
	if _pending_snapshot != null:
		_apply_snapshot(_pending_snapshot)
		_pending_snapshot = null

func _apply_snapshot(data: Dictionary) -> void:
	# Restaurar posición inmediatamente desde el snapshot (corrige errores de punto flotante).
	if data.has("pos"):
		var p = data["pos"]
		global_transform.origin = Vector3(p[0], p[1], p[2])
		# Recalcular start_position y end_position basados en la posición restaurada y time.
		if data.has("time") and data.has("movement_vector"):
			var mv = data["movement_vector"]
			movement_vector = Vector3(mv[0], mv[1], mv[2])
			# Calcular start_position retroactivamente desde pos y time.
			var t = data["time"]
			if t <= 0:
				start_position = Vector3(p[0], p[1], p[2])
			else:
				# Si t > 0, la posición restaurada es intermedia; calcular start desde ella.
				var half_cycle = cycle_duration / 2.0 if cycle_duration > 0 else 1.0
				var raw_progress = pingpong_logic(t, half_cycle) / half_cycle if half_cycle > 0 else 0.0
				var cooked_progress = apply_easing(raw_progress)
				if cooked_progress > 0 and cooked_progress < 1:
					start_position = Vector3(p[0], p[1], p[2]) - movement_vector * cooked_progress
				else:
					start_position = Vector3(p[0], p[1], p[2])
			end_position = start_position + movement_vector
	if data.has("time"):
		time_accumulator = data["time"]
	if data.has("vel"):
		var v = data["vel"]
		linear_velocity = Vector3(v[0], v[1], v[2])
	if data.has("cycle_duration"):
		cycle_duration = data["cycle_duration"]
	if data.has("start_delay"):
		start_delay = data["start_delay"]
	if data.has("ease_type"):
		ease_type = data["ease_type"]
	if data.has("debug_passengers"):
		debug_passengers = data["debug_passengers"]



func _physics_process(delta: float):
	# Guardar posición anterior para calcular velocidad.
	var previous_position = global_transform.origin

	# Avanzar tiempo de forma lineal (delta es constante en Godot 3.6).
	time_accumulator += delta

	# Si estamos en el periodo de delay, mantenemos la posición inicial.
	if time_accumulator < 0:
		global_transform.origin = start_position
		linear_velocity = Vector3.ZERO
		return

	# 1. Cálculo de progreso normalizado (0.0 a 1.0) usando ping-pong.
	var half_cycle = cycle_duration / 2.0
	var raw_progress = pingpong_logic(time_accumulator, half_cycle) / half_cycle if half_cycle > 0 else 0.0

	# 2. Aplicación de la "Curva" (Game Feel).
	var cooked_progress = apply_easing(raw_progress)

	# 3. Cálculo de la nueva posición global mediante interpolación.
	var new_position = start_position.linear_interpolate(end_position, cooked_progress)

	# 4. Actualización de posición global y cálculo de velocidad para el Player.
	global_transform.origin = new_position

	# Calcular velocidad (vital para que move_and_slide detecte el movimiento del suelo).
	if delta > 0:
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

	# Debug periódico.
	if debug_passengers:
		_debug_accum += delta
		if _debug_accum >= 0.5:
			_debug_accum = 0.0
			print("[MP2] passengers=", passengers.size(), " vel=", linear_velocity, " pos=", global_transform.origin)

func step(dt: float):
	# Alias para compatibilidad con SessionManager si lo usa.
	_physics_process(dt)

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
		"pos": [global_transform.origin.x, global_transform.origin.y, global_transform.origin.z],
		"time": time_accumulator,
		"vel": [linear_velocity.x, linear_velocity.y, linear_velocity.z],
		"cycle_duration": cycle_duration,
		"start_delay": start_delay,
		"ease_type": ease_type,
		"movement_vector": [movement_vector.x, movement_vector.y, movement_vector.z],
		"debug_passengers": debug_passengers
	}

func restore_snapshot(data: Dictionary):
	# Si no estamos en el árbol, guardar para aplicar en _ready.
	if not is_inside_tree():
		_pending_snapshot = data.duplicate(true)
		return
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
