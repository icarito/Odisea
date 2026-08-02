tool
extends Spatial
class_name FireSystem

# FD-051: la amenaza ascendente del domo.
#
# CAPA LÓGICA. El estado que importa es un solo float (`fire_height`). La muerte se decide
# comparando la Y de los cuerpos del grupo `fire_vulnerable` contra ese float. Cero
# partículas involucradas: si se apagara todo el render, la amenaza sería idéntica.
#
# El visual (FireVisualBand) y la viñeta cabalgan sobre las señales de este nodo y nunca
# le escriben de vuelta.

signal fire_height_changed(height)
# dps ya viene multiplicado por core_damage_multiplier si el cuerpo está bajo la línea.
signal heat_contact(body, dps, in_core)
signal fire_started()

const GROUP_VULNERABLE := "fire_vulnerable"
const GROUP_DESTRUCTIBLE := "fire_destructible"
const GROUP_SELF := "fire_system"

# m/s de subida inicial (calibrar vs ~30s de escalada).
export(float) var base_speed := 0.15
# m/s^2 de aceleración (0 = velocidad constante).
export(float) var accel := 0.0
# Y inicial de la línea de fuego.
export(float) var start_height := 0.0
# Techo opcional de la subida. Menor o igual a start_height = sin techo.
export(float) var max_height := 0.0
# m sobre la línea donde ya hay daño de calor.
export(float) var heat_band := 2.0
# Holgura extra de la zona de calor.
export(float) var fire_contact_margin := 0.5
# Drenaje de integridad por segundo en zona de calor.
export(float) var damage_per_second := 25.0
# Multiplicador de drenaje bajo la línea real del fuego.
export(float) var core_damage_multiplier := 4.0
# Arranca subiendo solo, o espera un start() explícito.
export(bool) var auto_start := true
# Dibuja el plano de debug a la altura exacta donde empieza el daño. Usa un shader de
# ruido animado (no un disco rojo plano), así que puede quedar SIEMPRE prendido sin
# desentonar con el flipbook: es la referencia fiel de dónde está fire_height de verdad.
export(bool) var debug_draw := true
# Radio del plano de debug (por defecto el del domo).
export(float) var debug_plane_radius := 30.0
# Imprime height/speed periódicamente por consola (calibración).
export(bool) var debug_readout := false

var fire_height := 0.0
var fire_speed := 0.0
var elapsed := 0.0
var is_running := false

var _debug_plane: MeshInstance = null
var _debug_band: MeshInstance = null
var _readout_timer := 0.0

func _init() -> void:
	add_to_group("replay_sync")

func _ready() -> void:
	add_to_group(GROUP_SELF)
	fire_height = start_height
	fire_speed = base_speed
	elapsed = 0.0
	_ensure_debug_nodes()
	_update_debug_visuals()
	if Engine.editor_hint:
		return
	if auto_start:
		start()

func start() -> void:
	if is_running:
		return
	is_running = true
	emit_signal("fire_started")

func stop() -> void:
	is_running = false

func reset() -> void:
	fire_height = start_height
	fire_speed = base_speed
	elapsed = 0.0
	is_running = auto_start
	emit_signal("fire_height_changed", fire_height)
	_update_debug_visuals()

# Altura del tope de la zona de calor: por encima de esto no hay daño alguno.
func get_heat_ceiling() -> float:
	return fire_height + heat_band + fire_contact_margin

# Margen de seguridad exigido entre un punto de respawn y la línea de fuego.
export(float) var respawn_safety_margin := 3.0

# FD-051: al morir, el respawn no debe reaparecer bajo o dentro de la zona de calor.
# Congela (nunca retrocede el avance ya ganado) fire_height por debajo de
# `respawn_y - respawn_safety_margin - heat_band - fire_contact_margin`, de forma que el
# punto de respawn quede fuera de la zona de calor. No es un reset a start_height: si el
# jugador murió muy arriba, el fuego sigue estando alto, solo se le da margen justo al
# checkpoint. Determinista: mismo respawn_y siempre da el mismo clamp.
func ensure_safe_for_respawn(respawn_y: float) -> void:
	var max_allowed: float = respawn_y - respawn_safety_margin - heat_band - fire_contact_margin
	if fire_height > max_allowed:
		fire_height = max_allowed
		emit_signal("fire_height_changed", fire_height)
		_update_debug_visuals()

# Consulta barata para props destructibles y lógica externa.
func is_point_burning(point: Vector3) -> bool:
	return point.y <= get_heat_ceiling()

func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		_update_debug_visuals()
		return
	if not is_running:
		return

	elapsed += delta
	fire_speed = base_speed + accel * elapsed
	fire_height += fire_speed * delta
	if max_height > start_height:
		fire_height = min(fire_height, max_height)

	emit_signal("fire_height_changed", fire_height)
	_scan_vulnerable_bodies(delta)
	_update_debug_visuals()

	if debug_readout:
		_readout_timer += delta
		if _readout_timer >= 1.0:
			_readout_timer = 0.0
			print("[FireSystem] height=%.2f speed=%.3f elapsed=%.1f" % [fire_height, fire_speed, elapsed])

func _scan_vulnerable_bodies(_delta: float) -> void:
	var ceiling := get_heat_ceiling()
	for body in get_tree().get_nodes_in_group(GROUP_VULNERABLE):
		if not is_instance_valid(body) or not (body is Spatial):
			continue
		var body_y: float = body.global_transform.origin.y
		if body_y > ceiling:
			continue
		var in_core: bool = body_y <= fire_height
		var dps := damage_per_second
		if in_core:
			dps *= core_damage_multiplier
		emit_signal("heat_contact", body, dps, in_core)

# --- DEBUG ---

const DEBUG_SHADER_PATH := "res://core_v2/systems/fire/shaders/fire_debug_plane.shader"

func _ensure_debug_nodes() -> void:
	_debug_plane = get_node_or_null("DebugPlane")
	if _debug_plane == null:
		_debug_plane = _make_debug_plane("DebugPlane", Color(1.0, 0.15, 0.05, 0.4), 0.08, 0.6)
	_debug_band = get_node_or_null("DebugHeatBand")
	if _debug_band == null:
		_debug_band = _make_debug_plane("DebugHeatBand", Color(1.0, 0.55, 0.1, 0.22), 0.04, 0.3)

# Ruido animado en vez de un disco de color plano: pensado para quedar SIEMPRE visible
# (referencia fiel de fire_height/heat_ceiling) sin desentonar con el flipbook real.
func _make_debug_plane(node_name: String, color: Color, alpha_min: float, alpha_max: float) -> MeshInstance:
	var instance := MeshInstance.new()
	instance.name = node_name
	var plane := PlaneMesh.new()
	plane.size = Vector2(debug_plane_radius * 2.0, debug_plane_radius * 2.0)
	instance.mesh = plane
	var material := ShaderMaterial.new()
	var shader = load(DEBUG_SHADER_PATH)
	if shader:
		material.shader = shader
		material.set_shader_param("base_color", color)
		material.set_shader_param("alpha_min", alpha_min)
		material.set_shader_param("alpha_max", alpha_max)
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
			t.origin = Vector3(0.0, to_local(Vector3(0.0, fire_height, 0.0)).y, 0.0)
			_debug_plane.transform = t
	if is_instance_valid(_debug_band):
		_debug_band.visible = debug_draw
		if debug_draw:
			var tb := _debug_band.transform
			tb.origin = Vector3(0.0, to_local(Vector3(0.0, get_heat_ceiling(), 0.0)).y, 0.0)
			_debug_band.transform = tb

# --- REPLAY ---

func get_snapshot() -> Dictionary:
	return {
		"fire_height": fire_height,
		"fire_speed": fire_speed,
		"elapsed": elapsed,
		"is_running": is_running
	}

func restore_snapshot(data: Dictionary) -> void:
	fire_height = float(data.get("fire_height", start_height))
	fire_speed = float(data.get("fire_speed", base_speed))
	elapsed = float(data.get("elapsed", 0.0))
	is_running = bool(data.get("is_running", auto_start))
	emit_signal("fire_height_changed", fire_height)
	_update_debug_visuals()
