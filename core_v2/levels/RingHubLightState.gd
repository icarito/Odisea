extends Node
class_name RingHubLightState

# O20 — Estados de iluminacion del domo de RingHub.
#
# El level tiene DOS estados: DARK (lamparas apagadas, pool de LightPathV2 sin
# energia, ambiente casi nulo) y LIT (ambiente del Environment a su valor base,
# pool encendido y la emision de las 16 lamparas de pared en ON). La transicion
# es un FLICKER industrial, no un fade: una tabla fija de niveles que se recorre
# a pasos, siempre el mismo patron, asi que es deterministica y sobrevive un
# replay (grupo replay_sync + get_snapshot/restore_snapshot).
#
# Este nodo es el unico dueno del ambiente despues del arranque:
#   escritorio / PBR : mueve ambient/background/Sun del Environment que
#                      DarkLevelLighting ya duplico y oscurecio una sola vez
#                      (asi no se duplica el Environment ni se pelea con su
#                      _ready; sus setters guardan el valor pendiente si el
#                      Environment todavia no se aplico).
#   tier bajo / plano: el Environment no pinta nada porque los materiales son
#                      unshaded (FlatFake), asi que baja la palanca del shader
#                      expuesta por GLES3VendorGate (ambient/exposure y
#                      world_light/glow_floor).
#
# La emision de las lamparas vive en el material de la superficie de vidrio del
# MultiMesh horneado. Se duplica mesh + multimesh para no mutar el recurso
# compartido (IndustrialWallLampLOD.mesh lo usan tambien otros domos).
#
# O28: ademas mueve la ENERGIA del BakedLightmap (LIT=1, DARK=0) para que el look
# horneado, estilo Dome_Intro, siga los dos estados con un solo bake. Ver los
# exports de "Lightmap horneado" y _apply_lightmap().

export(bool) var start_lit := false

export(NodePath) var dark_lighting_path := NodePath("../DarkLevelLighting")
export(NodePath) var wall_lights_path := NodePath("../Hub/WallLights")
export(NodePath) var fixture_batch_path := NodePath("../Hub/WallLights/FixtureBatch_00")
export(NodePath) var button_path := NodePath("../Hub/PedestalLight")

# --- Ambiente de escritorio (Environment duplicado por DarkLevelLighting) ---
export(float, 0.0, 4.0, 0.01) var dark_ambient_energy := 0.02
export(float, 0.0, 4.0, 0.01) var lit_ambient_energy := 1.5
export(Color) var dark_background := Color(0.010, 0.014, 0.020)
export(Color) var lit_background := Color(0.040, 0.055, 0.080)
export(float, 0.0, 8.0, 0.05) var dark_sun_energy := 0.0
export(float, 0.0, 8.0, 0.05) var lit_sun_energy := 1.5

# Escala del pool de LightPathV2 (las 2 OmniLight que persiguen al jugador). Con el
# bake iluminando el nivel, el pool solo agrega un "omnilight sobre Elias" que
# aplana el domo; 0 = sin pool (el bake se encarga). Default 1 = comportamiento viejo.
export(float, 0.0, 4.0, 0.01) var pool_energy_scale := 1.0

# --- Ambiente de tier bajo / plano (uniformes del FlatFake) ---
export(float, 0.0, 2.0, 0.01) var dark_flat_ambient := 0.05
export(float, 0.0, 2.0, 0.01) var lit_flat_ambient := 0.5
export(float, 0.0, 2.0, 0.01) var dark_flat_world_light := 0.02
export(float, 0.0, 2.0, 0.01) var lit_flat_world_light := 0.9
export(float, 0.0, 2.0, 0.01) var dark_flat_glow_floor := 0.05
export(float, 0.0, 2.0, 0.01) var lit_flat_glow_floor := 0.35

# --- Lamparas (vidrio del fixture MultiMesh) ---
export(float, 0.0, 8.0, 0.05) var lamp_off_emission := 0.0
export(float, 0.0, 8.0, 0.05) var lamp_on_emission := 0.9
export(Color) var lamp_off_albedo := Color(0.08, 0.10, 0.13)
export(Color) var lamp_on_albedo := Color(0.72, 0.84, 1.0)

# --- Lightmap horneado (O28) ---
# RingHub tiene UN solo bake: los dos estados se logran moviendo la ENERGIA del
# BakedLightmapData (LIT=1, DARK=0) en vez de intercambiar recursos .lmbake. El
# recurso se duplica en _resolve_nodes para no mutar un light_data compartido
# (asi el .lmbake de Dome_Intro nunca se toca, aunque hoy RingHub tenga el suyo).
export(NodePath) var lightmap_path := NodePath("../BakedLightmap")
export(float, 0.0, 16.0, 0.01) var lightmap_energy_dark := 0.0
export(float, 0.0, 16.0, 0.01) var lightmap_energy_lit := 1.0

# --- Luminarias simplificadas (una OmniLight por lampara de pared) ---
# El pool de LightPathV2 persigue al jugador, asi que en LIT solo se ve el tramo
# cercano. Estas 16 luces se crean por codigo en las posiciones horneadas de
# "Markers" (una por lampara, sin geometria ni sombras) y le dan al domo una
# iluminacion repartida: en LIT todo el anillo lee iluminado, no solo el pool.
# Son parte del estado: _apply_level les mueve la energia igual que al resto.
# En tier bajo/plano no se crean (los materiales unshaded no reciben luz real y
# el MobileLightBudget apretaria su alcance): ahi ilumina el pool y _apply_flat.
#
# O28: cuando el domo tiene un BakedLightmap horneado, las 16 luminarias son
# REDUNDANTES — el bake ya reparte la luz de las lamparas y sumar las runtime
# duplica el brillo. `lamp_lights_enabled=false` en RingHub_Level.tscn las
# desactiva; el lever queda por si hay que comparar A/B o volver atras.
export(NodePath) var lamp_markers_path := NodePath("../Hub/WallLights/Markers")
export(bool) var lamp_lights_enabled := true
export(float, 0.0, 8.0, 0.05) var lamp_light_energy := 1.4
export(float, 0.5, 60.0, 0.5) var lamp_light_range := 20.0
export(Color) var lamp_light_color := Color(0.72, 0.84, 1.0)
# La lampara esta montada contra la pared; correr la luz hacia el eje del domo
# evita que su volumen se coma la pared y manda el aporte hacia adentro.
export(float, -5.0, 5.0, 0.1) var lamp_inward_offset := 0.75
export(bool) var lamp_lights_cast_shadow := false

# --- Flicker ---
# Tabla fija (0 = DARK, 1 = LIT) muestreada cada flicker_step_time. El patron de
# encendido termina en 1; el de apagado en 0. Nada de randf ni de tiempo de
# frames: el mismo patron con los mismos deltas da el mismo resultado siempre.
export(Array, float) var flicker_on_pattern := [0.0, 1.0, 0.0, 0.0, 1.0, 0.2, 0.9, 0.0, 1.0, 1.0]
export(Array, float) var flicker_off_pattern := [1.0, 0.0, 1.0, 1.0, 0.0, 0.3, 0.0, 0.0]
export(float, 0.02, 0.5, 0.01) var flicker_step_time := 0.08

export(AudioStream) var switch_sound
export(float, -40.0, 24.0, 0.5) var switch_sound_db := 0.0

# --- Estado (snapshot para replay) ---
var lit := false
var _flicker_active := false
var _flicker_clock := 0.0
var _flicker_target := false
var _flicker_pattern := []
var _switch_sounds_played := 0
var _level := 0.0

var _dark_lighting: Node = null
var _wall_lights: Node = null
var _fixtures: MultiMeshInstance = null
var _fixture_materials := []
var _pool_lights := []
var _luminaries := []
var _lightmap: BakedLightmap = null
var _pool_base_energy := 0.8
var _sound_player: AudioStreamPlayer = null

func _ready() -> void:
	add_to_group("replay_sync")
	_resolve_nodes()
	_build_sound_player()
	_build_luminaries()
	_prepare_fixture_emission()
	_connect_button()
	set_process(false)
	# Deferred para correr despues del _apply() de DarkLevelLighting, pero sus
	# setters guardan pendiente igual, asi que el orden no es critico.
	call_deferred("_apply_initial")

func _apply_initial() -> void:
	lit = start_lit
	_flicker_target = lit
	_flicker_active = false
	_apply_level(1.0 if lit else 0.0)

# --- API publica ------------------------------------------------------------

func is_lit() -> bool:
	return lit

func is_flickering() -> bool:
	return _flicker_active

func toggle() -> void:
	set_lit(not lit)

func set_lit(value: bool) -> void:
	# Solo se reinicia si el target cambia. Hoy `lit` se fija al pedir el cambio,
	# asi que una re-entrada con el mismo valor (dos `activated` seguidos, un
	# restore, un consumidor que re-aplica el estado) no debe reiniciar el flicker
	# ni volver a sonar.
	if value == lit and (not _flicker_active or value == _flicker_target):
		return
	lit = value
	_start_flicker(value)

# --- Flicker determinista ---------------------------------------------------

func _start_flicker(value: bool) -> void:
	_flicker_target = value
	_flicker_pattern = flicker_on_pattern if value else flicker_off_pattern
	if _flicker_pattern.empty():
		_flicker_active = false
		_apply_level(1.0 if value else 0.0)
		set_physics_process(false)
		return
	_flicker_active = true
	_flicker_clock = 0.0
	if value:
		_play_switch_sound()
	_apply_level(_sample_level(0.0))
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if not _flicker_active:
		set_physics_process(false)
		return
	_flicker_clock += delta
	var total: float = float(_flicker_pattern.size()) * flicker_step_time
	if _flicker_clock >= total:
		_flicker_active = false
		_flicker_clock = total
		_apply_level(1.0 if _flicker_target else 0.0)
		set_physics_process(false)
		return
	_apply_level(_sample_level(_flicker_clock))

func _sample_level(t: float) -> float:
	if _flicker_pattern.empty():
		return 1.0 if _flicker_target else 0.0
	var step: int = int(floor(t / flicker_step_time))
	if step < 0:
		step = 0
	if step >= _flicker_pattern.size():
		step = _flicker_pattern.size() - 1
	return float(_flicker_pattern[step])

# --- Aplicacion -------------------------------------------------------------

func _apply_level(level: float) -> void:
	_level = clamp(level, 0.0, 1.0)
	_apply_environment(_level)
	_apply_flat(_level)
	_apply_lamps(_level)
	_apply_lightmap(_level)
	_apply_pool(_level)
	_apply_luminaries(_level)

func _apply_environment(level: float) -> void:
	if _dark_lighting == null:
		return
	if _dark_lighting.has_method("set_ambient_energy"):
		_dark_lighting.set_ambient_energy(lerp(dark_ambient_energy, lit_ambient_energy, level))
	if _dark_lighting.has_method("set_background_color"):
		_dark_lighting.set_background_color(dark_background.linear_interpolate(lit_background, level))
	if _dark_lighting.has_method("set_sun_energy"):
		_dark_lighting.set_sun_energy(lerp(dark_sun_energy, lit_sun_energy, level))

func _apply_flat(level: float) -> void:
	var gate = get_node_or_null("/root/GLES3VendorGate")
	if gate == null or not gate.has_method("is_flat_mode") or not bool(gate.is_flat_mode()):
		return
	if gate.has_method("set_flat_ambient"):
		gate.set_flat_ambient(lerp(dark_flat_ambient, lit_flat_ambient, level))
	if gate.has_method("set_flat_world_light"):
		gate.set_flat_world_light(lerp(dark_flat_world_light, lit_flat_world_light, level))
	if gate.has_method("set_flat_glow_floor"):
		gate.set_flat_glow_floor(lerp(dark_flat_glow_floor, lit_flat_glow_floor, level))

func _apply_lamps(level: float) -> void:
	if _fixture_materials.empty():
		return
	var energy: float = lerp(lamp_off_emission, lamp_on_emission, level)
	var albedo: Color = lamp_off_albedo.linear_interpolate(lamp_on_albedo, level)
	for mat in _fixture_materials:
		if not is_instance_valid(mat):
			continue
		var glass := mat as SpatialMaterial
		glass.albedo_color = Color(albedo.r, albedo.g, albedo.b, glass.albedo_color.a)
		glass.emission_enabled = true
		glass.emission = albedo
		glass.emission_energy = energy

# Mueve la energia del bake horneado junto con el resto del estado. Un solo bake
# cubre DARK y LIT: no hay swap de recursos ni segunda pasada de horneado. Si la
# escena no tiene light_data (todavia sin hornear) es un no-op y el resto de los
# levers siguen funcionando.
func _apply_lightmap(level: float) -> void:
	if _lightmap == null or _lightmap.light_data == null:
		return
	var data := _lightmap.light_data as BakedLightmapData
	if data == null:
		return
	data.energy = lerp(lightmap_energy_dark, lightmap_energy_lit, level)

func _apply_pool(level: float) -> void:
	_collect_pool_lights()
	# En handheld (low/flat) el pool es la unica luz que sigue al jugador: ahi el
	# scale no aplica (las luminarias no se crean en ese tier). Solo en desktop el
	# bake + luminarias reemplazan al pool.
	var scale: float = pool_energy_scale
	var gate = get_node_or_null("/root/GLES3VendorGate")
	if gate != null:
		var flat: bool = gate.has_method("is_flat_mode") and bool(gate.is_flat_mode())
		var low: bool = gate.has_method("is_low_tier") and bool(gate.is_low_tier())
		if flat or low:
			scale = 1.0
	var energy: float = _pool_base_energy * level * scale
	# LightPathV2 crea sus 2 OmniLight de forma perezosa (~0.25 s) leyendo este
	# export, asi que hay que moverlo tambien: si no, un DARK inicial dejaria las
	# luces naciendo encendidas y no habria ningun tick posterior que las apague.
	if _wall_lights != null and "light_energy" in _wall_lights:
		_wall_lights.set("light_energy", energy)
	for light in _pool_lights:
		if is_instance_valid(light):
			light.light_energy = energy

func _apply_luminaries(level: float) -> void:
	if _luminaries.empty():
		return
	var energy: float = lamp_light_energy * level
	# Apagadas del todo en reposo (0): una luz con energia 0 igual cuesta fillrate,
	# asi que se ocultan. Durante el flicker el nivel intermedio solo baja energia,
	# sin cambiar la cantidad de luces encendidas (eso evita recompilar variantes
	# de shader a cada paso del patron).
	var on: bool = energy > 0.01
	for light in _luminaries:
		if not is_instance_valid(light):
			continue
		light.light_energy = energy
		light.visible = on

# --- Resolucion de nodos / materiales --------------------------------------

func _resolve_nodes() -> void:
	_dark_lighting = get_node_or_null(dark_lighting_path)
	_wall_lights = get_node_or_null(wall_lights_path)
	if _wall_lights != null and "light_energy" in _wall_lights:
		var base = _wall_lights.get("light_energy")
		if base != null and (typeof(base) == TYPE_REAL or typeof(base) == TYPE_INT):
			_pool_base_energy = float(base)
	_lightmap = get_node_or_null(lightmap_path) as BakedLightmap
	if _lightmap != null and _lightmap.light_data != null:
		# Copia local: el .lmbake es un recurso compartido en disco y el estado le
		# mueve la energia a cada tick del flicker. Nunca mutar el recurso de la
		# escena (ni, menos, el de Dome_Intro).
		var copy := _lightmap.light_data.duplicate() as BakedLightmapData
		if copy != null:
			_lightmap.light_data = copy

func _collect_pool_lights() -> void:
	_pool_lights = []
	if _wall_lights == null:
		return
	for child in _wall_lights.get_children():
		if child is OmniLight:
			_pool_lights.append(child as OmniLight)

# Crea una OmniLight por cada una de las 16 lamparas de pared, en las posiciones
# horneadas de "Markers" (el mismo MultiMesh que usa el pool para colocarse). No
# toca la escena: el nodo contenedor es runtime-only. Ver los exports arriba para
# el porque de no crearlas en tier bajo/plano.
func _build_luminaries() -> void:
	_luminaries = []
	# O28: con lightmap horneado, las luminarias runtime son brillo doble. La
	# escena apaga el lever; el chequeo de tier de abajo queda solo para el A/B.
	if not lamp_lights_enabled:
		return
	var gate = get_node_or_null("/root/GLES3VendorGate")
	if gate != null:
		if gate.has_method("is_flat_mode") and bool(gate.is_flat_mode()):
			return
		if gate.has_method("is_low_tier") and bool(gate.is_low_tier()):
			return
	# Movil: 16 luces reales son fillrate puro y el MobileLightBudget igual les
	# recortaria el alcance, dejando un efecto debil. Se deja solo el pool (+ el
	# ambiente). ODISEA_FORCE_MOBILE_PROFILE=1 reproduce esta ruta desde desktop.
	var mobile_env := OS.get_environment("ODISEA_FORCE_MOBILE_PROFILE")
	if OS.get_name() in ["Android", "iOS"] or mobile_env in ["1", "true", "yes", "on"]:
		return
	var markers := get_node_or_null(lamp_markers_path) as MultiMeshInstance
	if markers == null or markers.multimesh == null:
		return
	var holder := Spatial.new()
	holder.name = "Luminaries"
	add_child(holder)
	for index in range(markers.multimesh.instance_count):
		var local: Vector3 = markers.multimesh.get_instance_transform(index).origin
		var world: Vector3 = markers.global_transform.xform(local)
		var inward := Vector3(-world.x, 0.0, -world.z)
		if inward.length_squared() > 0.0001:
			world += inward.normalized() * lamp_inward_offset
		var light := OmniLight.new()
		light.name = "Luminary_%02d" % index
		light.light_color = lamp_light_color
		light.light_energy = 0.0
		light.omni_range = lamp_light_range
		light.shadow_enabled = lamp_lights_cast_shadow
		light.visible = false
		holder.add_child(light)
		light.global_transform = Transform(Basis(), world)
		_luminaries.append(light)

# Duplica mesh y multimesh del batch de fixtures y guarda el material de la
# superficie de vidrio para poder animar su emision/albedo. No muta el recurso
# compartido (el .mesh lo usan los domos de Dome_Intro/Prologue).
func _prepare_fixture_emission() -> void:
	_fixture_materials = []
	_fixtures = get_node_or_null(fixture_batch_path) as MultiMeshInstance
	if _fixtures == null or _fixtures.multimesh == null:
		return
	var mesh: Mesh = _fixtures.multimesh.mesh
	if mesh == null:
		return
	var dup: Mesh = mesh.duplicate()
	var materials := []
	for s in range(dup.get_surface_count()):
		var src = dup.surface_get_material(s)
		if not (src is SpatialMaterial):
			continue
		var sm := src as SpatialMaterial
		var name_hint := str(sm.resource_name).to_lower()
		var is_glass: bool = name_hint.find("glass") != -1 \
			or name_hint.find("vidrio") != -1 or name_hint.find("cristal") != -1
		var em: Color = sm.emission
		var is_emissive: bool = sm.emission_enabled and max(em.r, max(em.g, em.b)) > 0.01
		if not (is_glass or is_emissive):
			continue
		var mat := sm.duplicate() as SpatialMaterial
		mat.resource_local_to_scene = true
		dup.surface_set_material(s, mat)
		materials.append(mat)
	# En modo plano el gate ya aplano las superficies a ShaderMaterial: no hay
	# vidrio que animar (ahi la iluminancia la mueve _apply_flat).
	if materials.empty():
		return
	var mm: MultiMesh = _fixtures.multimesh.duplicate()
	mm.mesh = dup
	_fixtures.multimesh = mm
	_fixture_materials = materials

func _connect_button() -> void:
	var button := get_node_or_null(button_path)
	if button == null:
		return
	if button.has_signal("activated") and not button.is_connected("activated", self, "_on_button_activated"):
		button.connect("activated", self, "_on_button_activated")

func _on_button_activated() -> void:
	toggle()

func _build_sound_player() -> void:
	if switch_sound == null:
		return
	_sound_player = AudioStreamPlayer.new()
	_sound_player.name = "SwitchSound"
	# El .ogg esta importado con loop=true porque las wall lights de Dome_Intro lo
	# usan como zumbido continuo. Aca es un efecto one-shot: se duplica el recurso
	# (NO se muta el compartido) y se apaga el loop solo en la copia del player.
	var stream: AudioStream = switch_sound
	var copy: Resource = switch_sound.duplicate()
	if copy != null and "loop" in copy:
		copy.set("loop", false)
		stream = copy as AudioStream
	_sound_player.stream = stream
	_sound_player.volume_db = switch_sound_db
	add_child(_sound_player)

func _play_switch_sound() -> void:
	_switch_sounds_played += 1
	if _sound_player != null:
		_sound_player.play()

# --- Replay determinista ----------------------------------------------------

func get_snapshot() -> Dictionary:
	return {
		"lit": lit,
		"flicker_active": _flicker_active,
		"flicker_clock": _flicker_clock,
		"flicker_target": _flicker_target,
	}

func restore_snapshot(data: Dictionary) -> void:
	lit = bool(data.get("lit", lit))
	_flicker_target = bool(data.get("flicker_target", lit))
	_flicker_clock = float(data.get("flicker_clock", 0.0))
	_flicker_active = bool(data.get("flicker_active", false))
	if _flicker_active:
		_flicker_pattern = flicker_on_pattern if _flicker_target else flicker_off_pattern
		_apply_level(_sample_level(_flicker_clock))
		set_physics_process(true)
	else:
		_flicker_clock = 0.0
		set_physics_process(false)
		_apply_level(1.0 if lit else 0.0)
