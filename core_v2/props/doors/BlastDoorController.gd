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
# Transit-Run: si existe /root/DomeSystemDirector con la senal maintenance_open, se conecta
# solo a open_maintenance() ademas de blast_door_open. Documentado en el Inspector.
export(bool) var autoconnect_maintenance := true
# Transit-Run: la apertura por MANTENIMIENTO (forzada por el jugador) retrae SOLO el panel B
# (+X), dejando un paso lateral franco al pozo/rampa de servicio = ruta principal lenta. El
# blast door por 4/4 (on_blast_door_open) sigue siendo el atajo rapido (ambos paneles +
# plataforma). En false, mantenimiento abre ambos paneles. Documentado en el Inspector.
export(bool) var maintenance_opens_panel_b_only := true

# --- STATE (snapshot) ---
var _healthy_count := 0
var _pulse_phase := 0.0
# Transit-Run: true cuando el descenso se abrio por la ruta de mantenimiento (sin redes).
var _maintenance_open := false
# Progreso propio del panel A (0..1) y su objetivo. Mantenimiento (solo panel B) y el atajo por
# 4/4 (ambos paneles) tienen que componer en CUALQUIER orden sin volver a cerrar el panel A:
# por eso el panel A no se deriva del flag de mantenimiento sino de su propio progreso.
var _panel_a_progress := 0.0
var _panel_a_target := 0.0

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
	# Si la compuerta arranca abierta (starts_active), el panel A tambien arranca afuera.
	if is_active:
		_panel_a_target = 1.0
		_panel_a_progress = 1.0
		_update_visuals()
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
	# Apertura completa (atajo): ambos paneles.
	_set_full_open(true)
	if is_active and not immediate:
		# Ya abierta por mantenimiento (panel A aun cerrado): PROMOVER a apertura completa sin
		# volver a cerrar nada; el panel A anima su propio progreso.
		if _panel_a_progress != _panel_a_target:
			set_physics_process(true)
		_update_visuals()
		return
	if not immediate:
		if _sfx_open and _sfx_open.has_method("play_sfx"):
			_sfx_open.play_sfx()
		if _tremor and _tremor.has_method("set_active"):
			_tremor.set_active(true)
	if immediate:
		_panel_a_progress = _panel_a_target
	set_active(true, immediate)

func close(immediate: bool = false) -> void:
	_set_full_open(false)
	if not is_active and not immediate:
		return
	if immediate:
		_panel_a_progress = 0.0
	set_active(false, immediate)

# Callback listo para conectar a la senal blast_door_open del director (T2).
func on_blast_door_open() -> void:
	open(false)

# Transit-Run: apertura forzada por el jugador (ruta principal de mantenimiento). NO exige
# redes HEALTHY. Por defecto retrae solo el panel B (paso lateral al pozo/rampa = descenso
# lento). Si el descenso YA esta abierto (p.ej. por 4/4) NO lo degrada: preserva la apertura
# completa. Determinista: estado puro funcion del input (sin randf ni tiempo de pared).
func open_maintenance() -> void:
	_maintenance_open = true
	if is_active:
		return
	_set_full_open(not maintenance_opens_panel_b_only)
	set_active(true, false)

func is_maintenance_open() -> bool:
	return _maintenance_open

func _set_full_open(want: bool) -> void:
	# `_panel_a_target` es 1 cuando la apertura debe incluir el panel A (atajo 4/4, o
	# mantenimiento con maintenance_opens_panel_b_only=false); 0 cuando el panel A queda como
	# sello (mantenimiento por defecto).
	_panel_a_target = 1.0 if want else 0.0

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
	if autoconnect_maintenance and director.has_signal("maintenance_open") and not director.is_connected("maintenance_open", self, "open_maintenance"):
		director.connect("maintenance_open", self, "open_maintenance")

# --- ANIMACION DETERMINISTA ---

func _update_visuals() -> void:
	# Panel B: progreso del door (ambos modos lo retraen). Panel A: su propio progreso, para
	# que mantenimiento (cerrado) y el atajo 4/4 (abierto) compongan en cualquier orden.
	var offset_b: float = _ease_in_out(anim_progress) * panel_slide
	var offset_a: float = _ease_in_out(_panel_a_progress) * panel_slide
	if _panel_a:
		_panel_a.translation = _panel_a_start - Vector3(offset_a, 0.0, 0.0)
		_panel_a.force_update_transform()
	if _panel_b:
		_panel_b.translation = _panel_b_start + Vector3(offset_b, 0.0, 0.0)
		_panel_b.force_update_transform()

func _wants_continuous_step() -> bool:
	# Step vivo mientras el semaforo pulsa (1-2 redes HEALTHY) o el panel A sigue animando.
	if _healthy_count == 1 or _healthy_count == 2:
		return true
	return abs(_panel_a_progress - _panel_a_target) > 0.001

func step(dt: float) -> void:
	.step(dt)
	if Engine.editor_hint:
		return
	_advance_panel_a(dt)
	if _healthy_count == 1 or _healthy_count == 2:
		_pulse_phase = fmod(_pulse_phase + dt * pulse_speed, TAU)
		_apply_semaphore()

# Avanza el progreso propio del panel A hacia su objetivo (misma ley que el panel B: velocidad
# constante y luego el easing en _update_visuals). Sin randf ni tiempo de pared.
func _advance_panel_a(dt: float) -> void:
	if abs(_panel_a_progress - _panel_a_target) < 0.001:
		if _panel_a_progress != _panel_a_target:
			_panel_a_progress = _panel_a_target
			_update_visuals()
		return
	var direction: float = sign(_panel_a_target - _panel_a_progress)
	_panel_a_progress += direction * anim_speed * dt
	if direction > 0.0 and _panel_a_progress >= _panel_a_target:
		_panel_a_progress = _panel_a_target
	elif direction < 0.0 and _panel_a_progress <= _panel_a_target:
		_panel_a_progress = _panel_a_target
	_update_visuals()

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
	snap["maintenance_open"] = _maintenance_open
	snap["panel_a_progress"] = _panel_a_progress
	snap["panel_a_target"] = _panel_a_target
	return snap

func restore_snapshot(data: Dictionary) -> void:
	if not is_inside_tree():
		_pending_snapshot = data.duplicate(true)
		return
	_healthy_count = int(data.get("healthy_count", _healthy_count))
	_pulse_phase = float(data.get("pulse_phase", 0.0))
	_maintenance_open = bool(data.get("maintenance_open", _maintenance_open))
	_panel_a_progress = float(data.get("panel_a_progress", _panel_a_progress))
	_panel_a_target = float(data.get("panel_a_target", _panel_a_target))
	if data.has("panel_slide"):
		panel_slide = float(data["panel_slide"])
	.restore_snapshot(data)
	_apply_semaphore()
	# Reanudar animacion si el snapshot quedo a mitad de camino (o el pulso sigue vivo).
	if abs(anim_progress - target_progress) > 0.001 or _wants_continuous_step():
		set_physics_process(true)
