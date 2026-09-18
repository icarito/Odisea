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
# SOLO adapters verificados en device (§11.10): un adapter desconocido NO se
# gatea — nunca dejar caer un device por culpa de otro.
const KNOWN_CONSERVATIVE_ADAPTERS := ["mali-g31"]

# Test seam: fuerza el gate sin depender del adapter del runner headless.
export var force_gate := false

var _gated_active := false

# FD-299: en tier LOW la fisica corre a 30 Hz. Medido en el Anbernic: con ~18 ms de GDScript
# por tick, a 60 Hz cada frame arrastraba 8 ticks y el juego iba al 54% del tiempo real. El
# paso del jugador se deriva de Engine.iterations_per_second, asi que no hay camara lenta.
const LOW_TIER_PHYSICS_FPS := 30

func _ready() -> void:
	_detect_gate()
	sync_physics_rate()
	_sync_low_tier_env_hints()
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
	if node.is_in_group("lowend_skip"):
		# Cortes cosmeticos declarativos (FD-299 3b): la escena marca la decoracion
		# y el gate la libera. Nunca marcar subtrees con colision o gameplay.
		node.queue_free()
	if node is WorldEnvironment:
		var gated := is_low_tier()
		# El lightmap manual SOLO en adapters donde el camino nativo está roto
		# (Mali-G31 verificado): es un shader del camino GLES2 y en Adreno
		# GLES3 muestrea 0 → nivel negro. El force del usuario no lo activa.
		_sync_manual_lightmap(_gated_active)
		if gated:
			strip_environment(node.environment)
	elif is_low_tier():
		_low_tier_node(node)

# Tier LOW (FD-299 3b): decisiones una vez por nodo, sin monitores por frame.
func is_low_tier() -> bool:
	return _gated_active or force_gate or _user_forced_low_end()

func _low_tier_node(node: Node) -> void:
	if node is Light:
		# El shadow atlas y el pase de sombras son el mayor costo por frame en
		# el G31: sin sombras, la iluminacion queda por ambient + vertex.
		node.shadow_enabled = false
	elif node is GeometryInstance:
		node.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		if node is MeshInstance:
			var mesh: Mesh = node.mesh
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
	if "flags_vertex_lighting" in mat:
		mat.set("flags_vertex_lighting", true)

# La opción de Opciones fuerza el gate en cualquier dispositivo.
func _user_forced_low_end() -> bool:
	var sm = get_node_or_null("/root/SettingsManager")
	return sm != null and "low_end_forced" in sm and bool(sm.get("low_end_forced"))

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
