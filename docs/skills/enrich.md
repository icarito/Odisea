# /enrich — Enriquecer un FD hasta que sea ejecutable

## Propósito

Tomar un FD en estado *Design* (una idea bien escrita) y dejarlo **ejecutable**: assets
verificados, riesgos técnicos identificados, dudas resueltas con Sebastián, y un plan de
tareas con ejecutor asignado (Sonnet, Jules o humano).

Entrada: `/enrich FD-256` (número, slug o ruta al archivo).
Salida: el mismo FD, con cuatro secciones nuevas y aprobación explícita para pasar a `/deliver`.

**Regla dura:** `/enrich` no escribe código de juego. Solo lee, verifica y edita el FD.

---

## Fase 0 — Contexto (sin preguntar nada todavía)

1. El FD objetivo y su padre/hijos si es parte de una familia (`FD-255` → `FD-256..259`).
2. `AGENTS.md` §1 (inmersión), §2 (convenciones), §5 (contratos críticos), §10 (alcance Acto I).
3. `docs/features/FEATURE_INDEX.md` — buscar features previos que toquen los mismos sistemas.

## Fase 1 — Inventario de assets (verificar, nunca confiar en el FD)

Todo path que el FD menciona se comprueba en disco. Un FD que cita un asset inexistente es
la causa número uno de una tarea delegada que vuelve mal.

```bash
ls core_v2/systems/gas/ core_v2/props/pipe/          # ¿existe lo que el FD asume?
git grep -il "<concepto>" -- core_v2/                # ¿ya existe algo que hace esto?
git grep -n "PlasmaExhaust_D" -- '*.tscn' '*.gd'     # ¿quién referencia lo que vamos a renombrar?
```

Clasificar cada asset y volcarlo como tabla en el FD:

| Estado | Significa | Consecuencia |
|---|---|---|
| `EXISTE` | el path está y hace lo que el FD dice | reutilizar, no recrear |
| `EXISTE-OTRO-ROL` | el path está pero hace otra cosa (nombre engañoso) | tarea de renombre/aclaración |
| `FALTA` | hay que crearlo | tarea de creación (candidata a Jules) |
| `AMBIGUO` | hay dos candidatos o el rol no se deduce | **pregunta para Sebastián** |

Contar también los *referenciadores*: un renombre con 14 referencias en escenas es una tarea
distinta a uno con 2.

## Fase 2 — Viabilidad técnica

Checklist mínima contra los contratos del proyecto. Anotar solo lo que aplica:

- **Determinismo/replay** — ¿el sistema tiene estado? Entonces grupo `replay_sync`,
  `restore_snapshot()`, lógica en `_physics_process`, sin `randf()` en gameplay (`AGENTS.md` §5.3).
- **Gravedad / WorldRotator** — ¿vive en una terraza centrífuga o plate streameada? Leer
  `docs/engineering/Gravity_Physics_Contracts.md` antes de proponer nada.
- **Cámara** — ningún modo nuevo reemplaza el `CameraRig` ni el spring arm (§2.3).
- **GLES2** — el proyecto es GLES2: partículas con `CPUParticles`, nunca el nodo `Particles`.
  Sin `SCREEN_TEXTURE` si el efecto tiene que verse en Android.
- **Culling en reposo** — props con animación por tiempo necesitan `_wants_continuous_step()`
  (FD-224), o se congelan al apagarse el `_physics_process`.
- **Presupuesto de render** — efectos volumétricos y luces realtime son draw calls; si el
  sistema mete N emisores en una sala, decirlo acá con número, no "podría impactar".
- **Escenas compartidas** — listar los `.tscn` de nivel que se van a tocar: son el punto de
  conflicto entre tareas paralelas.

## Fase 3 — Preguntas a Sebastián

Solo las preguntas cuya respuesta **cambia el trabajo**. Máximo ~5, todas juntas, cada una con
opciones concretas y una recomendación. Nunca inventar respuestas de diseño, arte o balance.

Lo que **siempre** se pregunta si no está en el FD: intención de gameplay (qué debe *sentir* el
jugador), qué es canon narrativo, y cualquier `AMBIGUO` de la Fase 1.
Lo que **nunca** se pregunta: decisiones deducibles del código o de `AGENTS.md`.

## Fase 4 — Escribir en el FD

Agregar (o actualizar) estas secciones, respetando el estilo del FD existente:

1. `## Inventario de assets` — la tabla de la Fase 1.
2. `## Riesgos y contratos` — los puntos aplicables de la Fase 2, con su mitigación.
3. `## Decisiones` — cada respuesta de Sebastián con fecha. Es el registro que evita
   re-preguntar lo mismo en la próxima sesión.
4. `## Plan de ejecución` — la tabla de tareas:

```markdown
| # | Tarea | Ejecutor | Archivos | Aceptación | Depende de | Estado |
|---|---|---|---|---|---|---|
| 1 | Fuga de coolant: máquina de estados + snapshot | JULES | core_v2/systems/cryo/** | test de determinismo nuevo pasa | — | pendiente |
| 2 | Válvula y pluma: geometría, material, escala | LOCAL | core_v2/props/pipe/*.tscn | capturas de test_prop.sh aprobadas | — | pendiente |
| 3 | Ajustar densidad de niebla | HUMANO | — | Sebastián valida jugando | 1, 2 | pendiente |
```

5. `## Checkpoints en vivo` — en qué momentos Sebastián prueba y qué se le pide juzgar.

### Criterio de asignación de ejecutor

El eje que decide **no** es el tamaño de la tarea, es **cómo se verifica**: lo que se juzga
leyendo un diff y corriendo un test se puede delegar lejos; lo que se juzga *mirando* tiene que
quedar cerca, donde hay capturas y un humano que opina.

| Ejecutor | Cuándo | Por qué |
|---|---|---|
| **JULES** (asíncrono, devuelve PR) | lógica sustancial y autocontenida que se verifica por diff + tests: máquinas de estado, determinismo y snapshots, sistemas nuevos en su propio directorio, refactors, migraciones, tests. **Tareas grandes, no recados.** | corre sin ocupar la sesión ni el repo local, y admite **hasta 3 sesiones en paralelo** |
| **SONNET/OPUS local** (subagente `executor`, o el lead) | todo lo **visual**: props, materiales, escalas, luz, composición de una sala, calibración de efectos. Y lo que necesita el repo vivo: correr el juego, telemetría, `project.godot`, plugins del editor, escenas de nivel compartidas | el ciclo real es editar → `test_prop.sh` → mirar la captura → ajustar, con Sebastián opinando en medio. Eso no se hace por PR asíncrono |
| **HUMANO** (Sebastián) | feel, balance, legibilidad: todo lo que se juzga jugando | no hay test que lo capture |

**Un prop no está listo cuando compila, está listo cuando se ve bien.** Por eso el trabajo
visual no se delega a un agente asíncrono: volvería un PR correcto y feo, y la iteración
costaría más que hacerlo local.

Patrón que funciona: **Jules construye la lógica, lo local le pone la cara.** Los sistemas
salen deterministas y testeados por un lado, y cuando hay una base coherente se itera lo visual
encima con capturas y feedback en vivo.

Reglas de corte, para que las tareas puedan correr en paralelo:

- Dos tareas nunca tocan el mismo archivo. Si se solapan, se fusionan o se serializan con `Depende de`.
- Hasta 3 tareas de Jules a la vez: elegir tres con archivos disjuntos y sin dependencias entre sí.
- Ninguna tarea de Jules toca escenas de nivel compartidas (`scenes/levels/**`, `core_v2/levels/**`)
  ni `project.godot`: ahí van los conflictos.
- Consumir la API de un archivo no es tocarlo: una tarea puede usar `GasArea3D` mientras otra lo
  edita, siempre que no lo modifique.
- Cada tarea tiene un criterio de aceptación **comprobable** (un test, una captura, un comando).

## Fase 5 — Aprobación

Presentar un resumen corto: qué se verificó, qué cambió del plan original, riesgos abiertos y
la tabla de tareas. **No pasar a `/deliver` ni cambiar `Status:` a `Open` sin el OK explícito
de Sebastián.**

Commit: `docs(FD-0XX): enriquecer plan de ejecución`.
