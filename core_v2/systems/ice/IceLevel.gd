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

const GROUP_VULNERABLE := "ice_vulnerable"
const GROUP_SELF := "ice_level"

# m/s de subida inicial (calibrar vs ~30s de escalada).
export(float) var base_speed := 0.15
# m/s^2 de aceleración (0 = velocidad constante).
export(float) var accel := 0.0
# Y inicial de la línea de hielo.
export(float) var start_height := 0.0
# Techo opcional de la subida. Menor o igual a start_height = sin techo.
export(float) var max_height := 0.0
# Profundidad superficial que Elías puede pisar antes de recibir daño.
export(float) var walkable_surface_depth := 0.45
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
# Radio del plano de debug (por defecto el del domo).
export(float) var debug_plane_radius := 30.0
# Altura recorrida necesaria para que el material pase de hielo húmedo a escarcha opaca.
export(float, 0.0, 1.0) var initial_freeze_progress := 0.32
export(float) var visual_freeze_height := 10.0
# Imprime height/speed periódicamente por consola (calibración).
export(bool) var debug_readout := false

var ice_height := 0.0
var ice_speed := 0.0
var elapsed := 0.0
var is_running := false
# Último progreso de congelamiento aplicado al material (0 = hielo húmedo, 1 = escarcha
# opaca). Se expone porque el valor no se puede leer de vuelta del ShaderMaterial en
# headless: con el rasterizer dummy get_shader_param() devuelve null.
var visual_freeze_progress := 0.0

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
	_update_debug_visuals()
	_update_ice_collider()
	_update_ice_fog()

# Altura del tope de la zona de frío: por encima de esto no hay daño alguno.
func get_frost_ceiling() -> float:
	return ice_height - walkable_surface_depth

# Margen de seguridad exigido entre un punto de respawn y la línea de hielo.
export(float) var respawn_safety_margin := 3.0

# FD-051: al morir, el respawn no debe reaparecer bajo o dentro de la zona de frío.
# Congela (nunca retrocede el avance ya ganado) ice_height por debajo de
# `respawn_y - respawn_safety_margin - heat_band - fire_contact_margin`, de forma que el
# punto de respawn quede fuera de la zona de frío. No es un reset a start_height: si el
# jugador murió muy arriba, el hielo sigue estando alto, solo se le da margen justo al
# checkpoint. Determinista: mismo respawn_y siempre da el mismo clamp.
func ensure_safe_for_respawn(respawn_y: float) -> void:
	var max_allowed: float = respawn_y - respawn_safety_margin
	if ice_height > max_allowed:
		ice_height = max_allowed
		emit_signal("ice_height_changed", ice_height)
		_update_debug_visuals()

# Consulta barata para props destructibles y lógica externa.
func is_point_frozen(point: Vector3) -> bool:
	return point.y <= ice_height

func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		_update_debug_visuals()
		return
	if not is_running:
		return

	elapsed += delta
	ice_speed = base_speed + accel * elapsed
	ice_height += ice_speed * delta
	_update_ice_collider()
	_update_ice_fog()
	if is_instance_valid(_crack_player) and ice_height >= _next_crack_height:
		_crack_player.play()
		_next_crack_height += max(crack_interval, 0.1)
	if max_height > start_height:
		ice_height = min(ice_height, max_height)

	emit_signal("ice_height_changed", ice_height)
	_scan_vulnerable_bodies(delta)
	_update_debug_visuals()

	if debug_readout:
		_readout_timer += delta
		if _readout_timer >= 1.0:
			_readout_timer = 0.0
			print("[IceLevel] height=%.2f speed=%.3f elapsed=%.1f" % [ice_height, ice_speed, elapsed])

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

func _ensure_ice_collider() -> void:
	_ice_collider = get_node_or_null("IceCollider") as StaticBody
	if _ice_collider:
		return
	_ice_collider = StaticBody.new()
	_ice_collider.name = "IceCollider"
	_ice_collider.collision_layer = 1
	_ice_collider.collision_mask = 0
	var shape_node := CollisionShape.new()
	var shape := BoxShape.new()
	shape.extents = Vector3(debug_plane_radius, 0.1, debug_plane_radius)
	shape_node.shape = shape
	_ice_collider.add_child(shape_node)
	add_child(_ice_collider)

func _update_ice_collider() -> void:
	if is_instance_valid(_ice_collider):
		_ice_collider.global_transform.origin.y = ice_height - 0.1

func _update_ice_fog() -> void:
	if not is_instance_valid(_ice_environment):
		return
	_ice_environment.fog_height_enabled = true
	_ice_environment.fog_height_min = ice_height + 0.5
	_ice_environment.fog_height_max = ice_height - 3.0

# --- DEBUG ---

const DEBUG_SHADER_PATH := "res://core_v2/systems/ice/shaders/transparent_ice.shader"

func _ensure_debug_nodes() -> void:
	_debug_plane = get_node_or_null("IceSurface")
	if _debug_plane == null:
		_debug_plane = _make_debug_plane("IceSurface", Color(0.08, 0.42, 1.0, 0.82), 0.9)
	_debug_band = get_node_or_null("FrostCeiling")
	if _debug_band == null:
		_debug_band = _make_debug_plane("FrostCeiling", Color(0.55, 0.85, 1.0, 0.28), 0.35)

# Ruido animado en vez de un disco de color plano: pensado para quedar SIEMPRE visible
# (referencia fiel de ice_height/heat_ceiling) sin desentonar con el flipbook real.
func _make_debug_plane(node_name: String, color: Color, density: float) -> MeshInstance:
	var instance := MeshInstance.new()
	instance.name = node_name
	var plane := PlaneMesh.new()
	plane.size = Vector2(debug_plane_radius * 2.0, debug_plane_radius * 2.0)
	instance.mesh = plane
	var material := ShaderMaterial.new()
	var shader = load(DEBUG_SHADER_PATH)
	if shader:
		material.shader = shader
		material.set_shader_param("albedo", color)
		material.set_shader_param("opacity", density * 0.5)
	instance.material_override = material
	instance.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	if Engine.editor_hint and get_tree() and get_tree().edited_scene_root:
		instance.owner = get_tree().edited_scene_root
	return instance

func _update_debug_visuals() -> void:
	if is_instance_valid(_debug_plane):
		_debug_plane.visible = debug_draw
		if debug_draw:
			var t := _debug_plane.transform
			t.origin = Vector3(0.0, to_local(Vector3(0.0, ice_height, 0.0)).y, 0.0)
			_debug_plane.transform = t
			var freeze_distance: float = max(visual_freeze_height, 0.001)
			var rise_progress: float = clamp((ice_height - start_height) / freeze_distance, 0.0, 1.0)
			visual_freeze_progress = lerp(clamp(initial_freeze_progress, 0.0, 1.0), 1.0, rise_progress)
			var material: Material = _debug_plane.material_override
			if material is ShaderMaterial:
				material.set_shader_param("freeze_progress", visual_freeze_progress)
	if is_instance_valid(_debug_band):
		_debug_band.visible = debug_draw and draw_frost_ceiling
		if debug_draw and draw_frost_ceiling:
			var tb := _debug_band.transform
			tb.origin = Vector3(0.0, to_local(Vector3(0.0, get_frost_ceiling(), 0.0)).y, 0.0)
			_debug_band.transform = tb

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
	_update_debug_visuals()
