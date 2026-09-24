extends GdUnitTestSuite

# Head-look durante la orbita pasiva (update_head_look_for_orbit):
#  - camara en el hemisferio FRONTAL: la cabeza mira a la POSICION de la camara.
#  - camara DETRAS: la cabeza congela la pose que tenia al pausar (no va a neutro).
#
# Convencion asumida (identica al comentario de _update_head_look): el modelo mira hacia
# +Z del pivot, asi que "camara adelante" = posicion de camara con Z > 0 en espacio del
# esqueleto y el test de hemisferio es aim.dot(fwd) > 0 con fwd = +Z.

const PilotAnimatorScript = preload("res://core_v2/actors/PilotAnimatorV2.gd")

var _gate_prev := {}


func before() -> void:
	# El head-look de orbita se apaga en tier LOW; neutralizamos el gate para que el test
	# mida la logica, no el hardware. Se restaura en after().
	var gate = get_node_or_null("/root/GLES3VendorGate")
	if gate:
		_gate_prev = {
			"force_gate": gate.force_gate,
			"gated": gate._gated_active,
			"env": gate._env_forced_low_tier,
		}
		gate.force_gate = false
		gate._gated_active = false
		gate._env_forced_low_tier = false


func after() -> void:
	var gate = get_node_or_null("/root/GLES3VendorGate")
	if gate and not _gate_prev.empty():
		gate.force_gate = _gate_prev["force_gate"]
		gate._gated_active = _gate_prev["gated"]
		gate._env_forced_low_tier = _gate_prev["env"]


func _make_animator() -> Array:
	var animator = PilotAnimatorScript.new()
	var skeleton := Skeleton.new()
	skeleton.name = "Skeleton"
	skeleton.add_bone("DEF-head")
	animator.add_child(skeleton)
	var camera := Camera.new()
	camera.name = "Camera"
	animator.add_child(camera)
	add_child(animator)
	camera.current = true
	animator._skeleton = skeleton
	return [animator, camera]


func test_orbit_head_look_tracks_camera_in_front() -> void:
	var parts: Array = _make_animator()
	var animator = parts[0]
	var camera: Camera = parts[1]
	# Camara delante y al costado (+X, +Z): yaw esperado 45 grados, dentro del clamp de 55.
	camera.transform.origin = Vector3(1.0, 0.0, 1.0)

	for i in range(80):
		animator.update_head_look_for_orbit(1.0 / 30.0)

	var look: Vector2 = animator.get_head_look()
	assert_float(look.x).is_equal_approx(deg2rad(45.0), 0.02)
	assert_float(look.y).is_equal_approx(0.0, 0.02)

	animator.free()


func test_orbit_head_look_freezes_pause_pose_with_camera_behind() -> void:
	var parts: Array = _make_animator()
	var animator = parts[0]
	var camera: Camera = parts[1]
	# Pose al momento de pausar; con la camara en -Z (detras) no debe cambiar.
	animator._head_look_yaw = 0.5
	animator._head_look_pitch = 0.2
	camera.transform.origin = Vector3(0.0, 0.0, -1.0)

	for i in range(80):
		animator.update_head_look_for_orbit(1.0 / 30.0)

	var look: Vector2 = animator.get_head_look()
	assert_float(look.x).is_equal_approx(0.5, 0.001)
	assert_float(look.y).is_equal_approx(0.2, 0.001)

	animator.free()


func test_normal_head_look_still_goes_neutral_with_camera_behind() -> void:
	# Regresion: el camino normal (no orbita) mantiene el neutro cuando la camara mira
	# hacia atras (aim.dot(fwd) <= 0), sin congelar ninguna pose.
	var parts: Array = _make_animator()
	var animator = parts[0]
	animator._head_look_yaw = 0.5
	animator._head_look_pitch = 0.2
	animator._last_anim_dt = 1.0 / 30.0

	for i in range(80):
		animator._update_head_look(false, false, 0.0)

	var look: Vector2 = animator.get_head_look()
	assert_float(look.x).is_equal_approx(0.0, 0.001)
	assert_float(look.y).is_equal_approx(0.0, 0.001)

	animator.free()


func test_orbit_head_look_has_no_jump_across_hemisphere() -> void:
	# Sin discontinuidad: dos posiciones de camara contiguas a cada lado del cruce de
	# hemisferio (dot ~ 0) deben dar poses de cabeza casi iguales. Se usa dt grande para
	# que el suavizado no enmascare el salto de target (la pose alcanza el target en 1 frame).
	var parts: Array = _make_animator()
	var animator = parts[0]
	var camera: Camera = parts[1]
	animator._head_look_yaw = 0.0
	animator._head_look_pitch = 0.0
	# Captura de la pose congelada con la camara detras.
	camera.transform.origin = Vector3(0.0, 0.0, -2.0)
	animator.update_head_look_for_orbit(100.0)

	var behind := Vector3(sin(deg2rad(90.5)), 0.0, cos(deg2rad(90.5))) * 2.0
	var front := Vector3(sin(deg2rad(89.5)), 0.0, cos(deg2rad(89.5))) * 2.0
	camera.transform.origin = behind
	animator.update_head_look_for_orbit(100.0)
	var look_behind: Vector2 = animator.get_head_look()
	camera.transform.origin = front
	animator.update_head_look_for_orbit(100.0)
	var look_front: Vector2 = animator.get_head_look()

	# Un gate duro saltaria de la pose congelada (~0) al clamp de yaw (~55 grados) en 1 frame.
	assert_float(abs(look_front.x - look_behind.x)).is_less(deg2rad(3.0))
	assert_float(abs(look_front.y - look_behind.y)).is_less(deg2rad(3.0))

	animator.free()


func test_orbit_head_look_pitch_respects_orbit_limit() -> void:
	# El pitch de orbita nunca supera ORBIT_HEAD_LOOK_PITCH_LIMIT_DEG, aunque la camara
	# quede muy por encima y el angulo crudo sea ~90 grados.
	var parts: Array = _make_animator()
	var animator = parts[0]
	var camera: Camera = parts[1]
	camera.transform.origin = Vector3(0.0, 2.0, 1.0)

	for i in range(200):
		animator.update_head_look_for_orbit(1.0 / 30.0)

	var look: Vector2 = animator.get_head_look()
	var orbit_pitch_limit: float = deg2rad(PilotAnimatorScript.ORBIT_HEAD_LOOK_PITCH_LIMIT_DEG)
	assert_float(abs(look.y)).is_less_equal(orbit_pitch_limit + 0.0001)
	# La camara esta bien al frente y arriba: el clamp debe quedar saturado, no a medias.
	assert_float(abs(look.y)).is_equal_approx(orbit_pitch_limit, 0.02)

	animator.free()


# --- Tier LOW (Anbernic): la orbita gira la cabeza, el gameplay sigue sin head-look ---

func _force_low_tier(active: bool) -> bool:
	var gate = get_node_or_null("/root/GLES3VendorGate")
	if gate == null:
		return false
	gate.force_gate = active
	return true


func test_orbit_head_look_runs_in_low_tier() -> void:
	# Aceptacion O19: con el gate en tier LOW, update_head_look_for_orbit NO sale temprano
	# y produce rotacion de cabeza igual que en el resto de los tiers.
	if not _force_low_tier(true):
		return
	var parts: Array = _make_animator()
	var animator = parts[0]
	var camera: Camera = parts[1]
	assert_bool(animator._is_hyper_low_runtime()).is_true()
	camera.transform.origin = Vector3(1.0, 0.0, 1.0)

	for i in range(80):
		animator.update_head_look_for_orbit(1.0 / 30.0)

	var look: Vector2 = animator.get_head_look()
	assert_float(look.x).is_equal_approx(deg2rad(45.0), 0.02)
	assert_float(look.y).is_equal_approx(0.0, 0.02)

	animator.free()
	_force_low_tier(false)


func test_gameplay_head_look_stays_suppressed_in_low_tier() -> void:
	# Aceptacion O19 (b): el camino NO-orbita sigue apagado en tier LOW. step_animator pasa
	# _is_hyper_low_runtime() como suppress_head_look; ese mismo valor debe dejar la cabeza
	# en neutro aunque la camara este al frente.
	if not _force_low_tier(true):
		return
	var parts: Array = _make_animator()
	var animator = parts[0]
	var camera: Camera = parts[1]
	camera.transform.origin = Vector3(1.0, 0.0, 1.0)
	animator._last_anim_dt = 1.0 / 30.0
	var suppress: bool = animator._is_hyper_low_runtime()
	assert_bool(suppress).is_true()

	for i in range(80):
		animator._update_head_look(suppress, false, 0.0)

	var look: Vector2 = animator.get_head_look()
	assert_float(look.x).is_equal_approx(0.0, 0.001)
	assert_float(look.y).is_equal_approx(0.0, 0.001)

	animator.free()
	_force_low_tier(false)


func test_orbit_head_look_freezes_idle_tree_in_low_tier() -> void:
	# Resolucion del desincronismo: en LOW el arbol corre en IDLE (pose por frame de render)
	# y el override se escribe en fisica. La orbita lo fuerza a MANUAL mientras el juego
	# esta pausado, asi que el override se escribe sobre una pose quieta.
	if not _force_low_tier(true):
		return
	var animator = PilotAnimatorScript.new()
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	animator.add_child(tree)
	animator.animation_tree = tree
	add_child(animator)
	tree.process_mode = AnimationTree.ANIMATION_PROCESS_IDLE

	get_tree().paused = true
	animator.update_head_look_for_orbit(1.0 / 30.0)
	var mode_while_paused: int = tree.process_mode
	get_tree().paused = false

	assert_int(mode_while_paused).is_equal(AnimationTree.ANIMATION_PROCESS_MANUAL)

	animator.free()
	_force_low_tier(false)

