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

export(bool) var start_lit := false

export(NodePath) var dark_lighting_path := NodePath("../DarkLevelLighting")
export(NodePath) var wall_lights_path := NodePath("../Hub/WallLights")
export(NodePath) var fixture_batch_path := NodePath("../Hub/WallLights/FixtureBatch_00")
export(NodePath) var button_path := NodePath("../Hub/PedestalLight")

# --- Ambiente de escritorio (Environment duplicado por DarkLevelLighting) ---
export(float, 0.0, 4.0, 0.01) var dark_ambient_energy := 0.02
export(float, 0.0, 4.0, 0.01) var lit_ambient_energy := 1.2
export(Color) var dark_background := Color(0.010, 0.014, 0.020)
export(Color) var lit_background := Color(0.030, 0.040, 0.060)
export(float, 0.0, 8.0, 0.05) var dark_sun_energy := 0.0
export(float, 0.0, 8.0, 0.05) var lit_sun_energy := 1.5

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
var _pool_base_energy := 0.8
var _sound_player: AudioStreamPlayer = null

func _ready() -> void:
	add_to_group("replay_sync")
	_resolve_nodes()
	_build_sound_player()
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
	if value == lit and not _flicker_active:
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
	_apply_pool(_level)

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

func _apply_pool(level: float) -> void:
	_collect_pool_lights()
	var energy: float = _pool_base_energy * level
	# LightPathV2 crea sus 2 OmniLight de forma perezosa (~0.25 s) leyendo este
	# export, asi que hay que moverlo tambien: si no, un DARK inicial dejaria las
	# luces naciendo encendidas y no habria ningun tick posterior que las apague.
	if _wall_lights != null and "light_energy" in _wall_lights:
		_wall_lights.set("light_energy", energy)
	for light in _pool_lights:
		if is_instance_valid(light):
			light.light_energy = energy

# --- Resolucion de nodos / materiales --------------------------------------

func _resolve_nodes() -> void:
	_dark_lighting = get_node_or_null(dark_lighting_path)
	_wall_lights = get_node_or_null(wall_lights_path)
	if _wall_lights != null and "light_energy" in _wall_lights:
		var base = _wall_lights.get("light_energy")
		if base != null and (typeof(base) == TYPE_REAL or typeof(base) == TYPE_INT):
			_pool_base_energy = float(base)

func _collect_pool_lights() -> void:
	_pool_lights = []
	if _wall_lights == null:
		return
	for child in _wall_lights.get_children():
		if child is OmniLight:
			_pool_lights.append(child as OmniLight)

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
	_sound_player.stream = switch_sound
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
