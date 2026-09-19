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
# SOLO adapters verificados en device (§11.10): un adapter desconocido NO se
# gatea — nunca dejar caer un device por culpa de otro.
const KNOWN_CONSERVATIVE_ADAPTERS := ["mali-g31"]

# Test seam: fuerza el gate sin depender del adapter del runner headless.
export var force_gate := false

# Override de desarrollo (tools/launch_game.sh --lowend): fuerza el tier LOW en
# cualquier dispositivo sin tocar settings.cfg. Es la contraparte de runtime del
# override.cfg que el handheld arma desde portmaster/lowend.cfg.
const FORCE_LOW_TIER_ENV := "ODISEA_FORCE_LOW_TIER"

var _gated_active := false
var _env_forced_low_tier := false
# Los tools de horneado (tools/bake_*.gd) instancian la escena fuente y guardan
# los materiales recolectados. Si el gate corre en tier LOW, _low_tier_material
# muta esos recursos COMPARTIDOS en memoria y el bake los persiste sin
# transparencia ni alpha scissor: asi quedaron opacas las rejillas de los
# andamios al rehornear en 57ae5b2d. El bake pide esto antes de instanciar.
var _mutation_suspended := false

# FD-299: en tier LOW la fisica corre a 30 Hz. Medido en el Anbernic: con ~18 ms de GDScript
# por tick, a 60 Hz cada frame arrastraba 8 ticks y el juego iba al 54% del tiempo real. El
# paso del jugador se deriva de Engine.iterations_per_second, asi que no hay camara lenta.
const LOW_TIER_PHYSICS_FPS := 30

func _ready() -> void:
	_env_forced_low_tier = _read_env_forced_low_tier()
	_unshaded_mode = OS.get_environment("ODISEA_UNSHADED").strip_edges()
	_flat_debug = OS.get_environment("ODISEA_FLAT_DEBUG") in ["1", "true", "yes", "on"]
	if _unshaded_mode == "3":
		# El lightmap manual pisaria nuestros materiales por superficie.
		OS.set_environment("ODISEA_MANUAL_LIGHTMAP", "")
		_load_flat_overrides()
	_pilot_billboard = OS.get_environment("ODISEA_PILOT_BILLBOARD") in ["1", "true", "yes", "on"]
	if _pilot_billboard:
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
	var target: int = LOW_TIER_PHYSICS_FPS if is_low_tier() else int(ProjectSettings.get_setting("physics/common/physics_fps"))
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
func _process(_delta: float) -> void:
	if not _pilot_billboard:
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
func _load_flat_overrides() -> void:
	_flat_overrides.clear()
	var f := File.new()
	if f.open("user://flat_albedo.json", File.READ) != OK:
		print("[GLES3VendorGate] flat albedo: sin overrides (user://flat_albedo.json)")
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
	# Los materiales del bake marcan su categoria con emision (barandas, vidrio
	# `mat_cyan`, warning): si hay emision, se usa el tinte del albedo sin promediar
	# la textura (que lo apagaba a gris) y se los enciende con glow.
	var emissive_glow := -1.0
	if source is SpatialMaterial:
		var sm := source as SpatialMaterial
		double_sided = sm.params_cull_mode == SpatialMaterial.CULL_DISABLED
		color = sm.albedo_color
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
	var key := color.to_html() + "|" + str(glow) + "|" + str(tex.get_instance_id() if tex != null else 0) + "|" + str(double_sided)
	if _flat_cache.has(key):
		return _flat_cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = FLAT_FAKE_DOUBLE_SIDED_SHADER if double_sided else FLAT_FAKE_SHADER
	# El uniform es vec3: pasar un Color no lo setea (queda el default gris).
	mat.set_shader_param("albedo", Vector3(color.r, color.g, color.b))
	mat.set_shader_param("glow", glow)
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
			if src == null:
				src = mesh.surface_get_material(0)
		var hint := _node_hint(node, mesh)
		var h := hint.to_lower()
		var is_screen := h.find("holo") != -1 or h.find("display") != -1 or h.find("screen") != -1 or h.find("pantalla") != -1
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
			else:
				node.material_override = _flat_material(src, hint)
		elif is_screen:
			# Perfil LOW sin modo plano: holopantallas y similares opacas (la
			# transparencia apaga el early-z y cuesta fillrate).
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
	env.fog_enabled = false
	env.glow_enabled = false
	env.dof_blur_far_enabled = false
	env.dof_blur_near_enabled = false
	env.adjustment_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
