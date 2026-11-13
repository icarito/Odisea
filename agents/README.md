# Agents RL (A.N.N.A)

Esta carpeta contiene scripts reproducibles para entrenar y evaluar un agente RL
en `core_v2/tests/TestScene_RL.tscn`.

Escena alternativa más difícil:
- `core_v2/tests/TestScene_RL_2.tscn` (obstáculos/corredores/pilares)
- `core_v2/tests/TestScene_RL_3.tscn` (laberinto + vallas bajas para salto/corrección)
- `core_v2/tests/TestScene_RL_BaseTerrace.tscn` (wrapper RL que instancia `core_v2/levels/BaseTerrace.tscn` real)

## Requisitos

- Python 3
- `gymnasium`
- `stable-baselines3`
- Godot 3.6 (`godot3-bin`) o `GODOT_BIN` configurado

Ejemplo:

```bash
pip install gymnasium stable-baselines3
```

## Run recomendado (overnight)

Si quieres un run largo, ordenado por carpeta y con pre-check de FPS:

```bash
./agents/run_overnight_best.sh
```

Runbook operativo:

- `agents/RUNBOOK_OVERNIGHT.md`

Regla critica de rendimiento:

- No usar `ANNA_GODOT_MAX_FPS=0` con `godot3-server` (baja mucho los SPS).

## 1) Entrenar modelo

Headless (recomendado):

```bash
python3 agents/train_anna.py --timesteps 200000 --cpu-threads 4
```

Entrenar en nivel difícil:

```bash
python3 agents/train_anna.py --scene core_v2/tests/TestScene_RL_2.tscn --timesteps 200000 --cpu-threads 4
```

Curriculum (nivel 1 -> nivel 2):

```bash
python3 agents/train_anna_curriculum.py \
  --scene-stage1 core_v2/tests/TestScene_RL.tscn \
  --scene-stage2 core_v2/tests/TestScene_RL_2.tscn \
  --timesteps-stage1 16000 \
  --timesteps-stage2 16000 \
  --cpu-threads 6
```

Curriculum pedido (8k fácil + resto nivel 2):

```bash
python3 agents/train_anna_curriculum.py \
  --scene-stage1 core_v2/tests/TestScene_RL.tscn \
  --scene-stage2 core_v2/tests/TestScene_RL_2.tscn \
  --timesteps-stage1 8000 \
  --timesteps-stage2 16000 \
  --cpu-threads 6 \
  --model-out agents/models/anna_ppo_lvl1_8k_lvl2_16k_v1.zip
```

Curriculum de 3 niveles (incluye nivel 3):

```bash
python3 agents/train_anna_curriculum.py \
  --scene-stage1 core_v2/tests/TestScene_RL.tscn \
  --scene-stage2 core_v2/tests/TestScene_RL_2.tscn \
  --scene-stage3 core_v2/tests/TestScene_RL_BaseTerrace.tscn \
  --timesteps-stage1 8000 \
  --timesteps-stage2 8000 \
  --timesteps-stage3 8000 \
  --cpu-threads 6 \
  --model-out agents/models/anna_ppo_lvl1_lvl2_lvl3_24k_v1.zip
```

Con ventana (para observar):

```bash
python3 agents/train_anna.py --timesteps 50000 --render --cpu-threads 4
```

Entrenamiento grande en GPU CUDA (curriculum RL -> RL_2 -> BaseTerrace wrapper):

```bash
./agents/run_train_best_cuda.sh
```

No requiere `.venv` en servidor: si existe lo activa automáticamente; si no, usa el Python activo del sistema.

El script grande aplica por defecto el equivalente a:

```bash
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia python agents/train_anna_cuda_big.py
```

Puedes personalizar sin editar el script, por ejemplo:

```bash
CPU_THREADS=12 \
NUM_ENVS=8 \
CUDA_VISIBLE_DEVICES=0 \
STAGE1_STEPS=150000 \
STAGE2_STEPS=650000 \
STAGE3_STEPS=700000 \
MODEL_OUT=agents/models/anna_ppo_cuda_big_custom.zip \
./agents/run_train_best_cuda.sh
```

Preset robusto para Vast.ai (sin `.venv`, más tolerancia de arranque):

```bash
PYTHON_BIN=python \
CPU_THREADS=16 \
NUM_ENVS=8 \
ANNA_GODOT_PREFER_SERVER=1 \
ANNA_GODOT_SERVER_FALLBACK=1 \
ANNA_GODOT_READY_TIMEOUT_SEC=90 \
ANNA_CONNECT_MAX_RETRIES=90 \
./agents/run_train_best_cuda.sh
```

Antes de entrenar, `run_train_best_cuda.sh` corre un paso estilo GitHub Actions:
- import global de recursos (`godot -e --headless`)
- smoke de recursos críticos (`tests/ci_resource_smoke.gd`)
- retry automático de smoke una vez

Logs:
- `reports/import_resources_train.log`
- `reports/resource_smoke_train.log`
- `reports/resource_smoke_train_retry.log`

Control por env:
- `ANNA_PREIMPORT_BEFORE_TRAIN=0` desactiva el paso
- `ANNA_PREIMPORT_REQUIRED=0` permite continuar aunque falle
- `ANNA_IMPORT_FORCE_SOFTWARE=1` fuerza `LIBGL_ALWAYS_SOFTWARE=1` (default)
- `ANNA_PREIMPORT_DISABLE_EDITOR_PLUGINS=1` desactiva temporalmente plugins en el pass de import (default)
- `ANNA_IMPORT_GODOT_BIN=godot3` fija binario de import/smoke (si `GODOT_BIN=godot3-server`, el launcher ya evita usar server para preimport)
- `ANNA_SKIP_PY_PREWARM_AFTER_PREIMPORT=1` evita duplicar prewarm en Python (default)

Notas de throughput por defecto del launcher CUDA:
- `ANNA_RL_PHYSICS_FPS=0` (preset uncapped de `AnnaBridge`)
- `ODISEA_DISABLE_PERFMON_IN_RL=1` (evita overhead del monitor en entrenamiento)
- `ODISEA_DISABLE_FAKE_SHADOW=1` (desactiva blob/fake shadow del piloto en RL)
- `ODISEA_DISABLE_SHADER_WARMUP=1` (evita compilación de shader cache runtime en RL)
- `ANNA_RL_DISABLE_QODOT=1` (desactiva comportamiento de Qodot en wrapper RL BaseTerrace)
- `BATCH_SIZE=8192`
- `NUM_ENVS_STAGE3=2` por defecto para estabilizar `BaseTerrace` (stage3)
- `ANNA_CUDA_TF32=1`, `ANNA_CUDNN_BENCHMARK=1`, `ANNA_TORCH_MATMUL_PRECISION=high`

Script base (si prefieres invocarlo directo):

```bash
python3 agents/train_anna_cuda_big.py --device auto --model-out agents/models/anna_ppo_cuda_big.zip
```

Salida por defecto:

- Modelo: `agents/models/anna_ppo.zip`
- Metadata: `agents/models/anna_ppo.meta.json`

## 2) Evaluar / ver el agente

```bash
python3 agents/eval_anna.py --model agents/models/anna_ppo.zip --episodes 5 --render --cpu-threads 4
```

## 3) Arnés autónomo (train/eval hasta mejorar dirección)

Este script itera rondas `entrenar -> evaluar -> puntuar` y guarda:

- checkpoints por ronda: `agents/models/anna_auto_rN.zip`
- mejor modelo acumulado: `agents/models/anna_auto_best.zip`
- resumen completo: `agents/models/anna_auto_summary.json`

Ejemplo:

```bash
python3 agents/auto_train_anna.py \
  --cpu-threads 6 \
  --rounds 1 \
  --scene-stage1 core_v2/tests/TestScene_RL.tscn \
  --scene-stage2 core_v2/tests/TestScene_RL_2.tscn \
  --scene-stage3 core_v2/tests/TestScene_RL_BaseTerrace.tscn \
  --timesteps-stage1 8000 \
  --timesteps-stage2 16000 \
  --timesteps-stage3 8000 \
  --eval-episodes 6 \
  --eval-max-steps 800 \
  --success-target 0.5 \
  --direction-target 0.62 \
  --fast-success-target 0.45 \
  --wall-contact-max 0.18
```

## Limitar CPU (evitar sobrecalentamiento)

Ambos scripts aplican límite de hilos vía `--cpu-threads`:

- `OMP_NUM_THREADS`
- `MKL_NUM_THREADS`
- `OPENBLAS_NUM_THREADS`
- `NUMEXPR_NUM_THREADS`
- `torch.set_num_threads()`

Si quieres limitar aún más, en Linux puedes combinarlos con `taskset`.

## Export de política PPO a inferencia MLP en GDScript

Los checkpoints de `agents/models/` son PPO de Stable-Baselines3 (zip con `policy.pth`).
Para usarlos en el juego sin meter torch/onnxruntime en el export de Godot:

```bash
python agents/export_ppo_mlp.py \
  --model agents/models/anna_ppo_noorbit_v2_137640.zip \
  --name anna_ppo_noorbit_v1
```

Genera:

- `core_v2/agents/<name>_weights.json` — pesos de la política (MLP + tanh, solo resp, en float64).
- `core_v2/tests/fixtures/<name>_golden.json` — entradas fijas + logits esperados (golden para tests).

En GDScript: `core_v2/agents/MLPPolicyInference.gd` carga el JSON y expone
`predict_logits(obs: Array) -> Array` (determinista, sin dependencias externas).
Test de verificación: `core_v2/tests/test_anna_mlp_inference.gd`.

Modelos inspeccionados (2026-11-13):

| Modelo | Obs | Acción | Arquitectura política | Estado |
|---|---|---|---|---|
| `anna_ppo_noorbit_lvl2_32k_fps120_v1.zip` | Box(12,) ∈ [-1,1] | Discrete(6) | 12→64→64→6 (tanh) | **obsoleto** (32k smoke, dims viejas) |
| `anna_candidate.zip` | Box(13,) ∈ [-1,1] | Discrete(8) | 13→128→128→8 (tanh) | warm-start (112.640 steps) |
| `anna_ppo_noorbit_v2_137640.zip` | Box(13,) ∈ [-1,1] | Discrete(8) | 13→128→128→8 (tanh) | **exportado actualmente** |

## Rebuild del modelo ANNA (2026-11-13)

El modelo de inferencia exportado (`core_v2/agents/anna_ppo_noorbit_v1_weights.json`) estaba
desactualizado: venía de un smoke de 32k steps con dims viejas (obs 12 / act 6) que **no coinciden**
con el bridge RL actual (`AnnaInterface.get_rl_observation` → `Box(13,)`, `apply_rl_action` →
`Discrete(8)`), y la escena original `TestScene_RL_2.tscn` fue eliminada (commit `6d44b6c3`).

Pipeline actual (dev tooling: torch + SB3 en un venv aparte; nada de esto entra al export de Godot):

```bash
# 1) Evaluar el baseline aleatorio y el checkpoint de partida (40 episodios c/u)
python agents/eval_anna.py --model random --episodes 40
python agents/eval_anna.py --model agents/models/anna_candidate.zip --episodes 40

# 2) Fine-tune (warm-start) sobre TestScene_RL.tscn, 13 obs / 8 acciones
python agents/train_anna.py \
  --scene core_v2/tests/TestScene_RL.tscn \
  --init-from agents/models/anna_candidate.zip \
  --timesteps 150000 --num-envs 2 --seed 42 \
  --vec-env subproc --start-method fork \
  --net-arch 128 --n-steps 1024 --batch-size 256 --n-epochs 5 \
  --learning-rate 1e-4 --ent-coef 0.01 --checkpoint-freq 25000 \
  --model-out agents/models/anna_ppo_noorbit_v2_finetune.zip

# 3) Elegir el mejor checkpoint y exportar a GDScript
python agents/export_ppo_mlp.py \
  --model agents/models/anna_ppo_noorbit_v2_137640.zip --name anna_ppo_noorbit_v1
```

Métrica antes/después (recompensa media, eval determinista, mismo bridge; la varianza por episodio
es alta — usar ≥40 episodios para comparar):

| Política | Steps | Reward medio (40 eps) |
|---|---|---|
| aleatoria | — | −231.7 (15 eps) |
| `anna_candidate.zip` | 112.640 | +236.9 |
| `anna_ppo_noorbit_v2_137640.zip` | 137.640 (112.640 + 25k fine-tune) | **+587.5** |

Ninguna política llega al objetivo (`success = 0/40`): el objetivo de `TestScene_RL.tscn` queda a
>2 m y los episodios terminan por `timeout` (700 steps). La recompensa mide progreso/acercamiento,
que sí mejora de forma clara.

Notas de reproducibilidad:

- La escena randomiza spawn/objetivo por episodio; la eval es determinista en la **acción**
  (`predict(..., deterministic=True)`), no en la secuencia de episodios.
- El fine-tune arranca de `anna_candidate.zip` porque PPO desde cero no converge en este entorno
  con presupuesto acotado (probado a 131k steps: reward plano ≈ −302). El modelo original era un
  stage de curriculum (`noorbit_lvl2`); la escena `lvl2` ya no existe.

Pendiente:

- Mapeo `Discrete(8)` → `InputDataV2` / `PlayerControllerV2` en gameplay (hoy `apply_rl_action` vive
  en `AnnaInterface`; falta el puente de inferencia en partida real).
- Reentrenar/curriculum en una escena con objetivo alcanzable para obtener `success > 0`.

## Notas

- En modo RL (`ANNA_RL_MODE=1`) el mundo avanza en lock-step (un `STEP` -> un frame físico).
- Convención del proyecto: `-Z` es forward y `+Z` es back.
