# jules — Delegar tareas a Jules (agente asíncrono de Google)

Jules implementa código de forma asíncrona sobre `icarito/Odisea` y devuelve un PR. Nuestro rol
es **estructurar, delegar, monitorear y revisar** — no escribir el código de esas tareas ni
decidir el merge.

Uso normal: dentro de `/deliver`, para las tareas marcadas `JULES` en el plan de un FD.

## CLI

`bin/jules-cli` (Python 3, sin dependencias). Lee la API key de `JULES_API_KEY` en el entorno,
si no de `.env` en la raíz del repo, si no de `secrets/jules_key`. **Nunca imprimir la key.**

```bash
bin/jules-cli sources                                  # repos conectados a Jules
bin/jules-cli create --branch <rama> --spec-file <brief.md> --title "FD-0XX tN: ..."
bin/jules-cli check [--filter FD-0XX] [--limit N]      # una línea por sesión
bin/jules-cli status <session_id>                      # estado, última actividad, PR
bin/jules-cli activities <session_id> [--limit N]      # historial (plan, mensajes, preguntas)
bin/jules-cli approve-plan <session_id>
bin/jules-cli reply <session_id> "<texto>"
bin/jules-cli result <session_id> [--patch <archivo>]  # PR + archivos; el diff va al archivo
```

`create` usa `--repo icarito/Odisea` por defecto, exige aprobación de plan (`--auto-plan` la
salta) y crea PR automático (`--no-pr` lo evita). `status` nunca imprime el diff completo:
para leerlo, `result --patch`.

Estados que exigen acción nuestra (`needs_attention: true`): `AWAITING_PLAN_APPROVAL`,
`AWAITING_USER_FEEDBACK`, `PAUSED`, `FAILED`.

> **Una sesión esperando aprobación de plan puede cerrarse vacía.** Pasa `COMPLETED` sin haber
> escrito una línea, y en el listado se ve igual que una que entregó. Por eso `check` consulta
> los outputs de cada `COMPLETED` y marca `VACIA` las que no entregaron nada.
> Dos formas de no perder el trabajo: aprobar el plan apenas aparece, o lanzar con
> `--auto-plan` cuando el brief ya es específico (los planes de un brief bien escrito son
> siempre un calco del brief). Con tres sesiones en paralelo, `--auto-plan` es lo más seguro:
> si nadie mira durante veinte minutos, se pierden las tres.

## El PR hay que pedirlo, no darlo por hecho

`create` manda `automationMode: AUTO_CREATE_PR`, pero ese campo es **input-only** (nunca vuelve
en la respuesta, ni siquiera en las sesiones que sí publicaron) y la propia API lo define como
"crea rama y PR **si aplica**". En la práctica es discrecional: de siete sesiones, dos publicaron
PR y cinco entregaron solo el `changeSet`. **No existe ningún endpoint para publicar el PR
después** — no hay `publishPullRequest` ni equivalente; los únicos métodos son `create`, `get`,
`list`, `approvePlan` y `sendMessage`.

Consecuencia práctica: si la sesión no publica, hay que bajar el patch y aplicarlo a mano, que es
trabajo y contexto desperdiciados. Para evitarlo:

1. **Pedirlo en el brief.** Cerrar todo brief con una instrucción explícita de publicar el PR
   contra la rama de trabajo. Es lo único que Jules lee.
2. **Si igual no lo publicó**, reclamarlo por `reply`: un mensaje a una sesión `COMPLETED` la
   reabre (`IN_PROGRESS`) y la pone a publicar. Es más barato que integrar el patch a mano.
3. Recién como último recurso, `result --patch` + `git apply`.

## Flujo

1. **Brief** — `docs/features/tasks/FD-0XX-tN-<slug>.md`, autocontenido: objetivo, contexto del
   sistema, archivos permitidos y prohibidos, convenciones (Godot 3.6, GDScript 1.x con `yield`
   no `await`, todo en `core_v2/`, GLES2 ⇒ `CPUParticles`), criterio de aceptación, y qué no hacer.
   Jules no ve la conversación: lo que no está en el brief, no existe.
2. **Rama** — commitear y pushear el brief a la rama del FD antes de crear la sesión;
   `--branch` tiene que ser una rama que ya está en el remoto.
3. **Delegar** — `create`, y anotar el `session_id` en la tabla del FD.
4. **Monitorear** — `check --filter FD-0XX`. Trabajando y sin `needs_attention` ⇒ esperar en
   silencio y avanzar con otras tareas.
5. **Plan** — compararlo con el brief. Coherente ⇒ `approve-plan`. Se desvía ⇒ `reply` con la
   corrección. Duda real de diseño ⇒ preguntarle a Sebastián.
6. **Preguntas** — pasarle a Sebastián la pregunta **textual** de Jules y contestar con `reply`
   solo lo que él respondió.
7. **Resultado** — `result --patch`, revisar en chunks, correr tests y capturas, presentar a
   Sebastián. El merge lo decide él.

## Reglas críticas

- No inventar respuestas técnicas para Jules. Lo que no está en el brief se pregunta.
- Nunca mergear un PR sin aprobación explícita de Sebastián.
- Una sesión por tarea; tareas de Jules con archivos disjuntos entre sí.
- Nada de escenas de nivel compartidas (`scenes/levels/**`) en una tarea de Jules.
- `FAILED`/`CANCELLED` se reporta con contexto; no se reintenta en silencio.
- La API key no se imprime, no se pasa por argumento, no se commitea (`.env` está en `.gitignore`).
