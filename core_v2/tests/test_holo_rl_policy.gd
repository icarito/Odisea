extends GdUnitTestSuite

# Tests de la integración de la política RL en ProgrammerHoloNPC:
#  (a) el builder de obs13 produce 13 dims con rangos correctos ante estados conocidos,
#  (b) la selección de acción / la traza del NPC son deterministas,
#  (c) el NPC converge a un objetivo simple con la política activa,
#  (d) con el flag apagado el comportamiento hand-authored queda como fallback.
# La inferencia MLP contra golden ya la cubre core_v2/tests/test_anna_mlp_inference.gd.

const PolicyScript := preload("res://core_v2/agents/HoloPolicyController.gd")
const HoloNPCScene := preload("res://core_v2/actors/ProgrammerHoloNPC.tscn")
const ProgrammerHoloNPC := preload("res://core_v2/actors/ProgrammerHoloNPC.gd")
const WEIGHTS_PATH := "res://core_v2/agents/anna_ppo_noorbit_v1_weights.json"


func _new_controller():
	var c = PolicyScript.new()
	assert_bool(c.setup(WEIGHTS_PATH)).is_true()
	return c


func test_obs_builder_dim_and_ranges_known_state() -> void:
	var c = _new_controller()
	# 8 rayos: 20m (claro), 0m (colisión), 10m, y resto 20m.
	var rays := [20.0, 0.0, 10.0, 20.0, 20.0, 5.0, 20.0, 20.0]
	var obs: Array = c.build_observation(rays, 25.0, -PI / 2.0, Vector2(10.0, -5.0), 3.0)
	assert_int(obs.size()).is_equal(13)
	assert_float(obs[0]).is_equal_approx(1.0, 0.0001)    # 20 / 20
	assert_float(obs[1]).is_equal_approx(0.0, 0.0001)    # 0 / 20 (colisión pegada)
	assert_float(obs[2]).is_equal_approx(0.5, 0.0001)    # 10 / 20
	assert_float(obs[5]).is_equal_approx(0.25, 0.0001)   # 5 / 20
	assert_float(obs[8]).is_equal_approx(0.5, 0.0001)    # 25 / 50
	assert_float(obs[9]).is_equal_approx(-0.5, 0.0001)   # (-PI/2) / PI
	assert_float(obs[10]).is_equal_approx(0.5, 0.0001)   # 10 / 20
	assert_float(obs[11]).is_equal_approx(-0.25, 0.0001) # -5 / 20
	assert_float(obs[12]).is_equal_approx(3.0, 0.0001)   # altura cruda


func test_obs_builder_clamps_extremes() -> void:
	var c = _new_controller()
	var obs: Array = c.build_observation(
		[999.0, -5.0, 999.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		500.0, 4.0 * PI, Vector2(100.0, -100.0), -2.0)
	assert_int(obs.size()).is_equal(13)
	for i in range(12):
		assert_float(obs[i]).is_greater_equal(-1.0)
		assert_float(obs[i]).is_less_equal(1.0)
	assert_float(obs[0]).is_equal_approx(1.0, 0.0001)   # rayo clamp a 1
	assert_float(obs[1]).is_equal_approx(0.0, 0.0001)   # rayo clamp a 0
	assert_float(obs[8]).is_equal_approx(1.0, 0.0001)   # dist clamp a 1
	assert_float(obs[9]).is_equal_approx(1.0, 0.0001)   # ángulo clamp a 1
	assert_float(obs[10]).is_equal_approx(1.0, 0.0001)
	assert_float(obs[11]).is_equal_approx(-1.0, 0.0001)


func test_action_mapping_matches_env_contract() -> void:
	# Mapeo Discrete(8) espejo de AnnaInterface.apply_rl_action / anna_gym.py.
	assert_vector2(PolicyScript.action_to_local_move(0)).is_equal(Vector2(0.0, 0.0)) # SteerOnly
	assert_vector2(PolicyScript.action_to_local_move(1)).is_equal(Vector2(0.0, -1.0)) # Forward (-Z)
	assert_vector2(PolicyScript.action_to_local_move(2)).is_equal(Vector2(0.0, -1.0)) # SprintForward
	assert_vector2(PolicyScript.action_to_local_move(3)).is_equal(Vector2(0.0, -1.0)) # JumpForward (salto colapsado)
	assert_vector2(PolicyScript.action_to_local_move(4)).is_equal(Vector2(-1.0, 0.0)) # StrafeLeft
	assert_vector2(PolicyScript.action_to_local_move(5)).is_equal(Vector2(1.0, 0.0))  # StrafeRight
	assert_vector2(PolicyScript.action_to_local_move(6)).is_equal(Vector2(-1.0, 0.0)) # JumpStrafeLeft
	assert_vector2(PolicyScript.action_to_local_move(7)).is_equal(Vector2(1.0, 0.0))  # JumpStrafeRight
	assert_bool(PolicyScript.action_is_sprint(2)).is_true()
	for a in [0, 1, 3, 4, 5, 6, 7]:
		assert_bool(PolicyScript.action_is_sprint(a)).is_false()


func test_signed_angle_to_target_signs() -> void:
	# Facing yaw 0 -> forward = -basis.z = -Z. Objetivo al frente: ángulo 0.
	var facing := Basis(Vector3.UP, 0.0)
	assert_float(PolicyScript.signed_angle_to_target(facing, Vector3(0.0, 0.0, -5.0))).is_equal_approx(0.0, 0.0001)
	# Convención del env (AnnaInterface.get_rl_observation): con forward -Z, un objetivo
	# a la derecha (+X) da ángulo negativo (forward x to_target).y < 0.
	assert_float(PolicyScript.signed_angle_to_target(facing, Vector3(5.0, 0.0, 0.0))).is_less(0.0)
	assert_float(PolicyScript.signed_angle_to_target(facing, Vector3(-5.0, 0.0, 0.0))).is_greater(0.0)
	# Objetivo en el mismo punto: sin dirección -> 0.
	assert_float(PolicyScript.signed_angle_to_target(facing, Vector3.ZERO)).is_equal_approx(0.0, 0.0001)


func test_select_action_is_deterministic_for_same_obs() -> void:
	var c = _new_controller()
	var obs := [0.9, 0.2, 0.7, 0.1, 0.3, 0.6, 1.0, 0.0, 0.4, -0.3, 0.2, -0.6, 1.5]
	var first: int = c.select_action(obs)
	assert_int(first).is_greater_equal(0)
	assert_int(first).is_less_equal(7)
	for _i in range(25):
		assert_int(c.select_action(obs)).is_equal(first)


func test_npc_rl_is_off_by_default_and_opt_in() -> void:
	var root := Spatial.new()
	add_child(root)
	var npc := HoloNPCScene.instance()
	root.add_child(npc)
	# Default: flag apagado, sin carga de política -> hand-authored.
	assert_bool(npc.use_rl_policy).is_false()
	assert_bool(npc.is_rl_active()).is_false()
	npc.start_follow()
	assert_int(npc.get_behavior_mode()).is_equal(ProgrammerHoloNPC.BehaviorMode.FOLLOW)
	assert_bool(npc.is_rl_active()).is_false()
	# Opt-in explícito -> modo RL y política activa.
	npc.start_rl_follow()
	assert_int(npc.get_behavior_mode()).is_equal(ProgrammerHoloNPC.BehaviorMode.RL)
	assert_bool(npc.is_rl_active()).is_true()
	root.queue_free()


func test_npc_rl_guide_converges_to_point() -> void:
	var root := Spatial.new()
	add_child(root)
	var npc := HoloNPCScene.instance()
	root.add_child(npc)

	var target := Vector3(0.0, 0.0, 14.0)
	npc.start_rl_guide(target, 5.0)
	assert_bool(npc.is_rl_active()).is_true()

	var initial_dist: float = npc.global_transform.origin.distance_to(target)
	for _i in range(240):
		npc._physics_process(1.0 / 60.0)

	var final_dist: float = npc.global_transform.origin.distance_to(target)
	assert_bool(final_dist < initial_dist).is_true()
	assert_bool(final_dist < 1.5).is_true()

	root.queue_free()


func test_npc_rl_emits_arrived_on_guide_target() -> void:
	var root := Spatial.new()
	add_child(root)
	var npc := HoloNPCScene.instance()
	root.add_child(npc)

	var spy := SignalSpy.new()
	root.add_child(spy)
	npc.connect("arrived", spy, "on_arrived")

	npc.start_rl_guide(Vector3(0.0, 0.0, 12.0), 5.0)
	for _i in range(240):
		npc._physics_process(1.0 / 60.0)

	assert_int(spy.arrived_positions.size()).is_equal(1)
	root.queue_free()


func test_npc_rl_trace_is_reproducible() -> void:
	var trace_a := _run_rl_trace()
	var trace_b := _run_rl_trace()
	assert_int(trace_a.size()).is_greater(0)
	assert_int(trace_a.size()).is_equal(trace_b.size())
	for i in range(trace_a.size()):
		assert_float(trace_a[i]).is_equal_approx(trace_b[i], 0.0)


func _run_rl_trace() -> Array:
	var root := Spatial.new()
	add_child(root)
	var npc := HoloNPCScene.instance()
	root.add_child(npc)
	npc.start_rl_guide(Vector3(0.0, 0.0, 14.0), 5.0)

	var trace := []
	for _i in range(180):
		npc._physics_process(1.0 / 60.0)
		var p: Vector3 = npc.global_transform.origin
		trace.append(p.x)
		trace.append(p.y)
		trace.append(p.z)
	# Liberar de inmediato para que la segunda corrida vea el mismo árbol.
	root.free()
	return trace


class SignalSpy extends Node:
	var arrived_positions: Array = []

	func on_arrived(pos: Vector3) -> void:
		arrived_positions.append(pos)
