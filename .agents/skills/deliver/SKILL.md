---
name: deliver
description: Ejecutar el plan de un FD ya enriquecido — crear la rama, despachar tareas a subagentes Sonnet y a Jules (agente asíncrono de Google), monitorear, revisar diffs con tests y capturas, y frenar en los checkpoints donde Sebastián prueba en vivo. Usar al invocar /deliver, o cuando se pida implementar/despachar/entregar las tareas de un FD aprobado.
---

# /deliver — Ejecutar el plan de un FD

Fuente canónica: **`docs/skills/deliver.md`** — leerla completa antes de actuar.
Delegación a Jules: `docs/skills/jules.md`. Plan previo: `/enrich`.

## Adaptación para Codex

- **Dos carriles:** Jules construye lógica (hasta 3 sesiones en paralelo) mientras acá se
  trabaja lo visual con `test_prop.sh` y capturas. Mientras Jules corre, no esperar: avanzar el
  carril local.
- **Tareas locales:** `Agent` con `subagent_type: "executor"` (corre en Sonnet). Prompt
  autocontenido con el formato de `AGENTS.md` §3 (OBJETIVO / ARCHIVOS PERMITIDOS / PROHIBIDOS /
  REGLAS / ACEPTACIÓN / PROCEDIMIENTO). Lanzar en background y en paralelo solo si sus archivos
  permitidos son disjuntos.
- **Tareas JULES:** `bin/jules-cli` vía Bash. Una sesión por tarea, brief commiteado y pusheado
  antes de crear la sesión.
- **Estado:** vive en la tabla `## Plan de ejecución` del FD (incluido el `session_id`).
  Usar `TodoWrite` solo como vista de trabajo de la sesión actual, no como registro.
- **Capturas:** `test_prop.sh` / `test_ui.sh` / `capture_vision` → mostrar los PNG en el chat
  siempre, nunca describirlos.
- **Espera de Jules:** mientras una sesión está `IN_PROGRESS`, avanzar con otras tareas. Si no
  queda nada más, ofrecer `/loop` para chequear cada tanto en vez de hacer polling manual.
- Nunca mergear un PR sin OK explícito de Sebastián. Las preguntas de Jules se le pasan
  textuales.
