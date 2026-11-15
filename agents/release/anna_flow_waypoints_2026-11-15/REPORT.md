# REPORT — anna_flow_waypoints_2026-11-15

Pista F (Transit-Run): exposición de waypoints ordenados de la ruta principal desde
`FlowRouteValidator` como observación y recompensa en los gyms RL de `agents/`.

## Cambios

1. **Hook de lectura mínimo en `core_v2/systems/flow/FlowRouteValidator.gd`**:
   - `validate()` ahora incluye `"main_waypoints"` y `"side_socket_waypoints"`.
   - `extract_main_waypoints(graph, metrics)` y `extract_side_socket_waypoints(graph, metrics)`
     exponen los waypoints ordenados (`entry -> ... -> exit`) y los `CuratedSocket`
     opcionales de forma determinista y sin mutar generación.
2. **Entorno y shaping de waypoints en `agents/flow_waypoint_env.py`**:
   - `FlowWaypointTracker`: avanza monotónicamente por los waypoints de la ruta
     principal, recompensa progreso hacia el siguiente waypoint, penaliza retroceso
     (`backtracking`) y penaliza desvíos a `Side Sockets` mientras `main_route_exhausted == False`
     (permitiéndolos una vez agotada la ruta principal).
   - `FlowWaypointBifurcationEnv`: presets deterministas `ringhub_bifurcation` y
     `machinebay_bifurcation` compatibles con el contrato `obs13 / Discrete(8)`
     (`obs[8] = dist_to_wp / 50`, `obs[9] = angle_to_wp / PI`).
   - `FlowWaypointGymWrapper`: wrapper opcional para `AnnaGymEnv` en vivo.
   - `agents/eval_anna.py` y `agents/train_anna.py` aceptan `--env-preset` y `--waypoint-shaping`.

## Validación

- GdUnit3: `./runtest.sh -a ./core_v2/tests/test_flow_route_validator.gd -a ./core_v2/tests/test_flow_waypoints.gd` → 13/13 PASSED, 0 errors, 0 orphans.
- Pytest: `agents/test_flow_waypoints_gym.py` → 3/3 PASSED.
- Eval (`eval_anna.py`, determinista, 5 episodios):
  - `random` en `ringhub_bifurcation`: `success=0/5 (0%)`, `reward mean=+44.420`.
  - `anna_ring_ft_v1_best.zip` en `ringhub_bifurcation`: `success=5/5 (100%)`, `reward mean=+111.929`, `steps=247.0` (0 desvíos a Side Sockets, 0 retrocesos).
  - `anna_bay_ft_v1_best.zip` en `machinebay_bifurcation`: `success=5/5 (100%)`, `reward mean=+145.124`, `steps=346.0` (0 desvíos a Side Sockets, 0 retrocesos).
