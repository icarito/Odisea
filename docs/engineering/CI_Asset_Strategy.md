# CI Asset Strategy

## Goal

Keep regular CI fast, make missing critical imports fail in seconds, and reserve full cold rebuilds for the narrow set of changes that actually need them.

## The Problem We Hit

Godot's import pipeline mixes two categories:

- disposable cache
- project-critical generated artifacts

For this repo, the expensive failures came from imported scene artifacts for critical `.glb` actors. `Pilot` worked in cold CI because its generated `.import/*.scn` was versioned. `Programmer` did not, so CI spent a long time reimporting and only failed much later when tests tried to load `Programmer_v2.tscn`.

## Policy

1. Track only critical generated scene artifacts for gameplay-critical `.glb` imports.
2. Do not broadly version giant `.stex` texture outputs.
3. Treat tracked files inside `.import/` as versioned project inputs, not disposable cache.
4. Fail early if a critical import manifest points to artifacts that are missing or not tracked.
5. Use `Asset Integrity` only for cold-rebuild validation of the critical scene-import chain, not for every content change in the repo.

## Source Of Truth

- Policy file: `ci/critical_imports.json`
- Validator: `scripts/check_critical_import_artifacts.py`
- Generic manifest validator: `scripts/check_tracked_imports.py`
- Gate de artefactos generados: `scripts/check_import_artifacts_present.py` (+ `ci/import_artifacts_allowlist.txt`)
- CI smoke scene list: `tests/ci_resource_smoke.gd`
- Asset-integrity smoke scene list: `tests/ci_resource_smoke_asset_integrity.gd`

## Gate De Artefactos Generados

Las listas de arriba (críticos + smoke) cubren un subconjunto elegido a mano, así que
un asset nuevo que nadie anotó no está cubierto por ninguna. Eso ya rompió CI una vez:
`Dome_Intro.tscn` referenciaba un `.mp3` recién agregado, la cache de `.import/` venía
de un commit anterior y el pase de import (`--editor --quit`) abortó el scan antes de
procesarlo. El smoke pasó (no incluía esa escena) y el fallo apareció después, como un
test que no podía cargar la escena.

`scripts/check_import_artifacts_present.py` cierra ese hueco: recorre **todos** los
`.import` trackeados y exige que cada uno tenga al menos uno de sus `dest_files`
presente en disco (uno solo, no todos: las texturas declaran un dest por formato VRAM
y cada plataforma genera el suyo). `scripts/godot_import_smoke.sh` lo corre después del
pase de import; si falta algo reintenta un import completo y, si sigue faltando, aborta
ahí mismo listando los assets y el `git add -f` correspondiente — en el paso de import,
no 40 segundos después en un test.

Excepciones (packs de terceros que ninguna escena instancia) van en
`ci/import_artifacts_allowlist.txt`, no en el código.

## Critical Imports Today

- `models/Pilot.glb.import`
- `models/Programmer.glb.import`
- `assets/sfx/bb_loop.wav.import`
- `assets/sfx/spark.wav.import`
- `assets/sfx/Alarm_Loop_01.wav.import`
- `core_v2/props/dragon-studio-mechanical-door-386159.mp3.import`
- `assets/sfx/voicebosch-ice-crackling-168594.mp3.import`
- `core_v2/audio/footsteps/ice/FEETHmn-GRAVEL_AUDIOELK-Fs Gravel Shoes Outdoors 5{6,7}_AUDIOELK_AUDIOELK.wav.import`

(La lista autoritativa es `ci/critical_imports.json`; acá van los casos que conviene
recordar por qué están.)

These entries require:

- source file present
- imported runtime artifact present (`.scn`, `.sample`, `.mp3str`, etc.)
- `.md5` sidecar present
- all of the above tracked by git when listed as critical

## CI Lanes

Normal lanes:

- `tests`
- `pytest`
- `stress`
- `determinism`

Rules:

- run manifest validation first
- run critical import validation second
- run warm `Import + Smoke` with `clean-cache=0`
- skip redundant `runtest.sh` preflight after the smoke already succeeded

Cold lane:

- `Asset Integrity`

Rules:

- triggered only on critical import / actor / level / `.import` changes, or manually
- validates critical imports before invoking Godot
- runs `clean-cache=1` with the dedicated policy-backed smoke script
- does not reuse the heavier `BaseTerrace` smoke path from normal jobs
- fails fast instead of escalating to a full rebuild when a policy-backed artifact is missing

## Hooks

Repo-managed hooks are installed with:

```bash
scripts/install_git_hooks.sh
```

Hook behavior:

- `pre-commit`: validates staged tracked manifests and staged critical imports
- `pre-push`: validates the full tracked manifest set and critical imports before optional smoke

This is intentionally conservative: if a critical imported actor is broken, the push should fail locally instead of waiting for GitHub Actions.

## Adding A New Critical GLB

When a new actor/prop must survive cold CI loads:

1. Import it once locally with `godot3-bin`.
2. Add its manifest path to `ci/critical_imports.json`.
3. `git add` the generated `.import/*.scn` and `.import/*.md5`.
4. Add a representative scene to `tests/ci_resource_smoke.gd` if the asset is part of a critical runtime path.
5. Run:

```bash
python3 scripts/check_tracked_imports.py
python3 scripts/check_critical_import_artifacts.py
python3 scripts/check_import_artifacts_present.py --suggest-tracking
scripts/godot_import_smoke.sh --godot-bin godot3-bin --project-path . --clean-cache 0 --import-mode quick
```

## Adding A New Audio/Texture Asset

Mismo criterio, más barato: si el asset lo referencia una escena que CI carga (tests,
smoke, o cuelga de `Dome_Intro.tscn`), no dependa de que el import de CI lo genere a
tiempo — trackee el artefacto:

```bash
git add -f .import/<nombre>-<hash>.<mp3str|sample|stex> .import/<nombre>-<hash>.md5
```

Los `.sample`/`.mp3str` pesan cientos de KB (a diferencia de los `.stex`), así que el
costo en repo es despreciable frente a un CI rojo.

## Why Not A Dedicated Imports Branch

We explicitly do not use a separate branch as runtime source-of-truth for imports because it:

- decouples code commits from the assets they require
- makes bisection and rollback harder
- hides integration failures until merge time

If storage pressure becomes a real problem later, the next step is artifact mirroring or LFS for selected outputs, not a second branch that the game needs to boot.
