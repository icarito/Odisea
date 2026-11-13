extends InteractableBaseV2
class_name BlastDoorController

# BlastDoorController.gd - FD-289 §7.4 (T3)
# Compuerta de piso a escala hangar del domo. Base mecanica: FloorHatch.tscn (HatchDoor
# es un SlidingObjectV2 que se desliza); aca la apertura es HORIZONTAL y a otra escala:
# dos paneles de contencion se retraen en sentidos opuestos (-X / +X) revelando el pozo
# de descenso al hangar. No reemplaza ni toca FloorHatch.
#
# Interfaz (T2/DomeSystemDirector puede no existir todavia):
#   - open(immediate) / close(immediate): accionables por el director.
#   - on_blast_door_open(): callback listo para conectar a DomeSystemDirector.blast_door_open
#     (o llamar desde un wrapper del director).
#   - set_network_healthy_count(n): actualiza el semaforo de borde (§6.2) con las redes
#     HEALTHY (0..4). El director lo llama a medida que cada red pasa a HEALTHY.
#   - Senales semanticas: opened / closed.
#   - Hereda de InteractableBaseV2: is_active, anim_progress, target_progress, step(dt),
#     grupo "replay_sync", get_snapshot/restore_snapshot.
#
# Determinismo: la pose de los paneles se deriva SOLO de anim_progress (easing puro, sin
# randf ni tiempo de pared). El pulso del semaforo usa _pulse_phase acumulado por dt y
# viaja en el snapshot, asi que el replay lo reproduce bit a bit.

signal opened()
signal closed()

# --- EXPORTED TUNING ---
# Distancia (m) que se retrae cada panel hacia afuera al abrir, en el eje local X.
export(float) var panel_slide := 5.7 setget set_panel_slide
# Paneles que se deslizan (KinematicBody). Si quedan vacios se buscan "PanelA"/"PanelB".
export(NodePath) var panel_a_path
export(NodePath) var panel_b_path
# Semaforo de borde (§6.2): color/energia por cantidad de redes HEALTHY.
# 0 redes -> rojo tenue (reposo); 1-2 -> ambar pulsante; 3 -> ambar fijo; 4 -> verde/cian.
export(Color) var color_off := Color(0.6, 0.06, 0.06)          # 0 redes
export(Color) var color_restoring := Color(0.95, 0.5, 0.05)    # 1-3 redes
export(Color) var color_ready := Color(0.1, 0.9, 0.9)          # 4 redes
# Energia base del borde (~emision) y pico del pulso ambar.
export(float) var emission_base := 0.6
export(float) var emission_pulse := 2.4
# Velocidad del pulso ambar (rad/s sobre _pulse_phase).
export(float) var pulse_speed := 4.0
# Si existe /root/DomeSystemDirector con la senal blast_door_open, se conecta solo.
export(bool) var autoconnect_director := true

# --- STATE (snapshot) ---
var _healthy_count := 0
var _pulse_phase := 0.0

# --- NODE REFS (resueltas en _ready) ---
var _panel_a = null
var _panel_b = null
var _panel_a_start := Vector3.ZERO
var _panel_b_start := Vector3.ZERO
var _glow_material: SpatialMaterial = null
var _edge_lights: Array = []
var _tremor = null
var _sfx_open = null
var _pending_snapshot = null

func set_panel_slide(v: float) -> void:
	panel_slide = max(0.0, v)
	if is_inside_tree() and _panel_a != null:
		_update_visuals()

func _ready() -> void:
	_resolve_nodes()
	if _panel_a:
		_panel_a_start = _panel_a.translation
	if _panel_b:
		_panel_b_start = _panel_b.translation
	# Base: fija estado inicial, corre _update_visuals() y culling de physics.
	._ready()
	_apply_semaphore()
	_maybe_connect_director()
	if _pending_snapshot != null:
		var data = _pending_snapshot
		_pending_snapshot = null
		restore_snapshot(data)

func _resolve_nodes() -> void:
	_panel_a = get_node_or_null(panel_a_path) if panel_a_path else get_node_or_null("PanelA")
	_panel_b = get_node_or_null(panel_b_path) if panel_b_path else get_node_or_null("PanelB")
	_tremor = get_node_or_null("TremorZone")
	_sfx_open = get_node_or_null("SFX/SFX Open")

	# Unificar el material emisivo del borde en una copia local para poder cambiarlo por
	# instancia sin afectar otras compuertas que compartan el .tscn.
	var glow_group = get_node_or_null("EdgeLights")
	if glow_group:
		var glow_nodes: Array = []
		for child in glow_group.get_children():
			if child is CSGShape and child.material != null:
				glow_nodes.append(child)
		if glow_nodes.size() > 0:
			_glow_material = glow_nodes[0].material.duplicate() as SpatialMaterial
			if _glow_material:
				_glow_material.resource_local_to_scene = true
				for n in glow_nodes:
					n.material = _glow_material
	for child in get_children():
		if child is OmniLight:
			_edge_lights.append(child)

# --- INTERFAZ PUBLICA ---

func open(immediate: bool = false) -> void:
	if is_active and not immediate:
		return
	if not immediate:
		if _sfx_open and _sfx_open.has_method("play_sfx"):
			_sfx_open.play_sfx()
		if _tremor and _tremor.has_method("set_active"):
			_tremor.set_active(true)
	set_active(true, immediate)

func close(immediate: bool = false) -> void:
	if not is_active and not immediate:
		return
	set_active(false, immediate)

# Callback listo para conectar a la senal blast_door_open del director (T2).
func on_blast_door_open() -> void:
	open(false)

func is_open() -> bool:
	return is_active

func set_network_healthy_count(count: int) -> void:
	_healthy_count = int(clamp(count, 0, 4))
	_apply_semaphore()
	if _wants_continuous_step():
		set_physics_process(true)

func get_network_healthy_count() -> int:
	return _healthy_count

func _maybe_connect_director() -> void:
	if not autoconnect_director:
		return
	var director = get_node_or_null("/root/DomeSystemDirector")
	if director == null:
		return
	if director.has_signal("blast_door_open") and not director.is_connected("blast_door_open", self, "on_blast_door_open"):
		director.connect("blast_door_open", self, "on_blast_door_open")

# --- ANIMACION DETERMINISTA ---

func _update_visuals() -> void:
	var eased: float = _ease_in_out(anim_progress)
	var offset: float = eased * panel_slide
	if _panel_a:
		_panel_a.translation = _panel_a_start - Vector3(offset, 0.0, 0.0)
		_panel_a.force_update_transform()
	if _panel_b:
		_panel_b.translation = _panel_b_start + Vector3(offset, 0.0, 0.0)
		_panel_b.force_update_transform()

func _wants_continuous_step() -> bool:
	# Solo se necesita step vivo mientras el semaforo pulsa (1-2 redes HEALTHY).
	return _healthy_count == 1 or _healthy_count == 2

func step(dt: float) -> void:
	.step(dt)
	if _wants_continuous_step() and not Engine.editor_hint:
		_pulse_phase = fmod(_pulse_phase + dt * pulse_speed, TAU)
		_apply_semaphore()

func _on_animation_completed() -> void:
	._on_animation_completed()
	if is_active:
		emit_signal("opened")
	else:
		emit_signal("closed")

func _apply_semaphore() -> void:
	var color: Color = color_off
	var energy: float = emission_base
	match _healthy_count:
		0:
			color = color_off
			energy = emission_base
		1, 2:
			color = color_restoring
			energy = lerp(emission_base, emission_base + emission_pulse, 0.5 + 0.5 * sin(_pulse_phase))
		3:
			color = color_restoring
			energy = emission_base + emission_pulse * 0.5
		_:
			color = color_ready
			energy = emission_base + emission_pulse

	if _glow_material:
		_glow_material.emission = color
		_glow_material.emission_energy = energy
	for light in _edge_lights:
		if is_instance_valid(light):
			light.light_color = color
			light.light_energy = energy

# --- SNAPSHOT ---

func get_snapshot() -> Dictionary:
	var snap: Dictionary = .get_snapshot()
	snap["healthy_count"] = _healthy_count
	snap["pulse_phase"] = _pulse_phase
	snap["panel_slide"] = panel_slide
	return snap

func restore_snapshot(data: Dictionary) -> void:
	if not is_inside_tree():
		_pending_snapshot = data.duplicate(true)
		return
	_healthy_count = int(data.get("healthy_count", _healthy_count))
	_pulse_phase = float(data.get("pulse_phase", 0.0))
	if data.has("panel_slide"):
		panel_slide = float(data["panel_slide"])
	.restore_snapshot(data)
	_apply_semaphore()
	# Reanudar animacion si el snapshot quedo a mitad de camino (o el pulso sigue vivo).
	if abs(anim_progress - target_progress) > 0.001 or _wants_continuous_step():
		set_physics_process(true)
