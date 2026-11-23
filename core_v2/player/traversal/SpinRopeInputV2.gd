extends Spatial
class_name SpinRopeInputV2

# FD-324 F2 — input de cuerda: RT en el mando (decisión #6) + tecla R.
# Invoca SpinRopeSwingV2: anclaje asistido por mirada y restricción determinista
# `constrain_swing`. Al soltar solo se libera la restricción: el momento del
# Pilot se conserva (nunca se escribe velocidad al enganchar ni al soltar).

const RopeScript = preload("res://core_v2/player/traversal/SpinRopeSwingV2.gd")
const ROPE_KEY := KEY_E
const EPSILON := 1e-6

export(bool) var enabled := true
export(float) var rt_threshold := 0.35
export(float) var max_range := 55.0
export(float) var cone_deg := 38.0

var _pilot: Node = null
var _anchors: Array = []
var _rope = null
var _aim_override := Vector3.ZERO

func _ready() -> void:
	_ensure_rope()

func _physics_process(delta: float) -> void:
	if not enabled or _pilot == null or not is_instance_valid(_pilot):
		return
	step(_pilot, _anchors, _resolve_aim(), is_trigger_pressed(), delta)

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

# Núcleo testable: `trigger_pressed` sostenido engancha y luego mantiene la
# restricción; al soltarlo se desengancha sin tocar el momentum.
func step(
	pilot, anchors: Array, aim_dir: Vector3, trigger_pressed: bool, _dt: float
) -> Dictionary:
	var result := {
		"attached": false, "released": false, "taut": false,
		"anchor": Vector3.ZERO, "length": 0.0
	}
	if pilot == null or not is_instance_valid(pilot):
		return result
	var rope = _ensure_rope()
	var position: Vector3 = pilot.global_transform.origin
	if trigger_pressed:
		if not rope.is_attached():
			var best: Dictionary = RopeScript.select_best_anchor(
				position, aim_dir, anchors, max_range, cone_deg
			)
			if bool(best["hit"]):
				result["length"] = rope.attach(best["anchor_position"], position)
				result["attached"] = true
				result["anchor"] = best["anchor_position"]
		else:
			result["attached"] = true
			result["anchor"] = rope.get_anchor()
			result["length"] = rope.get_rope_length()
		if rope.is_attached():
			var constrained: Dictionary = RopeScript.constrain_swing(
				position, _velocity_of(pilot), rope.get_anchor(), rope.get_rope_length()
			)
			result["taut"] = bool(constrained["taut"])
			if result["taut"]:
				pilot.global_transform.origin = constrained["position"]
				if "velocity" in pilot:
					pilot.velocity = constrained["velocity"]
	elif rope.is_attached():
		rope.detach()
		result["released"] = true
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
	return should_trigger(
		read_hardware_trigger(), Input.is_key_pressed(ROPE_KEY), rt_threshold
	)

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
