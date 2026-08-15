---
description: Ejecutar el plan de un FD enriquecido — despachar tareas a Sonnet y a Jules, revisar, y checkpoints en vivo con Sebastian
---

# /deliver — Ejecutar el plan de un FD

Fuente canonica compartida: `docs/skills/deliver.md`. Delegacion a Jules: `docs/skills/jules.md`.

Precondicion: el FD tiene `## Plan de ejecucion` aprobado (`/enrich`). Si no, correr `/enrich`.

## Resumen del flujo

1. **Rama** — `feature/FD-0XX-<slug>`, pusheada. Una rama por FD.
2. **Despachar** — dos carriles: Jules construye logica (hasta 3 sesiones en paralelo, archivos
   disjuntos) mientras local se trabaja lo visual con capturas. Lanzar Jules primero y no
   quedarse esperando.
   - LOCAL: subagente ejecutor con prompt formato `AGENTS.md` §3
     (OBJETIVO / ARCHIVOS PERMITIDOS / PROHIBIDOS / REGLAS / ACEPTACION / PROCEDIMIENTO).
     Lo visual es lazo corto: editar → `./test_prop.sh` → mirar captura → ajustar.
   - JULES: brief autocontenido en `docs/features/tasks/FD-0XX-tN-<slug>.md`, commit+push, y
     `bin/jules-cli create --branch <rama> --spec-file <brief>`. Anotar `session_id` en el FD.
3. **Monitorear** — `bin/jules-cli check --filter FD-0XX`. Plan coherente ⇒ `approve-plan`;
   pregunta de Jules ⇒ pasarsela textual a Sebastian y responder con `reply`.
4. **Revisar** — `result --patch`, revision en chunks, `./runtest.sh -a <test>`,
   `./test_prop.sh` / `./test_ui.sh` y mostrar las capturas.
5. **Checkpoints en vivo** — `tools/launch_game.sh` + telemetria `:4999`; Sebastian juzga
   feel/balance/arte. Cada ajuste se anota en `## Decisiones` del FD.
6. **Cerrar** — `./runtest.sh` completo, merge solo con OK explicito, `/fd-verify`, `/fd-close`.

Reglas duras: nada se mergea sin OK de Sebastian; tareas paralelas con archivos disjuntos;
ninguna tarea de Jules toca `scenes/levels/**`.
