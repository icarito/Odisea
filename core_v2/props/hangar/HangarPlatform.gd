extends KinematicBody
class_name HangarPlatform

# HangarPlatform.gd - FD-289 §7.9 (T3)
# Plataforma movil de carga en el pozo del blast door: el jugador se sube y desciende
# hasta el fondo del pozo, donde cruza el trigger de transicion al hangar (T2/T4).
# Ubicacion: core_v2/props/hangar/ (junto a HangarPlatform.tscn); es un prop de nivel
# reutilizable por cualquier domo, coherente con core_v2/props/{elevator,machinery,...}.
#
# Estados canonicos: TOP -> DESCENDING -> BOTTOM. Automatica por Area de pie (un jugador
# parado sobre la plataforma) o por boton (button_path con senal "activated"); tambien
# expone descend()/activate()/interact() para cablearlo a mano.
#
# Determinismo: integracion por dt con move_toward (sin randf ni tiempo de pared). El
# temblor durante el descenso se delega a TremorZoneV2 (RNG sembrado, determinista). Grupo
# "replay_sync" + get_snapshot/restore_snapshot.

signal descend_started()
signal arrived_at_bottom()

enum State { TOP, DESCENDING, BOTTOM }

# --- EXPORTED TUNING ---
# Profundidad del pozo (m): cuanto baja la plataforma desde su posicion inicial.
export(float) var travel_distance := 12.0
# Velocidad maxima de descenso (m/s) y aceleraciones para no arrancar/frenar en seco.
export(float) var speed := 1.6
export(float) var acceleration := 2.5
export(float) var deceleration := 2.5
# Area que detecta pasajeros (para propagar velocidad a cajas/NPCs) y el auto-arranque.
export(NodePath) var passenger_area_path = NodePath("PassengerArea")
# Si un jugador pisa la plataforma en TOP, arranca el descenso solo.
export(bool) var auto_descend_on_player := true
# Boton opcional cuya senal "activated" arranca el descenso.
export(NodePath) var button_path
export(bool) var debug_passengers := false

# --- STATE (snapshot) ---
var state: int = State.TOP
var top_height := 0.0
var bottom_height := 0.0
var current_velocity_y := 0.0
var passengers := []

var _pending_snapshot = null
var _initialized := false
var _tremor = null
var _sfx_loop = null
var passenger_area: Area = null

func _init() -> void:
	add_to_group("replay_sync")

func _ready() -> void:
	passenger_area = get_node_or_null(passenger_area_path) if passenger_area_path else get_node_or_null("PassengerArea")
	if passenger_area:
		if not passenger_area.is_connected("body_entered", self, "_on_passenger_entered"):
			passenger_area.connect("body_entered", self, "_on_passenger_entered")
		if not passenger_area.is_connected("body_exited", self, "_on_passenger_exited"):
			passenger_area.connect("body_exited", self, "_on_passenger_exited")
	_tremor = get_node_or_null("TremorZone")
	_sfx_loop = get_node_or_null("SFX Loop")
	_connect_button()

	if _pending_snapshot != null:
		var data = _pending_snapshot
		_pending_snapshot = null
		_apply_snapshot(data)
	elif not _initialized:
		_initialized = true
		top_height = global_transform.origin.y
		bottom_height = top_height - travel_distance
		state = State.TOP
		set_physics_process(false)

func _connect_button() -> void:
	if not button_path or not has_node(button_path):
		return
	var b = get_node(button_path)
	if b and b.has_signal("activated") and not b.is_connected("activated", self, "descend"):
		b.connect("activated", self, "descend")

# --- INTERFAZ PUBLICA ---

func descend(_arg = null) -> void:
	if state != State.TOP:
		return
	state = State.DESCENDING
	current_velocity_y = 0.0
	set_physics_process(true)
	if _tremor and _tremor.has_method("set_active"):
		_tremor.set_active(true)
	if _sfx_loop and _sfx_loop.has_method("play_sfx"):
		_sfx_loop.play_sfx()
	emit_signal("descend_started")

func activate() -> void:
	descend()

func interact() -> void:
	descend()

func reset_to_top(immediate: bool = true) -> void:
	state = State.TOP
	current_velocity_y = 0.0
	if immediate:
		global_transform.origin.y = top_height
		force_update_transform()
	set_physics_process(false)

func get_state_name() -> String:
	return State.keys()[state]

# --- SIMULACION DETERMINISTA ---

func step(dt: float) -> void:
	_physics_process(dt)

func _physics_process(delta: float) -> void:
	if state != State.DESCENDING:
		return

	var current_y: float = global_transform.origin.y
	var diff: float = bottom_height - current_y
	var dist: float = abs(diff)
	var direction: float = sign(diff)

	if dist < 0.05 and abs(current_velocity_y) < 0.1:
		global_transform.origin.y = bottom_height
		current_velocity_y = 0.0
		state = State.BOTTOM
		set_physics_process(false)
		_update_passengers(Vector3.ZERO)
		if _tremor and _tremor.has_method("set_active"):
			_tremor.set_active(false)
		if _sfx_loop and _sfx_loop.has_method("stop_sfx"):
			_sfx_loop.stop_sfx()
		emit_signal("arrived_at_bottom")
		return

	# Perfil trapezoidal: acelera hacia la velocidad de frenado (sqrt(2*a*dist)).
	var braking_speed: float = sqrt(2.0 * max(0.001, deceleration) * dist)
	var target_speed: float = min(speed, braking_speed)
	current_velocity_y = move_toward(current_velocity_y, target_speed * direction, acceleration * delta)

	var move_step: float = current_velocity_y * delta
	if abs(move_step) > dist:
		move_step = diff
	global_transform.origin.y += move_step
	force_update_transform()

	_update_passengers(Vector3(0.0, current_velocity_y, 0.0))

func _update_passengers(velocity: Vector3) -> void:
	var current_passengers: Array = []
	if passenger_area:
		passenger_area.force_update_transform()
		current_passengers = passenger_area.get_overlapping_bodies()
	else:
		current_passengers = passengers
	for body in current_passengers:
		if body == self or body.get_parent() == self:
			continue
		# El jugador usa transform-delta tracking propio; no lo empujamos.
		if body.has_method("_update_platform_tracking"):
			continue
		if body.has_method("set_external_velocity"):
			body.set_external_velocity(velocity)
			if body.has_method("set_external_source_is_static"):
				body.set_external_source_is_static(true)

func _on_passenger_entered(body) -> void:
	if body and not passengers.has(body):
		passengers.append(body)
	if debug_passengers:
		print("[HangarPlatform] enter: ", body)
	if auto_descend_on_player and state == State.TOP and body and body.is_in_group("player"):
		descend()

func _on_passenger_exited(body) -> void:
	if body:
		passengers.erase(body)
	if debug_passengers:
		print("[HangarPlatform] exit: ", body)

# --- SNAPSHOT ---

func get_snapshot() -> Dictionary:
	return {
		"state": state,
		"position": [global_transform.origin.x, global_transform.origin.y, global_transform.origin.z],
		"top_height": top_height,
		"bottom_height": bottom_height,
		"current_velocity_y": current_velocity_y,
		"travel_distance": travel_distance,
		"speed": speed,
		"acceleration": acceleration,
		"deceleration": deceleration,
		"auto_descend_on_player": auto_descend_on_player,
		"debug_passengers": debug_passengers
	}

func restore_snapshot(data: Dictionary) -> void:
	if not is_inside_tree():
		_pending_snapshot = data.duplicate(true)
		return
	_apply_snapshot(data)

func _apply_snapshot(data: Dictionary) -> void:
	_initialized = true
	passengers.clear()
	if data.has("travel_distance"):
		travel_distance = float(data["travel_distance"])
	if data.has("speed"):
		speed = float(data["speed"])
	if data.has("acceleration"):
		acceleration = float(data["acceleration"])
	if data.has("deceleration"):
		deceleration = float(data["deceleration"])
	if data.has("auto_descend_on_player"):
		auto_descend_on_player = bool(data["auto_descend_on_player"])
	if data.has("debug_passengers"):
		debug_passengers = bool(data["debug_passengers"])
	if data.has("top_height"):
		top_height = float(data["top_height"])
	if data.has("bottom_height"):
		bottom_height = float(data["bottom_height"])
	if data.has("position"):
		var p = data["position"]
		global_transform.origin = Vector3(p[0], p[1], p[2])
	state = int(data.get("state", state))
	current_velocity_y = float(data.get("current_velocity_y", 0.0))
	force_update_transform()
	set_physics_process(state == State.DESCENDING)
	# Si se restauro a mitad del descenso, recalcular el temblor activo.
	if _tremor and _tremor.has_method("set_active"):
		_tremor.set_active(state == State.DESCENDING)
