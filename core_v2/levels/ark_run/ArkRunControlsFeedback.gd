extends Reference

# FD-324 F7 / FD-325 T4 — control de gameplay de los slots Suit OS + estado del HUD.
# Lee los holds reales de `player:thrusters` y `player:rope` (reubicables) o Shift/Q y E;
# empuja en dirección de cámara/WASD y apunta la cuerda con la mirada elevada.
# FD-325 T4: la presentación visual 3D/2D vive en ArkRunDiegeticJetV2 /
# ArkRunDiegeticRopeV2 (un solo jet y un solo tether). Este módulo sólo calcula el
# estado que el loop publica al HUD, sin pluma/marcador/tether duplicados.

const ThrusterScript = preload("res://core_v2/levels/ark_run/ArkRunThrusterInput.gd")
const RopeSwingScript = preload("res://core_v2/player/traversal/SpinRopeSwingV2.gd")
const RopeLos = preload("res://core_v2/levels/ark_run/ArkRunRopeLos.gd")
# Distancia mínima del impacto del crosshair para considerarlo blanco (no el propio pie).
const CROSSHAIR_MIN_RANGE_M := 3.0
const EPSILON := 1e-6

var loop = null
var wiring = null
var slice = null
var thrusting := false
var rope_state := "IDLE"
var rope_distance := 0.0
var rope_reeling := false
var _t := 0.0
# Flanco del gatillo de cuerda para el toggle del touch (tap engancha / tap suelta).
var _prev_rope_pressed := false

func setup(loop_node, wiring_node) -> void:
	loop = loop_node
	wiring = wiring_node
	slice = wiring.slice if wiring != null else null

# Devuelve el tick de gameplay para que el loop aplique jet/tether con el mismo estado.
func tick(dt: float, pilot, physics, pos: Vector3) -> Dictionary:
	_t += dt
	var lt_pressed: bool = slice.thruster_input != null \
		and (slice.thruster_input.read_left_trigger() >= float(slice.thruster_input.deadzone) \
			or slice.thruster_input.read_keyboard_pressed())
	var rope_pressed: bool = slice.rope_input != null and slice.rope_input.is_trigger_pressed()
	# FD-325 polish: el `_physics_process` del rope input está apagado y el step real vive
	# aquí. El aim es el rayo central exacto de la cámara (igual que el crosshair) y los
	# anclajes pasan el filtro de línea de visión antes de elegir el más centrado.
	if slice.rope_input != null and pilot != null and is_instance_valid(pilot):
		var aim: Vector3 = aim_dir(pilot)
		var target: Dictionary = resolve_crosshair_target(pilot, aim)
		var candidates: Array = [target["position"]] if bool(target["hit"]) else []
		slice.rope_input.step(pilot, candidates, aim, rope_pressed, dt, lt_pressed,
			_prev_rope_pressed, _jump_pressed(), slice.rope_input.touch_toggle_mode)
	_prev_rope_pressed = rope_pressed
	var attached: bool = slice.rope_input != null and slice.rope_input.is_attached()
	rope_reeling = attached and rope_pressed and lt_pressed
	thrusting = lt_pressed and not attached and physics != null \
		and not bool(physics._was_grounded) and slice.explosion.launched
	var thrust_dir: Vector3 = thrust_direction(pilot)
	if thrusting:
		ThrusterScript.apply(physics, dt, thrust_dir, 1.0, true)
	_refresh_rope_state(pilot, pos)
	return {"thrusting": thrusting, "thrust_dir": thrust_dir, "reeling": rope_reeling,
		"attached": attached}

func thrust_direction(pilot) -> Vector3:
	var forward: Vector3 = _camera_forward(pilot)
	var move := Vector2.ZERO
	if pilot.input_provider != null and pilot.input_provider.last_input != null:
		move = pilot.input_provider.last_input.move_vec
	if move.length() < 0.05:
		return forward
	var right: Vector3 = forward.cross(Vector3.UP)
	right = right.normalized() if right.length_squared() > 0.000001 else Vector3.RIGHT
	var direction: Vector3 = right * move.x + forward * (-move.y)
	return direction.normalized() if direction.length_squared() > 0.000001 else forward

func _camera_forward(pilot) -> Vector3:
	var camera: Camera = null
	if loop != null and loop.get_viewport() != null:
		camera = loop.get_viewport().get_camera()
	if camera != null:
		var forward: Vector3 = -camera.global_transform.basis.z
		if forward.length_squared() > 0.000001:
			return forward.normalized()
	var fallback: Vector3 = -pilot.global_transform.basis.z
	return fallback.normalized() if fallback.length_squared() > 0.000001 else Vector3.FORWARD

# Aim de cuerda: el rayo CENTRAL exacto de la cámara (1:1 con el crosshair de pantalla).
# Sin elevación artificial: lo que el jugador apunta con el centro es lo que engancha.
func aim_dir(pilot) -> Vector3:
	var camera: Camera = null
	if loop != null and loop.get_viewport() != null:
		camera = loop.get_viewport().get_camera()
	if camera != null:
		var forward: Vector3 = -camera.global_transform.basis.z
		if forward.length_squared() > 0.000001:
			return forward.normalized()
	return _camera_forward(pilot)

func camera_origin(pilot) -> Vector3:
	var camera: Camera = null
	if loop != null and loop.get_viewport() != null:
		camera = loop.get_viewport().get_camera()
	if camera != null:
		return camera.global_transform.origin
	return pilot.global_transform.origin

# Blanco del crosshair (1:1 con láser/gloo). Rayo central desde la cámara hasta 180 m
# (bodies-only, excluyendo pilot e hijos): cualquier sólido a >=3 m es el blanco directo.
# Si va al vacío o no hay física (headless), fallback al mejor anclaje visible de
# wiring.anchors con línea de visión (cono 14° con física, 24° sin física).
func resolve_crosshair_target(pilot, aim: Vector3) -> Dictionary:
	var origin: Vector3 = pilot.global_transform.origin
	var max_range: float = _float_prop(slice.rope_input, "max_range", 180.0)
	var eye: Vector3 = camera_origin(pilot)
	var space: PhysicsDirectSpaceState = RopeLos.space_state()
	if space != null:
		var from: Vector3 = eye
		var to: Vector3 = eye + aim.normalized() * max_range
		var hit: Dictionary = space.intersect_ray(from, to, RopeLos.exclude_for(pilot), 0x7FFFFFFF, true, false)
		if not hit.empty():
			var point: Vector3 = hit.get("position", to)
			if point.distance_to(eye) >= CROSSHAIR_MIN_RANGE_M and point.distance_to(origin) > EPSILON:
				return {"hit": true, "position": point, "distance": origin.distance_to(point)}
		return _best_visible_anchor(pilot, aim, target_anchor_cone_deg(true))
	return _best_visible_anchor(pilot, aim, target_anchor_cone_deg(false))

func target_anchor_cone_deg(has_physics: bool) -> float:
	return 14.0 if has_physics else 24.0

func _best_visible_anchor(pilot, aim: Vector3, cone: float) -> Dictionary:
	var origin: Vector3 = pilot.global_transform.origin
	var anchors: Array = _visible_anchors_from(pilot)
	if anchors.empty():
		anchors = wiring.anchors
	var best: Dictionary = RopeSwingScript.select_best_anchor(
		origin, aim, anchors, _float_prop(slice.rope_input, "max_range", 180.0), cone)
	if bool(best.get("hit", false)):
		return {"hit": true, "position": best["anchor_position"],
			"distance": float(best["distance"])}
	return {"hit": false, "position": Vector3.ZERO, "distance": 0.0}

# Anclajes de wiring.anchors con línea de visión desde el ojo (sin domo/terraza/casco
# delante). Sin física devuelve la lista entera (headless).
func _visible_anchors_from(pilot) -> Array:
	var space: PhysicsDirectSpaceState = RopeLos.space_state()
	if space == null:
		return wiring.anchors.duplicate()
	var eye: Vector3 = camera_origin(pilot)
	var kept: Array = []
	for anchor in wiring.anchors:
		var point: Vector3 = anchor.origin if typeof(anchor) == TYPE_TRANSFORM else anchor
		if RopeLos.has_line_of_sight(space, eye, point, pilot):
			kept.append(anchor)
	return kept

# Delegado (compatibilidad con tests): línea de visión ojo→anclaje.
func has_line_of_sight(space: PhysicsDirectSpaceState, eye: Vector3, point: Vector3, pilot) -> bool:
	return RopeLos.has_line_of_sight(space, eye, point, pilot)

# Estado publicado al HUD: anclaje real cuando hay cuerda; blanco del crosshair si no.
func _refresh_rope_state(pilot, pos: Vector3) -> void:
	if slice.rope_input != null and slice.rope_input.is_attached():
		var rope = slice.rope_input.get_rope()
		var anchor: Vector3 = rope.get_anchor() if rope != null else pos
		rope_state = "REELING" if rope_reeling else "ATTACHED"
		rope_distance = pos.distance_to(anchor)
		return
	var target: Dictionary = resolve_crosshair_target(pilot, aim_dir(pilot))
	rope_state = "READY" if bool(target["hit"]) else "IDLE"
	rope_distance = float(target["distance"]) if bool(target["hit"]) else 0.0

func _jump_pressed() -> bool:
	return InputMap.has_action("jump") and Input.is_action_pressed("jump")

func _float_prop(obj, property_name: String, default_value: float) -> float:
	if obj == null or not (property_name in obj):
		return default_value
	return float(obj.get(property_name))

