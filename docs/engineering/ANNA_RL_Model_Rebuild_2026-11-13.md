# Rebuild del modelo RL de ANNA (2026-11-13)

Nota corta de la verificación/reentrenamiento del modelo de inferencia RL de ANNA
(`core_v2/agents/anna_ppo_noorbit_v1_weights.json`). El detalle operativo y el pipeline
reproducible viven en `agents/README.md` §"Rebuild del modelo ANNA".

## Hallazgo

El modelo exportado venía de `agents/models/anna_ppo_noorbit_lvl2_32k_fps120_v1.zip`:

- **32.768 timesteps** (`.meta.json`) — un smoke, no un entrenamiento real.
- Política casi uniforme (probs ≈ 0.15–0.19 sobre observación cero).
- **Dims obsoletas**: obs 12 / act 6, mientras el bridge RL actual
  (`core_v2/anna/AnnaInterface.gd`, `get_rl_observation` / `apply_rl_action`) usa
  `Box(13,)` / `Discrete(8)`.
- La escena de entrenamiento `core_v2/tests/TestScene_RL_2.tscn` fue eliminada en
  `6d44b6c3`; se evaluó/reentrenó sobre `TestScene_RL.tscn`.

Evaluación determinista (test sobre el bridge, 15 episodios, con shim 12/6 → 13/8): el
modelo de 32k obtiene una recompensa media **−232.9**, indistinguible de la política
**aleatoria (−231.7)**; 0 % de éxito y 15/15 `timeout`. No sirve.

`anna_candidate.zip` (13/8, 112.640 steps) sí aprendió: **+236.9** de recompensa media (40 eps).

## Reentrenamiento

Fine-tune con warm-start desde `anna_candidate.zip` sobre `TestScene_RL.tscn`
(seed 42, 2 envs, `n_steps=1024`, `batch=256`, 5 epochs, `lr=1e-4`, `ent=0.01`). EPPO desde
cero no converge en este entorno con presupuesto acotado (reward plano ≈ −302 a 131k steps),
así que el warm-start es la vía correcta.

Mejor checkpoint: **`agents/models/anna_ppo_noorbit_v2_137640.zip`** (112.640 + 25k fine-tune).

| Política | Steps | Reward medio | Éxito |
|---|---|---|---|
| aleatoria | — | −231.7 (15 eps) | 0 % |
| `anna_candidate.zip` | 112.640 | +236.9 (40 eps) | 0 % |
| `anna_ppo_noorbit_v2_137640.zip` | 137.640 | **+587.5 (40 eps)** | 0 % |

`success = 0` en todas: el objetivo queda a >2 m y los episodios terminan por `timeout`
(700 steps); la recompensa mide progreso.

## Export y validación

`agents/export_ppo_mlp.py --model agents/models/anna_ppo_noorbit_v2_137640.zip --name anna_ppo_noorbit_v1`
regeneró `anna_ppo_noorbit_v1_weights.json` (13→128→128→8, tanh) y el golden
`core_v2/tests/fixtures/anna_ppo_noorbit_v1_golden.json`.

- `core_v2/tests/test_anna_mlp_inference.gd`: metadata + golden + determinismo → **3/3 PASSED**.
- Cross-check independiente: el JSON reproduce el argmax de SB3 **200/200** observaciones
  (la capa `action_net(policy_net(obs))` coincide a ~1.6e-7; `get_distribution().logits` de
  SB3 difiere solo por el offset constante `−logsumexp`, que no cambia el argmax).

## Pendiente

- Puente `Discrete(8)` → `InputDataV2` / `PlayerControllerV2` para usar la política en partida
  real (hoy `apply_rl_action` es solo del bridge RL).
- Curriculum/escena con objetivo alcanzable para obtener `success > 0`.
