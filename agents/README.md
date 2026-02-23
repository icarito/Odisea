# Agents RL (A.N.N.A)

Esta carpeta contiene scripts reproducibles para entrenar y evaluar un agente RL
en `core_v2/tests/TestScene_RL.tscn`.

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

Con ventana (para observar):

```bash
python3 agents/train_anna.py --timesteps 50000 --render --cpu-threads 4
```

Salida por defecto:

- Modelo: `agents/models/anna_ppo.zip`
- Metadata: `agents/models/anna_ppo.meta.json`

## 2) Evaluar / ver el agente

```bash
python3 agents/eval_anna.py --model agents/models/anna_ppo.zip --episodes 5 --render --cpu-threads 4
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
