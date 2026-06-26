---
description: Cargar contexto del proyecto Odisea para una sesión de desarrollo
---

# /fd-explore — Cargar contexto del proyecto

Fuente canonica compartida: `docs/skills/fd-explore.md`.

## Propósito
Iniciar una sesión de agente con todo el contexto necesario del proyecto Odisea, evitando arrancar desde cero.

## Archivos a cargar (en orden)

1. `AGENTS.md` — convenciones del proyecto, estructura de agentes.
2. `docs/features/FEATURE_INDEX.md` — FDs activos y completados.
3. `CHANGELOG.md` — historial de cambios recientes.
4. `docs/architecture.md` o equivalente — arquitectura de sistemas (`core_v2/`).
5. `project.godot` — configuración general (Godot 3, versión).
6. Si el FD lo requiere: `core_v2/` archivos relevantes al feature.

## Para el agente implementador
- Cargar el FD específico asignado como spec principal.
- Leer `docs/skills/fd-verify.md` y `docs/skills/fd-close.md` al finalizar implementación.
- Seguir convenciones Godot 3 / GDScript 1.x del proyecto.

## Para el agente planificador
- Cargar contexto del vault `Odisea_Design_Docs/` si el FD toca diseño de niveles o narrativa.
- Cross-check con `FEATURE_INDEX.md` para evitar duplicar features existentes.
