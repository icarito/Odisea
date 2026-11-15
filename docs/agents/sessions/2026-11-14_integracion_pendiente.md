# 2026-11-14 — Integración pendiente (triage pre-rediseño de la bahía)

Sesión: `src-52` (worktree). Pedido de Sebastián: integrar a main lo ya hecho y
triagear PRs viejos / ramas de ago-sep. El orquestador amplió alcance: integrar
lo rescatable en tandas pequeñas (push a main por tanda, CI en verde antes de la
siguiente), cerrar PRs superados con comentario y no forzar decisiones de diseño.

**Restricciones aplicadas:**
- No se tocan zonas de otros workers: `core_v2/input`, `core_v2/player`,
  `core_v2/ui`, `core_v2/props/machines`, `core_v2/levels/machines`.
- No deploy ni cambios de release/TestFlight.
- `project.godot`: diffear bloque entero si se toca.
- Tests: solo puntuales (pytest `tests/test_odisea_runner.py -k ...`).

---

## 1. Ítems 1–2 (integrados)

| Ítem | Fuente | Estado | Nota |
|---|---|---|---|
| 1. organizeize (8 commits) | `origin/ao/tarea-integrar-el/organize-this-project` | Ya estaba en main vía PR #378 (squash `db44cad4`). Corrección: desarchivar FDs vivos. | Se restauraron de `docs/features/archive/` → `docs/features/`: FD-289, FD-050.1/.2, FD-050_scaffold_wfc, FD-052-duct-tile, FD-052_mst_polar, FD-052_v2_mazelab (PR #408, mergeado). CI verde. |
| 2. agents-movement-model (2 commits) | `ao/objetivo-pulido-nocturno-5/agents-movement-model` | Mergeado en PR #408. | Release `agents/release/anna_mapgyms_2026-11-13/` (REPORT + manifest + summary + 3 zips ~480KB c/u; razonables, sin LFS configurado en el repo). Nota en `agents/README.md`. CI verde. |

## 2. Ítem 3 — locales src-20 (reporte)

Worktree `/home/icarito/.ao/data/worktrees/src/src-20` (rama
`ao/finalmente-me-gustar/laberinto-pulido-artistico`): 7 `locale/*.translation`
modificadas sin commitear.

**Veredicto: regeneración del import (ruido), no cambios reales de strings.**
- `ui_strings.csv` (fuente) no está modificado.
- Tamaño byte-idéntico en las 7 (15820→15820, etc.).
- Comparación de contenido con el motor (PHashTranslation): el multiset de
  strings decodificadas del pool es **idéntico** en las 7 (0 diferencias de
  contenido). Solo difieren offsets internos/orden (hash/bucket tables), firma
  típica de reexport del importador.
- Conclusión: descartar el diff (no commitear); no es pérdida de strings.

## 3. Ítem 4 — Triage de PRs abiertos

| PR | Rama | Clasificación | Detalle |
|---|---|---|---|
| #377 | `copilot/fix-upload-macos-job` | **Descartar (restricción)** | Draft; toca `export_all.yml` (upload TestFlight macOS). Prohibido por restricción (release/TestFlight). No se toca. |
| #362 | `feature/FD-315-discord-rich-presence-2609393513590002763` | **Rescatable — integrado (tanda 3)** | FD nuevo. Autoloads DiscordPresence + SettingsManager + test + project.godot (1 línea en [autoload], resuelto conservando `DebugHud` de main). Test puntual `test_discord_presence.gd` pasa. Sin zonas de otros workers. |
| #359 | `docs/FD-310-311-gui-mapa` | **Superado** | Contenido ya cubierto por `docs/engineering/gui-map-2026-09-20.md` y `gui-refactor-review.md` (en main). FDs 310/311/312/313 ya existen. Cerrar con comentario. |
| #358 | `copilot/fix-run-tests-core` | **Descartar (WIP)** | Draft `[WIP]`; fix de CI ya resuelto en main (la suite CI corre en verde). Cerrar con comentario. |
| #347 | `feature/dome-terrace-v2` | **Ya integrado/superado** | cherry contra main: ambos commits `-` (ya aplicados por patch-id). El domo paramétrico V2 ya está en main (`tools/dome_v2/scene_dome.py`, `tools/smoke_dome_default_v2.gd`). Cerrar con comentario (no requiere decisión de diseño: el estado de main ya incorpora el trabajo). |
| #337 | `fix/deploy-sqlite-backup-retention` | **Rescatable — integrado (tanda 2)** | PR #409. Código de script de deploy (no ejecuta deploy). Merge limpio. |
| #298 | `docs/storyboard-primer-puzzle-coolant` | **Rescatable — integrado (tanda 2)** | PR #409. Storyboard doc. Merge limpio. |
| #273 | `feature/FD-245-music-beat-sync` | **Superado** | FD-245 archivado (en `docs/features/archive/`). Toca AudioManager/PrologueDirector/scenes act0 + docs. No aporta a main actual; el FD fue movido a archive por #378. Cerrar con comentario. |
| #272 | `feature/FD-246-duct-collision-fix-15097812386351306092` | **Superado por rewrite de main** | Main ya reescribió `DuctMazeStreamer.gd` (commit `05c95991`, 367 líneas) con box-cage collision y test actualizado. El enfoque del PR (DUCT_WALL_DEPTH 1.2, 96 boxes) es anterior y conflictúa con la versión más nueva. Cerrar con comentario (criterio c: main tiene versión más nueva del mismo sistema). |

## 4. Ítem 4 — Triage de ramas remotas (ago-sep) sin PR

Criterios: (a) ya integrado/superado → saltar; (b) WIP/Initial plan vacíos →
saltar; (c) rescatable → rebase + resolver a favor de main cuando main tenga
versión más nueva del mismo sistema + tests puntuales + mergear; (d) conflicto de
diseño → NO forzar, reportar.

### Ya integrado / superado (cherry 0 o versión más nueva en main)

| Rama | FD | Por qué |
|---|---|---|
| `feature/FD-255-ship-systems-13149698130882545734` | FD-255 vivo | cherry 0/1 (ya aplicado). |
| `feature/FD-265-coolant-lab-greybox` | FD-265 archivado | cherry 0/1. |
| `feature/FD-270-pipe-network-flow-4563819868774246755` | FD-270 archivado | cherry 0/1. |
| `feature/FD-270-pipe-network-flow-9824899782746209167` | FD-270 archivado | cherry 0/1. |
| `feature/FD-270-pipe-network-flow-10388348912452645879` | FD-270 archivado | cherry 1/2; código de redes de pipe ya en main. |
| `feature/FD-273-cold-rupture-oys` | FD-273 archivado | cherry 0/1. |
| `feature/FD-274-elevator-replay-determinism` | FD-274 | cherry 0/1. |
| `fix/fd-274-t1-elevator-replay-determinism-2354333782940828873` | FD-274 | cherry 0/2. |
| `feature/FD-281-room3d-lab` | FD-281 archivado | cherry 0/1. |
| `feature/FD-282-environmental-damage-wind` | FD-282 archivado | cherry 0/1. |
| `feature/FD-296-f3-hud-mode-531388334936566415` | FD-296 | cherry 0/1; además toca UI (zona otro worker). |
| `feature/FD-296-suitos-core` | FD-296 | cherry 0/1. |
| `feature/FD-296-f4-control-remoto-hud` | FD-296 | cherry 0/1 (spec ya en main). |
| `feature/FD-309-coreano` | FD-309 vivo | cherry 0/1; main ya tiene soporte coreano (FD-309 vivo). |
| `fix/ci-hud-pause-leak` | — | cherry 0/3. |
| `chore/box3d-v0.2.0` | — | cherry 0/3; bump de motor ya considerado/descartado en main. |
| `feature/FD-316-sim-host-render` | FD-316 vivo | main ya tiene `net/RemoteSimHost.gd` + `RemoteSimClient.gd` (versión más nueva). |
| `feature/FD-316-remote-sim-offload-16685293078621563829` | FD-316 vivo | main ya tiene el sistema (RemoteSimHost/Client). versión más nueva. |
| `feat/fd-296-suit-os-f1-5595116229208619491` | FD-296 | main ya tiene `SuitOS.gd` + `HUDableComponent.gd` (versión más nueva). |
| `feature/fd-296-f1.5-suitos-visible-slice-9451354173055743452` | FD-296 | toca UI (zona otro worker); main tiene versión más nueva. |
| `feature/FD-297-seamless-hud-transitions-15345067568234042724` | FD-297 | toca input/UI (zona otro worker). |
| `feature/FD-297-transiciones-seamless` | FD-297 | spec ya en main (FD-297 vivo). |
| `feature/FD-296-f4-control-remoto-hud-2971282181895848043` | FD-296 | toca UI (zona otro worker). |
| `feature/FD-309-interactable-hudable-placeholder` | FD-309 | spec placeholder; toca UI. |
| `feature/FD-285-light-fixtures`, `-286-light-switch`, `-287-light-flicker` | FDs archivados | specs archivadas; main ya tiene sistema de luces. |
| `fd-287-light-flicker-1905668912619779718`, `feat/fd-285-light-fixtures-upgrade-13912145732527871354` | FDs archivados | main ya tiene sistema de luces. |
| `jules-13720415065976826531-f3412a09` | FD-286 archivado | main ya tiene `LightSwitchV2.gd`. |
| `feature/FD-261-circuit-editor-usability`, `feature/FD-262-procedural-pipe-router`, `feature/FD-263-touch-universal`, `feature/FD-264-coolant-flow-graph` | FDs vivos | specs ya existentes en main (solo docs). |
| `feature/fd-262-pipe-router-8030756822320062193` | FD-262 | main ya tiene `systems/pipe/` (PipeRouter/PipeRun/TubeBuilder) — versión más nueva. |
| `feat/circuit-editor-dome-intro-12187682062895793459` | FD-261 | main ya tiene `addons/odyssey_circuit_editor/` + `LogicCircuitManager` — versión más nueva. |
| `jules-fd-294-control-remoto-13111048624747009724` | FD-294 | toca UI (zona otro worker); main ya tiene RemoteControl. |
| `feature/fd-263-touch-universal-1578914674142014119` | FD-263 | toca input/player (zona otro worker). |
| `fd-264-coolant-flow-graph-791304327056840520` | FD-264 | toca player (zona otro worker). |
| `feature/FD-271-ragdoll-death` | FD-271 archivado | toca player (zona otro worker). |
| `fd-273-cold-rupture-oys-refactor-13419569499427746083` | FD-273 archivado | conflictos 5; FD archivado. |

### Descartar (WIP / Initial plan vacíos / diag)

| Rama | Motivo |
|---|---|
| `copilot/fix-failing-github-actions-job` | Único commit "Initial plan" vacío. |
| `copilot/fix-run-tests-core` | WIP draft (PR #358). |
| `copilot/fix-run-tests-core-job` | WIP (fix de CI ya resuelto en main). |
| `diag/hud-rect` | diagnóstico temporal, 1 commit, sin valor de integración. |
| `feature/blender-bpy-skill`, `feature/blender-bpy-skill-rollup` | skills de blender (no vinculado al juego); no rescatable para main. |

### Rescatable pendiente de decisión

| Rama / PR | Qué aporta | Costo |
|---|---|---|
| PR #362 / `feature/FD-315-discord-rich-presence-2609393513590002763` | Feature completa de Discord Rich Presence con telemetría viva (autoloads + test). | Conflicto solo en `project.godot` (1 línea autoload). Sin zonas de otros workers. Candidato a integrar con resolución a favor de main. |

---

## 5. Estado de tandas

| Tanda | Contenido | PR | Estado |
|---|---|---|---|
| 1 | FDs vivos restaurados + agents-movement-model (anna_mapgyms) | #408 | Mergeado a main. CI verde. |
| 2 | #337 deploy backup retention + #298 storyboard + FD-300 doc | #409 | En CI (pendiente merge). |
| 3 | #362 Discord (FD-315) | — | Merge local listo (rama `ao/integraci-n-previa/tanda3-discord`, test pasa); a la espera de pushear y CI. |

**Pendiente:** cerrar PRs superados (#359, #358, #347, #273, #272) con comentario
explicativo; decidir #362.
