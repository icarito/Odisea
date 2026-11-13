extends Reference
# Sin class_name para no exigir reescritura de project.godot (mismo criterio que
# ProgrammerHoloNPC.gd). Se consume vía preload().
#
# HoloPolicyController — adapta la política PPO de ANNA (obs 13 -> MLP [128,128] tanh
# -> Discrete(8)) a la locomoción *cinemática* del holograma ProgrammerHoloNPC.
#
# Contrato de obs/acción (espejo de core_v2/anna/AnnaInterface.gd y anna_gym.py):
#   obs[0..7]  = 8 rayos normalizados clamp(d / SENSOR_RANGE, 0, 1); rayo i a
#                (360/8)*i grados en Y sobre el basis de la entidad, 0 = forward (-Z).
#   obs[8]     = clamp(dist_al_objetivo / 50.0, 0, 1)
#   obs[9]     = ángulo con signo al objetivo / PI  (rango -1..1)
#   obs[10]    = velocidad local x / RL_MAX_VELOCITY (clamp -1..1)
#   obs[11]    = velocidad local z / RL_MAX_VELOCITY (clamp -1..1)
#   obs[12]    = altura cruda (y) de la entidad
#
#   acción 0 = SteerOnly    (solo orientar)
#   acción 1 = Forward      (move.y = -1, -Z)
#   acción 2 = SprintForward
#   acción 3 = JumpForward
#   acción 4 = StrafeLeft   (move.x = -1)
#   acción 5 = StrafeRight  (move.x = +1)
#   acción 6 = JumpStrafeLeft
#   acción 7 = JumpStrafeRight
#
# El NPC es un holograma flotante sin física ni colisión: el componente "jump"
# se colapsa al horizontal (adelante / strafe) y se ignora. Ver
# docs/features/FD-HOLO_RL_POLICY.md.
#
# Determinismo: inferencia en floats de 64 bits y argmax con desempate por el menor
# índice. Sin randf, sin Tween, sin reloj de pared. La política de movimiento decide
# sólo locomoción; la orientación hacia el objetivo ("assisted steering") la aplica
# quien integra (el NPC), igual que hace el env RL del jugador.

const MLP_SCRIPT := preload("res://core_v2/agents/MLPPolicyInference.gd")
const DEFAULT_WEIGHTS_PATH := "res://core_v2/agents/anna_ppo_noorbit_v1_weights.json"

const RL_OBS_DIM := 13
const RL_SENSOR_RAY_COUNT := 8
const RL_SENSOR_RANGE := 20.0
const RL_MAX_VELOCITY := 20.0
const RL_DIST_NORM := 50.0

var _policy = null
var _obs_dim := 0
var _num_actions := 0
var _weights_path := ""


func setup(weights_path: String = DEFAULT_WEIGHTS_PATH) -> bool:
	var policy = MLP_SCRIPT.new()
	if not policy.load_from_json(weights_path):
		_policy = null
		_obs_dim = 0
		_num_actions = 0
		return false
	_policy = policy
	_weights_path = weights_path
	_obs_dim = policy.get_obs_dim()
	_num_actions = policy.get_num_actions()
	return _obs_dim == RL_OBS_DIM


func is_ready() -> bool:
	return _policy != null and _obs_dim == RL_OBS_DIM


func get_obs_dim() -> int:
	return _obs_dim


func get_num_actions() -> int:
	return _num_actions


func get_weights_path() -> String:
	return _weights_path


func predict_logits(obs: Array) -> Array:
	if _policy == null:
		return []
	return _policy.predict_logits(obs)


# Acción determinista: argmax de logits con desempate por el menor índice.
func select_action(obs: Array) -> int:
	if _policy == null:
		return 0
	var logits: Array = _policy.predict_logits(obs)
	if logits.empty():
		return 0
	var best := 0
	var best_val := float(logits[0])
	for i in range(1, logits.size()):
		var v := float(logits[i])
		if v > best_val:
			best_val = v
			best = i
	return best


# Constructor de obs puro y determinista (testeable sin escena).
# `ray_distances` son distancias crudas en metros; se normalizan aquí.
func build_observation(
		ray_distances: Array,
		dist_to_target: float,
		angle_to_target_rad: float,
		local_vel: Vector2,
		height: float,
		sensor_range: float = 20.0) -> Array:
	var obs := []
	obs.resize(RL_OBS_DIM)
	var norm_range: float = max(sensor_range, 0.001)
	for i in range(RL_SENSOR_RAY_COUNT):
		var d: float = norm_range
		if i < ray_distances.size():
			d = float(ray_distances[i])
		obs[i] = clamp(d / norm_range, 0.0, 1.0)
	obs[8] = clamp(dist_to_target / RL_DIST_NORM, 0.0, 1.0)
	obs[9] = clamp(angle_to_target_rad / PI, -1.0, 1.0)
	obs[10] = clamp(local_vel.x / RL_MAX_VELOCITY, -1.0, 1.0)
	obs[11] = clamp(local_vel.y / RL_MAX_VELOCITY, -1.0, 1.0)
	obs[12] = float(height)
	return obs


# Ángulo con signo (radianes, -PI..PI) del forward `-facing.z` hacia `to_target`.
# Espeja el cálculo de AnnaInterface.get_rl_observation (obs[9]).
static func signed_angle_to_target(facing: Basis, to_target: Vector3) -> float:
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	if flat.length_squared() < 0.000001:
		return 0.0
	flat = flat.normalized()
	var forward := -facing.z
	forward.y = 0.0
	if forward.length_squared() < 0.000001:
		return 0.0
	forward = forward.normalized()
	var angle: float = forward.angle_to(flat)
	if forward.cross(flat).y < 0.0:
		angle = -angle
	return angle


# Dirección horizontal local (x = strafe, y = forward; -Z es forward) para una acción.
static func action_to_local_move(action: int) -> Vector2:
	match action:
		1, 2, 3:
			return Vector2(0.0, -1.0)
		4, 6:
			return Vector2(-1.0, 0.0)
		5, 7:
			return Vector2(1.0, 0.0)
		_:
			return Vector2.ZERO


# ¿La acción pide sprint explícito? (2 = SprintForward)
static func action_is_sprint(action: int) -> bool:
	return action == 2
