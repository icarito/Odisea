---
description: Mapa principal del código de Odisea (Godot 3.6 fork, GDScript). Pendiente de indexado completo.
read_if: Antes de explorar el repo o buscar dónde vive un sistema.
---

# Shared Project Index

## Architecture

- Juego Godot 3.6 (fork con Box3D), GDScript 1.x; todo el código vigente vive en `core_v2/`.
- Core determinista con replay: la simulación corre en `_physics_process` (ver `AGENTS.md` §5).
- Telemetría: autoload `ANNAV2` → peer Python `:4999` → central `:5003` con dashboard.
- Convención de ejes no estándar: -Z es forward.

## Project Index

- `AGENTS.md` — Reglas canónicas para agentes
- `CLAUDE.md`, `GEMINI.md`, `KILO.md` — Adaptadores finos a `AGENTS.md`
- `project.godot`, `export_presets.cfg`, `Makefile` — Ditto
- `odisea_peer.py`, `odisea_central.py` — Peer y central de telemetría
- `runtest.sh`, `test_prop.sh`, `test_ui.sh` — Runners de tests, props y UI
- `docs/` — Documentación; `docs/features/` Feature Docs, `docs/agents/` mapa de agentes, `docs/engineering/` contratos
- `tools/`, `scripts/` — Utilidades de build, bake y CI
- `dashboard/` — Dashboard web (Vite PWA)
- `assets/`, `textures/`, `models/`, `materials/`, `shaders/` — Arte; no listar archivos
- `addons/`, `.import/`, `build/` — Dependencias y artefactos; no listar archivos

### `core_v2/` — Código principal del juego

- `player/` — Controladores del jugador, multi-tool, zero-G
- `components/` — Bases de interactuables, zonas, plataformas, `PushableBoxV2`
- `props/` — Props interactivos y decorativos
- `props/machines/` — Kit de máquinas (FD-320): `MachinePart`, `MachineHinge`, `MachineTrigger` y `MachineLevel` (niveles por layout JSON)
- `levels/machines/` — Bahía de máquinas: `MachineBay.tscn` + `machine_bay.json`
- `levels/` — Escenas de nivel; `levels/interiors/` domos y fuentes de bake
- `input/` — `InputProviderV2` (árbitro LIVE/REPLAY), `InputDataV2` (frame serializable), `AutopilotInputV2` (modo asistido Transit-Run)
- `systems/` — Sistemas de nave (cryo, room)
- `systems/flow/` — `FlowMetrics` (alcance del jugador leído de `Pilot_v2`) y `FlowRouteValidator` (ruta principal y waypoints por semilla)
- `systems/scaffold/`, `systems/ScaffoldStreamController.gd` — Andamio WFC por chunks en streaming; `ScaffoldOrbit` lo proyecta al cilindro; `ScaffoldChunkRegistry` es el catálogo 1D de chunks Transit-Run (datos puros)
- `agents/` — Inferencia MLP de la política de ANNA en GDScript (`MLPPolicyInference`, `HoloPolicyController`)
- `ui/` — HUD, OdiseaOS, menús, mouse virtual
- `telemetry/` — ANNAV2 y servidor MCP
- `tests/` — GdUnit y OYS
