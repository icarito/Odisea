# Odisea Agent Entry Point

Este directorio organiza las instrucciones compartidas para cualquier agente que trabaje en
*Odisea: El Arca Silenciosa*.

## Orden de lectura obligatorio

1. `AGENTS.md` en la raiz del repo: reglas duras del proyecto, convenciones Godot 3, contratos criticos y validacion.
2. `docs/agents/agent-map.md`: donde vive cada tipo de instruccion y que archivo editar.
3. `docs/agents/tooling.md`: comandos de test, telemetria, runtime debug, props y UI.
4. `docs/agents/skills-index.md`: catalogo de skills/comandos disponibles para Codex, Claude, Gemini, Kilo y agentes genericos.
5. El FD o spec de la tarea en `docs/features/`, si aplica.

## Regla de fuente canonica

- Reglas de desarrollo del proyecto: `AGENTS.md`.
- Workflows reutilizables por cualquier agente: `docs/skills/`.
- Explicacion de herramientas y validacion: `docs/agents/tooling.md`.
- Skills nativas de Claude: `.claude/skills/`, idealmente como adaptadores que apuntan a docs canonicos.
- Comandos nativos de Kilo: `.kilo/command/`, idealmente como adaptadores con front matter que apuntan a docs canonicos.
- Entradas para otros agentes: `CLAUDE.md`, `GEMINI.md`, `KILO.md` y otros shims deben enlazar aca y no inventar reglas nuevas.

Si hay conflicto, gana este orden: instrucciones del usuario actual, `AGENTS.md`, docs en `docs/agents/`, docs en `docs/skills/`, adaptadores especificos de agente.

## Invariantes que no se negocian

- Godot 3.6 con GDScript 1.x. Usar `godot3-bin`, no `godot`.
- Todo codigo nuevo o refactorizado va en `core_v2/`.
- No romper inmersion: la camara no salta, no rota 180 grados y no cambia de rig al entrar/salir de modos.
- Sistema de coordenadas no estandar: `+Z = BACK`, `-Z = FORWARD`.
- No introducir no-determinismo en gameplay/replay.
- ANNA V1 esta deprecado para debugging nuevo; usar telemetria ANNA V2 via peer HTTP `:4999`.
- Cambios chicos, enfocados, con hipotesis clara y tests relevantes despues.

