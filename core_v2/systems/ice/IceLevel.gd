tool
extends Spatial
class_name IceLevel

# FD-051: la amenaza ascendente del domo.
#
# CAPA LÓGICA. El estado que importa es un solo float (`ice_height`). La muerte se decide
# comparando la Y de los cuerpos del grupo `fire_vulnerable` contra ese float. Cero
# partículas involucradas: si se apagara todo el render, la amenaza sería idéntica.
#
# El visual (IceVisualBand) y la viñeta cabalgan sobre las señales de este nodo y nunca
# le escriben de vuelta.

signal ice_height_changed(height)
# dps ya viene multiplicado por core_damage_multiplier si el cuerpo está bajo la línea.
signal frost_contact(body, dps, in_core)
signal ice_started()
# El intento anterior terminó: la capa visual debe soltar lo que quedó pegado del hielo
# viejo (parches, partículas en vuelo, altura de dibujo) en vez de arrastrarlo al respawn.
signal ice_visuals_reset()

const GROUP_VULNERABLE := "ice_vulnerable"
const GROUP_SELF := "ice_level"

# m/s de subida inicial (calibrar vs ~30s de escalada).
export(float) var base_speed := 0.15
# m/s^2 de aceleración (0 = velocidad constante).
export(float) var accel := 0.0
# Pulsación determinista de la subida: altera el ritmo, nunca el estado aleatoriamente.
export(float, 0.0, 0.5) var rise_twitch_amount := 0.08
export(float) var rise_twitch_frequency := 0.85
# Y inicial de la línea de hielo.
export(float) var start_height := -0.2

# Techo opcional de la subida. Menor o igual a start_height = sin techo.
export(float) var max_height := 0.0
# Profundidad superficial que Elías puede pisar antes de recibir daño.
export(float) var walkable_surface_depth := 0.85
# Profundidad de inmersión desde la que se aplica el multiplicador de núcleo.
export(float) var core_submersion_depth := 1.25
# Drenaje de integridad por segundo en zona de frío.
export(float) var damage_per_second := 25.0
# Multiplicador de drenaje bajo la línea real del hielo.
export(float) var core_damage_multiplier := 4.0
# Arranca subiendo solo, o espera un start() explícito.
export(bool) var auto_start := true
# Altura entre fracturas audibles de la capa de hielo.
export(float) var crack_interval := 2.5
# Dibuja el plano de debug a la altura exacta donde empieza el daño. Usa un shader de
# ruido animado (no un disco rojo plano), así que puede quedar SIEMPRE prendido sin
# desentonar con el flipbook: es la referencia fiel de dónde está ice_height de verdad.
export(bool) var debug_draw := true
# El techo lógico se conserva, pero su segundo raymarch queda apagado por defecto: la
# superficie de hielo ya comunica la amenaza y duplicarlo cuesta un pase volumétrico.
export(bool) var draw_frost_ceiling := false
# Radio mínimo del plano de debug y de la placa de colisión (por defecto el del domo).
# El recorte real lo manda `dome_profile`; esto solo garantiza malla suficiente.
export(float) var debug_plane_radius := 30.0
# Silueta INTERIOR del domo: pares (altura, radio) de la pared, +0.1 para que el borde
# del disco muera DENTRO de la pared opaca en vez de dejar una junta a la vista.
#
# Un radio fijo no sirve: abajo la pared está a 31.35 y un disco de 29.7 dejaba un
# anillo de piso descubierto; arriba la bóveda se cierra (r=21 a y=24.75) y ese mismo
# disco asomaría fuera del domo. Los puntos son los quiebres reales de la cúpula, así
# que interpolar lineal entre ellos reproduce la pared con error <0.01 m.
#
# Medido con `godot3-bin --no-window -s tools/measure_dome_profile.gd` (rayos desde el
# eje contra DomeTerrace_baked.mesh). Volver a correrlo si cambia la cúpula.
export(PoolVector2Array) var dome_profile := PoolVector2Array([
	Vector2(0.0, 31.45),
	Vector2(6.7, 31.45),
	Vector2(13.45, 29.63),
	Vector2(19.6, 26.1),
	Vector2(24.75, 21.06),
	Vector2(28.7, 14.8),
	Vector2(31.0, 8.13)
])
# Altura recorrida necesaria para que el material pase de hielo húmedo a escarcha opaca.
export(float, 0.0, 1.0) var initial_freeze_progress := 0.32
export(float) var visual_freeze_height := 10.0
# Deriva visual continua del PBR mientras sube el hielo. No forma parte del estado lógico
# ni del snapshot: evita saltos visibles y no influye en colisión, daño o replay.
export(float) var uv_drift_speed := 0.65
export(float) var uv_drift_amplitude := 0.0045
# Conserva en desktop la paleta estable de Android sin perder UV, normal, roughness ni AO.
export(bool) var use_mobile_color_pbr := true
# La niebla ambiental del domo permanece activa, pero el hielo no arrastra una banda de
# height-fog con su superficie: esa banda lavaba el plano y parecía iluminación propia.
export(bool) var ice_height_fog_enabled := false
# Imprime height/speed periódicamente por consola (calibración).
export(bool) var debug_readout := false

# NodePath opcional a Room3D para leer la temperatura y evaporar el hielo
export(NodePath) var room_path: NodePath
export(float) var melt_speed := 0.3
export(float) var evap_contamination_rate := 0.08
# El hielo representa el refrigerante que efectivamente salió de los tanques. Si no
# hay tanques en la escena conserva el comportamiento ambiental anterior.
export(bool) var cap_rise_by_coolant_volume := true
# Techo de la columna de criocoolant; Dome_Intro lo calibra al piso cinco. La cantidad
# total de los tanques decide qué fracción de este máximo ya salió de la instalación.
export(float) var max_coolant_height := 18.0
# Fallo visual de luces dinámicas bajo la superficie; no toca la iluminación baked.
export(bool) var fail_submerged_lights := true
export(float) var light_submersion_margin := 0.1

var ice_height := 0.0
var ice_speed := 0.0
var elapsed := 0.0
var is_running := false
# Último progreso de congelamiento aplicado al material (0 = hielo húmedo, 1 = escarcha
# opaca). Se expone porque el valor no se puede leer de vuelta del ShaderMaterial en
# headless: con el rasterizer dummy get_shader_param() devuelve null.
var visual_freeze_progress := 0.0
var visual_uv_offset := Vector2.ZERO
var _visual_uv_time := 0.0

var _debug_plane: MeshInstance = null
var _debug_band: MeshInstance = null
var _readout_timer := 0.0
var _next_crack_height := 0.0
var _crack_player: AudioStreamPlayer3D = null
var _ice_collider: StaticBody = null
var _ice_environment: Environment = null

func _init() -> void:
	add_to_group("replay_sync")

func _ready() -> void:
	add_to_group(GROUP_SELF)
	ice_height = start_height
	ice_speed = base_speed
	elapsed = 0.0
	_next_crack_height = start_height + max(crack_interval, 0.1)
	_crack_player = get_node_or_null("IceCrackSound")
	_ice_environment = _find_environment()
	_ensure_ice_collider()
	_ensure_debug_nodes()
	_update_debug_visuals()
	_update_ice_collider()
	_update_ice_fog()
	if Engine.editor_hint:
		return
	if auto_start:
		start()

func start() -> void:
	if is_running:
		return
	is_running = true
	emit_signal("ice_started")

func stop() -> void:
	is_running = false

func reset() -> void:
	ice_height = start_height
	ice_speed = base_speed
	elapsed = 0.0
	is_running = auto_start
	emit_signal("ice_height_changed", ice_height)
	_reset_ice_visuals()
	_update_debug_visuals()
	_update_ice_collider()
	_update_ice_fog()

# Todo camino que resetea la presentacion (reset, respawn, restore de checkpoint) tiene
# que callar la fractura en curso y re-armar el cursor de cracks contra la altura nueva:
# el stream dura 7 s y sobrevivia al respawn sonando encima del intento siguiente, y el
# cursor viejo quedaba por encima de la linea, mudo hasta volver a treparla.
func _reset_ice_visuals() -> void:
	if is_instance_valid(_crack_player):
		_crack_player.stop()
	_next_crack_height = ice_height + max(crack_interval, 0.1)
	emit_signal("ice_visuals_reset")

# Altura del tope de la zona de frío: por encima de esto no hay daño alguno.
func get_frost_ceiling() -> float:
	return ice_height - walkable_surface_depth

# Hasta dónde llega el hielo a una altura dada: el radio de la pared del domo ahí.
# Lo consulta también la capa de partículas (IceVisualBand), para que la escarcha
# trepe por la pared real y no por un cilindro imaginario.
func get_surface_radius_at(height: float) -> float:
	var count: int = dome_profile.size()
	if count == 0:
		return max(debug_plane_radius, 1.0)
	if height <= dome_profile[0].x:
		return dome_profile[0].y
	for i in range(1, count):
		var previous: Vector2 = dome_profile[i - 1]
		var next: Vector2 = dome_profile[i]
		if height > next.x:
			continue
		var span: float = next.x - previous.x
		if span <= 0.0:
			return next.y
		return lerp(previous.y, next.y, (height - previous.x) / span)
	return dome_profile[count - 1].y

func get_surface_radius() -> float:
	return get_surface_radius_at(ice_height)

# Extensión que necesitan la malla del plano y la placa de colisión: nunca menor que
# el punto más ancho del perfil, o el disco se cortaría en recto antes de la pared.
func _max_surface_radius() -> float:
	var maximum: float = max(debug_plane_radius, 1.0)
	for point in dome_profile:
		maximum = max(maximum, point.y)
	return maximum

# Margen de seguridad exigido entre un punto de respawn y la línea de hielo.
export(float) var respawn_safety_margin := 3.0

# FD-051: al morir, el respawn no debe reaparecer bajo o dentro de la zona de frío.
# Congela (nunca retrocede el avance ya ganado) ice_height por debajo de
# `respawn_y - respawn_safety_margin - heat_band - fire_contact_margin`, de forma que el
# punto de respawn quede fuera de la zona de frío. No es un reset a start_height: si el
# jugador murió muy arriba, el hielo sigue estando alto, solo se le da margen justo al
# checkpoint. Determinista: mismo respawn_y siempre da el mismo clamp.
func ensure_safe_for_respawn(respawn_y: float) -> void:
	# La línea inicial es el piso lógico y visual del sistema. Bajarlo por debajo de
	# start_height para ganar margen entierra IceSurface y deja un respawn sin hielo
	# visible; un spawn por debajo de esa base debe corregirse en el SpawnPoint, no
	# deformar el estado del nivel.
	var max_allowed: float = max(start_height, respawn_y - respawn_safety_margin)
	if ice_height > max_allowed:
		ice_height = max_allowed
		emit_signal("ice_height_changed", ice_height)
		_update_debug_visuals()
		_update_ice_collider()
		_update_ice_fog()
	# Siempre, aun sin clamp: la escarcha adherida y las partículas del intento anterior
	# quedaron a la altura donde murió Elías, no donde reaparece.
	_reset_ice_visuals()

# Consulta barata para props destructibles y lógica externa.
func is_point_frozen(point: Vector3) -> bool:
	return point.y <= ice_height

func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		_update_debug_visuals()
		return
	# Durante la reproduccion de un hotzone este nodo NO debe avanzar con el reloj de pared:
	# lo maneja HotzonePlayer llamando step(dt) con el delta grabado, en lockstep con el
	# jugador. Antes el hielo subia al ritmo del dispositivo que reproducia, no al de la
	# grabacion, y como la simulacion del jugador depende de la linea de hielo (profundidad
	# pisable, dano, colision) esa era una fuente directa de divergencia.
	if _is_hotzone_playback():
		return
	step(delta)


func _is_hotzone_playback() -> bool:
	var sm = get_node_or_null("/root/SessionManager")
	return sm != null and bool(sm.get("is_hotzone_playback"))


# Avance determinista de la linea de hielo. Separado de _physics_process para que el
# replay pueda invocarlo con el delta grabado en vez del delta real del frame.
func step(delta: float) -> void:
	var coolant_flow_amount: float = _get_coolant_leak_flow()
	var coolant_flow_active: bool = coolant_flow_amount > 0.0001
	var room_is_freezing := false
	var room_is_cold_for_damage := true
	var room_is_warm := false
	var room: Node = null
	if room_path != null and not room_path.is_empty():
		room = get_node_or_null(room_path)
		if room != null:
			var room_temp: float = float(room.get("temperature"))
			var freeze_pt: float = float(room.get("freezing_point"))
			room_is_freezing = room_temp <= freeze_pt
			room_is_cold_for_damage = room_temp < freeze_pt
			room_is_warm = room_temp > freeze_pt
			if room_is_freezing and coolant_flow_active:
				if not is_running:
					start()
			elif is_running:
				stop()

	# Cerrar las fugas conserva el hielo. Solo una fuente de calor que lleve la sala
	# por encima del umbral lo derrite y libera el vapor ambiental heredado de FD-269.
	if room_is_warm:
		if ice_height > start_height:
			ice_height = max(start_height, ice_height - melt_speed * delta)
			if room != null and room.has_method("add_contamination"):
				room.call("add_contamination", evap_contamination_rate * delta)
			emit_signal("ice_height_changed", ice_height)
			_update_ice_collider()
			_update_ice_fog()
			_update_submerged_lights()
			_update_debug_visuals()
		return

	# Una válvula cerrada o un tanque vacío conserva el volumen que ya se congeló;
	# no se derrite ni sigue persiguiendo refrigerante drenado antes del cierre.
	if not coolant_flow_active:
		if is_running:
			stop()
		# El hielo detenido sigue siendo letal mientras la sala permanezca bajo cero.
		if room_is_cold_for_damage:
			_scan_vulnerable_bodies(delta)
		return

	if not is_running:
		return

	# El volumen fugado es el techo del hielo, no una orden de teletransportar la
	# superficie. Al cruzar 0°C puede haber refrigerante ya drenado: alcanzarlo en un
	# tick ocultaba el piso de hielo y dejaba a Elías dentro del volumen.
	var coolant_height: float = _get_coolant_height_cap()
	elapsed += delta
	var base_rise_speed: float = base_speed + accel * elapsed
	var rise_pulse: float = sin(elapsed * TAU * rise_twitch_frequency) * 0.68
	rise_pulse += sin(elapsed * TAU * rise_twitch_frequency * 2.37 + 1.9) * 0.32
	ice_speed = base_rise_speed * clamp(1.0 + rise_pulse * rise_twitch_amount, 0.55, 1.45)
	# Cada fuga activa añade caudal al volumen que se congela: dos fugas plenas suben
	# el doble que una, y las rampas de CoolantLeak se reflejan sin saltos visuales.
	ice_speed *= coolant_flow_amount
	if coolant_height != INF:
		var previous_height: float = ice_height
		# Drenar es irreversible; si un tanque se rellena por una corrección externa no
		# hacemos desaparecer hielo. El derretimiento sigue siendo responsabilidad de
		# Room3D cuando la temperatura vuelve a estar sobre freezing_point.
		var target_height: float = max(ice_height, coolant_height)
		ice_height = min(target_height, ice_height + ice_speed * delta)
		if is_equal_approx(ice_height, target_height):
			stop()
		_update_ice_collider()
		_update_ice_fog()
		_update_submerged_lights()
		if ice_height > previous_height:
			_emit_cracks_until_current_height()
			emit_signal("ice_height_changed", ice_height)
			if room_is_cold_for_damage:
				_scan_vulnerable_bodies(delta)
			_update_debug_visuals()
		return

	ice_height += ice_speed * delta
	_update_ice_collider()
	_update_ice_fog()
	_update_submerged_lights()
	_emit_cracks_until_current_height()
	if max_height > start_height:
		ice_height = min(ice_height, max_height)

	emit_signal("ice_height_changed", ice_height)
	if room_is_cold_for_damage:
		_scan_vulnerable_bodies(delta)
	_update_debug_visuals()

	if debug_readout:
		_readout_timer += delta
		if _readout_timer >= 1.0:
			_readout_timer = 0.0
			print("[IceLevel] height=%.2f speed=%.3f elapsed=%.1f" % [ice_height, ice_speed, elapsed])


func _emit_cracks_until_current_height() -> void:
	if not is_instance_valid(_crack_player):
		return
	while ice_height >= _next_crack_height:
		# La posición es solo presentación; la altura y el estado de gameplay no
		# dependen de este efecto audiovisual.
		var crack_angle := randf() * TAU
		var crack_radius := debug_plane_radius * sqrt(randf())
		_crack_player.transform.origin = Vector3(cos(crack_angle) * crack_radius, ice_height, sin(crack_angle) * crack_radius)
		_crack_player.play()
		_next_crack_height += max(crack_interval, 0.1)


func _get_coolant_height_cap() -> float:
	if not cap_rise_by_coolant_volume or get_tree() == null:
		return INF
	var tanks: Array = get_tree().get_nodes_in_group("coolant_source")
	if tanks.empty():
		return INF
	var total_capacity := 0.0
	var remaining_coolant := 0.0
	for tank in tanks:
		if not is_instance_valid(tank) or not ("tank_level" in tank):
			continue
		var capacity: float = float(tank.get("coolant_capacity")) if "coolant_capacity" in tank else 1.0
		capacity = max(capacity, 0.0)
		total_capacity += capacity
		remaining_coolant += clamp(float(tank.get("tank_level")), 0.0, 1.0) * capacity
	if total_capacity <= 0.0:
		return INF
	var leaked_fraction: float = clamp((total_capacity - remaining_coolant) / total_capacity, 0.0, 1.0)
	return start_height + max(max_coolant_height, 0.0) * leaked_fraction


func _get_coolant_leak_flow() -> float:
	if get_tree() == null:
		return 0.0
	var tanks: Array = get_tree().get_nodes_in_group("coolant_source")
	if tanks.empty():
		# Escenas atmosféricas legacy sin tanques conservan la subida por temperatura.
		return 1.0
	var has_coolant := false
	for tank in tanks:
		if is_instance_valid(tank) and "tank_level" in tank and float(tank.get("tank_level")) > 0.0001:
			has_coolant = true
			break
	if not has_coolant:
		return 0.0
	var leaks: Array = get_tree().get_nodes_in_group("coolant_leak")
	if leaks.empty():
		# Conserva compatibilidad con escenas/tests que aún no usan CoolantLeak.
		return 1.0
	var total_flow := 0.0
	for leak in leaks:
		if is_instance_valid(leak) and leak.has_method("get_leak_intensity"):
			total_flow += max(0.0, float(leak.call("get_leak_intensity")))
	return total_flow


# Indice de luces ordenado por altura + cursor, en vez de recorrer el arbol entero.
# Esto se llama en CADA tick mientras el hielo sube, y recorrer los ~2400 nodos de
# Dome_Intro armando un Array por tick marcaba 81 ms de 84 en el profiler (el mayor costo
# del frame despues de la rotura). Como la respuesta solo depende de la altura del hielo,
# alcanza con ordenar las luces una vez y mover un cursor: mismo patron que
# IceSubmergedCuller, que ya resolvia esto para las colisiones.
#
# ponytail: el indice se arma una sola vez. Una luz que se INSTANCIE despues (el fogonazo
# de una explosion) o que BAJE hasta el hielo no queda contemplada; si algun dia hace falta,
# reindexar en el mismo evento que la crea, no volver a barrer por tick.
var _light_entries: Array = []
var _light_cursor: int = 0
var _lights_indexed := false


func _index_submerged_lights() -> void:
	_light_entries = []
	_light_cursor = 0
	if get_tree() == null:
		return
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var pending: Array = [scene]
	while not pending.empty():
		var node: Node = pending.pop_back()
		if node is Light and not (node is DirectionalLight):
			var light: Light = node as Light
			_light_entries.append({
				"light": light,
				"y": light.global_transform.origin.y + light_submersion_margin,
				"apagada_por_nosotros": false
			})
		for child in node.get_children():
			pending.append(child)
	_light_entries.sort_custom(self, "_por_altura_de_luz")
	_lights_indexed = true


func _por_altura_de_luz(a, b) -> bool:
	return a.y < b.y


func _update_submerged_lights() -> void:
	if not fail_submerged_lights or get_tree() == null:
		return
	if not _lights_indexed:
		_index_submerged_lights()
	# El hielo subio: apagar lo que quedo sepultado.
	while _light_cursor < _light_entries.size() and _light_entries[_light_cursor].y <= ice_height:
		var e = _light_entries[_light_cursor]
		if is_instance_valid(e.light) and e.light.visible:
			e.light.visible = false
			e.apagada_por_nosotros = true
		_light_cursor += 1
	# El hielo bajo (derretimiento, o restore de un checkpoint): devolver SOLO las que
	# apagamos nosotros, para no pisar a quien las haya apagado por otro motivo
	# (MobileLightBudget, por ejemplo). El codigo anterior nunca las devolvia: una vez
	# sepultada, la luz quedaba apagada aunque el hielo se derritiera del todo.
	while _light_cursor > 0 and _light_entries[_light_cursor - 1].y > ice_height:
		_light_cursor -= 1
		var e2 = _light_entries[_light_cursor]
		if is_instance_valid(e2.light) and e2.apagada_por_nosotros:
			e2.light.visible = true
			e2.apagada_por_nosotros = false

func _process(delta: float) -> void:
	if Engine.editor_hint or not is_running:
		return
	# En GLES2 móvil la precisión y el frame pacing convierten esta deriva subpíxel en
	# saltos visibles. El plano conserva el PBR, pero su origen UV queda estable.
	if OS.get_name() in ["Android", "iOS"]:
		visual_uv_offset = Vector2.ZERO
		return
	_visual_uv_time += delta * max(uv_drift_speed, 0.0)
	var twitch_drift: Vector2 = Vector2(
		clamp(sin(_visual_uv_time * 5.3 + 0.4) * 2.8, -1.0, 1.0) * 0.68 + sin(_visual_uv_time * 19.1) * 0.32,
		clamp(sin(_visual_uv_time * 7.7 + 2.1) * 2.6, -1.0, 1.0) * 0.64 + sin(_visual_uv_time * 23.3 + 1.2) * 0.36
	)
	visual_uv_offset = twitch_drift * max(uv_drift_amplitude, 0.0)
	if is_instance_valid(_debug_plane) and _debug_plane.material_override is ShaderMaterial:
		_debug_plane.material_override.set_shader_param("uv_offset", visual_uv_offset)

func _scan_vulnerable_bodies(_delta: float) -> void:
	for body in get_tree().get_nodes_in_group(GROUP_VULNERABLE):
		if not is_instance_valid(body) or not (body is Spatial):
			continue
		var feet_y: float = body.global_transform.origin.y - 1.0 if body.has_method("set_ice_submersion") else body.global_transform.origin.y
		var submersion_depth: float = ice_height - feet_y
		if body.has_method("set_ice_submersion"):
			body.set_ice_submersion(max(submersion_depth, 0.0))
		if submersion_depth <= walkable_surface_depth:
			continue
		var in_core: bool = submersion_depth >= core_submersion_depth
		var dps := damage_per_second
		if in_core:
			dps *= core_damage_multiplier
		emit_signal("frost_contact", body, dps, in_core)

func _find_environment() -> Environment:
	var world := get_node_or_null("../WorldEnvironment") as WorldEnvironment
	return world.environment if world else null

const ICE_FOOTSTEP_PROFILE := preload("res://core_v2/audio/footsteps/footstep_profile_ice.tres")

func _ensure_ice_collider() -> void:
	_ice_collider = get_node_or_null("IceCollider") as StaticBody
	if _ice_collider == null:
		_ice_collider = StaticBody.new()
		_ice_collider.name = "IceCollider"
		_ice_collider.collision_layer = 1
		_ice_collider.collision_mask = 0
		var shape_node := CollisionShape.new()
		shape_node.shape = BoxShape.new()
		_ice_collider.add_child(shape_node)
		add_child(_ice_collider)
	# Elías pisa esta placa una vez el hielo sube por encima del piso real: sin esto
	# FootstepDetector caía al fallback genérico también sobre hielo ya subido.
	_ice_collider.set_meta("footstep_profile", ICE_FOOTSTEP_PROFILE)
	# La placa que se pisa debe llegar tan lejos como el disco visible: si se queda
	# corta, junto a la pared se ve hielo pero se cae al piso de abajo. Es una caja
	# (cubre de más en las diagonales), pero ahí la pared del domo ya frena al jugador.
	var extent: float = _max_surface_radius()
	for child in _ice_collider.get_children():
		if child is CollisionShape and child.shape is BoxShape:
			child.shape.extents = Vector3(extent, 0.1, extent)

func _update_ice_collider() -> void:
	if is_instance_valid(_ice_collider):
		var target_y := ice_height - 0.1
		for body in get_tree().get_nodes_in_group(GROUP_VULNERABLE):
			if is_instance_valid(body) and body is Spatial and body.has_method("set_ice_submersion"):
				var feet_y: float = body.global_transform.origin.y - 1.0
				if ice_height >= feet_y - 0.02:
					target_y = min(target_y, _ice_collider.global_transform.origin.y)
		_ice_collider.global_transform.origin.y = target_y

func _update_ice_fog() -> void:
	if not is_instance_valid(_ice_environment):
		return
	_ice_environment.fog_height_enabled = ice_height_fog_enabled
	if not ice_height_fog_enabled:
		return
	_ice_environment.fog_height_min = ice_height + 0.65
	_ice_environment.fog_height_max = ice_height - 2.6

# --- DEBUG ---

const DEBUG_SHADER_PATH := "res://core_v2/systems/ice/shaders/transparent_ice.shader"
const ICE_COLOR_TEXTURE := preload("res://assets/textures/Ice/ice_0002_color_1k.jpg")
const ICE_NORMAL_TEXTURE := preload("res://assets/textures/Ice/ice_0002_normal_opengl_1k.png")
const ICE_ROUGHNESS_TEXTURE := preload("res://assets/textures/Ice/ice_0002_roughness_1k.jpg")
const ICE_AO_TEXTURE := preload("res://assets/textures/Ice/ice_0002_ao_1k.jpg")

func _ensure_debug_nodes() -> void:
	_debug_plane = get_node_or_null("IceSurface")
	if _debug_plane == null:
		_debug_plane = _make_debug_plane("IceSurface", Color(0.08, 0.42, 1.0, 0.82), 0.9)
	_debug_band = get_node_or_null("FrostCeiling")
	if _debug_band == null:
		_debug_band = _make_debug_plane("FrostCeiling", Color(0.55, 0.85, 1.0, 0.28), 0.35)
	_apply_ice_textures(_debug_plane)
	_apply_ice_textures(_debug_band)
	_fit_plane_mesh(_debug_plane)
	_fit_plane_mesh(_debug_band)

func _apply_ice_textures(instance: MeshInstance) -> void:
	if instance == null or not (instance.material_override is ShaderMaterial):
		return
	var material: ShaderMaterial = instance.material_override
	material.set_shader_param("ice_texture", ICE_COLOR_TEXTURE)
	material.set_shader_param("ice_normal", ICE_NORMAL_TEXTURE)
	material.set_shader_param("ice_roughness", ICE_ROUGHNESS_TEXTURE)
	material.set_shader_param("ice_ao", ICE_AO_TEXTURE)
	material.set_shader_param("low_end_mobile", OS.get_name() in ["Android", "iOS"])
	material.set_shader_param("mobile_color_pbr", use_mobile_color_pbr)

# El shader recorta el disco, pero no puede dibujar más allá de la malla: si el plano
# de la escena quedó chico para el perfil, el borde se corta recto contra el aire.
func _fit_plane_mesh(instance: MeshInstance) -> void:
	if instance == null or not (instance.mesh is PlaneMesh):
		return
	var plane: PlaneMesh = instance.mesh
	var needed: float = _max_surface_radius() * 2.0
	if plane.size.x < needed or plane.size.y < needed:
		plane.size = Vector2(max(plane.size.x, needed), max(plane.size.y, needed))

# Ruido animado en vez de un disco de color plano: pensado para quedar SIEMPRE visible
# (referencia fiel de ice_height/heat_ceiling) sin desentonar con el flipbook real.
func _make_debug_plane(node_name: String, color: Color, density: float) -> MeshInstance:
	var instance := MeshInstance.new()
	instance.name = node_name
	var plane := PlaneMesh.new()
	plane.size = Vector2(_max_surface_radius() * 2.0, _max_surface_radius() * 2.0)
	instance.mesh = plane
	var material := ShaderMaterial.new()
	var shader = load(DEBUG_SHADER_PATH)
	if shader:
		material.shader = shader
		material.set_shader_param("albedo", color)
		material.set_shader_param("opacity", density * 0.5)
		material.set_shader_param("ice_texture", ICE_COLOR_TEXTURE)
		material.set_shader_param("ice_normal", ICE_NORMAL_TEXTURE)
		material.set_shader_param("ice_roughness", ICE_ROUGHNESS_TEXTURE)
		material.set_shader_param("ice_ao", ICE_AO_TEXTURE)
	instance.material_override = material
	instance.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	if Engine.editor_hint and get_tree() and get_tree().edited_scene_root:
		instance.owner = get_tree().edited_scene_root
	return instance

func _update_debug_visuals() -> void:
	if is_instance_valid(_debug_plane):
		# La superficie de hielo no debe dibujarse hasta que el hielo arranca a subir:
		# apagada al inicio evita el z-fighting contra el piso del domo. debug_draw
		# la fuerza visible para calibrar ice_height sin esperar el descenso térmico.
		var show_surface: bool = debug_draw or ice_height > start_height
		_debug_plane.visible = show_surface
		if show_surface:
			var t := _debug_plane.transform
			t.origin = Vector3(0.0, to_local(Vector3(0.0, ice_height, 0.0)).y, 0.0)
			_debug_plane.transform = t
			var freeze_distance: float = max(visual_freeze_height, 0.001)
			var rise_progress: float = clamp((ice_height - start_height) / freeze_distance, 0.0, 1.0)
			visual_freeze_progress = lerp(clamp(initial_freeze_progress, 0.0, 1.0), 1.0, rise_progress)
			var material: Material = _debug_plane.material_override
			if material is ShaderMaterial:
				material.set_shader_param("freeze_progress", visual_freeze_progress)
				# El disco se ensancha o angosta con la pared del domo a esta altura.
				material.set_shader_param("surface_radius", get_surface_radius_at(ice_height))
	if is_instance_valid(_debug_band):
		_debug_band.visible = debug_draw and draw_frost_ceiling
		if debug_draw and draw_frost_ceiling:
			var ceiling: float = get_frost_ceiling()
			var tb := _debug_band.transform
			tb.origin = Vector3(0.0, to_local(Vector3(0.0, ceiling, 0.0)).y, 0.0)
			_debug_band.transform = tb
			var band_material: Material = _debug_band.material_override
			if band_material is ShaderMaterial:
				band_material.set_shader_param("surface_radius", get_surface_radius_at(ceiling))

# --- REPLAY ---

func get_snapshot() -> Dictionary:
	return {
		"ice_height": ice_height,
		"ice_speed": ice_speed,
		"elapsed": elapsed,
		"is_running": is_running
	}

func restore_snapshot(data: Dictionary) -> void:
	ice_height = float(data.get("ice_height", start_height))
	ice_speed = float(data.get("ice_speed", base_speed))
	elapsed = float(data.get("elapsed", 0.0))
	is_running = bool(data.get("is_running", auto_start))
	emit_signal("ice_height_changed", ice_height)
	# IceVisualBand es presentación y no entra al snapshot. Al restaurar una altura de
	# checkpoint debe vaciar sus partículas viejas y tomar esta altura de inmediato.
	_reset_ice_visuals()
	_update_debug_visuals()
	_update_ice_collider()
	_update_ice_fog()
	_update_submerged_lights()
