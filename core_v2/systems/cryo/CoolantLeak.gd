extends Spatial
class_name CoolantLeak

# CoolantLeak.gd - Deterministic state machine for cryocoolant leak cycle (FD-256 / FD-255 / FD-266).
# Manages HEALTHY -> WARNING -> LEAKING -> DEPRESSURIZED / SEALED state transitions and leak intensity.

# --- STATE MACHINE ---
# DEPRESSURIZED: El tramo no tiene caudal porque la válvula aguas arriba está cerrada.
# Se diferencia de SEALED porque la fisura física no ha sido reparada; reabrir la
# válvula sin haber aplicado un parche firme volverá a soltar el refrigerante.
enum State { HEALTHY, WARNING, LEAKING, SEALED, DEPRESSURIZED }

# --- EXPORTED PROPERTIES ---
# If true, the system starts leaking (in WARNING state) on _ready()
export(bool) var starts_leaking: bool = false
# Duration in seconds of condensation warning phase before leak starts
export(float) var warning_duration: float = 4.0
# Duration in seconds for leak intensity to ramp up from 0 to 1
export(float) var ramp_up_duration: float = 3.0
# Duration in seconds for leak intensity to dissipate from current value to 0
export(float) var dissipate_duration: float = 5.0
# If true, leak can be re-triggered after SEALED -> HEALTHY transition
export(bool) var auto_restart: bool = false
# Optional NodePath to a PipeValve node; if set, closing valve depressurizes
export(NodePath) var valve_path: NodePath
# Optional NodePath to a CoolantFlowAdapter node; if set, queries real flow at node location
export(NodePath) var flow_adapter_path: NodePath
# Optional NodePath to a Room3D environmental aggregator
export(NodePath) var room_path: NodePath
export(float) var leak_temp_rate: float = 5.0
export(float) var leak_contam_rate: float = 0.1

# --- SIGNALS ---
signal state_changed(new_state)
signal warning_started()
signal leak_started()
signal leak_sealed()

# --- INTERNAL STATE ---
var _state: int = State.HEALTHY
var _state_timer: float = 0.0
var _leak_intensity: float = 0.0
var _start_intensity: float = 0.0
var _has_been_sealed: bool = false
var _is_provisionally_patched: bool = false
var _flow_adapter: Node = null
var _room: Node = null
var _ice_capped: bool = false
# Distingue el corte temporal del hielo de una válvula cerrada: ambos quedan
# DEPRESSURIZED, pero sólo el primero debe reabrir al bajar la superficie.
var _depressurized_by_ice: bool = false
const ICE_CAP_SUBMERSION_MARGIN := 0.05


func _ready() -> void:
	add_to_group("replay_sync")
	add_to_group("coolant_leak")

	if valve_path != null and not valve_path.is_empty():
		var valve = get_node_or_null(valve_path)
		if valve and valve.has_signal("valve_state_changed"):
			valve.connect("valve_state_changed", self, "_on_valve_state_changed")

	if flow_adapter_path != null and not flow_adapter_path.is_empty():
		_flow_adapter = get_node_or_null(flow_adapter_path)

	if room_path != null and not room_path.is_empty():
		_room = get_node_or_null(room_path)
	# Sin room_path explicito (caso comun: docenas de fugas autoria en Dome_Intro), _room se
	# resuelve de forma perezosa en _apply_room_deltas() -- ver ahi el porque.

	if starts_leaking:
		trigger_leak()
	else:
		# PERF: arranca en HEALTHY (default) — nada que tickear hasta que algo la
		# active. Ver el mismo gate en _set_state().
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return
	_refresh_ice_cap()
	if _ice_capped and (_state == State.WARNING or _state == State.LEAKING):
		_depressurized_by_ice = true
		depressurize()
	elif not _ice_capped and _depressurized_by_ice:
		_depressurized_by_ice = false
		trigger_leak()

	match _state:
		State.HEALTHY:
			_leak_intensity = 0.0

		State.WARNING:
			_leak_intensity = 0.0
			_state_timer += delta
			if _state_timer >= warning_duration:
				_set_state(State.LEAKING)

		State.LEAKING:
			if _ice_capped:
				depressurize()
				return
			# El tanque vacío corta el caudal igual que una válvula cerrada — el mismo
			# adapter ya lo modela (compute_flow multiplica por tank_level), así que
			# reusar is_pressurized_at() cubre ambos casos sin duplicar la lectura del
			# tanque acá.
			if _flow_adapter != null and _flow_adapter.has_method("is_pressurized_at"):
				if not bool(_flow_adapter.call("is_pressurized_at", self)):
					_set_state(State.DEPRESSURIZED)
					return
			_state_timer += delta
			if _is_provisionally_patched:
				if dissipate_duration > 0.0:
					var progress: float = clamp(_state_timer / dissipate_duration, 0.0, 1.0)
					_leak_intensity = lerp(_start_intensity, 0.0, progress)
				else:
					_leak_intensity = 0.0
			else:
				if ramp_up_duration > 0.0:
					var progress: float = clamp(_state_timer / ramp_up_duration, 0.0, 1.0)
					_leak_intensity = lerp(_start_intensity, 1.0, progress)
				else:
					_leak_intensity = 1.0

		State.DEPRESSURIZED:
			# DEPRESSURIZED sólo se alcanza desde una fisura que ya se rompió (o desde
			# trigger_leak() mientras la válvula estaba cerrada). Recuperar presión no
			# crea fugas HEALTHY, pero sí deja escapar de nuevo esa fisura pendiente.
			var own_valve_open := true
			if valve_path != null and not valve_path.is_empty():
				var valve = get_node_or_null(valve_path)
				if valve != null and "is_active" in valve:
					own_valve_open = bool(valve.get("is_active"))
			if not _ice_capped and own_valve_open and _flow_adapter != null and _flow_adapter.has_method("is_pressurized_at"):
				if bool(_flow_adapter.call("is_pressurized_at", self)):
					trigger_leak()
					return
			_state_timer += delta
			if dissipate_duration > 0.0:
				var progress: float = clamp(_state_timer / dissipate_duration, 0.0, 1.0)
				_leak_intensity = lerp(_start_intensity, 0.0, progress)
			else:
				_leak_intensity = 0.0

		State.SEALED:
			_state_timer += delta
			if dissipate_duration > 0.0:
				var progress: float = clamp(_state_timer / dissipate_duration, 0.0, 1.0)
				_leak_intensity = lerp(_start_intensity, 0.0, progress)
			else:
				_leak_intensity = 0.0

			if _leak_intensity <= 0.0 or _state_timer >= dissipate_duration:
				_leak_intensity = 0.0
				_has_been_sealed = true
				_set_state(State.HEALTHY)

	_apply_room_deltas(delta)


# --- PUBLIC API ---

func get_state() -> int:
	return _state


func get_leak_intensity() -> float:
	return _leak_intensity


func set_flow_adapter(adapter: Node) -> void:
	_flow_adapter = adapter


func is_ice_capped() -> bool:
	return _ice_capped


func is_depressurized() -> bool:
	return _state == State.DEPRESSURIZED


func set_provisionally_patched(value: bool) -> void:
	if _is_provisionally_patched == value:
		return
	_is_provisionally_patched = value
	_start_intensity = _leak_intensity
	_state_timer = 0.0


func trigger_leak() -> void:
	if _ice_capped:
		if _state == State.WARNING or _state == State.LEAKING:
			depressurize()
		return
	if valve_path != null and not valve_path.is_empty():
		var valve = get_node_or_null(valve_path)
		if valve != null and "is_active" in valve and not bool(valve.get("is_active")):
			_set_state(State.DEPRESSURIZED)
			return

	if _flow_adapter != null and _flow_adapter.has_method("is_pressurized_at"):
		if not bool(_flow_adapter.call("is_pressurized_at", self)):
			_set_state(State.DEPRESSURIZED)
			return

	# Reabrir mientras está despresurizado vuelve a la fuga sin pasar por el aviso:
	# el caño sigue roto, no hay nada que anticipar de nuevo.
	if _state == State.DEPRESSURIZED:
		_set_state(State.LEAKING)
		return
	if _state == State.SEALED:
		_set_state(State.LEAKING)
		return
	if _state != State.HEALTHY:
		return
	if _has_been_sealed and not auto_restart:
		return
	_set_state(State.WARNING)


func seal() -> void:
	_is_provisionally_patched = false
	if _state == State.WARNING:
		_has_been_sealed = true
		_set_state(State.HEALTHY)
		_leak_intensity = 0.0
		emit_signal("leak_sealed")
	elif _state == State.LEAKING or _state == State.DEPRESSURIZED:
		_set_state(State.SEALED)


func set_active(value: bool) -> void:
	# Activar el circuito puede restituir caudal a una fisura ya rota, pero no crear
	# una ruptura sana. La primera transición desde HEALTHY sigue siendo trigger_leak().
	if value:
		if _state == State.DEPRESSURIZED:
			trigger_leak()
	else:
		depressurize()


func depressurize() -> void:
	# Unico camino a DEPRESSURIZED: la valvula y el grafo entran los dos por aca para
	# que no se vuelvan a desincronizar.
	if _state == State.WARNING or _state == State.LEAKING:
		_set_state(State.DEPRESSURIZED)


func reset() -> void:
	_has_been_sealed = false
	_is_provisionally_patched = false
	_ice_capped = false
	_depressurized_by_ice = false
	_leak_intensity = 0.0
	_start_intensity = 0.0
	_state_timer = 0.0
	_state = State.HEALTHY
	emit_signal("state_changed", _state)


# --- INTERNAL HELPERS ---

func _set_state(new_state: int) -> void:
	if _state == new_state:
		return
	_state = new_state
	_state_timer = 0.0
	_start_intensity = _leak_intensity

	emit_signal("state_changed", _state)

	match _state:
		State.WARNING:
			emit_signal("warning_started")
		State.LEAKING:
			emit_signal("leak_started")
		State.SEALED:
			emit_signal("leak_sealed")
		State.DEPRESSURIZED, State.HEALTHY:
			pass

	# PERF: en Dome_Intro hay ~24 CoolantLeak de autoria y solo 2-3 estan activas por
	# partida (RandomLeakSeeder) — el resto se queda en HEALTHY toda la partida. Sin
	# esto, las ~21 inactivas tickeaban _physics_process a 60Hz sin nada que hacer.
	# HEALTHY es el unico estado sin timer ni intensidad que evolucionar por si solo;
	# trigger_leak()/set_active() las despierta de nuevo via _set_state().
	set_physics_process(_state != State.HEALTHY)


func _apply_room_deltas(delta: float) -> void:
	if _leak_intensity <= 0.0:
		return

	# Resolucion perezosa, dos casos:
	# 1) Sin room_path explicito (~24 fugas de autoria en Dome_Intro, cuelgan de
	#    TowerCoolantRiser/CryoLoopWest/etc, declarados en el .tscn ANTES que DomeRoom3D):
	#    en _ready() el grupo room_3d todavia estaba vacio. Para cuando el primer frame de
	#    fuga activa llega aca, el arbol entero ya cargo.
	# 2) Con room_path explicito seteado DESPUES de add_child() (patron comun en tests y
	#    en escenas armadas a mano): _ready() ya paso y get_node_or_null() dio null para
	#    siempre si solo se intentaba una vez ahi.
	if _room == null:
		if room_path != null and not room_path.is_empty():
			_room = get_node_or_null(room_path)
		else:
			var rooms := get_tree().get_nodes_in_group("room_3d")
			if not rooms.empty():
				_room = rooms[0]

	if _room == null or not is_instance_valid(_room):
		return
	if _room.has_method("add_temperature"):
		_room.call("add_temperature", -leak_temp_rate * _leak_intensity * delta)
	if _room.has_method("add_contamination"):
		_room.call("add_contamination", leak_contam_rate * _leak_intensity * delta)


func _refresh_ice_cap() -> void:
	if get_tree() == null:
		return
	var ice_systems: Array = get_tree().get_nodes_in_group("ice_level")
	var capped := false
	if not ice_systems.empty():
		var ice = ice_systems[0]
		if is_instance_valid(ice) and "ice_height" in ice:
			# La superficie al nivel exacto del origen no tapa la boquilla todavía; evitar
			# ese empate mantiene activas las fugas del suelo hasta que queden sumergidas.
			capped = float(ice.get("ice_height")) > global_transform.origin.y + ICE_CAP_SUBMERSION_MARGIN
	_ice_capped = capped


func _on_valve_state_changed(is_open: bool) -> void:
	# Abrir no puede activar una fisura HEALTHY. Pero una fisura ya rota queda
	# DEPRESSURIZED al cerrar y debe volver a LEAKING al recuperar presión.
	if is_open:
		if _state != State.DEPRESSURIZED:
			return
		if _flow_adapter != null and _flow_adapter.has_method("is_pressurized_at"):
			if not bool(_flow_adapter.call("is_pressurized_at", self)):
				return
		trigger_leak()
	else:
		depressurize()


# --- REPLAY / SNAPSHOT SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"state": _state,
		"state_timer": _state_timer,
		"leak_intensity": _leak_intensity,
		"start_intensity": _start_intensity,
		"has_been_sealed": _has_been_sealed,
		"is_provisionally_patched": _is_provisionally_patched,
		"ice_capped": _ice_capped,
		"depressurized_by_ice": _depressurized_by_ice
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("state"):
		_state = int(data["state"])
	if data.has("state_timer"):
		_state_timer = float(data["state_timer"])
	if data.has("leak_intensity"):
		_leak_intensity = float(data["leak_intensity"])
	if data.has("start_intensity"):
		_start_intensity = float(data["start_intensity"])
	if data.has("has_been_sealed"):
		_has_been_sealed = bool(data["has_been_sealed"])
	if data.has("is_provisionally_patched"):
		_is_provisionally_patched = bool(data["is_provisionally_patched"])
	if data.has("ice_capped"):
		_ice_capped = bool(data["ice_capped"])
	_depressurized_by_ice = bool(data.get("depressurized_by_ice", false))
