extends Node

# Sin class_name: es un autoload y el singleton ya ocupa ese nombre global.
#
# FD-284 — los tres estados de iluminación del domo.
#
#   OSCURAS  bake dark + cero luces runtime. Solo el ambiente del Environment.
#   BAJO     bake dark + el pool runtime de luces cercanas (el comportamiento
#            histórico de LightPathV2 + MobileLightBudget, reusado tal cual).
#   PLENO    bake full (todos los fixtures horneados) + cero luces runtime.
#
# Solo agrega: no toca gameplay, no reemplaza a MobileLightBudget ni a
# SceneLighting, y no emite ninguna señal existente.
#
# El nombre del bake NO está hardcodeado.
#
# PLENO reusa el bake que la escena YA trae (el `light_data` con el que carga), en vez
# de un archivo aparte: duplicarlo costaba 58 MB de .lmbake por nada, y ademas hacia que
# el chequeo de tamaño de scripts/check_added_file_sizes.sh rechazara el archivo nuevo.
# Los demas modos salen del nombre de la escena raíz:
#
#   res://core_v2/levels/interiors/lightmaps/<modo>/<Escena>.lmbake
#
# Hoy solo Dome_Intro tiene BakedLightmap; Dome_Prologue comparte Dome_Base pero
# no hornea, así que ahí el swap de bake es un no-op y quedan operativos los dos
# estados que sí dependen del pool (OSCURAS y BAJO). Cuando Dome_Prologue gane su
# propio bake, alcanza con hornearlo a lightmaps/<modo>/Dome_Prologue.lmbake.

enum { OSCURAS, BAJO, PLENO }

signal state_changed(old, new)

const BAKE_DIR := "res://core_v2/levels/interiors/lightmaps"
const MODE_BY_STATE := {OSCURAS: "dark", BAJO: "dark", PLENO: "full"}
# PLENO no tiene carpeta propia: es el bake que la escena referencia de fabrica.
const MODE_SHIPPED := "full"

# BAJO es el comportamiento previo a FD-284: arrancar en otro estado cambiaría el
# look del domo sin que nadie lo haya pedido.
var state: int = BAJO
# Tests: raíz a inspeccionar y reemplazo de load(), en vez de instanciar el domo
# entero (3200 líneas de .tscn y 56 MB de bake) dentro de una suite headless.
var root_override: Node = null
var bake_loader: FuncRef = null

var _active_bake_path := ""
# Ruta del .lmbake con el que la escena vino cargada. Se lee una sola vez por escena,
# ANTES del primer swap, porque despues light_data ya no es el original.
var _shipped_bake_path := ""
var _pool_sizes := {}  # LightPathV2 -> light_pool_size original
var _scene: Node = null
var _flicker_depth := 0.0
var _flicker_hz := 0.0
var _flicker_phase := 0.0
var _warned_missing := {}


func _ready() -> void:
	set_process(false)
	if Engine.editor_hint:
		return
	var sm := get_node_or_null("/root/SceneManager")
	if sm != null and sm.has_signal("scene_ready"):
		var _e = sm.connect("scene_ready", self, "_on_scene_ready")


func _on_scene_ready(_path, _scene_root, _params) -> void:
	# El autoload sobrevive al cambio de escena, así que el cache de pools apunta
	# a nodos ya liberados y el bake activo es el de la escena anterior.
	_scene = null
	_pool_sizes.clear()
	_active_bake_path = ""
	apply()


func set_state(next: int) -> void:
	if not next in MODE_BY_STATE:
		push_error("[DomeLightState] estado inválido: %s" % next)
		return
	var old: int = state
	state = next
	apply()
	if old != next:
		emit_signal("state_changed", old, next)


func get_state() -> int:
	return state


func get_active_bake_path() -> String:
	return _active_bake_path


# Reaplica el estado actual sobre la escena viva. Idempotente.
func apply() -> void:
	var root: Node = _scene_root()
	if root == null:
		return
	if root != _scene:
		_scene = root
		_pool_sizes.clear()
		_active_bake_path = ""
		_shipped_bake_path = ""
	_apply_bake(root)
	_apply_pool(root)


func _scene_root() -> Node:
	if root_override != null and is_instance_valid(root_override):
		return root_override
	return get_tree().current_scene if get_tree() != null else null


func _apply_bake(root: Node) -> void:
	var baked: BakedLightmap = _find_baked(root)
	if baked == null:
		return  # Escena sin lightmap horneado (Dome_Prologue): nada que intercambiar.
	if _shipped_bake_path == "" and baked.light_data != null:
		_shipped_bake_path = baked.light_data.resource_path
		_active_bake_path = _shipped_bake_path
	var mode: String = MODE_BY_STATE[state]
	var path: String = _shipped_bake_path if mode == MODE_SHIPPED else "%s/%s/%s.lmbake" % [BAKE_DIR, mode, root.name]
	if path == "":
		return  # La escena no traia bake y este modo no tiene archivo propio.
	if path == _active_bake_path:
		return
	if bake_loader == null and not ResourceLoader.exists(path):
		# Todavía no se horneó ese modo: se conserva el bake que trae la escena en
		# vez de dejarla sin lightmap, que se vería peor que no haber cambiado nada.
		if not _warned_missing.has(path):
			_warned_missing[path] = true
			push_warning("[DomeLightState] falta %s; se conserva el bake de la escena." % path)
		return
	# iOS nunca puede tener los dos bakes en memoria: se suelta la referencia
	# ANTES de pedir la nueva, para que el recurso viejo llegue a refcount 0.
	# ponytail: si SceneManager mantiene vivo el PackedScene del nivel, su
	# ext_resource sostiene el bake original igual; liberar el PackedScene tras
	# instanciar es el siguiente paso si iOS sigue quedándose corto de memoria.
	baked.light_data = null
	_active_bake_path = ""
	var data = bake_loader.call_func(path) if bake_loader != null else load(path)
	if data == null:
		push_error("[DomeLightState] no pude cargar %s" % path)
		return
	baked.light_data = data
	_active_bake_path = path
	# En iOS el motor no dibuja el lightmap y IOSLightmapFallback lo aplica a mano
	# sobre los materiales. Cambiar light_data sin reaplicarlo deja las superficies
	# con el bake anterior muestreado desde el shader.
	var fallback: Node = _find_named(root, "IOSLightmapFallback")
	if fallback != null and fallback.has_method("_apply"):
		fallback.call_deferred("_apply")


func _apply_pool(root: Node) -> void:
	var wants_pool: bool = state == BAJO
	var stack: Array = [root]
	while not stack.empty():
		var node: Node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		if "light_pool_size" in node:
			var current: int = int(node.light_pool_size)
			# Baseline vivo, no el primero que vimos: MobileLightBudget sube y baja este
			# valor por su cuenta (mejora progresiva hasta max_pool_size). Cachear solo
			# la primera lectura devolvia un pool viejo al salir de PLENO.
			if current > 0 or not _pool_sizes.has(node):
				_pool_sizes[node] = current
			var target: int = int(_pool_sizes[node]) if wants_pool else 0
			if int(node.light_pool_size) != target:
				node.light_pool_size = target
				# _drive_lights() corta antes de reconciliar cuando el pool es 0,
				# así que sin este empujón las OmniLight ya creadas seguirían en el
				# árbol iluminando en PLENO.
				if node.has_method("_ensure_light_pool"):
					node.call("_ensure_light_pool")
		for child in node.get_children():
			stack.push_back(child)


# --- Parpadeo -------------------------------------------------------------
#
# Capa sobre el estado actual, no un estado más: no rehornea nada ni toca el
# .lmbake. Se apoya en SceneLighting, que ya sabe escalar la energía de todas las
# luces y el ambiente de la escena, así que no agrega materiales, transparencias
# ni post-proceso (restricción GLES2).
#
# ponytail: modulación global de brillo, no un material emisivo por fixture. Para
# la tormenta alcanza; si hace falta que parpadeen solo algunos fixtures, el
# siguiente paso es un shader param sobre el material de los BulbGlowBatch.
# Comparte SceneLighting con AirlockTransitionFX: parpadear durante una
# transición de airlock haría que se pisen. Apagar el flicker antes.

func set_flicker(depth: float, hz: float) -> void:
	_flicker_depth = clamp(depth, 0.0, 1.0)
	_flicker_hz = max(hz, 0.0)
	var active: bool = _flicker_depth > 0.0 and _flicker_hz > 0.0
	set_process(active)
	if not active:
		_flicker_phase = 0.0
		var lighting := get_node_or_null("/root/SceneLighting")
		if lighting != null:
			lighting.restore_brightness()


func clear_flicker() -> void:
	set_flicker(0.0, 0.0)


func _process(delta: float) -> void:
	var lighting := get_node_or_null("/root/SceneLighting")
	if lighting == null:
		set_process(false)
		return
	_flicker_phase += delta * _flicker_hz * TAU
	# Dos senos inconmensurables: irregular a la vista y sin RNG, que rompería el
	# replay determinista.
	var wave: float = 0.5 + 0.5 * sin(_flicker_phase) * sin(_flicker_phase * 1.618)
	lighting.set_brightness(1.0 - _flicker_depth * wave)


# --- Snapshot / replay ----------------------------------------------------
#
# Solo el enum y el hash del bake activo: la ruta completa cambia de largo con el
# nombre de la escena y el .lmbake pesa 56 MB, ninguno de los dos entra en un
# snapshot. El hash alcanza para detectar que un replay corrió con otro bake.

func get_snapshot() -> Dictionary:
	return {
		"dome_light_state": state,
		"dome_bake_hash": _active_bake_path.hash(),
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("dome_light_state"):
		set_state(int(data["dome_light_state"]))


func _find_baked(root: Node) -> BakedLightmap:
	var stack: Array = [root]
	while not stack.empty():
		var node: Node = stack.pop_back()
		if node is BakedLightmap:
			return node as BakedLightmap
		for child in node.get_children():
			stack.push_back(child)
	return null


func _find_named(root: Node, wanted: String) -> Node:
	var stack: Array = [root]
	while not stack.empty():
		var node: Node = stack.pop_back()
		if node.name == wanted:
			return node
		for child in node.get_children():
			stack.push_back(child)
	return null
