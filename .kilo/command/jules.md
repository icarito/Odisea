---
description: Delegar una tarea de codigo a Jules (agente asincrono de Google) sobre icarito/Odisea y gestionar la sesion hasta el PR
---

# /jules — Delegacion asincrona de tareas

Fuente canonica compartida: `docs/skills/jules.md`. Uso normal: tareas marcadas `JULES` en el
plan de un FD (`/deliver`).

## CLI

```bash
bin/jules-cli sources
bin/jules-cli create --branch <rama> --spec-file <brief.md> --title "FD-0XX tN: ..."
bin/jules-cli check --filter FD-0XX
bin/jules-cli status <session_id>
bin/jules-cli activities <session_id>
bin/jules-cli approve-plan <session_id>
bin/jules-cli reply <session_id> "<texto>"
bin/jules-cli result <session_id> --patch /tmp/FD-0XX-tN.diff
```

Lee `JULES_API_KEY` de `.env` (o `secrets/jules_key`). **Nunca imprimir la key.**
`needs_attention: true` en `AWAITING_PLAN_APPROVAL`, `AWAITING_USER_FEEDBACK`, `PAUSED`, `FAILED`.

## Reglas

- El brief es autocontenido: Jules no ve la conversacion.
- Lo que no esta en el brief se le pregunta a Sebastian, no se inventa.
- Preguntas de Jules ⇒ texto exacto a Sebastian; su respuesta va con `reply`.
- Una sesion por tarea, archivos disjuntos, nada de `scenes/levels/**`.
- Nunca mergear sin OK explicito. `FAILED`/`CANCELLED` se reporta con contexto.
