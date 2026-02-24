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

## Notas

- En modo RL (`ANNA_RL_MODE=1`) el mundo avanza en lock-step (un `STEP` -> un frame físico).
- Convención del proyecto: `-Z` es forward y `+Z` es back.
