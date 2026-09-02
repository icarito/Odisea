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

## Assets Nuevos: CI No Los Importa

Dos hechos medidos, contra-intuitivos, que conviene tener presentes:

1. **El pase de import de CI no importa.** `godot --editor --quit` sale en el primer
   frame idle y aborta el scan (`WARNING: Scan thread aborted...`). Un segundo pase no
   avanza nada. En la práctica CI vive de la cache de `.import/` acumulada, y un asset
   agregado en el commit no existe allá salvo que su artefacto viaje en el repo.
2. **No todo lo faltante rompe igual.** Un `ext_resource` de audio/escena/malla que no
   resuelve tumba la escena entera (`[ext_resource] referenced nonexistent resource`);
   una textura faltante solo imprime un error suelto y la escena igual carga
   (verificado cargando `Dome_Intro.tscn` sin sus `.stex`). Por eso los `.stex` quedan
   fuera del chequeo que bloquea, además de ser los que pesan.

De ahí la regla que se hace cumplir: **todo asset importado nuevo que no sea textura
debe traer su artefacto trackeado**. La valida `scripts/check_import_artifacts_present.py`:

- `--mode added --base <sha>`: falla si un `.import` agregado en el push/PR no tiene su
  artefacto en git, e imprime el `git add -f` exacto. Corre como paso propio en
  `pytest_runner.yml`, antes del import, sin depender de Godot.
- `--mode all`: informativo. Lista los assets sin artefacto en disco, marcando cuáles
  romperían escenas. Lo corre `godot_import_smoke.sh` después del import para que el
  hueco quede visible en el log.

Esto ya rompió CI una vez: `Dome_Intro.tscn` referenciaba un `.mp3` recién agregado, el
smoke no incluía esa escena y el fallo apareció después, como un test que no podía
cargarla.

Sumar `Dome_Intro.tscn` al smoke se probó y se revirtió: la escena **carga** en CI, pero
el paso de smoke falla ante cualquier línea `Failed loading resource:`, y la escena
arrastra texturas que la cache nunca generó (`pilot.png`, `HelmetView_HI-RES`,
`steel_grate_platform`). Mientras esos huecos sigan abiertos, agregarla solo produce
ruido. Queda cubierta por `test_menu_checkpoint_flow`.

Al día de hoy el reporte informativo lista ~66 assets sin artefacto en CI (43 texturas
tolerables + 23 audio/malla que sí romperían la escena que los use). Son huecos
preexistentes de la cache, no regresiones: ninguna escena que CI cargue hoy los toca.
Cerrarlos de verdad requiere que el pase de import complete el scan, que es trabajo
aparte del gate.

Excepciones (packs de terceros que ninguna escena instancia) van en
`ci/import_artifacts_allowlist.txt`, no en el código.

## Qué variantes VRAM se trackean

Godot genera hasta cinco `.stex` por textura (`s3tc`, `etc2`, `etc`, `pvrtc` y el
plano sin comprimir). Trackearlas todas cuadruplica el costo en git sin beneficio:

- `s3tc` — Desktop Linux/Windows/macOS y HTML5. **Se trackea.**
- `etc` — Android GLES2. **Se trackea.**
- `pvrtc` — iOS, que sí se exporta. **Se trackea.**
- `etc2` — Android **GLES3**. Desde el 2026-09-01 el proyecto corre GLES3 en todas las
  plataformas (ver `Renderer_GLES3_iOS.md`), así que **sí se carga**: trackear las
  `.etc2.stex` nuevas (empezaron a entrar con `dff33286`).
- plano — fallback; se trackea cuando el importador lo genera.

Los sets PBR nuevos (1k, cinco mapas cada uno) además se importan con
`size_limit=512`: a 1k pesaban ~19 MB de artefactos por set. Cerrar los huecos de
`Dome_Intro.tscn` costaba 71 MB con todas las variantes a 1k y quedó en 21 MB.

Ojo al auditar dependencias: `DomeTerrace_baked.mesh` es un recurso binario y sus
materiales referencian texturas que **no** aparecen si uno recorre las líneas
`ext_resource` de los `.tscn` a mano. Usar `ResourceLoader.get_dependencies()`.

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
python3 scripts/check_import_artifacts_present.py --mode added --base origin/main
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
