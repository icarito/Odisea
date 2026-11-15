extends CanvasLayer
class_name MultiToolCrosshair

# MultiToolCrosshair.gd - Retículo del multi-tool (feedback de Sebastián, 2026-11-14).
#
# El multi-tool dispara desde la mano (over-the-shoulder), así que el impacto real
# diverge del centro de pantalla por paralaje. Este retículo se ubica en el punto donde
# el tool va a impactar de verdad:
#   - Láser: MISMO rayo que MultiToolLaser (muzzle, -basis.z, laser_max_range y
#     laser_collision_mask), proyectado con camera.unproject_position.
#   - Gloo: predice el arco balístico (gloo_projectile_speed + gloo_projectile_gravity,
#     igual que MultiToolGlooProjectile) y marca el punto de aterrizaje.
# Feedback por estado sin texto (forma = tipo de tool, color = estado):
#   - valid (verde), fuera de rango (gris), obstruido (rojo), interactuable apuntado
#     (amarillo: gana el clic, coherente con C2).
#   - Pulso al disparar, brillo con el "calor" del láser mientras se sostiene, y un
#     núcleo que marca el cooldown del gloo.
# Se suaviza la posición (interpolación exponencial) para evitar jitter. En tier LOW se
# recalcula el target a mitad de frecuencia para no redibujar caro.
#
# Vive fuera de PlayerControllerV2: lo instancia el propio jugador como hijo (CanvasLayer)
# y se alimenta del estado del MultiToolV2 (grupo "multitool").

enum ReticleShape { NONE, LASER, GLOO }
enum State { IDLE, VALID, OUT_OF_RANGE, OBSTRUCTED, INTERACT }

const PAL := {
	"idle": Color(0.92, 0.94, 0.97, 0.75),
	"valid": Color(0.60, 0.95, 0.72, 0.95),
	"range": Color(0.72, 0.76, 0.84, 0.55),
	"obstructed": Color(0.92, 0.34, 0.34, 0.96),
	"interact": Color(0.95, 0.88, 0.48, 0.98),
}

# Factor de suavizado para 1 - exp(-k*dt) (independiente del frame rate).
const SMOOTH_K := 20.0
const PULSE_DECAY := 3.5
const HEAT_UP := 1.4
const HEAT_DOWN := 0.9
const HEAT_MAX := 1.0
const GLOO_SIM_HORIZON_SEC := 6.0
const GLOO_SIM_MAX_STEPS := 1500
const GLOO_SIM_BUDGET := 40
const GLOO_SIM_BUDGET_LOW := 20
# Reutiliza la MISMA integracion balistica del proyectil real para no duplicar (ni divergir
# de) la fisica del gloo.
const GlooProjectileScript = preload("res://core_v2/player/MultiToolGlooProjectile.gd")

var _root: Control
var _reticle: Control
var _laser_ui: Control
var _gloo_ui: Control
var _gloo_core: ColorRect
var _center_dot: ColorRect
var _obstruction_ring: Polygon2D
var _interact_tag: Control
var _ring_phase := 0.0
# Simulacion amortizada del arco del gloo (presupuesto por frame; se reinicia solo si el
# estado de disparo cambio lo suficiente). Evita 100+ consultas de fisica por frame.
var _gloo_sim_valid := false
var _gloo_sim_origin := Vector3.ZERO
var _gloo_sim_dir := Vector3.ZERO
var _gloo_sim_p := Vector3.ZERO
var _gloo_sim_vel := Vector3.ZERO
var _gloo_sim_step := 0
var _gloo_sim_total := 0
var _gloo_sim_dt := 0.0
var _gloo_sim_done := false
var _gloo_sim_hit: Dictionary = {}
var _shape: int = ReticleShape.NONE
var _state: int = State.IDLE
var _pulse := 0.0
var _heat := 0.0
var _was_firing := false
var _cooldown_ratio := 0.0
var _last_screen := Vector2(-10000.0, -10000.0)
var _last_world := Vector3.ZERO
var _has_target := false
var _low_tier := false
var _frame := 0
var _player = null
var _tool = null

func _ready() -> void:
	layer = 6
	_low_tier = _resolve_low_tier()
	_root = Control.new()
	_root.name = "AimRoot"
	_root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_reticle()
	set_process(true)

func _resolve_low_tier() -> bool:
	var gate = get_node_or_null("/root/GLES3VendorGate")
	return gate != null and gate.has_method("is_low_tier") and gate.is_low_tier()

# --- construcción (una sola vez) ----------------------------------------------

func _build_reticle() -> void:
	_reticle = Control.new()
	_reticle.name = "Reticle"
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_reticle)

	# Láser: cruz de 4 brazos (centrada en 0,0 local). GDScript 1.x: sin Vector4.
	_laser_ui = Control.new()
	_laser_ui.name = "Laser"
	var thick := 1.6
	var arm := 9.0
	var c := 0.0
	var arms := [
		[Vector2(c - thick * 0.5, c - arm - 4.0), Vector2(thick, arm)],
		[Vector2(c - thick * 0.5, c + 4.0), Vector2(thick, arm)],
		[Vector2(c - arm - 4.0, c - thick * 0.5), Vector2(arm, thick)],
		[Vector2(c + 4.0, c - thick * 0.5), Vector2(arm, thick)],
	]
	for piece in arms:
		var r := ColorRect.new()
		r.color = Color.white
		r.rect_position = piece[0]
		r.rect_size = piece[1]
		_laser_ui.add_child(r)
	# Punto central del láser (distingue el láser del gloo incluso en estados tenues).
	_center_dot = ColorRect.new()
	_center_dot.name = "CenterDot"
	_center_dot.color = Color.white
	_center_dot.rect_position = Vector2(-2.0, -2.0)
	_center_dot.rect_size = Vector2(4.0, 4.0)
	_laser_ui.add_child(_center_dot)
	_reticle.add_child(_laser_ui)

	# Anillo de obstrucción: aviso claro cuando el muzzle está bloqueado por algo cercano
	# que el centro de pantalla no ve (paralaje).
	_obstruction_ring = Polygon2D.new()
	_obstruction_ring.name = "ObstructionRing"
	_obstruction_ring.polygon = _make_circle_polygon(13.0, 24)
	_obstruction_ring.color = Color(1.0, 0.3, 0.3, 0.85)
	_obstruction_ring.visible = false
	_reticle.add_child(_obstruction_ring)

	# Gloo: rombo (contorno) + núcleo de cooldown.
	_gloo_ui = Control.new()
	_gloo_ui.name = "Gloo"
	var diamond := Polygon2D.new()
	diamond.name = "Diamond"
	diamond.polygon = PoolVector2Array([
		Vector2(0, -11), Vector2(8, 0), Vector2(0, 11), Vector2(-8, 0),
	])
	diamond.color = Color.white
	diamond.antialiased = true
	_gloo_ui.add_child(diamond)
	_gloo_core = ColorRect.new()
	_gloo_core.name = "Core"
	_gloo_core.color = Color.white
	_gloo_core.rect_position = Vector2(-3.0, -3.0)
	_gloo_core.rect_size = Vector2(6.0, 6.0)
	_gloo_ui.add_child(_gloo_core)
	_reticle.add_child(_gloo_ui)

	# Tag de interactuable apuntado (punto pequeño detrás del retículo).
	_interact_tag = Control.new()
	_interact_tag.name = "InteractTag"
	var tag_dot := ColorRect.new()
	tag_dot.color = Color.white
	tag_dot.rect_position = Vector2(-5.0, -5.0)
	tag_dot.rect_size = Vector2(10.0, 10.0)
	_interact_tag.add_child(tag_dot)
	_reticle.add_child(_interact_tag)

	_reticle.visible = false

# --- referencias --------------------------------------------------------------

func _resolve_refs() -> void:
	if not is_instance_valid(_tool):
		_tool = null
		var nodes = get_tree().get_nodes_in_group("multitool")
		if not nodes.empty() and is_instance_valid(nodes[0]):
			_tool = nodes[0]
	if not is_instance_valid(_player):
		_player = null
		var players = get_tree().get_nodes_in_group("player")
		if not players.empty() and is_instance_valid(players[0]):
			_player = players[0]

# --- main loop ----------------------------------------------------------------

func _process(delta: float) -> void:
	_frame += 1
	_ring_phase += delta * 6.0
	_resolve_refs()
	if not is_instance_valid(_tool):
		_set_hidden()
		return

	if _low_tier and _frame % 2 == 1:
		# En tier LOW recalcular el target a mitad de frecuencia; igual se suaviza.
		pass
	else:
		_refresh_target()

	var show := _should_show()
	_pulse = max(0.0, _pulse - PULSE_DECAY * delta)

	if show:
		var firing := Input.is_action_pressed("tool_fire_primary")
		if firing and not _was_firing:
			_pulse = 1.0
		if firing:
			_heat = min(HEAT_MAX, _heat + HEAT_UP * delta)
		else:
			_heat = max(0.0, _heat - HEAT_DOWN * delta)
		_was_firing = firing
		_refresh_cooldown()

	_apply_visual(delta)

func _set_hidden() -> void:
	_reticle.visible = false
	_has_target = false
	_last_screen = Vector2(-10000.0, -10000.0)

func _should_show() -> bool:
	if not is_instance_valid(_tool):
		return false
	if not _tool.has_method("get_equipped_name"):
		return false
	var name := String(_tool.get_equipped_name())
	if name != "LASER" and name != "GLOO":
		return false
	var suit = get_node_or_null("/root/SuitOS")
	if suit != null and suit.has_method("is_hud_mode_active") and suit.is_hud_mode_active():
		return false
	var tree = get_tree()
	if tree != null and tree.paused:
		return false
	return true

# --- target: mismo rayo que el disparo ----------------------------------------

func _space_state():
	if is_instance_valid(_player) and _player.has_method("get_world"):
		return _player.get_world().direct_space_state
	if is_instance_valid(_tool) and _tool.has_method("get_world"):
		return _tool.get_world().direct_space_state
	return null

# Solo CollisionObjects: el tool es un Spatial sin cuerpo, y un elemento invalido en el
# `exclude` de intersect_ray hace que la consulta falle.
func _exclude() -> Array:
	var arr := []
	if is_instance_valid(_player) and _player is CollisionObject:
		arr.append(_player)
	return arr

func _refresh_target() -> void:
	_has_target = false
	var space = _space_state()
	if space == null:
		return
	var cam = _camera()
	if cam == null:
		return

	var name := String(_tool.get_equipped_name())
	if name == "LASER":
		_refresh_laser_target(space, cam)
	elif name == "GLOO":
		_refresh_gloo_target(space, cam)

func _camera():
	var vp = get_viewport()
	if vp == null:
		return null
	return vp.get_camera()

func _refresh_laser_target(space, cam) -> void:
	var laser = _tool.get_node_or_null("Laser")
	if laser == null:
		return
	var from: Vector3 = laser.global_transform.origin
	var dir: Vector3 = -laser.global_transform.basis.z.normalized()
	var max_range: float = float(_tool.laser_max_range)
	var mask: int = int(_tool.laser_collision_mask)
	var hit = space.intersect_ray(from, from + dir * max_range, _exclude(), mask)
	var point: Vector3
	if hit.empty():
		point = from + dir * max_range
		_set_state(State.OUT_OF_RANGE)
	else:
		point = hit["position"]
		_eval_hit_state(hit, from, point, space, cam)
	_last_world = point
	_project_point(point, cam)

func _refresh_gloo_target(space, cam) -> void:
	var spawn = _tool.get_node_or_null("GlooSpawnPoint")
	if spawn == null:
		return
	var from: Vector3 = spawn.global_transform.origin
	var dir: Vector3 = -spawn.global_transform.basis.z.normalized()
	var speed: float = float(_tool.gloo_projectile_speed)
	var gravity: float = float(_tool.gloo_projectile_gravity)
	var mask: int = int(_tool.gloo_collision_mask)
	# Como el proyectil real: el RAYO se extiende por max(radio, collision_radius), pero el
	# CUERPO que barre move_and_collide usa el radio de vuelo (launch_radius).
	var ray_radius: float = max(float(_tool.gloo_launch_radius), float(_tool.gloo_collision_radius))
	var body_radius: float = max(0.01, float(_tool.gloo_launch_radius))
	# Se reinicia solo si el disparo cambio lo suficiente (la mano oscila unos mm por frame:
	# resetear siempre desperdiciaria la amortizacion).
	var changed: bool = not _gloo_sim_valid \
		or from.distance_to(_gloo_sim_origin) > 0.05 \
		or dir.dot(_gloo_sim_dir) < 0.999
	if changed:
		var fps: float = float(Engine.iterations_per_second)
		if fps <= 0.0:
			fps = 60.0
		var dt: float = 1.0 / fps
		var total: int = int(ceil(GLOO_SIM_HORIZON_SEC / dt))
		if total > GLOO_SIM_MAX_STEPS:
			# Se recorta el horizonte, NUNCA el dt: el paso debe seguir siendo el de la
			# fisica para no divergir de la trayectoria real del proyectil.
			total = GLOO_SIM_MAX_STEPS
		_gloo_sim_valid = true
		_gloo_sim_origin = from
		_gloo_sim_dir = dir
		_gloo_sim_p = from
		_gloo_sim_vel = dir * speed
		_gloo_sim_step = 0
		_gloo_sim_total = total
		_gloo_sim_dt = dt
		_gloo_sim_done = false
		_gloo_sim_hit = {}

	# Presupuesto por frame: se avanza un tramo por frame y se reutiliza el resultado si el
	# disparo no cambio (mitad en tier LOW).
	var budget: int = GLOO_SIM_BUDGET_LOW if _low_tier else GLOO_SIM_BUDGET
	var budget_end: int = min(_gloo_sim_step + budget, _gloo_sim_total)
	var exclude_rids := _exclude_rids()
	while not _gloo_sim_done and _gloo_sim_step < budget_end:
		var ball: Dictionary = GlooProjectileScript.step_ballistic(
			_gloo_sim_p, _gloo_sim_vel, gravity, _gloo_sim_dt, ray_radius)
		_gloo_sim_vel = ball["velocity"]
		var motion: Vector3 = ball["motion"]
		var ray_end: Vector3 = ball["ray_end"]
		# 1) Mismo rayo extendido que el proyectil evalua primero.
		var ray_hit = space.intersect_ray(_gloo_sim_p, ray_end, _exclude(), mask)
		if not ray_hit.empty():
			_gloo_sim_hit = {"collider": ray_hit.get("collider", null),
				"position": ray_hit["position"], "normal": ray_hit.get("normal", Vector3.UP)}
			_gloo_sim_done = true
			break
		# 2) Mismo barrido de esfera que move_and_collide (cast_motion + punto de contacto).
		var sweep: Dictionary = GlooProjectileScript.sweep_sphere(
			space, _gloo_sim_p, motion, body_radius, mask, exclude_rids)
		if not sweep.empty():
			_gloo_sim_hit = {"collider": sweep.get("collider", null),
				"position": sweep.get("point", _gloo_sim_p + motion),
				"normal": sweep.get("normal", Vector3.UP)}
			_gloo_sim_done = true
			break
		_gloo_sim_p = _gloo_sim_p + motion
		_gloo_sim_step += 1
	if _gloo_sim_step >= _gloo_sim_total:
		_gloo_sim_done = true

	if _gloo_sim_done and not _gloo_sim_hit.empty():
		_last_world = _gloo_sim_hit["position"]
		_eval_hit_state(_gloo_sim_hit, from, _gloo_sim_hit["position"], space, cam)
	else:
		_last_world = _gloo_sim_p
		_set_state(State.OUT_OF_RANGE)
	_project_point(_last_world, cam)


func _exclude_rids() -> Array:
	var arr: Array = []
	if is_instance_valid(_player) and _player is CollisionObject:
		arr.append((_player as CollisionObject).get_rid())
	return arr

# Un hit del rayo/arco del muzzle es "obstruido" si algo está muy cerca del arma, o si el
# punto de impacto se aleja de la línea del rayo de cámara (el centro de pantalla ve otra
# cosa). Si el collider pertenece al interactuable apuntado, gana el clic (C2) -> "interact".
func _eval_hit_state(hit: Dictionary, from: Vector3, point: Vector3, space, cam) -> void:
	var collider = hit.get("collider", null)
	if _hit_is_current_interactable(collider):
		_set_state(State.INTERACT)
		return
	var hit_dist: float = from.distance_to(point)
	var tool_name := String(_tool.get_equipped_name())
	# Algo pegado al arma: se marca aunque el centro también lo vea (pared en la cara).
	var near: float = 1.0 if tool_name == "LASER" else 0.9
	if hit_dist <= near:
		_set_state(State.OBSTRUCTED)
		return
	# Paralaje genuino: el centro de pantalla mira al vacío, pero el muzzle golpea algo
	# cercano (un obstáculo al costado de la mano que el centro no ve). Apuntar al piso o a
	# una caja no dispara esto porque el rayo de cámara sí golpea esa misma superficie.
	var center: Vector2 = get_viewport().size * 0.5
	var cam_from: Vector3 = cam.project_ray_origin(center)
	var cam_dir: Vector3 = cam.project_ray_normal(center).normalized()
	var cam_hit = space.intersect_ray(cam_from, cam_from + cam_dir * 80.0, _exclude(), int(_tool.laser_collision_mask))
	if cam_hit.empty() and hit_dist < 2.5:
		_set_state(State.OBSTRUCTED)
		return
	_set_state(State.VALID)

func _hit_is_current_interactable(collider) -> bool:
	if is_instance_valid(_player) and _player.has_method("_current_interactable") \
			and is_instance_valid(_player._current_interactable):
		var root = null
		if _player.has_method("_resolve_interactable_root"):
			root = _player._resolve_interactable_root(collider)
		if is_instance_valid(root) and (root == _player._current_interactable \
				or root.is_ancestor_of(_player._current_interactable)):
			return true
		var node = collider
		for _i in range(5):
			if not is_instance_valid(node):
				break
			if node == _player._current_interactable:
				return true
			node = node.get_parent()
	return false

func _project_point(world: Vector3, cam) -> void:
	var screen: Vector2 = cam.unproject_position(world)
	var cam_pos: Vector3 = cam.global_transform.origin
	var to_target: Vector3 = world - cam_pos
	var forward: Vector3 = -cam.global_transform.basis.z.normalized()
	# Detrás de la cámara (claro): ocultar. Con un punto muy cercano (pared pegada) se
	# mantiene visible y se sujeta al borde del viewport para que el aviso de obstrucción
	# siempre se note.
	if to_target.dot(forward) < -0.15:
		_has_target = false
		return
	var vp_size: Vector2 = get_viewport().size
	if screen.x < 0.0:
		screen.x = 0.0
	elif screen.x > vp_size.x:
		screen.x = vp_size.x
	if screen.y < 0.0:
		screen.y = 0.0
	elif screen.y > vp_size.y:
		screen.y = vp_size.y
	_has_target = true
	_last_screen = screen

func _set_state(s: int) -> void:
	_state = s

# --- visual -------------------------------------------------------------------

func _apply_visual(delta: float) -> void:
	var shape_name := String(_tool.get_equipped_name()) if is_instance_valid(_tool) else ""
	_shape = ReticleShape.LASER if shape_name == "LASER" else (ReticleShape.GLOO if shape_name == "GLOO" else ReticleShape.NONE)

	if _shape == ReticleShape.NONE or not _has_target or not _should_show():
		_reticle.visible = false
		return

	var target_screen: Vector2 = _last_screen
	if _last_screen.x < -5000.0:
		target_screen = get_viewport().size * 0.5
	# Suavizado exponencial de la posición (snap en el primer frame).
	var k := 1.0 - exp(-SMOOTH_K * delta)
	_last_screen = _last_screen.linear_interpolate(target_screen, k) if _last_screen.x >= -5000.0 else target_screen

	_reticle.visible = true
	# Posición local del contenedor: los hijos viven centrados en 0,0.
	_reticle.rect_position = _last_screen

	var col := _state_color()
	_laser_ui.visible = _shape == ReticleShape.LASER
	_gloo_ui.visible = _shape == ReticleShape.GLOO
	_interact_tag.visible = _state == State.INTERACT

	# Pulso de disparo: expansión leve.
	var scale := 1.0 + _pulse * 0.28
	_reticle.rect_scale = Vector2(scale, scale)

	# Calor del láser: el retículo se "calienta" mientras se sostiene el disparo.
	if _shape == ReticleShape.LASER:
		var hot := col.linear_interpolate(Color(1.0, 0.55, 0.25, col.a), clamp(_heat, 0.0, 1.0))
		_apply_color_recursive(_laser_ui, hot)
	else:
		_apply_color_recursive(_gloo_ui, col)
		# Cooldown del gloo: el núcleo se desvanece mientras recarga.
		if _gloo_core != null:
			_gloo_core.modulate.a = col.a * _cooldown_ratio
	if _interact_tag != null:
		_apply_color_recursive(_interact_tag, PAL["interact"])

	# Anillo de obstrucción: pulso rojo y más grande que la cruz (siempre visible en ese
	# estado, incluso con el punto pegado a la pared).
	if _obstruction_ring != null:
		var obstructed: bool = _state == State.OBSTRUCTED
		_obstruction_ring.visible = obstructed
		if obstructed:
			var pulse := 0.5 + 0.5 * sin(_ring_phase)
			_obstruction_ring.color.a = 0.55 + 0.4 * pulse
			var ring_scale := 1.0 + 0.12 * pulse
			_obstruction_ring.scale = Vector2(ring_scale, ring_scale)

func _state_color() -> Color:
	match _state:
		State.VALID: return PAL["valid"]
		State.OUT_OF_RANGE: return PAL["range"]
		State.OBSTRUCTED: return PAL["obstructed"]
		State.INTERACT: return PAL["interact"]
	return PAL["idle"]

func _apply_color_recursive(node: Node, col: Color) -> void:
	for child in node.get_children():
		if child is CanvasItem:
			child.modulate = col

func _make_circle_polygon(radius: float, segments: int) -> PoolVector2Array:
	var pts := PoolVector2Array()
	for i in range(segments):
		var ang := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(ang), sin(ang)) * radius)
	return pts

func _refresh_cooldown() -> void:
	var cooldown: float = float(_tool.get("_gloo_cooldown_left"))
	var total: float = float(_tool.gloo_fire_cooldown)
	_cooldown_ratio = clamp(1.0 - (cooldown / total if total > 0.0 else 0.0), 0.0, 1.0)

# API pública para tests: el punto de mundo que el retículo está marcando (igual al
# impacto real del rayo del tool).
func get_last_world_point() -> Vector3:
	return _last_world

func has_target() -> bool:
	return _has_target
