extends Spatial
class_name SpinRopeInputV2

# FD-324 F2 / FD-325 T1 — input de cuerda: RT en el mando (decisión #6) + tecla R.
# Invoca SpinRopeSwingV2: anclaje asistido por mirada y restricción determinista
# `constrain_swing`. Al soltar solo se libera la restricción: el momento del
# Pilot se conserva (nunca se escribe velocidad al enganchar ni al soltar).
#
# FD-325: `rope_grapple` (RT analógica/digital + E) es la acción oficial. Además del
# modo hold de mando/teclado, el touch usa `touch_toggle_mode`: un flanco engancha o
# suelta (soltar el dedo no suelta) y un salto (jump) suelta conservando el momento.

const RopeScript = preload("res://core_v2/player/traversal/SpinRopeSwingV2.gd")
const ROPE_KEY := KEY_E
const EPSILON := 1e-6

export(bool) var enabled := true
# FD-325 T2: el touch no puede "mantener" un gatillo con el dedo quieto sobre un boton
# mientras salta: ahi la cuerda es un toggle (tap engancha, tap o salto suelta). El
# mando (RT) y el teclado (E) siguen en modo hold.
export(bool) var touch_toggle_mode := false
export(float) var rt_threshold := 0.25
export(float) var max_range := 55.0
export(float) var cone_deg := 38.0

var _pilot: Node = null
var _anchors: Array = []
var _rope = null
var _aim_override := Vector3.ZERO
var _lifted := false
var _prev_trigger_pressed := false

func _ready() -> void:
	_ensure_rope()

func _physics_process(delta: float) -> void:
	if not enabled or _pilot == null or not is_instance_valid(_pilot):
		return
	var pressed: bool = is_trigger_pressed()
	step(_pilot, _anchors, _resolve_aim(), pressed, delta,
		false, _prev_trigger_pressed, _is_jump_pressed(), touch_toggle_mode)
	_prev_trigger_pressed = pressed

func set_pilot(pilot: Node) -> void:
	_pilot = pilot

func set_anchors(anchors: Array) -> void:
	_anchors = anchors.duplicate()

func set_aim_dir_override(aim_dir: Vector3) -> void:
	_aim_override = aim_dir

func clear_aim_dir_override() -> void:
	_aim_override = Vector3.ZERO

func get_rope():
	return _ensure_rope()

func is_attached() -> bool:
	return _ensure_rope().is_attached()

# Núcleo testable. Modo hold (default): `trigger_pressed` sostenido engancha y luego
# mantiene la restricción; al soltarlo se desengancha sin tocar el momentum.
# Modo toggle (`touch_toggle`): solo el flanco de subida engancha/suelta, soltar el dedo
# no suelta, y un `jump_pressed` (flanco) enganchado suelta conservando el momento.
func step(
	pilot, anchors: Array, aim_dir: Vector3, trigger_pressed: bool, dt: float,
	reel_pressed: bool = false, pressed_prev: bool = false, jump_pressed: bool = false,
	touch_toggle: bool = false
) -> Dictionary:
	var result := {
		"attached": false, "released": false, "taut": false, "reeling": false,
		"anchor": Vector3.ZERO, "length": 0.0
	}
	if pilot == null or not is_instance_valid(pilot):
		return result
	var rope = _ensure_rope()
	var position: Vector3 = pilot.global_transform.origin
	# Salto con la cuerda enganchada: suelta (el jugador salta y conserva el momento).
	if touch_toggle and jump_pressed and rope.is_attached():
		rope.detach()
		_lifted = false
		result["released"] = true
		return result
	# "intent": si la cuerda DEBE quedar enganchada este tick.
	#  - hold (default): mientras el gatillo está sostenido.
	#  - toggle (touch): solo el flanco de subida alterna (engancha si está libre, suelta si
	#    está enganchada); soltar el dedo no suelta ni re-engancha.
	var intent: bool = trigger_pressed
	if touch_toggle:
		if trigger_pressed and not pressed_prev:
			intent = not rope.is_attached()
		else:
			intent = rope.is_attached()
	if intent and not rope.is_attached():
		var best: Dictionary = RopeScript.select_best_anchor(
			position, aim_dir, anchors, max_range, cone_deg
		)
		if bool(best["hit"]):
			result["length"] = rope.attach(best["anchor_position"], position)
			result["attached"] = true
			result["anchor"] = best["anchor_position"]
	elif not intent and rope.is_attached():
		rope.detach()
		_lifted = false
		result["released"] = true
	if rope.is_attached():
		result["attached"] = true
		result["anchor"] = rope.get_anchor()
		result["length"] = rope.get_rope_length()
		if reel_pressed:
			var reeling: Dictionary = RopeScript.reel_in(
				position, _velocity_of(pilot), rope.get_anchor(), rope.get_rope_length(), dt)
			rope.set_rope_length(float(reeling["length"]))
			pilot.global_transform.origin = reeling["position"]
			if "velocity" in pilot:
				pilot.velocity = reeling["velocity"]
				if not _lifted:
					if pilot.has_method("get_sim_up"):
						pilot.velocity += pilot.get_sim_up().normalized() * 1.6
					var physics = pilot.get_spin_physics() if pilot.has_method("get_spin_physics") else null
					if physics != null:
						physics._was_grounded = false
					_lifted = true
			result["reeling"] = true
			result["taut"] = bool(reeling["taut"])
			result["length"] = rope.get_rope_length()
		else:
			var constrained: Dictionary = RopeScript.constrain_swing(
				position, _velocity_of(pilot), rope.get_anchor(), rope.get_rope_length()
			)
			result["taut"] = bool(constrained["taut"])
			if result["taut"]:
				pilot.global_transform.origin = constrained["position"]
				if "velocity" in pilot:
					pilot.velocity = constrained["velocity"]
			_lifted = false
	return result

# RT analógica (JOY_ANALOG_R2) o su botón digital, más la tecla de respaldo.
static func should_trigger(
	rt_axis: float, key_down: bool, threshold: float = 0.35
) -> bool:
	return key_down or rt_axis >= threshold

func read_hardware_trigger() -> float:
	var value: float = 0.0
	for device in Input.get_connected_joypads():
		value = max(value, Input.get_joy_axis(device, JOY_ANALOG_R2))
		if Input.is_joy_button_pressed(device, JOY_R2):
			value = 1.0
	return value

func is_trigger_pressed() -> bool:
	# FD-325: la acción oficial primero (misma que sintetiza el botón táctil CUERDA vía
	# Input.action_press). Después el fallback crudo: RT analógica/digital, E o clic derecho
	# con puntero capturado (tercera persona).
	if InputMap.has_action("rope_grapple") and Input.is_action_pressed("rope_grapple"):
		return true
	var mouse_right: bool = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED \
		and Input.is_mouse_button_pressed(BUTTON_RIGHT)
	return should_trigger(
		read_hardware_trigger(), Input.is_key_pressed(ROPE_KEY) or mouse_right, rt_threshold
	)

# Salto: misma acción que el resto del gameplay, para que el toggle del touch suelte la
# cuerda al saltar. `jump` es built-in del proyecto (jump/space).
func _is_jump_pressed() -> bool:
	return InputMap.has_action("jump") and Input.is_action_pressed("jump")

func _ensure_rope():
	if _rope == null or not is_instance_valid(_rope):
		_rope = RopeScript.new()
		_rope.name = "RopeSwing"
		add_child(_rope)
	return _rope

func _resolve_aim() -> Vector3:
	if _aim_override.length_squared() > EPSILON:
		return _aim_override.normalized()
	if _pilot == null or not is_instance_valid(_pilot):
		return Vector3.FORWARD
	var forward: Vector3 = -_pilot.global_transform.basis.z
	return forward.normalized() if forward.length_squared() > EPSILON else Vector3.FORWARD

func _velocity_of(pilot) -> Vector3:
	var value = pilot.get("velocity") if "velocity" in pilot else null
	return value if typeof(value) == TYPE_VECTOR3 else Vector3.ZERO
