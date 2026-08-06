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
# Altura visual que la escarcha adelanta sobre la pared respecto de la línea del hielo.
export(float) var wall_climb_height := 3.2
# Fracción de partículas de hielo reservada a lenguas sobre el perímetro del domo.
export(float, 0.0, 1.0) var wall_emission_ratio := 0.32
# Deriva lateral de la escarcha; combina dos ondas para evitar un movimiento mecánico.
export(float) var organic_drift_strength := 0.28
# Parches proyectados que dejan acumulación visible sobre paredes y objetos.
export(bool) var surface_frost_enabled := true
export(int, 8, 256) var surface_frost_pool_size := 192
export(float) var surface_frost_per_second := 34.0
export(float) var surface_frost_lifetime := 14.0
export(float) var surface_frost_size := 0.32
# Franja vertical sobre ice_height donde nacen los parches adheridos.
export(float) var surface_frost_edge_band_height := 1.95
# Radio interior real de la pared; es mayor que el radio visual de partículas del domo.
export(float) var surface_frost_wall_radius := 31.0
export(int, 6, 20) var surface_frost_branch_steps := 12
export(float) var surface_frost_branch_spread := 0.018
export(float) var surface_frost_wall_size_multiplier := 3.2
export(float) var surface_frost_object_size_multiplier := 1.45
# Microcristales emitidos sobre impactos para integrar los parches con la banda móvil.
export(float, 0.0, 1.0) var surface_frost_particle_ratio := 0.55
export(int, LAYERS_3D_PHYSICS) var surface_frost_collision_mask := 65
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
var _surface_patches: Array = []
var _surface_patch_ages: Array = []
var _surface_patch_cursor := 0
var _surface_patch_counter := 0
var _surface_patch_accumulator := 0.0

const FROST_DECAL_SHADER := preload("res://core_v2/systems/ice/shaders/frost_decal.shader")

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
		_ensure_surface_frost_pool()
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
	if _ice_level.has_signal("ice_visuals_reset") and not _ice_level.is_connected("ice_visuals_reset", self, "reset_visuals"):
		var _err_reset = _ice_level.connect("ice_visuals_reset", self, "reset_visuals")
	_target_height = float(_ice_level.ice_height)
	if not _height_initialized:
		_display_height = _target_height
		_height_initialized = true

func _on_ice_height_changed(height: float) -> void:
	_target_height = height
	if not _height_initialized:
		_display_height = height
		_height_initialized = true

# Al morir, `ice_height` puede caer varios metros de golpe (ensure_safe_for_respawn). Lo
# visual no debe arrastrar el intento anterior: parches de escarcha pegados donde ya no hay
# hielo, partículas en vuelo, y un _display_height que tardaría segundos en bajar por lerp.
func reset_visuals() -> void:
	if is_instance_valid(_manager) and _manager.has_method("clear_all"):
		_manager.clear_all()
	for i in range(_surface_patches.size()):
		var patch: MeshInstance = _surface_patches[i]
		if is_instance_valid(patch):
			patch.visible = false
		_surface_patch_ages[i] = surface_frost_lifetime
	_surface_patch_accumulator = 0.0
	_spawn_accumulator = 0.0
	if is_instance_valid(_ice_level):
		_target_height = float(_ice_level.ice_height)
	_display_height = _target_height
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
	_update_surface_frost(delta)

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

func _ensure_surface_frost_pool() -> void:
	if not surface_frost_enabled or not _surface_patches.empty():
		return
	var shared_quad := QuadMesh.new()
	shared_quad.size = Vector2.ONE
	for i in range(max(surface_frost_pool_size, 8)):
		var patch := MeshInstance.new()
		patch.name = "SurfaceFrost_%02d" % i
		patch.mesh = shared_quad
		patch.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = FROST_DECAL_SHADER
		material.set_shader_param("pattern_seed", float(i) * 0.731)
		patch.material_override = material
		patch.visible = false
		add_child(patch)
		_surface_patches.append(patch)
		_surface_patch_ages.append(surface_frost_lifetime)

func _update_surface_frost(delta: float) -> void:
	for i in range(_surface_patches.size()):
		var patch: MeshInstance = _surface_patches[i]
		if not patch.visible:
			continue
		_surface_patch_ages[i] = float(_surface_patch_ages[i]) + delta
		var age_ratio: float = float(_surface_patch_ages[i]) / max(surface_frost_lifetime, 0.001)
		var material := patch.material_override as ShaderMaterial
		if material:
			material.set_shader_param("ice_height_world", _display_height)
			material.set_shader_param("opacity", 1.0 - smoothstep(0.82, 1.0, age_ratio))
		if patch.global_transform.origin.y <= _display_height + 0.03 or age_ratio >= 1.0:
			patch.visible = false
	_surface_patch_accumulator += delta * max(surface_frost_per_second, 0.0)
	while _surface_patch_accumulator >= 1.0:
		_surface_patch_accumulator -= 1.0
		_emit_surface_frost_patch()

func _emit_surface_frost_patch() -> void:
	if _surface_patches.empty() or get_world() == null:
		return
	_surface_patch_counter += 1
	var r2 := _hashed_unit(_surface_patch_counter + 3253)
	var r3 := _hashed_unit(_surface_patch_counter + 7919)
	var r4 := _hashed_unit(_surface_patch_counter + 10427)
	var wall_sample := (_surface_patch_counter % 5) < 3
	var angle: float
	var sample_y: float
	if wall_sample:
		# Una raíz conserva su ángulo durante varios pasos y serpentea al crecer. Las
		# desviaciones alternas forman bifurcaciones similares a capilares congelados.
		var steps: int = int(max(surface_frost_branch_steps, 2))
		var tendril_id := int(_surface_patch_counter / steps)
		var tendril_step := _surface_patch_counter % steps
		var growth := float(tendril_step) / float(steps - 1)
		var root_angle := fmod(float(tendril_id) * 2.39996323, TAU)
		var curvature := (_hashed_unit(tendril_id + 2381) * 2.0 - 1.0) * surface_frost_branch_spread
		var segment_noise := _hashed_unit(_surface_patch_counter + tendril_id * 31)
		var branch_side := -1.0 if segment_noise < 0.5 else 1.0
		var branch := branch_side * surface_frost_branch_spread * growth * (0.2 + r3 * 0.8)
		var phase := _hashed_unit(tendril_id + 5521) * TAU
		angle = root_angle + sin(growth * TAU + phase) * curvature + branch
		var step_height := max(surface_frost_edge_band_height, 0.1) / float(steps - 1)
		var height_jitter := (segment_noise - 0.5) * step_height * 0.7
		sample_y = _display_height + 0.04 + growth * max(surface_frost_edge_band_height, 0.1) + height_jitter
	else:
		# Los objetos interiores conservan una distribución uniforme desde el perímetro.
		angle = fmod(float(_surface_patch_counter) * 2.39996323, TAU)
		sample_y = _display_height + (0.04 + r2 * 0.96) * max(surface_frost_edge_band_height, 0.1)
	var radial := Vector3(cos(angle), 0.0, sin(angle))
	var from: Vector3
	var to: Vector3
	if not wall_sample:
		# Avanza desde afuera hacia dentro: encuentra primero los objetos más cercanos a
		# la pared, de modo que la congelación invada el domo desde el perímetro.
		from = radial * max(surface_frost_wall_radius - 0.8, 0.0) + Vector3.UP * sample_y
		to = radial * 0.5 + Vector3.UP * sample_y
	else:
		# La mayor parte de los parches nace directamente sobre la pared del domo.
		from = radial * max(surface_frost_wall_radius - 6.0, 0.0) + Vector3.UP * sample_y
		to = radial * (surface_frost_wall_radius + 2.0) + Vector3.UP * sample_y
	var hit: Dictionary = get_world().direct_space_state.intersect_ray(from, to, [], surface_frost_collision_mask, true, false)
	# La cúpula visual no tiene colisión continua en esclusas y segmentos decorativos.
	# Completar esos huecos sobre el cilindro interior mantiene la cobertura pareja.
	if hit.empty() and wall_sample:
		hit = {
			"position": radial * surface_frost_wall_radius + Vector3.UP * sample_y,
			"normal": -radial
		}
	if hit.empty():
		return
	var normal: Vector3 = Vector3(hit.get("normal", -radial)).normalized()
	var tangent := Vector3.UP.cross(normal)
	if tangent.length_squared() < 0.001:
		tangent = Vector3.RIGHT
	tangent = tangent.normalized()
	var local_up := normal.cross(tangent).normalized()
	var patch: MeshInstance = _surface_patches[_surface_patch_cursor]
	_surface_patch_ages[_surface_patch_cursor] = 0.0
	_surface_patch_cursor = (_surface_patch_cursor + 1) % _surface_patches.size()
	var size_variation := surface_frost_size * (0.42 + r3 * 1.05)
	if wall_sample:
		size_variation *= surface_frost_wall_size_multiplier
	else:
		size_variation *= surface_frost_object_size_multiplier
	var world_basis: Basis
	if wall_sample:
		# El shader dibuja el capilar dentro de una superficie amplia; pequeñas diferencias
		# de escala e inclinación evitan la repetición visible entre segmentos.
		var wall_tilt := (r4 * 2.0 - 1.0) * 0.16
		var wall_x := (tangent * cos(wall_tilt) + local_up * sin(wall_tilt)).normalized()
		var wall_y := normal.cross(wall_x).normalized()
		world_basis = Basis(wall_x * size_variation * (0.78 + r2 * 0.38), wall_y * size_variation * (1.9 + r3 * 0.8), normal)
	else:
		var patch_angle := r4 * TAU
		var patch_x := tangent * cos(patch_angle) + local_up * sin(patch_angle)
		var patch_y := normal.cross(patch_x).normalized()
		var aspect := 0.62 + r2 * 0.76
		world_basis = Basis(patch_x * size_variation * aspect, patch_y * size_variation / aspect, normal)
	patch.global_transform = Transform(world_basis, Vector3(hit["position"]) + normal * 0.025)
	var material := patch.material_override as ShaderMaterial
	if material:
		material.set_shader_param("opacity", 1.0)
		material.set_shader_param("ice_height_world", _display_height)
		material.set_shader_param("tendril_mode", 1.0 if wall_sample else 0.0)
	patch.visible = true
	if r4 <= surface_frost_particle_ratio:
		_emit_surface_crystal(Vector3(hit["position"]), normal, r2, r3)

func _emit_surface_crystal(world_position: Vector3, normal: Vector3, size_seed: float, speed_seed: float) -> void:
	if not is_instance_valid(_manager):
		return
	var local_position := _manager.to_local(world_position + normal * 0.06)
	var local_normal := _manager.global_transform.basis.xform_inv(normal).normalized()
	var velocity := local_normal * (0.025 + speed_seed * 0.055) + Vector3.UP * frost_rise_speed * 0.28
	var lifetime := frost_lifetime * (1.15 + size_seed * 0.9)
	var crystal_scale := frost_scale * (0.16 + size_seed * 0.13)
	var index: int = _manager.emit_particle(local_position, velocity, lifetime, crystal_scale)
	var crystal_color := cool_color.linear_interpolate(hot_color, 0.35 + speed_seed * 0.45)
	_manager.set_particle_combustion(index, true, crystal_color)

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
	var wall_frost: bool = not is_smoke_crown and r3 < clamp(wall_emission_ratio, 0.0, 1.0)

	var position: Vector3
	var angle: float
	if wall_frost:
		angle = center_angle + (r1 * 2.0 - 1.0) * half_arc
		var wall_pulse := sin(angle * wave_frequency * 0.63 - _wave_time * 1.35)
		var wall_radius := ring_radius - 0.12 - wall_pulse * 0.08
		position = Vector3(cos(angle) * wall_radius, 0.0, sin(angle) * wall_radius)
	elif emit_center_column and (_emit_counter % 5) == 0:
		angle = r1 * TAU
		var center_r := center_column_radius * sqrt(r2)
		position = Vector3(cos(angle) * center_r, 0.0, sin(angle) * center_r)
	elif ring_only:
		angle = center_angle + (r1 * 2.0 - 1.0) * half_arc
		var radius := ring_radius - r2 * max(ring_thickness, 0.0)
		position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	else:
		# El congelamiento entra desde la pared. La potencia baja concentra el nacimiento
		# cerca del perímetro y deja algunas lenguas avanzar hacia el interior.
		angle = center_angle + (r1 * 2.0 - 1.0) * half_arc
		var radius := ring_radius * pow(r2, 0.22)
		position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

	var base_y := to_local(Vector3(0.0, _display_height, 0.0)).y
	if is_smoke_crown:
		base_y += smoke_height_offset

	if is_smoke_crown:
		position.y = base_y + (r3 * 2.0 - 1.0) * line_noise
	elif wall_frost:
		# Más densidad junto a la línea y lenguas aisladas que se adelantan por la pared.
		var climb := pow(r2, 1.65) * max(wall_climb_height, 0.0)
		var wall_wave := sin(angle * wave_frequency - _wave_time * 1.4) * wave_amplitude * 0.45
		wall_wave += sin(angle * 2.7 + _wave_time * 0.8) * organic_drift_strength
		position.y = base_y + climb + wall_wave
	else:
		# Oleaje coherente en el ángulo real (no ruido puro por índice): la superficie de
		# hielo sube y baja en ondas continuas que se desplazan con el tiempo, más un
		# jitter chico por partícula para que no se vea geométricamente perfecta.
		var wave := sin(angle * wave_frequency + _wave_time) * wave_amplitude
		wave += sin(angle * wave_frequency * 2.3 - _wave_time * 1.7) * wave_amplitude * 0.4
		position.y = base_y + wave + (r3 * 2.0 - 1.0) * line_noise * 0.3

	var velocity := Vector3(0.0, frost_rise_speed * (0.6 + r3 * 0.8), 0.0)
	if wall_frost:
		var tangent := Vector3(-sin(angle), 0.0, cos(angle))
		var drift_wave := sin(angle * 3.1 + _wave_time * 1.7)
		velocity += tangent * drift_wave * organic_drift_strength
		velocity.y *= 1.35
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
