---
name: jules
description: Delegar tareas de código a Jules, el agente asíncrono de Google, sobre el repo icarito/Odisea — crear sesiones desde un brief, aprobar planes, responder preguntas, y traer el PR para revisión. Usar cuando se pida delegar/encargar una tarea a Jules, consultar el estado de una sesión de Jules, o al invocar /jules.
---

# jules — Delegación asíncrona de tareas

Fuente canónica: **`docs/skills/jules.md`** — leerla antes de operar.
Contexto de uso normal: las tareas marcadas `JULES` en el plan de un FD (`/deliver`).

## CLI

```bash
bin/jules-cli create --branch <rama> --spec-file <brief.md> --title "FD-0XX tN: ..."
bin/jules-cli check --filter FD-0XX
bin/jules-cli status <session_id>
bin/jules-cli activities <session_id>
bin/jules-cli approve-plan <session_id>
bin/jules-cli reply <session_id> "<texto>"
bin/jules-cli result <session_id> --patch /tmp/FD-0XX-tN.diff
```

Lee `JULES_API_KEY` de `.env`. Nunca imprimir la key ni pasarla por argumento.

## Reglas

- El brief es autocontenido: Jules no ve esta conversación.
- Preguntas de Jules → texto exacto a Sebastián (`AskUserQuestion`), respuesta vía `reply`.
- `status` no trae el diff completo; para leerlo usar `result --patch` y revisarlo en chunks.
- Nunca mergear sin OK explícito de Sebastián. `FAILED`/`CANCELLED` se reporta, no se reintenta.
