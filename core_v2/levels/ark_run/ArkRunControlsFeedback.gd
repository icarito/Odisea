extends Reference

# FD-324 F7 / FD-325 T4 — control de gameplay de los slots Suit OS + estado del HUD.
# Lee los holds reales de `player:thrusters` y `player:rope` (reubicables) o Shift/Q y E;
# empuja en dirección de cámara/WASD y apunta la cuerda con la mirada elevada.
# FD-325 T4: la presentación visual 3D/2D vive en ArkRunDiegeticJetV2 /
# ArkRunDiegeticRopeV2 (un solo jet y un solo tether). Este módulo sólo calcula el
# estado que el loop publica al HUD, sin pluma/marcador/tether duplicados.

const ThrusterScript = preload("res://core_v2/levels/ark_run/ArkRunThrusterInput.gd")
const RopeSwingScript = preload("res://core_v2/player/traversal/SpinRopeSwingV2.gd")
# Margen de tolerancia alrededor del anclaje: si el impacto de la traza cae dentro de
# este radio, el anclaje se considera libre (el propio anclaje/domo no lo tapa).
const LOS_MIN_CLEARANCE_M := 4.5

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
# Anclajes con línea de visión (sin domo/terraza/casco a medio camino) del último tick.
var _visible_anchors: Array = []

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
		var candidates: Array = visible_anchors(pilot)
		slice.rope_input.step(pilot, candidates, aim, rope_pressed, dt, lt_pressed,
			_prev_rope_pressed, false, slice.rope_input.touch_toggle_mode)
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

# Anclajes con línea de visión real desde el ojo de la cámara: descarta los que quedan
# detrás de un domo/terraza/casco a más de LOS_MIN_CLEARANCE_M del anclaje. Sin mundo
# físico (headless sin colisión) devuelve la lista de comodidad intacta.
func visible_anchors(pilot) -> Array:
	var candidates: Array = _comfort_anchors(pilot)
	var space: PhysicsDirectSpaceState = null
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var world: World = tree.root.get_world()
		if world != null:
			space = world.direct_space_state
	if space == null:
		_visible_anchors = candidates
		return candidates
	var eye: Vector3 = camera_origin(pilot)
	var kept: Array = []
	for anchor in candidates:
		var point: Vector3 = anchor.origin if typeof(anchor) == TYPE_TRANSFORM else anchor
		if has_line_of_sight(space, eye, point, pilot):
			kept.append(anchor)
	_visible_anchors = kept if not kept.empty() else candidates
	return kept

# Traza cámara→anclaje excluyendo al pilot y todo lo que cuelga de él (su capsula y
# rig). Si el impacto cae a menos de LOS_MIN_CLEARANCE_M del anclaje, el anclaje está
# tapado por una estructura y se rechaza.
func has_line_of_sight(space: PhysicsDirectSpaceState, eye: Vector3, point: Vector3, pilot) -> bool:
	if space == null:
		return true
	var delta: Vector3 = point - eye
	if delta.length_squared() <= 0.000001:
		return true
	var exclude: Array = []
	if pilot != null and is_instance_valid(pilot):
		exclude.append(pilot)
		for child in pilot.get_children():
			if child is CollisionObject:
				exclude.append(child)
	# hit_from_inside=true (un rayo cuyo origen está DENTRO de una placa/casco devuelve
	# vacío si se apaga; el guard de proximidad al ojo descarta esa geometría contenedora).
	# collide_with_areas=false: las Areas (InteractArea) no son obstáculos visuales.
	var hit: Dictionary = space.intersect_ray(eye, point, exclude, 0x7FFFFFFF, true, false)
	if hit.empty():
		return true
	var hit_pos: Vector3 = hit.get("position", point)
	# Un impacto pegado al ojo o pegado al anclaje no tapa la vista.
	if hit_pos.distance_to(eye) <= LOS_MIN_CLEARANCE_M:
		return true
	return hit_pos.distance_to(point) <= LOS_MIN_CLEARANCE_M

# Estado publicado al HUD: anclaje real cuando hay cuerda; anclaje visible listo si no.
func _refresh_rope_state(pilot, pos: Vector3) -> void:
	if slice.rope_input != null and slice.rope_input.is_attached():
		var rope = slice.rope_input.get_rope()
		var anchor: Vector3 = rope.get_anchor() if rope != null else pos
		rope_state = "REELING" if rope_reeling else "ATTACHED"
		rope_distance = pos.distance_to(anchor)
		return
	var candidates: Array = visible_anchors(pilot)
	var best: Dictionary = RopeSwingScript.select_best_anchor(
		pos, aim_dir(pilot), candidates, _float_prop(slice.rope_input, "max_range", 55.0),
		_float_prop(slice.rope_input, "cone_deg", 24.0))
	rope_state = "READY" if bool(best.get("hit", false)) else "IDLE"
	rope_distance = float(best.get("distance", 0.0)) if bool(best.get("hit", false)) else 0.0

# Prefiere anclajes que no obliguen a mirar muy arriba (<=30 m sobre el pilot).
# La altura se mide sobre el `sim_up` del pilot (el eje Y global es tangencial en las
# paredes del cilindro y dejaba pasar anclajes "bajos" que están 30 m arriba).
func _comfort_anchors(pilot) -> Array:
	var origin: Vector3 = pilot.global_transform.origin
	var sim_up: Vector3 = pilot.get_sim_up() if pilot.has_method("get_sim_up") else Vector3.UP
	sim_up = sim_up.normalized() if sim_up.length_squared() > 0.000001 else Vector3.UP
	var filtered: Array = []
	for anchor in wiring.anchors:
		var point: Vector3 = anchor.origin if typeof(anchor) == TYPE_TRANSFORM else anchor
		if (point - origin).dot(sim_up) <= 30.0:
			filtered.append(anchor)
	return filtered if not filtered.empty() else wiring.anchors

func _float_prop(obj, property_name: String, default_value: float) -> float:
	if obj == null or not (property_name in obj):
		return default_value
	return float(obj.get(property_name))

