extends Spatial
class_name IceVisualBand

# FD-051: capa VISUAL del hielo. Cabalga sobre `ice_height` y nunca lo alimenta de vuelta.
#
# Reutiliza GasParticleManager (FD-045) configurado como banda de hielo: emite partículas en
# un arco anular a la altura de la línea de hielo, solo en el sector cercano a la cámara.
# El resto del anillo no gasta partículas. `collide_with_world` va en false (sin raycast por
# partícula) — ese es el techo de coste.
#
# Si por LOD no hay partículas en un sector, el ice_height lógico sigue matando ahí igual.
# Nada de esto entra al snapshot: se reconstruye desde el estado lógico.

# Radio exterior del hielo (pared del domo). El hielo cubre todo el disco interior hasta
# acá, no solo un anillo delgado: la superficie completa del piso bajo ice_height arde.
export(float) var ring_radius := 28.0
# Si es true, solo emite en una franja delgada cerca de ring_radius (comportamiento viejo,
# "anillo"). Si es false (default), cubre todo el disco desde el centro hasta ring_radius,
# como una superficie de hielo completa.
export(bool) var ring_only := false
# Grosor radial de la franja, usado solo cuando ring_only=true.
export(float) var ring_thickness := 3.0
# Partículas emitidas por segundo (techo real lo pone el pool del manager).
export(float) var particles_per_second := 45.0
# Arco del anillo emitido alrededor de la cámara, en grados.
export(float) var visible_arc_deg := 140.0
# Ruido vertical de la línea de hielo (para que no sea plana).
export(float) var line_noise := 0.6
# Suavizado del seguimiento a ice_height.
export(float) var follow_lerp := 12.0
# Velocidad vertical inicial de las lenguas de hielo. Baja a propósito: cada escarcha debe
# nacer y apagarse cerca de ice_height, no viajar varios metros (eso lee como columnas
# verticales en vez de una banda horizontal).
export(float) var frost_rise_speed := 0.35
# Cuánto vive cada lengua de hielo individual (más corto = banda más plana y quieta).
export(float) var frost_lifetime := 0.55
# Escala visual de cada lengua de hielo (base; se varía por burbuja, ver frost_scale_variance).
export(float) var frost_scale := 5.5
# Cuánto varía el tamaño entre partículas (0 = todas iguales, 1 = algunas casi el doble).
# Mezclar tamaños grandes y chicos, muy solapados, es lo que da lectura de masa fluida
# (hielo) en vez de lenguas individuales separadas.
export(float) var frost_scale_variance := 0.5
# Amplitud del "oleaje" de la superficie: ondas continuas (seno) en vez de ruido puro por
# partícula, para que la línea de hielo suba y baje como una superficie de hielo viva.
export(float) var wave_amplitude := 0.5
# Cuántas crestas de ola entran en la vuelta completa del anillo.
export(float) var wave_frequency := 5.0
# Velocidad de desplazamiento del oleaje (rad/s).
export(float) var wave_speed := 0.6
# Solo hielo: color de la hielo más caliente (núcleo de una burbuja/lengua), casi blanco.
export(Color) var hot_color := Color(0.82, 0.95, 1.0, 0.9)
# Solo hielo: color de la hielo más fría (borde/costra), rojo oscuro casi apagado.
export(Color) var cool_color := Color(0.08, 0.32, 0.72, 0.72)
# Cuánto pesa la "temperatura" aleatoria por partícula vs. el ignition_color base del
# manager. 0 = todas iguales (color plano), 1 = varía completo entre hot_color y cool_color.
export(float) var temperature_variance := 0.85
# Cadencia del atlas para hielo. Reduce la variación heredada del manager, que a 32 FPS
# podía llevar algunas escarchas hasta ~64 FPS y hacerlas leer como parpadeo.
export(float) var frost_animation_speed := 0.72
# Luz ambiental única para que la superficie afecte al entorno sin una luz por partícula.
export(float) var ice_light_energy := 0.4
export(float) var ice_light_range := 18.0
# Emite también en el centro (pozo) además del anillo.
export(bool) var emit_center_column := false
export(float) var center_column_radius := 2.5
# Modo corona de humo: emite por encima de ice_height (offset vertical), sin marcar
# combustión (usa el color normal del manager, no la vía de hielo del shader). Pensado
# para un segundo IceVisualBand hijo apuntando a un GasParticleManager con atlas de humo.
export(bool) var is_smoke_crown := false
export(float) var smoke_height_offset := 1.5
# Altura global de la bóveda donde el humo deja de subir y empieza a extenderse.
export(float) var smoke_ceiling_height := 27.5
# Solo humo: velocidad lateral inicial (dispersión radial/tangencial, no solo vertical).
# Combinada con la viscosity alta del GasParticleManager de humo (fricción exponencial),
# esta velocidad decae con el tiempo: el humo sube, se abre en nube y se frena solo,
# leyendo como "se condensa arriba" en vez de escapar en línea recta.
export(float) var smoke_lateral_speed := 0.9

var _manager: GasParticleManager = null
var _ice_level: Node = null
var _target_height := 0.0
var _display_height := 0.0
var _height_initialized := false
var _spawn_accumulator := 0.0
var _emit_counter := 0
var _wave_time := 0.0
var _ice_light: OmniLight = null

func _ready() -> void:
	if Engine.editor_hint:
		return
	_manager = get_node_or_null("GasParticleManager")
	if _manager == null:
		push_warning("[IceVisualBand] falta el hijo GasParticleManager; sin visual de hielo.")
	elif is_smoke_crown:
		# La bóveda visual contiene el humo; no hacen falta raycasts contra el mundo.
		_manager.collide_with_world = false
		_manager.vertical_ceiling_y = _manager.to_local(Vector3(0.0, smoke_ceiling_height, 0.0)).y
	else:
		_manager.anim_speed_base = frost_animation_speed
		_manager.anim_speed_velocity_factor = 0.04
		_ensure_ice_light()
	call_deferred("_connect_ice_level")

func _ensure_ice_light() -> void:
	_ice_light = get_node_or_null("IceLight")
	if _ice_light == null:
		_ice_light = OmniLight.new()
		_ice_light.name = "IceLight"
		add_child(_ice_light)
	_ice_light.light_color = Color(0.2, 0.62, 1.0)
	_ice_light.omni_range = ice_light_range
	_ice_light.shadow_enabled = false

func _connect_ice_level() -> void:
	if not get_tree():
		return
	var systems: Array = get_tree().get_nodes_in_group("ice_level")
	if systems.empty():
		return
	_ice_level = systems[0]
	if not is_instance_valid(_ice_level):
		return
	if not _ice_level.is_connected("ice_height_changed", self, "_on_ice_height_changed"):
		var _err = _ice_level.connect("ice_height_changed", self, "_on_ice_height_changed")
	_target_height = float(_ice_level.ice_height)
	if not _height_initialized:
		_display_height = _target_height
		_height_initialized = true

func _on_ice_height_changed(height: float) -> void:
	_target_height = height
	if not _height_initialized:
		_display_height = height
		_height_initialized = true

# Visual puro: va en _process, nunca en _physics_process (§5.3 es para lógica).
func _process(delta: float) -> void:
	if Engine.editor_hint or _manager == null:
		return
	if not is_instance_valid(_ice_level):
		_connect_ice_level()
		return

	_display_height = lerp(_display_height, _target_height, clamp(delta * follow_lerp, 0.0, 1.0))
	_wave_time += delta * wave_speed

	_spawn_accumulator += delta * max(particles_per_second, 0.0)
	var to_spawn := int(_spawn_accumulator)
	if to_spawn <= 0:
		return
	_spawn_accumulator -= float(to_spawn)
	# Nunca más de un pool completo por frame.
	to_spawn = int(min(to_spawn, _manager.pool_size))

	var center_angle := _get_camera_arc_center()
	var half_arc := deg2rad(clamp(visible_arc_deg, 1.0, 360.0)) * 0.5
	_update_ice_light(center_angle)

	for _i in range(to_spawn):
		_emit_frost(center_angle, half_arc)

func _update_ice_light(center_angle: float) -> void:
	if not is_instance_valid(_ice_light):
		return
	var radius := min(ring_radius * 0.42, 11.0)
	var base_y := to_local(Vector3(0.0, _display_height, 0.0)).y
	_ice_light.translation = Vector3(cos(center_angle) * radius, base_y + 1.2, sin(center_angle) * radius)
	# El hielo emite una luz estable; no debe comportarse como una llama.
	_ice_light.light_energy = ice_light_energy

# Ángulo (alrededor de +Y, local a este nodo) del sector del anillo que mira la cámara.
func _get_camera_arc_center() -> float:
	var viewport := get_viewport()
	if viewport == null:
		return 0.0
	var camera := viewport.get_camera()
	if not is_instance_valid(camera):
		return 0.0
	var local_cam: Vector3 = to_local(camera.global_transform.origin)
	if abs(local_cam.x) < 0.0001 and abs(local_cam.z) < 0.0001:
		return 0.0
	return atan2(local_cam.z, local_cam.x)

func _emit_frost(center_angle: float, half_arc: float) -> void:
	_emit_counter += 1
	var r1 := _hashed_unit(_emit_counter)
	var r2 := _hashed_unit(_emit_counter + 4127)
	var r3 := _hashed_unit(_emit_counter + 9311)

	var position: Vector3
	var angle: float
	if emit_center_column and (_emit_counter % 5) == 0:
		angle = r1 * TAU
		var center_r := center_column_radius * sqrt(r2)
		position = Vector3(cos(angle) * center_r, 0.0, sin(angle) * center_r)
	elif ring_only:
		angle = center_angle + (r1 * 2.0 - 1.0) * half_arc
		var radius := ring_radius - r2 * max(ring_thickness, 0.0)
		position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	else:
		# Disco completo, no solo el borde: toda la superficie del piso bajo ice_height
		# arde, no únicamente la pared. sqrt(r2) da densidad de área uniforme (si no, el
		# muestreo lineal de radio amontona partículas cerca del centro).
		angle = center_angle + (r1 * 2.0 - 1.0) * half_arc
		var radius := ring_radius * sqrt(r2)
		position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

	var base_y := to_local(Vector3(0.0, _display_height, 0.0)).y
	if is_smoke_crown:
		base_y += smoke_height_offset

	if is_smoke_crown:
		position.y = base_y + (r3 * 2.0 - 1.0) * line_noise
	else:
		# Oleaje coherente en el ángulo real (no ruido puro por índice): la superficie de
		# hielo sube y baja en ondas continuas que se desplazan con el tiempo, más un
		# jitter chico por partícula para que no se vea geométricamente perfecta.
		var wave := sin(angle * wave_frequency + _wave_time) * wave_amplitude
		wave += sin(angle * wave_frequency * 2.3 - _wave_time * 1.7) * wave_amplitude * 0.4
		position.y = base_y + wave + (r3 * 2.0 - 1.0) * line_noise * 0.3

	var velocity := Vector3(0.0, frost_rise_speed * (0.6 + r3 * 0.8), 0.0)
	var scale := frost_scale
	if is_smoke_crown:
		# Dispersión lateral: el humo no sube en línea recta, se abre en nube. La viscosity
		# alta del manager (fricción exponencial) hace que esta velocidad decaiga sola con
		# el tiempo — junto al buoyancy suave, el humo frena su ascenso y "se estanca"
		# dispersándose en vez de seguir subiendo indefinidamente.
		var r4 := _hashed_unit(_emit_counter + 2731)
		var lateral_angle := r4 * TAU
		var lateral_speed := smoke_lateral_speed * (0.3 + r1 * 0.9)
		velocity.x = cos(lateral_angle) * lateral_speed
		velocity.z = sin(lateral_angle) * lateral_speed
	else:
		# Burbujas de tamaño desparejo, muy solapadas: eso es lo que lee como masa fluida
		# continua (hielo) en vez de lenguas individuales separadas.
		scale = frost_scale * (1.0 - frost_scale_variance * 0.5 + r2 * frost_scale_variance)

	var lifetime := frost_lifetime * (0.7 + r2 * 0.6)
	var index: int = _manager.emit_particle(position, velocity, lifetime, scale)
	if not is_smoke_crown:
		var emitted: Dictionary = _manager.particles[index]
		emitted["anim_speed_mod"] = 0.85 + r3 * 0.3
		_manager.particles[index] = emitted
		# Temperatura aproximada por partícula: mezcla un hash independiente con el tamaño
		# (r2) para que las burbujas grandes/lentas tiendan más a fría (costra) y las
		# chicas/rápidas a caliente (grieta viva) — correlación física simple, no random
		# puro desconectado del resto de la partícula.
		var r_temp := _hashed_unit(_emit_counter + 6451)
		var temperature := clamp(r_temp * 0.7 + (1.0 - r2) * 0.3, 0.0, 1.0)
		var particle_color: Color = cool_color.linear_interpolate(hot_color, temperature)
		particle_color = _manager.ignition_color.linear_interpolate(particle_color, temperature_variance)
		# El shader usa la vía de combustión siempre: esto es hielo, no gas/humo.
		_manager.set_particle_combustion(index, true, particle_color)

# Determinista, nada de randf() (§1.2). A diferencia del LCG simple de GasParticleManager
# (que sobre índices consecutivos con offsets fijos puede dejar ver espirales/bandas ahora
# que el disco completo está cubierto), esto mezcla bits estilo "wang hash": decorrelaciona
# mucho mejor salidas consecutivas, así que la distribución en el disco se ve pareja.
func _hashed_unit(index: int) -> float:
	var h := int(index) & 0x7fffffff
	h = ((h >> 15) ^ h) * 0x2c1b3c6d
	h = h & 0x7fffffff
	h = ((h >> 12) ^ h) * 0x297a2d39
	h = h & 0x7fffffff
	h = (h >> 15) ^ h
	h = h & 0x7fffffff
	return float(h % 100000) / 100000.0
