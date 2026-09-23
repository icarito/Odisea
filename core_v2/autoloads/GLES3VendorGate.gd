extends Node

# GLES3VendorGate.gd — Contrato §11.10: renderer GLES3 en Mali (handhelds FRT).
#
# En Mali-G31 (GLES3 via FRT/EGL) las pasadas full-screen del Environment —
# fog, glow, DOF y tonemap ACES — fallan en silencio: el mundo se ve blanco/
# cian lavado con el HUD dibujando encima (log limpio, sin errores de shader).
# El mismo build con esas pasadas apagadas renderiza texturizado (verificado
# en device con ANNA, 2026-09-14).
#
# Este gate detecta el adapter por vendor ("Mali") y apaga las pasadas
# riesgosas de CUALQUIER WorldEnvironment que entre al árbol, dejando el
# ambiente en el nivel conservador que se sabe correcto (el equivalente a
# Environment_InteriorLab: bg color, sin post-process). Scope por vendor,
# no por escena: los levels siguen compartiendo sus .tres en desktop/iOS.

const VENDOR_TAG := "mali"
# Modo plano unshaded: un shader de "shading falso" (lambert de una direccion en
# espacio de camara + AO vertical) para que las formas se lean sin costo de PBR.
const FLAT_FAKE_SHADER = preload("res://core_v2/visual/FlatFake.shader")
# Variante cull_disabled para materiales fuente doble-lado (rejillas CULL_DISABLED):
# el deck horneado puede tener winding hacia abajo y con cull_back desaparece.
const FLAT_FAKE_DOUBLE_SIDED_SHADER = preload("res://core_v2/visual/FlatFakeDoubleSided.shader")
# Prototipo de "luces apagadas": misma base que FlatFake pero con linterna.
# Se activa con ODISEA_FLASHLIGHT=1 y se calibra con ODISEA_WORLD_LIGHT /
# ODISEA_GLOW_FLOOR, para poder comparar variantes sin recompilar.
const FLAT_FAKE_FLASHLIGHT_SHADER = preload("res://core_v2/visual/FlatFakeFlashlight.shader")
const FLAT_FAKE_FLASHLIGHT_DS_SHADER = preload("res://core_v2/visual/FlatFakeFlashlightDoubleSided.shader")
# Variantes transparentes: el vidrio (criopods, ventanas) conserva su transparencia en
# vez de quedar como un panel opaco. Mismo shading falso, con blend_mix + ALPHA.
const FLAT_FAKE_TRANSPARENT_SHADER = preload("res://core_v2/visual/FlatFakeTransparent.shader")
const FLAT_FAKE_TRANSPARENT_DOUBLE_SIDED_SHADER = preload("res://core_v2/visual/FlatFakeTransparentDoubleSided.shader")
# SOLO adapters verificados en device (§11.10): un adapter desconocido NO se
# gatea — nunca dejar caer un device por culpa de otro.
const KNOWN_CONSERVATIVE_ADAPTERS := ["mali-g31"]

# Test seam: fuerza el gate sin depender del adapter del runner headless.
export var force_gate := false

# Override de desarrollo (tools/launch_game.sh --lowend): fuerza el tier LOW en
# cualquier dispositivo sin tocar settings.cfg. Es la contraparte de runtime del
# override.cfg que el handheld arma desde portmaster/lowend.cfg.
const FORCE_LOW_TIER_ENV := "ODISEA_FORCE_LOW_TIER"

# Escape para el A/B de niebla (perf_bisect.sh): fog_enabled cayo junto con los pases
# full-screen caros, pero en GLES3 la niebla se computa DENTRO del scene shader (UBO
# SceneData: fog_depth_enabled/begin/end en scene.glsl del fork), no es un pase aparte.
# En un GPU tile-based es barata y es lo que mas profundidad da por lo que cuesta.
const KEEP_FOG_ENV := "ODISEA_KEEP_FOG"

# Escape para MEDIR el glow, igual que el de la niebla. El glow cayo con el resto
# de los pases full-screen por §11.10 (el mundo se veia blanco/cian lavado en
# Mali), pero eso se midio en 2026-09-14 y el motor cambio bastante desde
# entonces. ODISEA_KEEP_GLOW=1 lo deja pasar para ver que cuesta y si sigue roto.
const KEEP_GLOW_ENV := "ODISEA_KEEP_GLOW"

var _gated_active := false
var _env_forced_low_tier := false
var _env_keep_fog := false
var _env_keep_glow := false
# Los tools de horneado (tools/bake_*.gd) instancian la escena fuente y guardan
# los materiales recolectados. Si el gate corre en tier LOW, _low_tier_material
# muta esos recursos COMPARTIDOS en memoria y el bake los persiste sin
# transparencia ni alpha scissor: asi quedaron opacas las rejillas de los
# andamios al rehornear en 57ae5b2d. El bake pide esto antes de instanciar.
var _mutation_suspended := false

# FD-299: en tier LOW la fisica corre a 20 Hz. Medido en el Anbernic (2026-09-22, release,
# FRT_PERF, mismas 3 corridas intercaladas por tasa, escena RingHub en el spawn):
#   30 Hz: frame 46.9 ms, fps 21.3, 1.42 pasos/frame, 20.8 ms de scripts por frame
#   20 Hz: frame 40.9 ms, fps 24.5 (+15%), 0.82 pasos/frame, 13.1 ms
# El paso del jugador se deriva de Engine.iterations_per_second, asi que no hay camara lenta.
# El perfil LOW ya trae physics_interpolation=true: el transform del player/camara se muestrea
# por frame de render, asi que bajar la tasa no escalona la camara (la logica de OTS/spring arm
# si corre al ritmo del tick). Los replays fuerzan el rate del proyecto, asi que la validacion
# de determinismo en CI no cambia. Para volver atras: 30.
const LOW_TIER_PHYSICS_FPS := 20

# Un replay mapea 1 frame de buffer -> 1 tick de fisica, sin importar el Hz real: el paso
# del jugador (SessionManager.FIXED_DT) esta fijo a 1/60 a proposito, pero todo lo que NO se
# stepea a mano (RigidBody, Area, _physics_process nativo de props sueltos) sigue el Hz real
# del motor. Si ese Hz es 30 (tier LOW) en vez de los 60 con que se grabo, esos nodos avanzan
# el DOBLE de tiempo simulado por el mismo numero de frames consumidos -> deriva catastrofica
# (medido: drift de ~2833 m en un replay de escritorio reproducido en el Anbernic). Mientras
# haya una grabacion o reproduccion activa, se fuerza el rate del proyecto sin importar el
# tier; SessionManager llama a set_replay_active en los bordes de is_recording/is_replaying.
var _replay_active := false

func set_replay_active(active: bool) -> void:
	if _replay_active == active:
		return
	_replay_active = active
	sync_physics_rate()

func _ready() -> void:
	_env_forced_low_tier = _read_env_forced_low_tier()
	_env_keep_fog = OS.get_environment(KEEP_FOG_ENV).to_lower() in ["1", "true", "yes", "on"]
	_env_keep_glow = OS.get_environment(KEEP_GLOW_ENV).to_lower() in ["1", "true", "yes", "on"]
	_unshaded_mode = OS.get_environment("ODISEA_UNSHADED").strip_edges()
	_flat_debug = OS.get_environment("ODISEA_FLAT_DEBUG") in ["1", "true", "yes", "on"]
	var amb_env := OS.get_environment("ODISEA_FLAT_AMBIENT").strip_edges()
	if amb_env.is_valid_float():
		_flat_ambient = float(amb_env)
	# La linterna del perfil plano va atada al MODO PLANO, que es el flag conocido
	# del tier bajo: si los materiales son unshaded, ninguna luz real los toca y
	# esta es la unica forma de tener linterna. ODISEA_FLASHLIGHT=0 la apaga para
	# poder comparar contra el FlatFake pelado.
	_flashlight_mode = _unshaded_mode == "3"
	var fl_env := OS.get_environment("ODISEA_FLASHLIGHT").strip_edges()
	if fl_env != "":
		_flashlight_mode = fl_env in ["1", "true", "yes", "on"]
	# Valor elegido mirando las tres variantes en el device (opcion 1): oscuridad
	# casi total, el cono es lo unico que ilumina.
	_world_light = 0.02
	var wl := OS.get_environment("ODISEA_WORLD_LIGHT").strip_edges()
	if wl.is_valid_float():
		_world_light = float(wl)
	_glow_floor = 0.15
	var gf := OS.get_environment("ODISEA_GLOW_FLOOR").strip_edges()
	if gf.is_valid_float():
		_glow_floor = float(gf)
	if _unshaded_mode == "3":
		# El lightmap manual pisaria nuestros materiales por superficie.
		OS.set_environment("ODISEA_MANUAL_LIGHTMAP", "")
		_load_flat_overrides()
	_pilot_billboard = OS.get_environment("ODISEA_PILOT_BILLBOARD") in ["1", "true", "yes", "on"]
	if _pilot_billboard or _flashlight_mode:
		set_process(true)
	_detect_gate()
	sync_physics_rate()
	_sync_low_tier_env_hints()
	# A/B del cap de render: ODISEA_TARGET_FPS=0 lo saca (techo), N lo fija.
	var tf := OS.get_environment("ODISEA_TARGET_FPS").strip_edges()
	if tf.is_valid_integer():
		Engine.target_fps = int(tf)
	print("[GLES3VendorGate] render: target_fps=%d physics=%d" % [Engine.target_fps, Engine.iterations_per_second])
	get_tree().connect("node_added", self, "_on_node_added")

# Hints de entorno del tier LOW que tienen que estar seteados ANTES de que las
# escenas instancien sus nodos (leen el env en _ready). Hoy: las sombras falsas
# (quads/raycast por prop) son ~+7% de ticks/s en RG351V y son cosmeticas.
func _sync_low_tier_env_hints() -> void:
	if is_low_tier():
		OS.set_environment("ODISEA_DISABLE_FAKE_SHADOW", "1")

# Fuera del tier vuelve al valor del proyecto: desktop, CI y replays siguen a 60 Hz. Se llama
# tambien al cambiar la opcion "low end" en el menu.
func sync_physics_rate() -> void:
	var target: int = LOW_TIER_PHYSICS_FPS if (is_low_tier() and not _replay_active) else int(ProjectSettings.get_setting("physics/common/physics_fps"))
	# A/B de rate de fisica sin recompilar: a fps bajos el motor corre varios pasos por
	# frame (catch-up), asi que el rate define cuanto trabajo de fisica entra por frame.
	var override := OS.get_environment("ODISEA_PHYSICS_FPS").strip_edges()
	if override.is_valid_integer():
		target = int(override)
	if Engine.iterations_per_second != target:
		Engine.iterations_per_second = target

func _detect_gate() -> void:
	var adapter := String(VisualServer.get_video_adapter_name()).to_lower()
	var vendor := String(VisualServer.get_video_adapter_vendor()).to_lower()
	for known in KNOWN_CONSERVATIVE_ADAPTERS:
		if adapter.find(known) != -1 or vendor.find(known) != -1:
			_gated_active = true
			break
	if _gated_active:
		# El lightmap nativo colisiona de unidad en Mali (§11.10): el sync del
		# camino manual lo maneja _sync_manual_lightmap al entrar los niveles.
		print("[GLES3VendorGate] %s: ambiente conservador + lightmap manual" % adapter)

var _manual_lightmap_synced := false

func _on_node_added(node: Node) -> void:
	if _mutation_suspended:
		return
	if node.is_in_group("lowend_skip"):
		# Cortes cosmeticos declarativos (FD-299 3b): la escena marca la decoracion
		# y el gate la libera. Nunca marcar subtrees con colision o gameplay.
		node.queue_free()
	if _pilot_billboard and node.name == "Pilot":
		call_deferred("_hide_pilot_visual_for_billboard", node)
	if node is WorldEnvironment:
		var gated := is_low_tier()
		# El lightmap manual SOLO en adapters donde el camino nativo está roto
		# (Mali-G31 verificado): es un shader del camino GLES2 y en Adreno
		# GLES3 muestrea 0 → nivel negro. El force del usuario no lo activa.
		# En modo plano (3) no se activa: pisaria los materiales planos por superficie.
		_sync_manual_lightmap(_gated_active and _unshaded_mode != "3")
		if gated:
			strip_environment(node.environment)
	elif is_low_tier():
		_low_tier_node(node)

# Tier LOW (FD-299 3b): decisiones una vez por nodo, sin monitores por frame.
func is_low_tier() -> bool:
	return _gated_active or force_gate or _user_forced_low_end() or _env_forced_low_tier

# Congela toda mutacion del gate (materiales compartidos, sombras, environments)
# mientras un tool offline recolecta geometria/materiales para hornear. Sin esto,
# un bake corrido con ODISEA_FORCE_LOW_TIER=1 escribe la huella del tier LOW en
# los .material compartidos y las rejillas quedan opacas para todos los perfiles.
func suspend_node_mutation() -> void:
	_mutation_suspended = true

# Modo plano (ODISEA_UNSHADED 1/2/3): los materiales del mundo son unshaded y
# saltean el pase de luz, asi que la blob shadow analitica (light.blob_shadow_*)
# no los oscurece. FakeShadow lo consulta para usar el quad legacy en vez de la blob.
func is_flat_mode() -> bool:
	return _unshaded_mode != ""

var _unshaded_mat: SpatialMaterial = null
var _flat_cache := {}
var _flat_avg_cache := {}
var _flat_overrides := {}
# ODISEA_FLAT_DEBUG=1: loguea una vez por hint (nodo+mesh+material) el color elegido.
var _flat_debug := false
# < 0 = no tocar (el shader usa su default). ODISEA_FLAT_AMBIENT lo pisa.
var _flat_ambient := -1.0
var _flashlight_mode := false
# Materiales que llevan el shader de linterna: hay que sincronizarles la posicion
# y la direccion de la SpotLight. Son POCOS (uno por color/glow, no uno por nodo,
# gracias al cache de _flat_material), asi que actualizarlos sale barato.
var _flashlight_materials := []
var _flashlight_node: Spatial = null
var _flashlight_spot: Spatial = null
var _flashlight_accum := 0.0
var _world_light := 0.05
var _glow_floor := 0.35
var _flat_debug_seen := {}
# "1" = un solo material plano gris para todo (techo de ganancia, rompe el look).
# "2" = solo SpatialMaterial pasa a unshaded conservando albedo color/textura (los
#       ShaderMaterial del proyecto quedan sombreados, asi no se rompen).
# "3" = unshaded "albedo plano": un unico material por mesh, con el color promedio
#       del material original (color * promedio de la textura). Legible y sin luz.
var _unshaded_mode := ""
# "1" = techo de medicion del fallback billboard: oculta el Visual del Pilot y apaga
# su procesamiento (sin skinning ni AnimationTree), manteniendo el controller.
var _pilot_billboard := false

func _hide_pilot_visual_for_billboard(pilot: Node) -> void:
	if not is_instance_valid(pilot):
		return
	var vis = pilot.get_node_or_null("Visual")
	if vis == null:
		vis = pilot.find_node("Visual", true, false)
	if vis == null:
		print("[GLES3VendorGate] billboard: no encontre Visual en ", pilot.name)
		return
	if not vis.visible:
		return
	vis.visible = false
	vis.set_process(false)
	vis.set_physics_process(false)
	vis.propagate_call("set_process", [false])
	vis.propagate_call("set_physics_process", [false])
	print("[GLES3VendorGate] Pilot billboard ceiling: Visual oculto y procesamiento apagado (", pilot.name, ")")

# El nombre del nodo del player cambia segun como lo instancie la escena; en vez de
# matchear por nombre, se espera a que SessionManager tenga player y se oculta su Visual.
func _process(delta: float) -> void:
	if _flashlight_mode:
		_sync_flashlight(delta)
	if not _pilot_billboard:
		if not _flashlight_mode:
			set_process(false)
		return
	var players := get_tree().get_nodes_in_group("player") if get_tree() != null else []
	if players.empty():
		return
	_hide_pilot_visual_for_billboard(players[0])
	set_process(false)

func _unshaded_shared_material() -> SpatialMaterial:
	if _unshaded_mat == null:
		_unshaded_mat = SpatialMaterial.new()
		_unshaded_mat.flags_unshaded = true
		_unshaded_mat.albedo_color = Color(0.62, 0.66, 0.72)
	return _unshaded_mat

# Promedio del albedo de una textura, muestreado en una grilla (barato) y cacheado por
# textura. Es el "pre-bake" en runtime del albedo plano.
func _average_color(tex: Texture) -> Color:
	if tex == null:
		return Color(1, 1, 1)
	var id := tex.get_instance_id()
	if _flat_avg_cache.has(id):
		return _flat_avg_cache[id]
	var result := Color(1, 1, 1)
	var img: Image = tex.get_data()
	if img != null and img.get_width() > 0 and img.get_height() > 0:
		img.lock()
		var w := img.get_width()
		var h := img.get_height()
		var sx := int(max(1, w / 8))
		var sy := int(max(1, h / 8))
		var acc := Color(0, 0, 0, 0)
		var n := 0
		var x := 0
		while x < w:
			var y := 0
			while y < h:
				acc += img.get_pixel(x, y)
				n += 1
				y += sy
			x += sx
		img.unlock()
		if n > 0:
			result = Color(acc.r / n, acc.g / n, acc.b / n, acc.a / n)
	_flat_avg_cache[id] = result
	return result

# Color representativo: dominante por bucket cuantizado (16x16 muestras, opacas), que
# evita el gris embarrado del promedio plano y suele dar un color reconocible.
func _representative_color(tex: Texture) -> Color:
	if tex == null:
		return Color(1, 1, 1)
	var id := tex.get_instance_id()
	if _flat_avg_cache.has(id):
		return _flat_avg_cache[id]
	var result := Color(1, 1, 1)
	var img: Image = tex.get_data()
	if img != null and img.get_width() > 0 and img.get_height() > 0:
		img.lock()
		var w := img.get_width()
		var h := img.get_height()
		var sx := int(max(1, w / 16))
		var sy := int(max(1, h / 16))
		var buckets := {}
		var x := 0
		while x < w:
			var y := 0
			while y < h:
				var c := img.get_pixel(x, y)
				if c.a > 0.3:
					var key := int(c.r * 7.0) * 64 + int(c.g * 7.0) * 8 + int(c.b * 7.0)
					if not buckets.has(key):
						buckets[key] = [0, Color(0, 0, 0, 0)]
					var e = buckets[key]
					e[0] += 1
					e[1] += c
					buckets[key] = e
				y += sy
			x += sx
		img.unlock()
		var best_n := 0
		var best: Color = Color(1, 1, 1)
		for k in buckets.keys():
			var e = buckets[k]
			if int(e[0]) > best_n:
				best_n = int(e[0])
				var s: Color = e[1]
				best = Color(s.r / best_n, s.g / best_n, s.b / best_n, 1.0)
		if best_n > 0:
			result = best
	_flat_avg_cache[id] = result
	return result

# Paleta de respaldo por nombre, para ShaderMaterial sin uniforms legibles: asi los
# props del domo quedan entendibles (criopodos, hielo, caños, luces, barandas...).
func _palette_color(text: String) -> Color:
	var t := text.to_lower()
	# El vidrio va ANTES que pod/criopod: el vidrio de un criopod matchea ambos y debe
	# quedar cyan encendido, no del color del cuerpo.
	if t.find("glass") != -1 or t.find("cristal") != -1 or t.find("vidrio") != -1:
		return Color(0.22, 0.82, 0.90)
	if t.find("elevator") != -1 or t.find("ascensor") != -1:
		return Color(0.35, 0.40, 0.48)
	if t.find("criopod") != -1 or t.find("pod") != -1:
		return Color(0.20, 0.26, 0.34)
	if t.find("holo") != -1 or t.find("display") != -1 or t.find("screen") != -1 or t.find("pantalla") != -1:
		return Color(0.22, 0.72, 0.82)
	if t.find("ice") != -1 or t.find("frost") != -1 or t.find("snow") != -1 or t.find("hielo") != -1:
		return Color(0.45, 0.70, 0.82)
	if t.find("hazard") != -1 or t.find("warning") != -1 or t.find("warn") != -1:
		return Color(0.85, 0.55, 0.12)
	if t.find("rail") != -1 or t.find("barand") != -1:
		return Color(0.88, 0.70, 0.15)
	if t.find("grate") != -1 or t.find("scaffold") != -1 or t.find("andam") != -1 or t.find("soporte") != -1 or t.find("support") != -1 or t.find("stilt") != -1:
		return Color(0.11, 0.14, 0.18)
	# Espiral/andamios/pasarelas: el mesh mezcla deck y barandas, asi que va acero
	# oscuro (no se puede pintar solo la baranda sin separar el material en el bake).
	if t.find("spiral") != -1 or t.find("walkway") != -1 or t.find("stair") != -1 or t.find("hubspoke") != -1 or t.find("spoke") != -1 or t.find("truss") != -1 or t.find("beam") != -1:
		return Color(0.30, 0.34, 0.40)
	if t.find("floor") != -1 or t.find("piso") != -1 or t.find("terrace") != -1 or t.find("terraza") != -1 or t.find("deck") != -1:
		return Color(0.24, 0.29, 0.35)
	if t.find("dome") != -1 or t.find("shell") != -1 or t.find("background") != -1 or t.find("fondo") != -1:
		return Color(0.08, 0.10, 0.13)
	if t.find("door") != -1 or t.find("puerta") != -1 or t.find("airlock") != -1:
		return Color(0.20, 0.25, 0.31)
	if t.find("wall") != -1 or t.find("panel") != -1:
		return Color(0.18, 0.22, 0.28)
	if t.find("pipe") != -1 or t.find("duct") != -1 or t.find("tuber") != -1:
		return Color(0.15, 0.18, 0.23)
	if t.find("lamp") != -1 or t.find("light") != -1 or t.find("glow") != -1 or t.find("emissive") != -1:
		return Color(1.0, 0.92, 0.75)
	if t.find("pilot") != -1 or t.find("elias") != -1 or t.find("suit") != -1 or t.find("character") != -1:
		return Color(1.0, 0.52, 0.10)
	return Color(0.22, 0.27, 0.33)

# Overrides de color editables sin recompilar: user://flat_albedo.json con
# {"clave": "#rrggbb"} o [{"match":"clave","color":"#rrggbb"}]. La clave matchea
# (substring) contra resource_path, resource_name o nombre del nodo, en minusculas.
# Aplana un MultiMeshInstance superficie por superficie. Duplica mesh y multimesh
# (el .tres es compartido entre instancias) y marca el nodo para no rehacerlo si el
# gate vuelve a pasar por el.
const FLAT_MM_META := "odisea_flat_multimesh"

func _flatten_multimesh_surfaces(node: MultiMeshInstance, mesh: Mesh, hint: String) -> void:
	if node.has_meta(FLAT_MM_META):
		return
	var dup := mesh.duplicate() as Mesh
	if dup == null:
		node.material_override = _flat_material(mesh.surface_get_material(0), hint)
		return
	for s in range(dup.get_surface_count()):
		var ssrc = dup.surface_get_material(s)
		var shint := hint
		if ssrc != null:
			if "resource_path" in ssrc:
				shint += " " + str(ssrc.resource_path)
			if "resource_name" in ssrc:
				shint += " " + str(ssrc.resource_name)
		dup.surface_set_material(s, _flat_material(ssrc, shint))
	var mm := node.multimesh.duplicate() as MultiMesh
	mm.mesh = dup
	node.multimesh = mm
	node.material_override = null
	node.set_meta(FLAT_MM_META, true)

# Overrides que VIAJAN en el build. user://flat_albedo.json es una herramienta de
# tuneo local del escritorio: no esta en el paquete, asi que un handheld nunca los
# recibia y ahi es justo donde corre el modo plano. El JSON sigue mandando (misma
# clave lo pisa, y puede agregar otras).
# El orden importa: _override_color devuelve el PRIMER match por substring, asi que
# la clave mas especifica va primero. El vidrio de la lampara tiene que ganarle al
# cuerpo, porque "industrial_wall_lamp" tambien matchea "industrial_wall_lamp_glass".
const FLAT_OVERRIDE_DEFAULTS := [
	["industrial_wall_lamp_glass", "ffeac0"],
	["industrial_wall_lamp", "16181c"],
]

# Pasa al shader plano donde esta la linterna y si esta encendida. Se hace por
# codigo porque Godot 3 no tiene uniforms globales: cada material del cache
# necesita su copia. Va a 20 Hz, no por frame: el cono se mueve con la cabeza de
# Elias y a esa tasa no se nota, y aca la CPU es el recurso escaso.
const FLASHLIGHT_SYNC_INTERVAL := 0.05

func _sync_flashlight(delta: float) -> void:
	if _flashlight_materials.empty():
		return
	_flashlight_accum += delta
	if _flashlight_accum < FLASHLIGHT_SYNC_INTERVAL:
		return
	_flashlight_accum = 0.0
	if not is_instance_valid(_flashlight_spot):
		_resolve_flashlight()
		if not is_instance_valid(_flashlight_spot):
			return
	var xform: Transform = _flashlight_spot.global_transform
	# El haz de una SpotLight apunta por su -Z, igual que una camara.
	var dir: Vector3 = -xform.basis.z.normalized()
	var on := 0.0
	if is_instance_valid(_flashlight_node):
		if bool(_flashlight_node.get("enabled")) and _flashlight_spot.visible:
			on = 1.0
	elif _flashlight_spot.visible:
		on = 1.0
	# El cono del shader se DERIVA de la luz, no se fija a mano: si no, el haz
	# analitico y el VolumetricCone (que es geometria y se ve igual en modo plano)
	# quedan con radios distintos y se nota el borde donde uno termina y el otro no.
	# spot_angle en Godot es el SEMI-angulo, del eje al borde.
	var cos_outer := 1.0
	var cos_inner := 1.0
	var reach := 14.0
	if _flashlight_spot is SpotLight:
		var spot := _flashlight_spot as SpotLight
		cos_outer = cos(deg2rad(clamp(spot.spot_angle, 1.0, 89.0)))
		# El borde interno cierra a ~60% del angulo: da un degrade corto en vez de
		# un corte duro, parecido a la atenuacion angular de la SpotLight.
		cos_inner = cos(deg2rad(clamp(spot.spot_angle * 0.6, 0.5, 89.0)))
		reach = spot.spot_range
	for mat in _flashlight_materials:
		if not is_instance_valid(mat):
			continue
		mat.set_shader_param("flashlight_pos", xform.origin)
		mat.set_shader_param("flashlight_dir", dir)
		mat.set_shader_param("flashlight_on", on)
		mat.set_shader_param("cone_cos_outer", cos_outer)
		mat.set_shader_param("cone_cos_inner", cos_inner)
		mat.set_shader_param("flashlight_range", reach)

func _resolve_flashlight() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.empty():
		return
	var found = (players[0] as Node).find_node("HelmetFlashlight", true, false)
	if found == null:
		return
	_flashlight_node = found as Spatial
	var spot = found.get_node_or_null("SpotLight")
	_flashlight_spot = spot as Spatial if spot != null else _flashlight_node

func _load_flat_overrides() -> void:
	_flat_overrides.clear()
	for pair in FLAT_OVERRIDE_DEFAULTS:
		_flat_overrides[str(pair[0]).to_lower()] = str(pair[1])
	var f := File.new()
	if f.open("user://flat_albedo.json", File.READ) != OK:
		print("[GLES3VendorGate] flat albedo: %d overrides por defecto" % _flat_overrides.size())
		return
	var parsed = JSON.parse(f.get_as_text())
	f.close()
	if parsed.error != OK:
		print("[GLES3VendorGate] flat albedo: JSON invalido (", parsed.error_string, ")")
		return
	var data = parsed.result
	if typeof(data) == TYPE_DICTIONARY:
		for k in data.keys():
			_flat_overrides[str(k).to_lower()] = str(data[k])
	elif typeof(data) == TYPE_ARRAY:
		for e in data:
			if typeof(e) == TYPE_DICTIONARY and e.has("match") and e.has("color"):
				_flat_overrides[str(e["match"]).to_lower()] = str(e["color"])
	print("[GLES3VendorGate] flat albedo overrides: ", _flat_overrides.size())

func _override_color(text: String) -> Color:
	if _flat_overrides.empty():
		return Color(0, 0, 0, 0)
	var t := text.to_lower()
	for k in _flat_overrides.keys():
		if t.find(k) != -1:
			var c := Color(str(_flat_overrides[k]).lstrip("#"))
			if c.a > 0.0:
				return c
	return Color(0, 0, 0, 0)

# Hint para paleta/overrides: SOLO nombre del nodo + resource_path del mesh + del
# material. Nada de ancestros: contenedores como "@Floor0@55", "Floors" o
# "ElevatorProp" matcheaban "floor"/"elevator" en props que no son ni piso ni ascensor.
func _node_hint(node: Node, mesh: Mesh) -> String:
	var parts := PoolStringArray()
	parts.append(str(node.name))
	if mesh != null:
		parts.append(str(mesh.resource_path))
	return parts.join(" ")

# Materiales que deben conservar el suyo en tier LOW porque son transparencia por
# diseno: pantallas holograficas, la sombra falsa del piloto y humo/vapor/leak.
# Aplanarlos los vuelve un panel opaco (FlatFake no tiene blend) y en el modo 3 el
# gate ademas suelta el material_override. Se detectan por el nombre del nodo (solo el
# nodo, no la ruta del mesh, para no atrapar muebles tipo "DisplayCase") o por la ruta
# del shader del material fuente.
func _keeps_own_material(node: Node, src) -> bool:
	var n := str(node.name).to_lower()
	if n.find("holo") != -1 or n.find("screen") != -1 \
			or n.find("pantalla") != -1 or n.find("display") != -1 \
			or n.find("shadow") != -1 or n.find("fakeshadow") != -1 \
			or n.find("smoke") != -1 or n.find("steam") != -1 \
			or n.find("vapor") != -1 or n.find("vapour") != -1 \
			or n.find("leak") != -1 or n.find("mist") != -1 \
			or n.find("haze") != -1 or n.find("fog") != -1 \
			or n.find("flashlight") != -1 or n.find("linterna") != -1 \
			or n.find("volumetric") != -1 or n.find("lightcone") != -1 \
			or n.find("lightbeam") != -1 or n.find("lightshaft") != -1:
		return true
	if src is ShaderMaterial:
		var sh := src as ShaderMaterial
		if sh.shader != null:
			var sp := str(sh.shader.resource_path).to_lower()
			for tok in ["holoscreen", "hologlass", "fakeshadow", "shadow", "smoke", "steam", "vapor", "leak", "mist", "volumetric", "flashlight", "lightbeam", "lightshaft"]:
				if sp.find(tok) != -1:
					return true
	return false

# Color plano del material original: albedo_color (SpatialMaterial) o los uniforms mas
# comunes de los shaders del proyecto, por color dominante de la textura. `hint` (nodo +
# mesh) alimenta la paleta de respaldo y los overrides por nombre.
func _flat_material(source, hint: String = "") -> ShaderMaterial:
	var color := Color(0, 0, 0, 0)
	var tex: Texture = null
	var name_hint := hint
	# El material fuente CULL_DISABLED (rejillas/decks) debe seguir viendose desde
	# ambos lados: el quad horneado puede venir con winding invertido y con cull_back
	# el piso caminable desaparece. El resto de los materiales queda cull_back.
	var double_sided := false
	# Alpha del material fuente, para no perder la transparencia del vidrio.
	var src_alpha := 1.0
	# Los materiales del bake marcan su categoria con emision (barandas, vidrio
	# `mat_cyan`, warning): si hay emision, se usa el tinte del albedo sin promediar
	# la textura (que lo apagaba a gris) y se los enciende con glow.
	var emissive_glow := -1.0
	if source is SpatialMaterial:
		var sm := source as SpatialMaterial
		double_sided = sm.params_cull_mode == SpatialMaterial.CULL_DISABLED
		color = sm.albedo_color
		src_alpha = color.a
		tex = sm.albedo_texture
		name_hint += " " + str(sm.resource_path) + " " + str(sm.resource_name)
		if sm.emission_enabled:
			var em: Color = sm.emission
			emissive_glow = clamp(max(em.r, max(em.g, em.b)) * 4.0, 0.25, 1.0)
	elif source is ShaderMaterial:
		var sh := source as ShaderMaterial
		name_hint += " " + str(sh.resource_path) + " " + str(sh.resource_name)
		if sh.shader != null and sh.shader.code.find("cull_disabled") != -1:
			double_sided = true
		for n in ["albedo_color", "base_color", "color", "tint_color", "overlay_color"]:
			var v = sh.get_shader_param(n)
			if v is Color and v.a > 0.05:
				color = v
				src_alpha = v.a
				break
		for n in ["albedo_texture", "base_texture", "texture", "albedo", "albedo_map"]:
			var t = sh.get_shader_param(n)
			if t is Texture:
				tex = t
				break

	var ov := _override_color(name_hint)
	if ov.a > 0.0:
		color = ov
		tex = null
	elif emissive_glow > 0.0:
		# Tinte emisivo del bake (barandas, vidrio): no promediar la textura.
		tex = null

	if tex != null:
		var base: Color = color if color.a > 0.05 else Color(1, 1, 1, 1)
		color = base * _representative_color(tex)

	if color.a <= 0.0 or (color.r <= 0.02 and color.g <= 0.02 and color.b <= 0.02):
		color = _palette_color(name_hint)
	elif ov.a <= 0.0:
		# Sin luz, un albedo promedio suele quedar apagado: leve levantada.
		color = color.lightened(0.04)

	# Sin luz, un plano muy oscuro se pierde: piso de 0.14 por canal.
	color = Color(max(0.14, color.r), max(0.14, color.g), max(0.14, color.b), 1.0)
	# Emisivos: vidrios de criopods, holos, luces. No se sombrean (quedan "encendidos").
	var ht := name_hint.to_lower()
	var glow := 0.0
	if ht.find("glass") != -1 or ht.find("vidrio") != -1 or ht.find("cristal") != -1 \
			or ht.find("holo") != -1 or ht.find("display") != -1 or ht.find("screen") != -1 or ht.find("pantalla") != -1 \
			or ht.find("lamp") != -1 or ht.find("light") != -1 or ht.find("glow") != -1 or ht.find("emissive") != -1:
		glow = 1.0
	elif ht.find("ice") != -1 or ht.find("frost") != -1 or ht.find("hielo") != -1:
		glow = 0.4
	elif ht.find("hazard") != -1 or ht.find("warning") != -1:
		glow = 0.3
	# El glow por emision solo aplica si el jugador NO eligio color por override.
	if emissive_glow > 0.0 and ov.a <= 0.0:
		glow = max(glow, emissive_glow)
	# Regla por color: el bake del domo pinta el vidrio de los criopods con `mat_cyan`
	# y no siempre el material se llama "glass". Si el color es cyan/teal o muy
	# brillante y saturado, se enciende.
	if ov.a <= 0.0:
		var mx = max(color.r, max(color.g, color.b))
		var mn = min(color.r, min(color.g, color.b))
		if color.b > 0.55 and color.g > 0.45 and color.r < 0.5:
			glow = 1.0
		elif mx > 0.85 and (mx - mn) > 0.4:
			glow = max(glow, 0.5)
	if _flat_debug and not _flat_debug_seen.has(name_hint):
		_flat_debug_seen[name_hint] = true
		print("[FLATDBG] '", name_hint, "' -> ", color.to_html(), " glow=", glow)
	# Vidrio: en flat el material por defecto es opaco, asi que recupera su transparencia.
	# Solo si el jugador no forzo color por override (ese camino manda).
	var transparent := ov.a <= 0.0 and (ht.find("glass") != -1 or ht.find("vidrio") != -1 or ht.find("cristal") != -1)
	var out_alpha := 1.0
	if transparent:
		out_alpha = clamp(src_alpha, 0.2, 0.8) if src_alpha < 0.95 else 0.45
	var key := color.to_html() + "|" + str(glow) + "|" + str(tex.get_instance_id() if tex != null else 0) + "|" + str(double_sided) + "|" + str(out_alpha)
	if _flat_cache.has(key):
		return _flat_cache[key]
	var mat := ShaderMaterial.new()
	if transparent:
		mat.shader = FLAT_FAKE_TRANSPARENT_DOUBLE_SIDED_SHADER if double_sided else FLAT_FAKE_TRANSPARENT_SHADER
		mat.set_shader_param("alpha", out_alpha)
	else:
		if _flashlight_mode:
			mat.shader = FLAT_FAKE_FLASHLIGHT_DS_SHADER if double_sided else FLAT_FAKE_FLASHLIGHT_SHADER
			mat.set_shader_param("world_light", _world_light)
			mat.set_shader_param("glow_floor", _glow_floor)
			_flashlight_materials.append(mat)
		else:
			mat.shader = FLAT_FAKE_DOUBLE_SIDED_SHADER if double_sided else FLAT_FAKE_SHADER
	# El uniform es vec3: pasar un Color no lo setea (queda el default gris).
	mat.set_shader_param("albedo", Vector3(color.r, color.g, color.b))
	mat.set_shader_param("glow", glow)
	# Prototipo de "luces apagadas" en el perfil plano: los materiales unshaded
	# ignoran el ambiente del Environment, asi que bajar ambient_light_energy no
	# oscurece nada en el handheld. Esta palanca baja el ambiente DEL SHADER.
	# glow=1 (lamparas, vidrios) no se ve afectado: ese mix va despues.
	if _flat_ambient >= 0.0:
		# Ojo: bajar SOLO `ambient` no apaga nada. En FlatFake la luz sale del
		# headlight `ndl` y el ambient apenas levanta las zonas en sombra:
		#   shaded = albedo * (ambient + (1-ambient)*ndl) * ao * exposure
		# Lo que apaga de verdad es `exposure`, que multiplica todo. Se bajan los
		# dos a la vez para que la escena quede a oscuras de verdad.
		mat.set_shader_param("ambient", _flat_ambient)
		mat.set_shader_param("exposure", clamp(_flat_ambient * 3.0, 0.02, 0.88))
	_flat_cache[key] = mat
	return mat

func _low_tier_node(node: Node) -> void:
	if node is Light:
		# El shadow atlas y el pase de sombras son el mayor costo por frame en
		# el G31: sin sombras, la iluminacion queda por ambient + vertex.
		node.shadow_enabled = false
	elif node is GeometryInstance:
		node.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		var mesh: Mesh = null
		if node is MeshInstance:
			mesh = node.mesh
		elif node is MultiMeshInstance and node.multimesh != null:
			mesh = node.multimesh.mesh
		var src = null
		if mesh != null and mesh.get_surface_count() > 0:
			src = node.get_surface_material(0) if node is MeshInstance else null
			# Un MultiMeshInstance lleva su color en material_override, no en el
			# mesh: el mesh horneado de los criopods trae un gris casi blanco
			# (0.906) y el color de verdad esta en el override. Mirando solo el
			# mesh, los anillos de pisos superiores salian BLANCOS, sin su color.
			if src == null and node is MultiMeshInstance:
				src = node.material_override
			if src == null:
				src = mesh.surface_get_material(0)
		elif "material" in node:
			# CSG (CSGBox) y otros GeometryInstance con material propio: la pantalla
			# holografica de los terminales es un CSGBox, no un MeshInstance.
			src = node.get("material")
		var hint := _node_hint(node, mesh)
		var h := hint.to_lower()
		# Materiales transparentes por diseño (holo, sombra, humo/vapor/leak): el
		# aplanado los vuelve opacos — y en el modo 3 ademas suelta el material_override
		# y aplana por superficie — asi que conservan su ShaderMaterial. Solo se les
		# apaga la sombra (arriba).
		if _keeps_own_material(node, src):
			return
		# Los personajes quedan FUERA del modo plano. FlatFake es un headlight en espacio
		# de camara: aplana justo lo que tiene que leerse con volumen. Conservando su
		# material, _low_tier_material le pone flags_vertex_lighting y el pilot se ve
		# gouraud (con su naranja real) contra un mundo plano. Es una malla: no cambia el
		# costo del frame de forma medible.
		var is_character := h.find("pilot") != -1 or h.find("elias") != -1 \
			or h.find("character") != -1 or h.find("suit") != -1
		if is_character:
			# El material puede estar por instancia, no solo en el mesh compartido (el
			# barrido de abajo solo mira mesh.surface_get_material).
			if node is MeshInstance and mesh != null:
				for s in range(mesh.get_surface_count()):
					_low_tier_material(node.get_surface_material(s))
		elif _unshaded_mode == "1":
			node.material_override = _unshaded_shared_material()
		elif _unshaded_mode == "3":
			# Por SUPERFICIE: los meshes horneados mezclan categorias (pod, baranda,
			# piso) en un CombinedMesh con varios materiales; el color tiene que salir
			# del material de cada superficie, no del nombre del nodo.
			if node is MeshInstance and mesh != null:
				# El material_override le gana a TODO material por superficie: sin
				# soltarlo, lo que sigue es codigo muerto y el prop sigue dibujando
				# su material original (asi las rejillas de SteelGratePlatform seguian
				# transparentes, con su alpha scissor intacto). Se usa primero como
				# fuente de color y recien despues se suelta.
				var ov_src = node.material_override
				node.material_override = null
				for s in range(mesh.get_surface_count()):
					var ssrc = node.get_surface_material(s)
					if ssrc == null:
						ssrc = mesh.surface_get_material(s)
					if ssrc == null:
						ssrc = ov_src
					var shint := hint
					if ssrc != null:
						if "resource_path" in ssrc:
							shint += " " + str(ssrc.resource_path)
						if "resource_name" in ssrc:
							shint += " " + str(ssrc.resource_name)
					node.set_surface_material(s, _flat_material(ssrc, shint))
			elif node is MultiMeshInstance and mesh != null and mesh.get_surface_count() > 1:
				# Un MultiMeshInstance no tiene material por instancia: su unica palanca
				# es material_override, que pinta TODAS las superficies con el color de
				# la 0. Una lampara (cuerpo metalico + vidrio emisivo) salia entonces
				# entera del color del cuerpo — blanco sobre blanco, sin contraste.
				# Los materiales por superficie viven en el mesh, que es compartido, asi
				# que se duplica para no aplanarselo a las demas instancias. Solo cuando
				# hay mas de una superficie: el MultiMesh de una sola (criopods, markers)
				# ya sale bien por material_override y no paga la copia.
				_flatten_multimesh_surfaces(node, mesh, hint)
			else:
				node.material_override = _flat_material(src, hint)
		if mesh != null:
			for s in range(mesh.get_surface_count()):
				_low_tier_material(mesh.surface_get_material(s))
	var mat = node.get("material_override") if node is GeometryInstance else null
	_low_tier_material(mat)

# Mutacion en memoria de recursos compartidos: nunca ResourceSaver.
func _low_tier_material(mat) -> void:
	if mat == null or not (mat is SpatialMaterial):
		return
	for prop in ["normal_enabled", "rim_enabled", "clearcoat_enabled", "ao_enabled",
			"depth_enabled", "subsurf_scatter_enabled"]:
		if prop in mat:
			mat.set(prop, false)
	# LOW: fuera la transparencia/alpha-scissor (apaga el early-z y cuesta fillrate).
	if "flags_transparent" in mat:
		mat.set("flags_transparent", false)
	if "params_use_alpha_scissor" in mat:
		mat.set("params_use_alpha_scissor", false)
	if "flags_vertex_lighting" in mat:
		mat.set("flags_vertex_lighting", true)
	if _unshaded_mode == "2" and "flags_unshaded" in mat:
		mat.set("flags_unshaded", true)

# La opción de Opciones fuerza el gate en cualquier dispositivo.
func _user_forced_low_end() -> bool:
	var sm = get_node_or_null("/root/SettingsManager")
	return sm != null and "low_end_forced" in sm and bool(sm.get("low_end_forced"))

func _read_env_forced_low_tier() -> bool:
	return OS.get_environment(FORCE_LOW_TIER_ENV).to_lower() in ["1", "true", "yes", "on"]

func _sync_manual_lightmap(gated: bool) -> void:
	if gated and not _manual_lightmap_synced:
		OS.set_environment("ODISEA_MANUAL_LIGHTMAP", "1")
		_manual_lightmap_synced = true
	elif not gated and _manual_lightmap_synced:
		OS.set_environment("ODISEA_MANUAL_LIGHTMAP", "")
		_manual_lightmap_synced = false

func strip_environment(env: Environment) -> void:
	if env == null:
		return
	if not _env_keep_fog:
		env.fog_enabled = false
	if not _env_keep_glow:
		env.glow_enabled = false
	# SSAO/SSR son los dos pases full-screen mas caros del G31 (leen depth y corren a
	# media resolucion) y se colaban por el gate: Environment_RingHub y los
	# Interior* traen ssao_enabled = true.
	env.ssao_enabled = false
	env.ss_reflections_enabled = false
	env.dof_blur_far_enabled = false
	env.dof_blur_near_enabled = false
	env.adjustment_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
