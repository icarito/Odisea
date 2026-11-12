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
- `levels/` — Escenas de nivel; `levels/interiors/` domos y fuentes de bake
- `systems/` — Sistemas de nave (cryo, room)
- `ui/` — HUD, OdiseaOS, menús, mouse virtual
- `telemetry/` — ANNAV2 y servidor MCP
- `tests/` — GdUnit y OYS
