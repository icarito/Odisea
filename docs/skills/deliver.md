# /deliver — Ejecutar el plan de un FD enriquecido

## Propósito

Llevar un FD con `## Plan de ejecución` aprobado hasta código mergeado: despachar tareas a
subagentes Sonnet y a Jules, revisar lo que vuelve, y frenar en los checkpoints donde
Sebastián juzga jugando.

Entrada: `/deliver FD-256`. Precondición: el FD pasó por `/enrich` y Sebastián lo aprobó.
Si no hay tabla de tareas, no improvisar: correr `/enrich` primero.

**Regla dura:** nada se mergea sin OK explícito de Sebastián.

---

## 1. Rama

```bash
git checkout main && git pull
git checkout -b feature/FD-0XX-<slug>
git push -u origin feature/FD-0XX-<slug>
```

Una rama por FD. Las tareas de Jules parten de esta rama y devuelven su propio PR.

## 2. Despachar

Recorrer la tabla en orden de dependencias. Lo que no depende de nada arranca en paralelo:
primero las tareas JULES (son asíncronas, tardan), después lo local.

**Dos carriles a la vez.** Jules construye lógica mientras acá se trabaja lo visual. Jules
admite **hasta 3 sesiones en paralelo**: elegir tres tareas con archivos disjuntos y sin
dependencias entre sí, lanzarlas juntas, y mientras corren no quedarse esperando — seguir con
el carril visual local, que es el que necesita ojo y feedback de Sebastián.

### Tareas SONNET / OPUS locales

Subagente `executor` (Sonnet, barato para bulk). El prompt sigue el formato de `AGENTS.md` §3
y debe ser autocontenido:

```
OBJETIVO: [una frase]
CONTEXTO: docs/features/FD-0XX-<slug>.md, sección "<tarea N>"
ARCHIVOS PERMITIDOS: [lista exacta]
ARCHIVOS PROHIBIDOS: escenas de nivel, autoloads, cualquier archivo de otra tarea
REGLAS: Godot 3.6 / GDScript 1.x (yield, no await). Todo en core_v2/.
        [contratos aplicables del FD: determinismo, cámara, GLES2...]
ACEPTACIÓN: [el comando o test que debe pasar]
PROCEDIMIENTO: leer → hipótesis → cambio mínimo → ./runtest.sh -a <test> → reportar
```

Varias tareas locales a la vez solo si sus `ARCHIVOS PERMITIDOS` son disjuntos.

El trabajo **visual** (props, materiales, escala, luz, composición) no se despacha y se olvida:
es un lazo corto — editar → `./test_prop.sh` → mirar la captura → ajustar → mostrarle a
Sebastián. Conviene hacerlo en la sesión (lead) o con un subagente al que se le revisan las
capturas, nunca a ciegas.

### Tareas JULES

Jules no ve esta conversación: el brief tiene que bastarse solo. Se le mandan tareas de
**lógica sustancial** (máquinas de estado, determinismo, sistemas nuevos, refactors, tests),
no recados; y nada que se juzgue mirando.

```bash
mkdir -p docs/features/tasks
# escribir docs/features/tasks/FD-0XX-tN-<slug>.md con:
#   objetivo, contexto del sistema, archivos permitidos/prohibidos,
#   convenciones (Godot 3.6, GDScript 1.x, core_v2/, GLES2/CPUParticles),
#   criterio de aceptación, y qué NO hacer
git add docs/features/tasks/ && git commit -m "docs(FD-0XX): brief tarea N" && git push

bin/jules-cli create --branch feature/FD-0XX-<slug> \
  --spec-file docs/features/tasks/FD-0XX-tN-<slug>.md \
  --title "FD-0XX tN: <título>"
```

Anotar el `session_id` devuelto en la columna `Estado` de la tabla del FD
(`en curso · jules 1221…`). El FD es el registro de estado; no hay archivo aparte.

Detalle del CLI y reglas de trato con Jules: `docs/skills/jules.md`.

## 3. Monitorear

```bash
bin/jules-cli check --filter FD-0XX      # una línea por sesión del FD
bin/jules-cli status <session_id>        # estado + última actividad + PR
```

- `IN_PROGRESS` sin `needs_attention` → esperar en silencio, seguir con otras tareas.
- `AWAITING_PLAN_APPROVAL` → leer el plan (`activities`), compararlo con el brief.
  Coherente → `approve-plan`. Se desvía → `reply` con la corrección. Duda real de diseño →
  preguntarle a Sebastián.
- `AWAITING_USER_FEEDBACK` → pasarle a Sebastián la pregunta **textual** de Jules. No inventar
  la respuesta; contestarla con `reply` cuando él responda.
- `FAILED` / `CANCELLED` → reportar con contexto. No reintentar en silencio.

## 4. Recibir y revisar

```bash
bin/jules-cli result <session_id> --patch /tmp/FD-0XX-tN.diff
```

Revisión en chunks digeribles, por archivo o subsistema, con riesgos explícitos. Antes de
llevárselo a Sebastián, verificar de verdad:

```bash
./runtest.sh -a ./core_v2/tests/<test relevante>.gd
./test_prop.sh --target="<Prop>" --base64      # props: siempre mostrar las capturas
./test_ui.sh --scene=<Escena> --base64         # UI
```

Las capturas se comparten en el chat siempre, no se describen. Un asset no está terminado
hasta que Sebastián confirma que la captura es correcta.

## 5. Checkpoints en vivo (Sebastián juega)

Para todo lo marcado `HUMANO` y al cerrar cada sistema:

```bash
tools/launch_game.sh --scene res://scenes/levels/<escena>.tscn   # headful
curl -s localhost:4999/status | python3 -m json.tool             # telemetría en vivo
```

Preguntar concreto: "¿la niebla tapa lo suficiente sin frustrar?", no "¿está bien?".
Cada ajuste que salga de acá se anota en `## Decisiones` del FD, con fecha. Si el ajuste es de
valores (densidad, duración, color), aplicarlo en el momento y volver a mostrar.

## 6. Cerrar

1. Suite completa: `./runtest.sh`.
2. Merge de los PR de Jules **solo con OK explícito** de Sebastián.
3. `/fd-verify` contra la sección `## Verification` del FD.
4. `/fd-close` — archivar y actualizar changelog.

Commits de implementación: `feat(FD-0XX): descripción`.

## Errores que ya cometimos

- Delegar a Jules una tarea que toca una escena de nivel compartida → conflicto de merge caro.
- Dar por buena una tarea porque el diff se ve bien: correr los tests y mirar las capturas.
- Responderle a Jules una duda de diseño en lugar de preguntarle a Sebastián: se implementa mal
  y hay que rehacerlo.
- Seguir despachando tareas mientras una está bloqueada esperando respuesta: primero desbloquear.
