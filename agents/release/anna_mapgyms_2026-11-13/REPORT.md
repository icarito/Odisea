# REPORT — anna_mapgyms_2026-11-13

Gyms RL adaptados al estilo de los mapas nuevos (RingHub y Bahía de Máquinas) +
política fine-tuneada para ambos, partiendo de `anna_candidate` con edición
quirúrgica de bias de acción.

## Qué se hizo

1. **Diagnóstico**: los checkpoints `agents/models/` (PPO SB3) no resolvían los
   mapas nuevos. Verificado que `godot3-server` de `~/.local/bin` es Godot 3.6.3
   **stock sin Box3D** — toda evaluación debe ir con el headless del fork v0.5.4
   (`~/.cache/odisea-godot/v0.5.4/godot.box3d.linux.x86_64.headless`).
2. **Gyms nuevos** (escenas nuevas en `core_v2/tests/`, sin editar los niveles):
   - `TestScene_RL_RingHubRing`: piso del domo + anillo central elevado
     (ScaffoldHubRing outer 13 / inner 6, deck y=4.5, como el RingFloor real) como
     obstáculo anular; pools sobre el piso alrededor (r 16..30).
   - `TestScene_RL_MachineBayCorridor`: corredor industrial 16x100 con
     bloques-estación alternados (z=8/28/48/68), como la bahía; spawn en la
     entrada (z -2..8), targets a lo largo del corredor (z 14..84).
   Ambos con el contrato standard: `AnnaBridge` + hook `anna_rl_choose_episode`
   (`RLSceneRandomizer`), Pilot + `RL_Target` (grupo `anna_target`), obs 13 /
   Discrete(8).
3. **Edición directa de pesos** (`agents/edit_ppo_action_bias.py`): prior de la
   action head del candidate — boost Forward/SprintForward (+0.8/+0.4), supresión
   idle (−0.3) y jump-strafe orbitantes (−0.6). Trunk 128x128 intacto.
   -> `anna_candidate_biasfix.zip`.
4. **Fine-tune** (`auto_train_anna.py --init-model`, 2 rounds x ~20k steps,
   warm-start del biasfix):
   - Bahía: `anna_bay_ft_v1_best.zip` — success_rate gate 0.6 -> **0.8**.
   - Ring (warm-start del bay best): `anna_ring_ft_v1_best.zip` — gate **1.0**.

## Evaluación (env externo `agents/eval_anna.py`, determinista, 5 eps, física 60 Hz)

| Modelo | RingHubRing | MachineBayCorridor |
|---|---|---|
| candidate original | — | 80% (timeout en 1/5) |
| **bay_ft_v1_best** | 100% (avg_len 341) | **100% (avg_len 602)** |
| **ring_ft_v1_best** | **100% (avg_len 327)** | 80% |

## Lección importante (régimen de física del eval)

Con `ANNA_RL_*_FPS` uncapped (0/4000) el mismo modelo da 0%: la dinámica por-step
cambia (steps de física muy chicos = desplazamiento por acción mínimo + timeout de
1100 steps = 0.28s de juego simulado). **Evaluar siempre a 60 Hz de física**
(default del gate de `auto_train_anna`) o al régimen del entrenamiento.

## Modelos

- `models/anna_candidate_biasfix.zip` — candidate con prior de acción editado.
- `models/anna_bay_ft_v1_best.zip` — fine-tune Bahía (gate 0.8).
- `models/anna_ring_ft_v1_best.zip` — fine-tune Ring (gate 1.0), alias current best.

Arquitectura: MLP 13 -> 128 -> 128 (tanh) -> Discrete(8). Obs: 8 rays + dist +
angle + vel_x + vel_z + height. Acciones: 0 idle, 1 forward, 2 sprint-forward,
3 jump-forward, 4 strafe-left, 5 strafe-right, 6 jump-strafe-left, 7
jump-strafe-right.

## Cómo re-evaluar

```bash
# 60 Hz (default del gate) con el binario del fork:
ANNA_RL_TARGET_FPS=60 ANNA_RL_PHYSICS_FPS=60 ANNA_RL_PHYSICS_FPS_CAP=60 \
ANNA_RL_MAX_PHYSICS_STEPS_PER_FRAME=8 \
GODOT_BIN=<fork-headless> .venv/bin/python agents/eval_anna.py \
  --model agents/release/anna_mapgyms_2026-11-13/models/anna_ring_ft_v1_best.zip \
  --scene core_v2/tests/TestScene_RL_RingHubRing.tscn --headless \
  --episodes 10 --max-steps 900 --port 5226
```

## Pendientes

- Validación en los niveles reales (RingHub_Level / MachineBay) cuando tengan
  zonas RL propias (spawn/target) — los gyms replican estilo/geometría con primitivas.
- Export MLPPolicyInference (GDScript) del ring_ft_v1_best cuando se quiera usar
  en juego sin torch (regenerar golden con `agents/export_ppo_mlp.py`).
