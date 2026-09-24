extends Node
class_name DarkLevelLighting

# "Luces apagadas" del nivel, por perfil.
#
# El mismo diseño se resuelve distinto segun el hardware, porque en el tier bajo
# los materiales son unshaded (FlatFake) y NINGUNA luz real los toca:
#
#   escritorio / PBR : se oscurece el Environment (ambient + niebla) y la
#                      SpotLight del casco ilumina de verdad. El glow map
#                      ensucia el halo de las lamparas, tipo lens dirt.
#   tier bajo / plano: no se toca el Environment — no haria nada. La oscuridad y
#                      el cono viven dentro de FlatFakeFlashlight, que
#                      GLES3VendorGate ya activa junto con el modo plano.
#
# Por eso aca solo se aplica la rama de escritorio: la otra ya esta cubierta.

export(bool) var enabled := true
export(float, 0.0, 1.0, 0.01) var ambient_energy := 0.03
export(float, 0.0, 60.0, 0.5) var fog_begin := 3.0
export(float, 0.0, 120.0, 0.5) var fog_end := 26.0
export(Color) var fog_color := Color(0.02, 0.03, 0.05)
export(float, 0.0, 4.0, 0.05) var sun_energy := 0.02

# O20: este nodo prepara UNA vez el Environment apagado (duplicado, glow map,
# niebla) y queda como el dueno del recurso; RingHubLightState mueve el ambiente
# DARK/LIT a traves de estos setters sin duplicar nada. Si el Environment todavia
# no se aplico (su _apply es deferred), el valor queda pendiente y se aplica al
# final de _apply, asi el orden de _ready de los dos nodos no importa.
var _env: Environment = null
var _world: WorldEnvironment = null
var _pending_ambient := -1.0
var _pending_background := false
var _pending_background_color := Color()

func get_environment() -> Environment:
	return _env

func set_ambient_energy(value: float) -> void:
	_pending_ambient = value
	if _env != null:
		_env.ambient_light_energy = value

func set_background_color(value: Color) -> void:
	_pending_background = true
	_pending_background_color = value
	if _env != null:
		_env.background_color = value

func set_sun_energy(value: float) -> void:
	sun_energy = value
	_apply_sun(value)

func _apply_sun(value: float) -> void:
	if _world == null:
		return
	for child in _world.get_children():
		if child is DirectionalLight:
			(child as DirectionalLight).light_energy = value

# Lens dirt sobre el glow. Es una perilla MUY sensible: a 0.9 la textura deja de
# ensuciar el halo y empieza a inventar lamparas donde solo habia un reflejo.
# 0.25 ensucia sin mentir, que es el efecto que se busca.
export(Texture) var glow_map
export(float, 0.0, 1.0, 0.05) var glow_map_strength := 0.75
# El glow map MULTIPLICA el glow existente: sin halos en pantalla no hace nada.
# Con el nivel a oscuras casi todo el glow viene de las lamparas y el vidrio de
# los criopods, asi que se sube la base para que el efecto tenga de que agarrarse.
export(float, 0.0, 4.0, 0.05) var glow_intensity := 1.7
export(float, 0.0, 4.0, 0.05) var glow_bloom := 0.35

func _ready() -> void:
	if not enabled:
		return
	call_deferred("_apply")

func _apply() -> void:
	var gate = get_node_or_null("/root/GLES3VendorGate")
	# En modo plano el Environment no pinta nada: la oscuridad la pone el shader.
	if gate != null and gate.has_method("is_flat_mode") and bool(gate.is_flat_mode()):
		return
	var world := _find_world_environment()
	if world == null or world.environment == null:
		return
	# Se duplica: el .tres del Environment lo comparten otros niveles.
	var env: Environment = world.environment.duplicate()
	env.ambient_light_energy = ambient_energy
	env.fog_enabled = true
	env.fog_color = fog_color
	env.fog_depth_begin = fog_begin
	env.fog_depth_end = fog_end
	env.glow_enabled = true
	env.glow_intensity = glow_intensity
	env.glow_bloom = glow_bloom
	var map: Texture = glow_map
	if map == null:
		map = _build_lens_dirt()
	if map != null and "glow_map" in env:
		env.glow_map = map
		env.glow_map_strength = glow_map_strength
	world.environment = env
	_env = env
	_world = world
	# Valores que RingHubLightState dejo antes de que el Environment existiera.
	if _pending_ambient >= 0.0:
		env.ambient_light_energy = _pending_ambient
	if _pending_background:
		env.background_color = _pending_background_color
	_apply_sun(sun_energy)
	if disable_flashlight_shadow:
		_disable_own_flashlight_shadow()

func _find_world_environment() -> WorldEnvironment:
	var roots := []
	var current_scene = get_tree().current_scene if get_tree() != null else null
	roots.append(current_scene if current_scene != null else get_parent())
	# En tests el nivel cuelga del arbol del runner, no de current_scene: un
	# segundo barrido desde la raiz garantiza encontrar su WorldEnvironment.
	roots.append(get_tree().root if get_tree() != null else null)
	for root in roots:
		if root == null:
			continue
		var pending := [root]
		while not pending.empty():
			var current = pending.pop_back()
			if current is WorldEnvironment:
				return current as WorldEnvironment
			for child in current.get_children():
				pending.append(child)
	return null


# Lens dirt generado al vuelo. Se hace por codigo a proposito: un PNG hay que
# importarlo, y un asset sin .import rompe la escena entera al exportarla (paso).
# Son manchas suaves de bajo contraste — el glow map MULTIPLICA el glow, asi que
# con mucho contraste deja de ensuciar el halo y empieza a inventar lamparas.
const DIRT_W := 128
const DIRT_H := 72

func _build_lens_dirt() -> ImageTexture:
	var image := Image.new()
	image.create(DIRT_W, DIRT_H, false, Image.FORMAT_RGB8)
	image.lock()
	for y in range(DIRT_H):
		for x in range(DIRT_W):
			var u := float(x) / float(DIRT_W)
			var v := float(y) / float(DIRT_H)
			# Suma de senos de frecuencias no enteras: nubes sin repeticion obvia
			# y sin hash noise (que en este proyecto ya rompio en Adreno).
			var n := sin(u * 11.3 + v * 7.1) * 0.5
			n += sin(u * 23.7 - v * 17.9) * 0.28
			n += cos(u * 41.1 + v * 31.3) * 0.16
			var level: float = clamp(0.66 + n * 0.22, 0.35, 1.0)
			image.set_pixel(x, y, Color(level, level, level))
	image.unlock()
	var texture := ImageTexture.new()
	texture.create_from_image(image, Texture.FLAG_FILTER)
	return texture


# Elias SIGUE proyectando sombras de las demas luces del nivel: lo unico que se
# apaga es la sombra de SU PROPIA linterna.
#
# Pilot_v2.tscn prende shadow_enabled en su HelmetFlashlight (pisa el default del
# prop, que es false), y la lampara esta a ~20 cm del cuerpo: el torso y la cabeza
# entran en el frustum del spot y proyectan astillas de poligonos dentro del haz.
# Godot 3 no deja excluir un mesh de las sombras de UNA luz —light_cull_mask solo
# filtra la iluminacion, no el casteo—, asi que la salida es apagar la sombra de
# esa luz. Se nota poco: el haz apunta a donde no hay nada que sombrear.
export(bool) var disable_flashlight_shadow := true

func _disable_own_flashlight_shadow() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.empty():
		return
	var flashlight = (players[0] as Node).find_node("HelmetFlashlight", true, false)
	if flashlight == null:
		return
	if "shadow_enabled" in flashlight:
		flashlight.set("shadow_enabled", false)
	var spot = flashlight.get_node_or_null("SpotLight")
	if spot != null:
		spot.shadow_enabled = false
